import Foundation

public enum ChordDistribution:String,CaseIterable,Sendable {case stretch,repeatBars}
public enum AssistantError:Error,LocalizedError {
    case unsupported,ambiguous,mismatch,unsafe,stale
    public var errorDescription:String? {
        let key=switch self {
        case .unsupported:"Use a supported command: Tempo 110; Key D minor; Chorus 8 bars: Am F C G each 2 bars."
        case .ambiguous:"Choose how the chords fill the section before continuing."
        case .mismatch:"The chord durations do not fill the section. Adjust the bars or durations."
        case .unsafe:"This proposal contains unsupported or invalid operations."
        case .stale:"The project changed. Generate a fresh proposal before applying."
        }
        return NSLocalizedString(key,comment:"Assistant")
    }
}
public struct AssistantOperation:Codable,Equatable,Sendable {
    public enum Kind:String,Codable,Sendable {case setTempo,setKey,renameSection,resizeSection,setProgression,arrangeSong,styleHarmony,styleSong,generateSketch}
    public var type:Kind
    public var sectionID:UUID?;public var bpm:Double?;public var root:Int?;public var minor:Bool?;public var name:String?;public var bars:Int?;public var chords:[Chord]?;public var durations:[Int]?
    public var sections:[AssistantSongSection]?;public var style:String?
    public var sketch:SketchPlan?
    public init(_ type:Kind,sectionID:UUID?=nil,bpm:Double?=nil,root:Int?=nil,minor:Bool?=nil,name:String?=nil,bars:Int?=nil,chords:[Chord]?=nil,durations:[Int]?=nil,sections:[AssistantSongSection]?=nil,style:String?=nil,sketch:SketchPlan?=nil){self.type=type;self.sectionID=sectionID;self.bpm=bpm;self.root=root;self.minor=minor;self.name=name;self.bars=bars;self.chords=chords;self.durations=durations;self.sections=sections;self.style=style;self.sketch=sketch}
    private var parameters:Set<String>{var p=Set<String>();if sectionID != nil{p.insert("sectionID")};if bpm != nil{p.insert("bpm")};if root != nil{p.insert("root")};if minor != nil{p.insert("minor")};if name != nil{p.insert("name")};if bars != nil{p.insert("bars")};if chords != nil{p.insert("chords")};if durations != nil{p.insert("durations")};if sections != nil{p.insert("sections")};if style != nil{p.insert("style")};if sketch != nil{p.insert("sketch")};return p}
    func apply(to project:inout Project,scope:UUID)throws {
        let allowed:Set<String>=switch type{case .setTempo:["bpm"];case .setKey:["root","minor"];case .renameSection:["sectionID","name"];case .resizeSection:["sectionID","bars"];case .setProgression:["sectionID","chords","durations"];case .arrangeSong:["sections"];case .styleHarmony:["sectionID","style"];case .styleSong:["style"];case .generateSketch:["sketch"]}
        guard parameters==allowed else{throw AssistantError.unsafe}
        if let sectionID{guard sectionID==scope,project.sections.contains(where:{$0.id==sectionID})else{throw AssistantError.unsafe}}
        switch type {
        case .setTempo:project.bpm=bpm!
        case .setKey:project.keyRoot=root!;project.minor=minor!
        case .renameSection:let i=project.sections.firstIndex{$0.id==sectionID}!;project.sections[i].name=name!
        case .resizeSection:project=try Arrangement.resized(project,sectionID:sectionID!,bars:bars!)
        case .setProgression:
            guard let section=project.sections.first(where:{$0.id==sectionID}),let chords,let durations,!chords.isEmpty,chords.count<=256,chords.count==durations.count,durations.allSatisfy({(1...64).contains($0)})else{throw AssistantError.unsafe}
            guard durations.reduce(0,+)*barTicks==section.length else{throw AssistantError.mismatch}
            let sourceHarmony=Arrangement.harmony(project,section:section)
            var tick=0;var events:[ChordEvent]=[]
            for (c,duration) in zip(chords,durations){
                let retained=Arrangement.chordPreservingSource(c,at:tick,from:sourceHarmony)
                events.append(ChordEvent(tick:tick,duration:duration*barTicks,chord:retained));tick+=duration*barTicks
            }
            try Arrangement.replaceHarmony(events,in:section,project:&project)
        case .arrangeSong:project=try Arrangement.composing(project,parts:sections!,scope:scope)
        case .generateSketch:project=try SketchComposer.compose(project,plan:sketch!,scope:scope)
        case .styleHarmony,.styleSong:
            guard let style=HarmonyStyle(rawValue:style!)else{throw AssistantError.unsafe}
            let targets=type == .styleSong ? project.sections.filter{!Arrangement.harmony(project,section:$0).isEmpty}.map(\.id):[sectionID!]
            guard !targets.isEmpty else{throw HarmonyError.empty}
            for id in targets {let proposal=try HarmonyLab.propose(project,sectionID:id,options:HarmonyOptions(style:style));project=proposal.candidate}
        }
    }
}
public struct AssistantProposal:Codable,Identifiable,Sendable {
    public var id=UUID();public var schemaVersion=1
    public var projectID:UUID;public var baseRevision:Int;public var scopeSectionID:UUID
    public var operations:[AssistantOperation];public var assumptions:[String];public var warnings:[String]
    public var changesWholeSong:Bool{operations.contains{[AssistantOperation.Kind.arrangeSong,.styleSong,.generateSketch].contains($0.type)}}
    public init(project:Project,scope:UUID,operations:[AssistantOperation],assumptions:[String]=[],warnings:[String]=[]){projectID=project.id;baseRevision=project.revision;scopeSectionID=scope;self.operations=operations;self.assumptions=assumptions;self.warnings=warnings;if operations.contains(where:{$0.type == .generateSketch}){schemaVersion=3}else if operations.contains(where:{[AssistantOperation.Kind.arrangeSong,.styleHarmony,.styleSong].contains($0.type)}){schemaVersion=2}}
    public func candidate(for project:Project)throws->Project {
        guard project.id==projectID,project.revision==baseRevision else{throw AssistantError.stale}
        guard (1...3).contains(schemaVersion),(1...16).contains(operations.count),project.sections.contains(where:{$0.id==scopeSectionID}),assumptions.count<=16,warnings.count<=16,(assumptions+warnings).allSatisfy({$0.count<=500})else{throw AssistantError.unsafe}
        if schemaVersion<3,operations.contains(where:{$0.type == .generateSketch}){throw AssistantError.unsafe}
        if operations.contains(where:{$0.type == .generateSketch}),operations.count != 1{throw AssistantError.unsafe}
        if schemaVersion==1,operations.contains(where:{[AssistantOperation.Kind.arrangeSong,.styleHarmony,.styleSong].contains($0.type)}){throw AssistantError.unsafe}
        var result=project
        for op in operations{try op.apply(to:&result,scope:scopeSectionID);try result.validate()}
        try result.validate();return result
    }
    public func apply(to project:inout Project)throws{project=try candidate(for:project)}
    public static func decode(_ data:Data,for project:Project)throws->AssistantProposal {
        guard data.count<=64_000,let json=try JSONSerialization.jsonObject(with:data) as? [String:Any],Set(json.keys)==Set(["id","schemaVersion","projectID","baseRevision","scopeSectionID","operations","assumptions","warnings"]),let ops=json["operations"] as? [[String:Any]],ops.count<=16 else{throw AssistantError.unsafe}
        let keys:Set<String>=["type","sectionID","bpm","root","minor","name","bars","chords","durations","sections","style","sketch"]
        guard ops.allSatisfy({Set($0.keys).isSubset(of:keys)})else{throw AssistantError.unsafe}
        func safeChords(_ chords:[[String:Any]])->Bool{chords.count<=256 && chords.allSatisfy({Set($0.keys).isSubset(of:["root","quality","inversion","slashBass","voicedNotes","customIntervals","rootBassPitch","rootSpelling","slashBassSpelling"]) && Set(["root","quality","inversion"]).isSubset(of:Set($0.keys))})}
        for op in ops{
            if let sketch=op["sketch"]{guard let plan=sketch as? [String:Any],Set(plan.keys)==Set(["version","style","bpm","root","minor","bars","seed"])else{throw AssistantError.unsafe}}
            if let chords=op["chords"] as? [[String:Any]]{guard safeChords(chords)else{throw AssistantError.unsafe}}
            if let sections=op["sections"] as? [[String:Any]]{guard (1...8).contains(sections.count),sections.allSatisfy({Set($0.keys)==Set(["name","bars","chords","durations","sourceSectionID"]) && (($0["chords"] as? [[String:Any]]).map(safeChords) ?? false)})else{throw AssistantError.unsafe}}
        }
        let proposal=try JSONDecoder().decode(Self.self,from:data);_ = try proposal.candidate(for:project);return proposal
    }
}

