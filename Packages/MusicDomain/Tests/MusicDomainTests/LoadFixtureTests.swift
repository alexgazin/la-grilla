import Testing
import Foundation
@testable import MusicDomain

struct LoadFixtureTests {
    @Test func largePortableProjectsRemainValidAndPreserveCompiledMusic() throws {
        for level in 1...3 {
            var project=Project(name:"QA P\(level) · 64 bars",bars:64);project.bpm=123;project.master = -6
            let harmonyStep=level==1 ? barTicks:level==2 ? 480:240
            project.patterns[0].length=level==1 ? project.length:level==2 ? 32*barTicks:16*barTicks
            project.patterns[0].chords=stride(from:0,to:project.patterns[0].length,by:harmonyStep).map{ChordEvent(tick:$0,duration:harmonyStep,chord:Chord(root:0))}
            let drumStep=level==3 ? 240:480
            project.patterns[1].drums=stride(from:0,to:project.length,by:drumStep).map{DrumEvent(tick:$0,pad:($0/drumStep)%16,velocity:90)}
            if level==1{project.tracks.append(Track(role:.bass))}
            else {
                let step=level==2 ? 240:120
                for index in 0..<6 {
                    var pattern=Pattern(length:project.length)
                    pattern.notes=stride(from:0,to:project.length,by:step).map{NoteEvent(tick:$0,duration:min(1920,project.length-$0),pitch:48+($0/step+index)%36,velocity:90)}
                    var track=Track(role:.melody);track.name="QA melody \(index+1)";track.clips=[Clip(patternID:pattern.id,start:0,length:project.length)]
                    project.patterns.append(pattern);project.tracks.append(track)
                }
            }
            for index in project.tracks.indices{project.tracks[index].gain = -20}
            if level==3{project.masterFX=MasterFX(filter:-0.6,delayWet:0.4)}
            try project.validate();let compiled=Compiler.notes(project)
            #expect(compiled.count == (level==1 ? 768:level==2 ? 8192:16384))
            let bytes=try PortableProject.data(project),decoded=try PortableProject.decode(bytes,asCopy:false)
            #expect(Compiler.notes(decoded)==compiled);#expect(decoded.tracks.allSatisfy{$0.presetVersion==2})
            if let path=ProcessInfo.processInfo.environment["GRILLA_EXPORT_FIXTURES"] {
                let folder=URL(fileURLWithPath:path);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                try bytes.write(to:folder.appendingPathComponent("load-P\(level).grillapack"))
            }
        }
    }
}
