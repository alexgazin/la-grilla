import Foundation
import MusicDomain
import AudioDSP
import Observation

@MainActor @Observable final class PerformanceController {
    let audio:AudioController
    var contextActive=false;var playing=false;var recording=false;var starting=false;var replaying=false
    var stopping=false
    var runtimeProject:Project?;var activeSectionID:UUID?;var queuedSectionID:UUID?
    var repeatSize=480;var repeating=false;var seconds=0.0;var beatsToLaunch=0.0;var eventCount=0
    var error:String?;var notice:String?;var takeReady:PerformanceTake?
    @ObservationIgnored private var epoch=0
    @ObservationIgnored private var expectedCapture=false
    @ObservationIgnored private var frozenSource:Project?
    @ObservationIgnored private var events:[PerformanceEvent]=[]
    @ObservationIgnored private var requestedSequence:UInt64=0
    @ObservationIgnored private var startedAt=Date.distantPast
    @ObservationIgnored private(set) var replayTake:PerformanceTake?
    init(audio:AudioController){self.audio=audio}
    var fx:MasterFX{runtimeProject?.masterFX ?? MasterFX()}
    func begin(_ project:Project,sectionID:UUID,record:Bool)throws {
        guard !starting,!stopping,!recording,takeReady==nil else{return}
        var source=project;source.performanceTake=nil
        if let old=runtimeProject,contextActive,!replaying,old.tracks.map(\.id)==source.tracks.map(\.id){
            for i in source.tracks.indices{source.tracks[i].gain=old.tracks[i].gain;source.tracks[i].pan=old.tracks[i].pan;source.tracks[i].mute=old.tracks[i].mute;source.tracks[i].solo=old.tracks[i].solo};source.master=old.master;source.masterFX=old.masterFX
        }
        let solo=source.tracks.contains(where: \.solo)
        for i in source.tracks.indices{source.tracks[i].mute=source.tracks[i].mute || (solo && !source.tracks[i].solo);source.tracks[i].solo=false}
        guard let section=source.sections.first(where:{$0.id==sectionID})else{throw MusicError.invalidProject}
        try source.validate();if record{guard try JSONEncoder().encode(source).count<=2_000_000 else{throw MusicError.tooDense}}
        _ = audio.drainPerformance();events=[];eventCount=0;error=nil;notice=nil;requestedSequence=0
        runtimeProject=source;frozenSource=record ? source:nil;expectedCapture=record;replaying=false;replayTake=nil;contextActive=true;starting=true;startedAt=Date();activeSectionID=section.id;queuedSectionID=nil
        epoch=try audio.beginPerformance(source,section:section,token:source.sections.firstIndex(where:{$0.id==section.id})!+1,recording:record)
    }
    func playTake(_ take:PerformanceTake)throws {
        guard !recording,!starting,!stopping else{return};try take.validate()
        guard let first=take.events.first,let section=take.source.sections.first(where:{$0.id==first.sectionID})else{throw MusicError.invalidProject}
        let encoded=try PerformanceCodec.kernelEvents(take,targetRate:audio.sampleRate)
        let duration=UInt64((take.durationSeconds*audio.sampleRate).rounded())
        _ = audio.drainPerformance();events=[];eventCount=0;error=nil;notice=nil;requestedSequence=0;expectedCapture=false;frozenSource=nil
        runtimeProject=take.source;replayTake=take;contextActive=true;replaying=true;starting=true;startedAt=Date();activeSectionID=section.id;queuedSectionID=nil
        epoch=try audio.beginPerformance(take.source,section:section,token:take.source.sections.firstIndex(where:{$0.id==section.id})!+1,recording:false,replay:encoded,duration:duration)
    }
    func queueSection(_ id:UUID){
        guard playing,!replaying,let source=runtimeProject,let index=source.sections.firstIndex(where:{$0.id==id})else{return}
        let cancel=queuedSectionID==id,section=source.sections[index]
        let sequence=audio.withKernel{lg_perform_queue($0,1,0,Int32(cancel ? 0:section.start),Int32(cancel ? 0:section.start+section.length),Int32(cancel ? 0:index+1))} ?? 0
        if sequence==0{error="The performance control queue is full. Try again."}else{requestedSequence=sequence;queuedSectionID=cancel ? nil:id}
    }
    func jump(_ beats:Int){guard playing,!replaying else{return};if audio.withKernel({lg_perform_queue($0,2,Float(beats),0,0,0)})==0{error="The performance control queue is full. Try again."}}
    func toggleRepeat(){guard playing,!replaying else{return};let ticks=repeating ? 0:repeatSize;if audio.withKernel({lg_perform_queue($0,3,Float(ticks),0,0,0)})==0{error="The performance control queue is full. Try again."}}
    func setRepeatSize(_ ticks:Int){repeatSize=ticks;if repeating,!replaying{if audio.withKernel({lg_perform_queue($0,3,Float(ticks),0,0,0)})==0{error="The performance control queue is full. Try again."}}}
    func setEffects(filter:Double?=nil,delay:Double?=nil){
        guard contextActive,!replaying,var project=runtimeProject else{return};var value=project.masterFX ?? MasterFX();if let filter{value.filter=min(1,max(-1,filter))};if let delay{value.delayWet=min(0.5,max(0,delay))};project.masterFX=value;runtimeProject=project;audio.mix(project)
    }
    func editMix(_ change:(inout Project)throws->Void)throws {
        guard contextActive,!replaying,var value=runtimeProject else{return};let before=value;try change(&value)
        guard value.tracks.map(\.id)==before.tracks.map(\.id),value.patterns==before.patterns,value.sections==before.sections,value.master.isFinite,(-61...6).contains(value.master)else{throw MusicError.invalidProject}
        for track in value.tracks{guard track.gain.isFinite,(-61...6).contains(track.gain),track.pan.isFinite,(-1...1).contains(track.pan)else{throw MusicError.invalidProject}}
        runtimeProject=value;audio.mix(value)
    }
    func stopRecording(){guard recording else{return};audio.withKernel{lg_perform_record_stop($0)}}
    func panic(){guard !stopping else{return};stopping=true;audio.panic();repeating=false;queuedSectionID=nil;if var source=runtimeProject{source.masterFX=MasterFX();runtimeProject=source};Task{await finishStop();stopping=false}}
    func stop()async {
        if stopping{while stopping{try? await Task.sleep(for:.milliseconds(10))};return}
        stopping=true;defer{stopping=false};await finishStop()
    }
    private func finishStop()async {
        audio.stop();let deadline=Date().addingTimeInterval(1)
        while Date()<deadline {
            poll();if !(audio.withKernel{lg_perform_mode($0) != 0} ?? false){break}
            if !audio.isPrepared{audio.stopRenderAndFinalizePerformance();break}
            try? await Task.sleep(for:.milliseconds(10))
        }
        if audio.withKernel({lg_perform_mode($0) != 0})==true{audio.stopRenderAndFinalizePerformance()}
        poll();playing=false;starting=false
    }
    func exit()async {await stop();contextActive=false;replaying=false;replayTake=nil;queuedSectionID=nil;repeating=false;runtimeProject=nil}
    func finalizeBeforeReset(){audio.stopRenderAndFinalizePerformance();poll();playing=false;starting=false}
    private func collect(){
        let raw=audio.drainPerformance();guard expectedCapture,let source=frozenSource else{return}
        for event in raw where Int(event.epoch)==epoch{do{events.append(try PerformanceCodec.event(event,source:source))}catch{self.error=error.localizedDescription}}
        eventCount=events.count
    }
    func poll(){
        guard contextActive else{return};collect()
        guard let state=audio.withKernel({k in (Int(lg_perform_epoch(k)),lg_perform_mode(k) != 0,lg_perform_recording(k) != 0,Int(lg_perform_active_token(k)),Int(lg_perform_pending_token(k)),Int(lg_perform_repeat(k)),lg_perform_clock(k),lg_perform_duration(k),lg_perform_ack(k),Int(lg_perform_error(k)),Int(lg_perform_warning(k)))})else{return}
        guard state.0==epoch else{if starting && Date().timeIntervalSince(startedAt)>2{starting=false;error="The audio engine could not start the performance."};return}
        starting=false;playing=state.1 && audio.playing;recording=state.2;repeating=state.5 != 0;seconds=Double(state.6)/audio.sampleRate
        if let source=runtimeProject {
            if state.3>0,state.3<=source.sections.count{activeSectionID=source.sections[state.3-1].id}
            if state.8>=requestedSequence{queuedSectionID=state.4>0 && state.4<=source.sections.count ? source.sections[state.4-1].id:nil}
            let tick=seconds*source.bpm/60*Double(ppq);beatsToLaunch=(Double(barTicks)-tick.truncatingRemainder(dividingBy:Double(barTicks)))/Double(ppq)
        }
        if state.10==1{notice="Play the selected fragment once before using beat repeat."}
        if expectedCapture,!recording {
            collect();expectedCapture=false
            if let source=frozenSource,state.7>0 {
                let take=PerformanceTake(source:source,sampleRate:audio.sampleRate,durationFrames:state.7,events:events)
                do{try take.validate();takeReady=take;if state.9==1||state.9==2{notice="The automation limit was reached. The recorded part has been kept."}else if state.9==3{notice="The 64-bar performance limit was reached."}}
                catch{self.error=error.localizedDescription}
            }
            frozenSource=nil
        }
        if replaying,var project=runtimeProject {
            audio.withKernel{k in for i in project.tracks.indices{let gain=lg_gain_target(k,Int32(i));project.tracks[i].mute=gain<=0;if gain>0{project.tracks[i].gain=min(6,max(-61,20*log10(Double(gain))))};project.tracks[i].pan=Double(lg_pan_target(k,Int32(i)))};let master=lg_gain_target(k,Int32(masterBus));project.master=master>0 ? 20*log10(Double(master)):-61;project.masterFX=MasterFX(filter:Double(lg_filter_target(k)),delayWet:Double(lg_delay_target(k)))}
            runtimeProject=project
        }
    }
}
