import Foundation
import MusicDomain

// Original promo composition, performed by the unmodified La Grilla offline engine.
// This is an authored arrangement, not a recording of a person or a live iPhone.
@main struct PromoSoundtrack {
    static let rate = 48_000
    static let seconds = 96.0
    static let sourceSHA = "8e5b1f768fafe28d8de4b8154c786039e2a1fa71"

    static func main() async throws {
        let destination = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "PromoAudio", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        var project = composition()
        try project.validate()
        let take = performance(project)
        try take.validate()
        // Portable project retains both the editable score and exact render automation.
        project.performanceTake = take
        try project.validate()
        try PortableProject.data(project).write(to: destination.appendingPathComponent("la-grilla-promo.grillapack"))
        try MIDIExporter.data(project).write(to: destination.appendingPathComponent("la-grilla-promo-score.mid"))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(project).write(to: destination.appendingPathComponent("la-grilla-promo-project.json"))
        let receipt = try await OfflineRenderer.renderPerformance(
            take,
            to: destination.appendingPathComponent("la-grilla-promo-96s-48k24.wav"),
            settings: WAVSettings(sampleRate: rate, bitDepth: 24, tailSeconds: 0, dither: false)
        )
        print("WAV \(receipt.url.path)")
        print("frames=\(receipt.frames), rate=\(receipt.sampleRate), bits=\(receipt.bitDepth), DSP peak=\(receipt.peak), clipped=\(receipt.clipped)")
        print("compiled notes=\(Compiler.notes(take.source).count); automation events=\(take.events.count)")
        guard receipt.frames == rate * Int(seconds), !receipt.clipped else {
            throw NSError(domain: "PromoSoundtrack", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unexpected length or overloaded master"])
        }
    }

    static func composition() -> Project {
        var p = Project(name: "La Grilla · Lines into music", bars: 48)
        p.bpm = 120; p.keyRoot = 0; p.master = 6
        p.masterFX = MasterFX(filter: 0, delayWet: 0.12)
        p.bassGate = 0.82
        p.sections = [Section(name: "96-second promo score", length: 48 * barTicks)]
        p.modified = Date(timeIntervalSince1970: 1_794_787_200)
        p.tracks[0].name = "Warm chord pulse"; p.tracks[0].gain = -8; p.tracks[0].pan = -0.12
        p.tracks[1].name = "Tactile drum kit"; p.tracks[1].gain = -8; p.tracks[1].pan = 0
        var bass = Track(role: .bass); bass.name = "Round sub bass"; bass.gain = -5; p.tracks.append(bass)
        var motifPattern = Pattern(length: p.length)
        var sparklePattern = Pattern(length: p.length)
        var motif = Track(role: .melody); motif.name = "Four-note motif"; motif.gain = -8; motif.pan = 0.18
        var sparkle = Track(role: .melody); sparkle.name = "Air arpeggio"; sparkle.gain = -16; sparkle.pan = -0.4
        let roots = [0,9,5,7]
        for bar in 0..<48 {
            let start = bar * barTicks
            if bar >= 46 { continue }
            // A two-bar intro, then an evolving diatonic progression.
            let variation = (bar >= 18 && bar < 22) || (bar >= 34 && bar < 38)
            let root = variation ? [5,7,9,7][bar % 4] : roots[bar % 4]
            let quality: Quality = root == 9 ? .m7 : root == 7 ? .nineSus4 : .add9
            let voicing: [Int]
            switch root {
            case 0: voicing = [48,55,64,74]
            case 9: voicing = [45,55,60,64]
            case 5: voicing = [53,60,69,79]
            default: voicing = [43,53,60,62,69]
            }
            let chord = Chord(root: root, quality: quality, voicedNotes: voicing)
            if bar < 2 {
                p.patterns[0].chords.append(ChordEvent(tick: start, duration: 3 * ppq, chord: chord))
            } else {
                // Short offbeat responses create room for the bass and lead.
                for (tick, duration) in [(0,1320),(1920,720),(3120,480)] {
                    p.patterns[0].chords.append(ChordEvent(tick: start + tick, duration: duration, chord: chord))
                }
            }
            // Procedural kick/snare/hat pads. Fills and breaks are part of the score.
            if bar >= 2 {
                let breakBar = [9,17,25,29,37,41,45].contains(bar)
                let sparse = (bar >= 26 && bar < 30) || (bar >= 34 && bar < 36)
                var kicks = sparse ? [0,1920] : [0,1440,1920,3360]
                if breakBar { kicks = [0,1440] }
                for t in kicks { p.patterns[1].drums.append(DrumEvent(tick: start+t, pad: 0, velocity: t == 0 ? 108 : 87)) }
                for t in [960,2880] where !breakBar || t < 2000 {
                    p.patterns[1].drums.append(DrumEvent(tick: start+t, pad: bar >= 10 && bar < 14 ? 4 : 1, velocity: 88))
                    if bar >= 18 && !sparse { p.patterns[1].drums.append(DrumEvent(tick: start+t+30, pad: 5, velocity: 36)) }
                }
                for step in 0..<8 where !breakBar || step < 5 {
                    let t = start + step*480 + (step % 2 == 1 ? 34 : 0)
                    p.patterns[1].drums.append(DrumEvent(tick: t, pad: step == 7 && !sparse ? 3 : 2, velocity: step % 2 == 0 ? 57 : 37))
                }
                if bar >= 10 && bar < 26 && !breakBar {
                    for step in [1,3,5,7] { p.patterns[1].drums.append(DrumEvent(tick: start+step*480+240, pad: 14, velocity: 32)) }
                }
                if breakBar {
                    for (j,t) in [2880,3120,3360,3600].enumerated() {
                        p.patterns[1].drums.append(DrumEvent(tick: start+t, pad: j < 2 ? 5 : 8-j%3, velocity: 52+j*7))
                    }
                }
                if [6,10,14,18,22,30,38,42].contains(bar) {
                    p.patterns[1].drums.append(DrumEvent(tick: start, pad: 9, velocity: 40))
                }
            }
            // The recurring motif is deliberately short, with space between phrases.
            // All notes remain in C major, so richer harmony remains legible.
            let notes: [Int]
            switch root {
            case 0: notes = [76,79,74,72]
            case 9: notes = [76,72,71,69]
            case 5: notes = [77,76,72,69]
            default: notes = [74,72,71,67]
            }
            if bar >= 6 && !(bar >= 26 && bar < 30) && bar % 4 != 1 {
                for (j,t) in [0,720,1680,2880].enumerated() {
                    motifPattern.notes!.append(NoteEvent(tick: start+t, duration: j == 3 ? 600 : 420, pitch: notes[j], velocity: [77,62,72,65][j]))
                }
                if bar % 4 == 3 && bar < 42 {
                    motifPattern.notes!.append(NoteEvent(tick: start+3480, duration: 240, pitch: 71, velocity: 48))
                }
            }
            if bar >= 14 && bar < 46 && bar % 4 != 1 {
                let triad: [Int] = root == 9 ? [81,84,88,91] : root == 5 ? [77,81,84,88] : root == 7 ? [79,83,86,89] : [76,79,84,86]
                for (j,t) in [480,1440,2400,3360].enumerated() {
                    sparklePattern.notes!.append(NoteEvent(tick: start+t, duration: 240, pitch: triad[j], velocity: 48+j*3))
                }
            }
        }
        // Resolve at exactly 92 s; the last second contains only release/delay.
        p.patterns[0].chords.append(ChordEvent(tick: 46*barTicks, duration: 6*ppq, chord: Chord(root: 0, quality: .sixNine, voicedNotes: [48,55,64,69,74])))
        motifPattern.notes!.append(NoteEvent(tick: 46*barTicks, duration: 4*ppq, pitch: 84, velocity: 64))
        p.patterns[1].drums.append(DrumEvent(tick: 46*barTicks, pad: 9, velocity: 32))
        motif.clips = [Clip(patternID: motifPattern.id, start: 0, length: p.length)]
        sparkle.clips = [Clip(patternID: sparklePattern.id, start: 0, length: p.length)]
        p.patterns += [motifPattern,sparklePattern]; p.tracks += [motif,sparkle]
        return p
    }

    static func performance(_ p: Project) -> PerformanceTake {
        var events = [PerformanceEvent(frame: 0, kind: .section, sectionID: p.sections[0].id)]
        func at(_ seconds: Double, _ kind: PerformanceEvent.Kind, _ value: Double, _ track: Int? = nil) {
            events.append(PerformanceEvent(frame: UInt64((seconds * Double(rate)).rounded()), kind: kind, value: value, track: track))
        }
        func gain(_ second: Double, _ track: Int, _ dB: Double) { at(second, .gain, dB <= -61 ? 0 : pow(10,dB/20), track) }
        gain(0,2,-61); gain(0,3,-61); gain(0,4,-61)
        gain(4,0,-7); gain(12,0,-8); gain(12,3,-10)
        gain(20,1,-6.5); gain(20,3,-8)
        gain(28,2,-4.5); gain(28,1,-8); gain(28,4,-17)
        gain(36,0,-5.5); gain(36,3,-10); gain(36,4,-16)
        gain(44,0,-8); gain(44,3,-8); gain(44,1,-7)
        // A gentle instrumental breath under the Voice chapter, no synthetic singer.
        gain(52,3,-61); gain(52,4,-22); gain(52,1,-10); gain(52,2,-7)
        gain(60,3,-8); gain(60,4,-15); gain(60,1,-7); gain(60,2,-4.5)
        // True native filter/delay automation, captured in the portable take.
        for i in 0...32 {
            let t = 60 + Double(i)/8
            at(t, .filter, -0.62 * sin(Double(i)/32 * .pi))
            at(t, .delay, 0.12 + 0.19 * sin(Double(i)/32 * .pi))
        }
        for i in 1...16 {
            let t = 64 + Double(i)/4
            at(t, .filter, 0.35 * sin(Double(i)/16 * .pi))
            at(t, .delay, 0.12 + 0.08 * sin(Double(i)/16 * .pi))
        }
        // Mixer section briefly foregrounds each part, then opens the full arrangement.
        gain(68,0,-13); gain(68,3,-12); gain(68,4,-22); gain(68,1,-7)
        gain(70,2,-3.5); gain(72,0,-6); gain(72,2,-5); gain(74,3,-7.5)
        gain(76,0,-8); gain(76,1,-7); gain(76,2,-4.5); gain(76,3,-8); gain(76,4,-16)
        gain(84,1,-6.5); gain(84,0,-7); gain(84,3,-7.5); gain(84,4,-15)
        gain(90,4,-21); at(90,.delay,0.22)
        gain(92,1,-12); gain(92,2,-8); gain(92,0,-6); gain(92,3,-10); gain(92,4,-61)
        // Slow master fade allows a clean, click-free end inside the exact 96 s.
        for i in 0...32 {
            let t = 94 + Double(i)/16
            let amplitude = pow(max(0,1-Double(i)/32),1.3) * pow(10,6.0/20)
            at(t,.gain,amplitude,masterBus)
        }
        // Keep deterministic order for events sharing a frame; the section stays first.
        let sorted = events.enumerated().sorted { a,b in a.element.frame == b.element.frame ? a.offset < b.offset : a.element.frame < b.element.frame }.map(\.element)
        var take = PerformanceTake(name: "Original 96-second promo · authored automation", source: p, sampleRate: Double(rate), durationFrames: UInt64(rate*96), events: sorted)
        take.created = p.modified
        return take
    }
}
