import Foundation

public enum SongFormError: LocalizedError {
    case unsupported, length, chords, order
    public var errorDescription: String? {
        switch self {
        case .unsupported: NSLocalizedString("This section request includes instructions the offline arranger cannot play yet.", comment: "Song form")
        case .length: NSLocalizedString("Give each part a bar count. The song can contain up to 64 bars in total.", comment: "Song form")
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
        public init(bars: Int, chordText: String, relaxed: Bool = false, role: Role = .groove,
                    chordSource: Int? = nil, proposedBars: Bool = false) {
            self.bars = bars
            self.chordText = chordText
            self.relaxed = relaxed
            self.role = role
            self.chordSource = chordSource
            self.proposedBars = proposedBars
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

    private static let keyPattern = #"(?<![\p{L}\d])([a-g](?:[#♯b♭])?|до|ре|ми|фа|соль|ля|си)[\s-]+(?:(?:natural|натуральный)\s+)?(minor|major|минор|мажор)\b"#
    private static let marker = #"(?:\b(первая|вторая|третья)\s+часть\b|\b(first|second|third)\s+part\b|\b(?:part|section|часть)\s+([ABC123])\b)"#
    private static let returns = #"(?:\b(?:возвращаемся|вернуться|возврат)\s+(?:в|к)\s+(первую|первой|вторую|второй|третью|третьей)\s+част[ьи]\b|\b(?:return|back)\s+to\s+(?:the\s+)?(?:(first|second|third)\s+part|part\s+([ABC]))\b)"#
    private static func matches(_ pattern: String, _ text: String) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    }
    private static func value(_ match: NSTextCheckingResult, in text: NSString) -> String {
        for group in 1..<match.numberOfRanges where match.range(at: group).location != NSNotFound {
            return text.substring(with: match.range(at: group)).lowercased()
        }
        return ""
    }
    private static func index(_ word: String) -> Int? {
        [["первая","первую","первой","first","a","1"],["вторая","вторую","второй","second","b","2"],["третья","третью","третьей","third","c","3"]].firstIndex { $0.contains(word) }
    }

    public static func recognizes(_ text: String) -> Bool {
        text.count <= 2000 && matches(marker, text).count >= 2
    }

    public func validate() throws {
        let roles = parts.map(\.role)
        switch arrangement {
        case .groove:
            guard (1...3).contains(parts.count), roles.allSatisfy({ $0 == .groove }),
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
        let unsupported = #"\b(?:modulat(?:e|ion|ing|es)|модуляци[а-яё]*|модулиру[а-яё]*|accelerando|ritardando|ускорени[ея]|замедлени[ея]|dorian|phrygian|дорийск[а-яё]*|фригийск[а-яё]*)\b"#
        guard matches(unsupported, text).isEmpty else { throw SongFormError.unsupported }
        let spelledKeys = matches(keyPattern, text)
        let source = text as NSString
        let declarations = try spelledKeys.map { key in
            let note = source.substring(with: key.range(at: 1)).lowercased()
            let aliases = ["до":"C","ре":"D","ми":"E","фа":"F","соль":"G","ля":"A","си":"B"]
            let root = try Chord.parse(aliases[note] ?? note).root
            let minor = ["minor","минор"].contains(source.substring(with: key.range(at: 2)).lowercased())
            return root + (minor ? 12 : 0)
        }
        guard Set(declarations).count <= 1 else { throw SongFormError.unsupported }
        let references = matches(returns, text)
        let headings = matches(marker, text).filter { heading in
            !references.contains { NSIntersectionRange($0.range, heading.range).length > 0 }
        }
        guard headings.count >= 2, let first = headings.first else { throw SongFormError.order }
        let global = source.substring(to: first.range.location)
        let lower = text.lowercased()
        if ["эмбиент","эмбиэнт","ambient","медитаци","meditat"].contains(where: lower.contains) {
            return try expressive(.ambient, text: text, base: base, global: global, headings: headings, references: references)
        }
        if ["chillhop","chill-hop","chill hop","чиллхоп","чилл-хоп","чилл хоп"].contains(where: lower.contains) {
            return try expressive(.chillhop, text: text, base: base, global: global, headings: headings, references: references)
        }
        if ["флейт","бансури","арпеджи","гонг","диле","эмбиент","flute","arpeggio","gong","delay","ambient"].contains(where: lower.contains) {
            throw SongFormError.unsupported
        }
        var baseline = base
        baseline.songForm = nil
        var brief: TrackBrief
        do { brief = try baseline.suggesting(global) }
        catch TrackBriefError.unknownIdea { brief = baseline }
        let explicitTempo = !matches(#"(?:\d+\s*(?:bpm|бпм|ударов|уд/мин)|(?:темп|tempo|bpm|бпм)\s*[:=]?\s*\d+)"#, global).isEmpty
        if !explicitTempo && ["трениров","workout"].contains(where: global.lowercased().contains) { brief.tempo = 128 }
        let events = (headings.map { ($0, false) } + references.map { ($0, true) }).sorted { $0.0.range.location < $1.0.range.location }
        var form = SongFormBrief(parts: [], order: [], offbeatHats: ["слабую долю","offbeat","off-beat"].contains(where: lower.contains), proposedTempo: !explicitTempo, proposedKey: matches(keyPattern, global).isEmpty)
        for (position, event) in events.enumerated() {
            guard let index = index(value(event.0, in: source)) else { throw SongFormError.order }
            if event.1 {
                guard form.parts.indices.contains(index) else { throw SongFormError.order }
            } else {
                guard index == form.parts.count else { throw SongFormError.order }
                let start = NSMaxRange(event.0.range)
                let end = position + 1 < events.count ? events[position+1].0.range.location : source.length
                let body = source.substring(with: NSRange(location: start, length: end-start))
                guard let count = try barCount(body) else { throw SongFormError.length }
                guard let chordText = try progression(in: body) else { throw SongFormError.chords }
                let relaxed = ["спокойн","передыш","quieter","calmer","recovery"].contains(where: body.lowercased().contains)
                form.parts.append(Part(bars: count, chordText: chordText, relaxed: relaxed))
            }
            form.order.append(index)
        }
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
        let labelPattern = #"\b(?:аккорды|аккорда|аккорд(?:ов|ами)|chords?|progression)\b\s*(?:(?:песни|композиции|трека|по\s+повышающей|song|are|ascending)\s*)?[:=–—]?\s*"#
        guard let label = matches(labelPattern, text).first else { return nil }
        let tail = (text as NSString).substring(from: NSMaxRange(label.range))
        let boundary = #"[.;!?\n]|\s+(?:for|на|over|with|played|slightly|quieter|calmer|then|ending|end|для|и\s+опять|и\s+заверша|с\s+развит|затем|потом|далее|чуть|спокойн\w*|дальше|intro|in\s+the)\b|\s+"# + barsPattern
        let end = matches(boundary, tail).first?.range.location ?? (tail as NSString).length
        let list = (tail as NSString).substring(to: end).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",")))
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
