import Foundation
import Testing
@testable import MusicDomain

struct ChordWritingTests {
    @Test func parserStoresTheWrittenRootAndSlashAndAcceptsItsOwnUnicodeSymbol()throws {
        let examples:[(String,String,Int,Int?)]=[
            ("Dbmaj7/Ab","D♭maj7/A♭",1,8),("C#maj7/G#","C♯maj7/G♯",1,8),
            ("Cb/Eb","C♭/E♭",11,3),("B#/E#","B♯/E♯",0,5),
            ("F##m7/Bbb","F♯♯m7/B♭♭",7,9),("d♭{0,4,7,12}/a♭","D♭{0,4,7,12}/A♭",1,8)
        ]
        for (text,symbol,root,bass) in examples {
            let chord=try Chord.parse(text)
            #expect(chord.symbol==symbol);#expect(chord.root==root);#expect(chord.slashBass==bass)
            #expect(try Chord.parse(symbol)==chord);try chord.validate()
            #expect(try JSONDecoder().decode(Chord.self,from:JSONEncoder().encode(chord))==chord)
        }
        let flat=try Chord.parse("Dbmaj7/Ab"),sharp=try Chord.parse("C#maj7/G#")
        #expect(flat != sharp);#expect(flat.notes==sharp.notes)
        #expect(try Chord.parse("C").rootSpelling=="C")
    }

    @Test func autoHonorsStoredWritingWhilePreferencesOnlyChangeTheDisplay()throws {
        let written=try Chord.parse("A#maj7/Db"),original=written
        #expect(MusicalNotation.chordSymbol(written,keyRoot:5,minor:false)=="A♯maj7/D♭")
        #expect(MusicalNotation.chordSymbol(written,keyRoot:5,minor:false,spelling:.flats)=="B♭maj7/D♭")
        #expect(MusicalNotation.chordSymbol(written,keyRoot:5,minor:false,spelling:.sharps)=="A♯maj7/C♯")
        #expect(MusicalNotation.chordSymbol(Chord(root:10,quality:.maj7),keyRoot:5,minor:false)=="B♭maj7")
        #expect(written==original)
    }

    @Test func scaleDegreesUseWrittenLettersIncludingEnharmonicBoundaryNotes()throws {
        let cases:[String:String]=["C#":"♯I","Db":"♭II","B#":"♯VII","Cb":"♭I","C/Db":"I/♭II","C/B#":"I/♯VII"]
        for (text,degree) in cases {
            let chord=try Chord.parse(text)
            #expect(MusicalNotation.degreeSymbol(chord,keyRoot:0,minor:false)==degree)
            _=MusicalNotation.chordSymbol(chord,keyRoot:0,minor:false,spelling:.flats)
            #expect(MusicalNotation.degreeSymbol(chord,keyRoot:0,minor:false)==degree)
        }
        #expect(MusicalNotation.degreeSymbol(try Chord.parse("E#dim"),keyRoot:6,minor:false)=="vii°")
        #expect(MusicalNotation.degreeSymbol(try Chord.parse("Cbmaj7"),keyRoot:3,minor:true)=="VImaj7")
    }

