import Foundation
import AudioDSP

/// 54 · A track of recorded audio (voice, guitar, anything from the microphone) that plays with
/// the song. Takes are the project's audio assets; clips place part of a take on the timeline.
public struct AudioTrack: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID = UUID()
    public var name: String
    public var gain: Double = -6
    public var pan: Double = 0
    public var mute = false
    public var solo = false
    public var color: Int?
    public var clips: [AudioClip] = []
    public init(name: String) { self.name = String(name.prefix(40)) }
}

/// 54 · Part of a recorded take at a song position. `offset` and `duration` are seconds of the
/// take: trimming the start moves `offset`, trimming the end shortens `duration`. The take keeps
/// its recorded speed if the tempo changes.
public struct AudioClip: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID = UUID()
    public var assetID: UUID
    public var start: Int
    public var offset: Double
    public var duration: Double
    /// Clip gain in dB (−60…12).
    public var gain: Double = 0
    public var fadeIn: Double = 0
    public var fadeOut: Double = 0
    public init(assetID: UUID, start: Int, offset: Double, duration: Double) {
        self.assetID = assetID; self.start = start; self.offset = offset; self.duration = duration
    }
    /// Where the clip ends at `bpm`, in ticks.
    public func end(bpm: Double) -> Int { start + AudioTrackEditing.ticks(seconds: duration, bpm: bpm) }
}

extension Project {
    /// Schema written by songs that contain audio tracks; older apps then refuse them safely
    /// instead of opening them without their recordings.
    public static let audioSchemaVersion = 16
    /// The newest schema this app reads.
    public static let newestSchemaVersion = audioSchemaVersion
    public var hasAudioTracks: Bool { !(audioTracks ?? []).isEmpty }
    /// The schema this song must carry: 16 with audio tracks, else the current one.
    public var requiredSchemaVersion: Int { hasAudioTracks ? Project.audioSchemaVersion : Project.currentSchemaVersion }
}

public enum AudioTrackError: Error, LocalizedError, Equatable {
    case tooManyTracks, tooManyClips, missingTake, outsideTake, outsideSong, tooManyTakes
    public var errorDescription: String? {
        let key = switch self {
        case .tooManyTracks: "A song can have up to four audio tracks."
        case .tooManyClips: "An audio track can hold up to 64 clips. Delete a few takes first."
        case .missingTake: "This recording is no longer in the song."
        case .outsideTake: "The clip would go past the end of its recording."
        case .outsideSong: "The clip would start outside the song."
        case .tooManyTakes: "The song has as many recordings as it can keep. Delete takes you do not use."
        }
        return NSLocalizedString(key, comment: "Audio track")
    }
}

public enum AudioTrackEditing {
    public static let maximumTracks = 4
    public static let maximumClips = 64
    /// Recordings per song (takes for audio tracks and voice-to-MIDI sources together).
    public static let maximumTakes = 24

    public static func ticks(seconds: Double, bpm: Double) -> Int { Int((seconds * bpm / 60 * Double(ppq)).rounded()) }
    public static func seconds(ticks: Int, bpm: Double) -> Double { Double(ticks) / Double(ppq) * 60 / bpm }

    /// Keeps the schema in step with the content: 16 with audio tracks, the current one without.
    public static func normalize(_ project: inout Project) {
        if project.audioTracks?.isEmpty == true { project.audioTracks = nil }
        project.schemaVersion = project.requiredSchemaVersion
    }

    @discardableResult
    public static func addTrack(named name: String, to project: inout Project) throws -> UUID {
        var tracks = project.audioTracks ?? []
        guard tracks.count < maximumTracks else { throw AudioTrackError.tooManyTracks }
        let track = AudioTrack(name: name)
        tracks.append(track)
        project.audioTracks = tracks
        normalize(&project)
        return track.id
    }

    /// Removes the track and every recording no clip or melody uses any more.
    public static func removeTrack(_ id: UUID, from project: inout Project) {
        project.audioTracks?.removeAll { $0.id == id }
        normalize(&project)
        removeUnusedTakes(&project)
    }

