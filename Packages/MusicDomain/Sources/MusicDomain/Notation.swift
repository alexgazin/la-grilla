import Foundation

/// A display preference. Explicit sharps/flats override persisted chord writing
/// visually; Auto honors it and falls back to the project key for legacy data.
public enum PitchSpelling: String, CaseIterable, Sendable {
    /// U38: solfège names (Do, Re, Mi… — До, Ре, Ми… in Russian) spelled like `automatic`.
    case automatic, sharps, flats, solfege
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

    private static let solfegeSyllables = ["C": "Do", "D": "Re", "E": "Mi", "F": "Fa", "G": "Sol", "A": "La", "B": "Si"]
    /// Replaces the letter of a written note with its solfège syllable (localized).
    static func solfege(_ written: String) -> String {
        guard let first = written.first, let syllable = solfegeSyllables[String(first)] else { return written }
        return NSLocalizedString(syllable, comment: "Solfège note name") + written.dropFirst()
    }

    public static func pitchClassName(_ pitchClass: Int, keyRoot: Int, minor: Bool, spelling: PitchSpelling = .automatic) -> String {
        if spelling == .solfege { return solfege(pitchClassName(pitchClass, keyRoot: keyRoot, minor: minor, spelling: .automatic)) }
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
        if spelling == .solfege {
            let written = noteName(midiPitch, keyRoot: keyRoot, minor: minor, spelling: .automatic)
            return solfege(written)
        }
        let name = pitchClassName(midiPitch, keyRoot: keyRoot, minor: minor, spelling: spelling)
        var octave = Int(floor(Double(midiPitch)/12))-1
        // C-flat and B-sharp belong to the written octave of their letter.
        if name.hasPrefix("C"), pc(midiPitch) >= 10 { octave += 1 }
        if name.hasPrefix("B"), pc(midiPitch) <= 1 { octave -= 1 }
        return name + String(octave)
    }

    public static func chordSymbol(_ chord: Chord, keyRoot: Int, minor: Bool, spelling requested: PitchSpelling = .automatic) -> String {
        // Chord symbols stay in letters: "Ля m7" reads worse than "Am7" even for solfège users.
        let spelling: PitchSpelling = requested == .solfege ? .automatic : requested
        let root = rootName(chord,keyRoot:keyRoot,minor:minor,spelling:spelling)
        let suffix = chord.customIntervals.map { "{" + $0.map(String.init).joined(separator:",") + "}" } ?? chord.quality.rawValue
        let bassName = chord.slashBass.map { pitch in
            let written=spelling == .automatic ? ChordWriting.name(chord.slashBassSpelling,for:pitch):nil
            return "/"+(written ?? pitchClassName(pitch,keyRoot:keyRoot,minor:minor,spelling:spelling))
        } ?? (chord.bassPitchClass != chord.root ? "/"+pitchClassName(chord.bassPitchClass,keyRoot:keyRoot,minor:minor,spelling:spelling) : "")
        return root + suffix + bassName
    }

    public static func rootName(_ chord:Chord,keyRoot:Int,minor:Bool,spelling:PitchSpelling = .automatic)->String {
        let written=spelling == .automatic ? ChordWriting.name(chord.rootSpelling,for:chord.root):nil
        return written ?? pitchClassName(chord.root,keyRoot:keyRoot,minor:minor,spelling:spelling)
    }

