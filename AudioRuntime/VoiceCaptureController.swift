import Foundation
import AVFoundation
import Observation
import MusicDomain

private final class VoiceRecorderCallbacks:NSObject,AVAudioRecorderDelegate {
    let finish:@Sendable(Bool)->Void
    init(_ finish:@escaping @Sendable(Bool)->Void){self.finish=finish}
    func audioRecorderDidFinishRecording(_ recorder:AVAudioRecorder,successfully flag:Bool){finish(flag)}
    func audioRecorderEncodeErrorDidOccur(_ recorder:AVAudioRecorder,error:Error?){finish(false)}
}
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
        var samples=[Float](repeating:0,count:48000*3)
        for (index,pitch) in [60,64,67].enumerated(){let hz=440*pow(2,Double(pitch-69)/12);for frame in 0..<38400{let t=Double(frame)/48000;let gain=min(1,t/0.01,Double(38399-frame)/48000/0.01);samples[index*48000+frame]=Float(sin(2*Double.pi*hz*t)*gain*0.6)}}
        try write(samples,to:url)
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

@MainActor @Observable final class VoiceCaptureController {
    enum State:Equatable {case idle,preparing,countIn,recording,analyzing,ready}
    var state:State = .idle;var result:VoiceCaptureResult?;var error:String?
    var elapsed=0.0;var remaining=4;var level=0.0;var progress=0.0;var originalPlaying=false
    var isCapturing:Bool{state == .preparing || state == .countIn || state == .recording}
    private var recorder:AVAudioRecorder?;private var delegate:VoiceRecorderCallbacks?
    private var countPlayer:AVAudioPlayer?;private var originalPlayer:AVAudioPlayer?
    private var timer:Timer?;private var worker:Task<VoiceCaptureResult,Error>?
    private var generation=0;private var scheduledStart=0.0;private var recordedAt:Date?;private var inputLatency:Double?;private var tempoBPM:Double?;private var origin:AudioAssetRecord.Origin = .microphone;private var activeURL:URL?
    func start(bpm:Double,duration:Double,countIn:Bool)async {
        guard !isCapturing,state != .analyzing else{return};stopOriginal();state = .preparing;error=nil;generation+=1;let attempt=generation
        let permission=await AVAudioApplication.requestRecordPermission()
        guard attempt==generation else{return}
        guard permission else{error=NSLocalizedString("Microphone access was denied. You can still write notes in Piano roll.",comment:"");state=result==nil ? .idle:.ready;return}
        do {
            let session=AVAudioSession.sharedInstance();try session.setCategory(.playAndRecord,mode:.measurement,options:[.defaultToSpeaker]);try session.setPreferredSampleRate(48000);try session.setActive(true)
            let folder=FileManager.default.temporaryDirectory.appendingPathComponent("VoiceDraft-"+UUID().uuidString)
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            let url=folder.appendingPathComponent("source.caf");activeURL=url
            let settings:[String:Any]=[AVFormatIDKey:kAudioFormatLinearPCM,AVSampleRateKey:48000,AVNumberOfChannelsKey:1,AVLinearPCMBitDepthKey:32,AVLinearPCMIsFloatKey:true,AVLinearPCMIsBigEndianKey:false]
            let r=try AVAudioRecorder(url:url,settings:settings)
            let callback=VoiceRecorderCallbacks{[weak self] success in Task { @MainActor in guard let self,self.generation==attempt,self.isCapturing else{return};if success{self.finish(attempt:attempt)}else{self.fail(NSLocalizedString("The recording could not be completed. Try again.",comment:""))}}}
            delegate=callback;r.delegate=callback;r.isMeteringEnabled=true
            guard r.prepareToRecord()else{throw VoiceAnalysisError.invalidInput}
            recorder=r
            if countIn {
                let click=folder.appendingPathComponent("count-in.caf")
                try await Task.detached{try VoiceSourceIO.countIn(to:click,bpm:bpm)}.value
                guard attempt==generation else{return}
                let player=try AVAudioPlayer(contentsOf:click);player.prepareToPlay();player.volume=0.4;countPlayer=player
                scheduledStart=r.deviceCurrentTime+0.1+240/bpm;player.play(atTime:player.deviceCurrentTime+0.1)
            }else{scheduledStart=r.deviceCurrentTime+0.1}
            guard r.record(atTime:scheduledStart,forDuration:min(30,max(0.2,duration)))else{throw VoiceAnalysisError.invalidInput}
            recordedAt=Date(timeIntervalSinceNow:max(0,scheduledStart-r.deviceCurrentTime));inputLatency=session.inputLatency;tempoBPM=bpm;origin = .microphone
            elapsed=0;remaining=countIn ? 4:0;state=countIn ? .countIn:.recording
            timer?.invalidate();timer=Timer.scheduledTimer(withTimeInterval:1/30,repeats:true){[weak self] _ in Task { @MainActor in self?.poll(bpm:bpm) }}
        }catch{fail(error.localizedDescription)}
    }
    private func poll(bpm:Double){
        guard let recorder else{return}
        let until=scheduledStart-recorder.deviceCurrentTime
        if state == .countIn {remaining=max(0,Int(ceil(until*bpm/60)));if until<=0{state = .recording}}
        elapsed=max(0,recorder.currentTime);recorder.updateMeters();level=pow(10,Double(recorder.averagePower(forChannel:0))/20)
    }
    func stop(){
        if state == .countIn || state == .preparing{generation+=1;recorder?.stop();recorder=nil;delegate=nil;timer?.invalidate();countPlayer?.stop();clearActive();state=result==nil ? .idle:.ready;return}
        if state == .recording{finish(attempt:generation)}
    }
    private func finish(attempt:Int){
        guard let url=activeURL,state != .analyzing else{return};state = .analyzing
        recorder?.stop();recorder=nil;delegate=nil;countPlayer?.stop();countPlayer=nil;timer?.invalidate();timer=nil;progress=0
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
        do{let folder=FileManager.default.temporaryDirectory.appendingPathComponent("VoiceFixture-"+UUID().uuidString);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);let url=folder.appendingPathComponent("source.caf");activeURL=url;try await Task.detached{try VoiceSourceIO.fixture(to:url)}.value;guard generation==attempt else{return};analyze(url,attempt:attempt)}catch{fail(error.localizedDescription)}
    }
    func toggleOriginal()throws {
        if originalPlayer?.isPlaying==true{stopOriginal();return}
        guard let url=result?.sourceURL else{return};let player=try AVAudioPlayer(contentsOf:url);player.prepareToPlay();player.play();originalPlayer=player;originalPlaying=true
    }
    func pollOriginal(){originalPlaying=originalPlayer?.isPlaying ?? false}
    func stopOriginal(){originalPlayer?.stop();originalPlayer=nil;originalPlaying=false}
    private func fail(_ message:String){error=message;recorder?.stop();recorder=nil;delegate=nil;countPlayer?.stop();countPlayer=nil;timer?.invalidate();timer=nil;clearActive();state=result==nil ? .idle:.ready}
    private func clearActive(){if let folder=activeURL?.deletingLastPathComponent(){try? FileManager.default.removeItem(at:folder)};activeURL=nil}
    func discard(){generation+=1;worker?.cancel();worker=nil;stop();recorder?.stop();recorder=nil;timer?.invalidate();stopOriginal();clearActive();if let folder=result?.sourceURL.deletingLastPathComponent(){try? FileManager.default.removeItem(at:folder)};result=nil;state = .idle}
}
