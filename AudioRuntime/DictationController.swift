import AVFoundation
import Foundation
import Speech
import Observation

private final class SpeechRequestHandle:@unchecked Sendable {
    let request:SFSpeechAudioBufferRecognitionRequest
    private let lock=NSLock()
    private var ended=false
    init(_ request:SFSpeechAudioBufferRecognitionRequest){self.request=request}
    // Speech receives PCM on InputDrain's serial worker, never on the realtime
    // tap. Finish can also arrive from the main actor after a recognition result.
    // Serialize those two owners and end a request only once.
    func append(_ buffer:AVAudioPCMBuffer){
        lock.lock();defer{lock.unlock()}
        guard !ended else{return}
        request.append(buffer)
    }
    func endAudio(){
        lock.lock();defer{lock.unlock()}
        guard !ended else{return}
        ended=true;request.endAudio()
    }
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
    nonisolated static func recognize(_ recognizer:SFSpeechRecognizer,request:SpeechRequestHandle,update:@escaping @MainActor @Sendable(String?,Bool,String?)->Void)->SFSpeechRecognitionTask {
        recognizer.recognitionTask(with:request.request){ @Sendable result,error in
            let text=result?.bestTranscription.formattedString
            let final=result?.isFinal ?? false
            let failure=error?.localizedDescription
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
    private var generation=0
    func start(locale:String,audio:AudioController)async {
        guard !recording && !requesting && !finalizing else{return}
        cancelRecognition();requesting=true;error=nil;text="";let attempt=generation
        defer{if generation==attempt{requesting=false}}
        let authorized=await SpeechCallbacks.authorized()
        guard attempt==generation else{return}
        guard authorized else{error=NSLocalizedString("Dictation permission was denied. You can still type a command.",comment:"");return}
        guard let recognizer=SFSpeechRecognizer(locale:Locale(identifier:locale)),recognizer.isAvailable,recognizer.supportsOnDeviceRecognition else{error=NSLocalizedString("On-device dictation is unavailable for this language. Type a command.",comment:"");return}
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
                if let error{self.error=error;self.cancelRecognition()}
                else if final{self.finishRecognition()}
            }
            microphone=try LiveMicrophone(audio:audio,delay:0.05,duration:30,receiver:{_ in SpeechCallbacks.receiver(handle)},onFailure:{[weak self] message in
                guard let self,self.generation==attempt else{return};self.error=message;self.cancelRecognition()
            })
            recording=true
            timeout=Task{try? await Task.sleep(for:.seconds(30));guard !Task.isCancelled,self.generation==attempt else{return};self.stop()}
        }catch{self.error=error.localizedDescription;cancelRecognition()}
    }
    /// End the shared input tap immediately, then allow the on-device recognizer
    /// to finalize already submitted audio. No output engine is stopped/reset.
    func stop(){
        if requesting && !recording{cancelRecognition();return}
        guard recording || microphone != nil else{return}
        timeout?.cancel();timeout=nil
        do{try microphone?.stop()}catch{self.error=error.localizedDescription}
        microphone=nil;recording=false;requesting=false;finalizing=true
        request?.endAudio();task?.finish()
        let attempt=generation
        settling?.cancel();settling=Task{try? await Task.sleep(for:.seconds(2));guard !Task.isCancelled,self.generation==attempt else{return};self.finishRecognition()}
    }
    func cancel(){cancelRecognition()}
    private func finishRecognition(){
        generation+=1
        timeout?.cancel();timeout=nil;settling?.cancel();settling=nil
        // Recognition is already final (or its settling deadline expired).
        // Close Speech input before joining any still-pending PCM drain.
        request?.endAudio()
        do{try microphone?.stop()}catch{self.error=error.localizedDescription}
        microphone=nil;recording=false;requesting=false;finalizing=false
        task?.cancel();task=nil;request=nil;recognizer=nil
    }
    private func cancelRecognition(){
        generation+=1;timeout?.cancel();timeout=nil;settling?.cancel();settling=nil
        request?.endAudio()
        try? microphone?.stop();microphone=nil
        task?.cancel();task=nil;request=nil;recognizer=nil;recording=false;requesting=false;finalizing=false
    }
}
