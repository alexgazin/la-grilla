import AVFoundation
import Foundation

/// I36 · Sound from a video or a voice memo: the audio of any file AVFoundation can read
/// (MOV, MP4, M4A, MP3, CAF…) becomes a short WAV the sample importers already accept.
enum AudioExtraction {
    enum Failure: LocalizedError {
        case noAudio
        var errorDescription: String? {
            NSLocalizedString("This file has no sound to take. Choose a video or recording with audio.", comment: "Audio extraction")
        }
    }

    /// WAV and AIFF pass through; anything else is decoded (first `limit` seconds, 44.1 kHz).
    static func wavIfNeeded(_ url: URL, limit: Double = 30) async throws -> URL {
        let ext = url.pathExtension.lowercased()
        if ["wav", "wave", "aif", "aiff", "aifc"].contains(ext) { return url }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw Failure.noAudio }
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: limit, preferredTimescale: 600))
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 2,
                                       AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
                                       AVLinearPCMIsNonInterleaved: false]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? Failure.noAudio }
        var pcm = Data()
        while let buffer = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(buffer) {
            try Task.checkCancellation()
            var length = 0
            var pointer: UnsafeMutablePointer<CChar>?
            if CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer) == kCMBlockBufferNoErr, let pointer {
                pcm.append(UnsafeRawPointer(pointer).assumingMemoryBound(to: UInt8.self), count: length)
            }
        }
        guard reader.status == .completed || reader.status == .reading, pcm.count > 4 * 441 else { throw reader.error ?? Failure.noAudio }
        var wav = Data("RIFF".utf8)
        func le32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { wav.append(contentsOf: $0) } }
        func le16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { wav.append(contentsOf: $0) } }
        le32(UInt32(36 + pcm.count)); wav.append(contentsOf: Array("WAVEfmt ".utf8))
        le32(16); le16(1); le16(2); le32(44_100); le32(44_100 * 4); le16(4); le16(16)
        wav.append(contentsOf: Array("data".utf8)); le32(UInt32(pcm.count)); wav.append(pcm)
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(url.deletingPathExtension().lastPathComponent + "-sound-\(UUID().uuidString.prefix(6)).wav")
        try wav.write(to: destination, options: .atomic)
        return destination
    }
}
