import Foundation

/// A bounded pass buffer certified once from an immutable, validated draft.
/// Append never copies/compiles/encodes the project. The caller must still use
/// DrumRecordingDraft.commitPass at the boundary; this is not a commit API.
public struct DrumRecordingPass:Sendable {
    public private(set) var events:[DrumEvent]=[]
    public let capacity:Int
    private let length:Int
    private var identifiers:Set<UUID>

    public init(draft:DrumRecordingDraft,replacing absoluteRange:Range<Int>?=nil)throws {
        var baseline=draft.project
        guard let index=baseline.patterns.firstIndex(where:{$0.id==draft.patternID}),
              let track=baseline.tracks.first(where:{$0.id==draft.trackID}),track.role == .drums,
              let clip=track.clips.first(where:{$0.id==draft.clipID}),
              clip.patternID==draft.patternID,clip.start==draft.start,clip.length==draft.length,
              clip.offset==0,clip.length<=baseline.patterns[index].length,
              baseline.tracks.flatMap(\.clips).filter({$0.patternID==draft.patternID}).count==1
        else{throw MusicError.invalidProject}
        if let absoluteRange {
            guard absoluteRange.lowerBound>=0,absoluteRange.upperBound<=64*barTicks else{throw MusicError.invalidProject}
            baseline.patterns[index].drums.removeAll{absoluteRange.contains(draft.start+$0.tick)}
        }
        // Only removing drum events preserves the draft's validated structure.
        // This exact clip has one occurrence: each appended event adds one
        // compiled note and two units to Project.validate's conservative bound.
        var upperBound=0
        for owner in baseline.tracks {for occurrence in owner.clips {
            guard let pattern=baseline.patterns.first(where:{$0.id==occurrence.patternID})else{throw MusicError.invalidProject}
            let voices=pattern.chords.reduce(0){$0+$1.chord.notes.count}
            upperBound+=((occurrence.length+pattern.length-1)/pattern.length+1)*(voices+pattern.drums.count+(pattern.notes ?? []).count)
        }}
        let compiledCount=Compiler.notes(baseline).count
        let bytes=try JSONEncoder().encode(baseline).count
        guard upperBound<=65_536,compiledCount<=32_768,bytes<=8_000_000 else{throw MusicError.tooDense}
        // A valid DrumEvent contains only UUID, tick<=245759, pad<=15 and
        // velocity<=127. Its encoded object plus separator is <128 bytes.
        capacity=max(0,min(4_096-baseline.patterns[index].drums.count,
                           32_768-compiledCount,(65_536-upperBound)/2,(8_000_000-bytes)/128))
        length=draft.length
        var ids=[baseline.id]
        if let take=baseline.performanceTake{ids.append(take.id)}
        ids+=(baseline.audioAssets ?? []).map(\.id)
        ids+=baseline.tracks.map(\.id)+baseline.patterns.map(\.id)+baseline.sections.map(\.id)
        ids+=baseline.tracks.flatMap{$0.clips.map(\.id)}
        for pattern in baseline.patterns {
            ids+=pattern.chords.map(\.id)+pattern.drums.map(\.id)+(pattern.notes ?? []).map(\.id)
        }
        identifiers=Set(ids)
        identifiers.reserveCapacity(identifiers.count+capacity)
        events.reserveCapacity(capacity)
    }

    public mutating func append(_ event:DrumEvent)throws {
        guard event.tick>=0,event.tick<length,(0..<16).contains(event.pad),(1...127).contains(event.velocity),
              !identifiers.contains(event.id)else{throw MusicError.invalidProject}
        guard events.count<capacity else{throw MusicError.tooDense}
        identifiers.insert(event.id)
        events.append(event)
    }
}
