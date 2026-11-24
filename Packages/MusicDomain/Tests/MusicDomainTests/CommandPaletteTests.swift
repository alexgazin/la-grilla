import Testing
@testable import MusicDomain

struct CommandPaletteTests {
    private func top(_ query: String) -> CommandMatch? { CommandMatcher.rank(query).first }

    @Test(arguments: [
        ("темп 92", CommandID.tempo, CommandArgument.bpm(92)),
        ("tempo 120", .tempo, .bpm(120)),
        ("92 bpm", .tempo, .bpm(92)),
        ("ntvg 92", .tempo, .bpm(92)),
        ("темпп 100", .tempo, .bpm(100)),
        ("92", .tempo, .bpm(92)),
        ("ля минор", .key, .key(root: 9, minor: true)),
        ("тональность ля минор", .key, .key(root: 9, minor: true)),
        ("в ля миноре", .key, .key(root: 9, minor: true)),
        ("a minor", .key, .key(root: 9, minor: true)),
        ("Am", .key, .key(root: 9, minor: true)),
        ("key f# major", .key, .key(root: 6, minor: false)),
        ("до диез мажор", .key, .key(root: 1, minor: false)),
        ("ebm", .key, .key(root: 3, minor: true)),
        ("key Bb", .key, .key(root: 10, minor: false)),
        ("транспонировать на 2", .transpose, .semitones(2)),
        ("транспонируй ниже на 3", .transpose, .semitones(-3)),
        ("transpose -2", .transpose, .semitones(-2)),
        ("+2", .transpose, .semitones(2)),
        ("добавь припев", .addSection, .name("Chorus")),
        ("add verse", .addSection, .name("Verse")),
        ("добавить секцию бридж", .addSection, .name("Bridge")),
    ])
    func parameterisedQueriesRunTheirCommandWithTheValue(query: String, command: CommandID, argument: CommandArgument) {
        let match = top(query)
        #expect(match?.command == command, "\(query) → \(String(describing: match))")
        #expect(match?.argument == argument, "\(query) → \(String(describing: match))")
    }

    @Test(arguments: [
        ("удали последний дубль", CommandID.deleteLastTake), ("отмени", .undo), ("undo", .undo), ("redo", .redo),
        ("играй", .play), ("стоп", .play), ("запиши", .record), ("record drums", .record),
        ("микшер", .mixer), ("mixr", .mixer), ("пэды", .jam), ("карманный бит", .jam), ("сетка", .grid),
        ("напеть", .voice), ("hum", .voice), ("экспорт", .export), ("поделиться", .export), ("история правок", .history),
        ("корзина", .trash), ("недавно удалённые", .trash), ("сохранить версию", .versions), ("версии", .versions),
        ("new project", .newProject), ("новая песня", .newProject), ("settings", .settings), ("sttings", .settings),
        ("ghjtrns", .projects), ("ассистент", .assistant), ("лаборатория гармонии", .harmony), ("палитра", .palettes),
        ("добавь мелодию", .addMelody), ("дублировать секцию", .duplicateSection), ("пиано ролл", .notes), ("луп", .loop),
        ("миди контроллер", .midiDevices), ("выступление", .perform), ("настройки баса", .bass), ("структура", .sections),
        ("битмашина", .beatMachine), ("драм машина", .beatMachine), ("drum machine", .beatMachine), ("грувбокс", .beatMachine), ("808", .beatMachine),
    ])
    func plainQueriesFindTheirAction(query: String, command: CommandID) {
        #expect(top(query)?.command == command, "\(query) → \(String(describing: CommandMatcher.rank(query).prefix(3)))")
    }

    @Test func unrelatedTextFindsNothingAndEmptyShowsRecent() {
        #expect(CommandMatcher.rank("qqqq zzzz").isEmpty)
        #expect(CommandMatcher.rank("  ", recent: [.history, .jam]).map(\.command) == [.history, .jam])
    }

    @Test func recentActionsWinTies() {
        let plain = CommandMatcher.rank("стоп").first?.command
        #expect(plain == .play)
        let ranked = CommandMatcher.rank("версии", recent: [.versions]).first
        #expect(ranked?.command == .versions)
    }

    @Test func everyCommandHasSynonymsInBothLanguages() {
        for descriptor in CommandCatalog.all {
            #expect(descriptor.synonyms.contains { $0.unicodeScalars.contains { $0.value >= 0x0400 && $0.value <= 0x04FF } }, "\(descriptor.id) RU")
            #expect(descriptor.synonyms.contains { $0.unicodeScalars.allSatisfy { $0.value < 0x0400 } }, "\(descriptor.id) EN")
        }
        #expect(Set(CommandCatalog.all.map(\.id)) == Set(CommandID.allCases))
    }
}
