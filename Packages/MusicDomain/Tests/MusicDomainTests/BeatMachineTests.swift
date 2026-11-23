import Foundation
import Testing
@testable import MusicDomain

struct BeatMachineTests {
    private func kitAssets(_ kit: FactoryDrumKit = .trap808) throws -> [Int: SampleAsset] {
        Dictionary(uniqueKeysWithValues: try PaletteEngine.kit(kit).map { ($0.pad, $0.asset) })
    }

    @Test func libraryCoversEveryGenreWithWellFormedPatterns() throws {
        let library = BeatPreset.library
        #expect(library.count >= 45)
        #expect(Set(library.map(\.id)).count == library.count)
        #expect(Set(library.map(\.genre)) == Set(BeatPreset.Genre.allCases))
        #expect(Set(library.map(\.kit)).count >= 15, "Most kits have a beat that shows them off")
        let allowed = Set("Xxo234.")
        for preset in library {
            #expect((40...240).contains(preset.bpm), "\(preset.id)")
            #expect((0.5...0.66).contains(preset.swing), "\(preset.id)")
            #expect([16, 32].contains(preset.steps), "\(preset.id)")
            #expect(Set(preset.lanes.map(\.pad)).count == preset.lanes.count, "\(preset.id) repeats a pad")
            for lane in preset.lanes {
                let steps = BeatPreset.clean(lane.steps)
                #expect(steps.count == preset.steps, "\(preset.id) pad \(lane.pad)")
                #expect(steps.allSatisfy(allowed.contains), "\(preset.id) pad \(lane.pad)")
                #expect((0..<16).contains(lane.pad))
                let bars = lane.steps.split(separator: "|")
                #expect(bars.allSatisfy { $0.count == 16 }, "\(preset.id) pad \(lane.pad) bar length")
            }
            let tokens = preset.bassLine.split(separator: " ").count
            let notes = BeatDraft.parseBass(preset.bassLine, steps: preset.steps)
            #expect(notes.count == tokens, "\(preset.id) drops a bass token")
            for (note, next) in zip(notes, notes.dropFirst()) {
                #expect(note.step + note.length <= next.step, "\(preset.id) overlapping bass at \(note.step)")
            }
            #expect(preset.bass == nil || preset.bass?.family == .bass)
            let draft = BeatDraft(preset)
            #expect(draft.hitCount > 0)
        }
    }

    @Test func stepsBecomeHitsWithSwingAccentsAndRolls() {
        var draft = BeatDraft(kit: .boomBap, bpm: 90)
        draft.swing = 0.6
        draft.set(pad: 0, step: 0, .accent)
        draft.set(pad: 2, step: 1, .normal)
        draft.set(pad: 2, step: 3, .roll(3))
        draft.set(pad: 1, step: 4, .ghost)
        let events = draft.drumEvents()
        #expect(events.map(\.tick) == [0, 240 + 48, 720 + 48, 960])
        #expect(events.first { $0.pad == 0 }?.velocity == 122)
        #expect(events.first { $0.pad == 1 }?.velocity == 54)
        #expect(events.first { $0.tick == 768 }?.ratchet == 3)
        draft.toggle(pad: 0, step: 0)
        #expect(!draft.hit(pad: 0, step: 0).isOn)
        #expect(!draft.activePads.contains(0), "An emptied lane goes away")
    }

    @Test func bassFollowsTheSongsKeyAndMode() {
        #expect((0..<12).map { BeatDraft.bassRoot(keyRoot: $0) }.allSatisfy { (29...40).contains($0) })
        #expect(BeatDraft.fitted(3, writtenMinor: true, songMinor: false) == 4)
        #expect(BeatDraft.fitted(-4, writtenMinor: true, songMinor: false) == -3)
        #expect(BeatDraft.fitted(10, writtenMinor: true, songMinor: false) == 10, "The flat seventh stays")
        #expect(BeatDraft.fitted(16, writtenMinor: false, songMinor: true) == 15)
        #expect(BeatDraft.fitted(7, writtenMinor: true, songMinor: false) == 7)
        let draft = BeatDraft(BeatPreset.preset("trap-classic")!)
        let inA = draft.bassEvents(keyRoot: 9, minor: true)
        #expect(inA.first?.pitch == 33, "A1")
        let lastWritten = draft.bassNotes.last!
        #expect(lastWritten.semitones == 3)
        #expect(draft.bassEvents(keyRoot: 9, minor: false).last?.pitch == 33 + 4, "Minor third becomes major in a major song")
        #expect(inA.allSatisfy { $0.tick + $0.duration <= draft.length })
    }

