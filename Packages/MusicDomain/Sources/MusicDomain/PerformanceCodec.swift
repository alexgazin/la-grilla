import Foundation
import AudioDSP

public enum PerformanceCodec {
    public static func kernelEvents(_ take:PerformanceTake,targetRate:Double)throws->[LGPerformanceEvent] {
        try take.validate();guard targetRate.isFinite,(8000...192000).contains(targetRate)else{throw MusicError.invalidProject}
        return try take.events.map{event in
            var out=LGPerformanceEvent();out.frame=UInt64((Double(event.frame)*targetRate/take.sampleRate).rounded());out.kind=Int32(event.kind.rawValue);out.track=Int32(event.track ?? -1);out.value=Float(event.value)
            switch event.kind {
            case .section:guard let i=take.source.sections.firstIndex(where:{$0.id==event.sectionID})else{throw MusicError.invalidProject};let section=take.source.sections[i];out.a=Int32(section.start);out.b=Int32(section.start+section.length);out.token=Int32(i+1)
            case .pad:out.a=Int32(event.pad!);out.track=1
            case .preview:out.a=Int32(event.note!.pitch);out.b=Int32(event.instrument!);out.value=Float(event.note!.velocity)
            case .midiNoteOn,.midiNoteOff:out.a=Int32(event.note!.pitch);out.b=Int32(event.midiKey!);out.token=Int32(event.instrument!);out.value=event.kind == .midiNoteOn ? Float(event.note!.velocity):0
            case .midiSustain,.midiClear:out.b=Int32(event.midiKey!)
            default:break
            }
            return out
        }
    }
    public static func event(_ raw:LGPerformanceEvent,source:Project)throws->PerformanceEvent {
        guard let kind=PerformanceEvent.Kind(rawValue:Int(raw.kind))else{throw MusicError.invalidProject}
        switch kind {
        case .section:guard raw.token>0,Int(raw.token)<=source.sections.count else{throw MusicError.invalidProject};return PerformanceEvent(frame:raw.frame,kind:kind,sectionID:source.sections[Int(raw.token)-1].id)
        case .pad:return PerformanceEvent(frame:raw.frame,kind:kind,value:Double(raw.value),track:1,pad:Int(raw.a))
        case .preview:return PerformanceEvent(frame:raw.frame,kind:kind,track:Int(raw.track),note:NoteEvent(tick:0,duration:Int((0.65*source.bpm/60*Double(ppq)).rounded()),pitch:Int(raw.a),velocity:Int(raw.value)),instrument:Int(raw.b))
        case .midiNoteOn,.midiNoteOff:return PerformanceEvent(frame:raw.frame,kind:kind,track:Int(raw.track),note:NoteEvent(tick:0,duration:1,pitch:Int(raw.a),velocity:kind == .midiNoteOn ? Int(raw.value):1),instrument:Int(raw.token),midiKey:Int(raw.b))
        case .midiSustain,.midiClear:return PerformanceEvent(frame:raw.frame,kind:kind,value:Double(raw.value),midiKey:Int(raw.b))
        case .gain,.pan:return PerformanceEvent(frame:raw.frame,kind:kind,value:Double(raw.value),track:Int(raw.track))
        default:return PerformanceEvent(frame:raw.frame,kind:kind,value:Double(raw.value))
        }
    }
}
