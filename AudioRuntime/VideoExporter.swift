import AVFoundation
import CoreText
import CoreVideo
import MusicDomain

/// I67 · a vertical 1080×1920 video of the song for social posts: the
/// rendered stereo mix with a moving playhead over the note map. Frames are
/// drawn offline into H.264, then joined with the audio into an MP4.
enum VideoExporter {
    enum Failure: Error { case writer, pixels }

    static func encode(wav: URL, project: Project, range: Range<Int>, to url: URL, fps: Int = 30,
                       progress: @escaping @Sendable (Double) -> Void) async throws {
        let audio = AVURLAsset(url: wav)
        let seconds = try await audio.load(.duration).seconds
        let board = VideoStoryboard(project: project, range: range, seconds: seconds, fps: fps)
        let silent = url.deletingLastPathComponent().appendingPathComponent("frames-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: silent) }
        try await writeFrames(board, to: silent, progress: progress)
        try await mux(video: silent, audio: audio, to: url)
    }

    // MARK: Frames

    private static let width = Int(VideoStoryboard.width), height = Int(VideoStoryboard.height)

    private static func writeFrames(_ board: VideoStoryboard, to url: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 6_000_000]])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height])
        guard writer.canAdd(input) else { throw Failure.writer }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? Failure.writer }
        writer.startSession(atSourceTime: .zero)
        guard let background = backgroundImage(board) else { throw Failure.pixels }
        for frame in 0..<board.frames {
            try Task.checkCancellation()
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(4)) }
            guard let pool = adaptor.pixelBufferPool else { throw writer.error ?? Failure.writer }
            var buffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let pixels = buffer else { throw Failure.pixels }
            CVPixelBufferLockBaseAddress(pixels, [])
            let drawn: Bool = {
                guard let context = CGContext(data: CVPixelBufferGetBaseAddress(pixels), width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: CVPixelBufferGetBytesPerRow(pixels), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return false }
                context.draw(background, in: CGRect(x: 0, y: 0, width: width, height: height))
                drawPlayhead(board, frame: frame, in: context)
                return true
            }()
            CVPixelBufferUnlockBaseAddress(pixels, [])
            guard drawn, adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(board.fps))) else {
                throw writer.error ?? Failure.writer
            }
            if frame % 30 == 0 { progress(0.5 + 0.45 * Double(frame) / Double(board.frames)) }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? Failure.writer }
    }

    /// Drawing uses top-left coordinates from the storyboard; CoreGraphics is bottom-left.
    private static func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect {
        CGRect(x: x, y: Double(height) - y - h, width: w, height: h)
    }

    private static func colour(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: alpha)
    }
    private static func roleColour(_ role: TrackRole) -> UInt32 {
        switch role { case .harmony: 0xE5BE69; case .drums: 0xB7BCEF; case .bass: 0x85D6C3; default: 0xD8F780 }
    }
    private static let sectionColours: [UInt32] = [0xE5BE69, 0xB7BCEF, 0x85D6C3, 0xD8F780]

    private static func backgroundImage(_ board: VideoStoryboard) -> CGImage? {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        context.setFillColor(colour(0x0C0E12)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let m = VideoStoryboard.map
        context.setFillColor(colour(0x171C23))
        context.addPath(CGPath(roundedRect: rect(m.x - 24, m.y - 150, m.width + 48, m.height + 190), cornerWidth: 36, cornerHeight: 36, transform: nil)); context.fillPath()
        text(board.title, size: 64, weight: 0.4, colour: 0xF3F5F0, x: 60, y: 260, in: context)
        text(board.subtitle, size: 36, weight: 0, colour: 0xA8B2BE, x: 60, y: 350, in: context)
        for band in board.sections {
            context.setFillColor(colour(sectionColours[band.colour % 4], alpha: 0.85))
            context.addPath(CGPath(roundedRect: rect(band.x + 2, m.y - 110, max(2, band.width - 4), 64), cornerWidth: 14, cornerHeight: 14, transform: nil)); context.fillPath()
            if band.width > 90 { text(band.name, size: 28, weight: 0.3, colour: 0x0C0E12, x: band.x + 16, y: m.y - 92, in: context) }
        }
        for block in board.blocks {
            context.setFillColor(colour(roleColour(block.role), alpha: 0.9))
            context.fill(rect(block.x, block.y, block.width, block.height))
        }
        text(NSLocalizedString("Made with La Grilla", comment: "Video credit"), size: 30, weight: 0, colour: 0x6F7B88, x: 60, y: 1780, in: context)
        return context.makeImage()
    }

    private static func drawPlayhead(_ board: VideoStoryboard, frame: Int, in context: CGContext) {
        let m = VideoStoryboard.map, x = board.playheadX(frame: frame)
        // Dim what has not played yet.
        context.setFillColor(colour(0x0C0E12, alpha: 0.55))
        context.fill(rect(x, m.y - 4, max(0, m.x + m.width - x), m.height + 8))
        if let index = board.section(frame: frame) {
            let band = board.sections[index]
            context.setStrokeColor(colour(0xF3F5F0)); context.setLineWidth(4)
            context.addPath(CGPath(roundedRect: rect(band.x + 2, m.y - 110, max(2, band.width - 4), 64), cornerWidth: 14, cornerHeight: 14, transform: nil)); context.strokePath()
        }
        context.setFillColor(colour(0xFF858D))
        context.fill(rect(x - 3, m.y - 30, 6, m.height + 60))
    }

    private static func text(_ string: String, size: CGFloat, weight: CGFloat, colour hex: UInt32, x: Double, y: Double, in context: CGContext) {
        let font = CTFontCreateUIFontForLanguage(weight > 0.2 ? .emphasizedSystem : .system, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font,
                                                         NSAttributedString.Key(kCTForegroundColorAttributeName as String): colour(hex)]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
        context.textPosition = CGPoint(x: x, y: Double(height) - y - Double(size))
        CTLineDraw(line, context)
    }

    // MARK: Audio + video

    private static func mux(video: URL, audio: AVURLAsset, to url: URL) async throws {
        let picture = AVURLAsset(url: video)
        let composition = AVMutableComposition()
        guard let videoTrack = try await picture.loadTracks(withMediaType: .video).first,
              let audioTrack = try await audio.loadTracks(withMediaType: .audio).first,
              let videoOut = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioOut = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw Failure.writer }
        let videoDuration = try await picture.load(.duration), audioDuration = try await audio.load(.duration)
        let duration = CMTimeMinimum(videoDuration, audioDuration)
        try videoOut.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: videoTrack, at: .zero)
        try audioOut.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: audioTrack, at: .zero)
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else { throw Failure.writer }
        try await session.export(to: url, as: .mp4)
    }
}
