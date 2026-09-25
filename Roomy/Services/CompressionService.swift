import Foundation
import AVFoundation
import CoreGraphics
import CoreVideo
import ImageIO
import UniformTypeIdentifiers

// MARK: - Photo compression

/// Pure image compression / verification helpers. No side effects, no I/O beyond memory.
enum CompressionService {

    /// Whether this device can write HEIC (all iOS 17 devices can, but check at runtime anyway).
    static func heicSupported() -> Bool {
        guard let ids = CGImageDestinationCopyTypeIdentifiers() as? [String] else { return false }
        return ids.contains(UTType.heic.identifier)
    }

    /// Compress a photo. Returns compressed data + "HEIC" or "JPEG".
    /// Presets: smart → keep dimensions, quality 0.72; smaller → long edge ≤ 2048, quality 0.55; best → keep dimensions, quality 0.88.
    static func compressPhoto(_ data: Data, preset: QualityPreset) async throws -> (data: Data, format: String) {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw RoomyError.verificationFailed("Could not read the photo.")
        }

        // Read pixel dimensions.
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let pixelWidth = (props?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let pixelHeight = (props?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        guard pixelWidth > 0, pixelHeight > 0 else {
            throw RoomyError.verificationFailed("Could not read the photo.")
        }

        let quality: CGFloat
        let maxEdge: Int
        switch preset {
        case .smart:
            quality = 0.72
            maxEdge = max(pixelWidth, pixelHeight) // no downscale
        case .smaller:
            quality = 0.55
            maxEdge = 2048
        case .best:
            quality = 0.88
            maxEdge = max(pixelWidth, pixelHeight) // no downscale
        }

        let thumbOptions: CFDictionary = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxEdge,
        ] as CFDictionary
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOptions) else {
            throw RoomyError.exportFailed("Could not decode the photo for compression.")
        }

        let useHEIC = heicSupported()
        let typeID = (useHEIC ? UTType.heic : .jpeg).identifier

        let destData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(destData, typeID as CFString, 1, nil) else {
            throw RoomyError.exportFailed("Could not write the compressed photo.")
        }
        CGImageDestinationAddImage(
            dest,
            thumb,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        )
        guard CGImageDestinationFinalize(dest) else {
            throw RoomyError.exportFailed("Could not write the compressed photo.")
        }