    /// Places a finished recording on a track. `startTick` is where the take began on the
    /// timeline; `latency` seconds at its start (the input delay) are skipped so it lines up
    /// with what was heard.
    @discardableResult
    public static func place(_ record: AudioAssetRecord, on trackID: UUID, at startTick: Int, latency: Double, in project: inout Project) throws -> UUID {
        guard let track = project.audioTracks?.firstIndex(where: { $0.id == trackID }) else { throw AudioTrackError.missingTake }
        guard project.audioTracks![track].clips.count < maximumClips else { throw AudioTrackError.tooManyClips }
        var assets = project.audioAssets ?? []
        if !assets.contains(where: { $0.id == record.id }) {
            guard assets.count < maximumTakes else { throw AudioTrackError.tooManyTakes }
            assets.append(record)
        }
        let skip = min(max(0, latency.isFinite ? latency : 0), max(0, record.duration - 0.05))
        guard startTick >= 0, startTick < project.length else { throw AudioTrackError.outsideSong }
        let clip = AudioClip(assetID: record.id, start: startTick, offset: skip, duration: record.duration - skip)
        project.audioAssets = assets
        project.audioTracks![track].clips.append(clip)
        project.audioTracks![track].clips.sort { $0.start < $1.start }
        normalize(&project)
        return clip.id
    }

    private static func locate(_ clipID: UUID, in project: Project) -> (track: Int, clip: Int)? {
        for (t, track) in (project.audioTracks ?? []).enumerated() {
            if let c = track.clips.firstIndex(where: { $0.id == clipID }) { return (t, c) }
        }
        return nil
    }

    private static func update(_ clipID: UUID, in project: inout Project, _ change: (inout AudioClip, AudioAssetRecord) throws -> Void) throws {
        guard let at = locate(clipID, in: project) else { throw AudioTrackError.missingTake }
        var clip = project.audioTracks![at.track].clips[at.clip]
        guard let record = project.audioAssets?.first(where: { $0.id == clip.assetID }) else { throw AudioTrackError.missingTake }
        try change(&clip, record)
        guard clip.start >= 0, clip.start < project.length else { throw AudioTrackError.outsideSong }
        guard clip.offset >= 0, clip.duration >= 0.05, clip.offset + clip.duration <= record.duration + 0.0005 else { throw AudioTrackError.outsideTake }
        clip.fadeIn = min(clip.fadeIn, clip.duration / 2); clip.fadeOut = min(clip.fadeOut, clip.duration / 2)
        project.audioTracks![at.track].clips[at.clip] = clip
        project.audioTracks![at.track].clips.sort { $0.start < $1.start }
    }

    /// Moves a clip by `ticks` (snap to bars or beats in the interface).
    public static func move(_ clipID: UUID, by ticks: Int, in project: inout Project) throws {
        try update(clipID, in: &project) { clip, _ in clip.start += ticks }
    }

    /// Trims the start: positive cuts the beginning (the rest stays where it was heard).
    public static func trimStart(_ clipID: UUID, by seconds: Double, in project: inout Project) throws {
        let bpm = project.bpm
        try update(clipID, in: &project) { clip, _ in
            let shift = max(-clip.offset, min(seconds, clip.duration - 0.05))
            clip.offset += shift; clip.duration -= shift
            clip.start += ticks(seconds: shift, bpm: bpm)
        }
    }

    /// Trims the end: positive makes the clip shorter, negative longer (up to the take's end).
    public static func trimEnd(_ clipID: UUID, by seconds: Double, in project: inout Project) throws {
        try update(clipID, in: &project) { clip, record in
            clip.duration = max(0.05, min(record.duration - clip.offset, clip.duration - seconds))
        }
    }

    public static func setGain(_ clipID: UUID, to decibels: Double, in project: inout Project) throws {
        try update(clipID, in: &project) { clip, _ in clip.gain = max(-60, min(12, decibels.isFinite ? decibels : 0)) }
    }

