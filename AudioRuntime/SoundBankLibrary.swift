import AVFoundation
import Foundation

struct ImportedSoundBank: Identifiable, Sendable {
    let id: UUID
    let url: URL
    let name: String
    let programs: [SoundBankProgram]
}

enum SoundBankError: LocalizedError {
    case invalid, tooLarge, cannotRender

    var errorDescription: String? {
        let key: String = switch self {
        case .invalid: "Choose a valid SoundFont bank with playable programs."
        case .tooLarge: "SoundFont banks must be 128 MB or smaller."
        case .cannotRender: "This instrument could not be played. Try a different program."
        }
        return NSLocalizedString(key, comment: "SoundFont library error")
    }
}

actor SoundBankLibrary {
    static let shared = SoundBankLibrary()
    private static let maximumBytes = 128_000_000
    private let files = FileManager.default
    private let directory: URL?

    init(directory: URL? = nil) { self.directory = directory }

    func list() throws -> [ImportedSoundBank] {
        let folders = try files.contentsOfDirectory(at: libraryURL(), includingPropertiesForKeys: nil)
        return folders.compactMap { folder in
            guard let id = UUID(uuidString: folder.lastPathComponent),
                  let urls = try? files.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil),
                  let url = urls.first(where: { $0.pathExtension.lowercased() == "sf2" }) else { return nil }
            return try? describe(url, id: id)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func importBank(from source: URL) throws -> ImportedSoundBank {
        let granted = source.startAccessingSecurityScopedResource()
        defer { if granted { source.stopAccessingSecurityScopedResource() } }
        guard source.pathExtension.lowercased() == "sf2" else { throw SoundBankError.invalid }
        try checkFile(source)
        let root = try libraryURL()
        let id = UUID()
        let staging = root.appendingPathComponent(".import-" + id.uuidString, isDirectory: true)
        try files.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? files.removeItem(at: staging) }
        let destination = staging.appendingPathComponent(source.lastPathComponent, isDirectory: false)
        try files.copyItem(at: source, to: destination)
        let validated = try describe(destination, id: id)
        guard let program = validated.programs.first else { throw SoundBankError.invalid }
        let sampler = AVAudioUnitSampler()
        try load(program, into: sampler, from: destination)
        try Task.checkCancellation()
        let committed = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try files.moveItem(at: staging, to: committed)
        return ImportedSoundBank(id: id, url: committed.appendingPathComponent(destination.lastPathComponent),
                                 name: validated.name, programs: validated.programs)
    }

    func audition(_ program: SoundBankProgram, in bank: ImportedSoundBank) throws -> URL {
        guard bank.programs.contains(program),
              let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024) else { throw SoundBankError.cannotRender }
        let engine = AVAudioEngine()
        let sampler = AVAudioUnitSampler()
        engine.attach(sampler)
        engine.connect(sampler, to: engine.mainMixerNode, format: format)
        try load(program, into: sampler, from: bank.url)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: buffer.frameCapacity)
        try engine.start()
        defer { engine.stop() }

        let output = files.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("caf")
        var completed = false
        defer { if !completed { try? files.removeItem(at: output) } }
        let file = try AVAudioFile(forWriting: output, settings: format.settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        let notes: [UInt8] = program.bank == 128 ? [36, 38, 42, 46] : [60, 64, 67, 72]
        let noteLength: AVAudioFramePosition = 10_240
        for note in notes {
            sampler.startNote(note, withVelocity: 92, onChannel: 0)
            try render(frames: noteLength, in: engine, buffer: buffer, to: file)
            sampler.stopNote(note, onChannel: 0)
        }
        try render(frames: 11_264, in: engine, buffer: buffer, to: file)
        try Task.checkCancellation()
        completed = true
        return output
    }

    private func render(frames: AVAudioFramePosition, in engine: AVAudioEngine,
                        buffer: AVAudioPCMBuffer, to file: AVAudioFile) throws {
        let end = engine.manualRenderingSampleTime + frames
        var stalled = 0
        while engine.manualRenderingSampleTime < end {
            try Task.checkCancellation()
            let previous = engine.manualRenderingSampleTime
            let count = AVAudioFrameCount(min(AVAudioFramePosition(buffer.frameCapacity), end - previous))
            switch try engine.renderOffline(count, to: buffer) {
            case .success:
                guard buffer.frameLength > 0, engine.manualRenderingSampleTime > previous else { throw SoundBankError.cannotRender }
                try file.write(from: buffer)
                stalled = 0
            case .cannotDoInCurrentContext:
                stalled += 1
                guard stalled < 8 else { throw SoundBankError.cannotRender }
            default: throw SoundBankError.cannotRender
            }
        }
    }

    private func load(_ program: SoundBankProgram, into sampler: AVAudioUnitSampler, from url: URL) throws {
        try sampler.loadSoundBankInstrument(at: url, program: program.program,
                                            bankMSB: program.bankMSB, bankLSB: program.bankLSB)
    }

    private func libraryURL() throws -> URL {
        let root: URL
        if let directory { root = directory }
        else {
            let parent = try files.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                       appropriateFor: nil, create: true)
            root = parent.appendingPathComponent("SoundBanks", isDirectory: true)
        }
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func checkFile(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, let size = values.fileSize, size >= 12 else {
            throw SoundBankError.invalid
        }
        guard size <= Self.maximumBytes else { throw SoundBankError.tooLarge }
    }

    private func describe(_ url: URL, id: UUID) throws -> ImportedSoundBank {
        try checkFile(url)
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let programs: [SoundBankProgram]
        do { programs = try SoundFontProgramTable.read(data) }
        catch { throw SoundBankError.invalid }
        return ImportedSoundBank(id: id, url: url, name: url.deletingPathExtension().lastPathComponent, programs: programs)
    }
}
