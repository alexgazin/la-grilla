import Foundation
import MusicDomain

struct Samples:Codable {
    let rawMilliseconds:[Double]
    let medianMilliseconds:Double
    let p95Milliseconds:Double
    init(_ values:[Double]) {
        rawMilliseconds=values
        let ordered=values.sorted();medianMilliseconds=ordered[ordered.count/2]
        p95Milliseconds=ordered[min(ordered.count-1,Int(ceil(Double(ordered.count)*0.95))-1)]
    }
}
struct FixtureReceipt:Codable {
    let name:String
    let archiveBytes:Int
    let compiledNotes:Int
    let fullValidationMix:Samples
    let firstUncertifiedMix:Samples
    let certifiedContinuousMix:Samples
    let postUndoFirstMix:Samples
}
struct Receipt:Codable {
    let hostOnly=true
    let devicePerformanceVerified=false
    let realTimeAudioDeadlineVerified=false
    let optimizedBuild=true
    let runtime="Swift 6.1.2, Linux x86_64"
    let measurementMethod="DispatchTime uptime; 15 samples after one unrecorded warmup per operation. Full/uncertified start a fresh History per sample. Continuous reuses a genuinely validated History certificate and coalesces 0.01 dB fader changes. Post-Undo invalidates certificate before the measured call. Shared fixture PCM/compiler unchanged. No SwiftUI/Session/AVAudioEngine timing."
    let fixtures:[FixtureReceipt]
    let checksum:Int
}
@main enum Main {
    static func main()throws {
        let args=CommandLine.arguments
        guard args.count==3 else{fatalError("Usage fixture-root receipt-path")}
        var checksum=0,receipts:[FixtureReceipt]=[]
        func measured(_ operation:()throws->Int)rethrows->Samples {
            checksum &+= try operation()
            var raw:[Double]=[]
            for _ in 0..<15 {
                let start=DispatchTime.now().uptimeNanoseconds
                let value=try operation()
                let elapsed=Double(DispatchTime.now().uptimeNanoseconds-start)/1_000_000
                checksum &+= value;raw.append(elapsed)
            }
            return Samples(raw)
        }
        for level in [1,3] {
            let data=try Data(contentsOf:URL(fileURLWithPath:args[1]).appendingPathComponent("docs/release/fixtures/load-P\(level).grillapack"))
            let project=try PortableProject.decode(data,asCopy:false)
            let notes=Compiler.notes(project)
            guard notes.count==(level==1 ? 768:16384)else{fatalError("Changed musical fixture")}
            let full=try measured {
                var p=project;var history=History()
                try history.apply(&p){$0.tracks[0].gain -= 0.01}
                return p.revision+(history.canUndo ? 1:0)
            }
            let first=try measured {
                var p=project;var history=History()
                try history.applyMix(&p){$0.tracks[0].gain -= 0.01}
                return p.revision+(history.canUndo ? 1:0)
            }
            var live=project;var liveHistory=History()
            try liveHistory.applyMix(&live){$0.tracks[0].gain -= 0.01}
            let continuous=try measured {
                try liveHistory.applyMix(&live,coalescing:true){$0.tracks[0].gain -= 0.01}
                return live.revision+(liveHistory.canUndo ? 1:0)
            }
            var postUndoSamples:[Double]=[]
            for index in 0...15 {
                var p=project;var history=History()
                try history.applyMix(&p){$0.master -= 0.01}
                history.undo(&p)
                // Isolate revalidation after undo; setup above is intentionally
                // excluded below by this operation's own inner timing receipt.
                let start=DispatchTime.now().uptimeNanoseconds
                try history.applyMix(&p){$0.tracks[0].gain -= 0.01}
                let elapsed=Double(DispatchTime.now().uptimeNanoseconds-start)/1_000_000
                if index>0{postUndoSamples.append(elapsed)}
                checksum &+= p.revision
            }
            let postUndo=Samples(postUndoSamples)
            receipts.append(FixtureReceipt(name:"P\(level)",archiveBytes:data.count,compiledNotes:notes.count,fullValidationMix:full,firstUncertifiedMix:first,certifiedContinuousMix:continuous,postUndoFirstMix:postUndo))
        }
        let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
        try encoder.encode(Receipt(fixtures:receipts,checksum:checksum)).write(to:URL(fileURLWithPath:args[2]))
    }
}
