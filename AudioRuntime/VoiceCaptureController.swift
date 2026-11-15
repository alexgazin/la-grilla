import Foundation
import AVFoundation
import Observation
import MusicDomain

struct VoiceCaptureResult:Sendable {
    let sourceURL:URL;let data:Data;let record:AudioAssetRecord;let analysis:VoiceAnalysis
}
private enum VoiceSourceIO {
    nonisolated static func write(_ samples:[Float],to url:URL)throws {
        let format=AVAudioFormat(commonFormat:.pcmFormatFloat32,sampleRate:48000,channels:1,interleaved:false)!
        let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:AVAudioFrameCount(samples.count))!
        buffer.frameLength=AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer{source in buffer.floatChannelData![0].update(from:source.baseAddress!,count:source.count)}
        let file=try AVAudioFile(forWriting:url,settings:format.settings);try file.write(from:buffer)
    }
    nonisolated static func countIn(to url:URL,bpm:Double)throws {
        let length=Int((240/bpm*48000).rounded());var samples=[Float](repeating:0,count:length)
        for beat in 0..<4{let start=Int((Double(beat)*60/bpm*48000).rounded());for frame in 0..<min(2400,length-start){let t=Double(frame)/48000;samples[start+frame]=Float(sin(2*Double.pi*(beat==0 ? 2200:1600)*t)*exp(-t*100)*0.5)}}
        try write(samples,to:url)
    }
    nonisolated static func fixture(to url:URL)throws {
        // Native fixture exercises the same off-tap conversion/file sink as a
        // 44.1 kHz input route; it remains explicitly synthetic in UI/metadata.
        let rate=44100,voiceFrames=35280
        var samples=[Float](repeating:0,count:rate*3)
        for (index,pitch) in [60,64,67].enumerated(){let hz=440*pow(2,Double(pitch-69)/12);for frame in 0..<voiceFrames{let t=Double(frame)/Double(rate);let gain=min(1,t/0.01,Double(voiceFrames-1-frame)/Double(rate)/0.01);samples[index*rate+frame]=Float(sin(2*Double.pi*hz*t)*gain*0.6)}}
        let format=AVAudioFormat(commonFormat:.pcmFormatFloat32,sampleRate:Double(rate),channels:1,interleaved:false)!
        let receiver=try VoicePCMSink.receiver(url:url,input:format)
        for start in stride(from:0,to:samples.count,by:997){
            let count=min(997,samples.count-start),buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:AVAudioFrameCount(count))!
            buffer.frameLength=AVAudioFrameCount(count)
            samples.withUnsafeBufferPointer{buffer.floatChannelData![0].update(from:$0.baseAddress!.advanced(by:start),count:count)}
            try receiver.receive(buffer)
        }
        try receiver.finish()
    }
    nonisolated static func analyze(_ url:URL,recordedAt:Date?,inputLatency:Double?,tempoBPM:Double?,origin:AudioAssetRecord.Origin,progress:@escaping @Sendable(Double)->Void)throws->VoiceCaptureResult {
        let count=try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
        guard (64...12_000_000).contains(count)else{throw VoiceAnalysisError.invalidInput}
        let file=try AVAudioFile(forReading:url,commonFormat:.pcmFormatFloat32,interleaved:false)
        let rate=file.processingFormat.sampleRate
        guard file.processingFormat.channelCount==1,file.length>0,Double(file.length)<=rate*30.25 else{throw VoiceAnalysisError.invalidInput}
        guard let buffer=AVAudioPCMBuffer(pcmFormat:file.processingFormat,frameCapacity:AVAudioFrameCount(file.length))else{throw VoiceAnalysisError.invalidInput}
        try file.read(into:buffer)
        guard let channel=buffer.floatChannelData?[0]else{throw VoiceAnalysisError.invalidInput}
        let samples=Array(UnsafeBufferPointer(start:channel,count:Int(buffer.frameLength)))
        let data=try Data(contentsOf:url),duration=Double(buffer.frameLength)/rate
        let record=AudioAssetRecord(sha256:try AssetIntegrity.sha256(data),byteCount:data.count,sampleRate:rate,duration:duration,origin:origin,recordedAt:recordedAt,inputLatencySeconds:inputLatency,tempoBPM:tempoBPM)
        try AssetIntegrity.validate(data,record:record)
        let analysis=try VoiceAnalyzer.analyze(samples,sampleRate:rate,progress:progress)
        return VoiceCaptureResult(sourceURL:url,data:data,record:record,analysis:analysis)
    }
}

