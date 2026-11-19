import Foundation

/// Local RU/EN parser for edits of the open project. It works without network
/// or a system model. Scope (section occurrence, bars) and protected parts are
/// established first; events are computed only by SongEditor afterwards.
/// The parser recognises words and their forms, not whole stored examples:
/// it handles numerals, "first two", "last", "before the second chorus",
/// "every other bar", exceptions ("everything except the bass"), negation
/// ("don't remove the hats") and single-letter typos in longer words.
public enum SongEditParser {

    // MARK: Public API

    public static func intent(_ text: String, project: Project?) -> SongEditIntent {
        if SongFormBrief.recognizes(text) { return .create }
        let clauses = Self.clauses(Self.tokens(text))
        let edits = clauses.map { analyse($0, project: project) }
        let hasAction = edits.contains { ($0.action != nil && $0.action != .make) || $0.kind != nil }
        let hasScope = edits.contains { $0.hasScope }
        let hasPart = edits.contains { !$0.targets.isEmpty || $0.fillNoun }
        // "Make a chillhop beat at 88 bpm, 8 bars, laid back keys" describes a new
        // song: it starts with a creation verb, the offline arranger understands
        // it, and it names no place in the open song (section, first/last bars).
        let names = edits.contains { $0.sectionKind != nil || $0.sectionName != nil || $0.firstBars != nil || $0.lastBars != nil || $0.everyOther }
        let normalized = normalize(text).trimmingCharacters(in: .whitespacesAndNewlines)
        let creationVerb = ["create ", "make ", "generate ", "compose ", "создай ", "сделай ", "сгенерируй ", "сочини ", "напиши "].contains { normalized.hasPrefix($0) }
        if creationVerb, !names, (try? TrackBrief.offlineCreationRequest(text)) != nil { return .create }
        if project != nil, hasAction, hasPart || hasScope { return .edit }
        if (try? TrackBrief.offlineCreationRequest(text)) != nil { return .create }
        if project != nil, (hasAction && hasPart) || (edits.contains { $0.action == .make } && hasScope) { return .edit }
        return .unknown
    }

