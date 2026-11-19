import Foundation
import Testing
@testable import MusicDomain

/// Build 45 corpus: 20 new, fixed descriptions (8 new songs, 8 targeted edits,
/// 4 ambiguous or contradictory requests) plus Andrey's three regressions.
/// Every edit is rendered before and after through the offline renderer: bars
/// outside the edited range (plus one bar of tail) must be sample-identical and
/// the edited bars must actually change. Set GRILLA_SONG_EDIT_REPORT to a file
/// path to write the per-request results table as JSON.
struct SongEditCorpusTests {
    struct Outcome: Codable {
        var id: String, language: String, category: String, text: String
        var expected: String, actual: String, protected: String, rendered: String, pass: Bool
    }

    // MARK: Rendering helpers

    static func library(for project: Project) throws -> SampleLibrary {
        var library = SampleLibrary()
        if let kick = project.tracks.first(where: { $0.role == .drums })?.padSamples?[0] {
            library.insert(try PreparedSampleBank(asset: kick, data: try SongEditFixture.kickData()))
        }
        return library
    }

    /// Mono-summed PCM of a 24-bit stereo WAV.
    static func pcm(_ url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        var offset = 12
        while offset + 8 <= data.count {
            let id = String(decoding: data[offset..<offset + 4], as: UTF8.self)
            let size = Int(data[offset + 4]) | Int(data[offset + 5]) << 8 | Int(data[offset + 6]) << 16 | Int(data[offset + 7]) << 24
            if id == "data" {
                let body = data[(offset + 8)..<(offset + 8 + size)]
                let bytes = [UInt8](body)
                var out: [Float] = []
                out.reserveCapacity(bytes.count / 6)
                var i = 0
                while i + 5 < bytes.count {
                    func sample(_ j: Int) -> Float {
                        var v = Int32(bytes[j]) | Int32(bytes[j + 1]) << 8 | Int32(bytes[j + 2]) << 16
                        if v & 0x800000 != 0 { v -= 0x1000000 }
                        return Float(v) / 8_388_608
                    }
                    out.append(sample(i) + sample(i + 3)); i += 6
                }
                return out
            }
            offset += 8 + size + (size & 1)
        }
        throw ExportError.invalidArchive
    }

