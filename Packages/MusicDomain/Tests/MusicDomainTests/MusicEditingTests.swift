import Foundation
import Testing
@testable import MusicDomain

struct MusicEditingTests {
    private func populated()throws->Project {
        var p=Project.demo();try p.addMelody()
        p.patterns[0].chords[0].chord=try Chord.parse("Bmaj7/F#")
        p.patterns[0].chords[1].chord=try Chord.parse("C{0,3,7,12}/E")
        p.patterns[2].notes=[NoteEvent(tick:120,duration:300,pitch:59,velocity:93,confidence:0.81),NoteEvent(tick:540,duration:720,pitch:72,velocity:108)]
        return p
    }

    @Test func everyActualPitchedNoteMovesExactlyAcrossOctavesAndDrumsDoNot()throws {
        let p=try populated(),before=Compiler.notes(p)
        for delta in [-24,-13,-1,1,2,13,24] {
            let proposal=try MusicalEditing.transpose(p,semitones:delta),after=Compiler.notes(proposal.candidate)
            var expected:[CompiledNote]=before
            for index in expected.indices where p.tracks[expected[index].track].role != .drums{expected[index].pitch+=delta}
            expected.sort{left,right in left.tick == right.tick ? left.pitch<right.pitch:left.tick<right.tick}
            // Equal-time equal-pitch notes on different tracks have no ordering
            // contract; compare every musical field with a total sort key.
            let actualFields=after.map{[$0.track,$0.tick,$0.duration,$0.pitch,$0.velocity,$0.pad,$0.instrument]}.sorted{$0.lexicographicallyPrecedes($1)}
            let expectedFields=expected.map{[$0.track,$0.tick,$0.duration,$0.pitch,$0.velocity,$0.pad,$0.instrument]}.sorted{$0.lexicographicallyPrecedes($1)}
            #expect(actualFields==expectedFields)
            #expect(proposal.candidate.tracks==p.tracks)
            #expect(proposal.candidate.sections==p.sections)
            #expect(proposal.candidate.patterns.map(\.id)==p.patterns.map(\.id))
            #expect(proposal.candidate.patterns[0].chords.map(\.id)==p.patterns[0].chords.map(\.id))
            #expect(proposal.candidate.patterns[1]==p.patterns[1])
            #expect(proposal.candidate.patterns[2].notes?.map(\.id)==p.patterns[2].notes?.map(\.id))
            #expect(proposal.candidate.patterns[0].chords[1].chord.customIntervals==p.patterns[0].chords[1].chord.customIntervals)
            #expect(proposal.candidate.patterns[0].chords[0].chord.slashBass==(6+delta%12+12)%12)
        }
    }

    @Test func lowAndHighBassRegistersTransposeExactlyAndStillRespondToRegister()throws {
        for register in [-1,0,1] {
            var original=Project.demo();original.bassOctave=register
            var changed=try MusicalEditing.transpose(original,semitones:1).candidate
            #expect(changed.patterns[0].chords[0].chord.rootBassPitch==37+register*12)
            #expect(Compiler.notes(changed).filter{$0.instrument==2}.map(\.pitch)==Compiler.notes(original).filter{$0.instrument==2}.map{$0.pitch+1})
            let next=register==1 ? 0:register+1
            let before=Compiler.notes(changed).filter{$0.instrument==2}.map(\.pitch)
            try MusicalEditing.setBassRegister(next,in:&changed)
            #expect(Compiler.notes(changed).filter{$0.instrument==2}.map(\.pitch)==before.map{$0+(next-register)*12})
        }
    }

    @Test func oneHistoryTransactionUndoRedoAndOppositeTransposeRestoreSound()throws {
        var project=try populated();let original=project,notes=Compiler.notes(project)
        var history=History();let proposal=try MusicalEditing.transpose(project,semitones:13)
        try history.apply(&project){try proposal.apply(to:&$0)}
        #expect(project.revision==original.revision+1);#expect(history.canUndo)
        let changed=Compiler.notes(project)
        history.undo(&project);#expect(Compiler.notes(project)==notes);#expect(!history.canUndo)
        #expect(project.patterns==original.patterns);#expect(project.tracks==original.tracks)
        history.redo(&project);#expect(Compiler.notes(project)==changed)
        let back=try MusicalEditing.transpose(project,semitones:-13)
        #expect(Compiler.notes(back.candidate)==notes)
    }

