import AVFoundation
import AppKit

struct SourceInfo {
    var url: URL
    var fileSize: Int64 = 0
    var duration: Double = 0
    var width: Int = 0
    var height: Int = 0
    var fps: Double = 30
    var videoBitrate: Double = 0
    var audioBitrate: Double = 0
    var hasAudio: Bool = false
    var audioChannels: Int = 2
    var audioSampleRate: Double = 44_100
    var codec: String = "—"
    var thumbnail: NSImage?
    /// AVFoundation умеет читать этот файл сам (без ffmpeg).
    var nativeReadable: Bool = true

    var frames: Double { max(1, duration * fps) }
    var resolutionText: String { width > 0 ? "\(width)×\(height)" : "—" }
}

enum Probe {

    static func load(_ url: URL, completion: @escaping (Result<SourceInfo, ChiselError>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = loadSync(url)
            DispatchQueue.main.async { completion(result) }
        }
    }

    static func loadSync(_ url: URL) -> Result<SourceInfo, ChiselError> {
        var fileSize: Int64 = 0
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let n = attrs[.size] as? NSNumber {
            fileSize = n.int64Value
        }

        if var info = nativeProbe(url) {
            info.fileSize = fileSize
            info.thumbnail = thumbnail(for: url)
            return .success(info)
        }
        // AVFoundation не открыл контейнер (mkv, webm, экзотика) — пробуем ffprobe.
        if var info = FFmpegEngine.probe(url) {
            info.fileSize = fileSize
            info.nativeReadable = false
            let at = info.duration > 0 ? min(1.0, info.duration * 0.1) : 0
            info.thumbnail = FFmpegEngine.thumbnail(url, at: at)
            return .success(info)
        }
        return .failure(FFmpegEngine.locate() == nil
                        ? .unsupportedNeedsFFmpeg
                        : .unreadable)
    }

    private static func nativeProbe(_ url: URL) -> SourceInfo? {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        guard let v = asset.tracks(withMediaType: .video).first else { return nil }

        var info = SourceInfo(url: url)
        info.duration = CMTimeGetSeconds(asset.duration)
        if !info.duration.isFinite || info.duration <= 0 {
            info.duration = CMTimeGetSeconds(v.timeRange.duration)
        }

        let oriented = v.naturalSize.applying(v.preferredTransform)
        info.width = Estimator.even(Int(abs(oriented.width).rounded()))
        info.height = Estimator.even(Int(abs(oriented.height).rounded()))
        guard info.width > 0, info.height > 0 else { return nil }

        let nominal = Double(v.nominalFrameRate)
        info.fps = nominal > 0.1 ? nominal : 30
        info.videoBitrate = Double(v.estimatedDataRate)
        info.codec = codecName(v)

        if let a = asset.tracks(withMediaType: .audio).first {
            info.hasAudio = true
            info.audioBitrate = Double(a.estimatedDataRate)
            // formatDescriptions объявлен как [Any], но условное приведение (as?)
            // к типу CoreFoundation Swift запрещает — такие типы не проверяются
            // динамически. Поэтому здесь безусловное as!: элементы этого массива
            // всегда являются описаниями формата.
            if let fd = a.formatDescriptions.first {
                let desc = fd as! CMFormatDescription
                if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee {
                    info.audioChannels = max(1, Int(asbd.mChannelsPerFrame))
                    if asbd.mSampleRate > 0 { info.audioSampleRate = asbd.mSampleRate }
                }
            }
        }
        return info
    }

    private static func codecName(_ track: AVAssetTrack) -> String {
        guard let fd = track.formatDescriptions.first else { return "—" }
        let desc = fd as! CMFormatDescription
        let code = CMFormatDescriptionGetMediaSubType(desc)
        let tag = fourCC(code)
        switch tag {
        case "avc1", "avc3": return "H.264"
        case "hvc1", "hev1": return "HEVC"
        case "mp4v": return "MPEG-4"
        case "jpeg", "mjpa", "mjpb": return "MJPEG"
        case "vp09": return "VP9"
        case "av01": return "AV1"
        case "ap4h", "apch", "apcn", "apcs", "apco", "ap4x": return "ProRes"
        case "dvh1", "dvhe": return "Dolby Vision"
        default: return tag
        }
    }

    private static func fourCC(_ code: FourCharCode) -> String {
        let bytes: [UInt8] = [UInt8((code >> 24) & 0xFF), UInt8((code >> 16) & 0xFF),
                              UInt8((code >> 8) & 0xFF), UInt8(code & 0xFF)]
        let s = String(bytes: bytes, encoding: .macOSRoman) ?? "—"
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func thumbnail(for url: URL) -> NSImage? {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 640, height: 640)
        gen.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
        gen.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)
        let dur = CMTimeGetSeconds(asset.duration)
        let at = CMTime(seconds: dur.isFinite && dur > 0 ? min(1.0, dur * 0.1) : 0,
                        preferredTimescale: 600)
        guard let cg = try? gen.copyCGImage(at: at, actualTime: nil) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
