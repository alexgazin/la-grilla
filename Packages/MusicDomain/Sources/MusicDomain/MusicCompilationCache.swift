import Foundation

/// A single most-recent compilation, owned by the serialized control path.
/// This is a value cache, not a revision/UUID or hash-based promise: every input
/// read by Compiler.notes participates in the exact signature. Pattern and clip
/// arrays retain their copy-on-write storage; hits create no replacement arrays.
/// Audio layout, tempo, loop and generation publication remain the caller's job.
public struct MusicCompilationCache:Sendable {
    private struct TrackInput:Equatable,Sendable {
        let role:TrackRole
        let clips:[Clip]
    }
    private struct Inputs:Equatable,Sendable {
        let patterns:[Pattern]
        let tracks:[TrackInput]
        let length:Int
        let range:Range<Int>
        let bassOctave:Int
        let bassGate:Double

        init(_ project:Project,range:Range<Int>){
            patterns=project.patterns
            tracks=project.tracks.map{TrackInput(role:$0.role,clips:$0.clips)}
            length=project.length;self.range=range
            bassOctave=project.bassOctave;bassGate=project.bassGate
        }
        func matches(_ project:Project,range:Range<Int>)->Bool {
            guard self.range==range,length==project.length,
                  bassOctave==project.bassOctave,bassGate==project.bassGate,
                  patterns==project.patterns,tracks.count==project.tracks.count else{return false}
            // Do not build a temporary [TrackInput] on every fader move. Exact
            // array equality keeps COW's fast path while detecting in-place
            // musical edits even when project UUID/revision did not change.
            for index in tracks.indices {
                guard tracks[index].role==project.tracks[index].role,
                      tracks[index].clips==project.tracks[index].clips else{return false}
            }
            return true
        }
    }
    private struct Entry:Sendable {
        let inputs:Inputs
        let notes:[CompiledNote]
    }
    private var entry:Entry?
    /// Lifetime count of actual Compiler.notes calls; reset() releases the
    /// retained compilation without concealing earlier compilation work.
    public private(set) var compileCount=0
    public var retainedCompilationCount:Int{entry == nil ? 0:1}
    public var cachedNoteCount:Int{entry?.notes.count ?? 0}
    public init(){}

    public mutating func notes(_ project:Project,range:Range<Int>?=nil)->[CompiledNote] {
        let range=range ?? 0..<project.length
        if let entry,entry.inputs.matches(project,range:range){return entry.notes}
        let notes=Compiler.notes(project,range:range)
        entry=Entry(inputs:Inputs(project,range:range),notes:notes)
        if compileCount<Int.max{compileCount+=1}
        return notes
    }
    /// Drop the one retained signature/result when the owning renderer resets.
    /// A graph reprepare can reuse this pure music value; it does not authorize
    /// skipping the caller's new-kernel snapshot submission.
    public mutating func reset(){entry=nil}
}