    @Test func rangeFailureAndStaleProposalAreAtomic()throws {
        var p=try populated();p.patterns[2].notes?[0].pitch=127
        let original=p;var history=History()
        #expect(throws:TranspositionError.self){try history.apply(&p){$0=try MusicalEditing.transpose($0,semitones:1).candidate}}
        #expect(p==original);#expect(!history.canUndo)
        p.patterns[2].notes?[0].pitch=0
        #expect(throws:TranspositionError.self){try MusicalEditing.transpose(p,semitones:-1)}
        for amount in [0,25,-25,Int.max,Int.min]{#expect(throws:TranspositionError.self){try MusicalEditing.transpose(original,semitones:amount)}}
        var current=try populated();let plan=try MusicalEditing.transpose(current,semitones:2)
        current.revision+=1;let snapshot=current
        #expect(throws:TranspositionError.self){try plan.apply(to:&current)};#expect(current==snapshot)
    }

    @Test func customVoicingRangeFailureAndBassEditDoNotClipOrKeepWrongRoot()throws {
        var p=Project.demo()
        p.patterns[0].chords[0].chord=Chord(root:0,voicedNotes:[120,124,127])
        #expect(throws:TranspositionError.self){try MusicalEditing.transpose(p,semitones:1)}
        var chord=try MusicalEditing.transpose(Project.demo(),semitones:1).candidate.patterns[0].chords[0].chord
        #expect(chord.rootBassPitch==37)
        chord.root=2;chord.voicedNotes=nil;#expect(chord.rootBassPitch==nil)
        chord.rootBassPitch=38;try chord.validate();chord.slashBass=4;#expect(chord.rootBassPitch==nil)
        chord.rootBassPitch=39;#expect(throws:MusicError.self){try chord.validate()}
        chord.rootBassPitch=128;#expect(throws:MusicError.self){try chord.validate()}
        var low=Project.demo();low.patterns[0].chords[0].chord.rootBassPitch=0
        let original=low
        #expect(throws:TranspositionError.self){try MusicalEditing.setBassRegister(-1,in:&low)}
        #expect(low==original)
    }

    @Test func voiceAssetsAndFrozenPerformanceRemainUnchangedAndPortable()throws {
        let (data,record)=AudioAssetTests.source()
        var p=try populated();p.audioAssets=[record];p.tracks[3].clips[0].sourceAssetID=record.id
        p.performanceTake=PerformanceTake(source:p,sampleRate:48000,durationFrames:48000,events:[PerformanceEvent(frame:0,kind:.section,sectionID:p.sections[0].id)])
        let frozen=p.performanceTake,assetHash=record.sha256
        let changed=try MusicalEditing.transpose(p,semitones:2).candidate
        #expect(changed.performanceTake==frozen);#expect(changed.audioAssets==p.audioAssets)
        #expect(changed.tracks[3].clips[0].sourceAssetID==record.id)
        let archive=try PortableProject.data(changed,assets:[record.relativePath:data])
        let decoded=try PortableProject.decodeBundle(archive,asCopy:false)
        #expect(decoded.project==changed);#expect(decoded.assets[record.relativePath]==data)
        #expect(try AssetIntegrity.sha256(decoded.assets[record.relativePath]!)==assetHash)
    }

    @Test func allLegacyVersionsAndFrozenSourcesMigrateWithoutChangingMusic()throws {
        let (audio,record)=AudioAssetTests.source()
        for version in 1...8 {
            var old=try populated();old.schemaVersion=version;old.audioAssets=[record]
            old.tracks[3].clips[0].sourceAssetID=record.id
            old.performanceTake=PerformanceTake(source:old,sampleRate:48000,durationFrames:48000,events:[PerformanceEvent(frame:0,kind:.section,sectionID:old.sections[0].id)])
            let originalMusic=Compiler.notes(old),originalSourceMusic=Compiler.notes(old.performanceTake!.source)
            let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys];let manifest=try encoder.encode(old)
            let metadata:[String:String]=["format":"La Grilla portable project","version":"2","manifestCRC32":String(format:"%08x",ProjectArchive.checksum(manifest))]
            let archive=try ProjectArchive.encode([.init("manifest.json",manifest),.init("metadata.json",try JSONSerialization.data(withJSONObject:metadata)),.init(record.relativePath,audio)])
            let migrated=try PortableProject.decodeBundle(archive,asCopy:false)
            #expect(migrated.project.schemaVersion==9);#expect(migrated.project.performanceTake?.source.schemaVersion==9)
            #expect(Compiler.notes(migrated.project)==originalMusic)
            #expect(Compiler.notes(migrated.project.performanceTake!.source)==originalSourceMusic)
            #expect(migrated.project.performanceTake?.events==old.performanceTake?.events)
            #expect(migrated.project.audioAssets==old.audioAssets);#expect(migrated.assets[record.relativePath]==audio)
            #expect(try encoder.encode(old)==manifest)
            // ZIP CRC alone must not allow modified source audio through migration.
            var entries=try ProjectArchive.decode(archive)
            let index=try #require(entries.firstIndex{$0.name==record.relativePath})
            entries[index].data[entries[index].data.count-1] ^= 1
            let tampered=try ProjectArchive.encode(entries)
            #expect(throws:ExportError.self){try PortableProject.decodeBundle(tampered)}
        }
    }

