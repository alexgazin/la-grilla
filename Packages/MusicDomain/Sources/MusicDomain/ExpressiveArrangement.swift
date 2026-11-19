import Foundation

public enum ArrangerTimbre: String, Hashable, Sendable {
    case piano, flute, bansuri, gong, ambientPad
}

public enum ExpressiveArrangement {
    /// Track IDs keep sample assignments independent of the device language and user-facing names.
    public static func instruments(form: SongFormBrief, project: Project) -> [UUID: ArrangerTimbre] {
        let layout: [ArrangerTimbre?]
        switch form.arrangement {
        case .groove: return [:]
        case .chillhop: layout = [.piano, nil, nil, .flute, .piano, .gong]
        case .ambient:
            layout = form.longDelay ? [.ambientPad, nil, .bansuri, .piano, .bansuri, .piano] : [.ambientPad, nil, .bansuri, .piano]
        }
        guard project.tracks.count == layout.count else { return [:] }
        return Dictionary(uniqueKeysWithValues: zip(project.tracks, layout).compactMap { track, voice in
            guard !track.clips.isEmpty, let voice else { return nil }
            return (track.id, voice)
        })
    }

    static func make(form: SongFormBrief, brief: TrackBrief, name: String) throws -> Project {
        try form.validate()
        var score = Project(name: name, bars: form.totalBars)
        score.bpm = Double(brief.tempo)
        score.keyRoot = brief.root
        score.minor = brief.minor
        score.sections = []
        score.patterns = []
        switch form.arrangement {
        case .groove: return try GrooveArrangement.make(form: form, brief: brief, name: name)
        case .chillhop:
            score.tracks = [
                track(.harmony, "Piano", -5), track(.drums, "Drums", -5), track(.melody, "Bass", -4),
                track(.melody, "Flute", -5), track(.melody, "Piano arpeggio", -4), track(.melody, "Gong", -4)
            ]
        case .ambient:
            score.tracks = [track(.harmony, "Ambient pad", -6), track(.drums, "Drums", -6),
                            track(.melody, "Bansuri", -3), track(.melody, "Keys", -7)]
            if form.longDelay {
                score.masterFX = MasterFX(delayWet: 0.20)
                score.tracks += [track(.melody, "Flute echo", -13, pan: 0.47), track(.melody, "Piano echo", -13, pan: -0.38)]
            }
        }

        var cursor = 0
        var echoNotes = [[NoteEvent](), [NoteEvent]()]
        for source in form.order {
            let part = form.parts[source]
            let length = part.bars * barTicks
            let cycle = try form.resolvedChords(for: source)
            var patterns = score.tracks.map { _ in Pattern(length: length) }
            switch part.role {
            case .fluteIntro:
                patterns[3].notes = fluteIntro(brief: brief, bars: part.bars)
            case .developingBeat, .arpeggio:
                try groove(part: part, cycle: cycle, brief: brief, patterns: &patterns)
            case .gong:
                patterns[5].notes = [NoteEvent(tick: 0, duration: length, pitch: 60, velocity: 108)]
            case .ambientIntro, .bansuriSolo, .keysOutro:
                try ambient(part: part, cycle: cycle, fadeBars: form.fadeBars, seed: brief.seed, patterns: &patterns)
                if form.longDelay {
                    for (slot, index) in [2, 3].enumerated() {
                        for note in patterns[index].notes ?? [] {
                            echoNotes[slot] += echoes(of: note, at: cursor, songEnd: form.totalBars * barTicks)
                        }
                    }
                }
            case .groove: throw SongFormError.unsupported
            }
            score.sections.append(Section(name: title(for: part.role), start: cursor, length: length))
            for (trackIndex, pattern) in patterns.enumerated() where !pattern.chords.isEmpty || !pattern.drums.isEmpty || !(pattern.notes ?? []).isEmpty {
                append(pattern, at: cursor, trackIndex: trackIndex, to: &score)
            }
            cursor += length
        }
        if form.arrangement == .ambient, form.longDelay {
            for (slot, delayed) in echoNotes.enumerated() {
                appendEchoes(delayed, trackIndex: 4+slot, to: &score)
            }
        }
        try score.validate()
        return score
    }

    /// Let a response finish across a section cut. Close its clip at the next gap,
    /// keeping patterns local for section edits and avoiding a second MIDI attack.
    private static func appendEchoes(_ delayed: [NoteEvent], trackIndex: Int, to score: inout Project) {
        let notes = delayed.sorted { $0.tick < $1.tick }
        var first = 0
        while first < notes.count {
            let start = notes[first].tick
            guard let section = score.sections.last(where: { $0.start <= start }) else { return }
            var last = first+1
            var end = notes[first].tick + notes[first].duration
            while last < notes.count && (notes[last].tick < section.start+section.length || notes[last].tick < end) {
                end = max(end, notes[last].tick + notes[last].duration)
                last += 1
            }
            let span = end-start
            let shifted = notes[first..<last].map { source in
                NoteEvent(tick: source.tick-start, duration: source.duration, pitch: source.pitch, velocity: source.velocity)
            }
            let pattern = Pattern(length: ((span+barTicks-1)/barTicks)*barTicks, notes: shifted)
            score.patterns.append(pattern)
            score.tracks[trackIndex].clips.append(Clip(patternID: pattern.id, start: start, length: span))
            first = last
        }
    }

