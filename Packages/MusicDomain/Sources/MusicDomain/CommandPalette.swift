import Foundation

/// U4 · Every action the search field (and the quick bar, U13) can run.
public enum CommandID: String, CaseIterable, Codable, Sendable {
    case play, record, undo, redo, loop
    case tempo, key, transpose, addSection, duplicateSection, addMelody, deleteLastTake
    case grid, jam, mixer, notes, voice, assistant, harmony, palettes, sections, bass, perform
    case settings, projects, newProject, export, history, versions, trash, midiDevices, chordImport, lyrics, master, focusSection, practice, mood, doctor, earTraining, repeatLast, coNotes, vj, help, continueIdea, grooves, practicePlayer, beatMachine, tuner, markers, dynamics, louder, quieter, brighter, warmer, moreSpace, course, audioTracks, plugins
}

/// What a command needs from the query.
public enum CommandParameter: Sendable, Equatable { case bpm, key, semitones, sectionName }

public enum CommandArgument: Equatable, Sendable, Codable {
    case bpm(Int)
    case key(root: Int, minor: Bool)
    case semitones(Int)
    case name(String)
}

public struct CommandDescriptor: Sendable, Equatable, Identifiable {
    public let id: CommandID
    /// English title, also the localization key.
    public let title: String
    public let symbol: String
    public let parameter: CommandParameter?
    /// Lower-case words people type, Russian and English.
    public let synonyms: [String]
}

public struct CommandMatch: Equatable, Sendable, Codable {
    public let command: CommandID
    public let argument: CommandArgument?
    public let score: Double
    public init(command: CommandID, argument: CommandArgument?, score: Double) { self.command = command; self.argument = argument; self.score = score }
}

