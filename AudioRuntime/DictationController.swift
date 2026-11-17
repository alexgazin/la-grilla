import AVFoundation
import Foundation
import Speech
import Observation

private final class SpeechRequestHandle:@unchecked Sendable {
    let request:SFSpeechAudioBufferRecognitionRequest
    private let lock=NSLock()
    private var ended=false
    private var frames:UInt64=0
    init(_ request:SFSpeechAudioBufferRecognitionRequest){self.request=request}
    // Speech receives PCM on InputDrain's serial worker, never on the realtime
    // tap. Finish can also arrive from the main actor after a recognition result.
    // Serialize those two owners and end a request only once.
    func append(_ buffer:AVAudioPCMBuffer){
        lock.lock();defer{lock.unlock()}
        guard !ended else{return}
        request.append(buffer)
        frames+=UInt64(buffer.frameLength)
    }
    var receivedFrames:UInt64{lock.lock();defer{lock.unlock()};return frames}
    func endAudio(){
        lock.lock();defer{lock.unlock()}
        guard !ended else{return}
        ended=true;request.endAudio()
    }
}
private struct SpeechCallbackFailure:Sendable {
    let message:String
    let domain:String
    let code:Int
}
private enum SpeechCallbacks {
    nonisolated static func authorized()async->Bool {
        // The legacy framework callback can run off the main queue. Construct
        // it outside MainActor, as for the render/input callbacks, rather than
        // inheriting start()'s actor and trapping at the callback boundary.
        await withCheckedContinuation{(continuation:CheckedContinuation<Bool,Never>) in
            SFSpeechRecognizer.requestAuthorization{ @Sendable status in
                continuation.resume(returning:status == .authorized)
            }
        }
    }
    nonisolated static func receiver(_ handle:SpeechRequestHandle)->LiveInputReceiver {
        LiveInputReceiver(receive:{ @Sendable [handle] buffer in handle.append(buffer)},finish:{ @Sendable [handle] in handle.endAudio()})
    }
    nonisolated static func recognize(_ recognizer:SFSpeechRecognizer,request:SpeechRequestHandle,update:@escaping @MainActor @Sendable(String?,Bool,SpeechCallbackFailure?)->Void)->SFSpeechRecognitionTask {
        recognizer.recognitionTask(with:request.request){ @Sendable result,error in
            let text=result?.bestTranscription.formattedString
            let final=result?.isFinal ?? false
            let failure=error.map{error in let value=error as NSError;return SpeechCallbackFailure(message:error.localizedDescription,domain:String(value.domain.prefix(160)),code:value.code)}
            // Snapshot Sendable values on Speech's callback queue; framework
            // result/error objects never cross into the main-actor task.
            Task{@MainActor in update(text,final,failure)}
        }
    }
}