    @Test func midiContainsTransposedRealPitchesWithDrumChannelUnchanged()throws {
        let original=try populated(),changed=try MusicalEditing.transpose(original,semitones:13).candidate
        let before=try midiPitches(MIDIExporter.data(original)),after=try midiPitches(MIDIExporter.data(changed))
        for index in original.tracks.indices {
            #expect(after[index+1]==before[index+1]?.map{$0+(original.tracks[index].role == .drums ? 0:13)})
        }
    }

    @Test func keyAwareSpellingAndWrittenOctavesUsePracticalAccidentals()throws {
        #expect(MusicalNotation.pitchClassName(10,keyRoot:5,minor:false)=="B♭")
        #expect(MusicalNotation.pitchClassName(1,keyRoot:1,minor:false)=="D♭")
        #expect(MusicalNotation.pitchClassName(5,keyRoot:6,minor:false)=="E♯")
        #expect(MusicalNotation.noteName(59,keyRoot:3,minor:true)=="C♭4")
        #expect(MusicalNotation.noteName(70,keyRoot:5,minor:false,spelling:.sharps)=="A♯4")
        #expect(MusicalNotation.noteName(61,keyRoot:7,minor:false,spelling:.flats)=="D♭4")
        #expect(MusicalNotation.chordSymbol(try Chord.parse("A#maj7/Db"),keyRoot:5,minor:false)=="B♭maj7/D♭")
        for root in 0..<12 {for minor in [false,true] {for pitch in 0..<128 {
            let name=MusicalNotation.pitchClassName(pitch,keyRoot:root,minor:minor)
            #expect(try Chord.parse(name).root==pitch%12)
        }}}
    }

    @Test func scaleDegreesDescribeMajorMinorAndChromaticChordsWithoutChangingData()throws {
        let samples:[(String,Int,Bool,String)]=[("Dm7",0,false,"ii7"),("G7",0,false,"V7"),("Bdim7",0,false,"vii°7"),("Dm7b5",0,true,"iiø7"),("Abmaj7",0,true,"VImaj7"),("A7",0,false,"VI7"),("Bb",5,false,"IV"),("Bb",0,false,"♭VII"),("Eb",0,false,"♭III"),("F#",0,false,"♯IV"),("B",0,true,"♯VII"),("C/E",0,false,"I/III")]
        for (symbol,key,minor,expected) in samples {
            let chord=try Chord.parse(symbol),copy=chord
            #expect(MusicalNotation.degreeSymbol(chord,keyRoot:key,minor:minor)==expected)
            #expect(chord==copy)
        }
    }

    @Test func rebuildingAnEquivalentOrNewQualitySymbolRetainsTheActualTransposedBass()throws {
        var project=try MusicalEditing.transpose(Project.demo(),semitones:1).candidate
        let transposed=project.patterns[0].chords[0].chord
        #expect(transposed.rootBassPitch==37)
        let same=try MusicalEditing.rebuildChord(from:"Db",preserving:transposed)
        #expect(same==transposed)
        project.patterns[0].chords[0].chord=same
        #expect(Compiler.notes(project).first{$0.track==2 && $0.tick==0}?.pitch==37)
        let seventh=try MusicalEditing.rebuildChord(from:"C#maj7",preserving:transposed)
        #expect(seventh.quality == .maj7);#expect(seventh.rootBassPitch==37)
        project.patterns[0].chords[0].chord=seventh
        #expect(Compiler.notes(project).first{$0.track==2 && $0.tick==0}?.pitch==37)
        let newRoot=try MusicalEditing.rebuildChord(from:"Dmaj7",preserving:seventh)
        #expect(newRoot.rootBassPitch==nil)
        let newSlash=try MusicalEditing.rebuildChord(from:"C#maj7/F",preserving:seventh)
        #expect(newSlash.rootBassPitch==nil)
        var slashProject=Project.demo();slashProject.patterns[0].chords[0].chord=try Chord.parse("C/E")
        let slash=try MusicalEditing.transpose(slashProject,semitones:1).candidate.patterns[0].chords[0].chord
        let updated=try MusicalEditing.rebuildChord(from:"Dbmaj7/F",preserving:slash)
        #expect(updated.rootBassPitch==slash.rootBassPitch)
        #expect(Compiler.bassPitch(for:updated,register:slashProject.bassOctave)==29)
    }

