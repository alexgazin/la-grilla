import Foundation

/// Shared editing rules for touch, accessibility and imported transcription.
public enum NoteEditing {
    public static func snapped(_ tick:Int,step:Int,length:Int,duration:Int)->Int {
        let grid=max(1,step)
        let bounded=max(0,min(length-max(1,duration),tick))
        return min(max(0,length-duration),Int((Double(bounded)/Double(grid)).rounded())*grid)
    }
    public static func insert(_ note:NoteEvent,into pattern:inout Pattern,step:Int=240)throws {
        guard pattern.length>0,note.duration>0 else{throw MusicError.invalidProject}
        var n=note;n.id=UUID();n.duration=min(n.duration,pattern.length)
        n.tick=snapped(n.tick,step:step,length:pattern.length,duration:n.duration)
        n.pitch=min(127,max(0,n.pitch));n.velocity=min(127,max(1,n.velocity))
        var notes=pattern.notes ?? []
        guard notes.count<4096 else{throw MusicError.tooDense}
        notes.append(n);pattern.notes=notes
    }
    public static func move(_ id:UUID,in pattern:inout Pattern,tick:Int,pitch:Int,step:Int=240) {
        guard let i=pattern.notes?.firstIndex(where:{$0.id==id}),let duration=pattern.notes?[i].duration else{return}
        pattern.notes?[i].tick=snapped(tick,step:step,length:pattern.length,duration:duration)
        pattern.notes?[i].pitch=min(127,max(0,pitch))
    }
    public static func resize(_ id:UUID,in pattern:inout Pattern,duration:Int,step:Int=240) {
        guard let i=pattern.notes?.firstIndex(where:{$0.id==id}),let tick=pattern.notes?[i].tick else{return}
        let grid=max(1,step)
        let snapped=max(grid,Int((Double(max(1,min(pattern.length,duration)))/Double(grid)).rounded())*grid)
        pattern.notes?[i].duration=max(1,min(pattern.length-tick,snapped))
    }
    public static func duplicate(_ id:UUID,in pattern:inout Pattern,step:Int=240)throws {
        guard var n=pattern.notes?.first(where:{$0.id==id})else{return}
        n.tick=min(pattern.length-n.duration,n.tick+n.duration)
        try insert(n,into:&pattern,step:step)
    }
}