    private static func track(_ role: TrackRole, _ name: String, _ gain: Double, pan: Double = 0) -> Track {
        var track = Track(role: role)
        track.name = NSLocalizedString(name, comment: "Generated instrument")
        track.gain = gain
        track.pan = pan
        track.presetVersion = SoundPalette.warm.rawValue
        return track
    }

    private static func title(for role: SongFormBrief.Role) -> String {
        let title: String
        switch role {
        case .fluteIntro: title = "Flute intro"
        case .developingBeat: title = "Main groove"
        case .arpeggio: title = "Arpeggio"
        case .gong: title = "Gong"
        case .ambientIntro: title = "Ambient intro"
        case .bansuriSolo: title = "Bansuri solo"
        case .keysOutro: title = "Closing keys"
        case .groove: title = "Groove"
        }
        return NSLocalizedString(title, comment: "Generated section")
    }

    private static func append(_ pattern: Pattern, at start: Int, trackIndex: Int, to score: inout Project) {
        score.patterns.append(pattern)
        score.tracks[trackIndex].clips.append(Clip(patternID: pattern.id, start: start, length: pattern.length))
    }

    private static func fluteIntro(brief: TrackBrief, bars: Int) -> [NoteEvent] {
        let third = brief.minor ? 3 : 4
        let variants = [[0, third, 5, third, 7], [7, 5, third, 2, 0], [third, 2, 0, 5, 7]]
        let rhythm = [(0, 650), (840, 430), (1440, 380), (1930, 540), (2640, 780)]
        return (0..<bars).flatMap { bar in
            let steps = variants[(Int(brief.seed % 3) + bar) % variants.count]
            return zip(rhythm, steps).map { value, step in
                NoteEvent(tick: bar*barTicks + value.0, duration: value.1,
                          pitch: 72 + brief.root + step, velocity: value.0 == 0 ? 91 : 78)
            }
        }
    }

    /// Compress onto the eighth-note grid when an edited section is shorter than its progression.
    /// Longer chillhop parts repeat their cycle every N bars. Ambient gives the progression a slower harmonic rhythm.
    private static func harmony(_ cycle: [Chord], bars: Int, ambient: Bool) throws -> [ChordEvent] {
        guard !cycle.isEmpty, cycle.count <= bars*8 else { throw SongFormError.chords }
        let count = ambient ? cycle.count : max(cycle.count, bars)
        var previous: [Int] = []
        var events: [ChordEvent] = []
        for index in 0..<count {
            let start = index * bars*8 / count * (ppq/2)
            let end = (index+1) * bars*8 / count * (ppq/2)
            var chord = cycle[index % cycle.count]
            chord.voicedNotes = try HarmonyLab.voicing(chord, previous: previous, low: 49, high: 81)
            previous = chord.notes
            events.append(ChordEvent(tick: start, duration: end-start, chord: chord))
        }
        return events
    }

