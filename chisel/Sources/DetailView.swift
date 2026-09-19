import SwiftUI

struct DetailView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if let item = model.displayItem {
            VStack(spacing: 13) {
                HeaderBlock(model: model, item: item)
                CompareBlock(model: model, item: item)
                FitRow(model: model, item: item)
                ShareBlock(model: model)
                SlidersBlock(model: model, item: item)
                OptionsBlock(model: model, item: item)
                NotesBlock(item: item, error: model.loadError)
                FooterBlock(model: model)
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)
            .padding(.bottom, 14)
        } else {
            EmptyStateView(model: model)
        }
    }
}

// MARK: - Шапка: кадр слева, название и описание справа

struct HeaderBlock: View {
    @ObservedObject var model: AppModel
    var item: MediaItem

    private let maxThumbWidth: CGFloat = 208
    private let maxThumbHeight: CGFloat = 126

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            thumb
            VStack(alignment: .leading, spacing: 5) {
                Text(name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.text)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: true)
                Text(meta)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Кадр показываем в его собственных пропорциях — без чёрных полей по бокам.
    private var aspect: CGFloat {
        let w = CGFloat(item.info.width), h = CGFloat(item.info.height)
        guard w > 0, h > 0 else { return 16.0 / 9.0 }
        return w / h
    }

    private var thumbSize: CGSize {
        if aspect >= maxThumbWidth / maxThumbHeight {
            return CGSize(width: maxThumbWidth, height: (maxThumbWidth / aspect).rounded())
        }
        return CGSize(width: (maxThumbHeight * aspect).rounded(), height: maxThumbHeight)
    }

    private var thumb: some View {
        Group {
            if let image = item.info.thumbnail {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(Theme.panel)
            }
        }
        .frame(width: thumbSize.width, height: thumbSize.height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var name: String {
        let base = item.info.url.lastPathComponent
        let rest = model.items.count - 1
        guard model.shareSettings, rest > 0 else { return base }
        return "\(base) и ещё \(Fmt.files(rest))"
    }

    private var meta: String {
        var parts = [item.info.resolutionText,
                     Fmt.duration(item.info.duration),
                     item.info.codec,
                     Fmt.fps(item.info.fps)]
        if item.info.isHDR { parts.append("HDR") }
        if !item.info.hasAudio { parts.append("без звука") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Размер «до» и «после»

struct CompareBlock: View {
    @ObservedObject var model: AppModel
    var item: MediaItem

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            column(caption: "СЕЙЧАС", size: Fmt.bytes(beforeBytes),
                   detail: beforeDetail, color: Theme.text, showBadge: false)
            Text("→")
                .font(.system(size: 16, weight: .light))
                .foregroundColor(Theme.textDim)
            column(caption: "ПОСЛЕ", size: Fmt.bytes(afterBytes),
                   detail: afterDetail, color: Theme.gold, showBadge: true)
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.stroke.opacity(0.6), lineWidth: 1)
                )
        )
    }

    /// Когда настройки общие и файлов несколько, цифры показываем по всей очереди.
    private var batch: Bool { model.shareSettings && model.items.count > 1 }

    private var itemDone: Bool { item.status == .done && item.resultSize > 0 }

    private var beforeBytes: Int64 { batch ? model.totalSourceBytes : item.info.fileSize }

    private var afterBytes: Int64 {
        if batch { return model.allDone ? model.totalResultBytes : model.totalEstimatedBytes }
        return itemDone ? item.resultSize : item.estimatedBytes
    }

    private var ratio: Double {
        if batch { return model.totalRatio }
        guard item.info.fileSize > 0 else { return 1 }
        return itemDone ? Double(item.resultSize) / Double(item.info.fileSize) : item.sizeRatio
    }

    private var beforeDetail: String {
        batch ? Fmt.files(model.items.count)
              : "\(item.info.width)×\(item.info.height) · \(item.info.codec)"
    }

    private var afterDetail: String {
        batch ? "H.264 · \(Int((item.scale * 100).rounded()))% кадра"
              : "\(item.targetWidth)×\(item.targetHeight) · H.264"
    }

    private func column(caption: String, size: String, detail: String,
                        color: Color, showBadge: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(caption)
                .font(.system(size: 9, weight: .bold))
                .tracking(1.2)
                .foregroundColor(Theme.textDim)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(size)
                    .font(.system(size: 19, weight: .bold).monospacedDigit())
                    .foregroundColor(color)
                if showBadge { badge }
            }
            Text(detail)
                .font(.system(size: 10))
                .foregroundColor(Theme.textDim)
        }
    }

    private var badge: some View {
        Text(Fmt.signedPercent(ratio))
            .font(.system(size: 12, weight: .bold).monospacedDigit())
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill((ratio <= 1 ? Theme.good : Theme.warn).opacity(0.16))
            )
            .foregroundColor(ratio <= 1 ? Theme.good : Theme.warn)
    }
}

