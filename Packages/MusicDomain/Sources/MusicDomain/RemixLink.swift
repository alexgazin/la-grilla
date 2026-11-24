import Foundation

/// 54 · Who a remix came from; travels with the copy and is shown wherever the song is.
public struct RemixCredit: Codable, Equatable, Sendable {
    public var title: String
    public var author: String?
    public var license: String?
    public init(title: String, author: String?, license: String?) {
        self.title = String(title.prefix(120)); self.author = author.map { String($0.prefix(60)) }; self.license = license
    }
}

/// 54 · "Make your version": the music of a song (structure, chords, beat, notes, mix levels,
/// synth settings) packed into a `lagrilla://remix#…` link. No server or web page is involved: the
/// link opens La Grilla directly, and where a messenger does not make it tappable, "Paste a remix
/// link" in Projects opens it. Recorded and imported sounds are not in links; the project file
/// carries them.
public enum RemixLink {
    public static let scheme = "lagrilla"
    /// Messengers cut long messages (Telegram at 4096 characters); longer songs go as a file.
    public static let maximumLength = 3000
    static let version: UInt8 = 1

    public enum Failure: Error, LocalizedError, Equatable {
        case notAllowed, tooLong, damaged, newerVersion
        public var errorDescription: String? {
            let key = switch self {
            case .notAllowed: "This song is shared to listen only. Choose a licence that allows remixes to share it as a remix."
            case .tooLong: "This song is too long for a link. Share the project file instead."
            case .damaged: "This remix link is incomplete or damaged. Ask for the link again or for the project file."
            case .newerVersion: "This remix link needs a newer La Grilla. Update the app and open it again."
            }
            return NSLocalizedString(key, comment: "Remix link")
        }
    }

    /// Licences that allow someone else to make their version.
    public static func allowsRemix(_ license: String?) -> Bool { license == SongLicense.attribution.rawValue || license == SongLicense.nonCommercial.rawValue }

    // MARK: Link

    /// The shareable link, or `.tooLong` when the song needs the file.
    public static func link(_ project: Project, author: String?) throws -> URL {
        guard allowsRemix(project.license) else { throw Failure.notAllowed }
        let text = scheme + "://remix#" + (try payload(project, author: author))
        guard text.count <= maximumLength, let url = URL(string: text) else { throw Failure.tooLong }
        return url
    }

    /// The packed song from a remix link; nil for other links.
    public static func payload(from url: URL) -> String? {
        guard url.scheme?.lowercased() == scheme, url.host?.lowercased() == "remix" else { return nil }
        let text = url.absoluteString
        guard let hash = text.firstIndex(of: "#") else { return nil }
        let fragment = String(text[text.index(after: hash)...])
        return fragment.isEmpty ? nil : fragment
    }

    /// The first remix link inside pasted text (a whole message can be pasted).
    public static func link(in text: String) -> URL? {
        guard let start = text.range(of: scheme + "://remix#", options: .caseInsensitive) else { return nil }
        let tail = text[start.lowerBound...].prefix { !$0.isWhitespace && $0 != "\"" && $0 != "<" && $0 != ">" }
        return URL(string: String(tail)).flatMap { payload(from: $0) == nil ? nil : $0 }
    }

    // MARK: Packing

    public static func payload(_ project: Project, author: String?) throws -> String {
        let song = Song(project, author: author)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let json = try encoder.encode(song)
        return Base64URL.encode([version] + LZW.encode(Array(json)))
    }

    /// A new project (new identity) with the song's music and its credit.
    public static func project(from payload: String) throws -> Project {
        guard let bytes = Base64URL.decode(payload), let first = bytes.first else { throw Failure.damaged }
        guard first <= version else { throw Failure.newerVersion }
        guard first == version, let json = LZW.decode(Array(bytes.dropFirst())),
              let song = try? JSONDecoder().decode(Song.self, from: Data(json)) else { throw Failure.damaged }
        return try song.project()
    }

    /// A short description of a packed song (for the page and a confirmation), without making it.
    public static func summary(_ payload: String) throws -> (title: String, author: String?, bpm: Int, sections: [String]) {
        let project = try project(from: payload)
        return (project.remixOf?.title ?? project.name, project.remixOf?.author, Int(project.bpm.rounded()), project.sections.map(\.name))
    }

    // MARK: Compact song

    /// Short keys and no identifiers keep links small; identifiers are made anew on opening.
    struct Song: Codable, Equatable {
        var n: String                 // name
        var a: String?                // author
        var l: String?                // licence
        var b: Double                 // tempo
        var k: Int                    // key root
        var m: Bool                   // minor
        var g: Double                 // master gain
        var bo: Int?                  // bass octave
        var bg: Double?               // bass gate
        var s: [S]                    // sections
        var t: [T]                    // tracks
        var p: [P]                    // patterns
        var mk: [MK]?                 // markers
        var eq: StudioEQ?             // master EQ
        var fx: MasterFX?             // master effects

