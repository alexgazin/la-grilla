import Foundation

/// 54 · An Audio Unit (AUv3) the song uses: which component, what it was called and its saved
/// settings. The app instantiates it; the song only remembers it.
public struct PluginReference: Codable, Equatable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case instrument, effect }
    public var id: UUID = UUID()
    public var kind: Kind
    /// Four-character codes of the component description.
    public var type: UInt32, subtype: UInt32, manufacturer: UInt32
    public var name: String
    public var maker: String
    /// The unit's full state as a property list (`AUAudioUnit.fullState`), at most 2 MB.
    public var state: Data?
    public var bypassed: Bool?
    public init(kind: Kind, type: UInt32, subtype: UInt32, manufacturer: UInt32, name: String, maker: String, state: Data? = nil) {
        self.kind = kind; self.type = type; self.subtype = subtype; self.manufacturer = manufacturer
        self.name = String(name.prefix(80)); self.maker = String(maker.prefix(80)); self.state = state
    }
    public static let maximumState = 2_000_000

    public func validate() throws {
        guard !name.isEmpty, name.count <= 80, maker.count <= 80, (state?.count ?? 0) <= Self.maximumState, type != 0, subtype != 0 else { throw MusicError.invalidProject }
    }

    /// "aumu", "aufx", … from a four-character code.
    public static func fourCC(_ value: UInt32) -> String {
        String(bytes: [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)], encoding: .ascii) ?? "????"
    }
    public static func fourCC(_ text: String) -> UInt32 {
        text.utf8.prefix(4).reduce(0) { $0 << 8 | UInt32($1) }
    }
    /// The same component regardless of saved settings.
    public func sameUnit(as other: PluginReference) -> Bool { type == other.type && subtype == other.subtype && manufacturer == other.manufacturer }
}

/// 54 · An audio track made by playing a MIDI track through an instrument plugin. Its notes stay
/// on the original track; after editing them, "Bounce again" renders a new take.
public struct PluginBounce: Codable, Equatable, Sendable {
    public var sourceTrack: UUID
    public var plugin: PluginReference
    public init(sourceTrack: UUID, plugin: PluginReference) { self.sourceTrack = sourceTrack; self.plugin = plugin }
}

public enum PluginEditing {
    /// Effect plugins after the whole mix (live and in exports).
    public static let maximumMasterEffects = 2

    public static func addMasterEffect(_ plugin: PluginReference, to project: inout Project) throws {
        guard plugin.kind == .effect else { throw MusicError.invalidProject }
        try plugin.validate()
        var effects = project.masterPlugins ?? []
        guard effects.count < maximumMasterEffects else { throw MusicError.limit }
        effects.append(plugin)
        project.masterPlugins = effects
    }

    public static func removeMasterEffect(_ id: UUID, from project: inout Project) {
        project.masterPlugins?.removeAll { $0.id == id }
        if project.masterPlugins?.isEmpty == true { project.masterPlugins = nil }
    }

    public static func setState(_ state: Data?, of id: UUID, in project: inout Project) throws {
        guard (state?.count ?? 0) <= PluginReference.maximumState else { throw MusicError.limit }
        if let index = project.masterPlugins?.firstIndex(where: { $0.id == id }) { project.masterPlugins![index].state = state; return }
        for t in (project.audioTracks ?? []).indices where project.audioTracks![t].bounce?.plugin.id == id { project.audioTracks![t].bounce!.plugin.state = state }
    }

    public static func setBypassed(_ bypassed: Bool, of id: UUID, in project: inout Project) {
        guard let index = project.masterPlugins?.firstIndex(where: { $0.id == id }) else { return }
        project.masterPlugins![index].bypassed = bypassed ? true : nil
    }

    /// Effects that process the mix (bypassed ones are skipped).
    public static func activeMasterEffects(_ project: Project) -> [PluginReference] { (project.masterPlugins ?? []).filter { $0.bypassed != true } }

    /// The source notes for a bounce: one track's notes over the song, in seconds at the tempo.
    public struct BounceNote: Equatable, Sendable { public let start: Double, end: Double; public let pitch: Int, velocity: Int }
    public static func bounceNotes(_ project: Project, track trackID: UUID) -> [BounceNote] {
        guard let index = project.tracks.firstIndex(where: { $0.id == trackID }) else { return [] }
        let secondsPerTick = 60 / (project.bpm * Double(ppq))
        return Compiler.notes(project).filter { $0.track == index && $0.pad < 0 }
            .map { BounceNote(start: Double($0.tick) * secondsPerTick, end: Double($0.tick + $0.duration) * secondsPerTick, pitch: $0.pitch, velocity: $0.velocity) }
            .sorted { ($0.start, $0.pitch) < ($1.start, $1.pitch) }
    }

    /// Puts a rendered take on an audio track tied to its source (replacing the previous bounce
    /// of the same source) and mutes the source so it is not heard twice.
    @discardableResult
    public static func placeBounce(_ record: AudioAssetRecord, source: UUID, plugin: PluginReference, in project: inout Project) throws -> UUID {
        guard let sourceIndex = project.tracks.firstIndex(where: { $0.id == source }) else { throw MusicError.invalidProject }
        let trackID: UUID
        if let existing = project.audioTracks?.first(where: { $0.bounce?.sourceTrack == source }) {
            trackID = existing.id
            let index = project.audioTracks!.firstIndex { $0.id == trackID }!
            project.audioTracks![index].clips = []
            project.audioTracks![index].bounce = PluginBounce(sourceTrack: source, plugin: plugin)
        } else {
            trackID = try AudioTrackEditing.addTrack(named: project.tracks[sourceIndex].displayName + " · " + plugin.name, to: &project)
            let index = project.audioTracks!.firstIndex { $0.id == trackID }!
            project.audioTracks![index].bounce = PluginBounce(sourceTrack: source, plugin: plugin)
        }
        AudioTrackEditing.removeUnusedTakes(&project)
        try AudioTrackEditing.place(record, on: trackID, at: 0, latency: 0, in: &project)
        project.tracks[sourceIndex].mute = true
        return trackID
    }
}
