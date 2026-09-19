import Foundation

enum ChiselError: Error, LocalizedError {
    case unreadable
    case unsupportedNeedsFFmpeg
    case noVideoTrack
    case readerFailed(String)
    case writerFailed(String)
    case ffmpegMissing
    case ffmpegFailed(String)
    case cancelled

    var isCancelled: Bool {
        if case .cancelled = self { return true }
        return false
    }

    var errorDescription: String? {
        switch self {
        case .unreadable:
            return "Не получилось прочитать файл — похоже, это не видео или оно повреждено."
        case .unsupportedNeedsFFmpeg:
            return "macOS не умеет открывать этот контейнер сам. Установите ffmpeg (brew install ffmpeg) — Chisel подхватит его автоматически."
        case .noVideoTrack:
            return "В файле нет видеодорожки."
        case .readerFailed(let m):
            return "Ошибка чтения: \(m)"
        case .writerFailed(let m):
            return "Ошибка записи: \(m)"
        case .ffmpegMissing:
            return "ffmpeg не найден. Установите его командой brew install ffmpeg."
        case .ffmpegFailed(let m):
            return "ffmpeg завершился с ошибкой: \(m)"
        case .cancelled:
            return "Отменено."
        }
    }
}

enum OutputCodec: Int, CaseIterable, Identifiable {
    case h264 = 0, hevc = 1
    var id: Int { rawValue }
    var title: String { self == .h264 ? "H.264" : "HEVC" }
    /// HEVC при той же картинке весит примерно на 40% меньше.
    var bitrateFactor: Double { self == .h264 ? 1.0 : 0.6 }
}

/// Готовое задание на кодирование — ровно то, что уходит в движок.
struct Job {
    var input: URL
    var output: URL
    var width: Int
    var height: Int
    var videoBitrate: Int          // бит/с
    var fps: Double                // целевая частота кадров
    var limitFps: Bool             // ограничивать ли частоту кадров
    var codec: OutputCodec
    var sourceIsHDR: Bool
    var hdrIsPQ: Bool
    var keepHDR: Bool              // иначе HDR приводится к SDR
    var burnSubtitles: Bool        // вшить субтитры в картинку (только через ffmpeg)
    var includeAudio: Bool
    var audioBitrate: Int          // бит/с
    var audioChannels: Int
    var audioSampleRate: Double
    var duration: Double
}

/// Не даём перезаписать исходник и чужие файлы: подбираем свободное имя.
enum OutputNamer {
    static func suggest(for input: URL, in directory: URL? = nil) -> URL {
        let dir = directory ?? input.deletingLastPathComponent()
        let base = input.deletingPathExtension().lastPathComponent
        var candidate = dir.appendingPathComponent(base + ".mp4")
        if candidate.path.caseInsensitiveCompare(input.path) != .orderedSame,
           !FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        candidate = dir.appendingPathComponent(base + "-chisel.mp4")
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path)
                || candidate.path.caseInsensitiveCompare(input.path) == .orderedSame {
            candidate = dir.appendingPathComponent("\(base)-chisel-\(n).mp4")
            n += 1
            if n > 999 { break }
        }
        return candidate
    }
}