    public static func plan(_ text: String, project: Project) -> SongEditPlan {
        var plan = SongEditPlan(projectID: project.id, baseRevision: project.revision, text: text,
                                protectedTracks: [], protectedPads: [], operations: [], problems: [], choices: [])
        let original = Array(text)
        let tokens = Self.tokens(text)
        let clauseList = Self.clauses(tokens)
        let analysed = clauseList.map { analyse($0, project: project) }
        func fragment(_ clause: [Token]) -> String {
            guard let first = clause.first, let last = clause.last else { return "" }
            let lower = first.offset, upper = last.offset + last.length
            if upper <= original.count { return String(original[lower..<upper]) }
            return clause.map(\.text).joined(separator: " ")
        }
        // 1. Protected parts.
        for (clause, edit) in zip(clauseList, analysed) where edit.action == .keep && edit.kind == nil {
            let ids = resolve(edit.targets, except: edit.exceptions, project: project, forEdit: false)
            if ids.isEmpty { plan.problems.append(.init(fragment: fragment(clause), reason: .missing)); continue }
            for id in ids {
                if id.pads == nil { if !plan.protectedTracks.contains(id.trackID) { plan.protectedTracks.append(id.trackID) } }
                else if !plan.protectedPads.contains(id) { plan.protectedPads.append(id) }
            }
        }
        // 2. Operations in the established scope.
        for (clause, edit) in zip(clauseList, analysed) {
            guard edit.action != .keep || edit.kind != nil else { continue }
            guard let kind = edit.kind else {
                if edit.meaningful { plan.problems.append(.init(fragment: fragment(clause), reason: .unsupported)) }
                continue
            }
            switch resolveOperations(kind: kind, edit: edit, project: project, protected: plan.protectedTracks, protectedPads: plan.protectedPads) {
            case .operations(let ops):
                let audible = ops.filter { sounds($0, in: project) }
                if audible.isEmpty { plan.problems.append(.init(fragment: fragment(clause), reason: .silent)) }
                plan.operations.append(contentsOf: audible)
            case .choices(let choices): plan.choices.append(contentsOf: choices)
            case .problem(let reason): plan.problems.append(.init(fragment: fragment(clause), reason: reason))
            }
        }
        // 3. Contradictions with protection or between operations.
        for (index, op) in plan.operations.enumerated() {
            let padConflict = plan.protectedPads.contains { kept in
                kept.trackID == op.target.trackID && (op.target.pads.map { !Set($0).isDisjoint(with: kept.pads ?? []) } ?? true)
            }
            if plan.protectedTracks.contains(op.target.trackID) || (padConflict && op.kind != .fill) {
                plan.problems.append(.init(fragment: describe(op, project: project), reason: .contradiction))
            }
            if changesDerivedBass(op, project: project) {
                if let bass = project.tracks.first(where: { $0.role == .bass }), plan.protectedTracks.contains(bass.id) {
                    plan.problems.append(.init(fragment: describe(op, project: project), reason: .derivedBass))
                }
            }
            for other in plan.operations[(index + 1)...] where other.target.trackID == op.target.trackID && other.bars.overlaps(op.bars) {
                let pair = Set([op.kind, other.kind])
                if pair == [.denser, .sparser] || pair == [.fadeIn, .fadeOut] || (pair.contains(.remove) && pair.count == 2 && !pair.contains(.fill) && padsOverlap(op, other)) {
                    plan.problems.append(.init(fragment: describe(op, project: project) + " / " + describe(other, project: project), reason: .contradiction))
                }
            }
        }
        if plan.operations.isEmpty, plan.choices.isEmpty, plan.problems.isEmpty, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            plan.problems.append(.init(fragment: text, reason: .unsupported))
        }
        return plan
    }

    /// Whether the operation's part plays in its bars (fill and arpeggio create new material).
    static func sounds(_ op: SongEditOperation, in project: Project) -> Bool {
        if op.kind == .fill || op.kind == .arpeggiate { return true }
        guard let index = project.tracks.firstIndex(where: { $0.id == op.target.trackID }) else { return false }
        let range = op.bars.lowerBound * barTicks..<op.bars.upperBound * barTicks
        let pads = op.target.pads.map(Set.init)
        return Compiler.notes(project, range: range).contains { $0.track == index && (pads?.contains($0.pad) ?? true) }
    }

    static func padsOverlap(_ a: SongEditOperation, _ b: SongEditOperation) -> Bool {
        guard let x = a.target.pads, let y = b.target.pads else { return true }
        return !Set(x).isDisjoint(with: y)
    }

    static func describe(_ op: SongEditOperation, project: Project) -> String { op.summary(in: project) }

    /// Changing chord timing or presence changes a bass that is derived from chords.
    static func changesDerivedBass(_ op: SongEditOperation, project: Project) -> Bool {
        guard project.tracks.contains(where: { $0.role == .bass }),
              project.tracks.first(where: { $0.id == op.target.trackID })?.role == .harmony else { return op.kind == .arpeggiate && op.replacesChords && project.tracks.contains { $0.role == .bass } }
        return [.remove, .denser, .sparser, .delay].contains(op.kind)
    }

    // MARK: Tokens

    struct Token: Equatable {
        var text: String
        var offset: Int
        var length: Int
        var isPunctuation: Bool { text.count == 1 && ",.;!?".contains(text) }
    }

    static func normalize(_ text: String) -> String {
        String(text.lowercased().map { c -> Character in
            switch c { case "ё": "е"; case "–", "—": "-"; case "’": "'"; default: c }
        })
    }

    static func tokens(_ text: String) -> [Token] {
        let chars = Array(normalize(text))
        var result: [Token] = [], current = "", start = 0
        func flush(_ end: Int) { if !current.isEmpty { result.append(Token(text: current, offset: start, length: end - start)); current = "" } }
        for (i, c) in chars.enumerated() {
            if c.isLetter || c.isNumber || c == "#" || c == "♭" || c == "♯" || c == "/" || c == "'" || (c == "-" && !current.isEmpty && i + 1 < chars.count && (chars[i + 1].isLetter || chars[i + 1].isNumber)) {
                if current.isEmpty { start = i }
                current.append(c)
            } else {
                flush(i)
                if ",.;!?\n".contains(c) { result.append(Token(text: c == "\n" ? "." : String(c), offset: i, length: 1)) }
            }
        }
        flush(chars.count)
        return result
    }

    static let joiners: Set<String> = [",", "и", "а", "но", "затем", "потом", "and", "then", "but", "also", "также", "плюс", "plus"]

    /// Sentences split at . ; ! ? and then into segments at "and", "but",
    /// "then" or a comma. A segment without its own action or edit word joins
    /// the previous segment (or the next one at the start), so "bass and chords
    /// keep" and "remove the kick and the hats" stay one instruction while
    /// "remove the kick and add a fill" becomes two.
    static func clauses(_ tokens: [Token]) -> [[Token]] {
        var sentences: [[Token]] = [[]]
        for t in tokens {
            if [".", ";", "!", "?"].contains(t.text) { if !(sentences.last?.isEmpty ?? true) { sentences.append([]) } }
            else { sentences[sentences.count - 1].append(t) }
        }
        var result: [[Token]] = []
        for sentence in sentences where !sentence.isEmpty {
            var segments: [[Token]] = [[]]
            for t in sentence {
                if joiners.contains(t.text) { if !(segments.last?.isEmpty ?? true) { segments.append([]) }; continue }
                segments[segments.count - 1].append(t)
            }
            segments.removeAll { $0.isEmpty }
            var merged: [[Token]] = []
            var carry: [Token] = []
            for segment in segments {
                let words = segment.map(\.text)
                if bearsAction(words) {
                    merged.append(carry + segment); carry = []
                } else if merged.isEmpty {
                    carry += segment
                } else {
                    merged[merged.count - 1] += segment
                }
            }
            if !carry.isEmpty { if merged.isEmpty { merged.append(carry) } else { merged[0] = carry + merged[0] } }
            result += merged
        }
        return result
    }

    /// Whether a segment carries its own instruction (an action or edit word).
    static func bearsAction(_ words: [String]) -> Bool {
        words.enumerated().contains { i, w in
            any(w, Lexicon.keep + Lexicon.remove + Lexicon.add + Lexicon.make + Lexicon.fill + Lexicon.arpeggio + Lexicon.delay
                + Lexicon.denser + Lexicon.sparser + Lexicon.fadeIn + Lexicon.fadeOut + ["fade", "введи", "вводи", "выведи", "затух"])
                || (w == "не" && i + 1 < words.count && any(words[i + 1], ["трога", "меня", "измен"] + Lexicon.remove + Lexicon.keep))
                || w == "без" || w == "without"
        }
    }

    static func startsAction(_ tokens: [Token], at i: Int) -> Bool {
        let t = tokens[i].text
        if t == "не" || t == "don't" || t == "dont" || t == "do" { return i + 1 < tokens.count && startsAction(tokens, at: i + 1) }
        return Lexicon.actionStart.contains { matches(t, $0) }
    }

    static func clauseHasAction(_ clause: [Token]) -> Bool { clause.indices.contains { startsAction(clause, at: $0) } }

    // MARK: Fuzzy matching

    /// A token matches a stem when it starts with it, or (for stems of four or
    /// more letters) when its prefix differs by one edit, keeping the first letter.
    static func matches(_ token: String, _ stem: String) -> Bool {
        if token.hasPrefix(stem) { return true }
        guard stem.count >= 4, token.count >= stem.count - 1, token.first == stem.first else { return false }
        let a = Array(token.prefix(stem.count + 1)), b = Array(stem)
        // Edit distance between the stem and the best-matching prefix of the token.
        var previous = Array(0...b.count)
        var best = Int.max
        for i in 1...a.count {
            var row = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                row[j] = min(previous[j] + 1, row[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            if i >= b.count - 1 { best = min(best, row[b.count]) }
            previous = row
        }
        return best <= 1
    }

    static func any(_ token: String, _ stems: [String]) -> Bool { stems.contains { matches(token, $0) } }
    static func exact(_ token: String, _ words: [String]) -> Bool { words.contains(token) }

    // MARK: Clause analysis

    enum Action: Equatable { case keep, remove, add, make }
    enum TargetSpec: Equatable { case pads([Int]), drums, bass, harmony, keys, melody, track(UUID), all }
    enum Place: Equatable { case inside, before, after }

    struct Edit {
        var action: Action?
        var kind: SongEditOperation.Kind?
        var targets: [TargetSpec] = []
        var exceptions: [TargetSpec] = []
        var fillNoun = false
        var sectionKind: [String]? = nil
        var sectionName: String? = nil
        var sectionOrdinal: Int? = nil   // 1-based; -1 = last
        var place: Place = .inside
        var firstBars: Int? = nil
        var lastBars: Int? = nil
        var barRange: ClosedRange<Int>? = nil // 1-based inclusive
        var everyOther = false
        var delayTicks: Int? = nil
        var delayMilliseconds: Double? = nil
        var fillTicks = 2 * ppq
        var replacesChords = false
        var meaningful = false
        var hasScope: Bool { sectionKind != nil || sectionName != nil || firstBars != nil || lastBars != nil || barRange != nil || everyOther }
    }

    static func number(_ token: String) -> Int? {
        if let n = Int(token.trimmingCharacters(in: CharacterSet(charactersIn: "-йгмоыхяе"))), (1...64).contains(n) { return n }
        let digits = token.prefix { $0.isNumber }
        if !digits.isEmpty, let n = Int(digits), (1...64).contains(n) { return n }
        for (value, words) in Lexicon.numbers where words.contains(where: { token == $0 || (token.count > 3 && $0.count >= 4 && token.hasPrefix($0)) }) { return value }
        return nil
    }

    static func analyse(_ clause: [Token], project: Project?) -> Edit {
        var edit = Edit()
        let words = clause.map(\.text).filter { !Token(text: $0, offset: 0, length: 0).isPunctuation }
        edit.meaningful = words.contains { !Lexicon.stopwords.contains($0) && $0.count > 2 }
        // Action and its negation.
        for (i, w) in words.enumerated() {
            let negated = i > 0 && ["не", "don't", "dont", "never", "not"].contains(words[i - 1])
                || (i > 1 && words[i - 2] == "do" && words[i - 1] == "not")
            var found: Action?
            if any(w, Lexicon.keep) || (w == "не" && i + 1 < words.count && any(words[i + 1], ["трога", "меня", "измен"])) { found = .keep }
            else if any(w, Lexicon.remove) { found = .remove }
            else if any(w, Lexicon.add) { found = .add }
            else if any(w, Lexicon.make) { found = .make }
            guard var action = found else { continue }
            if w == "не" { action = .keep }
            else if negated { action = action == .remove ? .keep : (action == .keep ? .remove : action) }
            if edit.action == nil || (edit.action == .make && action != .make) { edit.action = action }
        }
        let text = " " + words.joined(separator: " ") + " "
        func phrase(_ list: [String]) -> Bool { list.contains { text.contains(" " + $0) } }
        // Operation kind.
        edit.fillNoun = words.contains { any($0, Lexicon.fill) }
        let fadeWord = words.firstIndex { $0 == "fade" || $0 == "fades" || $0 == "fading" }
        let fadeOutWord = fadeWord.map { f in words[f...].contains("out") } ?? false
        let fadeInWord = fadeWord.map { f in words[(f + 1)...].contains("in") && !words[f...].contains("out") } ?? false
        if phrase(Lexicon.fadeOutPhrases) || fadeOutWord || words.contains(where: { any($0, Lexicon.fadeOut) }) { edit.kind = .fadeOut }
        else if phrase(Lexicon.fadeInPhrases) || fadeInWord || words.contains(where: { any($0, Lexicon.fadeIn) }) { edit.kind = .fadeIn }
        else if fadeWord != nil { edit.kind = .fadeOut }
        else if edit.fillNoun { edit.kind = .fill }
        else if words.contains(where: { any($0, Lexicon.arpeggio) }) { edit.kind = .arpeggiate }
        else if words.contains(where: { any($0, Lexicon.delay) }) || phrase(["behind the beat", "laid back", "laid-back"]) { edit.kind = .delay }
        else if words.contains(where: { any($0, Lexicon.denser) }) { edit.kind = .denser }
        else if words.contains(where: { any($0, Lexicon.sparser) }) { edit.kind = .sparser }
        else if edit.action == .remove { edit.kind = .remove }
        else if edit.action == nil, words.contains(where: { $0 == "без" || $0 == "without" }) { edit.action = .remove; edit.kind = .remove }
        if edit.kind != nil, edit.action == .keep { edit.action = .make }
        if edit.kind == .arpeggiate, phrase(["вместо аккорд", "instead of the chord", "instead of chord", "replace the chord", "замени аккорд"]) { edit.replacesChords = true }
        if edit.kind == .fill {
            if words.contains(where: { any($0, ["коротк", "небольш", "маленьк", "short", "quick", "brief", "small"]) }) || phrase(["полтакта", "half bar", "half a bar", "half-bar"]) { edit.fillTicks = 2 * ppq }
            if words.contains(where: { any($0, ["длинн", "больш", "long", "big"]) }) || phrase(["целый такт", "на весь такт", "на такт", "full bar", "whole bar", "one bar", "один такт"]) { edit.fillTicks = barTicks }
            if phrase(["одну долю", "на долю", "one beat", "a beat", "single beat"]) { edit.fillTicks = ppq }
        }
        // Targets, with exceptions after "except"/"кроме".
        var exceptionMode = false
        var skip = 0
        for (i, w) in words.enumerated() {
            if skip > 0 { skip -= 1; continue }
            if ["кроме", "except", "excluding", "besides"].contains(w) || (w == "but" && i + 1 < words.count && words[i + 1] == "not") || (w == "за" && i + 1 < words.count && words[i + 1] == "исключением") { exceptionMode = true; continue }
            let next = i + 1 < words.count ? words[i + 1] : ""
            // Section and bar words never name a part ("chorus" is not "chord").
            if Lexicon.sectionKinds.joined().contains(where: { w.hasPrefix($0) }) || Lexicon.bar.contains(where: { w.hasPrefix($0) }) || Lexicon.part.contains(where: { w.hasPrefix($0) }) { continue }
            var spec: TargetSpec?
            if let project, let id = trackNameMatch(w, next: next, project: project) { spec = .track(id); if trackNameIsTwoWords(w, next, project) { skip = 1 } }
            else if (exact(w, Lexicon.bassWords) && (next == "drum" || next == "drums" || any(next, ["бочк"]))) || any(w, Lexicon.kick) { spec = .pads([0]); if exact(w, Lexicon.bassWords) { skip = 1 } }
            else if any(w, Lexicon.snare) { spec = .pads([1]) }
            else if any(w, Lexicon.clap) { spec = .pads([4]) }
            else if any(w, Lexicon.hat) {
                let open = (i > 0 && any(words[i - 1], ["открыт", "open"])), closed = (i > 0 && any(words[i - 1], ["закрыт", "closed"]))
                spec = .pads(open ? [3] : closed ? [2] : [2, 3])
            }
            else if any(w, Lexicon.toms) { spec = .pads([6, 7, 8]) }
            else if any(w, Lexicon.cymbals) { spec = .pads([9, 10]) }
            else if any(w, Lexicon.percussion) { spec = .pads([11, 12, 13, 14, 15]) }
            else if exact(w, Lexicon.bassWords) || any(w, ["басов", "bassline"]) { spec = .bass }
            else if any(w, Lexicon.drums) || exact(w, ["бит", "бита", "биту", "битом", "бите", "биты", "beat", "beats"]) { spec = .drums }
            else if any(w, Lexicon.harmony) { spec = .harmony }
            else if any(w, Lexicon.keys) { spec = .keys }
            else if any(w, Lexicon.melody) { spec = .melody }
            else if exact(w, Lexicon.all) { spec = .all }
            guard let spec else { continue }
            if exceptionMode { if !edit.exceptions.contains(spec) { edit.exceptions.append(spec) } }
            else if !edit.targets.contains(spec) { edit.targets.append(spec) }
        }
        // Scope.
        for (i, w) in words.enumerated() {
            let previous = i > 0 ? words[i - 1] : "", before2 = i > 1 ? words[i - 2] : ""
            let next = i + 1 < words.count ? words[i + 1] : ""
            if let kind = Lexicon.sectionKinds.first(where: { $0.contains { stem in matches(w, stem) } }) {
                // "fill" never names a section; "break" names one only with a section word.
                edit.sectionKind = kind
                if let n = ordinal(previous) ?? ordinal(next) { edit.sectionOrdinal = n }
                else if let n = number(next), Int(next) != nil { edit.sectionOrdinal = n }
                let preposition = [previous, before2, i > 2 ? words[i - 3] : ""]
                if preposition.contains(where: { ["перед", "before", "до", "into", "к"].contains($0) }) { edit.place = .before }
                else if preposition.contains(where: { ["после", "after", "out"].contains($0) }) { edit.place = .after }
            }
            if let project, edit.sectionKind == nil, edit.sectionName == nil,
               let section = project.sections.first(where: { s in let n = normalize(s.name); return n.count >= 3 && (n == w || (w.count >= 4 && matches(w, n))) }) {
                edit.sectionName = normalize(section.name)
                if let n = ordinal(previous) ?? ordinal(next) { edit.sectionOrdinal = n }
                if ["перед", "before", "до"].contains(previous) || ["перед", "before", "до"].contains(before2) { edit.place = .before }
                if ["после", "after"].contains(previous) || ["после", "after"].contains(before2) { edit.place = .after }
            }
            if any(w, Lexicon.part) && !any(w, ["партию", "партия", "партии"]), let n = ordinal(previous) ?? ordinal(next) ?? number(next) {
                edit.sectionKind = ["#part"]; edit.sectionOrdinal = n
                if ["перед", "before", "до"].contains(before2) || ["перед", "before", "до"].contains(previous) { edit.place = .before }
            }
            if any(w, Lexicon.bar) {
                // "first two bars", "первых 2 тактах", "last bar", "the last 4 bars"
                let window = Array(words[max(0, i - 3)..<i])
                let firstIndex = window.lastIndex { any($0, ["перв", "first", "начал", "opening"]) }
                let lastIndex = window.lastIndex { any($0, ["последн", "last", "final", "конечн"]) }
                let count = window.reversed().compactMap { word -> Int? in ordinal(word) == nil || Int(word) != nil || cardinal(word) != nil ? (cardinal(word) ?? Int(word)) : nil }.first
                if let firstIndex, lastIndex.map({ firstIndex > $0 }) ?? true { edit.firstBars = count ?? 1 }
                else if lastIndex != nil { edit.lastBars = count ?? 1 }
                else if ["через", "every", "каждый", "каждом"].contains(previous) || (["каждый", "каждом", "every"].contains(before2) && any(previous, ["втор", "other", "second"])) { edit.everyOther = true }
                else if let n = number(next) ?? (ordinal(previous) ?? Int(previous)) {
                    // "bar 5", "такт 5", "5-м такте", "bars 5-8", "тактах 5–8", "с 5 по 8 такт"
                    var upper = n
                    if next.contains("-"), let parts = Optional(next.split(separator: "-")), parts.count == 2, let a = Int(parts[0]), let b = Int(parts[1]) { edit.barRange = min(a, b)...max(a, b); continue }
                    if i + 3 < words.count, ["-", "по", "to", "through", "до"].contains(words[i + 2]), let m = number(words[i + 3]) { upper = m }
                    edit.barRange = min(n, upper)...max(n, upper)
                }
                if edit.barRange == nil, let s = words[max(0, i - 4)..<i].firstIndex(where: { $0 == "с" || $0 == "from" }),
                   s + 1 < i, let a = number(words[s + 1]), let p = words[(s + 1)..<i].firstIndex(where: { ["по", "to", "до", "through"].contains($0) }), p + 1 < i, let b = number(words[p + 1]) {
                    edit.barRange = min(a, b)...max(a, b); edit.firstBars = nil
                }
            }
            if (w == "every" && next == "other") || phrase(["через такт", "every other", "every second bar", "каждый второй такт", "в каждом втором такте"]) { edit.everyOther = true }
        }
        // Delay amount.
        if edit.kind == .delay {
            for (i, w) in words.enumerated() {
                if let ms = Double(w.filter { $0.isNumber || $0 == "." }), i + 1 < words.count, ["мс", "ms", "миллисекунд"].contains(where: { words[i + 1].hasPrefix($0) }) { edit.delayMilliseconds = ms }
                if w.hasSuffix("ms"), let ms = Double(w.dropLast(2)) { edit.delayMilliseconds = ms }
                if w == "1/16" || any(w, ["шестнадцат", "sixteenth"]) { edit.delayTicks = ppq / 4 }
                if w == "1/8" || any(w, ["восьм", "eighth"]) { edit.delayTicks = ppq / 2 }
                if w == "1/32" || any(w, ["тридцатьвтор", "thirty-second"]) { edit.delayTicks = ppq / 8 }
            }
        }
        return edit
    }

    static func ordinal(_ token: String) -> Int? {
        if any(token, ["последн", "last", "final"]) { return -1 }
        for (value, words) in Lexicon.ordinals where words.contains(where: { token.hasPrefix($0) }) { return value }
        if token.hasSuffix("st") || token.hasSuffix("nd") || token.hasSuffix("rd") || token.hasSuffix("th"), let n = Int(token.dropLast(2)) { return n }
        if token.contains("-"), let n = Int(token.split(separator: "-").first ?? "") , token.split(separator: "-").count == 2, Int(token.split(separator: "-")[1]) == nil { return n }
        return nil
    }

    static func cardinal(_ token: String) -> Int? {
        if let n = Int(token), (1...64).contains(n) { return n }
        for (value, words) in Lexicon.cardinals where words.contains(token) { return value }
        if let o = ordinal(token), o > 0 { return o }
        return nil
    }

    static func trackNameMatch(_ word: String, next: String, project: Project) -> UUID? {
        for track in project.tracks where track.name != nil {
            let name = normalize(track.name!)
            let parts = name.split(separator: " ").map(String.init)
            if parts.count == 2, parts[0] == word, parts[1] == next { return track.id }
            if parts.count == 1, name.count >= 3, word == name || (name.count >= 4 && word.hasPrefix(name)) || (name.count >= 5 && matches(word, name)) { return track.id }
            if parts.count == 2, Int(parts[1]) == nil, parts[0].count >= 4, word == parts[0] { return track.id }
        }
        // A localized display name for a role ("Bass" track named in the user's language).
        if exact(word, Lexicon.bassWords), let bass = project.tracks.first(where: { $0.role == .melody && isBassName($0.name) }) { return bass.id }
        return nil
    }

    static func trackNameIsTwoWords(_ word: String, _ next: String, _ project: Project) -> Bool {
        project.tracks.contains { t in
            guard let name = t.name else { return false }
            let parts = normalize(name).split(separator: " ").map(String.init)
            return parts.count == 2 && parts[0] == word && parts[1] == next
        }
    }

    static func isBassName(_ name: String?) -> Bool {
        guard let name else { return false }
        let n = normalize(name)
        return exact(n, Lexicon.bassWords) || n.hasPrefix("bass") || n.hasPrefix("бас") && !n.hasPrefix("бансур")
    }

    static func isArpName(_ name: String?) -> Bool {
        guard let name else { return false }
        return any(normalize(name), Lexicon.arpeggio)
    }

    // MARK: Resolution

    /// Track IDs (with pads) for target words. A melody track named "Bass" is
    /// the bass in generated songs; a derived bass role track is kept as a
    /// protection target but cannot be edited directly.
    static func resolve(_ specs: [TargetSpec], except: [TargetSpec], project: Project, forEdit: Bool) -> [SongEditTarget] {
        var result: [SongEditTarget] = []
        func add(_ t: SongEditTarget) { if !result.contains(t) { result.append(t) } }
        let drums = project.tracks.first { $0.role == .drums }
        let harmony = project.tracks.first { $0.role == .harmony }
        let namedBass = project.tracks.first { $0.role == .melody && isBassName($0.name) }
        let derivedBass = project.tracks.first { $0.role == .bass }
        let melodies = project.tracks.filter { $0.role == .melody && !isBassName($0.name) }
        let keysTrack = project.tracks.first { t in
            guard let name = t.name else { return false }
            return any(normalize(name), Lexicon.keys)
        }
        for spec in specs {
            switch spec {
            case .pads(let pads): if let drums { add(SongEditTarget(trackID: drums.id, pads: pads)) }
            case .drums: if let drums { add(SongEditTarget(trackID: drums.id)) }
            case .bass:
                if let namedBass { add(SongEditTarget(trackID: namedBass.id)) }
                if let derivedBass { add(SongEditTarget(trackID: derivedBass.id)) }
            case .harmony: if let harmony { add(SongEditTarget(trackID: harmony.id)) }
            case .keys: if let keysTrack { add(SongEditTarget(trackID: keysTrack.id)) } else if let harmony { add(SongEditTarget(trackID: harmony.id)) }
            case .melody: for m in melodies where !isArpName(m.name) || melodies.count == 1 { add(SongEditTarget(trackID: m.id)) }
            case .track(let id): add(SongEditTarget(trackID: id))
            case .all:
                for t in project.tracks where t.role != .bass || !forEdit { add(SongEditTarget(trackID: t.id)) }
            }
        }
        if !except.isEmpty {
            let excluded = resolve(except, except: [], project: project, forEdit: forEdit)
            var narrowed: [SongEditTarget] = []
            for target in result {
                let hits = excluded.filter { $0.trackID == target.trackID }
                if hits.isEmpty { narrowed.append(target); continue }
                // "all drums except the kick" keeps the other pads.
                if let removedPads = hits.compactMap(\.pads).first, hits.allSatisfy({ $0.pads != nil }) {
                    let remaining = (target.pads ?? Array(0..<16)).filter { !removedPads.contains($0) }
                    if !remaining.isEmpty { narrowed.append(SongEditTarget(trackID: target.trackID, pads: remaining)) }
                }
            }
            result = narrowed
        }
        return result
    }

    enum Resolution { case operations([SongEditOperation]), choices([SongEditChoice]), problem(SongEditProblem.Reason) }

    static func sections(matching edit: Edit, project: Project) -> [Section]? {
        if edit.sectionKind == ["#part"] { return project.sections }
        if let name = edit.sectionName { return project.sections.filter { normalize($0.name) == name } }
        guard let kind = edit.sectionKind else { return nil }
        return project.sections.filter { section in
            let name = normalize(section.name)
            return name.split(separator: " ").contains { word in kind.contains { matches(String(word), $0) } } || kind.contains { name.hasPrefix($0) }
        }
    }

    static func label(_ section: Section, project: Project, place: Place) -> String {
        let bar = place == .before ? section.start / barTicks : section.start / barTicks + 1
        let key = place == .before ? "Before %@ (bar %d)" : place == .after ? "After %@ (bar %d)" : "%@ (bar %d)"
        let barNumber = place == .after ? (section.start + section.length) / barTicks : bar
        return String(format: NSLocalizedString(key, comment: "Song edit choice"), section.name, barNumber)
    }

    static func resolveOperations(kind: SongEditOperation.Kind, edit: Edit, project: Project, protected: [UUID], protectedPads: [SongEditTarget] = []) -> Resolution {
        let totalBars = project.length / barTicks
        var targets: [SongEditTarget]
        if kind == .fill {
            guard let drums = project.tracks.first(where: { $0.role == .drums }) else { return .problem(.missing) }
            targets = [SongEditTarget(trackID: drums.id)]
        } else if kind == .arpeggiate {
            let explicit = resolve(edit.targets, except: edit.exceptions, project: project, forEdit: true)
            let melodyTarget = explicit.first { t in project.tracks.first { $0.id == t.trackID }?.role == .melody }
            let arpTrack = project.tracks.first { $0.role == .melody && isArpName($0.name) }
            let harmony = project.tracks.first { $0.role == .harmony }
            guard let target = melodyTarget ?? arpTrack.map({ SongEditTarget(trackID: $0.id) }) ?? harmony.map({ SongEditTarget(trackID: $0.id) }) else { return .problem(.missing) }
            if project.tracks.first(where: { $0.id == target.trackID })?.role == .harmony, project.tracks.count >= 8 { return .problem(.trackLimit) }
            targets = [target]
        } else {
            guard !edit.targets.isEmpty else { return .problem(.unsupported) }
            targets = resolve(edit.targets, except: edit.exceptions, project: project, forEdit: true)
            if edit.targets == [.all] || edit.targets.contains(.all) {
                // "everything" never touches protected parts or pads.
                targets.removeAll { protected.contains($0.trackID) }
                targets = targets.compactMap { target in
                    let kept = Set(protectedPads.filter { $0.trackID == target.trackID }.flatMap { $0.pads ?? [] })
                    guard !kept.isEmpty else { return target }
                    let pads = (target.pads ?? Array(0..<16)).filter { !kept.contains($0) }
                    return pads.isEmpty ? nil : SongEditTarget(trackID: target.trackID, pads: pads)
                }
            }
            if targets.contains(where: { t in project.tracks.first { $0.id == t.trackID }?.role == .bass }) {
                if targets.allSatisfy({ t in project.tracks.first { $0.id == t.trackID }?.role == .bass }) { return .problem(.derivedBass) }
                targets.removeAll { t in project.tracks.first { $0.id == t.trackID }?.role == .bass }
            }
            guard !targets.isEmpty else { return .problem(.missing) }
        }
        // Delay amount at the project tempo.
        var amount = 0
        if kind == .delay {
            if let ticks = edit.delayTicks { amount = ticks }
            else {
                let ms = edit.delayMilliseconds ?? 24
                amount = max(1, Int((ms / 1000 * project.bpm * Double(ppq) / 60).rounded()))
            }
        }
        if kind == .fill { amount = edit.fillTicks }
        func make(_ bars: Range<Int>, section: UUID?) -> [SongEditOperation] {
            targets.map { SongEditOperation(kind: kind, target: $0, bars: bars, sectionID: section, everyOther: edit.everyOther, amount: amount, replacesChords: edit.replacesChords) }
        }
        // Bars inside a section (or the song) for first/last/explicit ranges.
        func bars(in span: Range<Int>) -> Range<Int>? {
            if let n = edit.firstBars { return n <= span.count ? span.lowerBound..<(span.lowerBound + n) : nil }
            if let n = edit.lastBars { return n <= span.count ? (span.upperBound - n)..<span.upperBound : nil }
            if let r = edit.barRange {
                let lower = span.lowerBound + r.lowerBound - 1, upper = span.lowerBound + r.upperBound
                return upper <= span.upperBound ? lower..<upper : nil
            }
            return span
        }
        let song = 0..<totalBars
        guard let candidates = sections(matching: edit, project: project) else {
            // No section named.
            if kind == .fill {
                if let r = edit.barRange { return r.upperBound <= totalBars ? .operations(make((r.upperBound - 1)..<r.upperBound, section: nil)) : .problem(.missing) }
                if edit.lastBars != nil { return .operations(make((totalBars - 1)..<totalBars, section: nil)) }
                let boundaries = project.sections.filter { $0.start > 0 }
                guard !boundaries.isEmpty else { return .problem(.noBarBefore) }
                if boundaries.count == 1, let s = boundaries.first { return .operations(make((s.start / barTicks - 1)..<(s.start / barTicks), section: s.id)) }
                return .choices(boundaries.prefix(6).map { s in
                    SongEditChoice(label: label(s, project: project, place: .before), sectionID: s.id, operations: make((s.start / barTicks - 1)..<(s.start / barTicks), section: s.id))
                })
            }
            guard let range = bars(in: song) else { return .problem(.missing) }
            return .operations(make(range, section: nil))
        }
        guard !candidates.isEmpty else { return .problem(.missing) }
        func resolveSection(_ s: Section) -> Resolution {
            let span = (s.start / barTicks)..<((s.start + s.length) / barTicks)
            if kind == .fill {
                switch edit.place {
                case .before:
                    guard s.start > 0 else { return .problem(.noBarBefore) }
                    return .operations(make((span.lowerBound - 1)..<span.lowerBound, section: s.id))
                case .after, .inside:
                    return .operations(make((span.upperBound - 1)..<span.upperBound, section: s.id))
                }
            }
            switch edit.place {
            case .before:
                // "in the two bars before the chorus"
                let n = edit.lastBars ?? edit.firstBars ?? 1
                guard span.lowerBound - n >= 0 else { return .problem(.noBarBefore) }
                return .operations(make((span.lowerBound - n)..<span.lowerBound, section: s.id))
            case .after:
                let n = edit.firstBars ?? edit.lastBars ?? 1
                guard span.upperBound + n <= totalBars else { return .problem(.missing) }
                return .operations(make(span.upperBound..<(span.upperBound + n), section: s.id))
            case .inside:
                guard let range = bars(in: span) else { return .problem(.missing) }
                return .operations(make(range, section: s.id))
            }
        }
        if let ordinal = edit.sectionOrdinal {
            let index = ordinal == -1 ? candidates.count - 1 : ordinal - 1
            guard candidates.indices.contains(index) else { return .problem(.missing) }
            return resolveSection(candidates[index])
        }
        if candidates.count == 1 { return resolveSection(candidates[0]) }
        // Several occurrences and the choice matters: offer each as a target.
        var choices: [SongEditChoice] = []
        for s in candidates.prefix(6) {
            if case .operations(let ops) = resolveSection(s) {
                choices.append(SongEditChoice(label: label(s, project: project, place: kind == .fill ? (edit.place == .before ? .before : .after) : edit.place), sectionID: s.id, operations: ops))
            }
        }
        guard !choices.isEmpty else { return .problem(.missing) }
        return choices.count == 1 ? .operations(choices[0].operations) : .choices(choices)
    }
}

// MARK: - Lexicon

enum Lexicon {
    static let keep = ["остав", "сохран", "keep", "leave", "preserve", "untouched", "intact", "retain"]
    static let remove = ["убер", "убир", "удал", "выключ", "отключ", "заглуш", "выреж", "выкин", "сними", "убра", "remove", "delete", "drop", "mute", "kill", "silence", "strip", "cut"]
    static let add = ["добав", "встав", "впиш", "вставь", "add", "insert", "put", "include"]
    static let make = ["сделай", "сделать", "пусть", "make", "turn", "play", "сыграй", "играй"]
    static let actionStart = keep + remove + add + make + ["не", "введи", "fade", "затуш", "запазд", "сдвинь", "shift", "delay", "плавно", "постепенно"]
    static let fill = ["сбивк", "сбивоч", "fill", "fills", "drum-fill"]
    static let fadeIn = ["нарастан"]
    static let fadeOut = ["затух", "затуш", "рассеи", "fadeout"]
    static let fadeInPhrases = ["fade in", "fade-in", "fades in", "fading in", "введи постепенно", "введи плавно", "постепенно введи", "плавно введи", "постепенно вводи", "плавное появление", "плавно появ", "постепенно появ", "введи", "вводи"]
    static let fadeOutPhrases = ["fade out", "fade-out", "fades out", "fading out", "плавно убер", "постепенно убер", "плавно убир", "постепенно убир", "выведи", "уведи", "потихоньку убер", "затухание"]
    static let arpeggio = ["арпедж", "арпеж", "арпидж", "arpegg", "arpeg", "arpeggio"]
    static let delay = ["запазд", "опазд", "отстава", "позже", "сдвин", "late", "later", "delay", "shift", "drag"]
    static let denser = ["плотн", "гуще", "чаще", "насыщ", "активн", "удвой", "busier", "busy", "denser", "dense", "double", "fuller"]
    static let sparser = ["реже", "редк", "проще", "разреж", "пореже", "упрост", "sparser", "sparse", "simpler", "simplify", "thinner", "thin", "fewer", "halve"]
    static let kick = ["бочк", "бочек", "бочь", "кик", "kick", "kicks"]
    static let snare = ["малы", "малог", "малом", "малому", "снейр", "снэр", "снер", "рабоч", "snare", "snares"]
    static let clap = ["хлоп", "клэп", "клеп", "clap", "claps"]
    static let hat = ["хэт", "хет", "хай-хэт", "хайхэт", "хай-хет", "хайхет", "hat", "hats", "hihat", "hi-hat", "hi-hats", "hh"]
    static let toms = ["томы", "томов", "томам", "том-том", "tom", "toms"]
    static let cymbals = ["тарелк", "крэш", "креш", "райд", "crash", "cymbal", "ride"]
    static let percussion = ["перкусс", "шейкер", "тамбурин", "percussion", "shaker", "tambourine", "cowbell", "коубел"]
    static let drums = ["ударн", "барабан", "drum", "drums", "percussion"]
    static let bassWords = ["бас", "баса", "басу", "басом", "басе", "басы", "басов", "басовую", "басовая", "басовой", "bass", "basses"]
    static let harmony = ["аккорд", "гармон", "пэд", "chord", "chords", "harmony"]
    static let keys = ["пианин", "фортепиан", "рояль", "клавиш", "клавиш", "piano", "keys", "rhodes", "родес"]
    static let melody = ["мелоди", "лид", "соло", "флейт", "бансури", "melody", "melodies", "lead", "solo", "flute", "bansuri", "topline"]
    static let all = ["все", "всё", "всех", "всю", "весь", "всем", "everything", "all"]
    static let bar = ["такт", "bar", "bars", "measure", "measures"]
    static let part = ["част", "part"]
    static let sectionKinds: [[String]] = [
        ["припев", "хук", "рефрен", "chorus", "choruses", "hook", "refrain"],
        ["куплет", "verse", "verses"],
        ["вступлен", "интро", "intro"],
        ["бридж", "мост", "bridge"],
        ["концовк", "аутро", "outro", "ending", "финал", "coda", "кода"],
        ["проигрыш", "брейкдаун", "breakdown", "interlude"],
    ]
    static let ordinals: [(Int, [String])] = [
        (1, ["перв", "first", "1st"]), (2, ["втор", "second", "2nd"]), (3, ["трет", "third", "3rd"]),
        (4, ["четверт", "fourth"]), (5, ["пят", "fifth"]), (6, ["шест", "sixth"]), (7, ["седьм", "seventh"]), (8, ["восьм", "eighth"]),
    ]
    static let cardinals: [(Int, [String])] = [
        (1, ["один", "одного", "одном", "одну", "одним", "одна", "one", "a"]), (2, ["два", "две", "двух", "двум", "двумя", "two", "couple"]),
        (3, ["три", "трех", "трем", "тремя", "three"]), (4, ["четыре", "четырех", "четырем", "four"]), (5, ["пять", "пяти", "five"]),
        (6, ["шесть", "шести", "six"]), (7, ["семь", "семи", "seven"]), (8, ["восемь", "восьми", "eight"]),
        (12, ["двенадцать", "двенадцати", "twelve"]), (16, ["шестнадцать", "шестнадцати", "sixteen"]),
    ]
    static let numbers: [(Int, [String])] = cardinals + ordinals
    static let stopwords: Set<String> = ["и", "в", "во", "на", "с", "по", "к", "у", "о", "а", "но", "the", "a", "an", "in", "on", "of", "and", "to", "for", "with", "это", "этот", "эту", "там", "тут", "please", "пожалуйста", "bars", "тактах", "такта", "такт", "bar"]
}
