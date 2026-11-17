import AVFoundation
import AudioDSP
import Foundation
import MusicDomain

/// Explicit acceptance fixture: every recording transition is Session's normal
/// path and every clock/phase measurement comes from the running audio engine.
@MainActor enum DrumClipRuntimeQA {
    private struct Failure:LocalizedError {
        let message:String
        var errorDescription:String?{message}
    }
    private static func require(_ condition:Bool,_ message:String)throws{guard condition else{throw Failure(message:message)}}
    private static func wait(_ session:Session,deadline:Date,timeout:Double=3,stage:String,_ condition:()->Bool)async throws {
        let end=min(deadline,Date().addingTimeInterval(timeout))
        while Date()<end {
            try Task.checkCancellation()
            session.audio.poll()
            if condition(){return}
            try await Task.sleep(for:.milliseconds(20))
        }
        throw Failure(message:"Drum runtime timeout (\(stage)): tick=\(session.audio.tick), clock=\(session.audio.clock), playing=\(session.audio.playing), recording=\(session.recording), armed=\(session.armed), revision=\(session.project.revision), message=\(session.message ?? session.audio.error ?? "none")")
    }
    private static func kernel(_ audio:AudioController)throws->OpaquePointer {
        guard let pointer=audio.withKernel({$0})else{throw Failure(message:"Drum runtime has no live kernel")};return pointer
    }
    private static func fixture(bars:Int,bpm:Double,focusStart:Int,focusLength:Int)throws->Project {
        var project=Project(name:"Native drum acceptance",bars:bars);project.bpm=bpm
        project.patterns[1].length=barTicks
        project.patterns[1].drums=[DrumEvent(tick:0,pad:0),DrumEvent(tick:960,pad:1),DrumEvent(tick:2880,pad:2)]
        project.tracks[1].clips=[Clip(patternID:project.patterns[1].id,start:0,length:focusStart),Clip(patternID:project.patterns[1].id,start:focusStart,length:focusLength)]
        project.tracks[1].clips[1].offset=960
        try project.validate();return project
    }
    private static func install(_ project:Project,in session:Session,loop:Bool)throws {
        session.finishTake();session.saveTask?.cancel();session.endHarmonyPreview()
        session.project=project;session.history=History();session.message=nil
        session.loop=loop;session.countIn=false;session.overdub=true
        session.quantize = .sixteenth
        session.openDrumClip(project.tracks[1].clips[1].id)
        try require(session.drumClipID==project.tracks[1].clips[1].id,"Focused drum clip was not selected")
    }
    private struct Report:Encodable {
        let scenario:String
        let sampleRate:Double
        let elapsedSeconds:Double
        let loopClockFrames:UInt64
        let finiteClockFrames:UInt64
        let loopPhaseDifferenceTicks:Double
        let drumMeterPeak:Float
        let engineRetained:Bool
        let kernelRetained:Bool
        let focusedSourceIndependent:Bool
        let siblingClipUnchanged:Bool
        let sharedSourceUnchanged:Bool
        let originalHeardEventsPreserved:Bool
        let mixedGain:Double
        let mixedPan:Double
        let passesCrossed:Int
        let focusedNewPads:[Int]
        let oneUndoRedo:Bool
        let finiteNaturalStop:Bool
        let finiteRecordingUnlocked:Bool
        let finalPartialPassCommitted:Bool
        let outOfClipPadExcluded:Bool
        let finiteNewPads:[Int]
    }
    static func run(_ session:Session)async throws->String {
        let started=Date(),deadline=started.addingTimeInterval(30),audio=session.audio
        try audio.prepare()
        defer{session.finishTake();audio.stop()}
        audio.stop()
        try await wait(session,deadline:deadline,stage:"initial stop"){!audio.playing}
        let original=try fixture(bars:4,bpm:240,focusStart:2*barTicks,focusLength:2*barTicks)
        let sibling=original.tracks[1].clips[0],focused=original.tracks[1].clips[1],source=original.patterns[1]
        try install(original,in:session,loop:true)
        session.togglePlay()
        try await wait(session,deadline:deadline,stage:"focused loop start"){audio.playing && !audio.pendingSnapshot && audio.tick>=Double(focused.start)}
        let pointer=try kernel(audio)
        guard let engine=audio.captureEngine else{throw Failure(message:"Drum runtime has no AVAudioEngine")}
        audio.refreshClock();let clock=audio.clock,tick=audio.tick
        session.record()
        try require(session.armed || session.recording,"Session did not arm the focused drum take")
        try await wait(session,deadline:deadline,stage:"focused take arm"){session.recording && !session.armed && audio.playing}
        let firstPass=session.passClock
        session.hit(14)
        try await wait(session,deadline:deadline,stage:"first pad recording drain"){session.take.contains{$0.pad==14}}
        try require(session.take.filter{$0.pad==14}.count==1,"The first live pad did not enter the focused take exactly once")
        session.mixerImmediate{$0.tracks[1].gain = -14;$0.tracks[1].pan=0.25}
        let mixed=session.project
        try require(mixed.patterns==original.patterns && mixed.tracks[1].clips==original.tracks[1].clips,"Recording mutated source music before Finish")
        var peak:Float=0
        try await wait(session,deadline:deadline,stage:"actual drum output"){
            if audio.meters.indices.contains(1){peak=max(peak,audio.meters[1])};return peak>0.0001 && audio.playing
        }
        // Wait for Session.pollRecording to commit a complete real loop pass.
        // No direct commitPass invocation or synthetic clock can satisfy this.
        try await wait(session,deadline:deadline,timeout:4,stage:"complete focused pass"){session.passClock>firstPass && session.recording && audio.playing}
        let passesCrossed=Int((session.passClock-firstPass)/UInt64((Double(focused.length)/Double(ppq)*60/original.bpm*audio.sampleRate).rounded()))
        try require(session.project.patterns==mixed.patterns,"A pass created a separate project-history edit before Finish")
        guard let liveClip=session.displayProject.tracks[1].clips.first(where:{$0.id==focused.id}),let livePattern=session.displayProject.patterns.first(where:{$0.id==liveClip.patternID})else{throw Failure(message:"The live draft lost the focused clip")}
        try require(livePattern.drums.filter{$0.pad==14}.count==1,"The completed loop was not retained in the audible draft")
        session.hit(15)
        try await wait(session,deadline:deadline,stage:"second pad recording drain"){session.take.contains{$0.pad==15}}
        try require(session.take.filter{$0.pad==15}.count==1,"The second-pass live pad was not captured exactly once")
        session.finishTake()
        let finished=session.project
        try require(!session.recording && !session.armed,"Finish left the drum recording lock active")
        guard let changedClip=finished.tracks[1].clips.first(where:{$0.id==focused.id}),let changedPattern=finished.patterns.first(where:{$0.id==changedClip.patternID})else{throw Failure(message:"Finished take lost its clip or pattern")}
        let independent=changedClip.patternID != source.id && changedClip.offset==0 && changedClip.length==focused.length && changedClip.start==focused.start && changedPattern.length==focused.length
        let siblingSame=finished.tracks[1].clips.first(where:{$0.id==sibling.id})==sibling
        let sourceSame=finished.patterns.first(where:{$0.id==source.id})==source
        let heardSame=Compiler.notes(finished,range:0..<focused.start)==Compiler.notes(original,range:0..<focused.start)
        let originalFocusedEvents=Arrangement.materialize(original,track:original.tracks[1],section:MusicDomain.Section(name:"Heard clip",start:focused.start,length:focused.length)).drums
        let preserved=changedPattern.drums.filter{$0.pad<3}.map{[$0.tick,$0.pad,$0.velocity]}==originalFocusedEvents.map{[$0.tick,$0.pad,$0.velocity]}
        let newPads=changedPattern.drums.filter{$0.pad>=14}.map(\.pad).sorted()
        try require(independent && siblingSame && sourceSame && heardSame && preserved,"Focused recording altered a shared source, sibling clip, offset/repeated notes or clip boundaries")
        try require(newPads==[14,15] && changedPattern.drums.filter{$0.pad>=14}.allSatisfy{$0.tick%240==0 && $0.tick<focused.length},"Recorded pads were duplicated, outside the clip, or not quantized")
        try require(finished.tracks[1].gain == -14 && finished.tracks[1].pan==0.25 && finished.revision==mixed.revision+1,"Finish lost the mixer edit or committed more than one project transaction")
        try await wait(session,deadline:deadline,stage:"finished take adoption"){!audio.pendingSnapshot && audio.playing}
        session.undo()
        let oneUndo=session.project.patterns==mixed.patterns && session.project.tracks==mixed.tracks && session.project.sections==mixed.sections
        try require(oneUndo && session.history.canRedo,"One Undo did not restore the exact pre-take music while retaining its mixer edit")
        try await wait(session,deadline:deadline,stage:"Undo adoption"){!audio.pendingSnapshot && audio.playing}
        session.redo()
        let oneRedo=session.project.patterns==finished.patterns && session.project.tracks==finished.tracks
        try require(oneRedo,"Redo did not restore the complete multi-pass take")
        try await wait(session,deadline:deadline,stage:"Redo adoption"){!audio.pendingSnapshot && audio.playing}
        audio.refreshClock()
        try require(audio.clock>clock && audio.captureEngine===engine && (try kernel(audio))==pointer,"Recording/Undo/Redo reset or replaced the live engine/kernel/clock")
        let loopFrames=audio.clock-clock,length=Double(focused.length)
        let expected=(Double(loopFrames)*original.bpm*Double(ppq)/(60*audio.sampleRate)).truncatingRemainder(dividingBy:length)
        let actual=(audio.tick-tick+length).truncatingRemainder(dividingBy:length)
        let difference=abs(actual-expected),phaseDifference=min(difference,length-difference)
        try require(phaseDifference<128,"Focused recording/Undo/Redo changed live musical phase")

        // A later recording starts during a finite arrangement. It ends before
        // one recording pass, so only the natural-stop finalization can save it.
        audio.stop();try await wait(session,deadline:deadline,stage:"finite setup stop"){!audio.playing}
        let finite=try fixture(bars:4,bpm:120,focusStart:barTicks,focusLength:barTicks)
        let finiteClip=finite.tracks[1].clips[1],finiteSource=finite.patterns[1],finiteSibling=finite.tracks[1].clips[0]
        try install(finite,in:session,loop:false)
        session.quantize = .off;session.rewind()
        try await wait(session,deadline:deadline,stage:"finite rewind"){!audio.playing}
        session.togglePlay()
        try await wait(session,deadline:deadline,stage:"finite playback"){audio.playing && audio.tick>0 && audio.tick<Double(barTicks)}
        let finiteClock=audio.clock
        session.record()
        try await wait(session,deadline:deadline,timeout:4,stage:"finite arm inside focused clip"){session.recording && audio.tick>=Double(finiteClip.start+240) && audio.tick<Double(finiteClip.start+finiteClip.length-240)}
        let partialStart=session.passClock
        session.hit(13)
        try await wait(session,deadline:deadline,stage:"finite pad recording drain"){session.take.contains{$0.pad==13}}
        try require(session.take.filter{$0.pad==13}.count==1,"Finite focused pad was not captured")
        try await wait(session,deadline:deadline,timeout:4,stage:"outside focused clip"){audio.playing && session.recording && audio.tick>=Double(finiteClip.start+finiteClip.length+240)}
        let captured=session.take.count
        session.hit(12)
        // Observe the ordinary poll draining the new contact before checking
        // that it was excluded; checking an undrained queue could pass vacuously.
        audio.poll()
        try require(session.take.count==captured && !session.rawHits.contains{$0.event.pad==12},"An out-of-clip touch wrapped into the focused pattern")
        try await wait(session,deadline:deadline,timeout:5,stage:"natural finite end"){!audio.playing && !session.recording && !session.armed}
        try await wait(session,deadline:deadline,stage:"finite take adoption"){!audio.pendingSnapshot}
        let finiteResult=session.project
        guard let finalClip=finiteResult.tracks[1].clips.first(where:{$0.id==finiteClip.id}),let finalPattern=finiteResult.patterns.first(where:{$0.id==finalClip.patternID})else{throw Failure(message:"Natural stop lost the final partial take")}
        let finitePads=finalPattern.drums.filter{$0.pad>=12}.map(\.pad).sorted()
        let partialCommitted=finitePads==[13] && finiteResult.revision==finite.revision+1 && session.passClock==partialStart
        let outsideExcluded = !finiteResult.patterns.contains{$0.drums.contains{$0.pad==12}}
        try require(partialCommitted && outsideExcluded && finalClip.patternID != finiteSource.id,"Natural end did not commit precisely the final partial take")
        try require(finiteResult.patterns.first(where:{$0.id==finiteSource.id})==finiteSource && finiteResult.tracks[1].clips.first(where:{$0.id==finiteSibling.id})==finiteSibling,"Finite take changed its shared source or sibling")
        let naturalStop = !audio.playing,unlocked = !session.recording && !session.armed
        session.undo()
        try require(session.project.patterns==finite.patterns && session.project.tracks==finite.tracks,"The naturally finished take was not one Undo")
        session.redo()
        try require(session.project.patterns==finiteResult.patterns && session.project.tracks==finiteResult.tracks,"Finite take Redo lost its recorded note")
        audio.refreshClock()
        let engineSame=audio.captureEngine===engine,kernelSame=(try kernel(audio))==pointer
        try require(engineSame && kernelSame && audio.clock>finiteClock,"Finite recording replaced the engine/kernel or reset the actual clock")
        let report=Report(scenario:"focused-drum-clip",sampleRate:audio.sampleRate,elapsedSeconds:Date().timeIntervalSince(started),loopClockFrames:loopFrames,finiteClockFrames:audio.clock-finiteClock,loopPhaseDifferenceTicks:phaseDifference,drumMeterPeak:peak,engineRetained:engineSame,kernelRetained:kernelSame,focusedSourceIndependent:independent,siblingClipUnchanged:siblingSame,sharedSourceUnchanged:sourceSame,originalHeardEventsPreserved:preserved,mixedGain:finished.tracks[1].gain,mixedPan:finished.tracks[1].pan,passesCrossed:passesCrossed,focusedNewPads:newPads,oneUndoRedo:oneUndo && oneRedo,finiteNaturalStop:naturalStop,finiteRecordingUnlocked:unlocked,finalPartialPassCommitted:partialCommitted,outOfClipPadExcluded:outsideExcluded,finiteNewPads:finitePads)
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        return String(decoding:try encoder.encode(report),as:UTF8.self)
    }
}