    @Test func bassLaneTapsAddRemoveAndRetune() {
        var draft = BeatDraft(kit: .trap808)
        draft.toggleBass(step: 0, semitones: 0)
        #expect(draft.bassNotes == [BassStep(step: 0, semitones: 0, length: 2)])
        draft.toggleBass(step: 4)
        draft.transposeBass(step: 4, by: 5)
        draft.setBassLength(step: 0, 8)
        #expect(draft.bassNotes.map(\.length) == [4, 2], "A note never runs into the next one")
        #expect(draft.bassNotes[1].semitones == 5)
        draft.toggleBass(step: 1)
        #expect(draft.bassNotes.count == 1, "Tapping inside a held note removes it")
        draft.transposeBass(step: 4, by: 40)
        #expect(draft.bassNotes[0].semitones <= 24)
    }

    @Test func barsDoubleAndHalve() {
        var draft = BeatDraft(BeatPreset.preset("house-classic")!)
        #expect(draft.steps == 16)
        let hits = draft.hitCount
        draft.setBars(2)
        #expect(draft.steps == 32 && draft.hitCount == hits * 2)
        #expect(draft.bassNotes.count == 8)
        draft.setBars(1)
        #expect(draft.steps == 16 && draft.hitCount == hits && draft.bassNotes.count == 4)
    }

    @Test func variationKeepsTheBackboneAndRepeats() {
        let preset = BeatPreset.preset("trap-classic")!
        var a = BeatDraft(preset), b = BeatDraft(preset)
        a.vary(seed: 7); b.vary(seed: 7)
        #expect(a == b)
        var changed = false
        for seed in 1...20 {
            var c = BeatDraft(preset); c.vary(seed: UInt64(seed))
            #expect(c.hit(pad: 0, step: 0).isOn && c.hit(pad: 1, step: 8).isOn && c.hit(pad: 1, step: 24).isOn)
            if c != BeatDraft(preset) { changed = true }
        }
        #expect(changed)
    }

    @Test func applyingToTheSongPutsKitBeatAnd808InOneCandidate() throws {
        var project = Project.demo()
        try project.duplicateSection(project.sections[0].id, name: "Hook")
        let draft = BeatDraft(BeatPreset.preset("trap-classic")!)
        let bass = try FactorySynth.sub808.asset().asset
        let result = try BeatMachine.candidate(project, draft: draft, scope: .song, kit: try kitAssets(), bass: bass)
        #expect(result.bpm == 140)
        #expect(result.tracks[1].padSamples?.count == 16)
        #expect(result.tracks[1].clips.count == 2)
        for clip in result.tracks[1].clips {
            let pattern = result.patterns.first { $0.id == clip.patternID }!
            #expect(pattern.length == 2 * barTicks && pattern.drums.count == draft.drumEvents().count)
        }
        let track = try #require(BeatMachine.bassTrack(in: result))
        #expect(result.tracks[track].instrumentSample == bass)
        #expect(result.tracks[track].clips.count == 2)
        #expect(result.tracks.first { $0.role == .bass }?.mute == true)
        let compiled = Compiler.notes(result)
        #expect(compiled.contains { $0.track == track && $0.pitch == BeatDraft.bassRoot(keyRoot: 0) })
        #expect(compiled.filter { $0.pad == 0 }.count >= 4 * 3, "Kick hits in all eight bars")
        // Applying again reuses the 808 track instead of adding another one.
        let again = try BeatMachine.candidate(result, draft: draft, scope: .song, kit: try kitAssets(.phonk), bass: bass)
        #expect(again.tracks.count == result.tracks.count)
        #expect(again.tracks[1].padSamples?[0]?.name.hasPrefix("Phonk · ") == true)
    }

    @Test func applyingToOneSectionLeavesTheRestAndSplitsLongClips() throws {
        var project = Project.demo()
        try SectionEditing.append(name: "Chorus", bars: 4, to: &project)
        // One drum clip that spans both sections.
        let pattern = project.patterns[1].id
        project.tracks[1].clips = [Clip(patternID: pattern, start: 0, length: project.length)]
        try project.validate()
        let chorus = project.sections[1]
        var draft = BeatDraft(BeatPreset.preset("house-classic")!)
        draft.bass = nil
        let result = try BeatMachine.candidate(project, draft: draft, scope: .section(chorus.id), kit: try kitAssets(.house), bass: nil,
                                               options: .init(useTempo: false, muteChordBass: true))
        #expect(result.bpm == project.bpm)
        let clips = result.tracks[1].clips
        #expect(clips.count == 2)
        #expect(clips[0].patternID == pattern && clips[0].length == chorus.start)
        #expect(clips[1].start == chorus.start && clips[1].patternID != pattern)
        #expect(BeatMachine.bassTrack(in: result) == nil, "No 808 asked for, no 808 track")
        #expect(result.tracks.first { $0.role == .bass }?.mute == false)
    }

