import Foundation

/// Explicit local starting points. A starter contains normal, editable events;
/// it is never presented as a model-generated result.
public enum ProjectTemplate:String,CaseIterable,Sendable {case empty,starter}

public enum ProjectTemplates {
    public static func make(name:String,bpm:Double,root:Int,minor:Bool,bars:Int,template:ProjectTemplate)throws->Project {
        guard (1...64).contains(bars),bpm.isFinite,(40...240).contains(bpm),(0..<12).contains(root) else{throw MusicError.invalidProject}
        let title=name.trimmingCharacters(in:.whitespacesAndNewlines)
        var project=Project(name:title.isEmpty ? "Untitled":title,bars:bars)
        project.bpm=bpm;project.keyRoot=root;project.minor=minor
        if template == .starter {
            let offsets=minor ? [0,5,8,10]:[0,9,5,7]
            let qualities:[Quality]=minor ? [.minor,.minor,.major,.major]:[.major,.minor,.major,.major]
            for bar in 0..<bars {
                let index=bar%offsets.count
                let chord=Chord(root:(root+offsets[index])%12,quality:qualities[index])
                project.patterns[0].chords.append(ChordEvent(tick:bar*barTicks,chord:chord))
                for tick in [0,2*ppq]{project.patterns[1].drums.append(DrumEvent(tick:bar*barTicks+tick,pad:0))}
                for tick in [ppq,3*ppq]{project.patterns[1].drums.append(DrumEvent(tick:bar*barTicks+tick,pad:1))}
                for tick in stride(from:0,to:barTicks,by:ppq/2){project.patterns[1].drums.append(DrumEvent(tick:bar*barTicks+tick,pad:2,velocity:72))}
            }
            // Bass is the existing editable root-following instrument. Its
            // register/gate/mix and the harmony controlling it remain editable.
            project.tracks.append(Track(role:.bass))
        }
        try project.validate()
        return project
    }
}
