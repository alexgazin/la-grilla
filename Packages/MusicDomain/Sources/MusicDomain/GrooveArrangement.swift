import Foundation

/// Arrange generated harmony into playable sections with independent rhythm and bass variations.
enum GrooveArrangement {
    static func make(from project: Project, chords: [Chord], brief: TrackBrief) throws -> Project {
        guard chords.count == brief.bars, (0..<brief.bars).contains(brief.introBars) else {
            throw SketchError.invalidPlan
        }
        var song = project
        var harmony = song.tracks[0], drums = song.tracks[1]
        var bass = Track(role: .melody), lead = Track(role: .melody)
        bass.name = NSLocalizedString("Bass", comment: "Editable instrumental bass line")
        bass.presetVersion = SoundPalette.warm.rawValue
        bass.gain = -4
        lead.gain = -11
        harmony.presetVersion = SoundPalette.warm.rawValue
        harmony.gain = -9
        drums.gain = -3
        harmony.clips = []
        drums.clips = []
        song.tracks = [harmony, drums, bass, lead]
        song.sections = []
        song.patterns = []

        let split = brief.introBars > 0 ? brief.introBars : brief.bars / 2
        let drumSeed = brief.seed &+ brief.drumVariation
        let bassSeed = brief.seed &+ brief.bassVariation
        var previousVoicing: [Int] = []
        for (part, range) in [(0, 0..<split), (1, split..<brief.bars)] {
            let length = range.count * barTicks
            let sectionName = part == 0 ? (brief.introBars > 0 ? "Intro" : "Verse") : "Hook"
            let section = Section(name: NSLocalizedString(sectionName, comment: "Generated section"),
                                  start: range.lowerBound * barTicks, length: length)
            song.sections.append(section)
            var keys = Pattern(length: length), beat = Pattern(length: length)
            var low = Pattern(length: length), tune = Pattern(length: length)
            for bar in range {
                let at = (bar - range.lowerBound) * barTicks
                let end = brief.endBreak && bar == brief.bars - 1 ? barTicks / 2 : barTicks
                var chord = chords[bar]
                if let voiced = try? HarmonyLab.voicing(chord, previous: previousVoicing, low: 48, high: 82) {
                    chord.voicedNotes = voiced
                }
                previousVoicing = chord.notes
                let nextChord = chords[(bar + 1) % chords.count]
                beat.drums += percussion(style: brief.style, feel: brief.hipHopFeel, seed: drumSeed, bar: bar, lift: part == 1)
                    .filter { $0.tick + 120 <= end }
                    .map { DrumEvent(tick: at + $0.tick, pad: $0.pad, velocity: $0.velocity) }
                low.notes?.append(contentsOf: bassLine(chord, next: nextChord, style: brief.style, feel: brief.hipHopFeel, seed: bassSeed,
                                                       bar: bar, lift: part == 1, end: end, at: at))
                if bar >= brief.introBars {
                    let stab = brief.style == .house ? ppq / 2 : 0
                    keys.chords.append(ChordEvent(tick: at + stab, duration: min(end-stab, part == 1 ? 2*ppq : 3*ppq), chord: chord))
                    if part == 1 && end == barTicks {
                        keys.chords.append(ChordEvent(tick: at + 5*ppq/2, duration: ppq, chord: chord))
                    }
                    tune.notes?.append(contentsOf: melody(chord, style: brief.style, seed: brief.seed,
                                                         bar: bar, lift: part == 1, end: end, at: at))
                }
            }
            for (index, pattern) in [keys, beat, low, tune].enumerated() {
                guard !pattern.chords.isEmpty || !pattern.drums.isEmpty || !(pattern.notes ?? []).isEmpty else { continue }
                song.patterns.append(pattern)
                song.tracks[index].clips.append(Clip(patternID: pattern.id, start: section.start, length: length))
            }
        }
        try song.validate()
        return song
    }

