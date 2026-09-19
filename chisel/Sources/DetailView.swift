import SwiftUI

struct DetailView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if let item = model.selected {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 18) {
                        PreviewBlock(item: item)
                        TitleBlock(item: item)
                        CompareBlock(item: item)
                        SlidersBlock(model: model, item: item)
                        NotesBlock(item: item, error: model.loadError)
                    }
                    .frame(maxWidth: 540)
                    .padding(.horizontal, 26)
                    .padding(.top, 14)
                    .padding(.bottom, 10)
                    .frame(maxWidth: .infinity)
                }
                FooterBlock(model: model, item: item)
            }
        } else {
            EmptyStateView(model: model)
        }
    }
}

// MARK: - Превью

struct PreviewBlock: View {
    var item: MediaItem

    var body: some View {
        ZStack {
            if let image = item.info.thumbnail {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Text("без превью")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textDim)
            }
        }
        .frame(height: 196)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Имя файла и характеристики

struct TitleBlock: View {
    var item: MediaItem

    var body: some View {
        VStack(spacing: 4) {
            Text(item.info.url.lastPathComponent)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.text)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(meta)
                .font(.system(size: 11))
                .foregroundColor(Theme.textDim)
        }
        .frame(maxWidth: .infinity)
    }

    private var meta: String {
        var parts = [item.info.resolutionText,
                     Fmt.duration(item.info.duration),
                     item.info.codec,
                     Fmt.fps(item.info.fps)]
        if !item.info.hasAudio { parts.append("без звука") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Размер «до» и «после»

struct CompareBlock: View {
    var item: MediaItem

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            column(caption: "СЕЙЧАС",
                   size: Fmt.bytes(item.info.fileSize),
                   detail: "\(item.info.width)×\(item.info.height) · \(item.info.codec)",
                   color: Theme.text)
            Text("→")
                .font(.system(size: 16, weight: .light))
                .foregroundColor(Theme.textDim)
            column(caption: "ПОСЛЕ",
                   size: afterSize,
                   detail: "\(item.targetWidth)×\(item.targetHeight) · H.264",
                   color: Theme.gold)
            Spacer(minLength: 0)
            badge
        }
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

    private var isDone: Bool { item.status == .done && item.resultSize > 0 }

    private var afterSize: String {
        isDone ? Fmt.bytes(item.resultSize) : Fmt.bytes(item.estimatedBytes)
    }

    private var ratio: Double {
        guard item.info.fileSize > 0 else { return 1 }
        return isDone ? Double(item.resultSize) / Double(item.info.fileSize) : item.sizeRatio
    }

    private func column(caption: String, size: String, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(caption)
                .font(.system(size: 9, weight: .bold))
                .tracking(1.2)
                .foregroundColor(Theme.textDim)
            Text(size)
                .font(.system(size: 19, weight: .bold).monospacedDigit())
                .foregroundColor(color)
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

// MARK: - Два ползунка

struct SlidersBlock: View {
    @ObservedObject var model: AppModel
    var item: MediaItem

    var body: some View {
        VStack(spacing: 16) {
            SliderRow(title: "РАЗРЕШЕНИЕ",
                      value: "\(item.targetWidth)×\(item.targetHeight)",
                      caption: "\(Int((item.scale * 100).rounded()))% от оригинала",
                      position: model.binding(\.scale, fallback: 1.0),
                      range: 0.1...1.0)
            SliderRow(title: "БИТРЕЙТ",
                      value: Fmt.bitrate(item.videoBitrate),
                      caption: bitrateCaption,
                      position: model.bitrateBinding,
                      range: 0...1)
        }
        .disabled(model.isConverting)
        .opacity(model.isConverting ? 0.5 : 1)
    }

    private var bitrateCaption: String {
        String(format: "%.3f бит на пиксель · при смене разрешения битрейт идёт следом", item.bpp)
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
    var item: MediaItem

    var body: some View {
        VStack(spacing: 10) {
            if item.status == .running {
                VStack(spacing: 5) {
                    ProgressView(value: item.progress)
                        .accentColor(Theme.orange)
                    Text("\(Int(item.progress * 100))% · \(item.info.url.lastPathComponent)")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundColor(Theme.textDim)
                        .lineLimit(1)
                }
            }
            if item.status == .done, let url = item.resultURL {
                HStack(spacing: 8) {
                    Text("Готово · \(Fmt.bytes(item.resultSize))")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.good)
                    Button("Показать в Finder") { model.reveal(url) }
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
        .padding(.horizontal, 26)
        .padding(.vertical, 14)
        .frame(maxWidth: 592)
        .frame(maxWidth: .infinity)
    }

    private var destinationHint: String {
        if let folder = model.outputDirectory {
            return "Результат: \(folder.path)"
        }
        return "Результат ляжет рядом с исходным файлом, в формате MP4 / H.264"
    }
}
