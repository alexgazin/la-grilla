import Foundation

/// A display preference. It does not change MIDI pitches or retain typed spelling.
public enum PitchSpelling: String, CaseIterable, Sendable {
    case automatic, sharps, flats
}

public enum MusicalNotation {
    private static let sharps = ["C","C♯","D","D♯","E","F","F♯","G","G♯","A","A♯","B"]
    private static let flats = ["C","D♭","D","E♭","E","F","G♭","G","A♭","A","B♭","B"]
    private static let majorTonics = ["C","D♭","D","E♭","E","F","F♯","G","A♭","A","B♭","B"]
    private static let minorTonics = ["C","C♯","D","E♭","E","F","F♯","G","G♯","A","B♭","B"]
    private static let majorFifths = [0,-5,2,-3,4,-1,6,1,-4,3,-2,5]
    private static let minorFifths = [-3,4,-1,-6,1,-4,3,-2,5,0,-5,2]
    private static let letters = ["C","D","E","F","G","A","B"]
    private static let naturalPitches = [0,2,4,5,7,9,11]
    private static let majorScale = [0,2,4,5,7,9,11]
    private static let minorScale = [0,2,3,5,7,8,10]
    private static func pc(_ value: Int) -> Int { (value % 12 + 12) % 12 }
    private static func prefersFlats(keyRoot: Int, minor: Bool) -> Bool {
        (minor ? minorFifths : majorFifths)[pc(keyRoot)] < 0
    }

    public static func pitchClassName(_ pitchClass: Int, keyRoot: Int, minor: Bool, spelling: PitchSpelling = .automatic) -> String {
        let pitch = pc(pitchClass), root = pc(keyRoot)
        if spelling == .sharps { return sharps[pitch] }
        if spelling == .flats { return flats[pitch] }
        let scale = minor ? minorScale : majorScale
        if let degree = scale.firstIndex(of: pc(pitch-root)) {
            let tonic = (minor ? minorTonics : majorTonics)[root]
            let tonicLetter = letters.firstIndex(of: String(tonic.prefix(1)))!
            let letter = (tonicLetter + degree) % 7
            let delta = pc(pitch-naturalPitches[letter])
            let accidental = delta <= 6 ? delta : delta-12
            if (-2...2).contains(accidental) {
                return letters[letter] + String(repeating: accidental < 0 ? "♭":"♯", count: abs(accidental))
            }
        }
        return (prefersFlats(keyRoot: root, minor: minor) ? flats:sharps)[pitch]
    }

    public static func noteName(_ midiPitch: Int, keyRoot: Int, minor: Bool, spelling: PitchSpelling = .automatic) -> String {
        let name = pitchClassName(midiPitch, keyRoot: keyRoot, minor: minor, spelling: spelling)
        var octave = Int(floor(Double(midiPitch)/12))-1
        // C-flat and B-sharp belong to the written octave of their letter.
        if name.hasPrefix("C"), pc(midiPitch) >= 10 { octave += 1 }
        if name.hasPrefix("B"), pc(midiPitch) <= 1 { octave -= 1 }
        return name + String(octave)
    }

    public static func chordSymbol(_ chord: Chord, keyRoot: Int, minor: Bool, spelling: PitchSpelling = .automatic) -> String {
        let root = pitchClassName(chord.root, keyRoot: keyRoot, minor: minor, spelling: spelling)
        let suffix = chord.customIntervals.map { "{" + $0.map(String.init).joined(separator:",") + "}" } ?? chord.quality.rawValue
        let bass = chord.slashBass.map { "/" + pitchClassName($0, keyRoot: keyRoot, minor: minor, spelling: spelling) } ?? ""
        return root + suffix + bass
    }

    /// Scale-relative labels describe the written chord, not a functional analysis.
    /// For minor, degrees refer to the natural minor scale (its raised seventh is ♯VII).
    public static func degreeSymbol(_ chord: Chord, keyRoot: Int, minor: Bool) -> String {
        let scale = minor ? minorScale:majorScale
        let relative = pc(chord.root-keyRoot)
        var degree = scale.firstIndex(of: relative)
        var accidental = ""
        if degree == nil {
            // Prefer familiar borrowed major-key labels (♭III/♭VI/♭VII),
            // and raised minor sixth/seventh, rather than arbitrary ♯II/♯VI.
            let lowerDegree = minor ? [4,6,9,11].contains(relative):relative == 6
            let adjusted = pc(relative + (lowerDegree ? -1:1))
            degree = scale.firstIndex(of: adjusted)
            accidental = lowerDegree ? "♯":"♭"
        }
        let numerals = ["I","II","III","IV","V","VI","VII"]
        let isMinor = chord.effectiveIntervals.contains(3) && !chord.effectiveIntervals.contains(4)
        let numeral = numerals[degree ?? 0]
        let suffix: String
        if let intervals = chord.customIntervals { suffix = "{" + intervals.map(String.init).joined(separator:",") + "}" }
        else if chord.quality == .dim { suffix = "°" }
        else if chord.quality == .diminished7 { suffix = "°7" }
        else if chord.quality == .m7b5 { suffix = "ø7" }
        else { suffix = isMinor && chord.quality.rawValue.hasPrefix("m") ? String(chord.quality.rawValue.dropFirst()):chord.quality.rawValue }
        let bass = chord.slashBass.map { pitch in
            let rootOnly = Chord(root:pitch)
            return "/" + degreeSymbol(rootOnly, keyRoot:keyRoot, minor:minor)
        } ?? ""
        return accidental + (isMinor ? numeral.lowercased():numeral) + suffix + bass
    }
}
