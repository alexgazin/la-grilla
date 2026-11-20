import Foundation

extension Arrangement {
    public static func materialize(_ p:Project,track:Track,section:Section)->Pattern {
        var result=Pattern(length:section.length)
        for c in track.clips {
            guard let pattern=p.patterns.first(where:{$0.id==c.patternID})else{continue}
            for cycle in stride(from:-c.offset,to:c.length,by:pattern.length){
                for e in pattern.chords {
                    let start=max(c.start,c.start+cycle+e.tick,section.start),end=min(c.start+c.length,c.start+cycle+e.tick+e.duration,section.start+section.length)
                    if end>start{result.chords.append(ChordEvent(tick:start-section.start,duration:end-start,chord:e.chord,velocity:e.velocity))}
                }
                for e in pattern.drums {let absolute=c.start+cycle+e.tick;if absolute>=c.start,absolute<c.start+c.length,absolute>=section.start,absolute<section.start+section.length{result.drums.append(DrumEvent(tick:absolute-section.start,pad:e.pad,velocity:e.velocity))}}
                for e in pattern.notes ?? [] {
                    let start=max(c.start,c.start+cycle+e.tick,section.start),end=min(c.start+c.length,c.start+cycle+e.tick+e.duration,section.start+section.length)
                    if end>start{result.notes?.append(NoteEvent(tick:start-section.start,duration:end-start,pitch:e.pitch,velocity:e.velocity,confidence:e.confidence))}
                }
            }
        }
        return result
    }
    /// Shortening trims events; extending adds empty space and never invents repetitions.
    public static func resized(_ project:Project,sectionID:UUID,bars:Int)throws->Project {
        try project.validate()
        guard (1...64).contains(bars),let index=project.sections.firstIndex(where:{$0.id==sectionID})else{throw MusicError.invalidProject}
        let section=project.sections[index],length=bars*barTicks,delta=length-section.length,end=section.start+section.length
        guard project.length+delta<=songTickLimit else{throw MusicError.limit}
        if delta==0{return project}
        var result=project
        for i in project.tracks.indices {
            let track=project.tracks[i];var clips:[Clip]=[]
            for c in track.clips {
                let clipEnd=c.start+c.length
                if clipEnd<=section.start{clips.append(c);continue}
                if c.start>=end{var next=c;next.start+=delta;clips.append(next);continue}
                if c.start<section.start{var left=c;left.id=UUID();left.length=section.start-c.start;clips.append(left)}
                if clipEnd>end,let pattern=project.patterns.first(where:{$0.id==c.patternID}){var right=c;right.id=UUID();right.start=end+delta;right.length=clipEnd-end;right.offset=(c.offset+end-c.start)%pattern.length;clips.append(right)}
            }
            if track.role != .bass {
                var pattern=materialize(project,track:track,section:section);pattern.length=length
                pattern.chords=pattern.chords.compactMap{e in guard e.tick<length else{return nil};var copy=e;copy.duration=min(e.duration,length-e.tick);return copy}
                pattern.notes=pattern.notes?.compactMap{e in guard e.tick<length else{return nil};var copy=e;copy.duration=min(e.duration,length-e.tick);return copy}
                pattern.drums.removeAll{$0.tick>=length};result.patterns.append(pattern);var clip=Clip(patternID:pattern.id,start:section.start,length:length);let sources=Set(track.clips.filter{$0.start<end && $0.start+$0.length>section.start}.compactMap(\.sourceAssetID));if sources.count==1{clip.sourceAssetID=sources.first};clips.append(clip)
            }
            result.tracks[i].clips=clips.sorted{$0.start<$1.start}
        }
        result.sections[index].length=length
        for i in result.sections.indices where result.sections[i].start>=end{result.sections[i].start+=delta}
        result.removeUnusedPatterns()
        try result.validate();return result
    }
}