public enum CommandCatalog {
    public static let all: [CommandDescriptor] = [
        .init(id: .play, title: "Play or stop", symbol: "playpause.fill", parameter: nil,
              synonyms: ["play", "stop", "start", "pause", "играть", "играй", "стоп", "старт", "пауза", "воспроизвести", "остановить", "запусти"]),
        .init(id: .record, title: "Record drums", symbol: "record.circle", parameter: nil,
              synonyms: ["record", "rec", "record drums", "запись", "записать", "запиши", "записывать", "запись барабанов"]),
        .init(id: .undo, title: "Undo", symbol: "arrow.uturn.backward", parameter: nil,
              synonyms: ["undo", "back", "отмена", "отменить", "отмени", "назад", "верни как было"]),
        .init(id: .redo, title: "Redo", symbol: "arrow.uturn.forward", parameter: nil,
              synonyms: ["redo", "повтор", "повторить", "вернуть отменённое", "вперёд"]),
        .init(id: .loop, title: "Loop on or off", symbol: "repeat", parameter: nil,
              synonyms: ["loop", "repeat", "цикл", "луп", "зациклить", "повторять"]),
        .init(id: .tempo, title: "Set tempo", symbol: "metronome", parameter: .bpm,
              synonyms: ["tempo", "bpm", "speed", "темп", "бпм", "скорость", "быстрее", "медленнее"]),
        .init(id: .key, title: "Set key", symbol: "tuningfork", parameter: .key,
              synonyms: ["key", "scale", "тональность", "лад", "тоника", "в тональности"]),
        .init(id: .transpose, title: "Transpose the song", symbol: "arrow.up.arrow.down", parameter: .semitones,
              synonyms: ["transpose", "shift", "semitones", "транспонировать", "транспонируй", "транспонирование", "полутон", "полутона", "выше", "ниже", "сдвинуть тон"]),
        .init(id: .addSection, title: "Add a section", symbol: "plus.rectangle", parameter: .sectionName,
              synonyms: ["add section", "new section", "add chorus", "add verse", "добавить секцию", "добавь секцию", "новая секция", "добавь припев", "добавь куплет", "добавь бридж"]),
        .init(id: .duplicateSection, title: "Duplicate this section", symbol: "plus.square.on.square", parameter: nil,
              synonyms: ["duplicate section", "copy section", "дублировать секцию", "копия секции", "повторить секцию", "дублируй"]),
        .init(id: .addMelody, title: "Add a melody track", symbol: "music.note", parameter: nil,
              synonyms: ["add melody", "new track", "melody track", "добавить мелодию", "новая дорожка", "дорожка мелодии", "добавь мелодию"]),
        .init(id: .deleteLastTake, title: "Delete the last take", symbol: "arrow.uturn.backward.circle", parameter: nil,
              synonyms: ["delete last take", "remove take", "удалить последний дубль", "удали дубль", "убрать дубль", "последний дубль"]),
        .init(id: .grid, title: "Open Grid", symbol: "square.grid.3x3", parameter: nil,
              synonyms: ["grid", "arrangement", "chords", "сетка", "аранжировка", "аккорды"]),
        .init(id: .jam, title: "Open Jam", symbol: "square.grid.2x2", parameter: nil,
              synonyms: ["jam", "pads", "drums", "beat", "джем", "пэды", "пады", "барабаны", "бит", "карманный бит"]),
        .init(id: .mixer, title: "Open Mixer", symbol: "slider.vertical.3", parameter: nil,
              synonyms: ["mixer", "mix", "volume", "микшер", "сведение", "громкость"]),
        .init(id: .notes, title: "Open Piano roll", symbol: "pianokeys", parameter: nil,
              synonyms: ["piano roll", "notes", "melody", "ноты", "пиано ролл", "мелодия", "редактор нот"]),
        .init(id: .voice, title: "Hum to MIDI", symbol: "mic", parameter: nil,
              synonyms: ["hum", "voice", "sing", "voice to midi", "напев", "напеть", "голос", "спеть", "напев в midi"]),
        .init(id: .assistant, title: "Open Assistant", symbol: "sparkles", parameter: nil,
              synonyms: ["assistant", "ai", "help me", "ассистент", "помощник", "ии", "нейросеть"]),
        .init(id: .harmony, title: "Open Harmony lab", symbol: "music.quarternote.3", parameter: nil,
              synonyms: ["harmony", "progression", "reharmonize", "гармония", "прогрессия", "лаборатория гармонии", "реармонизация"]),
        .init(id: .palettes, title: "Open Sound palettes", symbol: "paintpalette", parameter: nil,
              synonyms: ["palette", "sound", "kit", "палитра", "звук", "набор", "палитры звука"]),
        .init(id: .sections, title: "Edit sections", symbol: "rectangle.split.3x1", parameter: nil,
              synonyms: ["sections", "form", "structure", "секции", "структура", "форма песни"]),
        .init(id: .bass, title: "Bass settings", symbol: "waveform.path", parameter: nil,
              synonyms: ["bass", "бас", "басс", "настройки баса"]),
        .init(id: .perform, title: "Perform", symbol: "music.mic", parameter: nil,
              synonyms: ["perform", "live", "stage", "выступление", "концерт", "сцена", "живое исполнение"]),
        .init(id: .settings, title: "Settings", symbol: "gearshape", parameter: nil,
              synonyms: ["settings", "preferences", "настройки", "параметры"]),
        .init(id: .projects, title: "Projects", symbol: "square.stack.3d.up", parameter: nil,
              synonyms: ["projects", "open project", "проекты", "открыть проект", "мои песни"]),
        .init(id: .newProject, title: "New project", symbol: "plus", parameter: nil,
              synonyms: ["new project", "new song", "новый проект", "новая песня", "создать проект"]),
        .init(id: .export, title: "Export", symbol: "square.and.arrow.up", parameter: nil,
              synonyms: ["export", "share", "wav", "mp3", "aac", "midi file", "экспорт", "поделиться", "сохранить файл", "выгрузить"]),
        .init(id: .history, title: "Edit history", symbol: "clock.arrow.circlepath", parameter: nil,
              synonyms: ["history", "edit history", "история", "история правок", "что я менял"]),
        .init(id: .versions, title: "Song versions", symbol: "bookmark", parameter: nil,
              synonyms: ["versions", "snapshot", "save version", "версии", "версия", "сохранить версию", "снимок"]),
        .init(id: .trash, title: "Recently deleted", symbol: "trash", parameter: nil,
              synonyms: ["trash", "deleted", "restore", "корзина", "удалённые", "недавно удалённые", "вернуть удалённое"]),
        .init(id: .chordImport, title: "Chords from a song or photo", symbol: "camera.viewfinder", parameter: nil,
              synonyms: ["chords from song", "chords from photo", "detect chords", "аккорды из песни", "аккорды с фото", "распознать аккорды", "подобрать аккорды", "аккорды из текста"]),
        .init(id: .lyrics, title: "Lyrics", symbol: "text.quote", parameter: nil,
              synonyms: ["lyrics", "words", "text", "текст песни", "слова", "текст", "лирика"]),
        .init(id: .master, title: "Prepare for release", symbol: "gauge.with.dots.needle.67percent", parameter: nil,
              synonyms: ["master", "mastering", "loudness", "lufs", "release", "мастеринг", "громкость трека", "к выпуску", "подготовить к выпуску", "мастер"]),
        .init(id: .focusSection, title: "Focus on this section", symbol: "scope", parameter: nil,
              synonyms: ["focus", "focus section", "loop section", "фокус", "фокус на секции", "зациклить секцию", "только эта секция"]),
        .init(id: .practice, title: "Practice slower", symbol: "tortoise", parameter: nil,
              synonyms: ["practice", "slower", "slow down", "практика", "медленнее", "замедлить", "потренироваться", "разучить"]),
        .init(id: .mood, title: "Progression by mood", symbol: "theatermasks", parameter: nil,
              synonyms: ["mood", "progression by mood", "sad chords", "happy chords", "настроение", "грустные аккорды", "весёлые аккорды", "прогрессия по настроению"]),
        .init(id: .doctor, title: "Check the song", symbol: "stethoscope", parameter: nil,
              synonyms: ["check song", "check arrangement", "problems", "проверить песню", "проверка", "что не так", "ошибки в аранжировке"]),
        .init(id: .earTraining, title: "Ear training", symbol: "ear", parameter: nil,
              synonyms: ["ear training", "guess chord", "quiz", "тренировка слуха", "угадай аккорд", "слух", "сольфеджио"]),
        .init(id: .repeatLast, title: "Repeat the last action", symbol: "arrow.clockwise", parameter: nil,
              synonyms: ["repeat", "again", "repeat last", "повторить", "ещё раз", "повтори последнее", "то же самое"]),
        .init(id: .coNotes, title: "Notes for co-authors", symbol: "note.text", parameter: nil,
              synonyms: ["notes", "comments", "co-author", "заметки", "комментарии", "соавтор", "заметки для соавтора"]),
        .init(id: .vj, title: "Stage visuals", symbol: "sparkles.tv", parameter: nil,
              synonyms: ["visuals", "vj", "visualizer", "stage screen", "визуализация", "визуализатор", "вид для сцены", "вджей"]),
        .init(id: .help, title: "Help", symbol: "questionmark.circle", parameter: nil,
              synonyms: ["help", "how", "tips", "справка", "помощь", "как пользоваться", "подсказки"]),
        .init(id: .continueIdea, title: "Continue for me", symbol: "arrow.forward.to.line", parameter: nil,
              synonyms: ["continue", "extend", "next part", "продолжи", "продолжить", "продолжи за меня", "следующая часть"]),
        .init(id: .beatMachine, title: "Beat machine", symbol: "square.grid.4x3.fill", parameter: nil,
              synonyms: ["beat machine", "drum machine", "groovebox", "beat maker", "sampler", "808", "hip hop beat", "trap beat", "sequencer",
                         "битмашина", "драм машина", "драм-машина", "грувбокс", "битмейкер", "сделать бит", "секвенсор", "пресеты битов"]),
        .init(id: .louder, title: "Louder", symbol: "speaker.plus", parameter: nil,
              synonyms: ["louder", "make it louder", "volume up", "громче", "сделай громче", "погромче", "прибавь громкость"]),
        .init(id: .quieter, title: "Quieter", symbol: "speaker.minus", parameter: nil,
              synonyms: ["quieter", "softer", "volume down", "тише", "сделай тише", "потише", "убавь громкость"]),
        .init(id: .brighter, title: "Brighter", symbol: "sun.max", parameter: nil,
              synonyms: ["brighter", "more highs", "crisper", "ярче", "сделай ярче", "больше верхов", "звонче"]),
        .init(id: .warmer, title: "Warmer", symbol: "flame", parameter: nil,
              synonyms: ["warmer", "more low end", "softer highs", "теплее", "сделай теплее", "больше низов", "мягче"]),
        .init(id: .moreSpace, title: "More space", symbol: "sparkles", parameter: nil,
              synonyms: ["more space", "more echo", "wider", "больше простора", "больше эха", "просторнее", "объёмнее"]),
        .init(id: .audioTracks, title: "Record audio", symbol: "mic.circle", parameter: nil,
              synonyms: ["record audio", "record vocals", "audio track", "record guitar", "sing over", "записать голос", "записать вокал", "аудиодорожка", "записать гитару", "запись звука", "спеть"]),
        .init(id: .plugins, title: "Plugins (AUv3)", symbol: "puzzlepiece.extension", parameter: nil,
              synonyms: ["plugins", "auv3", "audio unit", "effect plugin", "instrument plugin", "bounce", "плагины", "плагин", "эффект", "инструмент", "аудиоюнит"]),
        .init(id: .course, title: "Harmony course", symbol: "graduationcap", parameter: nil,
              synonyms: ["course", "lessons", "learn harmony", "theory", "assignment", "teacher", "курс", "уроки", "теория", "гармония", "задание", "учитель", "научиться"]),
        .init(id: .tuner, title: "Tuner", symbol: "tuningfork", parameter: nil,
              synonyms: ["tuner", "tune guitar", "tune", "pitch", "тюнер", "настроить гитару", "настройка гитары", "строй", "настроить"]),
        .init(id: .markers, title: "Markers", symbol: "flag", parameter: nil,
              synonyms: ["markers", "marker", "flag", "note on timeline", "маркеры", "маркер", "метка", "метки", "флажок", "заметка на таймлайне"]),
        .init(id: .dynamics, title: "Song dynamics", symbol: "chart.line.uptrend.xyaxis", parameter: nil,
              synonyms: ["dynamics", "energy", "sparse intro", "build up", "динамика", "динамика песни", "разбавить", "нарастание", "энергия песни"]),
        .init(id: .grooves, title: "Starter grooves", symbol: "music.quarternote.3", parameter: nil,
              synonyms: ["grooves", "ready beat", "drum pattern", "groove", "готовый бит", "грув", "ритм по жанру", "стартовые грувы"]),
        .init(id: .practicePlayer, title: "Work out a song", symbol: "ear.badge.waveform", parameter: nil,
              synonyms: ["work out", "transcribe", "slow down song", "learn song", "подобрать", "подбор", "разобрать песню", "замедлить песню"]),
        .init(id: .midiDevices, title: "MIDI devices", symbol: "pianokeys.inverse", parameter: nil,
              synonyms: ["midi", "controller", "keyboard", "миди", "контроллер", "миди устройства"]),
    ]