        struct S: Codable, Equatable { var n: String; var s: Int; var l: Int; var c: Int? }
        struct MK: Codable, Equatable { var t: Int; var x: String }
        struct T: Codable, Equatable {
            var r: TrackRole; var n: String?; var g: Double; var p: Double; var m: Bool?
            var c: [C]; var y: SynthPatch?; var q: StudioEQ?; var d: TrackDynamics?; var o: Int?; var gl: Double?; var mp: [Int]?
        }
        struct C: Codable, Equatable { var p: Int; var s: Int; var l: Int; var o: Int?; var m: Bool?; var c: Int? }
        struct H: Codable, Equatable { var t: Int; var d: Int; var c: Chord; var v: Int? }
        /// Drums: [Δtick, pad, velocity] plus [probability, ratchet] when set; notes: [Δtick, duration, pitch, velocity].
        struct P: Codable, Equatable { var l: Int; var h: [H]?; var d: [[Int]]?; var x: [[Int]]? }

        init(_ project: Project, author: String?) {
            n = String(project.name.prefix(120)); a = author.map { String($0.prefix(60)) }; l = project.license
            b = project.bpm; k = project.keyRoot; m = project.minor; g = project.master
            bo = project.bassOctave == 0 ? nil : project.bassOctave; bg = project.bassGate == 0.9 ? nil : project.bassGate
            s = project.sections.map { S(n: $0.name, s: $0.start, l: $0.length, c: $0.color) }
            mk = project.markers.map { $0.map { MK(t: $0.tick, x: $0.text) } }
            eq = project.masterEQ; fx = project.masterFX
            let index = Dictionary(uniqueKeysWithValues: project.patterns.enumerated().map { ($0.element.id, $0.offset) })
            t = project.tracks.map { track in
                T(r: track.role, n: track.name, g: track.gain, p: track.pan, m: track.mute ? true : nil,
                  c: track.clips.compactMap { clip in
                      index[clip.patternID].map { C(p: $0, s: clip.start, l: clip.length, o: clip.offset == 0 ? nil : clip.offset, m: clip.muted, c: clip.color) }
                  },
                  y: track.synth, q: track.equalizer, d: track.dynamics, o: track.color, gl: track.glide, mp: track.mutedPads)
            }
            p = project.patterns.map { pattern in
                var lastDrum = 0, lastNote = 0
                let drums = pattern.drums.sorted { ($0.tick, $0.pad) < ($1.tick, $1.pad) }.map { hit -> [Int] in
                    defer { lastDrum = hit.tick }
                    var row = [hit.tick - lastDrum, hit.pad, hit.velocity]
                    if hit.probability != nil || hit.ratchet != nil { row += [hit.probability ?? 100, hit.ratchet ?? 1] }
                    return row
                }
                let notes = (pattern.notes ?? []).sorted { ($0.tick, $0.pitch) < ($1.tick, $1.pitch) }.map { note -> [Int] in
                    defer { lastNote = note.tick }
                    return [note.tick - lastNote, note.duration, note.pitch, note.velocity]
                }
                return P(l: pattern.length, h: pattern.chords.isEmpty ? nil : pattern.chords.map { H(t: $0.tick, d: $0.duration, c: $0.chord, v: $0.velocity) },
                         d: drums.isEmpty ? nil : drums, x: notes.isEmpty ? nil : notes)
            }
        }

