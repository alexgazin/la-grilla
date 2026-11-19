import Foundation

/// A small producer project used for the on-screen song-edit walkthrough and
/// UI tests: Intro 2, Verse 4, Chorus 4, Verse 4, Chorus 4 bars. Both choruses
/// share one drum and one chord pattern; a named "Bass" melody track carries an
/// editable bass line and a "Flute" track has a hand-played pickup.
public enum SongEditDemo {
    public static func project(name: String = "Two choruses") throws -> Project {
        var p = Project(name: name, bars: 4)
        p.bpm = 92; p.keyRoot = 9; p.minor = true
        let parts: [(String, Int)] = [("Intro", 2), ("Verse", 4), ("Chorus", 4), ("Verse", 4), ("Chorus", 4)]
        var start = 0
        p.sections = parts.map { part in
            defer { start += part.1 * barTicks }
            return Section(name: NSLocalizedString(part.0, comment: "Generated section"), start: start, length: part.1 * barTicks)
        }
        func beat(bars: Int, busy: Bool, sparse: Bool = false) -> Pattern {
            var pattern = Pattern(length: bars * barTicks)
            for bar in 0..<bars {
                let at = bar * barTicks
                pattern.drums += [DrumEvent(tick: at, pad: 0, velocity: 110), DrumEvent(tick: at + 1920, pad: 0, velocity: 100)]
                if !sparse { pattern.drums += [DrumEvent(tick: at + 960, pad: 1), DrumEvent(tick: at + 2880, pad: 1)] }
                for step in stride(from: 0, to: barTicks, by: busy ? 240 : 480) {
                    pattern.drums.append(DrumEvent(tick: at + step, pad: 2, velocity: step % 960 == 0 ? 84 : 66))
                }
            }
            return pattern
        }
        func chords(_ symbols: [String]) throws -> Pattern {
            Pattern(length: symbols.count * barTicks, chords: try symbols.enumerated().map {
                ChordEvent(tick: $0.offset * barTicks, chord: try Chord.parse($0.element))
            })
        }
        let introBeat = beat(bars: 2, busy: false, sparse: true)
        let verseBeat = beat(bars: 4, busy: false), chorusBeat = beat(bars: 4, busy: true)
        let introChords = try chords(["Am", "Am"]), verseChords = try chords(["Am", "F", "C", "G"]), chorusChords = try chords(["F", "G", "Am", "Am"])
        var bassLine = Pattern(length: 18 * barTicks)
        let roots = [45, 45, 45, 41, 48, 43, 41, 43, 45, 45, 45, 41, 48, 43, 41, 43, 45, 45]
        for (bar, root) in roots.enumerated() {
            bassLine.notes?.append(NoteEvent(tick: bar * barTicks, duration: 1800, pitch: root, velocity: 96))
            bassLine.notes?.append(NoteEvent(tick: bar * barTicks + 1920, duration: 900, pitch: root + 7, velocity: 88))
            bassLine.notes?.append(NoteEvent(tick: bar * barTicks + 3360, duration: 400, pitch: root + 12, velocity: 80))
        }
        var lead = Pattern(length: 18 * barTicks)
        lead.notes = [NoteEvent(tick: 0, duration: 480, pitch: 76, velocity: 101)]
        for bar in [6, 7, 14, 15, 16, 17] {
            for (beat, pitch) in [76, 74, 72, 69].enumerated() {
                lead.notes?.append(NoteEvent(tick: bar * barTicks + beat * ppq, duration: 720, pitch: pitch, velocity: 94))
            }
        }
        p.patterns = [introChords, verseChords, chorusChords, introBeat, verseBeat, chorusBeat, bassLine, lead]
        func clips(_ patterns: [Pattern]) -> [Clip] {
            var at = 0
            return patterns.enumerated().map { index, pattern in
                defer { at += parts[index].1 * barTicks }
                return Clip(patternID: pattern.id, start: at, length: parts[index].1 * barTicks)
            }
        }
        p.tracks[0].clips = clips([introChords, verseChords, chorusChords, verseChords, chorusChords])
        p.tracks[1].clips = clips([introBeat, verseBeat, chorusBeat, verseBeat, chorusBeat])
        p.tracks[0].gain = -9; p.tracks[1].gain = -4; p.master = -3
        var bass = Track(role: .melody); bass.name = NSLocalizedString("Bass", comment: "Editable instrumental bass line")
        bass.presetVersion = SoundPalette.warm.rawValue; bass.gain = -5
        bass.clips = [Clip(patternID: bassLine.id, start: 0, length: 18 * barTicks)]
        var melody = Track(role: .melody); melody.name = NSLocalizedString("Flute", comment: "Demo melody track"); melody.gain = -10
        melody.clips = [Clip(patternID: lead.id, start: 0, length: 18 * barTicks)]
        p.tracks += [bass, melody]
        try p.validate()
        return p
    }
}
