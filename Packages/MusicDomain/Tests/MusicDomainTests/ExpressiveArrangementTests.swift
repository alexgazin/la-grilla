import Foundation
import Testing
@testable import MusicDomain

struct ExpressiveArrangementTests {
    let chillhop = """
    Песня в стиле chillhop. Около 90 бпм. Тональность ми натуральный минор. Вступление один такт флейта и сразу начинается бит, атмосферное слегка опаздывающее пианино.
    Первая часть аккорды: C, D, B, E
    16 тактов с развитием. Далее вторая часть арпеджио этих аккордов и завершаем ударом гонга
    """
    let meditation = """
    Песня для медитации. В стиле эмбиент. Длинные дилеи или подобные эффекты.
    Основные 4 аккорда песни C, Bb, G, Ab .
    Первая часть 8 тактов как вступление, далее вторая часть добавляем соло на флейте Бансури. 8 тактов.
    Третья часть добавляем немного клавиш и далее потихоньку рассеиваем звук что бы закончить трек
    """

    @Test func chillhopEntrancesDevelopmentAndOneGong() throws {
        let brief = try #require(try TrackBrief.offlineCreationRequest(chillhop))
        let song = try brief.makeProject(name: "Chillhop")
        let compiled = Compiler.notes(song)
        #expect(song.sections.map(\.length) == [1,16,8,1].map { $0 * barTicks })
        #expect(song.keyRoot == 4 && song.minor && song.bpm == 90)
        #expect(Set(compiled.filter { $0.tick < barTicks }.map(\.track)) == [3])
        #expect(compiled.first(where: { $0.track == 1 })?.tick == barTicks)
        #expect(compiled.first(where: { $0.track == 0 })?.tick == barTicks+35)
        let main = Arrangement.materialize(song, track: song.tracks[0], section: song.sections[1])
        #expect(main.chords.filter { $0.tick < 8*barTicks }.count == 8)
        #expect(main.chords.filter { $0.tick >= 8*barTicks }.count == 16)
        let brokenSection = compiled.filter { (17*barTicks..<25*barTicks).contains($0.tick) }
        #expect(Set(brokenSection.map(\.track)) == [1,2,4])
        #expect(compiled.filter { $0.track == 5 }.map(\.tick) == [25*barTicks])
        let end = compiled.filter { $0.tick >= 25*barTicks }
        #expect(end.count == 1 && end.first?.duration == barTicks)
        #expect(try PortableProject.decode(PortableProject.data(song), asCopy: false) == song)
    }

    @Test func editedSourceHarmonyDeterminesCompressedArpeggio() throws {
        var brief = try TrackBrief().suggesting(chillhop)
        brief.songForm?.parts[1].chordText = "Am Dm F G"
        brief.songForm?.parts[2].bars = 1
        let song = try brief.makeProject(name: "Arpeggio")
        let section = song.sections[2]
        let arp = Arrangement.materialize(song, track: song.tracks[4], section: section).notes ?? []
        #expect(arp.count == 8)
        for (index, symbol) in ["Am","Dm","F","G"].enumerated() {
            let chord = try Chord.parse(symbol)
            let classes = Set(chord.notes.map { $0 % 12 })
            let notes = arp.filter { $0.tick/ppq == index }
            #expect(notes.count == 2)
            #expect(notes.allSatisfy { classes.contains($0.pitch%12) })
        }
    }

    @Test func ambientArrangementBreathTailsAndPortableDiminuendo() throws {
        let brief = try TrackBrief().suggesting(meditation)
        let song = try brief.makeProject(name: "Meditation")
        let notes = Compiler.notes(song)
        #expect(song.sections.map(\.length) == [8*barTicks,8*barTicks,8*barTicks])
        #expect(song.masterFX?.delayWet ?? 0 > 0)
        #expect(!notes.contains { $0.track == 1 })
        #expect(Set(notes.filter { $0.tick < 8*barTicks }.map(\.track)) == [0])
        for section in song.sections {
            let harmony = Arrangement.materialize(song, track: song.tracks[0], section: section)
            let changes = harmony.chords.map(\.chord.symbol).reduce(into: [String]()) { cycle, symbol in
                if cycle.last != symbol { cycle.append(symbol) }
            }
            #expect(changes == ["C","B♭","G","A♭"])
        }
        let wind = notes.filter { $0.track == 2 }
        #expect(wind.first?.tick ?? 0 >= 8*barTicks)
        #expect(wind.first?.tick ?? 0 < 9*barTicks)
        #expect(wind.allSatisfy { $0.tick + $0.duration <= 16*barTicks })
        let span = zip(wind,wind.dropFirst())
        #expect(span.contains { first, second in second.tick - first.tick - first.duration >= ppq/2 })
        let phrase = try #require(wind.first)
        let echo = try #require(notes.first(where: { $0.track == 4 }))
        #expect(echo.pitch == phrase.pitch && echo.velocity < phrase.velocity && echo.tick-phrase.tick == 3*ppq/2)
        let finalKeys = notes.filter { $0.track == 3 }
        #expect(finalKeys.first?.tick ?? 0 >= 16*barTicks)
        #expect(finalKeys.last?.velocity ?? 127 < 32)
        let closing = Arrangement.materialize(song, track: song.tracks[0], section: song.sections[2])
        let dynamics = closing.chords.compactMap(\.velocity)
        #expect(dynamics.first == 62 && dynamics.last ?? 127 < 8)
        #expect(zip(dynamics,dynamics.dropFirst()).allSatisfy { $0 >= $1 })
        let resized = try Arrangement.resized(song, sectionID: song.sections[2].id, bars: 7)
        let remaining = Arrangement.materialize(resized, track: resized.tracks[0], section: resized.sections[2])
        #expect(remaining.chords.compactMap(\.velocity) == closing.chords.filter { $0.tick < 7*barTicks }.compactMap(\.velocity))
        let imported = try PortableProject.decode(PortableProject.data(song), asCopy: false)
        #expect(Compiler.notes(imported) == notes)
        #expect(try MIDIExporter.data(imported) == MIDIExporter.data(song))
    }
}

extension ExpressiveArrangementTests {
    @Test func shortEditableMeditationAndDryMix() throws {
        var brief = try TrackBrief().suggesting(meditation)
        var form = try #require(brief.songForm)
        form.longDelay = false
        for index in form.parts.indices { form.parts[index].bars = 1 }
        form.fadeBars = 1
        brief.songForm = form
        let dry = try brief.makeProject(name: "Short breathing phrase")
        #expect(dry.tracks.count == 4 && dry.masterFX == nil)
        #expect(dry.length == 3*barTicks)
        for section in dry.sections {
            let chordEvents = Arrangement.materialize(dry, track: dry.tracks[0], section: section).chords
            #expect(chordEvents.map(\.chord.symbol) == ["C","B♭","G","A♭"])
        }
        let lastChordNotes = Compiler.notes(dry, range: 2*barTicks..<3*barTicks).filter { $0.track == 0 }
        #expect(lastChordNotes.last?.velocity ?? 127 < lastChordNotes.first?.velocity ?? 0)
        form.fadeBars = 0
        brief.songForm = form
        let unfaded = try brief.makeProject(name: "Dry ending")
        let sustained = Compiler.notes(unfaded, range: 2*barTicks..<3*barTicks).filter { $0.track == 0 }
        #expect(Set(sustained.map(\.velocity)) == [62])
    }
}
