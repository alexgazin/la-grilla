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
    private struct Passage {
        let source: Range<Int>
        let start: Int
    }

    private static func sourcePassages(_ take: PerformanceTake) throws -> [Passage] {
        let sections = take.source.sections
        guard var section = sections.first(where: { $0.id == take.events.first?.sectionID }) else {
            throw MusicError.invalidProject
        }
        var position = section.start, clock = 0, passages: [Passage] = []
        func advance(_ end: Int) throws {
            while clock<end {
                let length=min(end-clock,section.start+section.length-position)
                guard length>0 else{throw MusicError.invalidProject}
                passages.append(Passage(source: position..<position + length, start: clock))
                clock+=length;position+=length
                if position>=section.start+section.length{position=section.start}
            }
        }
        for event in take.events where event.kind == .section || event.kind == .jump {
            try advance(tick(event, take))
            if event.kind == .section {
                guard let next = sections.first(where: { $0.id == event.sectionID }) else { throw MusicError.invalidProject }
                section = next
                position = section.start
            } else {
                let local = position - section.start + Int(event.value) * ppq
                position = section.start + ((local % section.length) + section.length) % section.length
            }
        }
        try advance(durationTicks(take))
        return passages
    }

    private static func repeatPassages(_ take: PerformanceTake) -> [Passage] {
        var result: [Passage] = [], clock = 0, repeatStart = 0, size = 0
        func emit(_ end: Int) {
            guard end > clock else { return }
            if size == 0 {
                result.append(Passage(source: clock..<end, start: clock))
            } else {
                let recorded = max(0, repeatStart - size)..<repeatStart
                var cursor = clock
                while cursor < end {
                    let phase = (cursor - repeatStart) % size
                    let length = min(end - cursor, size - phase)
                    let start = recorded.lowerBound + phase, finish = min(recorded.upperBound, start + length)
                    if finish > start { result.append(Passage(source: start..<finish, start: cursor)) }
                    cursor += length
                }
            }
            clock = end
        }
        for event in take.events where event.kind == .repeatSize {
            let t = tick(event, take)
            emit(t)
            repeatStart = t
            size = Int(event.value)
        }
        emit(durationTicks(take))
        return result
    }

    public static func backingNotes(_ take:PerformanceTake)throws->[CompiledNote] {
        try take.validate();let source=take.source,total=durationTicks(take)
        let compiled = Compiler.notes(source)
        var result: [CompiledNote] = []
        for passage in try sourcePassages(take) {
            result += slice(compiled, passage.source, offset: passage.start)
            guard result.count <= 200_000 else { throw MusicError.tooDense }
        }
        struct Held{var start:Int;var note:CompiledNote;var down:Bool}
        var held:[Int:Held]=[:],sustained:Set<Int>=[]
        func close(_ key:Int,_ t:Int){if let h=held.removeValue(forKey:key),t>h.start{var n=h.note;n.tick=h.start;n.duration=t-h.start;result.append(n)}}
        for event in take.events {
            let t=tick(event,take)
            switch event.kind {
            case .pad:if t<total{result.append(CompiledNote(tick:t,duration:min(120,total-t),pitch:Compiler.drumMap[event.pad!],velocity:Int(event.value),track:1,pad:event.pad!,instrument:1))}
            case .preview:if t<total,let note=event.note{result.append(CompiledNote(tick:t,duration:min(note.duration,total-t),pitch:note.pitch,velocity:note.velocity,track:event.track!,instrument:event.instrument!))}
            case .midiNoteOn:
                let key=event.midiKey!*128+event.note!.pitch;close(key,t)
                held[key]=Held(start:t,note:CompiledNote(tick:t,duration:1,pitch:event.note!.pitch,velocity:event.note!.velocity,track:event.track!,instrument:event.instrument!),down:true)
            case .midiNoteOff:
                let key=event.midiKey!*128+event.note!.pitch
                if sustained.contains(event.midiKey!){held[key]?.down=false}else{close(key,t)}
            case .midiSustain:
                let source=event.midiKey!
                if event.value>0{sustained.insert(source)}else{sustained.remove(source);for key in Array(held.keys) where key/128==source && held[key]?.down==false{close(key,t)}}
            case .midiClear:
                let source=event.midiKey!;for key in Array(held.keys) where key/128/16==source{close(key,t)};sustained=sustained.filter{$0/16 != source}
            default:break
            }
        }
        for key in Array(held.keys){close(key,total)};guard result.count<=200_000 else{throw MusicError.tooDense};return result.sorted{$0.tick==$1.tick ? $0.pitch<$1.pitch:$0.tick<$1.tick}
    }
    public static func notes(_ take:PerformanceTake)throws->[CompiledNote] {
        let backing = try backingNotes(take)
        var result: [CompiledNote] = []
        for passage in repeatPassages(take) {
            result += slice(backing, passage.source, offset: passage.start)
            guard result.count <= 200_000 else { throw MusicError.tooDense }
        }
        return result
    }

    /// Turn the musical parts of a take into independent clips. The exact
    /// audio performance, including its automation, stays attached as a take.
    public static func arrangement(_ take: PerformanceTake) throws -> Project {
        try take.validate()
        let source = take.source, ticks = durationTicks(take)
        let length = ((ticks + barTicks - 1) / barTicks) * barTicks
        var result = source
        let format = NSLocalizedString("%@ · Live", comment: "Project created from a performance")
        result.name = String(format: format, String(source.name.prefix(100)))
        result.sections = try form(take, length: length)
        result.performanceTake = take
        result.patterns = []
        let played = try notes(take)
        let chords = try performedChords(take)
        for index in result.tracks.indices {
            try Task.checkCancellation()
            let role = result.tracks[index].role
            result.tracks[index].clips = []
            guard role != .bass else { continue }
            let trackNotes = played.filter { $0.track == index }
            for section in result.sections {
                let range = section.start..<section.start + section.length
                var pattern = Pattern(length: section.length)
                switch role {
                case .harmony:
                    pattern.chords = chordSlice(chords, range, offset: 0)
                case .drums:
                    pattern.drums = trackNotes.compactMap { note in
                        guard note.pad >= 0, range.contains(note.tick) else { return nil }
                        return DrumEvent(tick: note.tick - section.start, pad: note.pad, velocity: note.velocity)
                    }
                case .melody:
                    pattern.notes = slice(trackNotes, range, offset: 0).map { note in
                        NoteEvent(tick: note.tick, duration: note.duration, pitch: note.pitch, velocity: note.velocity)
                    }
                case .bass: break
                }
                result.patterns.append(pattern)
                result.tracks[index].clips.append(Clip(patternID: pattern.id, start: section.start, length: section.length))
            }
        }
        try result.validate()
        return result
    }

    private static func form(_ take: PerformanceTake, length: Int) throws -> [Section] {
        var names: [(start: Int, name: String)] = []
        for event in take.events where event.kind == .section {
            guard let section = take.source.sections.first(where: { $0.id == event.sectionID }) else { throw MusicError.invalidProject }
            let barStart = ((tick(event, take) + barTicks / 2) / barTicks) * barTicks
            guard barStart < length else { continue }
            if names.last?.start == barStart { names[names.count - 1].name = section.name }
            else if names.count < 8 { names.append((barStart, section.name)) }
        }
        return names.enumerated().map { index, entry in
            let end = names.indices.contains(index + 1) ? names[index + 1].start : length
            return Section(name: entry.name, start: entry.start, length: end - entry.start)
        }
    }

    private static func chordSlice(_ chords: [ChordEvent], _ range: Range<Int>, offset: Int) -> [ChordEvent] {
        chords.compactMap { event in
            let begin = max(event.tick, range.lowerBound), end = min(event.tick + event.duration, range.upperBound)
            guard end > begin else { return nil }
            return ChordEvent(tick: begin - range.lowerBound + offset, duration: end - begin, chord: event.chord)
        }
    }

    private static func performedChords(_ take: PerformanceTake) throws -> [ChordEvent] {
        let source = take.source
        let harmony = Arrangement.materialize(source, track: source.tracks[0], section: Section(name: source.name, length: source.length))
        var backing: [ChordEvent] = []
        for passage in try sourcePassages(take) {
            backing += chordSlice(harmony.chords, passage.source, offset: passage.start)
            guard backing.count <= 16_384 else { throw MusicError.tooDense }
        }
        var result: [ChordEvent] = []
        for passage in repeatPassages(take) {
            result += chordSlice(backing, passage.source, offset: passage.start)
            guard result.count <= 16_384 else { throw MusicError.tooDense }
        }
        return result
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