    public static func setFades(_ clipID: UUID, fadeIn: Double, fadeOut: Double, in project: inout Project) throws {
        try update(clipID, in: &project) { clip, _ in clip.fadeIn = max(0, fadeIn.isFinite ? fadeIn : 0); clip.fadeOut = max(0, fadeOut.isFinite ? fadeOut : 0) }
    }

    /// A copy of the clip `ticks` later (same take, no new recording).
    @discardableResult
    public static func duplicate(_ clipID: UUID, by ticks: Int, in project: inout Project) throws -> UUID {
        guard let at = locate(clipID, in: project) else { throw AudioTrackError.missingTake }
        guard project.audioTracks![at.track].clips.count < maximumClips else { throw AudioTrackError.tooManyClips }
        var copy = project.audioTracks![at.track].clips[at.clip]
        copy.id = UUID(); copy.start += ticks
        guard copy.start >= 0, copy.start < project.length else { throw AudioTrackError.outsideSong }
        project.audioTracks![at.track].clips.append(copy)
        project.audioTracks![at.track].clips.sort { $0.start < $1.start }
        return copy.id
    }

    public static func delete(_ clipID: UUID, from project: inout Project) {
        guard let at = locate(clipID, in: project) else { return }
        project.audioTracks![at.track].clips.remove(at: at.clip)
        removeUnusedTakes(&project)
    }

    /// Recordings that no audio clip and no melody (voice-to-MIDI source) refer to are dropped.
    public static func removeUnusedTakes(_ project: inout Project) {
        var used = Set((project.audioTracks ?? []).flatMap { $0.clips.map(\.assetID) })
        for track in project.tracks { for clip in track.clips { if let source = clip.sourceAssetID { used.insert(source) } } }
        for take in project.performanceTakes ?? [] { used.formUnion((take.source.audioAssets ?? []).map(\.id)) }
        project.audioAssets = project.audioAssets?.filter { used.contains($0.id) }
        if project.audioAssets?.isEmpty == true { project.audioAssets = nil }
    }

    public static func setMix(_ trackID: UUID, gain: Double? = nil, pan: Double? = nil, mute: Bool? = nil, solo: Bool? = nil, in project: inout Project) {
        guard let index = project.audioTracks?.firstIndex(where: { $0.id == trackID }) else { return }
        if let gain, gain.isFinite { project.audioTracks![index].gain = max(-61, min(6, gain)) }
        if let pan, pan.isFinite { project.audioTracks![index].pan = max(-1, min(1, pan)) }
        if let mute { project.audioTracks![index].mute = mute }
        if let solo { project.audioTracks![index].solo = solo }
    }

    /// A track is heard unless muted, or when another track (MIDI or audio) is soloed.
    public static func audible(_ track: AudioTrack, in project: Project) -> Bool {
        let anySolo = project.tracks.contains(where: \.solo) || (project.audioTracks ?? []).contains(where: \.solo)
        return !track.mute && (!anySolo || track.solo)
    }

    /// What the kernel plays for `range` (ticks relative to its start). A clip starting before
    /// the range begins later in its take.
    public struct KernelClip: Equatable, Sendable {
        public let lane: Int
        public let assetID: UUID
        public let startTick: Double, endTick: Double, offset: Double
        public let gain: Double, fadeIn: Double, fadeOut: Double
    }

    public static func kernelClips(_ project: Project, range: Range<Int>? = nil) -> [KernelClip] {
        let range = range ?? 0..<project.length
        var result: [KernelClip] = []
        for (lane, track) in (project.audioTracks ?? []).prefix(maximumTracks).enumerated() {
            for clip in track.clips {
                let start = clip.start, end = clip.end(bpm: project.bpm)
                guard end > range.lowerBound, start < range.upperBound else { continue }
                let from = max(start, range.lowerBound), to = min(end, range.upperBound)
                let skipped = seconds(ticks: from - start, bpm: project.bpm)
                result.append(KernelClip(lane: lane, assetID: clip.assetID, startTick: Double(from - range.lowerBound), endTick: Double(to - range.lowerBound),
                                         offset: clip.offset + skipped, gain: clip.gain,
                                         fadeIn: from == start ? clip.fadeIn : 0, fadeOut: to == end ? clip.fadeOut : 0))
            }
        }
        return result
    }

