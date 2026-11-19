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

public struct SongFormBrief: Equatable, Sendable {
    public struct Part: Equatable, Sendable {
        public var bars: Int
        public var chordText: String
        public var relaxed: Bool
        func chords() throws -> [Chord] {
            let tokens = try AssistantEngine.chordTokens(chordText)
            guard !tokens.isEmpty else { throw SongFormError.chords }
            guard tokens.count <= bars else { throw TrackBriefError.tooManyChords }
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
    public var totalBars: Int { order.reduce(0) { $0 + parts[$1].bars } }

    private static let marker = #"(?:\b(первая|вторая|третья)\s+часть\b|\b(first|second|third)\s+part\b|\bpart\s+([ABC])\b)"#
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
        [["первая","первую","первой","first","a"],["вторая","вторую","второй","second","b"],["третья","третью","третьей","third","c"]].firstIndex { $0.contains(word) }
    }

    public static func recognizes(_ text: String) -> Bool {
        text.count <= 2000 && matches(marker, text).count >= 2
    }

    func validate() throws {
        guard (1...8).contains(order.count), order.allSatisfy(parts.indices.contains) else { throw SongFormError.order }
        guard parts.allSatisfy({ (1...64).contains($0.bars) }), totalBars <= 64 else { throw SongFormError.length }
        for part in parts { _ = try part.chords() }
    }

    static func parse(_ text: String, base: TrackBrief) throws -> TrackBrief {
        let source = text as NSString
        let references = matches(returns, text)
        let headings = matches(marker, text).filter { heading in
            !references.contains { NSIntersectionRange($0.range, heading.range).length > 0 }
        }
        guard headings.count >= 2, let first = headings.first else { throw SongFormError.order }
        let global = source.substring(to: first.range.location)
        let lower = text.lowercased()
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
        var form = SongFormBrief(parts: [], order: [], offbeatHats: ["слабую долю","offbeat","off-beat"].contains(where: lower.contains), proposedTempo: !explicitTempo)
        for (position, event) in events.enumerated() {
            guard let index = index(value(event.0, in: source)) else { throw SongFormError.order }
            if event.1 {
                guard form.parts.indices.contains(index) else { throw SongFormError.order }
            } else {
                guard index == form.parts.count else { throw SongFormError.order }
                let start = NSMaxRange(event.0.range)
                let end = position + 1 < events.count ? events[position+1].0.range.location : source.length
                let body = source.substring(with: NSRange(location: start, length: end-start))
                let lengths = matches(#"\b(\d+)\s*(?:такт[а-я]*|bars?)\b"#, body)
                guard lengths.count == 1, let count = Int(value(lengths[0], in: body as NSString)), (1...64).contains(count) else { throw SongFormError.length }
                guard let label = matches(#"\b(?:аккорды|chords)\b\s*(?:по\s+повышающей\s*|ascending\s*)?[:=]?\s*"#, body).first else { throw SongFormError.chords }
                let tail = (body as NSString).substring(from: NSMaxRange(label.range))
                let separator = matches(#"[.;!\n]|\s+(?:чуть|спокойн\w*|для|и\s+опять|quieter|calmer|slightly|then|\d+\s*(?:bars?|такт\w*))\b"#, tail).first
                let chordText = (tail as NSString).substring(to: separator?.range.location ?? (tail as NSString).length).trimmingCharacters(in: .whitespacesAndNewlines)
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