    private static func percussion(style: SketchStyle, feel: HipHopFeel, seed: UInt32, bar: Int, lift: Bool) -> [DrumEvent] {
        let variation = Int(seed % 4)
        let answer = bar % 2 == 1
        var hits: [DrumEvent] = []
        func hit(_ t: Int, _ pad: Int, _ v: Int) { hits.append(DrumEvent(tick: t, pad: pad, velocity: v)) }
        let kicks: [Int]
        switch style {
        case .house: kicks = [0, 960, 1920, 2880]
        case .hipHop:
            let pockets = feel == .westCoast ? [[0,1440,1920,3120],[0,1680,2400],[0,960,2160,3360],[0,1440,2640]] : [[0,1440,2160], [0,1680,1920], [0,1200,2400], [0,720,2160]]
            kicks = pockets[(variation + (answer ? 1 : 0)) % pockets.count]
        case .jazz: kicks = answer ? [0, 2240] : [0, 1920]
        }
        for (n,t) in kicks.enumerated() { hit(t, 0, n == 0 ? 113 : 95) }
        for t in [ppq, 3*ppq] {
            hit(t + (style == .hipHop && feel == .boomBap ? 24 + variation*5 : 0), style == .house ? 4 : 1, style == .jazz ? 68 : 105)
        }
        if style == .hipHop && feel == .westCoast {
            for t in [ppq, 3*ppq] { hit(t+8, 4, 86) }
        }
        for eighth in 0..<8 {
            let off = eighth % 2 == 1
            let swing = style == .hipHop && feel == .boomBap ? 42 + variation*12 : (style == .jazz ? ppq/6 : 0)
            let pad = style == .jazz ? 10 : (lift && eighth == 7 && answer ? 3 : 2)
            hit(eighth*ppq/2 + (off ? swing : 0), pad, (off ? 55 : 77) + (bar + eighth + variation)%9)
        }
        if answer && (Int((seed >> 2) % 4) + bar) % 3 == 0 {
            hit(style == .jazz ? 2*ppq + 2*ppq/3 : 2*ppq + 3*ppq/4, 1, 39 + variation*3)
        }
        if lift && bar % 4 == 3 { hit(3*ppq + ppq/4, 1, 47); hit(3*ppq + 3*ppq/4, 1, 61) }
        return hits.sorted { ($0.tick, $0.pad) < ($1.tick, $1.pad) }
    }

    private static func bassLine(_ chord: Chord, next: Chord, style: SketchStyle, feel: HipHopFeel, seed: UInt32,
                                 bar: Int, lift: Bool, end: Int, at: Int) -> [NoteEvent] {
        let root = 36 + (chord.slashBass ?? chord.root)
        let fifth = 36 + chord.root + (chord.effectiveIntervals.first(where: { (6...8).contains($0) }) ?? 7)
        let nextRoot = 36 + (next.slashBass ?? next.root)
        let v = Int(seed % 4)
        let positions: [Int]
        switch style {
        case .house: positions = [0, 480, 1440, 1920, 2400, 3360]
        case .hipHop: positions = feel == .westCoast ? [0,720,1440,1920,2640,3120] : [[0,1440,2160], [0,1680,2400], [0,1200,2160], [0,720,1920]][v]
        case .jazz: positions = [0, 960, 1920, 2880]
        }
        let ticks = positions + (lift && bar % 2 == 1 ? [3600] : [])
        return ticks.enumerated().compactMap { i,t in
            guard t < end else { return nil }
            let nextTick = i+1 < ticks.count ? ticks[i+1] : barTicks
            let pitch = t == 3600 ? nextRoot-1 : (i == 0 || i % 3 == 2 ? root : ((i + v + bar) % 2 == 0 ? fifth : root+12))
            let gate = style == .house || (style == .hipHop && feel == .westCoast) ? 0.58 : (style == .jazz ? 0.86 : 0.75)
            let duration = min(end-t, Int(Double(nextTick-t)*gate))
            return NoteEvent(tick: at+t, duration: duration, pitch: pitch, velocity: i == 0 ? 109 : 86+(i+v)%12)
        }
    }

    private static func melody(_ chord: Chord, style: SketchStyle, seed: UInt32,
                               bar: Int, lift: Bool, end: Int, at: Int) -> [NoteEvent] {
        let tones = Array(Set(chord.notes.map { 60 + ($0 % 12) })).sorted()
        let motif = [[0,1,2,1],[2,1,0,1],[1,0,2,0],[0,2,1,2]][Int(seed % 4)]
        let alternate = (seed >> 2) % 2 == 1
        let onsets: [Int]
        switch style {
        case .jazz: onsets = alternate ? [0, 960, 1600, 2880] : [0, 640, 1600, 2560]
        case .house: onsets = alternate ? [0, 720, 1440, 2400] : [0, 480, 1680, 2880]
        case .hipHop: onsets = alternate ? [0, 720, 1920, 2640] : [240, 960, 1680, 2640]
        }
        return onsets.enumerated().compactMap { i,t in
            guard t < end, lift || i < 2 else { return nil }
            let degree = bar % 4 == 3 && i == 3 ? 0 : motif[i]
            let pitch = tones[degree % tones.count] + (lift && bar % 4 == 3 ? 12 : 0)
            return NoteEvent(tick: at+t, duration: min(end-t, i == 3 ? 720 : 420), pitch: pitch, velocity: i == 0 ? 91 : 78)
        }
    }
}
