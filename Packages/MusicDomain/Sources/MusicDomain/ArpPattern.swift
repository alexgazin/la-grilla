import Foundation

/// I29 · A custom arpeggio: 8 or 16 steps, each a held-note index (lowest = 1) with an octave
/// offset, or a rest. The kernel plays it on the transport grid (arpeggio mode 4).
public struct ArpPattern: Codable, Equatable, Hashable, Sendable, Identifiable {
    public enum Step: Codable, Equatable, Hashable, Sendable {
        case rest
        /// `index` 0…15 counts held notes from the lowest; `octave` 0…2 raises the step.
        case note(index: Int, octave: Int)
    }

    public static let lengths = [8, 16]
    public static let maxNoteIndex = 15
    public static let maxOctave = 2
    /// The arpeggio order value that plays a pattern instead of up/down/as played.
    public static let kernelMode = 4

    public var name: String
    public var steps: [Step]
    public var id: String { name }

    public init(name: String, steps: [Step]) {
        self.name = name
        self.steps = steps
    }

    public func validate() throws {
        guard (1...16).contains(steps.count), !name.trimmingCharacters(in: .whitespaces).isEmpty, name.count <= 40 else { throw MusicError.invalidProject }
        for step in steps {
            if case let .note(index, octave) = step {
                guard (0...Self.maxNoteIndex).contains(index), (0...Self.maxOctave).contains(octave) else { throw MusicError.invalidProject }
            }
        }
    }

    /// Kernel codes: index + 16 × octave, −1 for a rest.
    public var codes: [Int] {
        steps.map { step in
            switch step {
            case .rest: -1
            case let .note(index, octave): index + 16 * octave
            }
        }
    }

    /// True when at least one step plays.
    public var plays: Bool { steps.contains { $0 != .rest } }

    /// Compact text: "1 3 - 2^1" (note number from the lowest, "^n" octave up, "-" rest).
    public var encoded: String {
        steps.map { step in
            switch step {
            case .rest: "-"
            case let .note(index, octave): octave == 0 ? "\(index + 1)" : "\(index + 1)^\(octave)"
            }
        }.joined(separator: " ")
    }

    public init?(name: String, encoded: String) {
        var parsed: [Step] = []
        for token in encoded.split(whereSeparator: \.isWhitespace) {
            if token == "-" { parsed.append(.rest); continue }
            let parts = token.split(separator: "^", omittingEmptySubsequences: false)
            guard (1...2).contains(parts.count), let number = Int(parts[0]) else { return nil }
            let octave = parts.count == 2 ? Int(parts[1]) : 0
            guard let octave else { return nil }
            parsed.append(.note(index: number - 1, octave: octave))
        }
        let pattern = ArpPattern(name: name, steps: parsed)
        guard (try? pattern.validate()) != nil else { return nil }
        self = pattern
    }

    // MARK: Editing

    /// Tapping a cell: a different note replaces the step, the same note makes it a rest.
    public mutating func toggle(step: Int, note index: Int) {
        guard steps.indices.contains(step), (0...Self.maxNoteIndex).contains(index) else { return }
        if case let .note(current, octave) = steps[step] {
            steps[step] = current == index ? .rest : .note(index: index, octave: octave)
        } else {
            steps[step] = .note(index: index, octave: 0)
        }
    }

    /// Cycles the octave of a playing step: 0 → +1 → +2 → 0.
    public mutating func cycleOctave(step: Int) {
        guard steps.indices.contains(step), case let .note(index, octave) = steps[step] else { return }
        steps[step] = .note(index: index, octave: (octave + 1) % (Self.maxOctave + 1))
    }

    /// 8 ↔ 16 steps: growing repeats the first half, shrinking keeps the first eight.
    public mutating func setLength(_ length: Int) {
        guard Self.lengths.contains(length), length != steps.count else { return }
        if length < steps.count { steps = Array(steps.prefix(length)) }
        else { let first = steps; while steps.count < length { steps.append(first[steps.count % first.count]) } }
    }

    // MARK: Ready patterns

    public static let presets: [ArpPattern] = [
        ArpPattern(name: "Rise", encoded: "1 2 3 4 1^1 2^1 3^1 4^1")!,
        ArpPattern(name: "Alberti", encoded: "1 3 2 3 1 3 2 3")!,
        ArpPattern(name: "Broken chord", encoded: "1 3 2 4 3 1^1 4 2")!,
        ArpPattern(name: "Pulse", encoded: "1 - 1 1^1 - 1 3 -")!,
        ArpPattern(name: "Octave jumps", encoded: "1 1^1 2 2^1 3 3^1 2 2^1")!,
        ArpPattern(name: "Trance gate", encoded: "1 1 - 1 3 - 1 2 1 1 - 1 3 - 2^1 1^1")!,
        ArpPattern(name: "Waltz", encoded: "1 - - 2 3 - 2 3")!,
    ]
}

/// The player's own patterns, kept on this device as JSON, newest last, at most 32.
public struct ArpPatternLibrary: Equatable, Sendable {
    public private(set) var patterns: [ArpPattern]
    public static let limit = 32

    public init(stored: String) {
        let decoded = stored.data(using: .utf8).flatMap { try? JSONDecoder().decode([ArpPattern].self, from: $0) } ?? []
        patterns = Array(decoded.filter { (try? $0.validate()) != nil }.suffix(Self.limit))
    }

    public var stored: String {
        guard let data = try? JSONEncoder().encode(patterns) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Saves under the pattern's name, replacing one with the same name; factory names are kept free.
    @discardableResult public mutating func save(_ pattern: ArpPattern) -> Bool {
        guard (try? pattern.validate()) != nil, !ArpPattern.presets.contains(where: { $0.name == pattern.name }) else { return false }
        patterns.removeAll { $0.name == pattern.name }
        patterns.append(pattern)
        if patterns.count > Self.limit { patterns.removeFirst(patterns.count - Self.limit) }
        return true
    }

    public mutating func remove(_ name: String) { patterns.removeAll { $0.name == name } }

    /// Factory patterns first, then the player's.
    public var all: [ArpPattern] { ArpPattern.presets + patterns }
}
