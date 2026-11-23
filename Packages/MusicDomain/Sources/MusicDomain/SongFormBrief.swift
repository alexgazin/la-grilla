import Foundation

public enum SongFormError: LocalizedError {
    case unsupported, length, chords, order
    public var errorDescription: String? {
        switch self {
        case .unsupported: NSLocalizedString("This section request includes instructions the offline arranger cannot play yet.", comment: "Song form")
        case .length: NSLocalizedString("Each part can be 1 to 64 bars, and the whole song up to 64 bars.", comment: "Song form")
        case .chords: NSLocalizedString("Enter a chord progression for each part, for example A, Bb, C, D.", comment: "Song form")
        case .order: NSLocalizedString("Describe the parts in order. A return must refer to an earlier part.", comment: "Song form")
        }
    }
}

public struct SongFormBrief: Codable, Equatable, Sendable {
    public enum Arrangement: String, Codable, Equatable, Sendable { case groove, chillhop, ambient }
    public enum Role: String, Codable, Equatable, Sendable {
        case groove, fluteIntro, developingBeat, arpeggio, gong, ambientIntro, bansuriSolo, keysOutro
        public var usesChords: Bool { self != .fluteIntro && self != .gong }
    }

    public struct Part: Codable, Equatable, Sendable {
        public var bars: Int
        public var chordText: String
        public var relaxed: Bool
        public var role: Role = .groove
        public var chordSource: Int?
        public var proposedBars = false
        /// The chords were not written for this part: they repeat an earlier part or the key's
        /// usual progression, shown as a suggestion. Nil in older recipes.
        public var proposedChords: Bool?
        /// The musician's own name for the part ("Verse", "Припев"). Nil = A, B, C, D.
        public var name: String?
        public init(bars: Int, chordText: String, relaxed: Bool = false, role: Role = .groove,
                    chordSource: Int? = nil, proposedBars: Bool = false, proposedChords: Bool? = nil, name: String? = nil) {
            self.bars = bars
            self.chordText = chordText
            self.relaxed = relaxed
            self.role = role
            self.chordSource = chordSource
            self.proposedBars = proposedBars
            self.proposedChords = proposedChords
            self.name = name
        }
        func chords() throws -> [Chord] {
            let tokens = try AssistantEngine.chordTokens(chordText)
            guard !tokens.isEmpty else { throw SongFormError.chords }
            if role == .groove && tokens.count > bars { throw TrackBriefError.tooManyChords }
            guard tokens.count <= 64 else { throw SongFormError.chords }
            return try tokens.map { token in
                guard let chord = try? Chord.parse(token) else { throw TrackBriefError.invalidChord(token) }
                return chord
            }
        }
    }

    public var parts: [Part]
    public private(set) var order: [Int]
    public var offbeatHats: Bool
    public var proposedTempo: Bool
    public var proposedKey: Bool
    public var arrangement: Arrangement = .groove
    public var longDelay = false
    public var fadeBars = 0
    public var proposedFadeBars = false
    /// Wishes in the description that the offline arranger does not play (an instrument,
    /// a modulation…), as English keys the app localizes. They are listed, never an error.
    public var skipped: [String]?

    public init(parts: [Part], order: [Int], offbeatHats: Bool = false, proposedTempo: Bool = false, proposedKey: Bool = false,
                arrangement: Arrangement = .groove, longDelay: Bool = false, fadeBars: Int = 0,
                proposedFadeBars: Bool = false) {
        self.parts = parts
        self.order = order
        self.offbeatHats = offbeatHats
        self.proposedTempo = proposedTempo
        self.proposedKey = proposedKey
        self.arrangement = arrangement
        self.longDelay = longDelay
        self.fadeBars = fadeBars
        self.proposedFadeBars = proposedFadeBars
    }

    /// Inheritance always points to an earlier definition; there can be no cycles.
    public func resolvedChordText(for index: Int) -> String {
        guard parts.indices.contains(index), parts[index].role.usesChords else { return "" }
        var origin = index
        while let earlier = parts[origin].chordSource {
            guard (0..<origin).contains(earlier) else { return "" }
            origin = earlier
        }
        return parts[origin].chordText
    }

    public func resolvedChords(for index: Int) throws -> [Chord] {
        guard parts.indices.contains(index) else { throw SongFormError.order }
        var part = parts[index]
        guard part.role.usesChords else { return [] }
        part.chordText = resolvedChordText(for: index)
        let chords = try part.chords()
        guard (1...64).contains(part.bars), chords.count <= part.bars * 8 else { throw SongFormError.chords }
        return chords
    }

    public var totalBars: Int {
        var bars = 0
        for index in order {
            guard parts.indices.contains(index), (1...64).contains(parts[index].bars) else { return 0 }
            bars += parts[index].bars
        }
        return bars
    }