    public static func validate(_ project: Project) throws {
        guard let tracks = project.audioTracks else { return }
        guard !tracks.isEmpty, tracks.count <= maximumTracks, Set(tracks.map(\.id)).count == tracks.count else { throw MusicError.invalidProject }
        let assets = Dictionary((project.audioAssets ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for track in tracks {
            guard !track.name.isEmpty, track.name.count <= 40, track.gain.isFinite, (-61...6).contains(track.gain), track.pan.isFinite, (-1...1).contains(track.pan),
                  track.clips.count <= maximumClips, Set(track.clips.map(\.id)).count == track.clips.count, track.color.map({ (0..<6).contains($0) }) ?? true else { throw MusicError.invalidProject }
            for clip in track.clips {
                guard let record = assets[clip.assetID], clip.start >= 0, clip.start < project.length,
                      clip.offset.isFinite, clip.offset >= 0, clip.duration.isFinite, clip.duration >= 0.05, clip.offset + clip.duration <= record.duration + 0.001,
                      clip.gain.isFinite, (-60...12).contains(clip.gain), clip.fadeIn.isFinite, clip.fadeOut.isFinite, clip.fadeIn >= 0, clip.fadeOut >= 0,
                      clip.fadeIn + clip.fadeOut <= clip.duration + 0.001 else { throw MusicError.invalidProject }
            }
        }
    }
}

/// 54 · Mono float samples of a stored take (CAF, 32-bit float, either byte order).
public enum AudioTakeReader {
    public static func samples(_ data: Data) throws -> (samples: [Float], rate: Double) {
        let bytes = [UInt8](data)
        guard bytes.count >= 8, Array(bytes[0..<4]) == Array("caff".utf8) else { throw ExportError.invalidArchive }
        func integer(_ position: Int, _ count: Int) throws -> UInt64 {
            guard position >= 0, position + count <= bytes.count else { throw ExportError.invalidArchive }
            return bytes[position..<position + count].reduce(0) { ($0 << 8) | UInt64($1) }
        }
        var cursor = 8, rate = 0.0, little = false, found = false
        var samples: [Float] = []
        for _ in 0..<64 where cursor + 12 <= bytes.count {
            let name = String(bytes: bytes[cursor..<cursor + 4], encoding: .ascii) ?? ""
            let raw = try integer(cursor + 4, 8)
            let size = (raw == UInt64.max && name == "data") ? UInt64(bytes.count - cursor - 12) : raw
            guard size <= UInt64(bytes.count - cursor - 12) else { throw ExportError.invalidArchive }
            let start = cursor + 12
            if name == "desc" {
                guard size == 32, Array(bytes[start + 8..<start + 12]) == Array("lpcm".utf8) else { throw ExportError.invalidArchive }
                rate = Double(bitPattern: try integer(start, 8))
                let flags = try integer(start + 12, 4)
                guard flags & 1 == 1, try integer(start + 24, 4) == 1, try integer(start + 28, 4) == 32 else { throw ExportError.invalidArchive }
                little = flags & 2 == 2
            }
            if name == "data" {
                let count = (Int(size) - 4) / 4
                guard count > 0 else { throw ExportError.invalidArchive }
                samples.reserveCapacity(count)
                for index in 0..<count {
                    let p = start + 4 + index * 4
                    let word = little ? UInt32(bytes[p]) | UInt32(bytes[p + 1]) << 8 | UInt32(bytes[p + 2]) << 16 | UInt32(bytes[p + 3]) << 24
                                      : UInt32(bytes[p]) << 24 | UInt32(bytes[p + 1]) << 16 | UInt32(bytes[p + 2]) << 8 | UInt32(bytes[p + 3])
                    let value = Float(bitPattern: word)
                    samples.append(value.isFinite ? max(-1, min(1, value)) : 0)
                }
                found = true
            }
            cursor = start + Int(size)
        }
        guard found, rate.isFinite, (8000...192000).contains(rate) else { throw ExportError.invalidArchive }
        return (samples, rate)
    }

    /// A mono 32-bit float CAF (little-endian), for tests and fixtures.
    public static func caf(_ samples: [Float], rate: Double) -> Data {
        var data = Data("caff".utf8); data += [0, 1, 0, 0]
        func be64(_ v: UInt64) -> [UInt8] { (0..<8).map { UInt8((v >> (56 - 8 * UInt64($0))) & 0xFF) } }
        func be32(_ v: UInt32) -> [UInt8] { (0..<4).map { UInt8((v >> (24 - 8 * UInt32($0))) & 0xFF) } }
        data += Array("desc".utf8) + be64(32) + be64(rate.bitPattern) + Array("lpcm".utf8) + be32(3) + be32(4) + be32(1) + be32(1) + be32(32)
        data += Array("data".utf8) + be64(UInt64(4 + samples.count * 4)) + [0, 0, 0, 0]
        for value in samples { let bits = value.bitPattern; data += [UInt8(bits & 0xFF), UInt8(bits >> 8 & 0xFF), UInt8(bits >> 16 & 0xFF), UInt8(bits >> 24)] }
        return data
    }
}

/// 54 · Decoded takes used to render audio tracks (offline exports and the live engine).
public struct AudioTakeLibrary: Sendable {
    public struct Take: Sendable { public let samples: [Float]; public let rate: Double }
    public private(set) var takes: [UUID: Take] = [:]
    public init() {}
    public mutating func insert(_ id: UUID, samples: [Float], rate: Double) { takes[id] = Take(samples: samples, rate: rate) }
    public mutating func retainOnly(_ ids: Set<UUID>) { takes = takes.filter { ids.contains($0.key) } }
    public func contains(_ id: UUID) -> Bool { takes[id] != nil }

    /// Hands the song's audio clips for `range` to `kernel`; a missing take fails rather than
    /// rendering the song without it.
    public static func submit(_ project: Project, range: Range<Int>, kernel: OpaquePointer, takes: AudioTakeLibrary, isolated: UUID?) -> Bool {
        let clips = AudioTrackEditing.kernelClips(project, range: range)
        guard !clips.isEmpty, let tracks = project.audioTracks else { return lg_audio_submit(kernel, nil, nil, 0, nil, 0) == 1 }
        var buffers: [UUID: OpaquePointer] = [:]
        defer { for buffer in buffers.values { lg_audio_release(buffer) } }
        for id in Set(clips.map(\.assetID)) {
            guard let take = takes.takes[id], take.samples.count >= 2,
                  let buffer = take.samples.withUnsafeBufferPointer({ lg_audio_create($0.baseAddress, Int32(clamping: $0.count), Int32(take.rate.rounded())) }) else { return false }
            buffers[id] = buffer
        }
        let lanes = tracks.prefix(AudioTrackEditing.maximumTracks).map { track in
            LGTrackMix(gainDB: Float(track.gain), pan: Float(track.pan),
                       audible: AudioTrackEditing.audible(track, in: project) && (isolated == nil || isolated == track.id) ? 1 : 0)
        }
        let kernelClips = clips.map { LGAudioClip(lane: Int32($0.lane), startTick: $0.startTick, endTick: $0.endTick, offsetSeconds: $0.offset,
                                                  gainDB: Float($0.gain), fadeInSeconds: Float($0.fadeIn), fadeOutSeconds: Float($0.fadeOut)) }
        let pointers: [OpaquePointer?] = clips.map { buffers[$0.assetID] }
        return kernelClips.withUnsafeBufferPointer { clipPointer in
            pointers.withUnsafeBufferPointer { bufferPointer in
                lanes.withUnsafeBufferPointer { lanePointer in
                    lg_audio_submit(kernel, clipPointer.baseAddress, bufferPointer.baseAddress, Int32(kernelClips.count), lanePointer.baseAddress, Int32(lanes.count)) == 1
                }
            }
        }
    }
}
