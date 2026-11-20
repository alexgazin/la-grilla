import Foundation

public let ppq = 960
public let barTicks = 3840
public let masterBus = 8
/// I38 · longest song (bars) and most sections; the kernel shares the tick limit.
public let maximumSongBars = 128
public let maximumSections = 16
public let songTickLimit = maximumSongBars * barTicks
public enum TrackRole: String, Codable, CaseIterable, Sendable { case harmony, drums, bass, melody
    public var instrument:Int {switch self{case .harmony:0;case .drums:1;case .bass:2;case .melody:3}}
}
public enum ChordFamily:String,CaseIterable,Sendable {
    case basic="Basic chords",sevenths="Sevenths",extensions="Extensions",altered="Altered chords",suspended="Suspended chords"
}
public enum Quality: String, Codable, CaseIterable, Sendable {
    // Raw values are the stable document representation and canonical notation.
    case major = "", minor = "m", dim, aug, sus2, sus4, seventh = "7", maj7, m7, m7b5
    case sixth="6",m6,add9,ninth="9",maj9,m9,eleventh="11",m11,thirteenth="13",flat9="7b9",sharp9="7#9",sharp11="7#11",flat13="7b13"
    case diminished7="dim7",augmented7="7#5",augmentedMajor7="maj7#5"
    case minorMajor7="mMaj7",minorMajor9="mMaj9",minorMajor11="mMaj11",minorMajor13="mMaj13"
    case major11="maj11",major13="maj13",minor13="m13",sixNine="6/9",minorSixNine="m6/9"
    case add2,add4,add11,minorAdd9="madd9",minorAdd11="madd11"
    case sevenSus2="7sus2",sevenSus4="7sus4",nineSus4="9sus4",thirteenSus4="13sus4"
    case sevenFlat5="7b5",nineFlat5="9b5",nineSharp5="9#5",major7Flat5="maj7b5",minor7Sharp5="m7#5",minor9Flat5="m9b5"
    case nineSharp11="9#11",thirteenSharp11="13#11",thirteenFlat9="13b9",thirteenSharp9="13#9"
    case sevenFlat9Sharp11="7b9#11",sevenSharp9Sharp11="7#9#11",sevenFlat9Flat13="7b9b13",sevenSharp9Flat13="7#9b13"
    case sevenSharp5Flat9="7#5b9",sevenSharp5Sharp9="7#5#9",alteredDominant="7alt"
    case major7Sharp11="maj7#11",major9Sharp11="maj9#11",major13Sharp11="maj13#11",sevenSus4Flat9="7sus4b9"
    public var intervals: [Int] {
        switch self {
        case .major: [0,4,7]; case .minor: [0,3,7]; case .dim: [0,3,6]; case .aug: [0,4,8]
        case .sus2: [0,2,7]; case .sus4: [0,5,7]; case .seventh: [0,4,7,10]
        case .maj7: [0,4,7,11]; case .m7: [0,3,7,10]; case .m7b5: [0,3,6,10]
        case .sixth:[0,4,7,9];case .m6:[0,3,7,9];case .add9:[0,4,7,14]
        case .ninth:[0,4,7,10,14];case .maj9:[0,4,7,11,14];case .m9:[0,3,7,10,14]
        case .eleventh:[0,4,7,10,14,17];case .m11:[0,3,7,10,14,17];case .thirteenth:[0,4,7,10,14,17,21]
        case .flat9:[0,4,7,10,13];case .sharp9:[0,4,7,10,15];case .sharp11:[0,4,7,10,18];case .flat13:[0,4,7,10,20]
        case .diminished7:[0,3,6,9];case .augmented7:[0,4,8,10];case .augmentedMajor7:[0,4,8,11]
        case .minorMajor7:[0,3,7,11];case .minorMajor9:[0,3,7,11,14];case .minorMajor11:[0,3,7,11,14,17];case .minorMajor13:[0,3,7,11,14,17,21]
        case .major11:[0,4,7,11,14,17];case .major13:[0,4,7,11,14,17,21];case .minor13:[0,3,7,10,14,17,21]
        case .sixNine:[0,4,7,9,14];case .minorSixNine:[0,3,7,9,14]
        case .add2:[0,2,4,7];case .add4:[0,4,5,7];case .add11:[0,4,7,17];case .minorAdd9:[0,3,7,14];case .minorAdd11:[0,3,7,17]
        case .sevenSus2:[0,2,7,10];case .sevenSus4:[0,5,7,10];case .nineSus4:[0,5,7,10,14];case .thirteenSus4:[0,5,7,10,14,21]
        case .sevenFlat5:[0,4,6,10];case .nineFlat5:[0,4,6,10,14];case .nineSharp5:[0,4,8,10,14];case .major7Flat5:[0,4,6,11]
        case .minor7Sharp5:[0,3,8,10];case .minor9Flat5:[0,3,6,10,14]
        case .nineSharp11:[0,4,7,10,14,18];case .thirteenSharp11:[0,4,7,10,14,18,21]
        case .thirteenFlat9:[0,4,7,10,13,21];case .thirteenSharp9:[0,4,7,10,15,21]
        case .sevenFlat9Sharp11:[0,4,7,10,13,18];case .sevenSharp9Sharp11:[0,4,7,10,15,18]
        case .sevenFlat9Flat13:[0,4,7,10,13,20];case .sevenSharp9Flat13:[0,4,7,10,15,20]
        case .sevenSharp5Flat9:[0,4,8,10,13];case .sevenSharp5Sharp9:[0,4,8,10,15]
        // An explicit altered-dominant palette; compact mode keeps #5 and b9.
        case .alteredDominant:[0,4,8,10,13,15]
        case .major7Sharp11:[0,4,7,11,18];case .major9Sharp11:[0,4,7,11,14,18];case .major13Sharp11:[0,4,7,11,14,18,21]
        case .sevenSus4Flat9:[0,5,7,10,13]
        }
    }
    public var family:ChordFamily {
        switch self {
        case .major,.minor,.dim,.aug,.sixth,.m6,.add2,.add4,.add9,.add11,.minorAdd9,.minorAdd11:return .basic
        case .seventh,.maj7,.m7,.m7b5,.diminished7,.augmented7,.augmentedMajor7,.minorMajor7:return .sevenths
        case .ninth,.maj9,.m9,.eleventh,.m11,.thirteenth,.major11,.major13,.minor13,.minorMajor9,.minorMajor11,.minorMajor13,.sixNine,.minorSixNine:return .extensions
        case .sus2,.sus4,.sevenSus2,.sevenSus4,.nineSus4,.thirteenSus4,.sevenSus4Flat9:return .suspended
        default:return .altered
        }
    }
    /// Tones that may be left out of a compact voicing. The root, chord-defining
    /// third/suspension, seventh, altered tones and named highest extension stay.
    public var optionalVoicingIntervals:Set<Int> {
        switch self {
        case .thirteenth,.major13,.minor13,.minorMajor13:return [7,14,17]
        case .eleventh,.major11,.m11,.minorMajor11:return [7,14]
        case .ninth,.maj9,.m9,.minorMajor9,.add9,.add11,.minorAdd9,.minorAdd11,.sixNine,.minorSixNine,
             .flat9,.sharp9,.sharp11,.flat13,.nineSharp11,.thirteenFlat9,.thirteenSharp9,
             .sevenFlat9Sharp11,.sevenSharp9Sharp11,.sevenFlat9Flat13,.sevenSharp9Flat13,.nineSus4,.major7Sharp11,.major9Sharp11,.sevenSus4Flat9:return [7]
        case .thirteenSharp11,.thirteenSus4,.major13Sharp11:return [7,14]
        case .alteredDominant:return [15]
        default:return []
        }
    }
    public var requiredVoicingIntervals:[Int]{intervals.filter{!optionalVoicingIntervals.contains($0)}}
    public var label: String { NSLocalizedString(self == .major ? "Major" : self == .minor ? "Minor" : rawValue,comment:"Chord quality") }
}
public struct Chord: Codable, Equatable, Sendable {
    public var root: Int {didSet{if root != oldValue{rootBassPitch=nil;rootSpelling=nil}}}
    public var quality: Quality; public var inversion: Int
    public var slashBass:Int? {didSet{if slashBass != oldValue{rootBassPitch=nil;slashBassSpelling=nil};if slashBass==nil{slashBassSpelling=nil}}}
    public var voicedNotes:[Int]?
    /// Schema 9: exact generated-bass MIDI pitch after arrangement transposition.
    /// Nil uses the legacy root/register rule; changing root/slash clears the override.
    public var rootBassPitch:Int?
    /// Schema 10: selected written letter/accidental. Nil means the legacy data
    /// never retained it; Auto then derives a display name from the project key.
    public var rootSpelling:String?
    public var slashBassSpelling:String?
    public var customIntervals:[Int]?
    /// Whole-chord register shift in octaves (−2…+2). Nil is the legacy register.
    public var octave:Int?
    public static let octaveRange = -2...2
    public static let maximumVoices=9 // Eight formula tones plus an explicit slash bass.
    public init(root: Int = 0, quality: Quality = .major, inversion: Int = 0,slashBass:Int?=nil,voicedNotes:[Int]?=nil,customIntervals:[Int]?=nil,rootBassPitch:Int?=nil,rootSpelling:String?=nil,slashBassSpelling:String?=nil) { self.root = root; self.quality = customIntervals==nil ? quality:.major; self.inversion = inversion;self.slashBass=slashBass;self.voicedNotes=voicedNotes;self.customIntervals=customIntervals;self.rootBassPitch=rootBassPitch;self.rootSpelling=rootSpelling.map{ChordWriting.canonical($0) ?? $0};self.slashBassSpelling=slashBassSpelling.map{ChordWriting.canonical($0) ?? $0} }
    public static let roots = ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]
    public var effectiveIntervals:[Int]{customIntervals ?? quality.intervals}
    public var requiredVoicingIntervals:[Int]{customIntervals ?? quality.requiredVoicingIntervals}
    public var symbol: String {
        let rootName=ChordWriting.name(rootSpelling,for:root) ?? Self.roots[(root % 12 + 12) % 12]
        let suffix:String
        if let customIntervals{suffix="{"+customIntervals.map(String.init).joined(separator:",")+"}"}else{suffix=quality.rawValue}
        let bassName=slashBass.map{"/"+(ChordWriting.name(slashBassSpelling,for:$0) ?? Self.roots[($0%12+12)%12])} ?? ""
        return rootName+suffix+bassName
    }
    /// The pitch class the bass should play: the slash bass, else the lowest
    /// chord tone of the chosen inversion, else the root.
    public var bassPitchClass:Int {
        if let slashBass{return slashBass}
        let intervals=effectiveIntervals
        guard voicedNotes==nil,inversion>0,intervals.indices.contains(inversion) else{return root}
        return (root+intervals[inversion])%12
    }
    /// Moves the whole chord by `octaves`, keeping an explicit voicing when it
    /// has one. Returns false (and changes nothing) when it would leave the range.
    @discardableResult public mutating func shiftOctave(by octaves:Int)->Bool {
        guard octaves != 0 else{return true}
        if let voiced=voicedNotes {
            let moved=voiced.map{$0+12*octaves}
            guard moved.allSatisfy({(0...127).contains($0)})else{return false}
            voicedNotes=moved;return true
        }
        let target=(octave ?? 0)+octaves
        guard Self.octaveRange.contains(target)else{return false}
        var candidate=self;candidate.octave=target==0 ? nil:target
        guard candidate.isValidVoicing(candidate.notes)else{return false}
        self=candidate;return true
    }
    public var notes: [Int] {
        if let voicedNotes{return voicedNotes.sorted()}
        guard (0..<12).contains(root),Self.validIntervals(effectiveIntervals),(0..<effectiveIntervals.count).contains(inversion),slashBass==nil || (0..<12).contains(slashBass!) else{return []}
        let base = (root == 0 ? 60 : 48 + root) + 12 * (octave ?? 0)
        var result = effectiveIntervals.map { base + $0 }
        for i in 0..<inversion {
            result[i] += 12
            // Custom formulas may deliberately include octave doublings.
            while result.enumerated().contains(where:{$0.offset != i && $0.element==result[i]}){result[i] += 12}
        }
        if let slashBass{var bass=48+slashBass+12*(octave ?? 0);while bass>=(result.min() ?? 60){bass-=12};result.append(bass)}
        return result.sorted()
    }
    public static func validIntervals(_ values:[Int])->Bool {
        (2...8).contains(values.count) && values.first==0 && values.allSatisfy{(0...48).contains($0)} && zip(values,values.dropFirst()).allSatisfy{$0.0<$0.1}
    }
    public static func parseCustomIntervals(_ text:String)throws->[Int] {
        guard text.utf8.count<=128 else{throw MusicError.invalidChord}
        let tokens=text.split{$0=="," || $0==";" || $0.isWhitespace}
        let values=tokens.compactMap{Int($0)}
        guard values.count==tokens.count,validIntervals(values)else{throw MusicError.invalidChord}
        return values
    }
    public func isValidVoicing(_ values:[Int])->Bool {
        guard (0..<12).contains(root),Self.validIntervals(effectiveIntervals),!values.isEmpty,values.count<=Self.maximumVoices,
              Set(values).count==values.count,values.allSatisfy({(0...127).contains($0)})else{return false}
        let actual=Set(values.map{$0%12})
        let allowed=Set(effectiveIntervals.map{($0+root)%12}+(slashBass.map{[$0]} ?? []))
        let required=Set(requiredVoicingIntervals.map{($0+root)%12}+(slashBass.map{[$0]} ?? []))
        guard actual.isSubset(of:allowed),required.isSubset(of:actual)else{return false}
        if customIntervals != nil {
            // Preserve every custom tone, including deliberate octave doubling.
            let requiredCounts=Dictionary(grouping:effectiveIntervals.map{($0+root)%12}+(slashBass.map{[$0]} ?? []),by:{$0}).mapValues(\.count)
            let actualCounts=Dictionary(grouping:values.map{$0%12},by:{$0}).mapValues(\.count)
            guard requiredCounts.allSatisfy({actualCounts[$0.key,default:0]>=$0.value})else{return false}
        }
        return true
    }
    public func validate()throws {
        guard (0..<12).contains(root),Self.validIntervals(effectiveIntervals),(0..<effectiveIntervals.count).contains(inversion),customIntervals==nil || quality == .major,
              slashBass==nil || (0..<12).contains(slashBass!),
              ChordWriting.valid(rootSpelling,for:root),
              slashBassSpelling==nil || (slashBass != nil && ChordWriting.valid(slashBassSpelling,for:slashBass!)),
              octave==nil || Self.octaveRange.contains(octave!),
              rootBassPitch==nil || ((0...127).contains(rootBassPitch!) && (rootBassPitch!%12 == (slashBass ?? root) || rootBassPitch!%12 == bassPitchClass)),isValidVoicing(notes) else{throw MusicError.invalidChord}
    }
    public static func parse(_ text: String) throws -> Chord {
        guard text.utf8.count<=256 else{throw MusicError.invalidChord}
        let value=text.trimmingCharacters(in:.whitespacesAndNewlines).replacingOccurrences(of:"♯",with:"#").replacingOccurrences(of:"♭",with:"b").replacingOccurrences(of:"−",with:"-")
        func pitch(_ raw:String)throws->(Int,String,String){
            guard let first=raw.first,let base=["C":0,"D":2,"E":4,"F":5,"G":7,"A":9,"B":11][String(first).uppercased()]else{throw MusicError.invalidChord}
            var suffix=String(raw.dropFirst()),root=base,writing=String(first).uppercased()
            if suffix.hasPrefix("#") || suffix.hasPrefix("b") {
                let accidental=suffix.first!,offset=accidental=="#" ? 1:-1
                var count=0
                while suffix.first==accidental,count<2{root+=offset;writing.append(accidental=="#" ? "♯":"♭");suffix.removeFirst();count+=1}
            }
            return ((root+12)%12,writing,suffix.trimmingCharacters(in:.whitespaces))
        }
        let (root,rootWriting,rawSuffix)=try pitch(value);var suffix=rawSuffix
        var bass:Int?,bassWriting:String?
        // A slash inside 6/9 belongs to the quality; a final /note is the bass.
        if let slash=suffix.lastIndex(of:"/") {
            let tail=String(suffix[suffix.index(after:slash)...]).trimmingCharacters(in:.whitespaces)
            if let (note,writing,remainder)=try? pitch(tail),remainder.isEmpty{bass=note;bassWriting=writing;suffix=String(suffix[..<slash]).trimmingCharacters(in:.whitespaces)}
        }
        if suffix.hasPrefix("{") {
            guard suffix.hasSuffix("}")else{throw MusicError.invalidChord}
            let formula=try parseCustomIntervals(String(suffix.dropFirst().dropLast()))
            let chord=Chord(root:root,slashBass:bass,customIntervals:formula,rootSpelling:rootWriting,slashBassSpelling:bassWriting);try chord.validate();return chord
        }
        suffix=suffix.filter{!$0.isWhitespace}
        if suffix.contains("(") || suffix.contains(")") {
            guard suffix.filter({$0=="("}).count==1,suffix.filter({$0==")"}).count==1,suffix.last==")",let opening=suffix.firstIndex(of:"(") else{throw MusicError.invalidChord}
            let prefix=String(suffix[..<opening]),inside=String(suffix[suffix.index(after:opening)..<suffix.index(before:suffix.endIndex)])
            suffix=prefix+inside.replacingOccurrences(of:",",with:"")
        }
        let aliases:[String:Quality]=[
            "M":.major,"M7":.maj7,"M9":.maj9,"M11":.major11,"M13":.major13,
            "Δ":.maj7,"Δ7":.maj7,"Δ9":.maj9,"Δ11":.major11,"Δ13":.major13,
            "M7#11":.major7Sharp11,"M9#11":.major9Sharp11,"M13#11":.major13Sharp11,
            "Δ7#11":.major7Sharp11,"Δ9#11":.major9Sharp11,"Δ13#11":.major13Sharp11,
            "-":.minor,"-7":.m7,"-9":.m9,"-11":.m11,"-13":.minor13,
            "mM7":.minorMajor7,"mM9":.minorMajor9,"mM11":.minorMajor11,"mM13":.minorMajor13,
            "mΔ7":.minorMajor7,"mΔ9":.minorMajor9,"mΔ11":.minorMajor11,"mΔ13":.minorMajor13,
            "°":.dim,"o":.dim,"°7":.diminished7,"o7":.diminished7,"ø":.m7b5,"ø7":.m7b5,"ø9":.minor9Flat5,
            "+":.aug,"+7":.augmented7,"7+":.augmented7,"aug7":.augmented7,"+M7":.augmentedMajor7,
            "69":.sixNine,"6add9":.sixNine,"m69":.minorSixNine,"m6add9":.minorSixNine,
            "sus":.sus4,"7sus":.sevenSus4,"9sus":.nineSus4,"13sus":.thirteenSus4,
            "major":.major,"maj":.major,"minor":.minor,"min":.minor,"min7":.m7,"min9":.m9,"min11":.m11,"min13":.minor13
            ,"minmaj7":.minorMajor7,"minmaj9":.minorMajor9,"minmaj11":.minorMajor11,"minmaj13":.minorMajor13
        ]
        guard let quality=Quality(rawValue:suffix) ?? aliases[suffix] ?? Quality.allCases.first(where:{$0.rawValue.lowercased()==suffix.lowercased()}) ?? aliases[suffix.lowercased()] else{throw MusicError.invalidChord}
        let chord=Chord(root:root,quality:quality,slashBass:bass,rootSpelling:rootWriting,slashBassSpelling:bassWriting);try chord.validate();return chord
    }
}
public struct ChordEvent: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID = UUID(); public var tick: Int; public var duration: Int; public var chord: Chord
    /// Missing in projects saved before per-chord dynamics; the original attack is 88.
    public var velocity: Int?
    public init(tick: Int, duration: Int = barTicks, chord: Chord, velocity: Int? = nil) {
        self.tick = tick; self.duration = duration; self.chord = chord; self.velocity = velocity
    }
}
public struct DrumEvent: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID = UUID(); public var tick: Int; public var pad: Int; public var velocity: Int
    public init(tick: Int, pad: Int, velocity: Int = 100) { self.tick = tick; self.pad = pad; self.velocity = velocity }
}
public struct NoteEvent: Codable, Equatable, Identifiable, Sendable {
    public var id:UUID=UUID()
    public var tick:Int;public var duration:Int;public var pitch:Int;public var velocity:Int
    public var confidence:Double?
    public init(tick:Int,duration:Int=ppq,pitch:Int=60,velocity:Int=100,confidence:Double?=nil){self.tick=tick;self.duration=duration;self.pitch=pitch;self.velocity=velocity;self.confidence=confidence}
    public var name:String{Chord.roots[(pitch%12+12)%12]+String(pitch/12-1)}
}
public struct Pattern: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID = UUID(); public var length: Int; public var chords: [ChordEvent] = []; public var drums: [DrumEvent] = []; public var notes:[NoteEvent]?
    public init(length: Int, chords: [ChordEvent] = [], drums: [DrumEvent] = [], notes:[NoteEvent]=[]) { self.length = length; self.chords = chords; self.drums = drums; self.notes=notes }
}
public struct Clip: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID = UUID(); public var patternID: UUID;public var sourceAssetID:UUID?; public var start: Int; public var length: Int; public var offset: Int = 0
    /// I34: alternative patterns for this clip (not including the current one),
    /// one to three. Nil in older files.
    public var variants: [UUID]?
    public init(patternID: UUID, start: Int, length: Int) { self.patternID = patternID; self.start = start; self.length = length }
}
public struct Track: Codable, Equatable, Identifiable, Sendable {
    public var equalizer:StudioEQ?
    public var id: UUID = UUID(); public var role: TrackRole; public var name:String?; public var displayName:String{name ?? NSLocalizedString(role.rawValue.capitalized,comment:"Track role")}; public var gain: Double = -6; public var pan: Double = 0
    public var mute = false; public var solo = false; public var presetVersion = 2; public var clips: [Clip] = []
    public var instrumentSample: SampleAsset?
    public var padSamples: [Int: SampleAsset]?
    public var padEdits: [Int: PadSampleEditRecord]?
    /// I39: a locked part is kept by generators, palettes and phrase edits.
    /// Absent in older files (= unlocked); older apps ignore it.
    public var locked: Bool?
    /// I5 · I56 · I57: choke groups, sidechain and insert colour; nil = neutral.
    public var dynamics: TrackDynamics?
    /// I55: synth voice for the built-in sound of a melodic track; nil = the palette preset.
    public var synth: SynthPatch?
    public init(role: TrackRole) { self.role = role }
}
public struct Section: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID = UUID(); public var name: String; public var start: Int; public var length: Int
    /// I35: chosen colour (0 harmony, 1 drums, 2 bass, 3 mint). Nil = by name, as before.
    public var color: Int?
    /// I36: master filter sweep across this section (from → to, −1 low-pass … 0 open … 1 high-pass).
    public var filterSweep: FilterSweep?
    public init(name: String, start: Int = 0, length: Int) { self.name = name; self.start = start; self.length = length }
}
public struct Project: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID = UUID(); public static let currentSchemaVersion=15
    /// Portable, nonnegative revision IDs. Exhaustion requires a new project
    /// copy rather than wrapping an ID used by history, saving and playback.
    public static let maximumRevision=Int(Int32.max)
    public var schemaVersion = Project.currentSchemaVersion; public var revision = 0
    fileprivate var nextRevision:Int? {revision>=0 && revision<Self.maximumRevision ? revision+1:nil}
    public var name: String; public var bpm: Double = 120; public var keyRoot = 0; public var minor = false
    public var modified = Date(); public var tracks: [Track]; public var patterns: [Pattern]; public var sections: [Section]
    /// A generated song with a composed ending opens in one-shot playback,
    /// including on the first import on another device. Later loop choices are local.
    public var hasComposedEnding: Bool?
    public var arrangementRecipe: ArrangementRecipe?
    public var masterEQ:StudioEQ?
    public var masterFX:MasterFX?;public var performanceTakes:[PerformanceTake]?
    public var performanceTake:PerformanceTake?{get{performanceTakes?.first}set{performanceTakes=newValue.map{[$0]}}}
    public var audioAssets:[AudioAssetRecord]?
    public var midi:MIDISettings?
    /// I41: the last phrase edits applied to this project (newest last, at most 32).
    public var editLog:[String]?
    /// Legacy register for implicit root bass. To change it in an existing project,
    /// use MusicalEditing.setBassRegister: explicit rootBassPitch values are absolute
    /// and must be shifted atomically as well; raw field assignment does not do that.
    public var bassOctave = 0; public var bassGate = 0.9; public var master: Double = -3
    public var length: Int { sections.reduce(0) { total, section in let (sum, overflow) = total.addingReportingOverflow(section.length); return overflow ? Int.max : sum } }
    public var keyName: String { Chord.roots[keyRoot] + " " + NSLocalizedString(minor ? "minor":"major",comment:"Key mode") }
    public init(name: String = "Untitled", bars: Int = 4) {
        self.name = name; let length = bars * barTicks
        let harmony = Pattern(length: length); let drums = Pattern(length: length)
        patterns = [harmony, drums]; sections = [Section(name: "Verse", length: length)]
        var h = Track(role: .harmony); h.clips = [Clip(patternID: harmony.id, start: 0, length: length)]
        var d = Track(role: .drums); d.clips = [Clip(patternID: drums.id, start: 0, length: length)]
        tracks = [h,d]
    }
    public static func demo() -> Project {
        var p = Project(name: "First light")
        p.patterns[0].chords = [Chord(root: 0), Chord(root: 9, quality: .minor), Chord(root: 5), Chord(root: 7)].enumerated().map { ChordEvent(tick: $0.offset * barTicks, chord: $0.element) }
        for bar in 0..<4 {
            for tick in [0,1920] { p.patterns[1].drums.append(DrumEvent(tick: bar * barTicks + tick, pad: 0)) }
            for tick in [960,2880] { p.patterns[1].drums.append(DrumEvent(tick: bar * barTicks + tick, pad: 1)) }
            for tick in stride(from: 0, to: barTicks, by: 480) { p.patterns[1].drums.append(DrumEvent(tick: bar * barTicks + tick, pad: 2, velocity: 72)) }
        }
        p.tracks.append(Track(role: .bass)); return p
    }
    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else { throw MusicError.unsupportedSchema }
        guard (0...Self.maximumRevision).contains(revision),bpm.isFinite, (40...240).contains(bpm), (0..<12).contains(keyRoot), !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 120,
              (1...maximumSections).contains(sections.count), (barTicks...songTickLimit).contains(length), tracks.count >= 2, tracks.count <= 8,
              bassGate.isFinite, (0.1...1).contains(bassGate), (-1...1).contains(bassOctave), master.isFinite, (-61...6).contains(master),
              tracks[0].role == .harmony, tracks[1].role == .drums, tracks.dropFirst(2).allSatisfy({$0.role == .bass || $0.role == .melody}), tracks.filter({$0.role == .bass}).count <= 1,
              patterns.count <= 128, Set(patterns.map(\.id)).count == patterns.count, Set(sections.map(\.id)).count == sections.count,
              Set(tracks.map(\.id)).count == tracks.count else { throw MusicError.invalidProject }
        guard (performanceTakes ?? []).count<=1 else{throw MusicError.limit}
        if let log=editLog{guard log.count<=32,log.allSatisfy({$0.count<=300}) else{throw MusicError.invalidProject}}
        for track in tracks{try track.dynamics?.validate();try track.synth?.validate();if track.synth != nil,track.role == .drums{throw MusicError.invalidProject}}
        guard sections.allSatisfy({$0.color.map{(0...3).contains($0)} ?? true}),sections.allSatisfy({$0.filterSweep?.isValid ?? true}) else{throw MusicError.invalidProject}
        try midi?.validate(self)
        try masterEQ?.validate()
        try masterFX?.validate();try performanceTake?.validate()
        if let take=performanceTake{guard (take.source.audioAssets ?? []).allSatisfy({asset in (audioAssets ?? []).contains(asset)})else{throw MusicError.invalidProject}}
        guard (audioAssets ?? []).count<=8 else{throw MusicError.tooDense}
        for asset in audioAssets ?? []{try asset.validate()}
        let samples = referencedSamples
        guard samples.count <= 48 else { throw SampleError.limit }
        for asset in samples { try asset.validate() }
        let sampleBytes = samples.reduce(0) { $0 + $1.byteCount }
        guard sampleBytes <= 48_000_000,
              sampleBytes <= 116_000_000 - (audioAssets ?? []).reduce(0, { $0 + $1.byteCount }) else { throw SampleError.limit }
        for track in tracks {
            if let asset = track.instrumentSample, track.role == .drums || asset.kind != .instrument { throw MusicError.invalidProject }
            if let edits = track.padEdits {
                guard track.role == .drums, edits.count <= 16 else { throw SampleError.invalid }
                for (pad, edit) in edits { try edit.validate(rendered: track.padSamples?[pad]) }
            }
            if let pads = track.padSamples {
                guard track.role == .drums, pads.count <= 16,
                      pads.allSatisfy({ (0..<16).contains($0.key) && $0.value.kind == .oneShot }) else { throw MusicError.invalidProject }
            }
        }
        var ids=[id];if let take=performanceTake{ids.append(take.id)};ids += (audioAssets ?? []).map(\.id)
        ids += samples.map(\.id)
        ids += tracks.map(\.id);ids += patterns.map(\.id);ids += sections.map(\.id)
        ids += tracks.flatMap{$0.clips.map(\.id)}
        for p in patterns {ids += p.chords.map(\.id);ids += p.drums.map(\.id);ids += (p.notes ?? []).map(\.id)}
        guard Set(ids).count == ids.count else { throw MusicError.invalidProject }
        var end = 0
        for s in sections { guard s.start == end, s.length > 0, s.length <= songTickLimit, s.length % barTicks == 0, !s.name.isEmpty, s.name.count <= 120 else { throw MusicError.invalidProject }; end += s.length }
        for p in patterns {
            guard p.length >= barTicks, p.length % barTicks == 0, p.length <= length, p.chords.count <= 256, p.drums.count <= 4096, (p.notes ?? []).count <= 4096 else { throw MusicError.invalidProject }
            var end = 0
            for e in p.chords.sorted(by: {$0.tick < $1.tick}) {
                guard e.tick >= end, e.tick < p.length, e.duration > 0, e.duration <= p.length, e.tick + e.duration <= p.length else { throw MusicError.invalidProject }
                if let velocity=e.velocity, !(1...127).contains(velocity) { throw MusicError.invalidProject }
                do{try e.chord.validate()}catch{throw MusicError.invalidProject}
                end = e.tick + e.duration
            }
            for e in p.notes ?? [] {
                guard e.tick>=0,e.tick<p.length,e.duration>0,e.duration<=p.length,e.tick+e.duration<=p.length,(0...127).contains(e.pitch),(1...127).contains(e.velocity),e.confidence==nil || (e.confidence!.isFinite && (0...1).contains(e.confidence!))else{throw MusicError.invalidProject}
            }
            for e in p.drums { guard e.tick >= 0, e.tick < p.length, (0..<16).contains(e.pad), (1...127).contains(e.velocity) else { throw MusicError.invalidProject } }
        }
        for t in tracks {
            try t.equalizer?.validate()
            guard (t.name==nil || (!t.name!.isEmpty && t.name!.count<=40)), t.gain.isFinite, (-61...6).contains(t.gain), t.pan.isFinite, (-1...1).contains(t.pan), SoundPalette(rawValue:t.presetVersion) != nil else { throw MusicError.invalidProject }
            var end = 0
            for c in t.clips.sorted(by: {$0.start < $1.start}) {
                guard c.start >= end, c.start < length, c.length > 0, c.length <= length, c.start + c.length <= length, c.offset >= 0, let p = patterns.first(where: {$0.id == c.patternID}), c.offset < p.length else { throw MusicError.invalidProject }
                if let asset=c.sourceAssetID{guard (audioAssets ?? []).contains(where:{$0.id==asset})else{throw MusicError.invalidProject}}
                if let v=c.variants{guard (1...3).contains(v.count),Set(v).count==v.count,!v.contains(c.patternID),v.allSatisfy({id in patterns.contains{$0.id==id}})else{throw MusicError.invalidProject}}
                end = c.start + c.length
            }
        }
        var upperBound = 0
        for t in tracks { for clip in t.clips {
            if let p = patterns.first(where: {$0.id == clip.patternID}) {
                let chordVoices=p.chords.reduce(0){$0+$1.chord.notes.count}
                upperBound += ((clip.length + p.length - 1) / p.length + 1) * (chordVoices + p.drums.count + (p.notes ?? []).count)
            }
        }}
        guard upperBound <= 65536 else { throw MusicError.tooDense }
        guard Compiler.notes(self).count <= 32768 else { throw MusicError.tooDense }
        guard try JSONEncoder().encode(self).count<=8_000_000 else{throw MusicError.tooDense}
    }
    public mutating func duplicateSection(_ id:UUID,name:String)throws {
        try SectionEditing.duplicate(id,name:name,in:&self)
    }
    public mutating func addMelody(name:String?=nil)throws {
        guard tracks.count<8 else{throw MusicError.trackLimit}
        var t=Track(role:.melody);t.name=name ?? String(format:NSLocalizedString("Melody %d",comment:"New track"),tracks.filter{$0.role == .melody}.count+1)
        for section in sections {let p=Pattern(length:section.length);patterns.append(p);t.clips.append(Clip(patternID:p.id,start:section.start,length:section.length))}
        tracks.append(t)
    }
    public mutating func deleteTrack(_ id:UUID)throws {
        guard let i=tracks.firstIndex(where:{$0.id==id}),i>=2 else{throw MusicError.invalidProject}
        tracks.remove(at:i);removeUnusedPatterns()
        midi?.mappings.removeAll{$0.trackID==id};if midi?.trackID==id{midi?.trackID=nil}
    }
    public mutating func duplicateTrack(_ id:UUID)throws {
        guard tracks.count<8,let t=tracks.first(where:{$0.id==id}),t.role == .melody else{throw MusicError.trackLimit}
        var copy=t;copy.id=UUID();copy.name=String(t.displayName.prefix(34))+" copy";copy.clips=[]
        for clip in t.clips {guard var p=patterns.first(where:{$0.id==clip.patternID})else{throw MusicError.invalidProject};p.id=UUID();p.notes=(p.notes ?? []).map{var n=$0;n.id=UUID();return n};p.chords=p.chords.map{var n=$0;n.id=UUID();return n};p.drums=p.drums.map{var n=$0;n.id=UUID();return n};patterns.append(p);var c=clip;c.id=UUID();c.patternID=p.id;copy.clips.append(c)}
        tracks.append(copy)
    }
    public mutating func deleteSection(_ id:UUID)throws {
        try SectionEditing.delete(id,in:&self)
    }
    public mutating func moveSection(_ id:UUID,by delta:Int)throws {
        guard let index=sections.firstIndex(where:{$0.id==id}),
              delta != 0,delta >= -index,delta < sections.count-index else{return}
        let payload=ArrangementDragPayload(project:self,sectionID:id)
        try ClipEditing.reorderSection(payload,to:sections[index+delta].id,in:&self)
    }

}
public enum MusicError: Error, LocalizedError {
    case invalidChord, invalidProject, unsupportedSchema, limit, tooDense, trackLimit, assetLimit, revisionLimit
    public var errorDescription: String? {
        let key = switch self {
        case .invalidChord: "Unrecognized chord. Choose a chord from the list."
        case .unsupportedSchema: "This project was made with a newer version. The original has been preserved."
        case .limit: "A song can contain up to 8 sections and 64 bars."
        case .assetLimit: "A project can keep up to eight source recordings."
        case .revisionLimit: "This project has reached its revision limit. Save a copy to continue editing."
        case .trackLimit: "A project can contain up to eight tracks."
        case .tooDense: "This project has too many events."
        case .invalidProject: "The project contains invalid musical data."
        }
        return NSLocalizedString(key, comment: "Project validation")
    }
}
public enum Quantize: Int, CaseIterable, Sendable { case off = 0, eighth = 480, sixteenth = 240
    public func tick(_ tick: Int, length: Int) -> Int { rawValue == 0 ? max(0, min(length - 1, tick)) : ((max(0, tick) + rawValue / 2) / rawValue * rawValue) % length }
}
public struct History: Sendable {
    private var past: [Project] = []; private var future: [Project] = []
    /// One bounded value/COW certificate, obtained only by full validation.
    /// Never reduce this to a revision/ID pair: callers can mutate values directly.
    private var fullyValidatedProject:Project?
    public init() {}
    public var canUndo: Bool { !past.isEmpty }; public var canRedo: Bool { !future.isEmpty }
    public var retainedSamples: Set<SampleAsset> {
        Set((past + future).flatMap { $0.referencedSamples })
    }
    public mutating func apply(_ project: inout Project, coalescing: Bool = false, _ change: (inout Project) throws -> Void) throws {
        guard let revision=project.nextRevision else{throw MusicError.revisionLimit}
        var candidate = project; try change(&candidate); candidate.revision = revision; candidate.modified = Date(); try candidate.validate()
        commit(candidate,replacing:&project,coalescing:coalescing)
    }
    /// Fast only for certified music plus finite, bounded mix changes. The first
    /// edit of an unchecked/changed baseline performs the ordinary full validation.
    public mutating func applyMix(_ project:inout Project,coalescing:Bool=false,_ change:(inout Project)throws->Void)throws {
        guard let revision=project.nextRevision else{throw MusicError.revisionLimit}
        if fullyValidatedProject != project {
            try project.validate()
            fullyValidatedProject=project
        }
        var candidate=project
        try change(&candidate)
        candidate.revision=revision;candidate.modified=Date()
        try MixEditValidation.validateChange(from:project,to:candidate)
        commit(candidate,replacing:&project,coalescing:coalescing)
    }
    private mutating func commit(_ candidate:Project,replacing project:inout Project,coalescing:Bool) {
        if !coalescing || past.isEmpty { past.append(project) }
        if past.count>80{past.removeFirst()}
        future.removeAll();project=candidate;fullyValidatedProject=candidate
    }
    public mutating func undo(_ project: inout Project) { guard let revision=project.nextRevision,var p = past.last else { return };past.removeLast(); future.append(project); p.revision = revision; p.modified = Date(); project = p;fullyValidatedProject=nil }
    public mutating func redo(_ project: inout Project) { guard let revision=project.nextRevision,var p = future.last else { return };future.removeLast(); past.append(project); p.revision = revision; p.modified = Date(); project = p;fullyValidatedProject=nil }
}

