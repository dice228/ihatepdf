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
/// Плотность бит на пиксель (bpp) хранится вместо абсолютного битрейта:
/// тогда при смене разрешения битрейт пересчитывается сам и качество остаётся прежним,
/// а «размер после» меняется от обоих ползунков.
struct MediaItem: Identifiable {
    let id = UUID()
    var info: SourceInfo
    var scale: Double = 1.0
    var bpp: Double = 0.08
    var audio: AudioMode = .k128

    var status: ItemStatus = .ready
    var progress: Double = 0
    var resultURL: URL?
    var resultSize: Int64 = 0
    var error: String?

    static let bppMin = 0.004
    static let bppMax = 1.0

    init(info: SourceInfo) {
        self.info = info
        self.bpp = MediaItem.initialBpp(info)
        self.audio = info.hasAudio ? .k128 : .off
    }

    /// Стартуем от плотности самого файла — «как есть», но уже в H.264.
    private static func initialBpp(_ info: SourceInfo) -> Double {
        let pixels = Double(info.width * info.height) * max(1, info.fps)
        guard pixels > 0, info.videoBitrate > 100_000 else { return 0.08 }
        return min(0.20, max(0.02, info.videoBitrate / pixels))
    }

    // MARK: - Производные величины

    var targetWidth: Int {
        Estimator.targetSize(sourceWidth: info.width, sourceHeight: info.height, scale: scale).w
    }

    var targetHeight: Int {
        Estimator.targetSize(sourceWidth: info.width, sourceHeight: info.height, scale: scale).h
    }

    var videoBitrate: Double {
        let raw = bpp * Double(targetWidth) * Double(targetHeight) * max(1, min(info.fps, 120))
        return min(max(raw, 60_000), 120_000_000)
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
        let bitrate = minBitrate * pow(maxBitrate / minBitrate, clamped)
        let pixels = Double(targetWidth * targetHeight) * max(1, min(info.fps, 120))
        guard pixels > 0 else { return }
        bpp = min(MediaItem.bppMax, max(MediaItem.bppMin, bitrate / pixels))
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
