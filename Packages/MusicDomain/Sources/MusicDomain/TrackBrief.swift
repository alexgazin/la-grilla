import Foundation

public enum TrackBriefError: Error, LocalizedError {
    case unknownIdea, tooManyChords, invalidTempo, invalidLength, invalidChord(String), invalidIntro
    public var errorDescription: String? {
        switch self {
        case .unknownIdea: NSLocalizedString("Try describing a rhythm or mood, or choose the settings below.", comment: "Track builder")
        case .tooManyChords: NSLocalizedString("Use at most one chord per bar.", comment: "Track builder")
        case .invalidTempo: NSLocalizedString("Enter a tempo from 40 to 240 BPM.", comment: "Track builder")
        case .invalidIntro: NSLocalizedString("The intro must end before the last bar finishes.", comment: "Track builder")
        case .invalidLength: NSLocalizedString("Choose a length of 4, 8 or 16 bars.", comment: "Track builder")
        case .invalidChord(let symbol): String(format:NSLocalizedString("Check the chord %@.",comment:"Track builder"), symbol)
        }
    }
}

public enum HipHopFeel: String, Codable, CaseIterable, Sendable {
    case boomBap = "Boom bap"
    case westCoast = "West Coast"
}

public struct TrackBrief: Codable, Equatable, Sendable {
    public var style: SketchStyle = .house
    public var tempo = 120
    public var root = 0
    public var minor = false
    public var songForm: SongFormBrief?
    public var bars = 8
    public var chordText = ""
    public var hipHopFeel: HipHopFeel = .boomBap
    public var introBars = 0
    public var endBreak = false
    public var laidBackKeys = false
    // Convert a small, audible performance delay to score ticks at the final tempo.
    var keysOffset: Int { laidBackKeys ? Int((0.024 * Double(tempo * ppq) / 60).rounded()) : 0 }
    public var drumVariation: UInt32 = 0
    public var bassVariation: UInt32 = 0
    public var seed: UInt32 = 1
    public init() {}

    public mutating func usePreset(_ style: SketchStyle) {
        self.style = style
        switch style {
        case .house: tempo = 124; root = 9; minor = true
        case .hipHop: tempo = 84; root = 2; minor = true
        case .jazz: tempo = 106; root = 0; minor = false
        }
        chordText = suggestedChords
    }

    public var suggestedChords: String {
        let offsets = style == .jazz ? (minor ? [2,7,0,0] : [2,7,0,9])
                                     : (minor ? [0,8,5,7] : [0,9,5,7])
        let suffixes = style == .jazz ? (minor ? ["m7b5","7","m7","m7"] : ["m7","7","maj7","m7"])
                                      : (minor ? ["m","","m","7"] : ["","m","",""])
        return zip(offsets,suffixes).map { Chord.roots[(root+$0.0)%12]+$0.1 }.joined(separator:" ")
    }

    public func makeProject(name:String, sourcePrompt: String = "") throws -> Project {
        guard (40...240).contains(tempo) else { throw TrackBriefError.invalidTempo }
        if let songForm {
            guard (0..<12).contains(root) else { throw SketchError.invalidPlan }
            let recipe = try ArrangementRecipe(brief: self, prompt: sourcePrompt)
            var project = songForm.arrangement == .groove
                ? try GrooveArrangement.make(form: songForm, brief: self, name: name)
                : try ExpressiveArrangement.make(form: songForm, brief: self, name: name)
            project.arrangementRecipe = recipe
            return project
        }
        let tokens = try AssistantEngine.chordTokens(chordText)
        guard tokens.count <= bars else { throw TrackBriefError.tooManyChords }
        let chords = try tokens.map { symbol -> Chord in
            do { return try Chord.parse(symbol) }
            catch { throw TrackBriefError.invalidChord(symbol) }
        }
        let plan = SketchPlan(style:style,bpm:Double(tempo),root:root,minor:minor,bars:bars,seed:seed)
        try plan.validate()
        let project = try ProjectTemplates.make(name:name,bpm:plan.bpm,root:root,minor:minor,bars:bars,template:.empty)
        let progression = SketchComposer.chordSequence(plan, cycle: chords, register: project.bassOctave)
        return try GrooveArrangement.make(from: project, chords: progression, brief: self)
    }

    private static let introPattern = #"\b(?:первые|first|intro(?:\s+of)?|интро)\s*[:—-]?\s*(\d+|один|два|две|четыре|восемь|one|two|four|eight)\b(?:[-\s]+(?:bars?\b|такт[а-я]*))?"#

    /// Local form instructions override model guesses and work without Foundation Models.
    public func applyingForm(_ prompt: String) throws -> Self {
        try formSettings(prompt).brief
    }

