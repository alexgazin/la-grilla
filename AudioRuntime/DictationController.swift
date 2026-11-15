import AVFoundation
import Speech
import Observation

private final class SpeechRequestHandle:@unchecked Sendable {
    let request:SFSpeechAudioBufferRecognitionRequest
    init(_ request:SFSpeechAudioBufferRecognitionRequest){self.request=request}
}
private enum SpeechCallbacks {
    nonisolated static func receiver(_ request:SFSpeechAudioBufferRecognitionRequest)->LiveInputReceiver {
        let handle=SpeechRequestHandle(request)
        return LiveInputReceiver(receive:{ @Sendable [handle] buffer in handle.request.append(buffer)},finish:{ @Sendable [handle] in handle.request.endAudio()})
    }
    nonisolated static func recognize(_ recognizer:SFSpeechRecognizer,request:SFSpeechAudioBufferRecognitionRequest,update:@escaping @Sendable(String?,Bool,String?)->Void)->SFSpeechRecognitionTask {
        recognizer.recognitionTask(with:request){result,error in update(result?.bestTranscription.formattedString,result?.isFinal ?? false,error?.localizedDescription)}
    }
}

@MainActor @Observable final class DictationController {
    var recording=false;var requesting=false;var finalizing=false;var text="";var error:String?
    private var microphone:LiveMicrophone?
    private var request:SFSpeechAudioBufferRecognitionRequest?
    private var task:SFSpeechRecognitionTask?
    private var timeout:Task<Void,Never>?
    private var settling:Task<Void,Never>?
    private var generation=0
    func start(locale:String,audio:AudioController)async {
        guard !recording && !requesting && !finalizing else{return}
        cancelRecognition();requesting=true;error=nil;text="";let attempt=generation
        defer{if generation==attempt{requesting=false}}
        let authorized=await withCheckedContinuation{(continuation:CheckedContinuation<SFSpeechRecognizerAuthorizationStatus,Never>) in SFSpeechRecognizer.requestAuthorization{status in continuation.resume(returning:status)}}
        guard attempt==generation else{return}
        guard authorized == .authorized else{error=NSLocalizedString("Dictation permission was denied. You can still type a command.",comment:"");return}
        guard let recognizer=SFSpeechRecognizer(locale:Locale(identifier:locale)),recognizer.isAvailable,recognizer.supportsOnDeviceRecognition else{error=NSLocalizedString("On-device dictation is unavailable for this language. Type a command.",comment:"");return}
        let permitted=await AVAudioApplication.requestRecordPermission()
        guard attempt==generation else{return}
        guard permitted else{error=NSLocalizedString("Microphone access was denied. You can still type a command.",comment:"");return}
        do {
            let request=SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition=true;request.shouldReportPartialResults=true
            request.contextualStrings=["Am","C","F","G","BPM","tempo","Chorus","Intro","Verse","куплет","припев","бридж","тактов","поджазовать"]
            self.request=request
            task=SpeechCallbacks.recognize(recognizer,request:request){[weak self] text,final,error in Task{@MainActor in
                guard let self,self.generation==attempt else{return}
                if let text{self.text=String(text.prefix(2000))}
                if let error{self.error=error;self.cancelRecognition()}
                else if final{self.finishRecognition()}
            }}
            microphone=try LiveMicrophone(audio:audio,delay:0.05,duration:30,receiver:{_ in SpeechCallbacks.receiver(request)},onFailure:{[weak self] message in
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
        do{try microphone?.stop()}catch{self.error=error.localizedDescription}
        microphone=nil;recording=false;requesting=false;finalizing=false
        request?.endAudio();task=nil;request=nil
    }
    private func cancelRecognition(){
        generation+=1;timeout?.cancel();timeout=nil;settling?.cancel();settling=nil
        try? microphone?.stop();microphone=nil
        request?.endAudio();task?.cancel();task=nil;request=nil;recording=false;requesting=false;finalizing=false
    }
}