    /// Bars (0-based) whose rendered audio differs between two projects.
    static func changedBars(_ before: Project, _ after: Project) async throws -> [Int] {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("song-edit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let settings = WAVSettings(sampleRate: 48_000, bitDepth: 24, tailSeconds: 0, dither: false)
        let a = folder.appendingPathComponent("a.wav"), b = folder.appendingPathComponent("b.wav")
        _ = try await OfflineRenderer.render(before, to: a, settings: settings, samples: try library(for: before))
        _ = try await OfflineRenderer.render(after, to: b, settings: settings, samples: try library(for: after))
        let x = try pcm(a), y = try pcm(b)
        let framesPerBar = Int((Double(barTicks) / Double(ppq) * 60 / before.bpm * 48_000).rounded())
        var bars: [Int] = []
        for bar in 0..<(before.length / barTicks) {
            let range = (bar * framesPerBar)..<min(x.count, y.count, (bar + 1) * framesPerBar)
            if range.isEmpty { continue }
            var difference: Float = 0
            for i in range { difference = max(difference, abs(x[i] - y[i])) }
            if difference > 1e-5 { bars.append(bar) }
        }
        return bars
    }

    static func write(_ outcomes: [Outcome], name: String) throws {
        guard let path = ProcessInfo.processInfo.environment["GRILLA_SONG_EDIT_REPORT"] else { return }
        let url = URL(fileURLWithPath: path).deletingPathExtension().appendingPathExtension("\(name).json")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(outcomes).write(to: url)
    }

    static func summary(_ plan: SongEditPlan, _ p: Project) -> String {
        var parts = plan.operations.map { $0.summary(in: p) }
        parts += plan.problems.map { "problem(\($0.reason.rawValue)): \($0.fragment)" }
        parts += plan.choices.map { "choice: \($0.label)" }
        return parts.joined(separator: "; ")
    }

    // MARK: 8 new songs (+3 regressions)

    struct SongCase: Sendable {
        let id: String, language: String, text: String, expected: String
        let check: @Sendable (TrackBrief, Project) -> Bool
    }

    static let songs: [SongCase] = [
        SongCase(id: "N1", language: "RU", text: "Сделай бит в стиле boom bap, 90 bpm, ре минор, 8 тактов, аккорды: Dm Bb Gm A7",
                 expected: "Boom bap, 90 BPM, D minor, 8 bars, written chords Dm Bb Gm A7 kept") { brief, song in
            song.bpm == 90 && song.keyRoot == 2 && song.minor && song.length == 8 * barTicks && brief.hipHopFeel == .boomBap
                && Arrangement.harmony(song, section: Section(name: "All", start: 0, length: song.length)).map(\.chord.root).prefix(4).elementsEqual([2, 10, 7, 9])
        },
        SongCase(id: "N2", language: "EN", text: "Make a house track at 124 bpm in A minor, 16 bars, chords: Am F C G",
                 expected: "House, 124 BPM, A minor, 16 bars, Am F C G") { brief, song in
            brief.style == .house && song.bpm == 124 && song.keyRoot == 9 && song.minor && song.length == 16 * barTicks
                && Set(Arrangement.harmony(song, section: Section(name: "All", start: 0, length: song.length)).map(\.chord.root)) == [9, 5, 0, 7]
        },
        SongCase(id: "N3", language: "RU", text: "Сделай джазовый трек 106 бпм, до мажор, 8 тактов, аккорды: Dm7 G7 Cmaj7 Am7",
                 expected: "Jazz, 106 BPM, C major, 8 bars, ii–V–I–vi as written") { brief, song in
            brief.style == .jazz && song.bpm == 106 && song.keyRoot == 0 && !song.minor && song.length == 8 * barTicks
                && Arrangement.harmony(song, section: Section(name: "All", start: 0, length: song.length)).first?.chord.quality == .m7
        },
        SongCase(id: "N4", language: "EN", text: "Create a West Coast beat, 94 bpm, G minor, 8 bars",
                 expected: "West Coast hip-hop feel, 94 BPM, G minor, 8 bars") { brief, song in
            brief.hipHopFeel == .westCoast && song.bpm == 94 && song.keyRoot == 7 && song.minor && song.length == 8 * barTicks
        },
        SongCase(id: "N5", language: "RU", text: "Сделай ночной лоу-фай бит на 4 такта",
                 expected: "Lo-fi hip-hop, night mood: minor, 96 BPM, 4 bars") { brief, song in
            brief.style == .hipHop && song.minor && song.bpm == 96 && song.length == 4 * barTicks
        },
        SongCase(id: "N6", language: "EN", text: "Make a jazz track, 4 bars, chords: Fmaj7 Em7 Am7 D9",
                 expected: "Written chords win over the jazz default progression") { brief, song in
            let symbols = Arrangement.harmony(song, section: Section(name: "All", start: 0, length: song.length)).map(\.chord.symbol)
            let heard = symbols.enumerated().filter { $0.offset == 0 || symbols[$0.offset - 1] != $0.element }.map(\.element)
            return heard == ["Fmaj7", "Em7", "Am7", "D9"]
        },
        SongCase(id: "N7", language: "RU", text: "Сделай хаус трек 128 бпм, 8 тактов, в конце полтакта тишины",
                 expected: "House 128 BPM, 8 bars, the last half bar is silent") { brief, song in
            brief.endBreak && song.bpm == 128 && Compiler.notes(song).allSatisfy { $0.tick < song.length - barTicks / 2 }
        },
        SongCase(id: "N8", language: "EN", text: "Make a chillhop beat at 88 bpm, E minor, 8 bars, laid back keys",
                 expected: "Hip-hop 88 BPM, E minor, keys about 24 ms behind the beat") { brief, song in
            brief.laidBackKeys && song.bpm == 88 && song.keyRoot == 4 && song.minor
                && (Compiler.notes(song).filter { $0.track == 0 }.first.map { $0.tick % ppq != 0 } ?? false)
        },
        // Andrey's three musical regressions stay in the corpus as creation requests.
        SongCase(id: "A1", language: "RU", text: ExpressiveArrangementTests().chillhop,
                 expected: "Chillhop 90 BPM E minor: flute bar, beat with late piano, 16 developing bars on C D B E, arpeggio part, one gong") { _, song in
            song.bpm == 90 && song.keyRoot == 4 && song.minor && song.sections.map(\.length) == [1, 16, 8, 1].map { $0 * barTicks }
        },
        SongCase(id: "A2", language: "RU", text: SongFormBriefTests().workout,
                 expected: "D minor workout: four-on-the-floor kick, offbeat hats, 8 bars A Bb C D, 16 calmer bars D E F G, the first part returns") { _, song in
            song.keyRoot == 2 && song.minor && song.sections.map(\.start) == [0, 8 * barTicks, 24 * barTicks]
        },
        SongCase(id: "A3", language: "RU", text: ExpressiveArrangementTests().meditation,
                 expected: "Ambient C Bb G Ab: 8-bar intro, 8 bars of bansuri, sparse keys, long delays, gradual fade with tail") { _, song in
            song.sections.first?.length == 8 * barTicks && song.masterFX != nil
        },
    ]

    @Test func newSongsAreCreationRequestsAndKeepExplicitValues() throws {
        var outcomes: [Outcome] = []
        var failures: [String] = []
        let open = try SongEditFixture.project()
        for item in Self.songs {
            var actual = "", pass = false
            let intent = SongEditParser.intent(item.text, project: open)
            do {
                guard let brief = try TrackBrief.offlineCreationRequest(item.text) else { throw TrackBriefError.unknownIdea }
                let song = try brief.makeProject(name: item.id, sourcePrompt: item.text)
                try song.validate()
                pass = intent == .create && item.check(brief, song)
                actual = "intent=\(intent.rawValue); \(Int(song.bpm)) BPM, \(song.keyName), \(song.length / barTicks) bars, \(song.sections.count) sections, \(Compiler.notes(song).count) notes"
            } catch { actual = "intent=\(intent.rawValue); error: \(error)" }
            if !pass { failures.append("\(item.id): \(actual)") }
            outcomes.append(Outcome(id: item.id, language: item.language, category: item.id.hasPrefix("A") ? "regression" : "new song", text: item.text,
                                    expected: item.expected, actual: actual, protected: "—", rendered: "offline project valid", pass: pass))
        }
        try Self.write(outcomes, name: "songs")
        #expect(failures.isEmpty, "\(failures)")
    }

    // MARK: 8 targeted edits

    struct EditCase: Sendable {
        let id: String, language: String, text: String, expected: String
        let derivedBass: Bool
        let check: @Sendable (SongEditPlan, Project) -> Bool
    }

    static let edits: [EditCase] = [
        EditCase(id: "E1", language: "RU", text: "Убери хэт во втором куплете", expected: "Hats removed in bars 11–14 only; the first verse shares the pattern and stays", derivedBass: false) { plan, p in
            plan.operations.count == 1 && plan.operations[0].kind == .remove && plan.operations[0].target.pads == [2, 3] && plan.operations[0].bars == 10..<14
        },
        EditCase(id: "E2", language: "EN", text: "Make the hats busier in the last chorus", expected: "Hats denser in bars 15–18", derivedBass: false) { plan, p in
            plan.operations.count == 1 && plan.operations[0].kind == .denser && plan.operations[0].bars == 14..<18 && plan.operations[0].target.pads == [2, 3]
        },
        EditCase(id: "E3", language: "RU", text: "Убери бочьку в последнем такте", expected: "Typo «бочьку» understood: kick removed in bar 18", derivedBass: false) { plan, p in
            plan.operations.count == 1 && plan.operations[0].kind == .remove && plan.operations[0].target.pads == [0] && plan.operations[0].bars == 17..<18
        },
        EditCase(id: "E4", language: "RU", text: "Сделай бас реже во втором припеве, аккорды не трогай", expected: "Bass line sparser in bars 15–18; chords protected", derivedBass: false) { plan, p in
            plan.operations.count == 1 && plan.operations[0].kind == .sparser && plan.operations[0].bars == 14..<18
                && plan.operations[0].target.trackID == p.tracks.first { $0.name == "Bass" }!.id && plan.protectedTracks == [p.tracks[0].id]
        },
        EditCase(id: "E5", language: "EN", text: "Fade the flute out over the last four bars", expected: "Flute fades out over bars 15–18; the hand-played pickup in bar 1 is unchanged", derivedBass: false) { plan, p in
            plan.operations.count == 1 && plan.operations[0].kind == .fadeOut && plan.operations[0].bars == 14..<18
                && plan.operations[0].target.trackID == p.tracks.first { $0.name == "Flute" }!.id
        },
        EditCase(id: "E6", language: "RU", text: "Пианино пусть слегка запаздывает в первом куплете", expected: "Keys (harmony) about 24 ms late in bars 3–6", derivedBass: false) { plan, p in
            plan.operations.count == 1 && plan.operations[0].kind == .delay && plan.operations[0].bars == 2..<6 && plan.operations[0].target.trackID == p.tracks[0].id
                && plan.operations[0].amount == Int((0.024 * p.bpm * Double(ppq) / 60).rounded())
        },
        EditCase(id: "E7", language: "RU", text: "Добавь арпеджио по аккордам во втором припеве", expected: "New arpeggio part over the existing chords in bars 15–18", derivedBass: false) { plan, p in
            plan.operations.count == 1 && plan.operations[0].kind == .arpeggiate && plan.operations[0].bars == 14..<18
        },
        EditCase(id: "E8", language: "EN", text: "Mute the kick every other bar in the first verse", expected: "Kick (own sample) silent in bars 4 and 6; sample assignment kept", derivedBass: false) { plan, p in
            plan.operations.count == 1 && plan.operations[0].kind == .remove && plan.operations[0].everyOther && plan.operations[0].editedBars == [3, 5] && plan.operations[0].target.pads == [0]
        },
    ]

    @Test func targetedEditsChangeOnlyTheirBarsAndParts() async throws {
        var outcomes: [Outcome] = []
        var failures: [String] = []
        for item in Self.edits {
            let p = try SongEditFixture.project(derivedBass: item.derivedBass)
            let plan = SongEditParser.plan(item.text, project: p)
            var pass = SongEditParser.intent(item.text, project: p) == .edit && plan.isApplicable && item.check(plan, p)
            var rendered = "not rendered", protectedText = "—"
            if plan.isApplicable {
                do {
                    let edited = try SongEditor.apply(plan, to: p)
                    let bars = try await Self.changedBars(p, edited)
                    let allowed = Set(plan.operations.flatMap { op -> [Int] in
                        let edited = op.kind == .fill ? [op.bars.upperBound - 1] : op.editedBars
                        return edited + edited.map { $0 + 1 }
                    })
                    let core = Set(plan.operations.flatMap { $0.kind == .fill ? [$0.bars.upperBound - 1] : $0.editedBars })
                    let outside = bars.filter { !allowed.contains($0) }
                    let heard = !Set(bars).isDisjoint(with: core)
                    rendered = "changed bars \(bars.map { $0 + 1 }); outside range: \(outside.map { $0 + 1 })"
                    pass = pass && outside.isEmpty && heard
                    // Untargeted parts, the hand-played note, sample and mix.
                    let diff = SongEditDiff(before: p, after: edited)
                    let targeted = Set(plan.operations.map(\.target.trackID))
                    let untouched = p.tracks.filter { !targeted.contains($0.id) }.allSatisfy { diff.events(on: $0.id).added.isEmpty && diff.events(on: $0.id).removed.isEmpty }
                    let pickup = Compiler.notes(edited, range: 0..<barTicks).contains { $0.pitch == 76 && $0.velocity == 101 }
                    // A new arpeggio part may be appended; every original track keeps its mix and sound.
                    let mix = Array(edited.tracks.prefix(p.tracks.count)).map(\.gain) == p.tracks.map(\.gain) && edited.master == p.master
                        && edited.tracks[1].padSamples == p.tracks[1].padSamples && Array(edited.tracks.prefix(p.tracks.count)).map(\.presetVersion) == p.tracks.map(\.presetVersion)
                    protectedText = "untargeted parts \(untouched ? "identical" : "CHANGED"), manual pickup \(pickup ? "kept" : "LOST"), mix/sample \(mix ? "kept" : "CHANGED")"
                    pass = pass && untouched && pickup && mix
                    // Undo restores the source exactly.
                    var history = History(), project = p
                    try history.apply(&project) { $0 = edited }
                    history.undo(&project)
                    pass = pass && project.tracks == p.tracks && project.patterns == p.patterns
                } catch { rendered = "apply error: \(error)"; pass = false }
            }
            if !pass { failures.append("\(item.id): \(Self.summary(plan, p)) | \(rendered) | \(protectedText)") }
            outcomes.append(Outcome(id: item.id, language: item.language, category: "edit", text: item.text, expected: item.expected,
                                    actual: Self.summary(plan, p), protected: protectedText, rendered: rendered, pass: pass))
        }
        try Self.write(outcomes, name: "edits")
        #expect(failures.isEmpty, "\(failures)")
    }

    // MARK: 4 ambiguous or contradictory requests

    static let unclear: [EditCase] = [
        EditCase(id: "Q1", language: "RU", text: "Сделай хэт плотнее в припеве", expected: "Two choruses: ask which one (bars 7–10 or 15–18)", derivedBass: false) { plan, p in
            plan.needsClarification && plan.choices.map(\.sectionID) == [p.sections[2].id, p.sections[4].id] && plan.problems.isEmpty
        },
        EditCase(id: "Q2", language: "EN", text: "Keep the drums and remove the kick in the first chorus", expected: "Contradiction: the kick is part of the kept drums", derivedBass: false) { plan, p in
            plan.problems.contains { $0.reason == .contradiction } && !plan.isApplicable
        },
        EditCase(id: "Q3", language: "RU", text: "Добавь вокал во второй припев и сделай его грустнее", expected: "Unsupported: vocals and «sadder» are named as the problem; draft kept", derivedBass: false) { plan, p in
            !plan.isApplicable && plan.problems.contains { $0.reason == .unsupported && $0.fragment.lowercased().contains("вокал") }
        },
        EditCase(id: "Q4", language: "RU", text: "Оставь бас и убери аккорды в первом куплете", expected: "The bass is built from the chords: removing them would change the kept bass", derivedBass: true) { plan, p in
            !plan.isApplicable && plan.problems.contains { $0.reason == .derivedBass }
        },
    ]

    @Test func ambiguousAndContradictoryRequestsAskOrExplainInsteadOfGuessing() throws {
        var outcomes: [Outcome] = []
        var failures: [String] = []
        for item in Self.unclear {
            let p = try SongEditFixture.project(derivedBass: item.derivedBass)
            let plan = SongEditParser.plan(item.text, project: p)
            let pass = item.check(plan, p)
            if !pass { failures.append("\(item.id): \(Self.summary(plan, p))") }
            outcomes.append(Outcome(id: item.id, language: item.language, category: "ambiguous", text: item.text, expected: item.expected,
                                    actual: Self.summary(plan, p), protected: "project unchanged (no apply)", rendered: "—", pass: pass))
        }
        try Self.write(outcomes, name: "unclear")
        #expect(failures.isEmpty, "\(failures)")
    }

    // MARK: Changed wording

    /// The same edits in different words give the same operations: the parser
    /// reads forms and scope, not a stored example string.
    @Test func rephrasedRequestsGiveTheSameOperations() throws {
        let p = try SongEditFixture.project()
        let groups: [[String]] = [
            ["Убери хэт во втором куплете", "Во втором куплете хэты убери", "удали хай-хэт из второго куплета", "Remove the hi-hats in the second verse", "Mute hats in verse 2"],
            ["Убери бочку в первых двух тактах", "В первых 2 тактах без бочки", "Remove the kick in the first two bars", "drop the kick for the first 2 bars", "Выключи бочку в тактах 1-2"],
            ["Сделай хэт плотнее в последнем припеве", "Хэты в последнем припеве сделай гуще", "Make the hats busier in the last chorus", "busier hi-hats in the final chorus"],
        ]
        for group in groups {
            let reference = SongEditParser.plan(group[0], project: p).operations
            #expect(!reference.isEmpty)
            for text in group.dropFirst() {
                let ops = SongEditParser.plan(text, project: p).operations
                #expect(ops.map(\.kind) == reference.map(\.kind), "\(text)")
                #expect(ops.map(\.bars) == reference.map(\.bars), "\(text)")
                #expect(ops.map(\.target) == reference.map(\.target), "\(text)")
            }
        }
    }

    @Test func everythingExceptTheBassRespectsTheException() throws {
        let p = try SongEditFixture.project()
        let plan = SongEditParser.plan("Убери всё кроме баса в последнем такте", project: p)
        let bass = p.tracks.first { $0.name == "Bass" }!.id
        #expect(plan.isApplicable)
        #expect(!plan.operations.contains { $0.target.trackID == bass })
        #expect(Set(plan.operations.map(\.target.trackID)) == Set(p.tracks.filter { $0.id != bass }.map(\.id)))
        let edited = try SongEditor.apply(plan, to: p)
        let last = Compiler.notes(edited, range: 17 * barTicks..<18 * barTicks)
        #expect(Set(last.map(\.track)) == [p.tracks.firstIndex { $0.id == bass }!])
    }

    @Test func negationKeepsThePart() throws {
        let p = try SongEditFixture.project()
        let plan = SongEditParser.plan("Не убирай хэт, а бочку убери в последнем припеве", project: p)
        #expect(plan.isApplicable, "\(plan.problems)")
        #expect(plan.operations.map(\.target.pads) == [[0]])
        #expect(plan.protectedTracks.isEmpty || plan.problems.isEmpty)
    }
}
