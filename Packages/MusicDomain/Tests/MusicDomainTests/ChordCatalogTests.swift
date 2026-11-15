import Foundation
import Testing
@testable import MusicDomain

struct ChordCatalogTests {
    @Test func jazzFormulasProduceTheExpectedWrittenPitches() throws {
        let examples:[String:[Int]]=[
            "Cdim7":[60,63,66,69],"CmMaj7":[60,63,67,71],
            "Cmaj13":[60,64,67,71,74,77,81],"Cm13":[60,63,67,70,74,77,81],
            "C6/9":[60,64,67,69,74],"Cm6/9":[60,63,67,69,74],
            "C7(b9,#11)":[60,64,67,70,73,78],"C7#5b9":[60,64,68,70,73],
            "C9sus4":[60,65,67,70,74],"C7alt":[60,64,68,70,73,75],
            "Cmaj7(#11)":[60,64,67,71,78],"Cmaj13#11":[60,64,67,71,74,78,81]
        ]
        for (symbol,expected) in examples {let chord=try Chord.parse(symbol);#expect(chord.notes==expected);try chord.validate()}
    }

    @Test func canonicalCatalogRoundTripsAllRootsAndSlashBasses() throws {
        #expect(Quality.allCases.count>=50)
        for root in 0..<12 {for quality in Quality.allCases {for bass in [nil,0,3,7,11] as [Int?] {
            let chord=Chord(root:root,quality:quality,slashBass:bass)
            #expect(try Chord.parse(chord.symbol)==chord)
            try chord.validate()
            if let bass{#expect(chord.notes.first!%12==bass)}
        }}}
    }

    @Test func notationAliasesKeepMajorMinorAndDominantDistinct() throws {
        #expect(try Chord.parse("C7").notes==[60,64,67,70])
        #expect(try Chord.parse("CM7").notes==[60,64,67,71])
        #expect(try Chord.parse("Cm7").notes==[60,63,67,70])
        for alias in ["CΔ7","Cmaj7","C MAJ7"]{#expect(try Chord.parse(alias).quality == .maj7)}
        for alias in ["CmΔ7","CmM7","CmMaj7"]{#expect(try Chord.parse(alias).quality == .minorMajor7)}
        for alias in ["Cø7","Cø","Cm7b5"]{#expect(try Chord.parse(alias).quality == .m7b5)}
        for alias in ["C°7","Co7","Cdim7"]{#expect(try Chord.parse(alias).quality == .diminished7)}
        for alias in ["CM7#11","CΔ7(#11)"]{#expect(try Chord.parse(alias).quality == .major7Sharp11)}
        #expect(try Chord.parse("Cø9").quality == .minor9Flat5)
        #expect(try Chord.parse("Db6/9/Ab")==Chord(root:1,quality:.sixNine,slashBass:8))
        #expect(try Chord.parse("C6/9/E").notes==[52,60,64,67,69,74])
        #expect(try Chord.parse("F♯m7♭5/C♯")==Chord(root:6,quality:.m7b5,slashBass:1))
        for invalid in ["C/","C/E/G","C/Em","C7(b9","C7((b9))","C7(b9)garbage","C9#banana","H7","C14","C6/9/9"] {
            #expect(throws:MusicError.self){try Chord.parse(invalid)}
        }
    }

    @Test func customFormulaRoundTripsAndCompilesEveryWrittenTone() throws {
        let formula=[0,3,7,11,14,18,21,24]
        for root in 0..<12 {
            let chord=Chord(root:root,slashBass:4,customIntervals:formula)
            let parsed=try Chord.parse(chord.symbol);#expect(parsed==chord);try parsed.validate()
            #expect(parsed.notes.count==9);#expect(parsed.notes.first!%12==4)
            var project=Project.demo();project.patterns[0].chords[0].chord=chord;try project.validate()
            #expect(Compiler.notes(project).filter{$0.tick==0 && $0.track==0}.map(\.pitch).sorted()==chord.notes)
            #expect(try PortableProject.decode(PortableProject.data(project),asCopy:false)==project)
        }
        #expect(try Chord.parse("C{0, 4, 7, 10, 14}/E").customIntervals==[0,4,7,10,14])
        #expect(try Chord.parseCustomIntervals("0 4 7 10 14")==[0,4,7,10,14])
    }

    @Test func invalidCustomDefinitionsAndMissingCustomTonesAreRejected() throws {
        for text in ["C{}","C{0}","C{4,7}","C{0,7,4}","C{0,4,4,7}","C{0,-1,7}","C{0,4,49}","C{0,1,2,3,4,5,6,7,8}","C{0,4.5,7}","C{0,4,7", "C{0,4,7}/Em"] {
            #expect(throws:MusicError.self){try Chord.parse(text)}
        }
        var chord=try Chord.parse("C{0,12}")
        chord.voicedNotes=[60];#expect(throws:MusicError.self){try chord.validate()}
        chord.voicedNotes=[60,72];try chord.validate()
        chord.voicedNotes=[60,61];#expect(throws:MusicError.self){try chord.validate()}
        var project=Project.demo();project.patterns[0].chords[0].chord=Chord(customIntervals:[0,Int.max]);#expect(throws:MusicError.self){try project.validate()}
        project.patterns[0].chords[0].chord=Chord(root:Int.max,customIntervals:[0,4,7]);#expect(throws:MusicError.self){try project.validate()}
    }

    @Test func compactJazzVoicingsKeepIdentityWithoutEveryIntermediateExtension() throws {
        for symbol in ["C13","Cmaj13","Cm13","Cmaj11","C9","C13#11","C13b9","C7b9#11"] {
            var chord=try Chord.parse(symbol)
            let complete=try HarmonyLab.voicing(chord,previous:[],low:36,high:96,layout:.complete)
            let compact=try HarmonyLab.voicing(chord,previous:[],low:48,high:84,layout:.compact)
            #expect(compact.count<complete.count)
            #expect(compact.allSatisfy{(48...84).contains($0)})
            let classes=Set(compact.map{$0%12})
            #expect(Set(chord.requiredVoicingIntervals.map{($0+chord.root)%12}).isSubset(of:classes))
            chord.voicedNotes=compact;try chord.validate()
            var project=Project.demo();project.patterns[0].chords[0].chord=chord;try project.validate()
        }
        var chord=try Chord.parse("C13")
        chord.voicedNotes=[60,64,70,81];try chord.validate() // Root, third, b7, 13.
        chord.voicedNotes=[60,67,70,81];#expect(throws:MusicError.self){try chord.validate()} // No third.
        chord.voicedNotes=[60,64,70,74];#expect(throws:MusicError.self){try chord.validate()} // No named 13.
        chord.voicedNotes=[60,64,70,78,81];#expect(throws:MusicError.self){try chord.validate()} // Unwritten #11.
        chord=try Chord.parse("C7b9");chord.voicedNotes=[60,64,70];#expect(throws:MusicError.self){try chord.validate()}
    }

    @Test func everyPresetCanBeVoicedAcrossEveryRootWithoutInventingPitches() throws {
        for root in 0..<12 {for quality in Quality.allCases {for bass in [nil,4] as [Int?] {
            var chord=Chord(root:root,quality:quality,slashBass:bass)
            for layout in HarmonyVoicing.allCases {
                let notes=try HarmonyLab.voicing(chord,previous:[],low:36,high:96,layout:layout)
                #expect(chord.isValidVoicing(notes));#expect(notes.allSatisfy{(36...96).contains($0)})
                if layout == .complete{#expect(notes.count==quality.intervals.count+(bass==nil ? 0:1))}
                if let bass{#expect(notes.first!%12==bass)}
                chord.voicedNotes=notes;try chord.validate()
            }
        }}}
    }

    @Test func customFormulaSurvivesEveryStyleAndCompactMode() throws {
        var project=Project.demo();let custom=try Chord.parse("C{0,3,7,11,14}/E");project.patterns[0].chords[0].chord=custom
        for style in HarmonyStyle.allCases {
            let proposal=try HarmonyLab.propose(project,sectionID:project.sections[0].id,options:HarmonyOptions(style:style,low:36,high:96,voicing:.compact))
            let result=proposal.changes[0].after
            #expect(result.customIntervals==custom.customIntervals)
            #expect(result.quality==custom.quality)
            #expect(result.notes.count==custom.notes.count)
            #expect(Set(result.notes.map{$0%12})==Set(custom.notes.map{$0%12}))
            try proposal.candidate.validate()
        }
    }

    @Test func legacyChordJSONStillDecodesWithoutAFormula() throws {
        let data=Data(#"{"root":0,"quality":"maj7","inversion":1,"slashBass":4,"voicedNotes":[52,64,67,71,72]}"#.utf8)
        let chord=try JSONDecoder().decode(Chord.self,from:data)
        #expect(chord.customIntervals==nil);#expect(chord.quality == .maj7);try chord.validate()
        #expect(try JSONDecoder().decode(Chord.self,from:JSONEncoder().encode(chord))==chord)
    }

    @Test func schemaSevenAndItsFrozenPerformanceSourceMigrateWithoutChangingMusic() throws {
        var legacy=Project.demo();legacy.schemaVersion=7
        for index in legacy.tracks.indices{legacy.tracks[index].presetVersion=1}
        legacy.performanceTake=PerformanceTake(source:legacy,sampleRate:48000,durationFrames:48000,events:[PerformanceEvent(frame:0,kind:.section,sectionID:legacy.sections[0].id)])
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        let original=try encoder.encode(legacy),notes=Compiler.notes(legacy)
        let migrated=try ProjectDocument.decode(original)
        #expect(migrated.schemaVersion==8);#expect(migrated.performanceTake?.source.schemaVersion==8)
        #expect(Compiler.notes(migrated)==notes)
        #expect(migrated.performanceTake?.source.patterns==legacy.performanceTake?.source.patterns)
        #expect(migrated.performanceTake?.source.tracks==legacy.performanceTake?.source.tracks)
        #expect(migrated.performanceTake?.events==legacy.performanceTake?.events)
        #expect(migrated.patterns==legacy.patterns);#expect(migrated.tracks==legacy.tracks)
        #expect(try encoder.encode(legacy)==original)
        try migrated.validate()
    }

    @Test func futureSchemaIsRejectedBeforeUnknownChordVocabularyIsDecoded() throws {
        let project=Project.demo()
        var future=try JSONSerialization.jsonObject(with:JSONEncoder().encode(project)) as! [String:Any]
        future["schemaVersion"]=Project.currentSchemaVersion+1
        var patterns=future["patterns"] as! [[String:Any]],chords=patterns[0]["chords"] as! [[String:Any]]
        var chord=chords[0]["chord"] as! [String:Any];chord["quality"]="future-chord-type";chords[0]["chord"]=chord;patterns[0]["chords"]=chords;future["patterns"]=patterns
        var parent=project;parent.performanceTake=PerformanceTake(source:project,sampleRate:48000,durationFrames:48000,events:[PerformanceEvent(frame:0,kind:.section,sectionID:project.sections[0].id)])
        var frozen=try JSONSerialization.jsonObject(with:JSONEncoder().encode(parent)) as! [String:Any]
        var takes=frozen["performanceTakes"] as! [[String:Any]];takes[0]["source"]=future;frozen["performanceTakes"]=takes
        for object in [future,frozen] {
            let bytes=try JSONSerialization.data(withJSONObject:object)
            do{_ = try ProjectDocument.decode(bytes);Issue.record("A newer schema must not be decoded or silently downgraded.")}
            catch let error as MusicError{if case .unsupportedSchema=error{}else{Issue.record("Expected unsupportedSchema, received \(error)")}}
            catch{Issue.record("Header rejection must precede chord decoding: \(error)")}
        }
    }
}
