import Foundation

/// I9 · Lyrics: syllables in Russian and English, laid under the notes of a melody.
public enum Syllables {
    private static let russianVowels: Set<Character> = ["а", "е", "ё", "и", "о", "у", "ы", "э", "ю", "я"]
    private static let englishVowels: Set<Character> = ["a", "e", "i", "o", "u", "y"]

    /// Splits one word into syllables: Russian by vowels (a consonant before a vowel
    /// starts the next syllable), English by vowel groups with a silent final "e".
    public static func split(_ word: String) -> [String] {
        let letters = Array(word)
        guard !letters.isEmpty else { return [] }
        let lower = letters.map { Character($0.lowercased()) }
        let cyrillic = lower.contains { $0.unicodeScalars.first.map { (0x0400...0x04FF).contains($0.value) } ?? false }
        let isVowel: (Int) -> Bool = { index in
            cyrillic ? russianVowels.contains(lower[index]) : (englishVowels.contains(lower[index]) && !(lower[index] == "y" && index == 0))
        }
        var vowels = lower.indices.filter(isVowel)
        if !cyrillic {
            // Vowel groups count once ("rain", "you"); a final silent e does not count ("time").
            vowels = vowels.enumerated().filter { $0.offset == 0 || $0.element != vowels[$0.offset - 1] + 1 }.map(\.element)
            if vowels.count > 1, let last = vowels.last, last == lower.count - 1, lower[last] == "e", !(lower.count >= 3 && lower[last - 1] == "l") {
                vowels.removeLast()
            }
        }
        guard vowels.count > 1 else { return [word] }
        var cuts: [Int] = []
        for (a, b) in zip(vowels, vowels.dropFirst()) {
            // Between two vowels: one consonant goes to the next syllable; of several, all but the first.
            let consonants = b - a - 1
            var cut = consonants <= 1 ? a + 1 : a + 2
            // Russian й and ь/ъ stay with the previous syllable.
            if cyrillic, cut < b, ["й", "ь", "ъ"].contains(lower[cut]) { cut += 1 }
            if !cyrillic, consonants <= 1, b < lower.count, cut == a + 1 { cut = a + 1 }
            cuts.append(min(cut, b))
        }
        var result: [String] = [], start = 0
        for cut in cuts where cut > start { result.append(String(letters[start..<cut])); start = cut }
        result.append(String(letters[start...]))
        return result
    }

    /// Syllables of a line, hyphenated for display ("лю-бовь", "rai-ning").
    public static func line(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).flatMap { raw -> [String] in
            let word = raw.trimmingCharacters(in: .punctuationCharacters)
            guard !word.isEmpty else { return [] }
            // Hyphens the writer typed ("мо-ло-ко") are their syllables.
            let parts = word.contains("-") ? word.split(separator: "-").map(String.init).filter { !$0.isEmpty } : split(word)
            return parts.enumerated().map { $0.offset < parts.count - 1 ? $0.element + "-" : $0.element }
        }
    }

    /// Puts the syllables of `lyrics` on the notes in order. Returns the notes and how
    /// many syllables found no note (positive) or notes left without words (negative).
    public static func assign(_ lyrics: String, to notes: [NoteEvent]) -> (notes: [NoteEvent], balance: Int) {
        let syllables = lyrics.components(separatedBy: .newlines).flatMap(line)
        var result = notes.sorted { $0.tick < $1.tick }
        for index in result.indices { result[index].syllable = index < syllables.count ? String(syllables[index].prefix(32)) : nil }
        return (result, syllables.count - result.count)
    }
}