    public static func descriptor(_ id: CommandID) -> CommandDescriptor { all.first { $0.id == id }! }
}

public enum CommandMatcher {
    /// Ranked matches for a typed query; `recent` (newest first) breaks ties.
    public static func rank(_ query: String, recent: [CommandID] = [], limit: Int = 8) -> [CommandMatch] {
        let variants = [normalize(query), normalize(swapLayout(query))].filter { !$0.isEmpty }
        guard !variants.isEmpty else {
            return recent.prefix(limit).map { CommandMatch(command: $0, argument: nil, score: 0) }
        }
        var best: [CommandID: CommandMatch] = [:]
        for text in variants {
            let argument = arguments(in: text)
            for descriptor in CommandCatalog.all {
                var score = descriptor.synonyms.map { similarity(text, $0) }.max() ?? 0
                let value = argument(descriptor.parameter)
                if let parameter = descriptor.parameter, value != nil {
                    // A bare value ("92", "ля минор", "+2") runs its command only when unambiguous.
                    if score > 0 { score += 0.35 } else if standalone(parameter, text) { score = 0.6 }
                }
                guard score > 0.34 else { continue }
                if let index = recent.firstIndex(of: descriptor.id) { score += 0.05 / Double(index + 1) }
                if score > (best[descriptor.id]?.score ?? 0) { best[descriptor.id] = CommandMatch(command: descriptor.id, argument: value, score: score) }
            }
        }
        return best.values.sorted { $0.score == $1.score ? $0.command.rawValue < $1.command.rawValue : $0.score > $1.score }.prefix(limit).map { $0 }
    }