/// The converter invokes its input block synchronously from one serial drain
/// call. This box transfers buffer ownership into that block without capturing
/// a mutable local or sharing the PCM buffer with an unrelated executor.
private final class VoiceConversionInput:@unchecked Sendable {
    private let buffer:AVAudioPCMBuffer
    private var supplied=false
    init(_ buffer:AVAudioPCMBuffer){self.buffer=buffer}
    func next(_ state:UnsafeMutablePointer<AVAudioConverterInputStatus>)->AVAudioBuffer? {
        if supplied{state.pointee = .noDataNow;return nil}
        supplied=true;state.pointee = .haveData;return buffer
    }
}

/// AVAudioFile and converter are confined to the input drain's serial worker.
/// The original capture remains mono 48 kHz Float32 CAF regardless of input route.
private final class VoicePCMSink:@unchecked Sendable {
    private var file:AVAudioFile?
    private let converter:AVAudioConverter?
    private let outputFormat:AVAudioFormat
    init(url:URL,input:AVAudioFormat)throws {
        guard let output=AVAudioFormat(commonFormat:.pcmFormatFloat32,sampleRate:48000,channels:1,interleaved:false)else{throw VoiceAnalysisError.invalidInput}
        outputFormat=output
        file=try AVAudioFile(forWriting:url,settings:output.settings)
        if input.sampleRate==48000{converter=nil}
        else{guard let value=AVAudioConverter(from:input,to:output)else{throw VoiceAnalysisError.invalidInput};value.primeMethod = .none;converter=value}
    }
    nonisolated static func receiver(url:URL,input:AVAudioFormat)throws->LiveInputReceiver {
        let sink=try VoicePCMSink(url:url,input:input)
        return LiveInputReceiver(receive:{ @Sendable [sink] buffer in try sink.append(buffer)},finish:{ @Sendable [sink] in try sink.finish()})
    }
    private func append(_ buffer:AVAudioPCMBuffer)throws {
        guard let file else{throw VoiceAnalysisError.invalidInput}
        guard let converter else{try file.write(from:buffer);return}
        let capacity=AVAudioFrameCount(ceil(Double(buffer.frameLength)*48000/buffer.format.sampleRate)+64)
        guard let output=AVAudioPCMBuffer(pcmFormat:outputFormat,frameCapacity:capacity)else{throw VoiceAnalysisError.invalidInput}
        let input=VoiceConversionInput(buffer)
        var failure:NSError?
        let status=converter.convert(to:output,error:&failure){ @Sendable [input] _,state in input.next(state) }
        if status == .error{throw failure ?? VoiceAnalysisError.invalidInput as NSError}
        if output.frameLength>0{try file.write(from:output)}
    }
    private func finish()throws {
        defer{file=nil}
        guard let file,let converter else{return}
        for _ in 0..<8 {
            guard let output=AVAudioPCMBuffer(pcmFormat:outputFormat,frameCapacity:4096)else{throw VoiceAnalysisError.invalidInput}
            var failure:NSError?
            let status=converter.convert(to:output,error:&failure){_,state in state.pointee = .endOfStream;return nil}
            if status == .error{throw failure ?? VoiceAnalysisError.invalidInput as NSError}
            if output.frameLength>0{try file.write(from:output)}
            if status == .endOfStream || output.frameLength==0{return}
        }
        throw VoiceAnalysisError.invalidInput
    }
}

