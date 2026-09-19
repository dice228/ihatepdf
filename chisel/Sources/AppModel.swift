import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Колбэки перетаскивания приходят с произвольных очередей — копим ссылки под замком.
private final class URLBox {
    private let lock = NSLock()
    private var storage: [URL] = []
    func append(_ url: URL) { lock.lock(); storage.append(url); lock.unlock() }
    var urls: [URL] { lock.lock(); defer { lock.unlock() }; return storage }
}

final class AppModel: ObservableObject {

    static let shared = AppModel()

    @Published var items: [MediaItem] = []
    @Published var selection: UUID?
    @Published var isConverting: Bool = false
    @Published var isLoading: Bool = false
    @Published var loadError: String = ""
    @Published var isDropTargeted: Bool = false
    /// «Параметры на все видео»: один набор настроек на всю очередь.
    /// Пока он включён, отдельное видео из списка не выбирается — редактируется вся очередь целиком.
    @Published var shareSettings: Bool = true

    var outputDirectory: URL?

    private var engineAV: AVEngine?
    private var engineFF: FFmpegEngine?
    private var pending: [UUID] = []
    private var cancelRequested = false

    // MARK: - Доступ к выбранному файлу

    var selectedIndex: Int? {
        if items.isEmpty { return nil }
        if shareSettings { return 0 }
        guard let id = selection else { return 0 }
        return items.firstIndex { $0.id == id } ?? 0
    }

    var selected: MediaItem? {
        guard let i = selectedIndex, items.indices.contains(i) else { return nil }
        return items[i]
    }

    /// Файл, к которому относится то, что показано в правой части окна.
    var displayItem: MediaItem? { selected }

    /// Пока идёт конвертация, прогресс показываем по текущему файлу очереди.
    var activeItem: MediaItem? {
        items.first { $0.status == .running } ?? selected
    }

    func binding<T>(_ keyPath: WritableKeyPath<MediaItem, T>, fallback: T) -> Binding<T> {
        Binding(
            get: {
                guard let i = self.selectedIndex, self.items.indices.contains(i) else { return fallback }
                return self.items[i][keyPath: keyPath]
            },
            set: { newValue in
                guard let i = self.selectedIndex, self.items.indices.contains(i) else { return }
                if self.shareSettings {
                    for j in self.items.indices { self.items[j][keyPath: keyPath] = newValue }
                } else {
                    self.items[i][keyPath: keyPath] = newValue
                }
            }
        )
    }

    /// Ползунок битрейта ходит по логарифму, поэтому у него отдельная привязка.
    var bitrateBinding: Binding<Double> {
        Binding(
            get: { self.selected?.bitratePosition ?? 0.5 },
            set: { value in
                guard let i = self.selectedIndex, self.items.indices.contains(i) else { return }
                self.items[i].setBitratePosition(value)
                if self.shareSettings {
                    let bitrate = self.items[i].videoBitrate
                    for j in self.items.indices { self.items[j].videoBitrate = bitrate }
                }
            }
        )
    }

    /// Звук тоже ползунком, но со ступенями: значений всего шесть.
    var audioBinding: Binding<Double> {
        Binding(
            get: {
                guard let item = self.selected,
                      let index = AudioMode.allCases.firstIndex(of: item.audio) else { return 3 }
                return Double(index)
            },
            set: { value in
                let modes = AudioMode.allCases
                let index = Int(value.rounded())
                guard modes.indices.contains(index) else { return }
                self.setAudio(modes[index])
            }
        )
    }

    func setAudio(_ mode: AudioMode) {
        guard let i = selectedIndex, items.indices.contains(i) else { return }
        if shareSettings {
            for j in items.indices {
                items[j].audio = items[j].info.hasAudio ? mode : .off
            }
        } else if items[i].info.hasAudio {
            items[i].audio = mode
        }
    }

    /// Переключатель «Параметры на все видео».
    /// При включении настройки текущего файла разъезжаются по всей очереди,
    /// иначе список показывал бы одно, а кодировались бы разные значения.
    var shareBinding: Binding<Bool> {
        Binding(
            get: { self.shareSettings },
            set: { isOn in
                let sourceIndex = self.selectedIndex
                self.shareSettings = isOn
                guard isOn, let i = sourceIndex, self.items.indices.contains(i) else { return }
                let source = self.items[i]
                for j in self.items.indices {
                    self.items[j].scale = source.scale
                    self.items[j].videoBitrate = source.videoBitrate
                    self.items[j].audio = self.items[j].info.hasAudio ? source.audio : .off
                }
                self.selection = self.items.first?.id
            }
        )
    }

    // MARK: - Итоги по всей очереди

    var totalSourceBytes: Int64 { items.reduce(0) { $0 + $1.info.fileSize } }

    var totalEstimatedBytes: Int64 { items.reduce(0) { $0 + $1.estimatedBytes } }

    var totalResultBytes: Int64 { items.reduce(0) { $0 + $1.resultSize } }

    var allDone: Bool { !items.isEmpty && items.allSatisfy { $0.status == .done } }

    var doneCount: Int { items.filter { $0.status == .done }.count }

    var totalRatio: Double {
        guard totalSourceBytes > 0 else { return 1 }
        let after = allDone ? totalResultBytes : totalEstimatedBytes
        return Double(after) / Double(totalSourceBytes)
    }

    // MARK: - Добавление файлов