@MainActor @Observable final class DictationController {
    var recording=false;var requesting=false;var finalizing=false;var text="";var error:String?
    private var microphone:LiveMicrophone?
    private var recognizer:SFSpeechRecognizer?
    private var request:SpeechRequestHandle?
    private var task:SFSpeechRecognitionTask?
    private var timeout:Task<Void,Never>?
    private var settling:Task<Void,Never>?
    @ObservationIgnored private var qaFramesTask:Task<Void,Never>?
    private var observedFrames:UInt64=0
    private var everStartedCapture=false
    private var speechAvailable:Bool?
    private var supportsOnDeviceSpeech:Bool?
    private var speechErrorDomain:String?
    private var speechErrorCode:Int?
    private var lastInputStopMetrics:LiveInputStopMetrics?
    private var stopSynchronousMilliseconds:Double?
    private var generation=0
    /// Native tests read actual authorization and received PCM, never a supplied
    /// transcript or simulated permission result. No debug values reach normal UI.
    var diagnosticState:String {
        guard ProcessInfo.processInfo.arguments.contains("--uitesting")else{return ""}
        struct State:Encodable {
            let speechAuthorization:String,microphonePermission:String
            let recording:Bool,requesting:Bool,finalizing:Bool,everStartedCapture:Bool
            let receivedFrames:UInt64
            let speechAvailable:Bool?,supportsOnDeviceSpeech:Bool?,error:String?,speechErrorDomain:String?
            let speechErrorCode:Int?
            let inputStopMetrics:LiveInputStopMetrics?
            let stopSynchronousMilliseconds:Double?
        }
        let authorization:String=switch SFSpeechRecognizer.authorizationStatus(){case .authorized:"authorized";case .denied:"denied";case .restricted:"restricted";case .notDetermined:"notDetermined";@unknown default:"unknown"}
        let permission:String=switch AVAudioApplication.shared.recordPermission{case .granted:"granted";case .denied:"denied";case .undetermined:"undetermined";@unknown default:"unknown"}
        let state=State(speechAuthorization:authorization,microphonePermission:permission,recording:recording,requesting:requesting,finalizing:finalizing,everStartedCapture:everStartedCapture,receivedFrames:max(observedFrames,request?.receivedFrames ?? 0),speechAvailable:speechAvailable,supportsOnDeviceSpeech:supportsOnDeviceSpeech,error:error.map{String($0.prefix(1024))},speechErrorDomain:speechErrorDomain,speechErrorCode:speechErrorCode,inputStopMetrics:lastInputStopMetrics,stopSynchronousMilliseconds:stopSynchronousMilliseconds)
        guard let data=try? JSONEncoder().encode(state)else{return ""}
        return String(decoding:data,as:UTF8.self)
    }
    func start(locale:String,audio:AudioController)async {
        guard !recording && !requesting && !finalizing else{return}
        cancelRecognition();requesting=true;error=nil;text="";let attempt=generation
        lastInputStopMetrics=nil;stopSynchronousMilliseconds=nil
        observedFrames=0;everStartedCapture=false;speechAvailable=nil;supportsOnDeviceSpeech=nil;speechErrorDomain=nil;speechErrorCode=nil
        defer{if generation==attempt{requesting=false}}
        let authorized=await SpeechCallbacks.authorized()
        guard attempt==generation else{return}
        guard authorized else{error=NSLocalizedString("Dictation permission was denied. You can still type a command.",comment:"");return}
        let availableRecognizer=SFSpeechRecognizer(locale:Locale(identifier:locale))
        speechAvailable=availableRecognizer?.isAvailable;supportsOnDeviceSpeech=availableRecognizer?.supportsOnDeviceRecognition
        guard let recognizer=availableRecognizer,recognizer.isAvailable,recognizer.supportsOnDeviceRecognition else{error=NSLocalizedString("On-device dictation is unavailable for this language. Type a command.",comment:"");return}
        let permitted=await AVAudioApplication.requestRecordPermission()
        guard attempt==generation else{return}
        guard permitted else{error=NSLocalizedString("Microphone access was denied. You can still type a command.",comment:"");return}
        do {
            // Permission UI and route changes can leave the output graph stopped.
            // Recover it before creating a Speech task or taking the input lease.
            if !audio.isPrepared{try audio.prepare()}
            let request=SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition=true;request.shouldReportPartialResults=true
            request.contextualStrings=["Am","C","F","G","BPM","tempo","Chorus","Intro","Verse","куплет","припев","бридж","тактов","поджазовать"]
            let handle=SpeechRequestHandle(request)
            self.recognizer=recognizer;self.request=handle
            task=SpeechCallbacks.recognize(recognizer,request:handle){[weak self] text,final,error in
                guard let self,self.generation==attempt else{return}
                if let text{self.text=String(text.prefix(2000))}
                if let error{self.speechErrorDomain=error.domain;self.speechErrorCode=error.code;self.error=error.message;self.cancelRecognition()}
                else if final{self.finishRecognition()}
            }
            microphone=try LiveMicrophone(audio:audio,delay:0.05,duration:30,receiver:{_ in SpeechCallbacks.receiver(handle)},onFailure:{[weak self] message in
                guard let self,self.generation==attempt else{return};self.error=message;self.cancelRecognition()
            })
            recording=true;everStartedCapture=true
            if ProcessInfo.processInfo.arguments.contains("--uitesting") {
                // Publish actual first audio once, then retain the final count
                // when stopping. Repeated debug-only AX updates would keep UI
                // automation waiting for quiescence while capture is running.
                qaFramesTask=Task { @MainActor [weak self,handle] in
                    while let self,!Task.isCancelled,self.generation==attempt,self.recording {
                        self.observedFrames=handle.receivedFrames
                        if self.observedFrames>0{return}
                        do{try await Task.sleep(for:.milliseconds(100))}catch{return}
                    }
                }
            }
            timeout=Task{try? await Task.sleep(for:.seconds(30));guard !Task.isCancelled,self.generation==attempt else{return};self.stop()}
        }catch{self.error=error.localizedDescription;cancelRecognition()}
    }
    /// End the shared input tap immediately, then allow the on-device recognizer
    /// to finalize already submitted audio. No output engine is stopped/reset.
    func stop(){
        if requesting && !recording{cancelRecognition();return}
        guard recording || microphone != nil else{return}
        let started=DispatchTime.now().uptimeNanoseconds
        defer{stopSynchronousMilliseconds=Double(DispatchTime.now().uptimeNanoseconds-started)/1_000_000}
        timeout?.cancel();timeout=nil
        do{try stopInput()}catch{self.error=error.localizedDescription}
        microphone=nil;recording=false;requesting=false;finalizing=true
        retainFrameCount()
        request?.endAudio();task?.finish()
        let attempt=generation
        settling?.cancel();settling=Task{try? await Task.sleep(for:.seconds(2));guard !Task.isCancelled,self.generation==attempt else{return};self.finishRecognition()}
    }
    private func stopInput()throws {
        guard let microphone else{return}
        defer{lastInputStopMetrics=microphone.stopMetrics}
        try microphone.stop()
    }
    func cancel(){cancelRecognition()}
    private func retainFrameCount(){
        qaFramesTask?.cancel();qaFramesTask=nil
        observedFrames=max(observedFrames,request?.receivedFrames ?? 0)
    }
    private func finishRecognition(){
        generation+=1
        timeout?.cancel();timeout=nil;settling?.cancel();settling=nil
        // Recognition is already final (or its settling deadline expired).
        // Close Speech input before joining any still-pending PCM drain.
        request?.endAudio()
        do{try stopInput()}catch{self.error=error.localizedDescription}
        retainFrameCount()
        microphone=nil;recording=false;requesting=false;finalizing=false
        task?.cancel();task=nil;request=nil;recognizer=nil
    }
    private func cancelRecognition(){
        generation+=1;timeout?.cancel();timeout=nil;settling?.cancel();settling=nil
        request?.endAudio()
        try? stopInput();microphone=nil
        retainFrameCount()
        task?.cancel();task=nil;request=nil;recognizer=nil;recording=false;requesting=false;finalizing=false
    }
}
