import Foundation
import AVFoundation
import AudioToolbox
import MusicDomain

/// 54 · Audio Units installed on this iPhone (AUv3 apps from the App Store and Apple's own).
enum PluginCatalog {
    struct Entry: Identifiable, Hashable {
        let reference: PluginReference
        var id: String { "\(reference.type)-\(reference.subtype)-\(reference.manufacturer)" }
        var isApple: Bool { reference.manufacturer == PluginReference.fourCC("appl") }
    }

    static func installed(_ kind: PluginReference.Kind) -> [Entry] {
        let types: [OSType] = kind == .instrument ? [kAudioUnitType_MusicDevice] : [kAudioUnitType_Effect, kAudioUnitType_MusicEffect]
        var seen = Set<String>(), result: [Entry] = []
        for type in types {
            let description = AudioComponentDescription(componentType: type, componentSubType: 0, componentManufacturer: 0, componentFlags: 0, componentFlagsMask: 0)
            for component in AVAudioUnitComponentManager.shared().components(matching: description) {
                let d = component.audioComponentDescription
                let entry = Entry(reference: PluginReference(kind: kind, type: d.componentType, subtype: d.componentSubType, manufacturer: d.componentManufacturer,
                                                             name: component.name, maker: component.manufacturerName))
                if seen.insert(entry.id).inserted { result.append(entry) }
            }
        }
        // Apps the person installed first, then Apple's units.
        return result.sorted { ($0.isApple ? 1 : 0, $0.reference.name.lowercased()) < ($1.isApple ? 1 : 0, $1.reference.name.lowercased()) }
    }
}

enum PluginHostError: Error, LocalizedError {
    case unavailable, render, tooLong
    var errorDescription: String? {
        let key = switch self {
        case .unavailable: "This plugin is not installed on this iPhone or could not start."
        case .render: "The plugin stopped while rendering. Try again, or choose another plugin."
        case .tooLong: "Plugins can render songs up to two and a half minutes. Shorten the song or bounce a section."
        }
        return NSLocalizedString(key, comment: "Plugins")
    }
}

/// 54 · Starting Audio Units, keeping their settings, and rendering through them offline.
enum PluginHost {
    static func description(_ reference: PluginReference) -> AudioComponentDescription {
        AudioComponentDescription(componentType: reference.type, componentSubType: reference.subtype, componentManufacturer: reference.manufacturer, componentFlags: 0, componentFlagsMask: 0)
    }

    /// An instance for offline rendering (used and released inside the render).
    static func instantiate(_ reference: PluginReference) async throws -> AVAudioUnit {
        let unit: AVAudioUnit
        do { unit = try await AVAudioUnit.instantiate(with: description(reference), options: [.loadOutOfProcess]) }
        catch { throw PluginHostError.unavailable }
        restore(reference, into: unit)
        return unit
    }
    /// An instance for the live engine and the plugin's own screen.
    @MainActor static func instantiateLive(_ reference: PluginReference) async throws -> AVAudioUnit {
        let unit: AVAudioUnit
        do { unit = try await AVAudioUnit.instantiate(with: description(reference), options: [.loadOutOfProcess]) }
        catch { throw PluginHostError.unavailable }
        restore(reference, into: unit)
        return unit
    }
    private static func restore(_ reference: PluginReference, into unit: AVAudioUnit) {
        if let state = reference.state,
           let plist = try? PropertyListSerialization.propertyList(from: state, options: [], format: nil) as? [String: Any] {
            unit.auAudioUnit.fullState = plist
        }
    }

    /// The unit's current settings to save in the song (nil when it has none or they are too big).
    static func state(of unit: AVAudioUnit) -> Data? {
        guard let state = unit.auAudioUnit.fullState,
              let data = try? PropertyListSerialization.data(fromPropertyList: state, format: .binary, options: 0),
              data.count <= PluginReference.maximumState else { return nil }
        return data
    }