// MARK: - Общие параметры на всю очередь

struct ShareBlock: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if model.items.count > 1 {
            HStack(spacing: 8) {
                Toggle("Параметры на все видео", isOn: model.shareBinding)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.text)
                Spacer(minLength: 0)
                Text(model.shareSettings ? "список только показывает файлы"
                                         : "выберите файл в списке слева")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textDim)
            }
            .disabled(model.isConverting)
            .opacity(model.isConverting ? 0.5 : 1)
        }
    }
}

// MARK: - Ползунки

struct SlidersBlock: View {
    @ObservedObject var model: AppModel
    var item: MediaItem

    var body: some View {
        VStack(spacing: 13) {
            SliderRow(title: "РАЗРЕШЕНИЕ",
                      value: "\(item.targetWidth)×\(item.targetHeight)",
                      caption: resolutionCaption,
                      position: model.binding(\.scale, fallback: 1.0),
                      range: 0.1...1.0)
            SliderRow(title: "БИТРЕЙТ ВИДЕО",
                      value: Fmt.bitrate(item.videoBitrate),
                      caption: bitrateCaption,
                      position: model.bitrateBinding,
                      range: 0...1)
            SliderRow(title: "ЗВУК",
                      value: audioValue,
                      caption: audioCaption,
                      position: model.audioBinding,
                      range: 0...Double(AudioMode.allCases.count - 1),
                      step: 1)
                .disabled(!item.info.hasAudio)
                .opacity(item.info.hasAudio ? 1 : 0.4)
            HStack(spacing: 10) {
                Toggle("Моно", isOn: model.monoBinding)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.text)
                Text(channelsHint)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textDim.opacity(0.8))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .disabled(!item.info.hasAudio || item.audio == .off)
            .opacity(item.info.hasAudio && item.audio != .off ? 1 : 0.4)
        }
        .disabled(model.isConverting)
        .opacity(model.isConverting ? 0.5 : 1)
    }

    private var batch: Bool { model.shareSettings && model.items.count > 1 }

    private var resolutionCaption: String {
        let percent = Int((item.scale * 100).rounded())
        return batch ? "\(percent)% от кадра каждого файла" : "\(percent)% от оригинала"
    }

    /// Разрешение и битрейт больше не связаны, поэтому вместо пересчёта — подсказка,
    /// сколько битрейта обычно хватает выбранному кадру.
    private var bitrateCaption: String {
        "для \(item.targetWidth)×\(item.targetHeight) обычно хватает \(Fmt.bitrate(item.recommendedBitrate))"
    }

    private var audioValue: String {
        guard item.info.hasAudio else { return "нет дорожки" }
        return item.audio == .off ? "выключен" : "AAC \(item.audio.rawValue / 1_000) кбит/с"
    }

    private var channelsHint: String {
        guard item.info.hasAudio, item.audio != .off else { return "" }
        let target = item.audioMono ? "моно" : (item.info.audioChannels > 1 ? "стерео" : "моно")
        let base = "\(item.sourceChannelsName) → \(target)"
        return item.audioMono ? base + " · на моно хватает вдвое меньшего битрейта" : base
    }

    private var audioCaption: String {
        guard item.info.hasAudio else { return "в файле нет звука" }
        if item.audio == .off { return "дорожка будет выброшена целиком" }
        return "добавит ≈ \(Fmt.bytes(item.audioBytes)) · речь разборчива и на 64k"
    }
}

// MARK: - Уложиться в лимит

struct FitRow: View {
    @ObservedObject var model: AppModel
    var item: MediaItem

    private let presets: [Double] = [10, 25, 50, 100]

    var body: some View {
        HStack(spacing: 6) {
            Text("УЛОЖИТЬ В")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Theme.textDim)
                .frame(width: 74, alignment: .leading)
            ForEach(presets, id: \.self) { megabytes in
                Pill(title: "\(Int(megabytes)) МБ", active: matches(megabytes)) {
                    model.fit(megabytes: megabytes)
                }
            }
            Spacer(minLength: 0)
        }
        .disabled(model.isConverting)
        .opacity(model.isConverting ? 0.5 : 1)
    }

    /// Кнопка подсвечена, если текущая оценка уже попадает в этот лимит.
    private func matches(_ megabytes: Double) -> Bool {
        let target = megabytes * 1_000_000
        return abs(Double(item.estimatedBytes) - target) < target * 0.03
    }
}

// MARK: - Кадры, кодек, HDR

