import Foundation

/// I17 · Chords from text: a photo of a songbook page (after on-device text
/// recognition) or pasted text. Chord lines are found among lyrics; bars come from
/// "|", repeats from "|: … :|", "x2"/"х2" and "%" (repeat the previous bar).
public enum ChordTextParser {
    public struct Result: Equatable, Sendable {
        /// Bars in order, each with its chords (split evenly inside the bar).
        public var bars: [[Chord]]
        /// Text lines recognised as chord lines (for highlighting).
        public var chordLines: [Int]
    }

    /// Parses chord lines out of free text. `germanNaming` (H = B, B = B♭) is detected
    /// automatically when any chord uses H, unless set explicitly.
    public static func parse(_ text: String, germanNaming: Bool? = nil) -> Result {
        let lines = text.components(separatedBy: .newlines)
        let german = germanNaming ?? lines.contains { line in tokens(line).contains { $0.hasPrefix("H") && chord($0, german: true) != nil } }
        var bars: [[Chord]] = [], chordLines: [Int] = []
        for (index, line) in lines.enumerated() {
            guard let parsed = chordLine(line, german: german) else { continue }
            chordLines.append(index)
            bars += parsed
        }
        return Result(bars: Array(bars.prefix(maximumSongBars)), chordLines: chordLines)
    }

    /// Chord events over `barTicks` per bar, starting at tick 0.
    public static func events(_ bars: [[Chord]]) -> [ChordEvent] {
        var result: [ChordEvent] = []
        for (bar, chords) in bars.enumerated() where !chords.isEmpty {
            let length = barTicks / chords.count
            for (index, chord) in chords.enumerated() {
                result.append(ChordEvent(tick: bar * barTicks + index * length, duration: index == chords.count - 1 ? barTicks - index * length : length, chord: chord))
            }
        }
        return result
    }

    static func tokens(_ line: String) -> [String] {
        var result: [String] = [], word = ""
        let characters = Array(line)
        var index = 0
        func flush() { if !word.isEmpty { result.append(word); word = "" } }
        while index < characters.count {
            let character = characters[index]
            let next = index + 1 < characters.count ? characters[index + 1] : nil
            if character == "|" && next == ":" { flush(); result.append("|:"); index += 2; continue }
            if character == ":" && next == "|" { flush(); result.append(":|"); index += 2; continue }
            if character == "|" { flush(); result.append("|"); index += 1; continue }
            if character.isWhitespace { flush() } else { word.append(character) }
            index += 1
        }
        flush()
        return result
    }

    static func chord(_ token: String, german: Bool) -> Chord? {
        var value = token.trimmingCharacters(in: CharacterSet(charactersIn: "(),.;"))
        guard let first = value.first, "ABCDEFGHabcdefgh".contains(first) else { return nil }
        // Songbooks write chords with a capital letter; "a", "be" and "had" are words.
        guard first.isUppercase else { return nil }
        if german {
            if value.hasPrefix("H") { value = "B" + value.dropFirst() }
            else if value.hasPrefix("B") && !value.hasPrefix("Bb") && !value.hasPrefix("B#") { value = "Bb" + value.dropFirst() }
        }
        return try? Chord.parse(value)
    }

    private static func repeatCount(_ token: String) -> Int? {
        let lowered = token.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "()"))
        for mark in ["x", "х", "×"] where lowered.hasPrefix(mark) || lowered.hasSuffix(mark) {
            let digits = lowered.replacingOccurrences(of: mark, with: "")
            if let count = Int(digits), (2...8).contains(count) { return count }
        }
        return nil
    }

    /// Bars of one line, or nil when the line is lyrics.
    static func chordLine(_ line: String, german: Bool) -> [[Chord]]? {
        let parts = tokens(line)
        guard !parts.isEmpty else { return nil }
        var chordCount = 0, wordCount = 0
        for part in parts {
            if ["|", "|:", ":|", "%", "-", "/"].contains(part) || repeatCount(part) != nil { continue }
            if chord(part, german: german) != nil { chordCount += 1 } else { wordCount += 1 }
        }
        guard chordCount > 0, Double(chordCount) >= 0.6 * Double(chordCount + wordCount) else { return nil }

        let hasBars = parts.contains("|") || parts.contains("|:") || parts.contains(":|")
        var bars: [[Chord]] = [], current: [Chord] = [], repeatStart: Int?, lineRepeat = 1
        var closedRepeat: [[Chord]]?   // the segment a ":|" just repeated once
        func closeBar() { if !current.isEmpty { bars.append(current); current = [] } }
        for part in parts {
            if let count = repeatCount(part) {
                if let segment = closedRepeat { for _ in 2..<count { bars += segment } }   // "|: A B :| x3" plays three times
                else if let start = repeatStart { closeBar(); let segment = Array(bars[start...]); for _ in 1..<count { bars += segment }; repeatStart = nil }
                else { lineRepeat = count }
                closedRepeat = nil
                continue
            }
            if part != ":|" { closedRepeat = nil }
            switch part {
            case "|": closeBar()
            case "|:": closeBar(); repeatStart = bars.count
            case ":|":
                closeBar()
                if let start = repeatStart, start < bars.count { let segment = Array(bars[start...]); bars += segment; closedRepeat = segment }
                repeatStart = nil
            case "%", "-": closeBar(); if let last = bars.last { bars.append(last) }
            default:
                if let value = chord(part, german: german) {
                    current.append(value)
                    if !hasBars { closeBar() }   // one chord per bar without bar lines
                }
            }
        }
        closeBar()
        let once = bars
        for _ in 1..<lineRepeat { bars += once }
        return bars.isEmpty ? nil : bars.map { Array($0.prefix(4)) }
    }
}