    @Test func mismatchedMalformedOrOrphanWritingIsRejected()throws {
        let invalid:[Chord]=[
            Chord(root:1,rootSpelling:"D"),Chord(root:1,rootSpelling:"H♭"),
            Chord(root:1,rootSpelling:"D♯♭"),Chord(root:1,rootSpelling:"D♭♭♭"),
            Chord(root:1,rootSpelling:""),Chord(root:1,rootSpelling:"D\n♭"),
            Chord(root:1,slashBassSpelling:"A♭"),Chord(root:1,slashBass:8,slashBassSpelling:"G")
        ]
        for chord in invalid {
            #expect(throws:MusicError.self){try chord.validate()}
            var p=Project.demo();p.patterns[0].chords[0].chord=chord
            #expect(throws:MusicError.self){try ProjectDocument.decode(JSONEncoder().encode(p))}
        }
        for text in ["C###","Dbbb","C#b","Cb#","C/G###"]{#expect(throws:MusicError.self){try Chord.parse(text)}}
    }

    @Test func rootAndSlashChangesCannotRetainStaleLetters()throws {
        var chord=try Chord.parse("Dbmaj7/Ab")
        chord.root=1;chord.slashBass=8
        #expect(chord.rootSpelling=="D♭");#expect(chord.slashBassSpelling=="A♭")
        chord.root=2;chord.voicedNotes=nil
        #expect(chord.rootSpelling==nil);#expect(chord.slashBassSpelling=="A♭")
        chord.slashBass=7;#expect(chord.slashBassSpelling==nil)
        try chord.validate()
        chord.slashBass=nil;#expect(chord.slashBassSpelling==nil)
    }

    @Test func transpositionUpdatesOrClearsWritingAndOneUndoRestoresItExactly()throws {
        var original=Project.demo();original.patterns[0].chords[0].chord=try Chord.parse("Dbmaj7/Ab")
        for interval in [-24,-12,-2,-1,1,2,12,24] {
            var p=original;var history=History()
            let proposal=try MusicalEditing.transpose(p,semitones:interval)
            try history.apply(&p){try proposal.apply(to:&$0)}
            let changed=p.patterns[0].chords[0].chord
            if interval%12==0 {
                #expect(changed.rootSpelling=="D♭");#expect(changed.slashBassSpelling=="A♭")
            }else {
                #expect(changed.rootSpelling==nil);#expect(changed.slashBassSpelling==nil)
            }
            try p.validate()
            history.undo(&p)
            #expect(p.patterns==original.patterns);#expect(p.patterns[0].chords[0].chord.symbol=="D♭maj7/A♭")
            #expect(Compiler.notes(p)==Compiler.notes(original))
        }
    }

    @Test func symbolEditsAndHarmonyVoicingPreserveChosenLetters()throws {
        var p=Project.demo();p.patterns[0].chords[0].chord=try Chord.parse("Db/Ab")
        let chord=p.patterns[0].chords[0].chord
        let edited=try MusicalEditing.rebuildChord(from:"Dbmaj7/Ab",preserving:chord)
        #expect(edited.rootSpelling=="D♭");#expect(edited.slashBassSpelling=="A♭")
        let respelled=try MusicalEditing.rebuildChord(from:"C#maj7/G#",preserving:edited)
        #expect(respelled.rootSpelling=="C♯");#expect(respelled.slashBassSpelling=="G♯")
        for style in [HarmonyStyle.voiceLeading,.gentle,.expressive] {
            let proposal=try HarmonyLab.propose(p,sectionID:p.sections[0].id,options:HarmonyOptions(style:style))
            let result=Arrangement.harmony(proposal.candidate,section:proposal.candidate.sections[0])[0].chord
            #expect(result.rootSpelling=="D♭");#expect(result.slashBassSpelling=="A♭")
        }
    }

    @Test func storedWritingSurvivesSavePortableAndFrozenSourceWithoutChangingAudio()async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:root)}
        let store=ProjectStore(root:root),(source,record)=AudioAssetTests.source()
        var p=Project.demo();p.patterns[0].chords[0].chord=try Chord.parse("Dbmaj7/Ab");p.audioAssets=[record]
        p.performanceTake=PerformanceTake(source:p,sampleRate:48000,durationFrames:48000,events:[PerformanceEvent(frame:0,kind:.section,sectionID:p.sections[0].id)])
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        let frozenHash=try AssetIntegrity.sha256(encoder.encode(p.performanceTake!.source))
        try await store.writeAsset(source,record:record,projectID:p.id);try await store.save(p)
        let loaded=try await store.load(p.id)
        #expect(loaded==p);#expect(loaded.patterns[0].chords[0].chord.symbol=="D♭maj7/A♭")
        #expect(try AssetIntegrity.sha256(encoder.encode(loaded.performanceTake!.source))==frozenHash)
        let archive=try PortableProject.data(loaded,assets:[record.relativePath:source])
        let bundle=try PortableProject.decodeBundle(archive,asCopy:false)
        #expect(bundle.project==p);#expect(bundle.assets[record.relativePath]==source)
        #expect(try AssetIntegrity.sha256(bundle.assets[record.relativePath]!)==record.sha256)
        #expect(try MIDIExporter.data(bundle.project)==MIDIExporter.data(p))
        var sharp=p;sharp.patterns[0].chords[0].chord=try Chord.parse("C#maj7/G#")
        #expect(Compiler.notes(sharp)==Compiler.notes(p))
        let flatURL=root.appendingPathComponent("flat.wav"),sharpURL=root.appendingPathComponent("sharp.wav")
        let settings=WAVSettings(sampleRate:44100,bitDepth:16,tailSeconds:0)
        _=try await OfflineRenderer.render(p,to:flatURL,settings:settings,range:0..<barTicks)
        _=try await OfflineRenderer.render(sharp,to:sharpURL,settings:settings,range:0..<barTicks)
        #expect(try Data(contentsOf:flatURL)==Data(contentsOf:sharpURL))
    }

    @Test func everyOldSchemaKeepsUnknownWritingUnknownAndPreservesMusicAndSourceAudio()throws {
        let (source,record)=AudioAssetTests.source()
        for version in 1...9 {
            var old=Project.demo();old.schemaVersion=version;old.audioAssets=[record]
            old.performanceTake=PerformanceTake(source:old,sampleRate:48000,durationFrames:48000,events:[PerformanceEvent(frame:0,kind:.section,sectionID:old.sections[0].id)])
            let data=try JSONEncoder().encode(old),hash=try AssetIntegrity.sha256(data)
            let migrated=try ProjectDocument.decode(data)
            #expect(migrated.schemaVersion==10);#expect(migrated.performanceTake?.source.schemaVersion==10)
            #expect(migrated.patterns.allSatisfy{$0.chords.allSatisfy{$0.chord.rootSpelling==nil && $0.chord.slashBassSpelling==nil}})
            #expect(Compiler.notes(migrated)==Compiler.notes(old))
            #expect(migrated.audioAssets==old.audioAssets)
            #expect(try AssetIntegrity.sha256(source)==record.sha256)
            #expect(try AssetIntegrity.sha256(data)==hash)
        }
    }
}
