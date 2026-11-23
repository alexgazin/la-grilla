import Foundation

/// U52 · Finding a sound by what it is, in Russian or English: "тёплые клавиши", "808",
/// "lofi keys", "бас пальцами". Every word must match the name or a tag.
public enum SoundIndex {
    /// Tags for built-in instruments by stable identifier (FactoryInstrument / FactorySynth raw values).
    public static let tags: [String: [String]] = [
        "piano": ["piano", "keys", "acoustic", "пианино", "фортепиано", "рояль", "клавиши", "акустика"],
        "nylon-guitar": ["guitar", "nylon", "acoustic", "strings", "гитара", "нейлон", "акустика", "струны"],
        "flute": ["flute", "wind", "airy", "флейта", "духовые", "воздушный"],
        "bansuri": ["bansuri", "flute", "india", "world", "бансури", "флейта", "индия", "этника"],
        "gong": ["gong", "metal", "ambient", "гонг", "металл", "эмбиент"],
        "ambient-pad": ["pad", "ambient", "atmosphere", "warm", "пэд", "эмбиент", "атмосфера", "тёплый"],
        "electric-piano": ["electric piano", "rhodes", "keys", "soul", "электропиано", "клавиши", "соул"],
        "marimba": ["marimba", "mallet", "wood", "маримба", "дерево", "перкуссия"],
        "vibraphone": ["vibraphone", "vibes", "jazz", "mallet", "вибрафон", "джаз"],
        "organ": ["organ", "drawbar", "church", "орган", "церковный"],
        "alto-sax": ["sax", "saxophone", "alto", "jazz", "саксофон", "альт", "джаз"],
        "tenor-sax": ["sax", "saxophone", "tenor", "jazz", "саксофон", "тенор", "джаз"],
        "soprano-sax": ["sax", "saxophone", "soprano", "саксофон", "сопрано"],
        "baritone-sax": ["sax", "saxophone", "baritone", "low", "саксофон", "баритон", "низкий"],
        "synth-808-sub": ["808", "bass", "sub", "trap", "drill", "бас", "саб", "трэп", "дрилл", "низы"],
        "synth-808-punch": ["808", "bass", "punch", "short", "бас", "панч", "короткий", "трэп"],
        "synth-808-dirty": ["808", "bass", "distorted", "phonk", "rage", "бас", "перегруз", "грязный", "фонк"],
        "synth-log-drum": ["log drum", "bass", "amapiano", "afro", "лог драм", "бас", "амапиано", "афро"],
        "synth-reese-bass": ["reese", "bass", "dnb", "jungle", "garage", "риз", "бас", "драм н бейс", "гараж"],
        "synth-acid-bass": ["acid", "bass", "303", "techno", "house", "эсид", "бас", "техно", "хаус"],
        "synth-finger-bass": ["bass", "finger", "funk", "electric bass", "бас", "пальцами", "фанк", "бас-гитара"],
        "synth-square-bass": ["bass", "square", "synth", "house", "synthwave", "бас", "квадратный", "синт", "синтвейв"],
        "synth-supersaw": ["supersaw", "lead", "edm", "trance", "wide", "лид", "суперсо", "широкий", "транс"],
        "synth-synth-pluck": ["pluck", "synth", "arp", "short", "пицц", "щипок", "синт", "арпеджио"],
        "synth-bell-keys": ["bell", "keys", "trap", "glass", "колокол", "клавиши", "трэп", "стекло"],
        "synth-lofi-keys": ["lofi", "lo-fi", "keys", "rhodes", "chill", "лоуфай", "лоу-фай", "клавиши", "чилл", "тёплый"],
        "synth-synth-brass": ["brass", "synth", "stab", "духовые", "синт", "стэб"],
        "synth-string-pad": ["strings", "pad", "orchestra", "струнные", "пэд", "оркестр", "скрипки"],
        "synth-choir-pad": ["choir", "voices", "pad", "ah", "хор", "голоса", "пэд"],
        "synth-chip-lead": ["8-bit", "chip", "game", "retro", "lead", "8 бит", "чиптюн", "игра", "ретро", "лид"],
    ]

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "ё", with: "е").replacingOccurrences(of: "-", with: " ")
    }

    /// True when every word of the query is found in the name or the tags (empty matches all).
    public static func matches(name: String, id: String, query: String) -> Bool {
        let words = fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return true }
        let haystack = ([fold(name)] + (tags[id] ?? []).map(fold)).joined(separator: " | ")
        return words.allSatisfy { word in
            haystack.contains(word) || (word.count >= 5 && haystack.contains(String(word.prefix(word.count - 1))))
        }
    }

    /// Higher is better: name matches first, then tags.
    public static func score(name: String, id: String, query: String) -> Int {
        let q = fold(query).trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return 0 }
        let folded = fold(name)
        if folded == q { return 100 }
        if folded.hasPrefix(q) { return 80 }
        if folded.contains(q) { return 60 }
        return matches(name: name, id: id, query: query) ? 30 : 0
    }
}

/// U53 · Starred items, kept on this device by stable identifiers.
public struct Favorites: Equatable, Sendable {
    public private(set) var ids: [String]
    public init(_ stored: String) { ids = stored.split(separator: ",").map(String.init).filter { !$0.isEmpty } }
    public var stored: String { ids.joined(separator: ",") }
    public func contains(_ id: String) -> Bool { ids.contains(id) }
    public mutating func toggle(_ id: String) {
        guard !id.isEmpty, !id.contains(",") else { return }
        if let index = ids.firstIndex(of: id) { ids.remove(at: index) } else { ids.append(id) }
        if ids.count > 200 { ids.removeFirst(ids.count - 200) }
    }
}

/// U54 · The last sounds used, newest first, at most eight.
public struct RecentItems: Equatable, Sendable {
    public private(set) var ids: [String]
    public static let limit = 8
    public init(_ stored: String) { ids = Array(stored.split(separator: ",").map(String.init).filter { !$0.isEmpty }.prefix(Self.limit)) }
    public var stored: String { ids.joined(separator: ",") }
    public mutating func use(_ id: String) {
        guard !id.isEmpty, !id.contains(",") else { return }
        ids.removeAll { $0 == id }
        ids.insert(id, at: 0)
        if ids.count > Self.limit { ids.removeLast(ids.count - Self.limit) }
    }
}
