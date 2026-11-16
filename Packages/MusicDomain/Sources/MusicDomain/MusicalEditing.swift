import Foundation

public enum TranspositionError: Error, LocalizedError {
    case range, amount, stale
    public var errorDescription: String? {
        let key = switch self {
        case .range: "Transposition would move notes outside MIDI 0–127. Choose a smaller interval. Nothing was changed."
        case .amount: "Choose a nonzero transposition between −24 and +24 semitones."
        case .stale: "The project changed. Review a new transposition before applying."
        }
        return NSLocalizedString(key, comment:"Arrangement transposition")
    }
}

public struct TranspositionProposal: Sendable {
    public let projectID: UUID
    public let revision: Int
    public let semitones: Int
    public let candidate: Project
    public let noteCount: Int
    public let trackIDs: [UUID]
    public let originalRange: ClosedRange<Int>?
    public let transposedRange: ClosedRange<Int>?

    public func apply(to project: inout Project) throws {
        guard project.id == projectID, project.revision == revision else { throw TranspositionError.stale }
        try candidate.validate()
        project = candidate
    }
}

public enum MusicalEditing {
    /// Editing the symbol keeps the existing bass register when its root and
    /// explicit slash bass have not changed. Re-entering an equivalent symbol
    /// also keeps the existing voicing rather than rebuilding an arbitrary octave.
    public static func rebuildChord(from symbol:String,preserving original:Chord)throws->Chord {
        try original.validate()
        var rebuilt=try Chord.parse(symbol)
        if rebuilt.root==original.root,rebuilt.slashBass==original.slashBass {
            rebuilt.rootBassPitch=original.rootBassPitch
            if rebuilt.quality==original.quality,rebuilt.customIntervals==original.customIntervals {
                rebuilt.inversion=original.inversion
                rebuilt.voicedNotes=original.voicedNotes
            }
        }
        try rebuilt.validate()
        return rebuilt
    }

    /// A value-copy proposal. Event/clip/track IDs, timing, source recordings and
    /// frozen performance sources are preserved; History owns the single Undo.
    public static func transpose(_ project: Project, semitones: Int) throws -> TranspositionProposal {
        try project.validate()
        guard (-24...24).contains(semitones), semitones != 0 else { throw TranspositionError.amount }
        let harmonyIDs = Set(project.tracks.filter{$0.role == .harmony}.flatMap{$0.clips.map(\.patternID)})
        let melodyIDs = Set(project.tracks.filter{$0.role == .melody || $0.role == .bass}.flatMap{$0.clips.map(\.patternID)})
        let hasBass = project.tracks.contains{$0.role == .bass}
        var candidate = project
        func shifted(_ pitch:Int)throws->Int {
            let result = pitch+semitones
            guard (0...127).contains(result) else { throw TranspositionError.range }
            return result
        }
        for index in candidate.patterns.indices {
            let patternID = candidate.patterns[index].id
            if harmonyIDs.contains(patternID) {
                for eventIndex in candidate.patterns[index].chords.indices {
                    let original = project.patterns[index].chords[eventIndex].chord
                    var chord = original
                    // Explicit voicing retains the exact interval across B/C;
                    // rebuilding a default root position would change octaves.
                    let notes = try original.notes.map(shifted)
                    // A chromatic interval does not specify a new written
                    // letter. Changed pitch classes clear their old spelling;
                    // Auto then uses the new key. Octave shifts retain writing.
                    chord.root = (original.root+semitones%12+12)%12
                    chord.slashBass = original.slashBass.map{($0+semitones%12+12)%12}
                    chord.voicedNotes = notes
                    if hasBass || original.rootBassPitch != nil { chord.rootBassPitch = try shifted(Compiler.bassPitch(for:original,register:project.bassOctave)) }
                    try chord.validate()
                    candidate.patterns[index].chords[eventIndex].chord = chord
                }
            }
            if melodyIDs.contains(patternID), let notes = candidate.patterns[index].notes {
                candidate.patterns[index].notes = try notes.map { value in
                    var note = value; note.pitch = try shifted(value.pitch); return note
                }
            }
        }
        candidate.keyRoot = (project.keyRoot+semitones%12+12)%12
        try candidate.validate()
        let before = Compiler.notes(project).filter{project.tracks[$0.track].role != .drums}
        let after = Compiler.notes(candidate).filter{candidate.tracks[$0.track].role != .drums}
        guard after.allSatisfy({(0...127).contains($0.pitch)}) else { throw TranspositionError.range }
        let played = Set(before.map{project.tracks[$0.track].id})
        func range(_ notes:[CompiledNote])->ClosedRange<Int>? {
            guard let low=notes.map(\.pitch).min(),let high=notes.map(\.pitch).max() else{return nil}
            return low...high
        }
        return TranspositionProposal(projectID:project.id,revision:project.revision,semitones:semitones,candidate:candidate,noteCount:before.count,trackIDs:project.tracks.filter{played.contains($0.id)}.map(\.id),originalRange:range(before),transposedRange:range(after))
    }

    /// Register still changes an already-transposed root bass by whole octaves.
    /// Reject atomically rather than clipping an explicit bass note at MIDI limits.
    public static func setBassRegister(_ register:Int, in project:inout Project)throws {
        try project.validate()
        guard (-1...1).contains(register) else { throw TranspositionError.range }
        var candidate=project
        let delta=(register-project.bassOctave)*12
        for i in candidate.patterns.indices {
            for j in candidate.patterns[i].chords.indices {
                if let pitch=candidate.patterns[i].chords[j].chord.rootBassPitch {
                    let shifted=pitch+delta
                    guard (0...127).contains(shifted) else{throw TranspositionError.range}
                    candidate.patterns[i].chords[j].chord.rootBassPitch=shifted
                }
            }
        }
        candidate.bassOctave=register
        try candidate.validate()
        project=candidate
    }
}
