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

    /// Сколько битрейта обычно хватает выбранному кадру — подсказка, а не ограничение.
    var recommendedBitrate: Double {
        0.08 * Double(targetWidth) * Double(targetHeight) * max(1, min(info.fps, 120))
    }

    var audioBitrate: Double {
        guard info.hasAudio, audio != .off else { return 0 }
        return Double(audio.rawValue)
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
                                 frames: info.duration * info.fps)
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
            fps: info.fps,
            limitFps: false,
            includeAudio: info.hasAudio && audio != .off,
            audioBitrate: max(32_000, audio.rawValue),
            audioChannels: info.audioChannels,
            audioSampleRate: info.audioSampleRate,
            duration: info.duration)
    }
}