/// I14 · A package for any DAW: aligned stems, a MIDI file with tempo, key and section
/// markers, and a README in plain words.
public enum DAWPackage {
    public static func readme(_ project: Project, settings: WAVSettings) -> String {
        var lines = [
            "\(project.name) — La Grilla",
            "",
            "Tempo: \(project.bpm == project.bpm.rounded() ? String(Int(project.bpm)) : String(project.bpm)) BPM · Time signature: 4/4 · Key: \(project.keyName)",
            "Audio: \(Int(settings.sampleRate)) Hz, \(settings.bitDepth)-bit WAV, every stem starts at bar 1.",
            "",
            "Sections:",
        ]
        for section in project.sections {
            lines.append("  bar \(section.start / barTicks + 1): \(section.name) (\(section.length / barTicks) bars)")
        }
        lines += ["", "Tracks:"]
        for (index, track) in project.tracks.enumerated() {
            lines.append("  \(String(format: "%02d", index + 1))-\(track.role.rawValue).wav — \(track.displayName)")
        }
        lines += [
            "",
            "song.mid has every part with the tempo, key and section markers.",
            "Logic, GarageBand, Ableton Live, FL Studio, Reaper: set the project tempo first,",
            "then drop the WAV files at bar 1 and song.mid for the notes.",
        ]
        return lines.joined(separator: "\n") + "\n"
    }

    /// Files added next to the stems.
    public static func extras(_ project: Project, range: Range<Int>?, settings: WAVSettings) throws -> [ProjectArchive.Entry] {
        [.init("song.mid", try MIDIExporter.data(project, range: range)),
         .init("README.txt", Data(readme(project, settings: settings).utf8))]
    }
}

/// I51 · Title, artist and a comment (tempo and key) inside a WAV's LIST/INFO chunk,
/// which music apps and Finder show. The audio data is untouched.
public enum WAVMetadata {
    public static func write(_ url: URL, title: String, artist: String?, comment: String) throws {
        var data = try Data(contentsOf: url)
        guard data.count >= 12, String(decoding: data[0..<4], as: UTF8.self) == "RIFF", String(decoding: data[8..<12], as: UTF8.self) == "WAVE" else {
            throw ExportError.invalidArchive
        }
        func field(_ id: String, _ text: String) -> Data {
            var value = Data(text.prefix(200).utf8); value.append(0)
            if value.count % 2 == 1 { value.append(0) }
            var chunk = Data(id.utf8)
            withUnsafeBytes(of: UInt32(value.count).littleEndian) { chunk.append(contentsOf: $0) }
            chunk.append(value)
            return chunk
        }
        var info = Data("INFO".utf8)
        info.append(field("INAM", title))
        if let artist, !artist.isEmpty { info.append(field("IART", artist)) }
        info.append(field("ICMT", comment))
        info.append(field("ISFT", "La Grilla"))
        var list = Data("LIST".utf8)
        withUnsafeBytes(of: UInt32(info.count).littleEndian) { list.append(contentsOf: $0) }
        list.append(info)
        data.append(list)
        let riffSize = UInt32(data.count - 8)
        withUnsafeBytes(of: riffSize.littleEndian) { data.replaceSubrange(4..<8, with: $0) }
        try data.write(to: url, options: .atomic)
    }

    /// Reads the INFO fields back (for tests and the export check).
    public static func read(_ url: URL) throws -> [String: String] {
        let data = try Data(contentsOf: url)
        var result: [String: String] = [:], offset = 12
        func u32(_ o: Int) -> Int { Int(data[o]) | Int(data[o + 1]) << 8 | Int(data[o + 2]) << 16 | Int(data[o + 3]) << 24 }
        while offset + 8 <= data.count {
            let id = String(decoding: data[offset..<offset + 4], as: UTF8.self), size = u32(offset + 4)
            if id == "LIST", offset + 12 <= data.count, String(decoding: data[offset + 8..<offset + 12], as: UTF8.self) == "INFO" {
                var inner = offset + 12
                while inner + 8 <= offset + 8 + size {
                    let key = String(decoding: data[inner..<inner + 4], as: UTF8.self), length = u32(inner + 4)
                    let value = data[(inner + 8)..<min(data.count, inner + 8 + length)]
                    result[key] = String(decoding: value.prefix { $0 != 0 }, as: UTF8.self)
                    inner += 8 + length + (length & 1)
                }
            }
            offset += 8 + size + (size & 1)
        }
        return result
    }
}