    private func formSettings(_ prompt: String) throws -> (brief: Self, matched: Bool) {
        var result = self
        var matched = false
        let text = prompt.lowercased()
        if ["west coast","west-coast","g-funk","g funk","вест кост","вест-кост","джи-фанк"].contains(where:text.contains) {
            result.style = .hipHop
            result.hipHopFeel = .westCoast
            matched = true
        } else if ["boom bap","boom-bap","бум-бэп","бум бэп"].contains(where:text.contains) {
            result.style = .hipHop
            result.hipHopFeel = .boomBap
            matched = true
        }
        if ["замени только ударные","измени только ударные","замени только барабаны","vary only the drums","change only the drums","new drum variation"].contains(where:text.contains) {
            result.drumVariation &+= 1
            matched = true
        }
        if ["замени только бас","измени только бас","vary only the bass","change only the bass","new bass variation"].contains(where:text.contains) {
            result.bassVariation &+= 1
            matched = true
        }
        if SongFormBrief.straightKeysRequested(in: text) {
            result.laidBackKeys = false
            matched = true
        } else if text.range(of: #"(?:опаздывающ[а-я]*|запаздывающ[а-я]*)\s+(?:пианино|клавиши)|(?:laid[ -]back|late)\s+(?:piano|keys)|(?:piano|keys)\s+behind the beat"#, options: .regularExpression) != nil {
            result.laidBackKeys = true
            matched = true
        }
        let regex = try NSRegularExpression(pattern: Self.introPattern)
        if let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text) {
            let words = ["один":1,"one":1,"два":2,"две":2,"two":2,"четыре":4,"four":4,"восемь":8,"eight":8]
            let token = String(text[range])
            if text.contains("интро") || text.contains("intro") ||
                ((text.contains("бас") || text.contains("bass")) && ["барабан","ударн","бит","drum","beat"].contains(where:text.contains)) {
                guard let count = Int(token) ?? words[token], count >= 0, count < bars else { throw TrackBriefError.invalidIntro }
                result.introBars = count
                matched = true
            }
        }
        if ["без вступления","без интро","no intro"].contains(where:text.contains) { result.introBars = 0; matched = true }
        if ["полтакта","половину такта","half a bar","half-bar","half bar"].contains(where:text.contains),
           ["тишин","пауза","паузу","break","silence","rest","silent"].contains(where:text.contains) {
            result.endBreak = true
            matched = true
        }
        if ["без паузы","no break","no rest"].contains(where:text.contains) { result.endBreak = false; matched = true }
        return (result, matched)
    }

    /// Only route requests for new music here. Project edits keep their normal review and Undo.
    public static func offlineCreationRequest(_ prompt: String) throws -> Self? {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if SongFormBrief.recognizes(prompt) { return try Self().suggesting(prompt) }
        guard text.count <= 2000,
              text.range(of: #"^(?:create|make|generate|compose|создай|сделай|сгенерируй|сочини)\s+"#, options: .regularExpression) != nil,
              text.range(of: #"^\S+\s+(?:(?:a|an|the|new|новый|новую)\s+)*(?:song form|section|chorus|verse|bridge|intro|track named|форму|секци[яию]|припев|куплет|бридж|вступление)\b"#, options: .regularExpression) == nil,
              text.range(of: #"\b(?:beat|groove|song|track|instrumental|hip[ -]?hop|jazz|house|boom[ -]bap|бит|грув|трек|инструментал|хип[ -]?хоп|джаз|хаус|бум[ -]бэп)\b"#, options: .regularExpression) != nil
        else { return nil }
        do { return try Self().suggesting(prompt) }
        catch TrackBriefError.unknownIdea { return nil }
    }

    /// A local starting point for common RU/EN descriptions on phones without an available model.
    public func suggesting(_ prompt:String) throws -> Self {
        let text = prompt.lowercased()
        if SongFormBrief.recognizes(prompt) { return try SongFormBrief.parse(prompt, base: self) }
        var result = self, matched = false
        result.songForm = nil
        func group(_ expression:String, in input:String) -> String? {
            guard let regex = try? NSRegularExpression(pattern:expression,options:.caseInsensitive),
                  let match = regex.firstMatch(in:input,range:NSRange(input.startIndex...,in:input)),
                  let range = Range(match.range(at:1),in:input) else { return nil }
            return String(input[range])
        }
        let rhythms: [(SketchStyle,[String])] = [(.hipHop,["chillhop","chill-hop","чиллхоп","чилл-хоп","hip-hop","hip hop","хип-хоп","хип хоп","хипхоп","lo-fi","lofi","лофай","лоу-фай","boom bap","boom-bap","бум-бэп","west coast","west-coast","g-funk","вест-кост","джи-фанк"]),(.jazz,["jazz","джаз","swing","свинг"]),(.house,["house","хаус","four on the floor","прямая бочка"])]
        if let style = rhythms.first(where:{ $0.1.contains(where:text.contains) })?.0 { result.usePreset(style); matched = true }
        let moods: [(words:[String],tempo:Int,minor:Bool)] = [
            (["ночн","night","тёмн","темн","dark","мрачн"],96,true),
            (["спокойн","мягк","chill","calm","relaxed","dreamy","мечтат"],82,true),
            (["бодр","энергич","энергичн","energetic","upbeat","bright","светл"],128,false)]
        if let mood = moods.first(where: { $0.words.contains(where:text.contains) }) {
            result.minor = mood.minor; result.tempo = mood.tempo; result.chordText = ""; matched = true
        }
        if let token = group(#"(\d+)\s*(?:bpm|бпм|ударов|уд/мин)"#,in:text) ?? group(#"(?:темп|tempo|bpm|бпм)\s*[:=]?\s*(\d+)"#,in:text) {
            guard let value=Int(token),(40...240).contains(value) else { throw TrackBriefError.invalidTempo }
            result.tempo=value; matched=true
        }
        let lengthText = text.replacingOccurrences(of: Self.introPattern, with: "", options: .regularExpression)
        if let token = group(#"(\d+)[\s-]*(?:bars?\b|такт)"#,in:lengthText) {
            guard let value=Int(token),[4,8,16].contains(value) else { throw TrackBriefError.invalidLength }
            result.bars=value; matched=true
        }
        let keyPattern = #"(?:^|[\s,;:])([a-g](?:[#♯b♭])?|до|ре|ми|фа|соль|ля|си)[\s-]*(?:(?:natural|натуральный)\s+)?(?:minor|major|минор|мажор)\b"#
        if let note=group(keyPattern,in:text) {
            let aliases=["до":"C","ре":"D","ми":"E","фа":"F","соль":"G","ля":"A","си":"B"]
            result.root=try Chord.parse(aliases[note] ?? note).root
            result.chordText=""; matched=true
        }
        if let mode=group(#"\b(minor|major|минор|мажор)\b"#,in:text) {
            result.minor=["minor","минор"].contains(mode);result.chordText="";matched=true
        }
        if result.style == .hipHop && ["jazz","jazzy","джаз"].contains(where: text.contains) {
            // Use a jazz turnaround in the requested key over the hip-hop beat.
            var harmony = result
            harmony.style = .jazz
            result.chordText = harmony.suggestedChords
        }
        if let progression=group(#"(?:аккорды|chords)\s*[:=]\s*([^;\n.!?]+)"#,in:prompt) {
            let symbols=try AssistantEngine.chordTokens(progression)
            for symbol in symbols where (try? Chord.parse(symbol)) == nil { throw TrackBriefError.invalidChord(symbol) }
            guard symbols.count<=result.bars else { throw TrackBriefError.tooManyChords }
            result.chordText=progression;matched=true
        }
        if result.introBars >= result.bars { result.introBars = 0 }
        let arranged = try result.formSettings(prompt)
        guard matched || arranged.matched else { throw TrackBriefError.unknownIdea }
        return arranged.brief
    }
}

/// Editable musical starting points for the existing three rhythm engines.
public struct GroovePreset: Identifiable, Sendable {
    public let name:String
    public let recipe:TrackBrief
    public var id:String { name }
    private init(_ name:String,_ style:SketchStyle,_ bpm:Int,_ root:Int,_ minor:Bool,_ length:Int,_ seed:UInt32,_ chords:String) {
        self.name=name
        var brief=TrackBrief()
        brief.style=style; brief.tempo=bpm; brief.root=root; brief.minor=minor
        brief.bars=length; brief.seed=seed; brief.chordText=chords
        recipe=brief
    }
    public static let library:[GroovePreset]=[
        .init("Classic house",.house,124,9,true,8,1,"Am F Dm E7"),
        .init("Deep afterhours",.house,116,2,true,16,17,"Dm9 Gm7 Bbmaj7 A7"),
        .init("Sunrise piano",.house,122,5,false,8,63,"Fmaj7 Am7 Bb C"),
        .init("Warehouse drive",.house,132,5,true,8,104,"Fm Db Eb Cm"),
        .init("Disco lift",.house,120,4,true,4,38,"Em7 A7 Dmaj7 B7"),
        .init("Coastal chords",.house,112,7,false,16,29,"Gmaj7 Em7 Am7 D9"),
        .init("Classic hip-hop",.hipHop,84,2,true,8,1,"Dm Bb Gm A7"),
        .init("Dusty boom bap",.hipHop,92,5,true,8,73,"Fm7 Bbm7 Dbmaj7 C7"),
        .init("Rain on tape",.hipHop,72,9,true,8,91,"Am9 Dm7 G7 Cmaj7"),
        .init("Half-time pulse",.hipHop,70,3,true,4,55,"Ebm B Gb Db"),
        .init("Soul loop",.hipHop,88,10,false,8,8,"Bbmaj7 Gm7 Cm7 F7"),
        .init("Late train",.hipHop,97,11,true,16,84,"Bm7 Em9 Gmaj7 F#7"),
        .init("Classic swing",.jazz,106,0,false,8,1,"Dm7 G7 Cmaj7 Am7"),
        .init("Blue hour",.jazz,78,2,true,8,62,"Em7b5 A7 Dm9 Dm7"),
        .init("Bebop turnaround",.jazz,166,5,false,8,31,"Fmaj7 D7 Gm7 C7"),
        .init("Midnight quartet",.jazz,98,7,true,8,45,"Gm9 Cm7 Am7b5 D7"),
        .init("Modal walk",.jazz,118,2,true,16,99,"Dm7 Dm9 Ebm7 Dm7"),
        .init("Sunday trio",.jazz,134,3,false,16,27,"Ebmaj7 Cm7 Fm7 Bb9")
    ]
}
