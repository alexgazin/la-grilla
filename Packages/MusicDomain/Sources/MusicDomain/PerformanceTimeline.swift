import Foundation

/// Musical projection of a finite take. WAV replay remains sample based; MIDI repeats
/// rearticulate sliced notes rather than trying to encode an audio buffer in SMF.
public enum PerformanceTimeline {
    public static func durationTicks(_ take:PerformanceTake)->Int {
        min(64*barTicks,max(1,Int((take.durationSeconds*take.source.bpm/60*Double(ppq)).rounded())))
    }
    private static func tick(_ event:PerformanceEvent,_ take:PerformanceTake)->Int {
        min(durationTicks(take),Int((Double(event.frame)/take.sampleRate*take.source.bpm/60*Double(ppq)).rounded()))
    }
    private static func slice(_ notes:[CompiledNote],_ range:Range<Int>,offset:Int)->[CompiledNote] {
        notes.compactMap{note in let start=max(note.tick,range.lowerBound),end=min(note.tick+note.duration,range.upperBound);guard end>start else{return nil};var n=note;n.tick=start-range.lowerBound+offset;n.duration=end-start;return n}
    }
    public static func backingNotes(_ take:PerformanceTake)throws->[CompiledNote] {
        try take.validate();let source=take.source,total=durationTicks(take)
        var section=source.sections.first(where:{$0.id==take.events[0].sectionID})!,position=0,clock=0,result:[CompiledNote]=[]
        position=section.start
        func advance(_ end:Int)throws {
            while clock<end {
                let length=min(end-clock,section.start+section.length-position)
                guard length>0 else{throw MusicError.invalidProject}
                for var n in Compiler.notes(source,range:position..<position+length){n.tick+=clock;result.append(n)}
                guard result.count<=200_000 else{throw MusicError.tooDense}
                clock+=length;position+=length
                if position>=section.start+section.length{position=section.start}
            }
        }
        for event in take.events {
            let t=tick(event,take);try advance(t)
            switch event.kind {
            case .section:section=source.sections.first(where:{$0.id==event.sectionID})!;position=section.start
            case .jump:let local=position-section.start+Int(event.value)*ppq;position=section.start+((local%section.length)+section.length)%section.length
            case .pad:if t<total{result.append(CompiledNote(tick:t,duration:min(120,total-t),pitch:Compiler.drumMap[event.pad!],velocity:Int(event.value),track:1,pad:event.pad!,instrument:1))}
            case .preview:if t<total,let note=event.note{result.append(CompiledNote(tick:t,duration:min(note.duration,total-t),pitch:note.pitch,velocity:note.velocity,track:event.track!,instrument:event.instrument!))}
            default:break
            }
        }
        try advance(total);return result.sorted{$0.tick==$1.tick ? $0.pitch<$1.pitch:$0.tick<$1.tick}
    }
    public static func notes(_ take:PerformanceTake)throws->[CompiledNote] {
        let backing=try backingNotes(take),total=durationTicks(take)
        var result:[CompiledNote]=[],clock=0,repeatStart=0,size=0
        func emit(_ end:Int)throws {
            guard end>clock else{return}
            if size==0 {result+=slice(backing,clock..<end,offset:clock)}else{
                let window=slice(backing,max(0,repeatStart-size)..<repeatStart,offset:0)
                var cursor=clock
                while cursor<end {
                    let phase=(cursor-repeatStart)%size,length=min(end-cursor,size-phase)
                    result+=slice(window,phase..<phase+length,offset:cursor);cursor+=length
                    guard result.count<=200_000 else{throw MusicError.tooDense}
                }
            }
            clock=end
        }
        for event in take.events where event.kind == .repeatSize {let t=tick(event,take);try emit(t);repeatStart=t;size=Int(event.value)}
        try emit(total);guard result.count<=200_000 else{throw MusicError.tooDense};return result
    }
    public static func midi(_ take:PerformanceTake)throws->Data {
        let notes=try notes(take),source=take.source
        var controls:[MIDIControl]=[],markers:[MIDIMarker]=[]
        let solo=source.tracks.contains(where: \.solo)
        var gains=source.tracks.map{$0.mute || (solo && !$0.solo) ? 0:pow(10,$0.gain/20)},master=source.master<=(-61) ? 0:pow(10,source.master/20)
        func cc(_ t:Int,_ track:Int,_ number:Int,_ value:Double){controls.append(MIDIControl(tick:t,track:track,number:number,value:min(127,max(0,Int(value.rounded())))))}
        func volumes(_ t:Int){for i in gains.indices{cc(t,i,7,gains[i]*master*127)}}
        volumes(0);for i in source.tracks.indices{cc(0,i,10,(source.tracks[i].pan+1)*63.5)}
        let fx=source.masterFX ?? MasterFX();for i in gains.indices{cc(0,i,74,(fx.filter+1)*63.5);cc(0,i,94,fx.delayWet*254)}
        for event in take.events {
            let t=tick(event,take)
            switch event.kind {
            case .section:markers.append(MIDIMarker(tick:t,text:source.sections.first(where:{$0.id==event.sectionID})!.name))
            case .gain:if event.track==masterBus{master=event.value}else{gains[event.track!]=event.value};volumes(t)
            case .pan:cc(t,event.track!,10,(event.value+1)*63.5)
            case .filter:for i in gains.indices{cc(t,i,74,(event.value+1)*63.5)}
            case .delay:for i in gains.indices{cc(t,i,94,event.value*254)}
            default:break
            }
            if [.gain,.pan,.filter,.delay,.repeatSize,.jump].contains(event.kind){markers.append(MIDIMarker(tick:t,text:"La Grilla \(event.kind) track=\(event.track ?? -1) value=\(event.value)"))}
        }
        return try MIDIExporter.sequence(source,notes:notes,duration:durationTicks(take),markers:markers,controls:controls)
    }
}
