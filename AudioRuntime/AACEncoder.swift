import AVFoundation

/// I66 · Compact AAC (.m4a) from the rendered stereo WAV, for messages and
/// sharing. The WAV is the same offline mix as the WAV export.
enum AACEncoder {
    static func encode(wav: URL, to url: URL, bitRate: Int = 256_000) throws {
        let input = try AVAudioFile(forReading: wav)
        let format = input.processingFormat
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: format.sampleRate,
                                       AVNumberOfChannelsKey: format.channelCount, AVEncoderBitRateKey: bitRate]
        let output = try AVAudioFile(forWriting: url, settings: settings, commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8192) else { throw ExportFailure.encoder }
        while input.framePosition < input.length {
            try Task.checkCancellation()
            try input.read(into: buffer)
            if buffer.frameLength == 0 { break }
            try output.write(from: buffer)
        }
    }
    enum ExportFailure: Error { case encoder }
}
