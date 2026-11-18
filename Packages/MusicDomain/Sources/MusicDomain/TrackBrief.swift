import Foundation

public enum TrackBriefError: Error, LocalizedError {
    case unknownIdea, tooManyChords, invalidTempo, invalidLength, invalidChord(String)
    public var errorDescription: String? {
        switch self {
        case .unknownIdea: NSLocalizedString("Try describing a rhythm or mood, or choose the settings below.", comment: "Track builder")
        case .tooManyChords: NSLocalizedString("Use at most one chord per bar.", comment: "Track builder")
        case .invalidTempo: NSLocalizedString("Enter a tempo from 40 to 240 BPM.", comment: "Track builder")
        case .invalidLength: NSLocalizedString("Choose a length of 4, 8 or 16 bars.", comment: "Track builder")
        case .invalidChord(let symbol): String(format:NSLocalizedString("Check the chord %@.",comment:"Track builder"), symbol)
        }
    }
}

public struct TrackBrief: Equatable, Sendable {
    public var style: SketchStyle = .house
    public var tempo = 120
    public var root = 0
    public var minor = false
    public var bars = 8
    public var chordText = ""
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

    public func makeProject(name:String) throws -> Project {
        guard (40...240).contains(tempo) else { throw TrackBriefError.invalidTempo }
        let tokens = try AssistantEngine.chordTokens(chordText)
        guard tokens.count <= bars else { throw TrackBriefError.tooManyChords }
        let chords = try tokens.map { symbol -> Chord in
            do { return try Chord.parse(symbol) }
            catch { throw TrackBriefError.invalidChord(symbol) }
        }
        let plan = SketchPlan(style:style,bpm:Double(tempo),root:root,minor:minor,bars:bars,seed:seed)
        try plan.validate()
        let project = try ProjectTemplates.make(name:name,bpm:plan.bpm,root:root,minor:minor,bars:bars,template:.empty)
        return try SketchComposer.compose(project,plan:plan,scope:project.sections[0].id,chordCycle:chords)
    }

    /// A local starting point for common RU/EN descriptions on phones without an available model.
    public func suggesting(_ prompt:String) throws -> Self {
        let text = prompt.lowercased()
        var result = self, matched = false
        func group(_ expression:String, in input:String) -> String? {
            guard let regex = try? NSRegularExpression(pattern:expression,options:.caseInsensitive),
                  let match = regex.firstMatch(in:input,range:NSRange(input.startIndex...,in:input)),
                  let range = Range(match.range(at:1),in:input) else { return nil }
            return String(input[range])
        }
        let rhythms: [(SketchStyle,[String])] = [(.hipHop,["hip-hop","hip hop","хип-хоп","хип хоп","хипхоп","lo-fi","lofi","лофай","лоу-фай","boom bap","бум-бэп"]),(.jazz,["jazz","джаз","swing","свинг"]),(.house,["house","хаус","four on the floor","прямая бочка"])]
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
        if let token = group(#"(\d+)\s*(?:bars?\b|такт)"#,in:text) {
            guard let value=Int(token),[4,8,16].contains(value) else { throw TrackBriefError.invalidLength }
            result.bars=value; matched=true
        }
        let keyPattern = #"(?:^|[\s,;:])([a-g](?:[#♯b♭])?|до|ре|ми|фа|соль|ля|си)[\s-]*(?:minor|major|минор|мажор)\b"#
        if let note=group(keyPattern,in:text) {
            let aliases=["до":"C","ре":"D","ми":"E","фа":"F","соль":"G","ля":"A","си":"B"]
            result.root=try Chord.parse(aliases[note] ?? note).root
            result.chordText=""; matched=true
        }
        if let mode=group(#"\b(minor|major|минор|мажор)\b"#,in:text) {
            result.minor=["minor","минор"].contains(mode);result.chordText="";matched=true
        }
        if let progression=group(#"(?:аккорды|chords)\s*[:=]\s*([^;\n.!?]+)"#,in:prompt) {
            let symbols=try AssistantEngine.chordTokens(progression)
            for symbol in symbols where (try? Chord.parse(symbol)) == nil { throw TrackBriefError.invalidChord(symbol) }
            guard symbols.count<=result.bars else { throw TrackBriefError.tooManyChords }
            result.chordText=progression;matched=true
        }
        guard matched else { throw TrackBriefError.unknownIdea }
        return result
    }
}