    func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audiovisualContent, .movie]
        panel.prompt = "Открыть"
        panel.message = "Выберите видео"
        if panel.runModal() == .OK { add(panel.urls) }
    }

    func add(_ urls: [URL]) {
        let fresh = urls.filter { url in
            !items.contains { $0.info.url.path == url.path }
        }
        guard !fresh.isEmpty else { return }
        loadError = ""
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            for url in fresh {
                let result = Probe.loadSync(url)
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    switch result {
                    case .success(let info):
                        var item = MediaItem(info: info)
                        // При общих параметрах новый файл сразу перенимает их,
                        // иначе в окне было бы одно, а кодировалось бы другое.
                        if self.shareSettings, let first = self.items.first {
                            item.scale = first.scale
                            item.videoBitrate = first.videoBitrate
                            item.audio = info.hasAudio ? first.audio : .off
                        }
                        self.items.append(item)
                        if self.selection == nil { self.selection = item.id }
                    case .failure(let error):
                        self.loadError = "\(url.lastPathComponent): \(error.localizedDescription)"
                    }
                }
            }
            DispatchQueue.main.async { self?.isLoading = false }
        }
    }

    /// Перетаскивание: принимаем любое количество файлов.
    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let type = UTType.fileURL.identifier
        let box = URLBox()
        let group = DispatchGroup()
        for provider in providers where provider.hasItemConformingToTypeIdentifier(type) {
            group.enter()
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    box.append(url)
                } else if let url = item as? URL {
                    box.append(url)
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            self?.add(box.urls)
        }
        return true
    }

    /// Вставка из буфера обмена (⌘V): Finder кладёт туда file-URL.
    func pasteFromClipboard() {
        let board = NSPasteboard.general
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = board.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
           !urls.isEmpty {
            add(urls)
        } else {
            loadError = "В буфере обмена нет файла."
        }
    }

    func remove(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items.remove(at: index)
        pending.removeAll { $0 == id }
        if selection == id {
            selection = items.indices.contains(index) ? items[index].id : items.last?.id
        }
    }

    func clearAll() {
        items.removeAll()
        selection = nil
        loadError = ""
    }

    // MARK: - Конвертация

    var canConvert: Bool { !items.isEmpty && !isConverting }

    var convertTitle: String {
        items.count > 1 ? "Конвертировать все (\(items.count))" : "Конвертировать"
    }

    func convertAll() {
        guard canConvert else { return }
        loadError = ""
        cancelRequested = false
        for index in items.indices {
            items[index].status = .ready
            items[index].progress = 0
            items[index].error = nil
            items[index].resultURL = nil
            items[index].resultSize = 0
        }
        pending = items.map { $0.id }
        isConverting = true
        runNext()
    }

    private func runNext() {
        guard !cancelRequested, !pending.isEmpty else {
            isConverting = false
            pending.removeAll()
            return
        }
        let id = pending.removeFirst()
        guard let index = items.firstIndex(where: { $0.id == id }) else { runNext(); return }

        let item = items[index]
        let output = OutputNamer.suggest(for: item.info.url, in: outputDirectory)
        let job = item.job(output: output)
        items[index].status = .running
        items[index].progress = 0
        if selection == nil { selection = id }

        let onProgress: (Double) -> Void = { [weak self] value in
            guard let self = self,
                  let i = self.items.firstIndex(where: { $0.id == id }) else { return }
            self.items[i].progress = value
        }
        let onDone: (Result<Void, Error>) -> Void = { [weak self] result in
            guard let self = self else { return }
            if let i = self.items.firstIndex(where: { $0.id == id }) {
                switch result {
                case .success:
                    var size: Int64 = 0
                    if let attrs = try? FileManager.default.attributesOfItem(atPath: output.path),
                       let n = attrs[.size] as? NSNumber { size = n.int64Value }
                    self.items[i].status = .done
                    self.items[i].progress = 1
                    self.items[i].resultURL = output
                    self.items[i].resultSize = size
                case .failure(let error):
                    if (error as? ChiselError)?.isCancelled == true {
                        self.items[i].status = .ready
                        self.items[i].progress = 0
                    } else {
                        self.items[i].status = .failed
                        self.items[i].error = error.localizedDescription
                    }
                }
            }
            self.engineAV = nil
            self.engineFF = nil
            self.runNext()
        }

        if item.info.nativeReadable {
            let engine = AVEngine()
            engineAV = engine
            engine.run(job: job, progress: onProgress, completion: onDone)
        } else {
            let engine = FFmpegEngine()
            engineFF = engine
            engine.run(job: job, progress: onProgress, completion: onDone)
        }
    }

    /// Во время работы — стоп. В покое — убрать файл из списка;
    /// при общих параметрах кнопка относится ко всей очереди, как и сами параметры.
    func cancelOrRemove() {
        if isConverting {
            cancelRequested = true
            pending.removeAll()
            engineAV?.cancel()
            engineFF?.cancel()
        } else if shareSettings && items.count > 1 {
            clearAll()
        } else if let i = selectedIndex, items.indices.contains(i) {
            remove(items[i].id)
        }
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func revealResults() {
        let urls = items.compactMap { $0.resultURL }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.prompt = "Выбрать"
        panel.message = "Куда сохранять готовые файлы"
        if panel.runModal() == .OK { outputDirectory = panel.url }
    }
}
