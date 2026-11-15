import AVFoundation
import Speech
import Observation

private final class SpeechRequestHandle:@unchecked Sendable {
    let request:SFSpeechAudioBufferRecognitionRequest
    init(_ request:SFSpeechAudioBufferRecognitionRequest){self.request=request}
}
private enum SpeechCallbacks {
    nonisolated static func install(_ input:AVAudioInputNode,request:SFSpeechAudioBufferRecognitionRequest,format:AVAudioFormat){
        let handle=SpeechRequestHandle(request)
        input.installTap(onBus:0,bufferSize:1024,format:format){ @Sendable [handle] buffer,_ in handle.request.append(buffer)}
    }
    nonisolated static func recognize(_ recognizer:SFSpeechRecognizer,request:SFSpeechAudioBufferRecognitionRequest,update:@escaping @Sendable(String?,Bool,String?)->Void)->SFSpeechRecognitionTask {
        recognizer.recognitionTask(with:request){result,error in update(result?.bestTranscription.formattedString,result?.isFinal ?? false,error?.localizedDescription)}
    }
}

@MainActor @Observable final class DictationController {
    var recording=false;var requesting=false;var text="";var error:String?
    private var engine:AVAudioEngine?;private var request:SFSpeechAudioBufferRecognitionRequest?;private var task:SFSpeechRecognitionTask?;private var timeout:Task<Void,Never>?
    private var generation=0
    func start(locale:String)async {
        guard !recording && !requesting else{return};requesting=true;error=nil;text="";generation+=1;let attempt=generation
        defer{requesting=false}
        let authorized=await withCheckedContinuation{(continuation:CheckedContinuation<SFSpeechRecognizerAuthorizationStatus,Never>) in SFSpeechRecognizer.requestAuthorization{status in continuation.resume(returning:status)}}
        guard attempt==generation else{return}
        guard authorized == .authorized else{error=NSLocalizedString("Dictation permission was denied. You can still type a command.",comment:"");return}
        let microphone=await AVAudioApplication.requestRecordPermission()
        guard attempt==generation else{return}
        guard microphone else{error=NSLocalizedString("Microphone access was denied. You can still type a command.",comment:"");return}
        guard let recognizer=SFSpeechRecognizer(locale:Locale(identifier:locale)),recognizer.isAvailable,recognizer.supportsOnDeviceRecognition else{error=NSLocalizedString("On-device dictation is unavailable for this language. Type a command.",comment:"");return}
        do {
            let session=AVAudioSession.sharedInstance();try session.setCategory(.record,mode:.measurement,options:[]);try session.setActive(true)
            let engine=AVAudioEngine(),request=SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition=true;request.shouldReportPartialResults=true
            request.contextualStrings=["Am","C","F","G","BPM","tempo","Chorus","куплет","припев","тактов"]
            let format=engine.inputNode.outputFormat(forBus:0)
            guard format.sampleRate>0,format.channelCount>0 else{throw NSError(domain:"LaGrilla.Dictation",code:1,userInfo:[NSLocalizedDescriptionKey:NSLocalizedString("No microphone is available.",comment:"")])}
            SpeechCallbacks.install(engine.inputNode,request:request,format:format)
            self.engine=engine;self.request=request
            task=SpeechCallbacks.recognize(recognizer,request:request){[weak self] text,final,error in Task { @MainActor in
                guard let self,self.generation==attempt else{return}
                if let text{self.text=String(text.prefix(2000))}
                if let error{self.error=error;self.stop()}
                else if final{self.stop()}
            }}
            engine.prepare();try engine.start();recording=true
            timeout=Task{try? await Task.sleep(for:.seconds(30));guard !Task.isCancelled,self.generation==attempt else{return};self.stop()}
        }catch{self.error=error.localizedDescription;stop()}
    }
    func stop(){
        generation+=1;timeout?.cancel();timeout=nil
        if let engine{engine.stop();engine.inputNode.removeTap(onBus:0)}
        request?.endAudio();task?.cancel();task=nil;request=nil;engine=nil;recording=false
    }
}
