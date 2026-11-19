import Foundation

public struct VoicePlacement:Sendable {public let project:Project;public let trackID:UUID}
extension Arrangement {
    public static func voiceCandidate(_ project:Project,sectionID:UUID,target:UUID?,notes:[NoteEvent],source:AudioAssetRecord)throws->VoicePlacement {
        try project.validate();try source.validate()
        guard !notes.isEmpty,let section=project.sections.first(where:{$0.id==sectionID})else{throw MusicError.invalidProject}
        var result=project
        let id:UUID
        if let target{guard result.tracks.contains(where:{$0.id==target && $0.role == .melody})else{throw MusicError.invalidProject};id=target}
        else{try result.addMelody();id=result.tracks.last!.id}
        guard let index=result.tracks.firstIndex(where:{$0.id==id})else{throw MusicError.invalidProject}
        if !(result.audioAssets ?? []).contains(where:{$0.id==source.id}){guard (result.audioAssets ?? []).count<8 else{throw MusicError.assetLimit};if result.audioAssets==nil{result.audioAssets=[]};result.audioAssets?.append(source)}
        else{guard result.audioAssets?.first(where:{$0.id==source.id})==source else{throw MusicError.invalidProject}}
        let end=section.start+section.length;var clips:[Clip]=[]
        for c in result.tracks[index].clips {
            let clipEnd=c.start+c.length
            if clipEnd<=section.start || c.start>=end{clips.append(c);continue}
            if c.start<section.start{var left=c;left.id=UUID();left.length=section.start-c.start;clips.append(left)}
            if clipEnd>end,let pattern=result.patterns.first(where:{$0.id==c.patternID}){var right=c;right.id=UUID();right.start=end;right.length=clipEnd-end;right.offset=(c.offset+end-c.start)%pattern.length;clips.append(right)}
        }
        let pattern=Pattern(length:section.length,notes:notes);result.patterns.append(pattern)
        var clip=Clip(patternID:pattern.id,start:section.start,length:section.length);clip.sourceAssetID=source.id;clips.append(clip)
        result.tracks[index].clips=clips.sorted{$0.start<$1.start}
        result.removeUnusedPatterns()
        try result.validate();return VoicePlacement(project:result,trackID:id)
    }
}