    private static let keyPattern = #"(?<![\p{L}\d])([a-g](?:[#♯b♭])?|до|ре|ми|фа|соль|ля|си)[\s-]+(?:(?:natural|натуральный)\s+)?(minor|major|минор|мажор)(?:е|а|у|ом)?\b"#
    // Part letters: Latin A–D in any case, Cyrillic А, Б, В, Г, С in capitals ("часть А").
    static let marker = #"(?:\b(первая|вторая|третья|четв[её]ртая)\s+часть\b|\b(first|second|third|fourth)\s+part\b|\b(?:part|section|часть|секция)\s+([A-D1-4]|(?-i:[АБВГС]))(?![\p{L}\d]))"#
    static let returns = #"(?:\b(?:возвращаемся|вернуться|вернёмся|возврат|снова|повтор(?:яем|ить)?)\s+(?:(?:в|к|на)\s+)?(первую|первой|вторую|второй|третью|третьей|четв[её]ртую|четв[её]ртой)\s+част[ьи]\b|\b(?:возвращаемся|вернуться|вернёмся|возврат|снова|повтор(?:яем|ить)?)\s+(?:(?:в|к|на)\s+)?част[ьиюе]\s+([A-D1-4]|(?-i:[АБВГС]))(?![\p{L}\d])|\b(?:return|back|repeat)\s+(?:to\s+)?(?:the\s+)?(?:(first|second|third|fourth)\s+part|part\s+([A-D1-4]))\b)"#
    static func matches(_ pattern: String, _ text: String) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    }
    static func value(_ match: NSTextCheckingResult, in text: NSString) -> String {
        for group in 1..<match.numberOfRanges where match.range(at: group).location != NSNotFound {
            return text.substring(with: match.range(at: group)).lowercased()
        }
        return ""
    }
    private static func index(_ word: String) -> Int? {
        [["первая","первую","первой","first","a","а","1"],["вторая","вторую","второй","second","b","б","в","2"],["третья","третью","третьей","third","c","с","3"]].firstIndex { $0.contains(word) }
    }

    public static func recognizes(_ text: String) -> Bool {
        guard text.count <= 2000 else { return false }
        if matches(marker, text).count >= 2 { return true }
        return namedHeadings(text).count >= 2
            && (!matches(barsPattern, text).isEmpty || bareProgression(in: text) != nil || !matches(#"\b(?:аккорд|chord)"#, text).isEmpty)
    }

    public func validate() throws {
        let roles = parts.map(\.role)
        switch arrangement {
        case .groove:
            guard (1...4).contains(parts.count), roles.allSatisfy({ $0 == .groove }),
                  parts.allSatisfy({ $0.chordSource == nil }), fadeBars == 0, !longDelay else { throw SongFormError.unsupported }
        case .chillhop:
            let validRoles: [[Role]] = [[.developingBeat,.arpeggio], [.fluteIntro,.developingBeat,.arpeggio],
                                        [.developingBeat,.arpeggio,.gong], [.fluteIntro,.developingBeat,.arpeggio,.gong]]
            guard validRoles.contains(roles), order == Array(parts.indices), fadeBars == 0 else { throw SongFormError.order }
        case .ambient:
            guard roles == [.ambientIntro,.bansuriSolo,.keysOutro], order == Array(parts.indices) else { throw SongFormError.order }
        }
        guard (1...8).contains(order.count), order.allSatisfy(parts.indices.contains) else { throw SongFormError.order }
        guard parts.allSatisfy({ (1...64).contains($0.bars) }), totalBars <= 64 else { throw SongFormError.length }
        for index in parts.indices {
            if let earlier = parts[index].chordSource {
                guard (0..<index).contains(earlier), parts[earlier].role.usesChords else { throw SongFormError.order }
            }
            _ = try resolvedChords(for: index)
        }
        if let end = parts.first(where: { $0.role == .keysOutro }) {
            guard (0...end.bars).contains(fadeBars) else { throw SongFormError.length }
        }
    }

    static func parse(_ text: String, base: TrackBrief) throws -> TrackBrief {
        // Wishes the offline arranger cannot play are listed in the form, never an error.
        var skipped: [String] = []
        let unsupported: [(String, String)] = [
            (#"\b(?:modulat(?:e|ion|ing|es)|модуляци[а-яё]*|модулиру[а-яё]*)\b"#, "Modulation"),
            (#"\b(?:accelerando|ritardando|ускорени[ея]|замедлени[ея])\b"#, "Tempo change"),
            (#"\b(?:dorian|phrygian|дорийск[а-яё]*|фригийск[а-яё]*)\b"#, "Church mode"),
        ]
        for (pattern, key) in unsupported where !matches(pattern, text).isEmpty { skipped.append(key) }
        let spelledKeys = matches(keyPattern, text)
        let source = text as NSString
        let declarations = try spelledKeys.map { key in
            let note = source.substring(with: key.range(at: 1)).lowercased()
            let aliases = ["до":"C","ре":"D","ми":"E","фа":"F","соль":"G","ля":"A","си":"B"]
            let root = try Chord.parse(aliases[note] ?? note).root
            let minor = ["minor","минор"].contains(source.substring(with: key.range(at: 2)).lowercased())
            return root + (minor ? 12 : 0)
        }
        if Set(declarations).count > 1 { skipped.append("Second key") }
        let headings = Self.headings(in: text)
        guard headings.count >= 2, let first = headings.first else { throw SongFormError.order }
        let global = source.substring(to: first.range.location)
        let lower = text.lowercased()
        let lettered = headings.allSatisfy { !$0.named }
        let letterHeadings = matches(marker, text).filter { heading in
            !matches(returns, text).contains { NSIntersectionRange($0.range, heading.range).length > 0 }
        }
        if lettered, ["эмбиент","эмбиэнт","ambient","медитаци","meditat"].contains(where: lower.contains) {
            var brief = try expressive(.ambient, text: text, base: base, global: global, headings: letterHeadings, references: matches(returns, text))
            if !skipped.isEmpty { brief.songForm?.skipped = skipped }
            return brief
        }
        if lettered, ["chillhop","chill-hop","chill hop","чиллхоп","чилл-хоп","чилл хоп"].contains(where: lower.contains) {
            var brief = try expressive(.chillhop, text: text, base: base, global: global, headings: letterHeadings, references: matches(returns, text))
            if !skipped.isEmpty { brief.songForm?.skipped = skipped }
            return brief
        }
        for (pattern, key) in instrumentWishes where !matches(pattern, text).isEmpty && !excludes(pattern, in: text) {
            skipped.append(key)
        }
        var baseline = base
        baseline.songForm = nil
        // Settings come from the text before the first part; bar counts and chord lists
        // there belong to the parts, not to a loop.
        let metadata = global.replacingOccurrences(of: barsPattern, with: "", options: [.regularExpression,.caseInsensitive])
        let label = matches(#"\b(?:chords?|progression|harmony|аккорд[а-я]*|гармони[а-яё]*)\b"#, metadata).first
        let settings = (metadata as NSString).substring(to: label?.range.location ?? (metadata as NSString).length)
        var brief: TrackBrief
        do { brief = try baseline.suggesting(settings) }
        catch TrackBriefError.invalidTempo { throw TrackBriefError.invalidTempo }
        catch { brief = baseline }
        if let key = spelledKeys.first {
            let note = source.substring(with: key.range(at: 1)).lowercased()
            let spelled = ["до":"C","ре":"D","ми":"E","фа":"F","соль":"G","ля":"A","си":"B"]
            brief.root = try Chord.parse(spelled[note] ?? note).root
            brief.minor = ["minor","минор"].contains(source.substring(with: key.range(at: 2)).lowercased())
        }
        let explicitTempo = !matches(#"(?:\d+\s*(?:bpm|бпм|ударов|уд/мин)|(?:темп|tempo|bpm|бпм)\s*[:=]?\s*\d+)"#, global).isEmpty
        if !explicitTempo && ["трениров","workout"].contains(where: global.lowercased().contains) { brief.tempo = 128 }
        var form = SongFormBrief(parts: [], order: [], offbeatHats: ["слабую долю","offbeat","off-beat"].contains(where: lower.contains), proposedTempo: !explicitTempo, proposedKey: spelledKeys.isEmpty)
        var seen: [String: Int] = [:]
        for (position, heading) in headings.enumerated() {
            if let index = seen[heading.key] { form.order.append(index); continue }
            guard !heading.isReturn else { throw SongFormError.order }
            guard form.parts.count < maximumParts else { throw SongFormError.order }
            let start = NSMaxRange(heading.range)
            let end = position + 1 < headings.count ? headings[position+1].range.location : source.length
            let body = source.substring(with: NSRange(location: start, length: max(0, end-start)))
            let chordText = try progression(in: body) ?? bareProgression(in: body)
            let chordCount = try chordText.map { try AssistantEngine.chordTokens($0).count } ?? 0
            let bars = try barCount(body, chords: chordCount)
            let relaxed = ["спокойн","передыш","тише","quieter","calmer","recovery","softer"].contains(where: body.lowercased().contains)
            seen[heading.key] = form.parts.count
            form.order.append(form.parts.count)
            form.parts.append(Part(bars: bars ?? 0, chordText: chordText ?? "", relaxed: relaxed,
                                   proposedBars: bars == nil, proposedChords: chordText == nil ? true : nil, name: heading.name))
        }
        // A part written without chords takes them from the nearest part that has some,
        // then from the text before the parts, then from the key — shown as a suggestion.
        let fallback = try progression(in: global) ?? bareProgression(in: global) ?? brief.suggestedChords
        for index in form.parts.indices where form.parts[index].chordText.isEmpty {
            let earlier = form.parts[..<index].last { !$0.chordText.isEmpty && $0.proposedChords != true }
            let later = form.parts[(index+1)...].first { !$0.chordText.isEmpty && $0.proposedChords != true }
            form.parts[index].chordText = (earlier ?? later)?.chordText ?? fallback
        }
        for index in form.parts.indices where form.parts[index].proposedBars {
            let count = (try? AssistantEngine.chordTokens(form.parts[index].chordText).count) ?? 4
            form.parts[index].bars = suggestedBars(chords: count)
        }
        form.skipped = skipped.isEmpty ? nil : skipped
        try form.validate()
        brief.songForm = form
        return brief
    }

}

extension SongFormBrief {
    static let countToken = #"([+-]?\d+(?:[.,]\d+)?|один|одна|два|две|три|четыре|восемь|шестнадцать|one|two|three|four|eight|sixteen)"#
    static let barsPattern = #"(?<![\p{L}\d.+-])"# + countToken + #"[\s-]*(?:bars?|measures?|такт[а-я]*)\b"#
    static let fadePattern = #"(?:fade(?:\s+out)?\s+(?:over\s+)?(?:the\s+)?(?:last\s+)?|(?:затуха[а-яё]*)\s+(?:за\s+)?(?:последни[ех]\s+)?|(?:за\s+)?последни[ех]\s+)"# + countToken + #"[\s-]*(?:bars?|такт[а-я]*)\b"#

    static func duration(_ match: NSTextCheckingResult, in text: String) throws -> Int {
        let token = value(match, in: text as NSString)
        let words = ["one":1,"один":1,"одна":1,"two":2,"два":2,"две":2,"three":3,"три":3,"four":4,"четыре":4,
                     "eight":8,"восемь":8,"sixteen":16,"шестнадцать":16]
        guard let bars = Int(token) ?? words[token], (1...64).contains(bars) else { throw SongFormError.length }
        return bars
    }

    static func barCount(_ text: String) throws -> Int? {
        let occurrences = matches(barsPattern, text)
        guard occurrences.count <= 1 else { throw SongFormError.length }
        return try occurrences.first.map { try duration($0, in: text) }
    }

    /// Consume the authored symbols as a list. In particular, reject an invalid
    /// entry instead of silently trimming a list to the last valid chord.
    static func progression(in text: String) throws -> String? {
        let labelPattern = #"\b(?:аккорды|аккорда|аккорд(?:ов|ами)|гармония|последовательность(?:\s+аккордов)?|chords?|progression|harmony)\b\s*(?:(?:песни|композиции|трека|части|по\s+повышающей|song|are|ascending)\s*)?[:=–—]?\s*"#
        guard let label = matches(labelPattern, text).first else { return nil }
        let tail = (text as NSString).substring(from: NSMaxRange(label.range))
        let boundary = #"[.;!?\n]|\s+(?:for|на|over|with|played|slightly|quieter|calmer|then|ending|end|для|и\s+опять|и\s+заверша|с\s+развит|затем|потом|далее|чуть|спокойн\w*|дальше|intro|in\s+the|по|each|per|каждый|тише|громче)\b|\s+"# + barsPattern
        let end = matches(boundary, tail).first?.range.location ?? (tail as NSString).length
        let written = (tail as NSString).substring(to: end)
        let list = normalizedChordList(written)
        guard !list.isEmpty else { return nil }
        let tokens = try AssistantEngine.chordTokens(list)
        guard tokens.count <= 64 else { throw SongFormError.chords }
        for token in tokens where (try? Chord.parse(token)) == nil { throw TrackBriefError.invalidChord(token) }
        return list
    }

    static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        let lowered = text.lowercased()
        return needles.contains(where: lowered.contains)
    }

    static func excludes(_ object: String, in text: String) -> Bool {
        let negative = #"\b(?:no|without|omit|skip|not|без|не(?:\s+(?:нуж[а-яё]*|надо|добавля[а-яё]*|использ[а-яё]*|игра[а-яё]*))?)\s+"#
        let modifiers = #"(?:(?:a|an|the|any|long|final|closing|slight(?:ly)?|intro|соло|удара?|длинн[а-яё]*|финальн[а-яё]*|плавн[а-яё]*|слегка)\s+){0,3}"#
        return !matches(negative + modifiers + "(?:" + object + ")", text).isEmpty
    }

    static func straightKeysRequested(in text: String) -> Bool {
        excludes(#"late\s+(?:piano|keys)|laid[ -]back|опаздыва[а-яё]*|запаздыва[а-яё]*"#, in: text) ||
        containsAny(text, ["piano on the grid","keys on the grid","пианино строго по сетке","клавиши строго по сетке"])
    }

    static func expressive(_ arrangement: Arrangement, text: String, base: TrackBrief, global: String,
                           headings: [NSTextCheckingResult], references: [NSTextCheckingResult]) throws -> TrackBrief {
        guard references.isEmpty, headings.count <= 3 else { throw SongFormError.order }
        let source = text as NSString
        let bodies = try headings.enumerated().map { position, heading -> String in
            guard index(value(heading, in: source)) == position else { throw SongFormError.order }
            let start = NSMaxRange(heading.range)
            let end = position + 1 < headings.count ? headings[position+1].range.location : source.length
            return source.substring(with: NSRange(location: start, length: end - start))
        }
        // Parse tempo and key independently of form. The ordinary loop builder
        // would otherwise interpret "one bar flute intro" as a one-bar song.
        var brief = TrackBrief()
        brief.seed = base.seed
        brief.bassVariation = base.bassVariation
        brief.drumVariation = base.drumVariation
        let metadata = global.replacingOccurrences(of: barsPattern, with: "", options: [.regularExpression,.caseInsensitive])
        let label = matches(#"\b(?:chords?|progression|аккорд[а-я]*)\b"#, metadata).first
        let settings = (metadata as NSString).substring(to: label?.range.location ?? (metadata as NSString).length)
        do { brief = try brief.suggesting(settings) }
        catch TrackBriefError.unknownIdea { /* No global key or tempo was supplied. */ }
        // A composer may put the key after a progression, or the tempo at the end.
        let keys = matches(keyPattern, text)
        if let key = keys.first {
            let note = source.substring(with: key.range(at: 1)).lowercased()
            let spelled = ["до":"C","ре":"D","ми":"E","фа":"F","соль":"G","ля":"A","си":"B"]
            brief.root = try Chord.parse(spelled[note] ?? note).root
            brief.minor = ["minor","минор"].contains(source.substring(with: key.range(at: 2)).lowercased())
        }
        let tempoDeclarations = matches(#"(?:(?<![\p{L}\d.+-])([+-]?\d+(?:[.,]\d+)?)\s*(?:bpm|бпм|ударов|уд/мин)\b|\b(?:темп|tempo|bpm|бпм)\s*[:=]?\s*([+-]?\d+(?:[.,]\d+)?))"#, text)
        let tempos = Set(tempoDeclarations.map { value($0, in: source) })
        guard tempos.count <= 1 else { throw TrackBriefError.invalidTempo }
        if let token = tempos.first {
            guard let tempo = Int(token), (40...240).contains(tempo) else { throw TrackBriefError.invalidTempo }
            brief.tempo = tempo
        } else {
            brief.tempo = arrangement == .ambient ? 64 : 90
        }
        if arrangement == .chillhop { brief.style = .hipHop; brief.hipHopFeel = .boomBap }
        var form = SongFormBrief(parts: [], order: [], offbeatHats: false, proposedTempo: tempos.isEmpty, proposedKey: keys.isEmpty, arrangement: arrangement)
        switch arrangement {
        case .ambient:
            try form.readAmbient(global: global, bodies: bodies, text: text)
        case .chillhop:
            try form.readChillhop(global: global, bodies: bodies, text: text)
            if straightKeysRequested(in: text) { brief.laidBackKeys = false }
            else if containsAny(text, ["опаздывающ","запаздывающ","behind the beat","laid-back piano","laid back piano","late piano","behind-the-beat"]) {
                brief.laidBackKeys = true
            }
        case .groove:
            throw SongFormError.unsupported
        }
        try form.validate()
        brief.songForm = form
        return brief
    }

    mutating func add(_ role: Role, bars: Int?, suggested: Int, chords: String = "", source: Int? = nil) {
        order.append(parts.count)
        parts.append(Part(bars: bars ?? suggested, chordText: chords, relaxed: false,
                          role: role, chordSource: source, proposedBars: bars == nil))
    }

    mutating func readChillhop(global: String, bodies: [String], text: String) throws {
        var mainIndex = 0
        let flute = ["флейт","flute"]
        let useFlute = !Self.excludes("flute|флейт", in: text)
        if useFlute, bodies.count == 3, Self.containsAny(bodies[0], flute) {
            add(.fluteIntro, bars: try Self.barCount(bodies[0]), suggested: 1)
            mainIndex = 1
        } else if useFlute, Self.containsAny(global, flute) {
            add(.fluteIntro, bars: try Self.barCount(global), suggested: 1)
        }
        guard bodies.count == mainIndex+2 else { throw SongFormError.order }
        let main = bodies[mainIndex], arp = bodies[mainIndex+1]
        guard Self.containsAny(arp, ["арпеджи","арпеджо","arpegg"]) else { throw SongFormError.unsupported }
        guard let chords = try Self.progression(in: main) ?? Self.progression(in: global) else { throw SongFormError.chords }
        let chordSource = parts.count
        add(.developingBeat, bars: try Self.barCount(main), suggested: 16, chords: chords)
        let gongMarker = Self.matches(#"(?:и\s+)?(?:заверша\w*|заканчива\w*|finish(?:es)?|end(?:ing|s)?)\s+(?:with\s+)?(?:a\s+)?(?:ударом\s+)?(?:the\s+)?(?:гонг\w*|gong)\b"#, arp).first
        let arpInstruction = (arp as NSString).substring(to: gongMarker?.range.location ?? (arp as NSString).length)
        let reuse = Self.containsAny(arpInstruction, ["этих аккорд","тех же аккорд","прежн","those chords","these chords","same chords","their notes"])
        let alternate = reuse ? nil : try Self.progression(in: arpInstruction)
        add(.arpeggio, bars: try Self.barCount(arpInstruction), suggested: 8, chords: alternate ?? "", source: alternate == nil ? chordSource : nil)
        if Self.containsAny(arp, ["гонг","gong"]), !Self.excludes("gong|гонг", in: text) {
            let tail = gongMarker.map { (arp as NSString).substring(from: NSMaxRange($0.range)) } ?? ""
            add(.gong, bars: try Self.barCount(tail), suggested: 1)
        }
    }

    mutating func readAmbient(global: String, bodies: [String], text: String) throws {
        guard bodies.count == 3, Self.containsAny(bodies[1], ["бансури","bansuri","флейт","flute"]),
              Self.containsAny(bodies[2], ["клавиш","пианино","рояль","фортепиано","keys","piano","keyboard"])
        else { throw SongFormError.unsupported }
        guard let cycle = try Self.progression(in: bodies[0]) ?? Self.progression(in: global) else { throw SongFormError.chords }
        add(.ambientIntro, bars: try Self.barCount(bodies[0]), suggested: 8, chords: cycle)
        let soloChords = try Self.progression(in: bodies[1])
        add(.bansuriSolo, bars: try Self.barCount(bodies[1]), suggested: 8, chords: soloChords ?? "", source: soloChords == nil ? 0 : nil)
        let ending = bodies[2]
        let fade = Self.matches(Self.fadePattern, ending).first
        let sectionText = ending.replacingOccurrences(of: Self.fadePattern, with: "", options: [.regularExpression,.caseInsensitive])
        let outroChords = try Self.progression(in: sectionText)
        add(.keysOutro, bars: try Self.barCount(sectionText), suggested: 8, chords: outroChords ?? "", source: outroChords == nil ? 0 : nil)
        let wantsDrySound = Self.excludes("delay|echo|диле|дилэ|дэлей|задерж|эх[ао]", in: text)
        longDelay = !wantsDrySound && Self.containsAny(text, ["диле","дилэ","дэлей","задержк","эхо","delay","echo"])
        if Self.containsAny(ending, ["рассеива","раствор","затуха","затих","fade","dissolve"]), !Self.excludes("fade|fading|затух|затих|рассеива", in: text) {
            proposedFadeBars = fade == nil
            fadeBars = try fade.map { try Self.duration($0, in: ending) } ?? min(4, parts[2].bars)
        }
    }
}

// MARK: - Musician feedback (build 51): any reasonable wording, and a table

extension SongFormBrief {
    /// Groove songs can have up to four parts (intro, verse, chorus, bridge).
    public static let maximumParts = 4

    struct Heading {
        let range: NSRange
        let key: String
        let name: String?
        let isReturn: Bool
        var named: Bool { name != nil }
    }

    /// Section names a musician uses as headings: "Куплет: …", "Chorus — …".
    static let namedPattern = #"(?:^|(?<=[.;!?]))[ \t]*(интро|вступление|куплет|предприпев|припев|бридж|переход|проигрыш|кода|аутро|концовка|intro|verse|pre-chorus|chorus|hook|bridge|breakdown|outro)(?:[ \t]+\d+)?[ \t]*(?:[:—–(-]|(?=[ \t]+\d+[ \t-]*(?:такт|bar))|(?=[ \t]*(?:[.;!?\n]|$)))"#

    static func namedHeadings(_ text: String) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: namedPattern, options: [.caseInsensitive, .anchorsMatchLines]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    private static func canonicalName(_ word: String) -> String {
        let lower = word.lowercased()
        let groups: [[String]] = [["интро","вступление","intro"], ["куплет","verse"], ["предприпев","pre-chorus"], ["припев","chorus","hook"],
                                  ["бридж","переход","bridge"], ["проигрыш","breakdown"], ["кода","аутро","концовка","outro"]]
        return groups.first { $0.contains(lower) }?.first ?? lower
    }

    /// A part's identity from its heading word: ordinals, digits and letters agree
    /// ("first part" = "part A" = "часть А"). Cyrillic В is the third letter when the text
    /// also uses Б, otherwise it is the look-alike of B.
    private static func key(_ word: String, cyrillicAlphabet: Bool) -> String {
        let table: [String: String] = ["первая":"1","первую":"1","первой":"1","first":"1","a":"1","а":"1","1":"1",
                                       "вторая":"2","вторую":"2","второй":"2","second":"2","b":"2","б":"2","2":"2",
                                       "третья":"3","третью":"3","третьей":"3","third":"3","c":"3","с":"3","3":"3",
                                       "четвертая":"4","четвёртая":"4","четвертую":"4","четвёртую":"4","четвертой":"4","четвёртой":"4",
                                       "fourth":"4","d":"4","г":"4","4":"4"]
        if word == "в" { return cyrillicAlphabet ? "3" : "2" }
        return table[word] ?? word
    }

    /// Part headings and returns in reading order. Lettered headings win; section names
    /// are used when the text has fewer than two lettered parts.
    static func headings(in text: String) -> [Heading] {
        let source = text as NSString
        let references = matches(returns, text)
        let cyrillic = !matches(#"\b(?:часть|секция|части)\s+(?-i:Б)(?![\p{L}\d])"#, text).isEmpty
        var result = references.map { Heading(range: $0.range, key: key(value($0, in: source), cyrillicAlphabet: cyrillic), name: nil, isReturn: true) }
        for heading in matches(marker, text) where !references.contains(where: { NSIntersectionRange($0.range, heading.range).length > 0 }) {
            result.append(Heading(range: heading.range, key: key(value(heading, in: source), cyrillicAlphabet: cyrillic), name: nil, isReturn: false))
        }
        if result.filter({ !$0.isReturn }).count < 2 {
            let named = namedHeadings(text)
            if named.count >= 2 {
                result = named.map { match in
                    let word = source.substring(with: match.range(at: 1))
                    return Heading(range: match.range, key: "name:" + canonicalName(word), name: word.prefix(1).uppercased() + word.dropFirst().lowercased(), isReturn: false)
                }
            }
        }
        return result.sorted { $0.range.location < $1.range.location }
    }

    /// Instruments and effects people ask for that the groove arranger does not play.
    static let instrumentWishes: [(String, String)] = [
        (#"\b(?:флейт[а-яё]*|flutes?)"#, "Flute"), (#"\b(?:бансури|bansuri)"#, "Bansuri"),
        (#"\b(?:арпеджи[а-яё]*|арпеджо|arpeggi[a-z]*)"#, "Arpeggio"), (#"\b(?:гонг[а-яё]*|gongs?)\b"#, "Gong"),
        (#"\b(?:диле[йя][а-яё]*|дилэ[а-яё]*|дэлей[а-яё]*|delay|эхо|echo)\b"#, "Long delay"), (#"\b(?:эмбиент[а-яё]*|ambient)\b"#, "Ambient pad"),
        (#"\b(?:скрипк[а-яё]*|струнн[а-яё]*|violins?|strings)\b"#, "Strings"), (#"\b(?:саксофон[а-яё]*|sax(?:ophone)?)\b"#, "Saxophone"),
        (#"\b(?:труб[аеуы]|духов[а-яё]*|trumpets?|brass)\b"#, "Brass"), (#"\b(?:гитар[а-яё]*|guitars?)\b"#, "Guitar"),
        (#"\b(?:хор|хора|хором|choir|вокал[а-яё]*|vocals?)\b"#, "Vocals"), (#"\b(?:орган|органа|organ)\b"#, "Organ"),
    ]

    /// Chord symbols written without a label: the longest run of two or more symbols
    /// that start with a capital letter A–G ("8 тактов: Db Eb Cm Fm").
    static func bareProgression(in text: String) -> String? {
        let spaced = text.replacingOccurrences(of: #"\s*(?:[–—→|]|\s-\s)\s*"#, with: " ", options: .regularExpression)
        var best: [String] = [], run: [String] = []
        let trim = CharacterSet(charactersIn: ".:!?()«»\"'")
        for raw in spaced.components(separatedBy: CharacterSet(charactersIn: " ,;\n\t")) where !raw.isEmpty {
            let token = raw.trimmingCharacters(in: trim)
            let pieces = token.contains("-") && !isChordSymbol(token) ? token.split(separator: "-").map(String.init) : [token]
            for piece in pieces where !piece.isEmpty {
                if isChordSymbol(piece) { run.append(piece) }
                else { if run.count > best.count { best = run }; run = [] }
            }
        }
        if run.count > best.count { best = run }
        return best.count >= 2 && best.count <= 64 ? best.joined(separator: ", ") : nil
    }

    static func isChordSymbol(_ token: String) -> Bool {
        guard let first = token.first, "ABCDEFG".contains(first), token.count <= 12 else { return false }
        return (try? Chord.parse(token)) != nil
    }

    /// A labelled list with any common separator, as a comma list the arranger reads.
    static func normalizedChordList(_ written: String) -> String {
        var list = written.replacingOccurrences(of: #"\s*(?:[–—→|]|\s-\s)\s*"#, with: ", ", options: .regularExpression)
        list = list.replacingOccurrences(of: #"(?<=[A-Za-z0-9#♯♭)])-(?=[A-G])"#, with: ", ", options: .regularExpression)
        return list.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",.")))
    }

    /// "по 2 такта", "по такту", "2 bars each", "each chord 2 bars", "2 такта на аккорд".
    static let perChordPattern = "(?:" + #"\bпо\s+"# + countToken + #"[\s-]*такт[а-я]*|\bпо\s+такту\b|"# + countToken
        + #"[\s-]*(?:bars?|measures?)\s+(?:each|per\s+chord|a\s+chord|for\s+each(?:\s+chord)?)|\b(?:each|every)\s+chord\s+(?:for\s+|gets\s+)?"#
        + countToken + #"[\s-]*(?:bars?|measures?)|"# + countToken + #"[\s-]*такт[а-я]*\s+на\s+(?:каждый\s+)?аккорд"# + ")"

    /// The part's length: a total if one is written, otherwise bars per chord × chords.
    static func barCount(_ text: String, chords: Int) throws -> Int? {
        let source = text as NSString
        let each = matches(perChordPattern, text)
        let totals = matches(barsPattern, text).filter { total in !each.contains { NSIntersectionRange($0.range, total.range).length > 0 } }
        if let total = totals.first { return try duration(total, in: text) }
        guard let first = each.first, chords > 0 else { return nil }
        let unit = value(first, in: source).isEmpty ? 1 : try duration(first, in: text)
        guard (1...64).contains(unit * chords) else { throw SongFormError.length }
        return unit * chords
    }

    /// A length to start from when a part has none: two bars per chord for short
    /// progressions, one bar per chord for longer ones.
    static func suggestedBars(chords: Int) -> Int {
        chords <= 0 ? 8 : chords <= 4 ? max(4, chords * 2) : min(64, chords)
    }

    // MARK: Table editing

    /// A two-part song to fill in as a table: verse and chorus in the key, played A B A.
    public static func starter(keyRoot: Int, minor: Bool) -> SongFormBrief {
        SongFormBrief(parts: [Part(bars: 8, chordText: progression(minor ? [0, 8, 3, 10] : [0, 7, 9, 5], keyRoot: keyRoot, minor: minor)),
                              Part(bars: 8, chordText: progression(minor ? [8, 10, 0, 0] : [5, 0, 7, 9], keyRoot: keyRoot, minor: minor))],
                      order: [0, 1, 0])
    }

    /// Chord symbols for scale steps (semitones from the key's root) with the key's own qualities.
    static func progression(_ offsets: [Int], keyRoot: Int, minor: Bool) -> String {
        offsets.compactMap { offset in diatonic(keyRoot: keyRoot, minor: minor).first { ($0.root - keyRoot + 12) % 12 == offset } }
            .map { MusicalNotation.chordSymbol($0, keyRoot: keyRoot, minor: minor) }
            .joined(separator: ", ")
    }

    /// The seven chords of the key, in scale order (natural minor in minor keys).
    public static func diatonic(keyRoot: Int, minor: Bool) -> [Chord] {
        let steps: [(Int, Quality)] = minor
            ? [(0, .minor), (2, .dim), (3, .major), (5, .minor), (7, .minor), (8, .major), (10, .major)]
            : [(0, .major), (2, .minor), (4, .minor), (5, .major), (7, .major), (9, .minor), (11, .dim)]
        return steps.map { Chord(root: (keyRoot + $0.0) % 12, quality: $0.1) }
    }

    /// Ready orders for the number of parts; every part plays at least once.
    public static func orderChoices(parts: Int) -> [[Int]] {
        switch parts {
        case 1: [[0], [0, 0]]
        case 2: [[0, 1], [0, 1, 0], [0, 1, 0, 1], [0, 0, 1, 0], [0, 1, 1, 0]]
        case 3: [[0, 1, 2], [0, 1, 0, 2], [0, 1, 0, 2, 1], [0, 1, 2, 1], [2, 0, 1, 0, 1]]
        default: [[0, 1, 2, 3], [0, 1, 2, 1, 3, 2], [3, 0, 1, 0, 1, 2, 1], [0, 1, 0, 1, 2, 1, 3]]
        }
    }

    public mutating func setOrder(_ next: [Int]) {
        guard (1...8).contains(next.count), next.allSatisfy(parts.indices.contains), Set(next) == Set(parts.indices) else { return }
        order = next
    }

    /// Adds a part after the others with the last part's chords; it plays once at the end.
    public mutating func addPart() {
        guard arrangement == .groove, parts.count < Self.maximumParts, order.count < 8 else { return }
        let chords = parts.isEmpty ? "" : resolvedChordText(for: parts.count - 1)
        parts.append(Part(bars: 8, chordText: chords))
        order.append(parts.count - 1)
    }

    /// Removes a part and every place it plays; at least one part stays.
    public mutating func removePart(_ index: Int) {
        guard arrangement == .groove, parts.count > 1, parts.indices.contains(index) else { return }
        parts.remove(at: index)
        order = order.compactMap { $0 == index ? nil : ($0 > index ? $0 - 1 : $0) }
        if order.isEmpty { order = [0] }
        for part in parts.indices {
            if let source = parts[part].chordSource { parts[part].chordSource = source == index ? nil : (source > index ? source - 1 : source) }
        }
    }

    /// The part's heading: its own name, or A, B, C, D.
    public func title(_ index: Int) -> String {
        guard parts.indices.contains(index) else { return "" }
        return parts[index].name ?? String(UnicodeScalar(UInt8(65 + min(index, 25))))
    }
}