    /// Spell chord tones by their interval/letter, rather than treating a minor
    /// third as an unrelated chromatic key note. General piano-roll notes retain
    /// the separate key-aware `noteName` API.
    public static func chordNoteName(_ midiPitch:Int,chord:Chord,keyRoot:Int,minor:Bool,spelling:PitchSpelling = .automatic)->String {
        if spelling != .automatic{return noteName(midiPitch,keyRoot:keyRoot,minor:minor,spelling:spelling)}
        if let bass=chord.slashBass,midiPitch==chord.notes.first,pc(midiPitch)==bass,
           let name=ChordWriting.name(chord.slashBassSpelling,for:bass) {
            return writtenNote(name,pitch:midiPitch)
        }
        let root=rootName(chord,keyRoot:keyRoot,minor:minor)
        let matchingIntervals=chord.effectiveIntervals.filter{pc($0+chord.root)==pc(midiPitch)}
        guard let first=root.first,let rootLetter=letters.firstIndex(of:String(first)),
              var interval=matchingIntervals.first else {
            return noteName(midiPitch,keyRoot:keyRoot,minor:minor)
        }
        // A custom formula can deliberately include b5/#11 or #5/b13 in
        // different octaves. Match equal-pitch-class voices in register order.
        if matchingIntervals.count>1 {
            var voices=chord.notes.filter{pc($0)==pc(midiPitch)}
            if chord.slashBass==pc(midiPitch),let first=chord.notes.first,voices.first==first{voices.removeFirst()}
            if let index=voices.firstIndex(of:midiPitch),index<matchingIntervals.count{interval=matchingIntervals[index]}
        }
        let degree=chordLetterDegree(interval,in:chord)
        let letter=(rootLetter+degree)%7
        let delta=pc(midiPitch-naturalPitches[letter])
        let accidental=delta<=6 ? delta:delta-12
        guard (-2...2).contains(accidental)else{return noteName(midiPitch,keyRoot:keyRoot,minor:minor)}
        let name=letters[letter]+String(repeating:accidental<0 ? "♭":"♯",count:abs(accidental))
        return writtenNote(name,pitch:midiPitch)
    }

    public static func chordNoteNames(_ chord:Chord,keyRoot:Int,minor:Bool,spelling:PitchSpelling = .automatic)->[String] {
        chord.notes.map{chordNoteName($0,chord:chord,keyRoot:keyRoot,minor:minor,spelling:spelling)}
    }

    private static func writtenNote(_ name:String,pitch:Int)->String {
        guard let first=name.first,let letter=letters.firstIndex(of:String(first))else{return name}
        let alteration=name.filter{$0=="♯"}.count-name.filter{$0=="♭"}.count
        let octave=(pitch-naturalPitches[letter]-alteration)/12-1
        return name+String(octave)
    }

    private static func chordLetterDegree(_ interval:Int,in chord:Chord)->Int {
        let semitone=pc(interval),formula=chord.effectiveIntervals
        switch semitone {
        case 0:return 0
        case 1,2:return 1
        case 3:return interval>=12 && !formula.contains(3) ? 1:2 // #9 versus minor third/doubling.
        case 4:return 2
        case 5:return 3
        case 6:return interval>=12 || (chord.customIntervals != nil && formula.contains(7)) ? 3:4 // #11 / b5.
        case 7:return 4
        case 8:return interval>=12 || (chord.customIntervals != nil && formula.contains(7)) ? 5:4 // b13 / #5.
        case 9:
            let diminished=chord.quality == .diminished7 || (chord.customIntervals != nil && formula.contains(3) && formula.contains(6) && !formula.contains(4) && !formula.contains(7))
            return diminished ? 6:5
        default:return 6
        }
    }

    /// Scale-relative labels describe the persisted written chord, not a functional
    /// analysis. A temporary Sharps/Flats display preference does not rewrite them.
    /// For minor, degrees refer to the natural minor scale (its raised seventh is ♯VII).
    public static func degreeSymbol(_ chord: Chord, keyRoot: Int, minor: Bool) -> String {
        let scale = minor ? minorScale:majorScale
        let relative = pc(chord.root-keyRoot)
        var degree = scale.firstIndex(of: relative)
        var accidental = ""
        if let written=ChordWriting.name(chord.rootSpelling,for:chord.root),let letter=written.first,
           let rootLetter=letters.firstIndex(of:String(letter)),
           let tonicLetter=(minor ? minorTonics:majorTonics)[pc(keyRoot)].first,
           let keyLetter=letters.firstIndex(of:String(tonicLetter)) {
            let writtenDegree=(rootLetter-keyLetter+7)%7
            let delta=pc(relative-scale[writtenDegree])
            let alteration=delta<=6 ? delta:delta-12
            degree=writtenDegree
            accidental=String(repeating:alteration<0 ? "♭":"♯",count:abs(alteration))
        }
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
            let rootOnly = Chord(root:pitch,rootSpelling:chord.slashBassSpelling)
            return "/" + degreeSymbol(rootOnly, keyRoot:keyRoot, minor:minor)
        } ?? ""
        return accidental + (isMinor ? numeral.lowercased():numeral) + suffix + bass
    }
}
