import AVFoundation
import AudioToolbox
import VideoToolbox

/// Основной движок: AVAssetReader → AVAssetWriter (VideoToolbox, аппаратный H.264).
/// Ничего не нужно доустанавливать — всё это часть macOS.
final class AVEngine {

    private var reader: AVAssetReader?
    private var writer: AVAssetWriter?
    private var cancelled = false
    private let videoQueue = DispatchQueue(label: "app.chisel.video")
    private let audioQueue = DispatchQueue(label: "app.chisel.audio")
    private var lastReport = Date.distantPast

    /// Отменяем только чтение: copyNextSampleBuffer вернёт nil, входы корректно
    /// закроются, а writer отменит запись уже в общем завершающем блоке.
    /// Дёргать cancelWriting отсюда нельзя — markAsFinished на отменённом writer бросает исключение.
    func cancel() {
        cancelled = true
        reader?.cancelReading()
    }

    func run(job: Job,
             progress: @escaping (Double) -> Void,
             completion: @escaping (Result<Void, Error>) -> Void) {
        do {
            try start(job: job, progress: progress, completion: completion)
        } catch {
            completion(.failure(error))
        }
    }

    // MARK: - Сборка конвейера

    private func start(job: Job,
                       progress: @escaping (Double) -> Void,
                       completion: @escaping (Result<Void, Error>) -> Void) throws {

        let asset = AVURLAsset(url: job.input,
                               options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            throw ChiselError.noVideoTrack
        }

        var duration = CMTimeGetSeconds(asset.duration)
        if !duration.isFinite || duration <= 0 { duration = job.duration }

        let reader = try AVAssetReader(asset: asset)
        self.reader = reader

        // — видео: композиция делает и поворот, и масштаб, и (при желании) прореживание кадров —
        let composition = AVMutableVideoComposition()
        composition.renderSize = CGSize(width: job.width, height: job.height)
        // Цвет. H.264 здесь 8-битный SDR, поэтому HDR-источник надо честно
        // привести к BT.709 — иначе картинка выходит блёклой и серой.
        if job.sourceIsHDR {
            if job.keepHDR {
                composition.colorPrimaries = AVVideoColorPrimaries_ITU_R_2020
                composition.colorTransferFunction = job.hdrIsPQ
                    ? AVVideoTransferFunction_SMPTE_ST_2084_PQ
                    : AVVideoTransferFunction_ITU_R_2100_HLG
                composition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_2020
            } else {
                composition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
                composition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
                composition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
            }
        }
        let outFps = max(1.0, job.fps)
        composition.frameDuration = CMTime(value: 1_000,
                                           timescale: CMTimeScale((outFps * 1_000).rounded()))

        let natural = videoTrack.naturalSize
        let transform = videoTrack.preferredTransform
        let mapped = CGRect(origin: .zero, size: natural).applying(transform)
        let recenter = CGAffineTransform(translationX: -mapped.minX, y: -mapped.minY)
        let sx = mapped.width == 0 ? 1 : CGFloat(job.width) / mapped.width
        let sy = mapped.height == 0 ? 1 : CGFloat(job.height) / mapped.height
        let full = transform
            .concatenating(recenter)
            .concatenating(CGAffineTransform(scaleX: sx, y: sy))

        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        layer.setTransform(full, at: .zero)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: asset.duration)
        instruction.layerInstructions = [layer]
        composition.instructions = [instruction]

