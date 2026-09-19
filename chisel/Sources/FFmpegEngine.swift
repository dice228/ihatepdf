import AppKit
import Foundation

/// Запасной движок для контейнеров, которые macOS не открывает сама (mkv, webm и т. п.).
/// Используется, только если ffmpeg уже стоит в системе; без него приложение работает как обычно.
final class FFmpegEngine {

    private var process: Process?
    private var cancelled = false

    // MARK: - Поиск бинарника

    private static let candidates = [
        "/opt/homebrew/bin/ffmpeg",     // Apple Silicon, Homebrew
        "/usr/local/bin/ffmpeg",        // Intel, Homebrew
        "/opt/local/bin/ffmpeg",        // MacPorts
        "/usr/bin/ffmpeg"
    ]

    static func locate() -> URL? {
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        // На случай нестандартного префикса — спрашиваем у login-шелла.
        if let found = shell("command -v ffmpeg"), !found.isEmpty,
           FileManager.default.isExecutableFile(atPath: found) {
            return URL(fileURLWithPath: found)
        }
        return nil
    }

    static func locateProbe() -> URL? {
        guard let ffmpeg = locate() else { return nil }
        let sibling = ffmpeg.deletingLastPathComponent().appendingPathComponent("ffprobe")
        if FileManager.default.isExecutableFile(atPath: sibling.path) { return sibling }
        if let found = shell("command -v ffprobe"), !found.isEmpty,
           FileManager.default.isExecutableFile(atPath: found) {
            return URL(fileURLWithPath: found)
        }
        return nil
    }