        return (destData as Data, useHEIC ? "HEIC" : "JPEG")
    }

    /// Return image data with GPS/location metadata removed (other metadata kept).
    /// Never throws fatally: returns the original data on any failure.
    static func stripLocation(from imageData: Data) -> Data {
        guard let src = CGImageSourceCreateWithData(imageData as CFData, nil),
              let type = CGImageSourceGetType(src),
              var props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              props.keys.contains(kCGImagePropertyGPSDictionary)
        else {
            return imageData
        }

        props.removeValue(forKey: kCGImagePropertyGPSDictionary)

        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, type, 1, nil) else {
            return imageData
        }
        CGImageDestinationAddImageFromSource(dest, src, 0, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            return imageData
        }
        return out as Data
    }

    /// Verify a compressed photo. `expectSameDimensions` = (preset != .smaller).
    static func verifyPhoto(
        originalData: Data,
        compressedData: Data,
        expectSameDimensions: Bool
    ) -> (passed: Bool, reason: String?) {
        guard !compressedData.isEmpty else {
            return (false, "The compressed file is empty.")
        }
        guard compressedData.count < originalData.count else {
            return (false, "Output is not smaller than the original.")
        }

        guard let origSrc = CGImageSourceCreateWithData(originalData as CFData, nil),
              let compSrc = CGImageSourceCreateWithData(compressedData as CFData, nil),
              CGImageSourceGetCount(origSrc) >= 1,
              CGImageSourceGetCount(compSrc) >= 1
        else {
            return (false, "The compressed photo could not be opened.")
        }

        if expectSameDimensions {
            let origProps = CGImageSourceCopyPropertiesAtIndex(origSrc, 0, nil) as? [CFString: Any]
            let compProps = CGImageSourceCopyPropertiesAtIndex(compSrc, 0, nil) as? [CFString: Any]
            let origW = (origProps?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
            let origH = (origProps?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
            let compW = (compProps?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
            let compH = (compProps?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
            guard origW > 0, origH > 0, compW > 0, compH > 0 else {
                return (false, "The compressed photo could not be opened.")
            }
            guard origW == compW, origH == compH else {
                return (false, "Dimensions changed unexpectedly.")
            }
        }

        return (true, nil)
    }
}

// MARK: - Video compression

/// Compresses one video with AVAssetReader/AVAssetWriter at a computed bitrate
/// (keeps dimensions except on `.smaller`).
final class VideoCompressor {
    private let lock = NSLock()
    private var _cancelled = false
    private var reader: AVAssetReader?
    private var writer: AVAssetWriter?

    private var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _cancelled
    }

    func cancel() {
        lock.lock()
        _cancelled = true
        lock.unlock()
        reader?.cancelReading()
        writer?.cancelWriting()
    }

    /// - Returns: file URL of the compressed .mp4 in a temp directory.
    func compress(
        sourceURL: URL,
        preset: QualityPreset,
        progress: @escaping (Double) -> Void
    ) async throws -> URL {
        // A previous cancel() must never poison later compressions:
        // reset the flag and drop stale reader/writer references up front.
        lock.lock()
        _cancelled = false
        reader = nil
        writer = nil
        lock.unlock()
        defer {
            lock.lock()
            reader = nil
            writer = nil
            lock.unlock()
        }
        // Try HEVC first; on any non-cancellation failure, retry once with H.264.
        do {
            return try await runCompression(
                sourceURL: sourceURL, preset: preset, codec: .hevc, progress: progress
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return try await runCompression(
                sourceURL: sourceURL, preset: preset, codec: .h264, progress: progress
            )
        }
    }

    /// Nonisolated: blocks on the reader/writer pump and sleeps between polls.
    private nonisolated func runCompression(
        sourceURL: URL,
        preset: QualityPreset,
        codec: AVVideoCodecType,
        progress: @escaping (Double) -> Void
    ) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw RoomyError.noVideoTrack
        }

        // Render size, honoring the track's preferred orientation.
        let naturalSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        let oriented = CGRect(origin: .zero, size: naturalSize).applying(transform).integral
        var w = evenDown(abs(oriented.width))
        var h = evenDown(abs(oriented.height))
        if preset == .smaller, max(w, h) > 1920 {
            let scale = 1920.0 / Double(max(w, h))
            w = evenDown(Double(w) * scale)
            h = evenDown(Double(h) * scale)
        }
        guard w > 0, h > 0 else {
            throw RoomyError.exportFailed("Could not read the video.")
        }

        var fps = try await videoTrack.load(.nominalFrameRate)
        if fps <= 0 { fps = 30 }

        let bitsPerPixel: Double
        switch preset {
        case .smart: bitsPerPixel = 0.08
        case .smaller: bitsPerPixel = 0.04
        case .best: bitsPerPixel = 0.14
        }
        let bitrate = max(800_000, Int(Double(w * h) * Double(fps) * bitsPerPixel))

        let audioTrack = try await asset.loadTracks(withMediaType: .audio).first

        // Source audio format, for a robust decode -> re-encode path.
        // (Audio passthrough with nil outputSettings silently drops the
        // audio track on some sources, which the verifier then rejects.)
        var audioSampleRate: Double = 44_100
        var audioChannels: Int = 2
        if let audioTrack,
           let formatDescs = try? await audioTrack.load(.formatDescriptions),
           let formatDesc = formatDescs.first,
           let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) {
            if asbd.pointee.mSampleRate > 0 { audioSampleRate = asbd.pointee.mSampleRate }
            if asbd.pointee.mChannelsPerFrame > 0 { audioChannels = Int(asbd.pointee.mChannelsPerFrame) }
        }
        let durationSeconds = CMTimeGetSeconds((try? await asset.load(.duration)) ?? .zero)

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        var didComplete = false
        defer {
            if !didComplete {
                try? FileManager.default.removeItem(at: outputURL)
            }
        }

        // Reader.
        let reader = try AVAssetReader(asset: asset)
        self.reader = reader
        let videoOutput = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        guard reader.canAdd(videoOutput) else {
            throw RoomyError.exportFailed("Could not read the video.")
        }
        reader.add(videoOutput)

        // Decode audio to PCM on read; the writer re-encodes to AAC below.
        var audioOutput: AVAssetReaderTrackOutput?
        if let audioTrack {
            let out = AVAssetReaderTrackOutput(
                track: audioTrack,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: audioSampleRate,
                    AVNumberOfChannelsKey: audioChannels,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsNonInterleaved: false,
                ]
            )
            if reader.canAdd(out) {
                reader.add(out)
                audioOutput = out
            }
        }

        // Writer.
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        self.writer = writer
        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: codec,
                AVVideoWidthKey: w,
                AVVideoHeightKey: h,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: bitrate,
                ],
            ]
        )
        videoInput.transform = transform
        videoInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput) else {
            throw RoomyError.exportFailed("Could not write the video.")
        }
        writer.add(videoInput)

        // Re-encode the decoded PCM to AAC so the output always carries
        // a real audio track (passthrough with nil settings silently
        // drops the track on some sources).
        var audioInput: AVAssetWriterInput?
        if audioOutput != nil {
            let input = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: audioSampleRate,
                    AVNumberOfChannelsKey: audioChannels,
                    AVEncoderBitRateKey: 128_000,
                ]
            )
            input.expectsMediaDataInRealTime = false
            if writer.canAdd(input) {
                writer.add(input)
                audioInput = input
            }
        }

        guard reader.startReading() else {
            throw RoomyError.exportFailed("Could not read the video.")
        }
        guard writer.startWriting() else {
            throw RoomyError.exportFailed("Could not write the video.")
        }
        writer.startSession(atSourceTime: .zero)

        // Pump samples from reader to writer.
        // Progress is throttled to ~2% steps: reporting every frame would
        // spawn thousands of main-thread UI updates per minute of video,
        // which made the whole phone feel slow.
        var lastReportedProgress = -1.0
        let reportProgress: (Double) -> Void = { p in
            if p >= 1.0 || p - lastReportedProgress >= 0.02 {
                lastReportedProgress = p
                progress(p)
            }
        }
        var videoDone = false
        var audioDone = audioInput == nil
        while !videoDone || !audioDone {
            if isCancelled { throw CancellationError() }

            if !videoDone {
                if let sample = videoOutput.copyNextSampleBuffer() {
                    while !videoInput.isReadyForMoreMediaData {
                        try? await Task.sleep(nanoseconds: 500_000)
                        if isCancelled { throw CancellationError() }
                    }
                    videoInput.append(sample)
                    let t = CMSampleBufferGetPresentationTimeStamp(sample)
                    if durationSeconds > 0 {
                        reportProgress(min(0.99, CMTimeGetSeconds(t) / durationSeconds))
                    }
                } else {
                    videoDone = true
                    videoInput.markAsFinished()
                }
            }

            if !audioDone, let audioOutput, let audioInput {
                if let sample = audioOutput.copyNextSampleBuffer() {
                    while !audioInput.isReadyForMoreMediaData {
                        try? await Task.sleep(nanoseconds: 500_000)
                        if isCancelled { throw CancellationError() }
                    }
                    audioInput.append(sample)
                } else {
                    audioDone = true
                    audioInput.markAsFinished()
                }
            }
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting {
                continuation.resume()
            }
        }
        guard writer.status == .completed else {
            throw RoomyError.exportFailed("Video export failed.")
        }

        reportProgress(1.0)
        didComplete = true
        return outputURL
    }

    /// Round down to an even integer (H.264/HEVC require even dimensions).
    private nonisolated func evenDown(_ x: Double) -> Int {
        Int((x / 2).rounded(.down)) * 2
    }

    /// Verify a compressed video file.
    static func verifyVideo(
        originalURL: URL,
        compressedURL: URL
    ) async -> (passed: Bool, reason: String?) {
        let origSize = (try? FileManager.default.attributesOfItem(atPath: originalURL.path)[.size]) as? Int64 ?? 0
        let compSize = (try? FileManager.default.attributesOfItem(atPath: compressedURL.path)[.size]) as? Int64 ?? 0

        guard compSize > 0 else {
            return (false, "The compressed video is empty.")
        }
        guard compSize < origSize else {
            return (false, "Output is not smaller than the original.")
        }

        let orig = AVURLAsset(url: originalURL)
        let comp = AVURLAsset(url: compressedURL)

        let compVideo = try? await comp.loadTracks(withMediaType: .video)
        guard compVideo?.isEmpty == false else {
            return (false, "The compressed video has no picture.")
        }

        let origAudioCount = (try? await orig.loadTracks(withMediaType: .audio))?.count ?? 0
        let compAudioCount = (try? await comp.loadTracks(withMediaType: .audio))?.count ?? 0
        if origAudioCount > 0 && compAudioCount == 0 {
            return (false, "The compressed video lost its audio.")
        }

        let origDur = CMTimeGetSeconds((try? await orig.load(.duration)) ?? .zero)
        let compDur = CMTimeGetSeconds((try? await comp.load(.duration)) ?? .zero)
        guard abs(origDur - compDur) <= 1.0 else {
            return (false, "The video length changed.")
        }

        let generator = AVAssetImageGenerator(asset: comp)
        generator.appliesPreferredTrackTransform = true
        guard (try? generator.copyCGImage(at: .zero, actualTime: nil)) != nil else {
            return (false, "The compressed video could not be previewed.")
        }

        return (true, nil)
    }
}