@MainActor @Observable final class VoiceCaptureController {
    enum State:Equatable {case idle,preparing,waiting,countIn,recording,analyzing,ready}
    var state:State = .idle;var result:VoiceCaptureResult?;var error:String?
    var elapsed=0.0;var remaining=4;var waitingSeconds=0.0;var plannedDuration=0.0;var level=0.0;var progress=0.0;var originalPlaying=false
    var isCapturing:Bool{state == .preparing || state == .waiting || state == .countIn || state == .recording}
    private var microphone:LiveMicrophone?
    private var countPlayer:AVAudioPlayer?;private var originalPlayer:AVAudioPlayer?
    private var timer:Timer?;private var worker:Task<VoiceCaptureResult,Error>?
    private var generation=0;private var recordedAt:Date?;private var inputLatency:Double?;private var tempoBPM:Double?;private var origin:AudioAssetRecord.Origin = .microphone;private var activeURL:URL?
    func start(audio:AudioController,bpm:Double,duration:Double,countIn:Bool,schedule:(@MainActor(Double)->Double?)?=nil,scheduleDuration:(@MainActor()->Double?)?=nil)async {
        guard !isCapturing,state != .analyzing else{return};stopOriginal();state = .preparing;plannedDuration=0;waitingSeconds=0;elapsed=0;level=0;error=nil;generation+=1;let attempt=generation
        let permission=await AVAudioApplication.requestRecordPermission()
        guard attempt==generation else{return}
        guard permission else{error=NSLocalizedString("Microphone access was denied. You can still write notes in Piano roll.",comment:"");state=result==nil ? .idle:.ready;return}
        do {
            guard bpm.isFinite,(40...240).contains(bpm),duration.isFinite,duration>0 else{throw VoiceAnalysisError.invalidInput}
            let folder=FileManager.default.temporaryDirectory.appendingPathComponent("VoiceDraft-"+UUID().uuidString)
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            let url=folder.appendingPathComponent("source.caf");activeURL=url
            let bar=countIn ? 240/bpm:0
            if countIn {
                let click=folder.appendingPathComponent("count-in.caf")
                try await Task.detached{try VoiceSourceIO.countIn(to:click,bpm:bpm)}.value
                guard attempt==generation else{return}
                let player=try AVAudioPlayer(contentsOf:click);player.prepareToPlay();player.volume=0.4;countPlayer=player
            }
            let stream=try LiveMicrophone(audio:audio,delay:0.2+bar,duration:min(30,duration),schedule:schedule,scheduleDuration:scheduleDuration,receiver:{format in try VoicePCMSink.receiver(url:url,input:format)},onFailure:{[weak self] message in
                guard let self,self.generation==attempt,self.isCapturing else{return};self.fail(message)
            })
            microphone=stream
            if let player=countPlayer {
                let untilClick=stream.secondsUntilStart-bar
                guard untilClick>0,player.play(atTime:player.deviceCurrentTime+untilClick)else{throw VoiceAnalysisError.invalidInput}
            }
            recordedAt=nil;inputLatency=AVAudioSession.sharedInstance().inputLatency;tempoBPM=bpm;origin = .microphone
            elapsed=0;remaining=countIn ? 4:0;plannedDuration=stream.duration;waitingSeconds=stream.secondsUntilStart;state = .waiting
            timer?.invalidate();timer=Timer.scheduledTimer(withTimeInterval:1/30,repeats:true){[weak self] _ in Task { @MainActor in self?.poll(bpm:bpm) }}
        }catch{guard generation==attempt else{return};fail(error.localizedDescription)}
    }
    private func poll(bpm:Double){
        guard let microphone else{return}
        let until=microphone.secondsUntilStart
        waitingSeconds=until
        if state == .waiting || state == .countIn {
            let bar=countPlayer==nil ? 0:240/bpm
            if until<=0{state = .recording;remaining=0}
            else if bar>0,until<=bar{state = .countIn;remaining=min(4,max(1,Int(ceil(until*bpm/60))))}
            else{state = .waiting}
        }
        elapsed=microphone.elapsed;level=microphone.level
        if elapsed==0,microphone.secondsSinceStart>2{fail(LiveInputError.unavailable.localizedDescription);return}
        if let date=microphone.recordedAt{recordedAt=date}
        if microphone.complete{finish(attempt:generation)}
    }
    func stop(){
        if state == .waiting || state == .countIn || state == .preparing {
            generation+=1;try? microphone?.stop();microphone=nil;timer?.invalidate();timer=nil;countPlayer?.stop();countPlayer=nil;clearActive();state=result==nil ? .idle:.ready;return
        }
        if state == .recording{finish(attempt:generation)}
    }
    private func finish(attempt:Int){
        guard let url=activeURL,state != .analyzing else{return}
        recordedAt=microphone?.recordedAt ?? recordedAt
        do{try microphone?.stop()}catch{fail(error.localizedDescription);return}
        microphone=nil;state = .analyzing;countPlayer?.stop();countPlayer=nil;timer?.invalidate();timer=nil;progress=0
        analyze(url,attempt:attempt)
    }
    private func analyze(_ url:URL,attempt:Int){
        let progress:@Sendable(Double)->Void={ [weak self] value in Task { @MainActor in guard let self,self.generation==attempt else{return};self.progress=value } }
        let date=recordedAt,latency=inputLatency,bpm=tempoBPM,kind=origin
        let task=Task.detached(priority:.userInitiated){try VoiceSourceIO.analyze(url,recordedAt:date,inputLatency:latency,tempoBPM:bpm,origin:kind,progress:progress)};worker=task
        Task{do{let value=try await task.value;guard generation==attempt else{return};if let old=result?.sourceURL.deletingLastPathComponent(){try? FileManager.default.removeItem(at:old)};result=value;activeURL=nil;state = .ready;worker=nil}
            catch{guard generation==attempt else{return};if !(error is CancellationError){fail(error.localizedDescription)}}}
    }
    func loadFixture()async {
        guard !isCapturing else{return};generation+=1;let attempt=generation;recordedAt=nil;inputLatency=nil;tempoBPM=nil;origin = .syntheticFixture;state = .analyzing;error=nil
        do{let folder=FileManager.default.temporaryDirectory.appendingPathComponent("VoiceFixture-"+UUID().uuidString);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);let url=folder.appendingPathComponent("source.caf");activeURL=url;try await Task.detached{try VoiceSourceIO.fixture(to:url)}.value;guard generation==attempt else{return};analyze(url,attempt:attempt)}catch{guard generation==attempt else{return};fail(error.localizedDescription)}
    }
    func toggleOriginal()throws {
        if originalPlayer?.isPlaying==true{stopOriginal();return}
        guard let url=result?.sourceURL else{return};let player=try AVAudioPlayer(contentsOf:url);player.prepareToPlay();player.play();originalPlayer=player;originalPlaying=true
    }
    func pollOriginal(){originalPlaying=originalPlayer?.isPlaying ?? false}
    func stopOriginal(){originalPlayer?.stop();originalPlayer=nil;originalPlaying=false}
    private func fail(_ message:String){error=message;try? microphone?.stop();microphone=nil;countPlayer?.stop();countPlayer=nil;timer?.invalidate();timer=nil;clearActive();state=result==nil ? .idle:.ready}
    private func clearActive(){if let folder=activeURL?.deletingLastPathComponent(){try? FileManager.default.removeItem(at:folder)};activeURL=nil}
    func discard(){generation+=1;worker?.cancel();worker=nil;try? microphone?.stop();microphone=nil;timer?.invalidate();timer=nil;countPlayer?.stop();countPlayer=nil;stopOriginal();clearActive();if let folder=result?.sourceURL.deletingLastPathComponent(){try? FileManager.default.removeItem(at:folder)};result=nil;state = .idle}
}