        func project() throws -> Project {
            guard !t.isEmpty, !s.isEmpty, t.count <= 8, p.count <= 128, s.count <= 64 else { throw Failure.damaged }
            var project = Project(name: n, bars: 1)
            project.bpm = b; project.keyRoot = k; project.minor = m; project.master = g
            project.bassOctave = bo ?? 0; project.bassGate = bg ?? 0.9
            project.masterEQ = eq; project.masterFX = fx
            project.sections = s.map { var section = Section(name: $0.n, start: $0.s, length: $0.l); section.color = $0.c; return section }
            project.markers = mk.map { $0.map { Marker(tick: $0.t, text: $0.x) } }
            let patterns: [Pattern] = try p.map { item in
                guard item.l > 0, item.l <= songTickLimit else { throw Failure.damaged }
                var pattern = Pattern(length: item.l)
                pattern.chords = (item.h ?? []).map { ChordEvent(tick: $0.t, duration: $0.d, chord: $0.c, velocity: $0.v) }
                var tick = 0
                pattern.drums = try (item.d ?? []).map { row in
                    guard row.count == 3 || row.count == 5 else { throw Failure.damaged }
                    tick += row[0]
                    var hit = DrumEvent(tick: tick, pad: row[1], velocity: row[2])
                    if row.count == 5 { hit.probability = row[3] == 100 ? nil : row[3]; hit.ratchet = row[4] == 1 ? nil : row[4] }
                    return hit
                }
                tick = 0
                let notes = try (item.x ?? []).map { row -> NoteEvent in
                    guard row.count == 4 else { throw Failure.damaged }
                    tick += row[0]
                    return NoteEvent(tick: tick, duration: row[1], pitch: row[2], velocity: row[3])
                }
                pattern.notes = notes.isEmpty ? nil : notes
                return pattern
            }
            project.patterns = patterns
            project.tracks = try t.map { item in
                var track = Track(role: item.r)
                track.name = item.n; track.gain = item.g; track.pan = item.p; track.mute = item.m ?? false
                track.synth = item.y; track.equalizer = item.q; track.dynamics = item.d; track.color = item.o; track.glide = item.gl; track.mutedPads = item.mp
                track.clips = try item.c.map { clip in
                    guard patterns.indices.contains(clip.p) else { throw Failure.damaged }
                    var made = Clip(patternID: patterns[clip.p].id, start: clip.s, length: clip.l)
                    made.offset = clip.o ?? 0; made.muted = clip.m; made.color = clip.c
                    return made
                }
                return track
            }
            project.license = l
            project.remixOf = RemixCredit(title: n, author: a, license: l)
            project.name = String((n + " · " + NSLocalizedString("my version", comment: "Remix name")).prefix(120))
            do { try project.validate() } catch { throw Failure.damaged }
            return project
        }
    }
}

/// URL-safe Base64 without padding.
enum Base64URL {
    static func encode(_ bytes: [UInt8]) -> String {
        Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    static func decode(_ text: String) -> [UInt8]? {
        var base = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        guard base.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "+" || $0 == "/") }) else { return nil }
        while base.count % 4 != 0 { base += "=" }
        return Data(base64Encoded: base).map(Array.init)
    }
}

/// LZW with fixed 12-bit codes (4096 entries, no reset): small, dependency-free, and simple to
/// mirror in the remix page's JavaScript.
enum LZW {
    static let limit = 4096

    static func encode(_ input: [UInt8]) -> [UInt8] {
        guard let firstByte = input.first else { return [] }
        var dictionary: [Int: Int] = [:]
        var next = 256
        var codes: [Int] = []
        var current = Int(firstByte)
        for byte in input.dropFirst() {
            let key = current << 8 | Int(byte)
            if let code = dictionary[key] { current = code; continue }
            codes.append(current)
            if next < limit { dictionary[key] = next; next += 1 }
            current = Int(byte)
        }
        codes.append(current)
        return pack(codes)
    }

    static func decode(_ input: [UInt8]) -> [UInt8]? {
        let codes = unpack(input)
        guard let first = codes.first, first < 256 else { return input.isEmpty ? [] : nil }
        var dictionary: [[UInt8]] = (0..<256).map { [UInt8($0)] }
        var output = dictionary[first]
        var previous = first
        for code in codes.dropFirst() {
            let entry: [UInt8]
            if code < dictionary.count { entry = dictionary[code] }
            else if code == dictionary.count { entry = dictionary[previous] + [dictionary[previous][0]] }
            else { return nil }
            output += entry
            if dictionary.count < limit { dictionary.append(dictionary[previous] + [entry[0]]) }
            previous = code
            guard output.count < 4_000_000 else { return nil }
        }
        return output
    }

    /// Two 12-bit codes per three bytes; a last odd code takes two bytes.
    static func pack(_ codes: [Int]) -> [UInt8] {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(codes.count * 3 / 2 + 2)
        var index = 0
        while index + 1 < codes.count {
            let a = codes[index], b = codes[index + 1]
            bytes += [UInt8(a >> 4), UInt8((a & 0xF) << 4 | b >> 8), UInt8(b & 0xFF)]
            index += 2
        }
        if index < codes.count { let a = codes[index]; bytes += [UInt8(a >> 4), UInt8((a & 0xF) << 4)] }
        return bytes
    }

    static func unpack(_ bytes: [UInt8]) -> [Int] {
        var codes: [Int] = []
        var index = 0
        while index + 2 < bytes.count {
            codes.append(Int(bytes[index]) << 4 | Int(bytes[index + 1]) >> 4)
            codes.append((Int(bytes[index + 1]) & 0xF) << 8 | Int(bytes[index + 2]))
            index += 3
        }
        if index + 1 < bytes.count { codes.append(Int(bytes[index]) << 4 | Int(bytes[index + 1]) >> 4) }
        return codes
    }
}