        let pixelFormat = job.keepHDR ? kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
                                      : kCVPixelFormatType_32BGRA
        let videoOutput = AVAssetReaderVideoCompositionOutput(
            videoTracks: [videoTrack],
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String:
                                NSNumber(value: pixelFormat)])
        videoOutput.videoComposition = composition
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else { throw ChiselError.readerFailed("видеодорожка") }
        reader.add(videoOutput)

        // — звук —
        let audioTrack = job.includeAudio ? asset.tracks(withMediaType: .audio).first : nil
        let channels = min(2, max(1, job.audioChannels))
        let sampleRate = job.audioSampleRate > 0 ? min(job.audioSampleRate, 48_000) : 44_100
        var audioOutput: AVAssetReaderTrackOutput?
        if let track = audioTrack {
            var pcm: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
                AVNumberOfChannelsKey: channels,
                AVSampleRateKey: sampleRate
            ]
            pcm[AVChannelLayoutKey] = AVEngine.channelLayoutData(channels)
            let out = AVAssetReaderTrackOutput(track: track, outputSettings: pcm)
            out.alwaysCopiesSampleData = false
            if reader.canAdd(out) {
                reader.add(out)
                audioOutput = out
            }
        }

        // — запись —
        try? FileManager.default.removeItem(at: job.output)
        let writer = try AVAssetWriter(outputURL: job.output, fileType: .mp4)
        self.writer = writer
        writer.shouldOptimizeForNetworkUse = true   // moov в начало файла: видео стартует сразу

        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: job.videoBitrate,
            AVVideoMaxKeyFrameIntervalKey: Int(max(1, (outFps * 2).rounded())),
            AVVideoMaxKeyFrameIntervalDurationKey: 2.0,
            AVVideoAllowFrameReorderingKey: true,
            AVVideoExpectedSourceFrameRateKey: Int(outFps.rounded())
        ]
        switch job.codec {
        case .h264:
            compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
        case .hevc:
            // 10 бит нужны только для HDR; обычному HEVC хватает профиля по умолчанию.
            if job.keepHDR {
                compression[AVVideoProfileLevelKey] = kVTProfileLevel_HEVC_Main10_AutoLevel as String
            }
        }

        let colorProperties: [String: Any] = job.keepHDR
            ? [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_2020,
               AVVideoTransferFunctionKey: job.hdrIsPQ
                    ? AVVideoTransferFunction_SMPTE_ST_2084_PQ
                    : AVVideoTransferFunction_ITU_R_2100_HLG,
               AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_2020]
            : [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
               AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
               AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2]

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: job.codec == .hevc ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: job.width,
            AVVideoHeightKey: job.height,
            AVVideoCompressionPropertiesKey: compression,
            AVVideoColorPropertiesKey: colorProperties
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput) else {
            throw ChiselError.writerFailed(job.codec.title)
        }
        writer.add(videoInput)

        var audioInput: AVAssetWriterInput?
        if audioOutput != nil {
            var settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVNumberOfChannelsKey: channels,
                AVSampleRateKey: sampleRate,
                AVEncoderBitRateKey: job.audioBitrate
            ]
            settings[AVChannelLayoutKey] = AVEngine.channelLayoutData(channels)
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
            input.expectsMediaDataInRealTime = false
            if writer.canAdd(input) {
                writer.add(input)
                audioInput = input
            }
        }

        guard reader.startReading() else {
            throw ChiselError.readerFailed(reader.error?.localizedDescription ?? "неизвестно")
        }
        guard writer.startWriting() else {
            throw ChiselError.writerFailed(writer.error?.localizedDescription ?? "неизвестно")
        }
        writer.startSession(atSourceTime: .zero)

        // MARK: - Перекачка сэмплов

        let group = DispatchGroup()

        group.enter()
        var videoDone = false
        videoInput.requestMediaDataWhenReady(on: videoQueue) { [weak self] in
            guard let self = self, !videoDone else { return }
            while videoInput.isReadyForMoreMediaData {
                if self.cancelled {
                    videoDone = true; videoInput.markAsFinished(); group.leave(); return
                }
                guard let buffer = videoOutput.copyNextSampleBuffer() else {
                    videoDone = true; videoInput.markAsFinished(); group.leave(); return
                }
                let pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(buffer))
                if !videoInput.append(buffer) {
                    videoDone = true; videoInput.markAsFinished(); group.leave(); return
                }
                if duration > 0, pts.isFinite {
                    self.report(min(1.0, max(0.0, pts / duration)), progress)
                }
            }
        }

        if let audioInput = audioInput, let audioOutput = audioOutput {
            group.enter()
            var audioDone = false
            audioInput.requestMediaDataWhenReady(on: audioQueue) { [weak self] in
                guard let self = self, !audioDone else { return }
                while audioInput.isReadyForMoreMediaData {
                    if self.cancelled {
                        audioDone = true; audioInput.markAsFinished(); group.leave(); return
                    }
                    guard let buffer = audioOutput.copyNextSampleBuffer() else {
                        audioDone = true; audioInput.markAsFinished(); group.leave(); return
                    }
                    if !audioInput.append(buffer) {
                        audioDone = true; audioInput.markAsFinished(); group.leave(); return
                    }
                }
            }
        }

        group.notify(queue: DispatchQueue.global(qos: .userInitiated)) { [weak self] in
            guard let self = self else { return }
            if self.cancelled {
                writer.cancelWriting()
                try? FileManager.default.removeItem(at: job.output)
                DispatchQueue.main.async { completion(.failure(ChiselError.cancelled)) }
                return
            }
            if reader.status == .failed {
                writer.cancelWriting()
                try? FileManager.default.removeItem(at: job.output)
                let message = reader.error?.localizedDescription ?? "чтение прервано"
                DispatchQueue.main.async { completion(.failure(ChiselError.readerFailed(message))) }
                return
            }
            writer.finishWriting {
                DispatchQueue.main.async {
                    if writer.status == .completed {
                        progress(1.0)
                        completion(.success(()))
                    } else {
                        try? FileManager.default.removeItem(at: job.output)
                        let message = writer.error?.localizedDescription ?? "запись прервана"
                        completion(.failure(ChiselError.writerFailed(message)))
                    }
                }
            }
        }
    }

    /// Прогресс приходит на каждый кадр — в UI отдаём не чаще 20 раз в секунду.
    private func report(_ value: Double, _ progress: @escaping (Double) -> Void) {
        let now = Date()
        guard now.timeIntervalSince(lastReport) > 0.05 else { return }
        lastReport = now
        DispatchQueue.main.async { progress(value) }
    }

    private static func channelLayoutData(_ channels: Int) -> Data {
        var layout = AudioChannelLayout()
        layout.mChannelLayoutTag = channels == 1 ? kAudioChannelLayoutTag_Mono
                                                 : kAudioChannelLayoutTag_Stereo
        return Data(bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size)
    }
}