    // MARK: Text

    static func normalize(_ text: String) -> String {
        let lowered = text.lowercased().replacingOccurrences(of: "ё", with: "е")
        let kept = lowered.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || "#+-♯♭".unicodeScalars.contains($0) ? Character($0) : " " }
        return String(kept).split(separator: " ").joined(separator: " ")
    }

    /// Text typed with the wrong keyboard layout (QWERTY ↔ ЙЦУКЕН).
    static func swapLayout(_ text: String) -> String {
        let latin = Array("qwertyuiop[]asdfghjkl;'zxcvbnm,.`")
        let cyrillic = Array("йцукенгшщзхъфывапролджэячсмитьбюё")
        var map: [Character: Character] = [:]
        for (a, b) in zip(latin, cyrillic) { map[a] = b; map[b] = a }
        return String(text.lowercased().map { map[$0] ?? $0 })
    }

    private static func distance(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }; if b.isEmpty { return a.count }
        var previous = Array(0...b.count), current = previous
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count { current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)) }
            swap(&previous, &current)
        }
        return previous[b.count]
    }

    /// How well a word of the query matches a word of a synonym (0…1).
    private static func wordScore(_ word: String, _ target: String) -> Double {
        if word == target { return 1 }
        if target.count >= 3, word.count >= 3, target.hasPrefix(word) || word.hasPrefix(target) { return 0.85 }
        guard word.count >= 4, target.count >= 4 else { return 0 }
        let allowed = target.count >= 7 ? 2 : 1
        let d = distance(Array(word), Array(target))
        return d <= allowed ? 0.75 - Double(d) * 0.1 : 0
    }

    /// Share of the synonym's words found in the query, weighted by how well they match.
    static func similarity(_ query: String, _ synonym: String) -> Double {
        let words = query.split(separator: " ").map(String.init)
        let targets = synonym.split(separator: " ").map(String.init)
        guard !words.isEmpty, !targets.isEmpty else { return 0 }
        let total = targets.reduce(0.0) { sum, target in sum + (words.map { wordScore($0, target) }.max() ?? 0) }
        let coverage = total / Double(targets.count)
        // A synonym that explains more of the query wins: longer phrases get a small bonus,
        // one-word synonyms lose a little for every query word they leave unexplained.
        let explained = Double(min(targets.count, words.count)) / Double(words.count)
        return coverage * (0.85 + 0.15 * explained) * (1 + 0.04 * Double(targets.count - 1))
    }

    // MARK: Arguments

    private static func standalone(_ parameter: CommandParameter, _ text: String) -> Bool {
        let words = text.split(separator: " ").map(String.init)
        switch parameter {
        case .bpm: return words.count <= 2 && words.contains { Int($0) != nil }
        case .semitones: return words.count <= 2 && words.contains { ($0.hasPrefix("+") || $0.hasPrefix("-")) && Int($0) != nil }
        case .key: return words.count <= 4
        case .sectionName: return false
        }
    }

    private static let sectionNames: [(words: [String], name: String)] = [
        (["chorus", "припев"], "Chorus"), (["verse", "куплет"], "Verse"), (["bridge", "бридж", "мост"], "Bridge"),
        (["intro", "интро", "вступление"], "Intro"), (["outro", "аутро", "концовка", "кода"], "Outro"),
        (["prechorus", "предприпев"], "Pre-chorus"), (["drop", "дроп"], "Drop"), (["break", "брейк"], "Break"),
    ]

    /// Lazily parses the argument a parameter kind needs from normalized text.
    private static func arguments(in text: String) -> (CommandParameter?) -> CommandArgument? {
        let words = text.split(separator: " ").map(String.init)
        let numbers = words.compactMap { Int($0.trimmingCharacters(in: CharacterSet(charactersIn: "+"))) }
        return { parameter in
            switch parameter {
            case .bpm?:
                guard let value = numbers.first(where: { (40...240).contains(abs($0)) }) else { return nil }
                return .bpm(abs(value))
            case .semitones?:
                let down = words.contains { ["ниже", "вниз", "down", "lower", "минус"].contains($0) }
                guard let raw = words.compactMap({ Int($0) }).first(where: { (-24...24).contains($0) && $0 != 0 }) else { return nil }
                let value = down && raw > 0 ? -raw : raw
                return .semitones(value)
            case .key?:
                return key(in: words)
            case .sectionName?:
                for (variants, name) in sectionNames where words.contains(where: { word in variants.contains(word) }) { return .name(name) }
                return nil
            case nil:
                return nil
            }
        }
    }

    private static let letterRoots: [String: Int] = ["c": 0, "d": 2, "e": 4, "f": 5, "g": 7, "a": 9, "b": 11, "h": 11]
    private static let solfegeRoots: [String: Int] = ["до": 0, "ре": 2, "ми": 4, "фа": 5, "соль": 7, "ля": 9, "си": 11]

    /// "ля минор", "a minor", "am", "f# major", "до диез мажор", "ebm".
    static func key(in words: [String]) -> CommandArgument? {
        let minorWords: Set = ["минор", "minor", "min", "moll", "минорная"]
        let majorWords: Set = ["мажор", "major", "maj", "dur", "мажорная"]
        for (index, word) in words.enumerated() {
            var root: Int?, rest = Substring("")
            if let value = solfegeRoots[word] { root = value }
            else if let first = word.first.map(String.init), let value = letterRoots[first], word.count <= 4 {
                root = value; rest = word.dropFirst()
                if let mark = rest.first, mark == "#" || mark == "♯" { root! += 1; rest = rest.dropFirst() }
                else if let mark = rest.first, mark == "b" || mark == "♭" { root! -= 1; rest = rest.dropFirst() }
                guard rest.isEmpty || rest == "m" || rest == "min" || rest == "maj" else { continue }
            }
            guard var value = root else { continue }
            let next = index + 1 < words.count ? words[index + 1] : ""
            var after = index + 1
            if next == "диез" || next == "sharp" { value += 1; after += 1 }
            if next == "бемоль" || next == "flat" { value -= 1; after += 1 }
            let mode = after < words.count ? words[after] : ""
            let minor = rest == "m" || rest == "min" || minorWords.contains(mode) || mode.hasPrefix("минор")
            let major = majorWords.contains(mode) || mode.hasPrefix("мажор") || rest == "maj"
            // A lone letter is a key only with a mode word, a sharp/flat or as the whole query.
            let isKey = minor || major || solfegeRoots[word] != nil || word.count >= 2 || words.count == 1
            guard isKey else { continue }
            return .key(root: (value % 12 + 12) % 12, minor: minor)
        }
        return nil
    }
}
