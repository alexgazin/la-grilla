import AVFoundation
import Foundation

// File-I/O fixture only. No microphone, audio engine or production acceptance.
let expectedFrames:AVAudioFramePosition=139_200
let sampleRate=48_000.0
let output=URL(fileURLWithPath:CommandLine.arguments.dropFirst().first ?? "FileIODiagnostics",isDirectory:true)
try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
let url=output.appendingPathComponent("synthetic-file-io-fixture.caf")
let began=Date()

func emit(_ stage:String,_ values:[String:Any]=[:]) {
    var row=values;row["stage"]=stage;row["diagnosticOnly"]=true;row["productionMicrophoneAcceptance"]=false
    let data=try! JSONSerialization.data(withJSONObject:row,options:[.sortedKeys])
    print(String(decoding:data,as:UTF8.self))
}
func errorFields(_ error:Error)->[String:Any] {
    let value=error as NSError
    var fields:[String:Any]=["domain":value.domain,"code":value.code,"description":value.localizedDescription]
    if let underlying=value.userInfo[NSUnderlyingErrorKey]as?NSError{fields["underlyingDomain"]=underlying.domain;fields["underlyingCode"]=underlying.code}
    return fields
}
func writeFixture()throws {
    guard let format=AVAudioFormat(commonFormat:.pcmFormatFloat32,sampleRate:sampleRate,channels:1,interleaved:false),let chunk=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:1024)else{throw NSError(domain:"CAFProbe",code:1)}
    let writer=try AVAudioFile(forWriting:url,settings:format.settings)
    var total:AVAudioFramePosition=0
    while total<expectedFrames {
        let count=AVAudioFrameCount(min(1024,expectedFrames-total))
        chunk.frameLength=count
        for index in 0..<Int(count){chunk.floatChannelData![0][index]=Float(sin(2*Double.pi*220*Double(total+AVAudioFramePosition(index))/sampleRate)*0.5)}
        try writer.write(from:chunk);total+=AVAudioFramePosition(count)
    }
    emit("fixture-written-before-writer-release",["frames":total,"writerLength":writer.length,"writerPosition":writer.framePosition,"sampleRate":writer.processingFormat.sampleRate])
}
func singleRead() {
    do {
        let file=try AVAudioFile(forReading:url,commonFormat:.pcmFormatFloat32,interleaved:false)
        let buffer=AVAudioPCMBuffer(pcmFormat:file.processingFormat,frameCapacity:AVAudioFrameCount(file.length))!
        let declared=file.length
        emit("single-read-before",["declared":declared,"capacity":buffer.frameCapacity,"position":file.framePosition])
        do{try file.read(into:buffer);emit("single-read-after",["declared":declared,"actual":buffer.frameLength,"position":file.framePosition,"duration":Double(buffer.frameLength)/sampleRate])}
        catch{var fields=errorFields(error);fields["declared"]=declared;fields["actual"]=buffer.frameLength;fields["position"]=file.framePosition;emit("single-read-error",fields)}
    }catch{emit("single-read-open-error",errorFields(error))}
}
func boundedRead(_ size:AVAudioFrameCount) {
    do {
        let file=try AVAudioFile(forReading:url,commonFormat:.pcmFormatFloat32,interleaved:false)
        let buffer=AVAudioPCMBuffer(pcmFormat:file.processingFormat,frameCapacity:size)!
        let declared=file.length
        var total:AVAudioFramePosition=0,calls=0,finite=true
        emit("bounded-read-before",["chunkSize":size,"declared":declared,"position":file.framePosition])
        while total<declared {
            let requested=AVAudioFrameCount(min(AVAudioFramePosition(size),declared-total)),previous=file.framePosition
            buffer.frameLength=0
            do{try file.read(into:buffer,frameCount:requested)}
            catch{var fields=errorFields(error);fields["chunkSize"]=size;fields["total"]=total;fields["requested"]=requested;fields["actual"]=buffer.frameLength;fields["previousPosition"]=previous;fields["position"]=file.framePosition;emit("bounded-read-error",fields);return}
            let actual=buffer.frameLength;calls+=1
            guard actual>0,actual<=requested,file.framePosition==previous+AVAudioFramePosition(actual)else{emit("bounded-read-progress-error",["chunkSize":size,"total":total,"declared":declared,"requested":requested,"actual":actual,"previousPosition":previous,"position":file.framePosition]);return}
            if let values=buffer.floatChannelData?[0]{for index in 0..<Int(actual){finite=finite && values[index].isFinite}}
            else{finite=false}
            total+=AVAudioFramePosition(actual)
            if calls<=2 || declared-total<AVAudioFramePosition(size){emit("bounded-read-progress",["chunkSize":size,"call":calls,"requested":requested,"actual":actual,"total":total,"position":file.framePosition])}
        }
        emit("bounded-read-complete",["chunkSize":size,"declared":declared,"total":total,"position":file.framePosition,"calls":calls,"finite":finite,"duration":Double(total)/sampleRate])
        buffer.frameLength=0
        emit("eof-probe-before",["chunkSize":size,"declared":declared,"position":file.framePosition])
        do{try file.read(into:buffer,frameCount:1);emit("eof-probe-returned",["chunkSize":size,"actual":buffer.frameLength,"position":file.framePosition,"length":file.length])}
        catch{var fields=errorFields(error);fields["chunkSize"]=size;fields["actual"]=buffer.frameLength;fields["position"]=file.framePosition;fields["length"]=file.length;emit("eof-probe-threw",fields)}
    }catch{var fields=errorFields(error);fields["chunkSize"]=size;emit("bounded-open-error",fields)}
}

emit("begin",["os":ProcessInfo.processInfo.operatingSystemVersionString,"expectedFrames":expectedFrames,"sampleRate":sampleRate,"signal":"Generated file-I/O tone fixture; not recorded microphone PCM"])
try autoreleasepool{try writeFixture()}
let count=try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
emit("fixture-closed",["bytes":count])
singleRead();boundedRead(4096);boundedRead(997)
emit("complete",["elapsedSeconds":Date().timeIntervalSince(began)])