    /// Plays `notes` through an instrument plugin offline, sample-accurately, and returns the
    /// mono mix at `rate` (the take an audio track plays).
    static func bounce(_ reference: PluginReference, notes: [PluginEditing.BounceNote], seconds: Double, rate: Double = 48000,
                       progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> [Float] {
        guard seconds.isFinite, seconds > 0, seconds <= 160 else { throw PluginHostError.tooLong }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) else { throw PluginHostError.render }
        let engine = AVAudioEngine()
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 512)
        let unit = try await instantiate(reference)
        engine.attach(unit)
        engine.connect(unit, to: engine.mainMixerNode, format: format)
        try engine.start()
        defer { engine.stop() }
        guard let schedule = unit.auAudioUnit.scheduleMIDIEventBlock,
              let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 512) else { throw PluginHostError.render }
        // Note-ons and note-offs at their sample positions (offs first at the same sample).
        var events: [(frame: Int64, off: Bool, bytes: [UInt8])] = []
        for note in notes {
            let pitch = UInt8(max(0, min(127, note.pitch))), velocity = UInt8(max(1, min(127, note.velocity)))
            events.append((Int64((note.start * rate).rounded()), false, [0x90, pitch, velocity]))
            events.append((Int64((note.end * rate).rounded()), true, [0x80, pitch, 0]))
        }
        events.sort { ($0.frame, $0.off ? 0 : 1) < ($1.frame, $1.off ? 0 : 1) }
        let total = Int64((seconds * rate).rounded())
        var output: [Float] = []; output.reserveCapacity(Int(total))
        var cursor = 0, position: Int64 = 0
        while position < total {
            try Task.checkCancellation()
            let frames = min(512, total - position)
            while cursor < events.count, events[cursor].frame < position + frames {
                let event = events[cursor]
                let offset = max(0, event.frame - position)
                event.bytes.withUnsafeBufferPointer { schedule(AUEventSampleTimeImmediate + offset, 0, event.bytes.count, $0.baseAddress!) }
                cursor += 1
            }
            guard try engine.renderOffline(AVAudioFrameCount(frames), to: buffer) == .success, let channels = buffer.floatChannelData else { throw PluginHostError.render }
            let count = Int(buffer.frameLength)
            let left = channels[0], right = buffer.format.channelCount > 1 ? channels[1] : channels[0]
            for index in 0..<count {
                let value = (left[index] + right[index]) * 0.5
                output.append(value.isFinite ? max(-1, min(1, value)) : 0)
            }
            position += frames
            if position % 48000 < 512 { progress(Double(position) / Double(total)) }
        }
        return output
    }

    /// Runs a rendered mix through effect plugins offline, replacing the file.
    static func process(_ url: URL, through references: [PluginReference]) async throws {
        guard !references.isEmpty else { return }
        let input = try AVAudioFile(forReading: url)
        let format = input.processingFormat
        let engine = AVAudioEngine()
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        let player = AVAudioPlayerNode()
        engine.attach(player)
        var previous: AVAudioNode = player
        for reference in references {
            let unit = try await instantiate(reference)
            engine.attach(unit); engine.connect(previous, to: unit, format: format); previous = unit
        }
        engine.connect(previous, to: engine.mainMixerNode, format: format)
        try engine.start()
        defer { player.stop(); engine.stop() }
        player.scheduleFile(input, at: nil)
        player.play()
        let processed = url.deletingLastPathComponent().appendingPathComponent("effects-\(UUID().uuidString).wav")
        let output = try AVAudioFile(forWriting: processed, settings: input.fileFormat.settings, commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096) else { throw PluginHostError.render }
        var stalls = 0
        while engine.manualRenderingSampleTime < input.length {
            try Task.checkCancellation()
            let frames = AVAudioFrameCount(min(4096, input.length - engine.manualRenderingSampleTime))
            switch try engine.renderOffline(frames, to: buffer) {
            case .success: try output.write(from: buffer); stalls = 0
            case .insufficientDataFromInputNode, .cannotDoInCurrentContext:
                stalls += 1
                guard stalls < 100 else { throw PluginHostError.render }
            case .error: throw PluginHostError.render
            @unknown default: throw PluginHostError.render
            }
        }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: processed)
    }
}