public enum ProjectDocument {
    /// Read/migrate a value copy. The source bytes are preserved until an explicit save.
    public static func decode(_ data:Data)throws->Project {
        guard data.count<=8_000_000 else{throw MusicError.tooDense}
        guard let header=try JSONSerialization.jsonObject(with:data) as? [String:Any]else{throw MusicError.invalidProject}
        try checkSchemaHeaders(header)
        return try migrated(JSONDecoder().decode(Project.self,from:data))
    }
    private static func checkSchemaHeaders(_ value:[String:Any],depth:Int=0)throws {
        guard depth<2,let version=value["schemaVersion"] as? Int else{throw MusicError.invalidProject}
        guard (1...Project.currentSchemaVersion).contains(version)else{throw MusicError.unsupportedSchema}
        // Check a frozen source before decoding its newer chord vocabulary too.
        for take in value["performanceTakes"] as? [[String:Any]] ?? [] {
            if let source=take["source"] as? [String:Any]{try checkSchemaHeaders(source,depth:depth+1)}
        }
    }
    private static func migrated(_ value:Project)throws->Project {
        var p=value
        guard (1...Project.currentSchemaVersion).contains(p.schemaVersion)else{throw MusicError.unsupportedSchema}
        // Schemas through 10 only knew the two original renderer versions.
        // New palettes require 11 so an older app rejects the document safely.
        if p.schemaVersion<11,!p.tracks.allSatisfy({(1...2).contains($0.presetVersion)}){throw MusicError.invalidProject}
        if p.schemaVersion==1 {p.schemaVersion=2;for i in p.patterns.indices{if p.patterns[i].notes==nil{p.patterns[i].notes=[]}}}
        if p.schemaVersion==2{p.schemaVersion=3}
        if p.schemaVersion==3{p.schemaVersion=4}
        if p.schemaVersion==4{p.schemaVersion=5}
        if p.schemaVersion==5{p.schemaVersion=6}
        if p.schemaVersion==6{p.schemaVersion=7}
        if p.schemaVersion==7{p.schemaVersion=8}
        if p.schemaVersion==8{p.schemaVersion=9}
        if p.schemaVersion==9{p.schemaVersion=10}
        if p.schemaVersion==10{p.schemaVersion=11}
        if p.schemaVersion==11 {
            guard p.tracks.allSatisfy({ $0.instrumentSample == nil && $0.padSamples == nil }) else { throw MusicError.invalidProject }
            p.schemaVersion=12
        }
        if p.schemaVersion==12 {
            guard p.masterEQ==nil,p.tracks.allSatisfy({$0.equalizer==nil}) else {throw MusicError.invalidProject}
            p.schemaVersion=13
        }
        if p.schemaVersion==13 {
            guard p.arrangementRecipe == nil, p.hasComposedEnding == nil, p.patterns.allSatisfy({ pattern in
                pattern.chords.allSatisfy { $0.velocity == nil }
            }) else { throw MusicError.invalidProject }
            p.schemaVersion=14
        }
        if p.schemaVersion==14 {
            guard p.tracks.allSatisfy({ $0.padEdits == nil }) else { throw MusicError.invalidProject }
            p.schemaVersion=15
        }
        if var take=p.performanceTake{take.source=try migrated(take.source);p.performanceTake=take}
        try p.validate();return p
    }
}