    private static func groove(part: SongFormBrief.Part, cycle: [Chord], brief: TrackBrief, patterns: inout [Pattern]) throws {
        let changes = try harmony(cycle, bars: part.bars, ambient: false)
        let arpeggio = part.role == .arpeggio
        let phase = Int(brief.seed % 4)
        for bar in 0..<part.bars {
            let at = bar*barTicks
            let developed = bar >= max(1, part.bars/2)
            let hits = GrooveArrangement.percussion(style: .hipHop, feel: brief.hipHopFeel, seed: brief.seed &+ brief.drumVariation, bar: bar, lift: developed)
            patterns[1].drums += hits.map { DrumEvent(tick: at+$0.tick, pad: $0.pad, velocity: $0.velocity) }
            let barChanges = changes.filter { $0.tick < at+barTicks && $0.tick+$0.duration > at }
            for change in barChanges {
                let start = max(at, change.tick)
                let end = min(at+barTicks, change.tick+change.duration)
                let next = changes.first { $0.tick >= end }?.chord ?? changes[0].chord
                patterns[2].notes?.append(contentsOf: GrooveArrangement.bassLine(change.chord, next: next, style: .hipHop,
                    feel: brief.hipHopFeel, seed: brief.seed &+ brief.bassVariation, bar: bar,
                    lift: developed, end: end-start, at: start))
            }
        }
        for change in changes {
            let end = change.tick + change.duration
            if arpeggio {
                let tones = change.chord.notes
                let ascent = Array(tones.indices)
                let degrees: [Int]
                if tones.count == 3 {
                    degrees = phase % 2 == 0 ? [0,1,2,1,0,2,1,2] : [0,2,1,2,0,1,2,1]
                } else {
                    // Let sevenths, ninths and the user's custom chord tones participate too.
                    degrees = ascent + Array(ascent.dropFirst().dropLast().reversed())
                }
                for (index, grid) in stride(from: change.tick, to: end, by: ppq/2).enumerated() {
                    let at = grid+brief.keysOffset
                    guard at < end else { continue }
                    let degree = degrees[index % degrees.count] % tones.count
                    patterns[4].notes?.append(NoteEvent(tick: at, duration: min(390,end-at),
                        pitch: tones[degree], velocity: index.isMultiple(of: 2) ? 90 : 70))
                }
            } else {
                let at = change.tick + brief.keysOffset
                let developed = change.tick/barTicks >= max(1,part.bars/2)
                patterns[0].chords.append(ChordEvent(tick: at, duration: min(end-at, developed ? 2*ppq : 3*ppq), chord: change.chord))
                let answer = at + 5*ppq/2
                if developed && answer < end {
                    patterns[0].chords.append(ChordEvent(tick: answer, duration: min(ppq,end-answer), chord: change.chord, velocity: 68))
                }
            }
        }
    }

    private static func ambient(part: SongFormBrief.Part, cycle: [Chord], fadeBars: Int, seed: UInt32, patterns: inout [Pattern]) throws {
        let changes = try harmony(cycle, bars: part.bars, ambient: true)
        let length = part.bars*barTicks
        let fade = part.role == .keysOutro ? min(part.bars, max(0, fadeBars))*barTicks : 0
        let fadeStart = length - fade
        let soundEnd = fade > 0 ? length - ppq/2 : length
        func level(at tick: Int, base: Int) -> Int {
            guard fade > 0 && tick >= fadeStart else { return base }
            let remaining = Double(max(0, soundEnd-tick)) / Double(soundEnd-fadeStart)
            return max(1, Int((Double(base)*remaining).rounded()))
        }
        for change in changes {
            let end = min(change.tick + change.duration, soundEnd)
            var at = change.tick
            while at < end {
                let next: Int
                if at < fadeStart { next = min(end,fadeStart) }
                else { next = min(end,at+ppq) }
                let gate = min(next-at, max(1,next-at-60))
                patterns[0].chords.append(ChordEvent(tick: at, duration: gate, chord: change.chord, velocity: level(at: at, base: 62)))
                at = next
            }
        }
        let variant = Int(seed % 3)
        for bar in 0..<part.bars {
            let at = bar*barTicks
            if part.role == .bansuriSolo {
                let phrases = [[(0,1180),(1680,670),(2700,700)], [(240,840),(1380,1450)], [(0,1380),(2100,820)]]
                let phrase = phrases[(bar+variant) % phrases.count]
                for (index, cue) in phrase.enumerated() {
                    let tick = at+cue.0
                    let chord = changes.last { $0.tick <= tick }!.chord
                    let intervals = chord.effectiveIntervals
                    let pitch = 60+chord.root+intervals[(variant+bar+index) % intervals.count]
                    patterns[2].notes?.append(NoteEvent(tick: tick, duration: cue.1, pitch: pitch < 65 ? pitch+12 : pitch, velocity: index == 0 ? 92 : 75))
                }
            } else if part.role == .keysOutro {
                let positions = (bar+variant).isMultiple(of: 2) ? [ppq/2, 5*ppq/2] : [ppq]
                for (index, position) in positions.enumerated() {
                    let tick = at+position
                    guard tick < soundEnd else { continue }
                    let chord = changes.last { $0.tick <= tick }!.chord
                    let tones = chord.notes
                    patterns[3].notes?.append(NoteEvent(tick: tick, duration: min(ppq, soundEnd-tick),
                        pitch: tones[(variant+index+bar) % tones.count], velocity: level(at: tick, base: 78)))
                }
            }
        }
    }

    private static func echoes(of note: NoteEvent, at start: Int, songEnd: Int) -> [NoteEvent] {
        // Dotted-quarter and dotted-half responses remain editable and audible after MIDI export.
        [1,2].compactMap { tap in
            let tick = start + note.tick + tap * 3*ppq/2
            guard tick < songEnd-ppq/2 else { return nil }
            let velocity = note.velocity / (tap == 1 ? 2 : 4)
            guard velocity >= 2 else { return nil }
            return NoteEvent(tick: tick, duration: min(note.duration, songEnd-ppq/2-tick), pitch: note.pitch, velocity: velocity)
        }
    }
}