    @Test func lockedTracksAndFullProjectsAreRefusedClearly() throws {
        var project = Project.demo()
        project.tracks[1].locked = true
        let draft = BeatDraft(BeatPreset.preset("drill-uk")!)
        let bass = try FactorySynth.sub808.asset().asset
        #expect(throws: BeatMachine.BeatError.drumsLocked) {
            try BeatMachine.candidate(project, draft: draft, scope: .song, kit: try kitAssets(), bass: bass)
        }
        project.tracks[1].locked = nil
        while project.tracks.count < 8 { try project.addMelody() }
        #expect(throws: MusicError.trackLimit) {
            try BeatMachine.candidate(project, draft: draft, scope: .song, kit: try kitAssets(), bass: bass)
        }
        #expect(throws: BeatMachine.BeatError.empty) {
            try BeatMachine.candidate(Project.demo(), draft: BeatDraft(kit: .rock), scope: .song, kit: try kitAssets(), bass: nil)
        }
    }

    @Test func synthInstrumentsAreValidLoopSeamlesslyAndDecayToSilence() throws {
        var hashes = Set<String>()
        for synth in FactorySynth.allCases {
            let pcm = try synth.pcm()
            #expect(pcm.zones.map(\.pitch) == synth.zonePitches)
            let data = try pcm.encode(kind: .instrument)
            let asset = try SampleAsset(kind: .instrument, name: synth.title, bytes: data)
            #expect(asset.kind == .instrument && data.count <= 8_000_000)
            #expect(hashes.insert(asset.sha256).inserted, "\(synth) sounds like another instrument")
            for zone in pcm.zones {
                #expect(zone.samples.contains { abs(Int($0)) > 8_000 }, "\(synth) \(zone.pitch) is too quiet")
                if synth.loops {
                    #expect(zone.loopStart > 0 && zone.loopStart <= zone.samples.count - 1024)
                    let jump = abs(Int(zone.samples[zone.samples.count - 1]) - Int(zone.samples[zone.loopStart - 1]))
                    #expect(jump < 900, "\(synth) \(zone.pitch) clicks at the loop: \(jump)")
                } else {
                    #expect(zone.loopStart == 0 && zone.samples.last == 0)
                }
            }
            let wav = try synth.previewWAV(pcm)
            #expect(wav.count > 44 + FactorySynth.rate * 4)
        }
        #expect(FactorySynth.basses.count == 8 && FactorySynth.melodic.count == 8)
    }

    @Test func everyKitHasANameAndPrefixThatMarksItsSamples() throws {
        #expect(FactoryDrumKit.allCases.count == 19)
        #expect(Set(FactoryDrumKit.allCases.map(\.title)).count == 19)
        for kit in [FactoryDrumKit.chip, .phonk, .synthwave] {
            let sounds = try PaletteEngine.kit(kit)
            #expect(sounds.allSatisfy { PaletteEngine.isFactoryKitSound($0.asset.name) })
        }
    }
}

struct EightOhEightSlideTests {
    @Test func slidesOverlapTheNextNoteAndTurnOnTheTrackGlide() throws {
        let preset = try #require(BeatPreset.preset("drill-uk"))
        var draft = BeatDraft(preset)
        #expect(draft.hasSlides && draft.bassNotes[0].slide)
        let events = draft.bassEvents(keyRoot: 0, minor: true)
        #expect(events[0].tick + events[0].duration > events[1].tick, "A slide holds into the next note")
        #expect(events[1].tick + events[1].duration < events[2].tick, "A plain note ends before the next")
        let kit = Dictionary(uniqueKeysWithValues: try PaletteEngine.kit(.drill).map { ($0.pad, $0.asset) })
        let bass = try FactorySynth.sub808.asset().asset
        let song = try BeatMachine.candidate(Project.demo(), draft: draft, scope: .song, kit: kit, bass: bass)
        let track = try #require(BeatMachine.bassTrack(in: song))
        #expect(song.tracks[track].glide == 0.07)
        for index in draft.bassNotes.indices where draft.bassNotes[index].slide { draft.toggleSlide(step: draft.bassNotes[index].step) }
        #expect(!draft.hasSlides)
        let plain = try BeatMachine.candidate(song, draft: draft, scope: .song, kit: kit, bass: bass)
        #expect(plain.tracks[track].glide == nil)
        var invalid = Project.demo(); invalid.tracks[1].glide = 0.1
        #expect(throws: MusicError.self) { try invalid.validate() }
    }
}
