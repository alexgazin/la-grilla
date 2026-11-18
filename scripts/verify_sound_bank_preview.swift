import AVFoundation
import Foundation

/// Runs only on Apple hosts and auditions a real external SoundFont, never a bundled fixture.
@main struct VerifySoundBankPreview {
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else { throw SoundBankError.invalid }
        let source = URL(fileURLWithPath: CommandLine.arguments[1])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = SoundBankLibrary(directory: root)
        let added = try await library.importBank(from: source)
        let reloaded = try await SoundBankLibrary(directory: root).list()
        guard reloaded.count == 1, let bank = reloaded.first, bank.id == added.id,
              bank.url != source, bank.programs == added.programs,
              let piano = bank.programs.first(where: { $0.bank == 0 && $0.program == 0 }),
              let guitar = bank.programs.first(where: { $0.bank == 0 && $0.program == 24 }) else {
            throw SoundBankError.invalid
        }
        let first = try await PCM(program: piano, bank: bank, library: library)
        let second = try await PCM(program: guitar, bank: bank, library: library)
        guard first != second, first.count == 52_224, second.count == first.count else { throw SoundBankError.cannotRender }
        print("Real SoundFont import persisted \(bank.programs.count) programs. Sampler rendered distinct audible piano and guitar previews.")
    }

    static func PCM(program: SoundBankProgram, bank: ImportedSoundBank, library: SoundBankLibrary) async throws -> [Float] {
        let url = try await library.audition(program, in: bank)
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try AVAudioFile(forReading: url)
        guard file.length == 52_224,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw SoundBankError.cannotRender
        }
        try file.read(into: buffer)
        guard let channel = buffer.floatChannelData?[0] else { throw SoundBankError.cannotRender }
        let pcm = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        guard pcm.allSatisfy(\.isFinite), pcm.contains(where: { abs($0) > 0.001 }) else { throw SoundBankError.cannotRender }
        return pcm
    }
}
