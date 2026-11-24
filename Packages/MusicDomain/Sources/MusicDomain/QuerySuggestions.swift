import Foundation

/// U69 · Hints under text fields: what you typed before comes first, then examples the app
/// understands, matched by the start of the text or of any word in it.
public enum QuerySuggestions {
    public static let limit = 5

    /// Phrases the assistant and the phrase editor understand.
    public static func assistantExamples(russian: Bool) -> [String] {
        russian
            ? ["темп 92", "в ля минор", "добавь припев", "сделай джазово", "убери бочку в тактах 1–2", "громче",
               "песня: куплет 8, припев 8", "хаус-эскиз 124 BPM", "транспонируй на +2", "бридж на 4 такта"]
            : ["tempo 92", "in A minor", "add a chorus", "make it jazzier", "remove the kick in bars 1–2", "louder",
               "song: verse 8, chorus 8", "house sketch at 124 BPM", "transpose up 2", "bridge of 4 bars"]
    }

    /// The best `limit` hints for `text`: history (newest first) before examples, no repeats, and
    /// never the text itself. An empty text gives the newest history, then the first examples.
    public static func top(_ text: String, history: [String], examples: [String], limit: Int = limit) -> [String] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var seen = Set<String>(), result: [String] = []
        func consider(_ candidate: String) {
            let key = candidate.lowercased()
            guard result.count < limit, !candidate.isEmpty, key != query, seen.insert(key).inserted else { return }
            if query.isEmpty || matches(key, query) { result.append(candidate) }
        }
        for item in history.reversed() { consider(item) }
        for item in examples { consider(item) }
        return result
    }

    /// True when `candidate` starts with `query` or one of its words does.
    static func matches(_ candidate: String, _ query: String) -> Bool {
        if candidate.hasPrefix(query) { return true }
        return candidate.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == ":" }).contains { $0.hasPrefix(query) }
    }

    /// Names for a new song from its key and tempo, without the names already used.
    public static func projectNames(existing: [String], keyRoot: Int, minor: Bool, bpm: Double, seed: UInt64, russian: Bool, limit: Int = 4) -> [String] {
        let used = Set(existing.map { $0.lowercased() })
        return Array(SongNames.suggestions(keyRoot: keyRoot, minor: minor, bpm: bpm, seed: seed, russian: russian).filter { !used.contains($0.lowercased()) }.prefix(limit))
    }
}
