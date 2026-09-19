import AppKit
import Foundation

enum ItemStatus { case ready, running, done, failed }

/// Битрейт звука отдельной настройкой: на длинном ролике с низким битрейтом видео
/// дорожка AAC занимает заметную долю файла, и на ней тоже можно выиграть вес.
enum AudioMode: Int, CaseIterable, Identifiable {
    case off = 0, k64 = 64_000, k96 = 96_000, k128 = 128_000, k192 = 192_000, k256 = 256_000
    var id: Int { rawValue }
    var title: String { self == .off ? "выкл" : "\(rawValue / 1_000)k" }
}

enum FpsMode: Int, CaseIterable, Identifiable {
    case source = 0, f60 = 60, f30 = 30, f24 = 24
    var id: Int { rawValue }
    var title: String { self == .source ? "как есть" : "\(rawValue)" }
    var limits: Bool { self != .source }
    func value(source: Double) -> Double {
        self == .source ? source : min(source, Double(rawValue))
    }
}

/// Один файл в очереди со своими настройками.
/// Ползунки независимы: разрешение отвечает за чёткость кадра, битрейт — за вес файла.
/// Разрешение на размер не влияет, поэтому рядом с битрейтом подсказано,
/// сколько обычно нужно выбранному кадру.
struct MediaItem: Identifiable {
    let id = UUID()
    var info: SourceInfo
    var scale: Double = 1.0
    var videoBitrate: Double = 5_000_000
    var audio: AudioMode = .k128
    /// Свести звук в один канал. Многоканальный источник (5.1) иначе сводится в стерео.
    var audioMono: Bool = false
    var fpsMode: FpsMode = .source
    var codec: OutputCodec = .h264
    /// Сохранять HDR можно только в HEVC: H.264 здесь всегда 8 бит.
    var keepHDR: Bool = false
    /// Субтитры в MP4 не переносятся — их можно только вшить в картинку, и только через ffmpeg.
    var burnSubtitles: Bool = false

    var status: ItemStatus = .ready
    var progress: Double = 0
    var resultURL: URL?
    var resultSize: Int64 = 0
    var error: String?

    init(info: SourceInfo) {
        self.info = info
        self.videoBitrate = MediaItem.initialBitrate(info)
        self.audio = info.hasAudio ? .k128 : .off
    }

    /// Стартуем от битрейта самого файла, но не выше разумного потолка для H.264:
    /// для ProRes и другого тяжёлого исходника это сразу даёт заметное сжатие.
    private static func initialBitrate(_ info: SourceInfo) -> Double {
        let ceiling = 0.20 * Double(info.width * info.height) * max(1, min(info.fps, 120))
        let source = info.videoBitrate > 100_000 ? info.videoBitrate : ceiling
        return min(max(min(source, ceiling), 100_000), 80_000_000)
    }

    // MARK: - Производные величины

    var targetWidth: Int {
        Estimator.targetSize(sourceWidth: info.width, sourceHeight: info.height, scale: scale).w
    }

    var targetHeight: Int {
        Estimator.targetSize(sourceWidth: info.width, sourceHeight: info.height, scale: scale).h
    }

    var targetFps: Double { fpsMode.value(source: info.fps) }

    /// Вшивание доступно, только если есть что вшивать и чем.
    var burnsSubtitles: Bool {
        burnSubtitles && info.subtitleTracks > 0 && FFmpegEngine.isAvailable
    }

    /// Сколько битрейта обычно хватает выбранному кадру — подсказка, а не ограничение.
    var recommendedBitrate: Double {
        0.08 * Double(targetWidth) * Double(targetHeight)
            * max(1, min(targetFps, 120)) * codec.bitrateFactor
    }

    /// Битрейт видео, при котором файл уложится в заданный размер.
    func bitrateToFit(bytes: Int64, duration: Double) -> Double {
        let seconds = max(0.5, duration)
        let payload = Double(bytes) * 0.985            // запас на контейнер и разброс кодировщика
        let total = payload * 8.0 / seconds
        return min(max(total - audioBitrate, 60_000), 120_000_000)
    }

    var audioBitrate: Double {
        guard info.hasAudio, audio != .off else { return 0 }
        return Double(audio.rawValue)
    }

    /// Как называется исходная раскладка каналов — чтобы было видно, что это 5.1.
    var sourceChannelsName: String {
        switch info.audioChannels {
        case 1: return "моно"
        case 2: return "стерео"
        case 6: return "5.1"
        case 8: return "7.1"
        default: return "\(info.audioChannels) кан."
        }
    }

    /// Сколько весит звуковая дорожка — видно, есть ли смысл её ужимать.
    var audioBytes: Int64 {
        guard info.duration > 0 else { return 0 }
        return Int64((audioBitrate * info.duration / 8.0).rounded())
    }

    var estimatedBytes: Int64 {
        Estimator.estimatedBytes(videoBps: videoBitrate,
                                 audioBps: audioBitrate,
                                 seconds: info.duration,
                                 frames: info.duration * targetFps)
    }

    var sizeRatio: Double {
        guard info.fileSize > 0 else { return 1 }
        return Double(estimatedBytes) / Double(info.fileSize)
    }

    var bitrateExceedsSource: Bool {
        guard info.videoBitrate > 100_000 else { return false }
        return videoBitrate > info.videoBitrate * 1.05
    }

    // MARK: - Ползунок битрейта (логарифмический)

    var minBitrate: Double { 100_000 }

    var maxBitrate: Double {
        min(80_000_000, max(12_000_000, info.videoBitrate * 1.4))
    }

    var bitratePosition: Double {
        let v = min(max(videoBitrate, minBitrate), maxBitrate)
        return log(v / minBitrate) / log(maxBitrate / minBitrate)
    }

    mutating func setBitratePosition(_ t: Double) {
        let clamped = min(max(t, 0), 1)
        videoBitrate = minBitrate * pow(maxBitrate / minBitrate, clamped)
    }

    func job(output: URL) -> Job {
        Job(input: info.url,
            output: output,
            width: targetWidth,
            height: targetHeight,
            videoBitrate: Int(videoBitrate.rounded()),
            fps: targetFps,
            limitFps: fpsMode.limits,
            codec: codec,
            sourceIsHDR: info.isHDR,
            hdrIsPQ: info.hdrIsPQ,
            keepHDR: keepHDR && info.isHDR && codec == .hevc,
            burnSubtitles: burnsSubtitles,
            includeAudio: info.hasAudio && audio != .off,
            audioBitrate: max(32_000, audio.rawValue),
            audioChannels: audioMono ? 1 : min(2, max(1, info.audioChannels)),
            audioSampleRate: info.audioSampleRate,
            duration: info.duration)
    }
}