    private static func shell(_ command: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", command]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n").first
    }

    // MARK: - Разбор файла через ffprobe

    static func probe(_ url: URL) -> SourceInfo? {
        guard let ffprobe = locateProbe() else { return nil }
        let p = Process()
        p.executableURL = ffprobe
        p.arguments = ["-v", "quiet", "-print_format", "json",
                       "-show_format", "-show_streams", url.path]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()

        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let streams = root["streams"] as? [[String: Any]] else { return nil }
        let format = root["format"] as? [String: Any] ?? [:]

        guard let video = streams.first(where: { ($0["codec_type"] as? String) == "video" })
        else { return nil }

        var info = SourceInfo(url: url)
        info.duration = number(format["duration"]) ?? number(video["duration"]) ?? 0
        var w = Int(number(video["width"]) ?? 0)
        var h = Int(number(video["height"]) ?? 0)
        if isRotatedQuarterTurn(video) { swap(&w, &h) }
        info.width = Estimator.even(w)
        info.height = Estimator.even(h)
        guard info.width > 0, info.height > 0 else { return nil }

        info.fps = fraction(video["avg_frame_rate"]) ?? fraction(video["r_frame_rate"]) ?? 30
        if !(info.fps > 0.1) { info.fps = 30 }
        info.codec = (video["codec_name"] as? String)?.uppercased() ?? "—"
        let transfer = (video["color_transfer"] as? String) ?? ""
        info.hdrIsPQ = transfer == "smpte2084"
        info.isHDR = info.hdrIsPQ || transfer == "arib-std-b67"
        info.videoBitrate = number(video["bit_rate"]) ?? 0

        if let audio = streams.first(where: { ($0["codec_type"] as? String) == "audio" }) {
            info.hasAudio = true
            info.audioBitrate = number(audio["bit_rate"]) ?? 128_000
            info.audioChannels = Int(number(audio["channels"]) ?? 2)
            info.audioSampleRate = number(audio["sample_rate"]) ?? 44_100
        }
        if info.videoBitrate <= 0 {
            let total = number(format["bit_rate"]) ?? 0
            info.videoBitrate = max(0, total - info.audioBitrate)
        }
        return info
    }

    /// Кадр для превью: AVFoundation такой контейнер не откроет, берём его через ffmpeg.
    static func thumbnail(_ url: URL, at seconds: Double) -> NSImage? {
        guard let ffmpeg = locate() else { return nil }
        let temp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("chisel-thumb-\(UUID().uuidString).jpg")
        let p = Process()
        p.executableURL = ffmpeg
        p.arguments = ["-v", "quiet", "-nostdin", "-y",
                       "-ss", String(format: "%.2f", max(0, seconds)),
                       "-i", url.path,
                       "-frames:v", "1", "-vf", "scale=640:-2", temp.path]
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        defer { try? FileManager.default.removeItem(at: temp) }
        guard p.terminationStatus == 0 else { return nil }
        return NSImage(contentsOf: temp)
    }

    private static func isRotatedQuarterTurn(_ stream: [String: Any]) -> Bool {
        var rotation: Double = 0
        if let tags = stream["tags"] as? [String: Any], let r = number(tags["rotate"]) { rotation = r }
        if let list = stream["side_data_list"] as? [[String: Any]] {
            for item in list { if let r = number(item["rotation"]) { rotation = r } }
        }
        let normalized = abs(rotation.truncatingRemainder(dividingBy: 180))
        return normalized > 45 && normalized < 135
    }

    private static func number(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let n = any as? NSNumber { return n.doubleValue }
        if let s = any as? String { return Double(s) }
        return nil
    }

    private static func fraction(_ any: Any?) -> Double? {
        guard let s = any as? String else { return number(any) }
        let parts = s.components(separatedBy: "/")
        if parts.count == 2, let a = Double(parts[0]), let b = Double(parts[1]), b != 0 {
            return a / b
        }
        return Double(s)
    }

    // MARK: - Кодирование

    func cancel() {
        cancelled = true
        process?.terminate()
    }

    func run(job: Job,
             progress: @escaping (Double) -> Void,
             completion: @escaping (Result<Void, Error>) -> Void) {
        guard let ffmpeg = FFmpegEngine.locate() else {
            completion(.failure(ChiselError.ffmpegMissing)); return
        }

        var args = ["-hide_banner", "-nostdin", "-y", "-i", job.input.path, "-map", "0:v:0"]
        if job.includeAudio { args += ["-map", "0:a:0?"] }
        var filters: [String] = []
        if job.sourceIsHDR && !job.keepHDR {
            // Стандартная цепочка тон-маппинга HDR → SDR (нужен ffmpeg с libzimg).
            filters += ["zscale=t=linear:npl=100", "format=gbrpf32le", "zscale=p=bt709",
                        "tonemap=tonemap=hable:desat=0", "zscale=t=bt709:m=bt709:r=tv"]
        }
        filters.append("scale=\(job.width):\(job.height):flags=lanczos")
        filters.append(job.keepHDR ? "format=yuv420p10le" : "format=yuv420p")

        args += ["-c:v", job.codec == .hevc ? "libx265" : "libx264", "-preset", "medium",
                 "-b:v", "\(job.videoBitrate)",
                 "-maxrate", "\(Int(Double(job.videoBitrate) * 1.5))",
                 "-bufsize", "\(job.videoBitrate * 3)",
                 "-vf", filters.joined(separator: ",")]
        if job.codec == .hevc { args += ["-tag:v", "hvc1"] }
        if job.limitFps { args += ["-r", String(format: "%.3f", job.fps)] }
        if job.includeAudio {
            args += ["-c:a", "aac", "-b:a", "\(job.audioBitrate)",
                     "-ac", "\(min(2, max(1, job.audioChannels)))"]
        } else {
            args += ["-an"]
        }
        args += ["-movflags", "+faststart",
                 "-progress", "pipe:1", "-nostats", "-loglevel", "error",
                 job.output.path]

        let p = Process()
        p.executableURL = ffmpeg
        p.arguments = args
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        process = p

        let duration = max(0.001, job.duration)
        out.fileHandleForReading.readabilityHandler = { handle in
            guard let text = String(data: handle.availableData, encoding: .utf8) else { return }
            for line in text.components(separatedBy: .newlines)
            where line.hasPrefix("out_time_us=") || line.hasPrefix("out_time_ms=") {
                let raw = line.components(separatedBy: "=").last ?? ""
                guard let micro = Double(raw), micro >= 0 else { continue }
                let value = min(1.0, micro / 1_000_000.0 / duration)
                DispatchQueue.main.async { progress(value) }
            }
        }

        var errorText = ""
        err.fileHandleForReading.readabilityHandler = { handle in
            if let text = String(data: handle.availableData, encoding: .utf8), !text.isEmpty {
                errorText += text
            }
        }

        p.terminationHandler = { [weak self] proc in
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
            let wasCancelled = self?.cancelled ?? false
            DispatchQueue.main.async {
                if wasCancelled {
                    try? FileManager.default.removeItem(at: job.output)
                    completion(.failure(ChiselError.cancelled))
                } else if proc.terminationStatus == 0 {
                    progress(1.0)
                    completion(.success(()))
                } else {
                    try? FileManager.default.removeItem(at: job.output)
                    let tail = errorText.components(separatedBy: .newlines)
                        .filter { !$0.isEmpty }.suffix(3).joined(separator: " ")
                    completion(.failure(ChiselError.ffmpegFailed(tail.isEmpty ? "код \(proc.terminationStatus)" : tail)))
                }
            }
        }

        do { try p.run() } catch { completion(.failure(ChiselError.ffmpegFailed(error.localizedDescription))) }
    }
}