struct OptionsBlock: View {
    @ObservedObject var model: AppModel
    var item: MediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            row(title: "КАДРЫ") {
                ForEach(fpsOptions) { mode in
                    Pill(title: mode.title, active: item.fpsMode == mode) {
                        model.setFps(mode)
                    }
                }
            }
            row(title: "КОДЕК") {
                ForEach(OutputCodec.allCases) { codec in
                    Pill(title: codec.title, active: item.codec == codec) {
                        model.setCodec(codec)
                    }
                }
            }
            if item.info.isHDR {
                row(title: "HDR") {
                    Pill(title: "в SDR", active: !item.keepHDR) { model.setKeepHDR(false) }
                    Pill(title: "сохранить", active: item.keepHDR) { model.setKeepHDR(true) }
                }
            }
            if item.info.subtitleTracks > 0 {
                row(title: "СУБТИТРЫ") {
                    Pill(title: "убрать", active: !item.burnSubtitles) {
                        model.setBurnSubtitles(false)
                    }
                    Pill(title: "вшить в кадр", active: item.burnSubtitles) {
                        model.setBurnSubtitles(true)
                    }
                    if !FFmpegEngine.isAvailable {
                        Text("нужен ffmpeg")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.warn)
                    }
                }
            }
            Text(caption)
                .font(.system(size: 10))
                .foregroundColor(Theme.textDim.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .disabled(model.isConverting)
        .opacity(model.isConverting ? 0.5 : 1)
    }

    /// Показываем только те частоты, которые ниже исходной: поднимать её незачем.
    private var fpsOptions: [FpsMode] {
        FpsMode.allCases.filter { $0 == .source || Double($0.rawValue) < item.info.fps - 0.5 }
    }

    private func row<Content: View>(title: String,
                                    @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Theme.textDim)
                .frame(width: 74, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    private var caption: String {
        if item.burnSubtitles {
            return FFmpegEngine.isAvailable
                ? "Субтитры рисуются прямо в кадр — иначе они не переживут отправку"
                : "Вшивание требует ffmpeg: brew install ffmpeg"
        }
        if item.codec == .hevc {
            return item.keepHDR
                ? "HDR сохраняется в 10-битном HEVC — такой файл откроется не везде"
                : "HEVC весит меньше при той же картинке, но Windows и старые плееры берут его не всегда"
        }
        if item.info.isHDR {
            return "HDR приводится к SDR — иначе у получателя картинка будет блёклой"
        }
        return "H.264 открывается везде — самый надёжный вариант для отправки"
    }
}

// MARK: - Предупреждения

struct NotesBlock: View {
    var item: MediaItem
    var error: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if item.bitrateExceedsSource {
                note("Битрейт выше исходного — файл вырастет, а качество не улучшится.", Theme.warn)
            }
            if !item.info.nativeReadable {
                note("Контейнер обрабатывается через ffmpeg.", Theme.textDim)
            }
            if item.info.subtitleTracks > 0 && !item.burnSubtitles {
                note("Субтитров внутри: \(item.info.subtitleTracks). Отдельной дорожкой в MP4 они не уедут — мессенджеры их всё равно не показывают.", Theme.textDim)
            }
            if item.info.audioTracks > 1 {
                note("Звуковых дорожек: \(item.info.audioTracks). В файл попадёт первая.", Theme.textDim)
            }
            if let itemError = item.error {
                note(itemError, Theme.warn)
            }
            if !error.isEmpty {
                note(error, Theme.warn)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func note(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Кнопки и прогресс

struct FooterBlock: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 10) {
            if let running = model.items.first(where: { $0.status == .running }) {
                VStack(spacing: 5) {
                    ProgressView(value: running.progress)
                        .accentColor(Theme.orange)
                    Text(progressText(running))
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundColor(Theme.textDim)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } else if model.doneCount > 0 {
                HStack(spacing: 8) {
                    Text(doneText)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.good)
                    Button("Показать в Finder") { model.revealResults() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.sand)
                    Spacer()
                }
            }
            HStack(spacing: 10) {
                PrimaryButton(title: model.isConverting ? "Конвертация…" : model.convertTitle,
                              enabled: model.canConvert) {
                    model.convertAll()
                }
                GhostButton(title: model.isConverting ? "Стоп" : "Отмена") {
                    model.cancelOrRemove()
                }
            }
            Text(destinationHint)
                .font(.system(size: 10))
                .foregroundColor(Theme.textDim.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.top, 2)
    }

    private func progressText(_ running: MediaItem) -> String {
        let percent = Int(running.progress * 100)
        guard model.items.count > 1 else {
            return "\(percent)% · \(running.info.url.lastPathComponent)"
        }
        let index = (model.items.firstIndex { $0.id == running.id } ?? 0) + 1
        return "\(percent)% · \(index) из \(model.items.count) · \(running.info.url.lastPathComponent)"
    }

    private var doneText: String {
        guard model.items.count > 1 else {
            return "Готово · \(Fmt.bytes(model.totalResultBytes))"
        }
        return "Готово \(model.doneCount) из \(model.items.count) · всего \(Fmt.bytes(model.totalResultBytes))"
    }

    private var destinationHint: String {
        if let folder = model.outputDirectory {
            return "Результат: \(folder.path)"
        }
        return "Результат ляжет рядом с исходным файлом, в формате MP4 / H.264"
    }
}