    @Test func harmonyStylesKeepTransposedBassUnlessTheyActuallyChangeTheRoot()throws {
        let transposed=try MusicalEditing.transpose(Project.demo(),semitones:1).candidate
        let bass=Compiler.notes(transposed).filter{$0.track==2}
        for style in [HarmonyStyle.voiceLeading,.gentle,.expressive] {
            let proposal=try HarmonyLab.propose(transposed,sectionID:transposed.sections[0].id,options:HarmonyOptions(style:style))
            #expect(Compiler.notes(proposal.candidate).filter{$0.track==2}==bass)
            #expect(proposal.candidate.patterns.flatMap(\.chords).first?.chord.rootBassPitch==37)
        }
        var original=Project.demo()
        original.patterns[0].chords=["C","D7","G","C"].enumerated().map{index,symbol in ChordEvent(tick:index*barTicks,chord:try! Chord.parse(symbol))}
        let before=try MusicalEditing.transpose(original,semitones:1).candidate
        let reharm=try HarmonyLab.propose(before,sectionID:before.sections[0].id,options:HarmonyOptions(style:.reharmonize))
        let events=Arrangement.harmony(reharm.candidate,section:reharm.candidate.sections[0])
        #expect(events[0].chord.rootBassPitch==37)
        #expect(events[1].chord.root==9);#expect(events[1].chord.rootBassPitch==nil)
        #expect(Compiler.notes(reharm.candidate).first{$0.track==2 && $0.tick==barTicks}?.pitch==33)
    }

    @Test func assistantReuseRetainsActualTransposedBassAndSchemaNineChordsRoundTrip()throws {
        let p=try MusicalEditing.transpose(Project.demo(),semitones:1).candidate
        let originalBass=Compiler.notes(p).filter{$0.track==2}.map(\.pitch)
        #expect(originalBass.first==37)
        let section=p.sections[0].id
        let proposal=try AssistantEngine.propose("Song: Intro 8 bars: C# A#m F# G# C# A#m F# G#",project:p,sectionID:section)
        let reused=try proposal.candidate(for:p)
        #expect(Compiler.notes(reused).filter{$0.track==2}.map(\.pitch)==originalBass+originalBass)
        let sourceNotes=Compiler.notes(p).filter{$0.track==0}.map(\.pitch)
        #expect(Compiler.notes(reused).filter{$0.track==0}.map(\.pitch)==sourceNotes+sourceNotes)
        let progression=try AssistantEngine.propose("C# A#m F# G#",project:p,sectionID:section)
        #expect(Compiler.notes(try progression.candidate(for:p)).filter{$0.track==2}.map(\.pitch)==originalBass)
        let explicit=AssistantProposal(project:p,scope:section,operations:[AssistantOperation(.setProgression,sectionID:section,chords:p.patterns[0].chords.map(\.chord),durations:[1,1,1,1])])
        let decoded=try AssistantProposal.decode(JSONEncoder().encode(explicit),for:p)
        #expect(Compiler.notes(try decoded.candidate(for:p))==Compiler.notes(p))
        var supplied=Chord(root:1,voicedNotes:[49,53,56],rootBassPitch:49)
        supplied=Arrangement.chordPreservingSource(supplied,at:0,from:Arrangement.harmony(p,section:p.sections[0]))
        #expect(supplied.rootBassPitch==49);#expect(supplied.notes==[49,53,56])
        let changed=try AssistantEngine.propose("D A#m F# G#",project:p,sectionID:section)
        let newRoot=try changed.candidate(for:p)
        #expect(Compiler.notes(newRoot).first{$0.track==2 && $0.tick==0}?.pitch==26)
    }

    private func midiPitches(_ data:Data)throws->[Int:[Int]] {
        let bytes=Array(data);var cursor=14,track=0,result:[Int:[Int]]=[:]
        func variable(_ position:inout Int)->Int {
            var value=0
            repeat{let byte=bytes[position];position+=1;value=value*128+Int(byte&127);if byte&128==0{return value}}while position<bytes.count
            return value
        }
        while cursor+8<=bytes.count {
            #expect(Array(bytes[cursor..<cursor+4])==Array("MTrk".utf8))
            let length=bytes[(cursor+4)..<(cursor+8)].reduce(0){$0*256+Int($1)};cursor+=8;let end=cursor+length
            while cursor<end {
                _=variable(&cursor);let status=bytes[cursor];cursor+=1
                if status==0xff{cursor+=1;let count=variable(&cursor);cursor+=count}
                else if status&0xf0==0xc0 || status&0xf0==0xd0{cursor+=1}
                else{let pitch=Int(bytes[cursor]),velocity=Int(bytes[cursor+1]);cursor+=2;if status&0xf0==0x90 && velocity>0{result[track,default:[]].append(pitch)}}
            }
            track+=1
        }
        return result
    }
}
