import AVFoundation
import AudioDSP
import Foundation
import MusicDomain

/// The signal is a scheduled instrument through the host HAL, never fabricated
/// microphone PCM or a supplied analysis result. This proves the production
/// recording/storage lifecycle, not human singing or pitch-detection accuracy.
@MainActor enum VoiceCaptureRuntimeQA {
    private struct Failure:LocalizedError {
        let message:String
        var errorDescription:String?{message}
    }
    private static func require(_ condition:Bool,_ message:String)throws {
        guard condition else{throw Failure(message:message)}
    }
    @MainActor private final class Continuity {
        let audio:AudioController
        let engine:AVAudioEngine
        let kernel:OpaquePointer
        let firstClock:UInt64
        let firstTick:Double
        let bpm:Double
        let rate:Double
        let length:Double
        let deadline:Date
        private var lastClock:UInt64
        private var task:Task<Void,Never>?
        private(set) var failure:Error?
        private(set) var samples=0
        private(set) var maximumPhaseError=0.0
        init(session:Session,deadline:Date)throws {
            let runtime=session.audio
            guard let engine=runtime.captureEngine,let kernel=runtime.withKernel({$0})else{throw Failure(message:"No shared voice-capture engine/kernel")}
            runtime.refreshClock()
            audio=runtime;self.deadline=deadline;self.engine=engine;self.kernel=kernel
            firstClock=runtime.clock;firstTick=runtime.tick;lastClock=runtime.clock
            bpm=session.project.bpm;rate=runtime.sampleRate;length=Double(session.loopRange.count)
            try check()
        }
        func check()throws {
            if let failure{throw failure}
            try VoiceCaptureRuntimeQA.require(Date()<deadline,"Production voice-capture lifecycle exceeded 33 seconds")
            audio.refreshClock()
            let sameKernel=audio.withKernel{$0==kernel} ?? false
            try VoiceCaptureRuntimeQA.require(sameKernel && audio.captureEngine===engine,"Voice lifecycle replaced the output engine or kernel")
            try VoiceCaptureRuntimeQA.require(audio.playing && audio.clock>=lastClock,"Voice lifecycle stopped or rewound the backing transport")
            lastClock=audio.clock
            let elapsed=Double(audio.clock-firstClock)*bpm*Double(ppq)/(60*rate)
            let expected=elapsed.truncatingRemainder(dividingBy:length)
            var actual=(audio.tick-firstTick).truncatingRemainder(dividingBy:length)
            if actual<0{actual+=length}
            let difference=abs(actual-expected),error=min(difference,length-difference)
            try VoiceCaptureRuntimeQA.require(error<128,"Production voice lifecycle changed the backing musical phase")
            maximumPhaseError=max(maximumPhaseError,error);samples+=1
        }
        func start(){
            task=Task{@MainActor [weak self] in
                while !Task.isCancelled {
                    guard let self else{return}
                    do{try self.check();try await Task.sleep(for:.milliseconds(20))}
                    catch is CancellationError{return}
                    catch{self.failure=error;return}
                }
            }
        }
        func stop(){task?.cancel();task=nil}
    }
    private struct Captured {
        let result:VoiceCaptureResult
        let plan:VoiceCapturePlan
        let route:LiveInputRouteSnapshot
        let states:[String]
    }
    private struct SourceProof {
        let frames:Int64
        let peak:Float
    }
    private struct Report:Encodable {
        let outcome="PASS"
        let signal="Scheduled monophonic instrument through actual host HAL/input tap; quiet backing drums continue. No injected PCM, synthetic analysis or human-voice accuracy claim."
        let source:AudioAssetRecord
        let sourceFrames:Int64
        let sourcePeak:Float
        let route:LiveInputRouteSnapshot
        let captureStates:[String]
        let detectedPitches:[Int]
        let reviewedPitches:[Int]
        let appliedTrackID:UUID
        let appliedRevision:Int
        let storedSourceMatches:Bool
        let storedProjectReopened:Bool
        let oneUndoRestoresBaseline:Bool
        let redoRestoresExactSourceAndNotes:Bool
        let sourceUnchangedAfterReview:Bool
        let sameEngineAndKernel:Bool
        let backingClockAdvanced:Bool
        let continuitySamples:Int
        let maximumPhaseErrorTicks:Double
        let elapsedSeconds:Double
        let outputHostTimingBaseline:AudioRuntimeQA.OutputHostTimingReport
        let outputHostTiming:AudioRuntimeQA.OutputHostTimingReport
        let physicalDropoutAbsenceVerified=false
        let referenceReusedWithoutPreparation:Bool
        let permissionBeforeCapture:String
        let permissionAfterCapture:String
    }
    static func run(_ session:Session,reusePreparedReference:Bool=false)async throws->String {
        let started=Date(),deadline=started.addingTimeInterval(33)
        if reusePreparedReference{try validatePreparedReference(session)}
        else{try await prepareReference(session,deadline:deadline)}
        let permissionBefore=permissionName(AVAudioApplication.shared.recordPermission)
        let baseline=session.project
        let monitor=try Continuity(session:session,deadline:deadline)
        monitor.start()
        let capture=VoiceCaptureController()
        defer{capture.discard();monitor.stop();session.audio.stop()}
        let baselineTiming=try await beginTiming(monitor)
        let captured=try await record(session,capture:capture,baseline:baseline,monitor:monitor)
        let proof=try validateSource(captured.result,planned:captured.plan.duration,bpm:baseline.bpm)
        try require(session.project==baseline,"Recording mutated the project before review/apply")
        let detected=try notes(captured,baseline:baseline)
        var reviewed=detected
        reviewed[0].pitch=reviewed[0].pitch<127 ? reviewed[0].pitch+1:reviewed[0].pitch-1
        try immutableSource(captured.result)
        try monitor.check()
        let placement=try Arrangement.voiceCandidate(baseline,sectionID:captured.plan.sectionID,target:nil,notes:reviewed,source:captured.result.record)
        let saved=try await session.applyVoice(placement,data:captured.result.data,record:captured.result.record,projectID:baseline.id,revision:baseline.revision)
        try require(saved && session.saveError==nil,"Captured source/notes could not be saved")
        try monitor.check()
        let applied=session.project
        try validatePlacement(applied,baseline:baseline,trackID:placement.trackID,sectionID:captured.plan.sectionID,reviewed:reviewed,source:captured.result.record)
        try await verifyStored(session,expected:applied,result:captured.result)
        try monitor.check()
        try await verifyHistory(session,baseline:baseline,applied:applied,result:captured.result,monitor:monitor)
        try immutableSource(captured.result)
        try monitor.check()
        try require(session.audio.clock>monitor.firstClock && monitor.samples>10,"No continuing backing callbacks were observed")
        let timing=try await readTiming(monitor,epoch:baselineTiming.epoch,minimumCallbacks:baselineTiming.callbacks+1)
        let report=Report(source:captured.result.record,sourceFrames:proof.frames,sourcePeak:proof.peak,route:captured.route,captureStates:captured.states,detectedPitches:detected.map(\.pitch),reviewedPitches:reviewed.map(\.pitch),appliedTrackID:placement.trackID,appliedRevision:applied.revision,storedSourceMatches:true,storedProjectReopened:true,oneUndoRestoresBaseline:true,redoRestoresExactSourceAndNotes:true,sourceUnchangedAfterReview:true,sameEngineAndKernel:true,backingClockAdvanced:true,continuitySamples:monitor.samples,maximumPhaseErrorTicks:monitor.maximumPhaseError,elapsedSeconds:Date().timeIntervalSince(started),outputHostTimingBaseline:.init(baselineTiming),outputHostTiming:.init(timing),referenceReusedWithoutPreparation:reusePreparedReference,permissionBeforeCapture:permissionBefore,permissionAfterCapture:permissionName(AVAudioApplication.shared.recordPermission))
        let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
        return String(decoding:try encoder.encode(report),as:UTF8.self)
    }
    private static func beginTiming(_ monitor:Continuity)async throws->LGOutputTiming {
        let epoch=lg_output_timing_begin(monitor.kernel)
        try require(epoch != 0,"Production voice output timing could not be armed")
        return try await readTiming(monitor,epoch:epoch,minimumCallbacks:8)
    }
    private static func readTiming(_ monitor:Continuity,epoch:UInt64,minimumCallbacks:UInt64)async throws->LGOutputTiming {
        while true {
            try monitor.check()
            var timing=LGOutputTiming()
            if lg_output_timing_read(monitor.kernel,&timing) != 0,timing.epoch==epoch,timing.comparedCallbacks>=8,timing.callbacks>=minimumCallbacks{return timing}
            try await Task.sleep(for:.milliseconds(20))
        }
    }
    private static func permissionName(_ value:AVAudioApplication.recordPermission)->String {
        value == .undetermined ? "undetermined":value == .granted ? "granted":"denied"
    }
    private static func validatePreparedReference(_ session:Session)throws {
        // The cold first-use path must not call prepare, edit, seek or play here:
        // it continues the exact graph/music observed before consent.
        try session.project.validate()
        let ready=session.audio.isPrepared && session.audio.playing && session.audio.appliedRevision==session.project.revision
        let reference=session.project.tracks.contains{$0.name=="Hardware loopback reference" && $0.role == .melody}
        try require(ready && reference && session.project.bpm==120 && session.loop && session.loopRange.count==2*barTicks,"Cold first-use reference is no longer running/prepared")
    }
    static func prepareReference(_ session:Session,deadline:Date)async throws {
        try session.audio.prepare()
        session.edit{project in
            project.bpm=120;project.masterFX=nil;project.midi=nil
            try project.duplicateSection(project.sections[0].id,name:"Loopback outro")
            try project.addMelody(name:"Hardware loopback reference")
            for index in project.tracks.indices {
                let role=project.tracks[index].role
                project.tracks[index].mute = role == .harmony || role == .bass
                project.tracks[index].solo=false
                if role == .drums{project.tracks[index].gain = -45}
            }
            let reference=project.tracks.count-1
            project.tracks[reference].gain = -3;project.tracks[reference].presetVersion=1
            for clip in project.tracks[reference].clips {
                guard let index=project.patterns.firstIndex(where:{$0.id==clip.patternID})else{throw MusicError.invalidProject}
                project.patterns[index].notes=[NoteEvent(tick:0,duration:ppq,pitch:60,velocity:110),NoteEvent(tick:2*ppq,duration:ppq,pitch:64,velocity:110),NoteEvent(tick:4*ppq,duration:ppq,pitch:67,velocity:110)]
            }
        }
        try require(session.project.tracks.last?.name=="Hardware loopback reference","Reference project edit was rejected")
        session.setLoop(bars:2,enabled:true)
        await session.save()
        try require(session.saveError==nil,"Reference project save failed")
        session.audio.seek(session.loopRange.lowerBound);session.audio.play()
        while Date()<deadline {
            session.audio.poll()
            if session.audio.playing && session.audio.clock>0 && session.audio.appliedRevision==session.project.revision{return}
            try await Task.sleep(for:.milliseconds(20))
        }
        throw Failure(message:"No actual reference backing callbacks")
    }
    private static func record(_ session:Session,capture:VoiceCaptureController,baseline:Project,monitor:Continuity)async throws->Captured {
        guard let owner=session.beginMicrophone(stop:{capture.stop()})else{throw Failure(message:"Production voice microphone lease rejected")}
        defer{session.endMicrophone(owner)}
        let category=AVAudioSession.sharedInstance().category
        var plan:VoiceCapturePlan?
        var scheduleFailure:String?
        await capture.start(audio:session.audio,bpm:baseline.bpm,duration:2.9,countIn:true,schedule:{lead in
            do {
                guard session.ownsMicrophone(owner),session.project==baseline else{throw AssistantError.stale}
                session.audio.refreshClock()
                let value=try VoiceCapturePlan.make(project:baseline,selectedSectionID:session.section.id,tick:session.audio.tick,playing:session.audio.playing,loop:true,range:session.loopRange,minimumLead:lead,maximumDuration:2.9)
                plan=value;return value.delay
            }catch{scheduleFailure=error.localizedDescription;return nil}
        },scheduleDuration:{plan?.duration})
        try monitor.check()
        guard let plan,capture.isCapturing else{throw Failure(message:scheduleFailure ?? capture.error ?? "Production VoiceCapture did not arm a real input")}
        let route=LiveInputRouteSnapshot.capture(monitor.engine,stage:"production-voice-input-armed")
        try require(route.isInputAvailable && (route.outputFormat.sampleRate ?? 0)>0,"Production capture has no actual input format")
        var states=[String(describing:capture.state)]
        while capture.state != .ready {
            try monitor.check()
            let state=String(describing:capture.state)
            if states.last != state{states.append(state)}
            if capture.state == .analyzing{session.endMicrophone(owner)}
            if let error=capture.error{throw Failure(message:error)}
            try await Task.sleep(for:.milliseconds(20))
        }
        states.append("ready");session.endMicrophone(owner)
        guard let result=capture.result else{throw Failure(message:"Production capture reached ready without an analyzed CAF")}
        try require(capture.error==nil && states.contains("recording"),"Production recording phase was not observed")
        try require(AVAudioSession.sharedInstance().category==category,"Voice analysis did not restore the output category")
        return Captured(result:result,plan:plan,route:route,states:states)
    }
    private static func validateSource(_ result:VoiceCaptureResult,planned:Double,bpm:Double)throws->SourceProof {
        try immutableSource(result)
        let file=try AVAudioFile(forReading:result.sourceURL,commonFormat:.pcmFormatFloat32,interleaved:false)
        let format=file.processingFormat,storedFormat=file.fileFormat
        try require(storedFormat.sampleRate==48000 && storedFormat.channelCount==1 && storedFormat.commonFormat == .pcmFormatFloat32,"Original CAF storage format is not mono Float32 48 kHz")
        try require(format.sampleRate==48000 && format.channelCount==1 && format.commonFormat == .pcmFormatFloat32 && !format.isInterleaved,"Production source is not mono Float32 48 kHz CAF")
        try require(file.length>0 && file.length<=144000,"Production CAF has invalid/unbounded frame count")
        let duration=Double(file.length)/48000
        try require(abs(duration-planned)<=1024.0/48000,"Production CAF lost capture frames or included count-in")
        let recordError=abs(result.record.duration-duration),analysisError=abs(result.analysis.duration-duration)
        let durationFacts=String(format:"fileFrames=%lld fileRate=%.17g fileDuration=%.17g recordDuration=%.17g analysisDuration=%.17g recordFrames=%.17g analysisFrames=%.17g recordError=%.17g analysisError=%.17g tolerance=%.17g sourceBytes=%lld",file.length,format.sampleRate,duration,result.record.duration,result.analysis.duration,result.record.duration*format.sampleRate,result.analysis.duration*format.sampleRate,recordError,analysisError,1.0/48000,Int64(result.data.count))
        try require(recordError<1.0/48000 && analysisError<1.0/48000,"CAF, source metadata and analysis durations disagree: "+durationFacts)
        try require(result.record.origin == .microphone && result.record.recordedAt != nil && result.record.inputLatencySeconds != nil && result.record.tempoBPM==bpm,"Production source capture provenance is missing")
        let declaredFrames=file.length
        // Independent inspection uses a different, non-dividing chunk size.
        // Verify actual decoded frames/peak, not one possibly short buffer.
        guard let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:997),file.framePosition==0 else{throw Failure(message:"Cannot allocate bounded source inspection")}
        var peak:Float=0,totalRead:AVAudioFramePosition=0
        while totalRead<declaredFrames {
            try Task.checkCancellation()
            let requested=AVAudioFrameCount(min(997,declaredFrames-totalRead)),position=file.framePosition
            buffer.frameLength=0
            try file.read(into:buffer,frameCount:requested)
            let actual=buffer.frameLength
            try require(actual>0 && actual<=requested && file.framePosition==position+AVAudioFramePosition(actual),"Original CAF read made no valid progress: decoded=\(totalRead) declared=\(declaredFrames) actual=\(actual) position=\(file.framePosition)")
            guard let values=buffer.floatChannelData?[0]else{throw Failure(message:"No CAF PCM channel")}
            for index in 0..<Int(actual){try require(values[index].isFinite,"Non-finite production source PCM");peak=max(peak,abs(values[index]))}
            totalRead+=AVAudioFramePosition(actual)
        }
        try require(totalRead==declaredFrames && file.framePosition==declaredFrames && file.length==declaredFrames,"Original CAF could not supply all declared frames")
        try require(peak>0.001,"Actual input CAF is silent; hardware loopback reference did not arrive")
        return SourceProof(frames:totalRead,peak:peak)
    }
    private static func immutableSource(_ result:VoiceCaptureResult)throws {
        let reread=try Data(contentsOf:result.sourceURL)
        try require(reread==result.data,"Original capture bytes changed during review/apply")
        try AssetIntegrity.validate(reread,record:result.record)
    }
    private static func notes(_ captured:Captured,baseline:Project)throws->[NoteEvent] {
        guard let section=baseline.sections.first(where:{$0.id==captured.plan.sectionID})else{throw Failure(message:"Capture target section is missing")}
        let source=VoiceAnalyzer.notes(captured.result.analysis,bpm:baseline.bpm,length:captured.plan.captureTicks)
        let projected=try captured.plan.place(source,sectionLength:section.length)
        try require(!projected.isEmpty,"Actual instrument loopback produced no stable analyzed notes; apply acceptance cannot be fabricated")
        return projected
    }
    private static func validatePlacement(_ project:Project,baseline:Project,trackID:UUID,sectionID:UUID,reviewed:[NoteEvent],source:AudioAssetRecord)throws {
        try project.validate()
        guard let section=project.sections.first(where:{$0.id==sectionID}),let track=project.tracks.first(where:{$0.id==trackID})else{throw Failure(message:"Applied melody destination is missing")}
        try require(project.audioAssets?.filter{$0.id==source.id}==[source],"Applied source record is missing, duplicated or altered")
        guard let clip=track.clips.first(where:{$0.start==section.start && $0.length==section.length}),let pattern=project.patterns.first(where:{$0.id==clip.patternID})else{throw Failure(message:"Applied melody clip/pattern is missing")}
        try require(clip.sourceAssetID==source.id && pattern.notes==reviewed,"Applied clip does not link the exact original source/reviewed notes")
        try require(project.tracks.filter{$0.id != trackID}==baseline.tracks && project.sections==baseline.sections,"Voice apply changed existing tracks or other sections")
        try require(baseline.patterns.allSatisfy{project.patterns.contains($0)},"Voice apply altered an existing pattern")
    }
    private static func verifyStored(_ session:Session,expected:Project,result:VoiceCaptureResult)async throws {
        let sourceURL=try await session.store.assetURL(result.record,projectID:expected.id)
        let stored=try Data(contentsOf:sourceURL)
        try require(stored==result.data,"Stored original CAF differs from captured bytes")
        try AssetIntegrity.validate(stored,record:result.record)
        let reopened=try await session.store.load(expected.id)
        try require(reopened==expected,"Reopening the real project package lost source/notes or revision")
    }
    private static func equivalent(_ a:Project,_ b:Project)->Bool {
        var left=a,right=b
        left.revision=0;right.revision=0
        left.modified=Date(timeIntervalSinceReferenceDate:0);right.modified=left.modified
        return left==right
    }
    private static func verifyHistory(_ session:Session,baseline:Project,applied:Project,result:VoiceCaptureResult,monitor:Continuity)async throws {
        session.undo()
        try require(equivalent(session.project,baseline),"One Undo did not restore the exact pre-capture music/source manifest")
        try monitor.check()
        session.redo()
        try require(equivalent(session.project,applied),"Redo did not restore exact reviewed notes/source IDs")
        await session.save()
        try require(session.saveError==nil,"Redo project save failed")
        try await verifyStored(session,expected:session.project,result:result)
        try monitor.check()
    }
}