public enum AssistantEngine {
    static func chordTokens(_ value:String)throws->[String] {
        var tokens:[String]=[],token="",groups:[Character]=[]
        for char in value {
            if char=="{" || char=="("{guard groups.count<2 else{throw AssistantError.unsupported};groups.append(char)}
            else if char=="}" || char==")"{guard groups.last==(char=="}" ? "{":"(")else{throw AssistantError.unsupported};groups.removeLast()}
            if groups.isEmpty && (char.isWhitespace || char==",") {if !token.isEmpty{tokens.append(token);token=""}}else{token.append(char)}
        }
        guard groups.isEmpty else{throw AssistantError.unsupported}
        if !token.isEmpty{tokens.append(token)}
        return tokens
    }
    private static func captures(_ pattern:String,_ value:String)->[String]? {
        guard let regex=try? NSRegularExpression(pattern:pattern,options:.caseInsensitive),let m=regex.firstMatch(in:value,range:NSRange(value.startIndex...,in:value)),m.range.length==(value as NSString).length else{return nil}
        return (1..<m.numberOfRanges).map{i in guard let range=Range(m.range(at:i),in:value)else{return ""};return String(value[range])}
    }
    private static func trim(_ value:String)->String{value.trimmingCharacters(in:.whitespacesAndNewlines)}
    private static func song(_ text:String,project:Project,selected:Section,distribution:ChordDistribution?)throws->AssistantProposal {
        let commands=text.split(separator:";",omittingEmptySubsequences:true).map{trim(String($0))}
        guard (1...10).contains(commands.count)else{throw AssistantError.unsupported}
        var operations:[AssistantOperation]=[],parts:[AssistantSongSection]=[],assumptions:[String]=[]
        for command in commands {
            if captures("^(?:темп|tempo|bpm)\\s+.+$",command) != nil || captures("^(?:тональность|key)\\s+.+$",command) != nil {
                let global=try propose(command,project:project,sectionID:selected.id)
                guard global.operations.allSatisfy({$0.type == .setTempo || $0.type == .setKey})else{throw AssistantError.unsupported}
                operations+=global.operations;continue
            }
            guard let match=captures("^([^:;]{1,120}?)\\s+([0-9]{1,2})\\s*(?:тактов|такта|такт|bars?)\\s*:?\\s*(.+)$",command),let bars=Int(match[1]),(1...64).contains(bars)else{throw AssistantError.unsupported}
            let name=trim(match[0]);var body=trim(match[2]),each:Int?
            if let m=captures("^(.+?)\\s+(?:по|each)\\s+(одному|один|два|две|четыре|one|two|four|[0-9]{1,2})\\s*(?:тактов|такта|такту|такт|bars?)$",body){let words=["одному":1,"один":1,"два":2,"две":2,"четыре":4,"one":1,"two":2,"four":4];each=Int(m[1]) ?? words[m[1].lowercased()];body=m[0]}
            let tokens=try chordTokens(body)
            guard (1...64).contains(tokens.count)else{throw AssistantError.unsupported}
            let aliases=["ам":"Am","до":"C","фа":"F","соль":"G","ля-минор":"Am","ре-минор":"Dm","ми-минор":"Em"]
            var chords:[Chord]
            do{chords=try tokens.map{try Chord.parse(aliases[$0.lowercased()] ?? $0)}}catch{throw AssistantError.unsupported}
            var durations:[Int]
            if let each{guard each>0,each*chords.count==bars else{throw AssistantError.mismatch};durations=Array(repeating:each,count:chords.count)}
            else if chords.count==bars{durations=Array(repeating:1,count:chords.count)}
            else{
                guard bars%chords.count==0,bars>=chords.count else{throw AssistantError.mismatch}
                guard let distribution else{throw AssistantError.ambiguous}
                switch distribution{case .stretch:durations=Array(repeating:bars/chords.count,count:chords.count);case .repeatBars:chords=(0..<bars).map{chords[$0%chords.count]};durations=Array(repeating:1,count:bars)}
                assumptions.append(NSLocalizedString("The displayed chord distribution is applied to each generated section.",comment:"Assistant"))
            }
            let translated=["интро":"intro","куплет":"verse","припев":"chorus","бридж":"bridge","аутро":"outro"]
            let sourceName=translated[name.lowercased()] ?? name.lowercased()
            let source=project.sections.first{(translated[$0.name.lowercased()] ?? $0.name.lowercased())==sourceName} ?? selected
            let part=AssistantSongSection(name:name,bars:bars,chords:chords,durations:durations,sourceSectionID:source.id)
            try part.validate(in:project);parts.append(part)
        }
        guard !parts.isEmpty,parts.count<=maximumSections,parts.reduce(0,{$0+$1.bars})<=maximumSongBars else{throw MusicError.limit}
        operations.append(.init(.arrangeSong,sections:parts))
        let warning=NSLocalizedString("This proposal replaces the song form. Existing rhythm and melody repeat or trim from the displayed source sections. Original recordings and the previous version remain available through Undo.",comment:"Assistant review")
        let proposal=AssistantProposal(project:project,scope:selected.id,operations:operations,assumptions:assumptions,warnings:[warning])
        _ = try proposal.candidate(for:project);return proposal
    }
    public static func propose(_ text:String,project:Project,sectionID:UUID,distribution:ChordDistribution?=nil)throws->AssistantProposal {
        try project.validate();guard text.count<=2000,let selected=project.sections.first(where:{$0.id==sectionID})else{throw AssistantError.unsafe}
        if SketchCommandParser.recognizes(text){return try SketchCommandParser.propose(text,project:project,scope:sectionID)}
        if let match=captures("^(?:song|песня|структура|форма)\\s*:\\s*(.+)$",text){return try song(match[0],project:project,selected:selected,distribution:distribution)}
        var operations:[AssistantOperation]=[];var assumptions:[String]=[];var warnings:[String]=[];var scope=selected.id;var sectionBars=Dictionary(uniqueKeysWithValues:project.sections.map{($0.id,$0.length/barTicks)})
        let commands=text.split(separator:";",omittingEmptySubsequences:true).map{trim(String($0))}
        guard (1...8).contains(commands.count)else{throw AssistantError.unsupported}
        for command in commands {
            let intent=command.lowercased().trimmingCharacters(in:.whitespacesAndNewlines)
            let jazz=["поджазовать","поджазуй","поджазить","сделай джазовее","усложни гармонию","jazz it up","make it jazzy","make jazzy","jazzify"]
            if jazz.contains(intent){operations.append(.init(.styleHarmony,sectionID:scope,style:HarmonyStyle.expressive.rawValue));continue}
            if jazz.contains(where:{intent==$0+" весь трек" || intent==$0+" whole song"}){operations.append(.init(.styleSong,style:HarmonyStyle.expressive.rawValue));warnings.append(NSLocalizedString("Harmony in every section will change. Rhythm and melody stay as written.",comment:"Assistant review"));continue}
            if let m=captures("^(?:темп|tempo|bpm)\\s*([0-9]{2,3}(?:[.,][0-9]+)?)\\s*(?:bpm)?$",command){guard let bpm=Double(m[0].replacingOccurrences(of:",",with:".")),(40...240).contains(bpm)else{throw MusicError.invalidProject};operations.append(.init(.setTempo,bpm:bpm));continue}
            if let m=captures("^(?:тональность|key)\\s+(.+)$",command){
                var key=trim(m[0]);let lower=key.lowercased();let minor=lower.hasSuffix("minor") || lower.hasSuffix("минор")
                for suffix in ["minor","major","минор","мажор"]{if key.lowercased().hasSuffix(suffix){key=trim(String(key.dropLast(suffix.count)))}}
                let names=["до":"C","ре":"D","ми":"E","фа":"F","соль":"G","ля":"A","си":"B"]
                key=names[key.lowercased()] ?? key
                let chord=try Chord.parse(key);guard [.major,.minor].contains(chord.quality),chord.slashBass==nil,chord.customIntervals==nil else{throw AssistantError.unsupported}
                operations.append(.init(.setKey,root:chord.root,minor:minor || chord.quality == .minor));continue
            }
            if let m=captures("^(?:назови секцию|rename section)\\s+(.+)$",command){operations.append(.init(.renameSection,sectionID:scope,name:trim(m[0])));continue}
            var body=command
            let aliases:[(pattern:String,name:String,aliases:[String])]=[
                ("(?:куплет(?:е)?|verse)","Verse",["verse","куплет"]),("(?:припев(?:е)?|chorus)","Chorus",["chorus","припев"]),("(?:бридж(?:е)?|bridge)","Bridge",["bridge","бридж"])]
            var target=project.sections.first{$0.id==scope}!
            for alias in aliases {
                if let m=captures("^(?:(?:сделай|make|в|in)\\s+)?"+alias.pattern+"\\s*[:,]?\\s*(.*)$",body){
                    if let found=project.sections.first(where:{alias.aliases.contains($0.name.lowercased())}){target=found}
                    else{target=selected;operations.append(.init(.renameSection,sectionID:target.id,name:alias.name));assumptions.append(NSLocalizedString("The selected section will be renamed",comment:"")+": "+target.name+" → "+alias.name)}
                    guard scope==selected.id || scope==target.id else{throw AssistantError.unsupported};scope=target.id;body=trim(m[0]);break
                }
            }
            var bars=sectionBars[target.id] ?? target.length/barTicks
            if let m=captures("^([0-9]{1,2})\\s*(?:тактов|такта|такт|bars?)\\s*[:,]?\\s*(.*)$",body){guard let count=Int(m[0]),(1...64).contains(count)else{throw MusicError.limit};bars=count;sectionBars[scope]=bars;operations.append(.init(.resizeSection,sectionID:scope,bars:bars));body=trim(m[1]);if bars<target.length/barTicks{warnings.append(NSLocalizedString("Shortening trims notes at the section end.",comment:""))}else if bars>target.length/barTicks{assumptions.append(NSLocalizedString("Extending the section adds empty space; existing notes are not repeated.",comment:""))}}
            if body.isEmpty{continue}
            if let m=captures("^(?:аккорды|chords|progression)\\s*:?\\s*(.+)$",body){body=m[0]}
            var each:Int?
            if let m=captures("^(.+?)\\s+(?:по|each)\\s+(одному|один|два|две|четыре|one|two|four|[0-9]{1,2})\\s*(?:тактов|такта|такту|такт|bars?)$",body){let words=["одному":1,"один":1,"два":2,"две":2,"четыре":4,"one":1,"two":2,"four":4];each=Int(m[1]) ?? words[m[1].lowercased()];body=m[0]}
            let tokens=try chordTokens(body)
            guard (1...64).contains(tokens.count)else{throw AssistantError.unsupported}
            let chords: [Chord]
            do{let aliases=["ам":"Am","до":"C","фа":"F","соль":"G","ля-минор":"Am","ре-минор":"Dm","ми-минор":"Em"];chords=try tokens.map{try Chord.parse(aliases[$0.lowercased()] ?? $0)}}catch{throw AssistantError.unsupported}
            var progression=chords;var durations:[Int]
            if let each{guard each>0,each*chords.count==bars else{throw AssistantError.mismatch};durations=Array(repeating:each,count:chords.count)}
            else if chords.count==bars{durations=Array(repeating:1,count:chords.count)}
            else {
                guard bars%chords.count==0,bars>=chords.count else{throw AssistantError.mismatch}
                guard let distribution else{throw AssistantError.ambiguous}
                switch distribution {
                case .stretch:durations=Array(repeating:bars/chords.count,count:chords.count);assumptions.append(NSLocalizedString("The chords are stretched evenly across the section.",comment:""))
                case .repeatBars:progression=(0..<bars).map{chords[$0%chords.count]};durations=Array(repeating:1,count:bars);assumptions.append(NSLocalizedString("The progression repeats with one bar per chord.",comment:""))
                }
            }
            operations.append(.init(.setProgression,sectionID:scope,chords:progression,durations:durations))
        }
        let proposal=AssistantProposal(project:project,scope:scope,operations:operations,assumptions:assumptions,warnings:warnings)
        _ = try proposal.candidate(for:project);return proposal
    }
}
