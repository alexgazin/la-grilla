import Foundation
import Testing
@testable import MusicDomain

struct VoiceTests {
    static func tone(_ pitch:Int,_ duration:Double,rate:Double=8000)->[Float] {
        let hz=440*pow(2,Double(pitch-69)/12),count=Int(duration*rate)
        return (0..<count).map{i in let t=Double(i)/rate,phase=2*Double.pi*hz*t,envelope=min(1,t/0.01,Double(count-1-i)/rate/0.01);return Float(envelope*(0.7*sin(phase)+0.2*sin(2*phase)+0.1*sin(3*phase))*0.7)}
    }
    static func noise(_ count:Int)->[Float]{var seed:UInt32=0x47524944;return (0..<count).map{_ in seed ^= seed<<13;seed ^= seed>>17;seed ^= seed<<5;return Float(Double(seed)/Double(UInt32.max)-0.5)*0.3}}
    @Test func compareTwoDetectorsOnIdenticalCleanPitchFixtures() throws {
        var report:[[String:Any]]=[]
        for detector in PitchDetector.allCases {
            var count=0,correct=0,octaves=0
            for pitch in 36...83 {
                let frames=try VoiceAnalyzer.frames(Self.tone(pitch,0.25),sampleRate:8000,detector:detector).filter{(0.08...0.17).contains($0.time)}
                for frame in frames{count+=1;if let note=frame.midi{if abs(note-Double(pitch))<=0.5{correct+=1};if abs(abs(note-Double(pitch))-12)<=0.5{octaves+=1}}}
            }
            let accuracy=Double(correct)/Double(count)
            #expect(accuracy>=0.98)
            let noise=try VoiceAnalyzer.frames(Self.noise(8000),sampleRate:8000,detector:detector)
            #expect(noise.filter{$0.frequency != nil}.count<=1)
            report.append(["detector":detector.rawValue,"stableFrames":count,"correctWithin50Cents":correct,"pitchAccuracy":accuracy,"octaveErrors":octaves,"noiseVoicedFrames":noise.filter{$0.frequency != nil}.count])
        }
        let data=try JSONSerialization.data(withJSONObject:["fixture":"48 deterministic harmonic tones, MIDI 36–83, 8 kHz; no human voice recordings","results":report],options:[.sortedKeys,.prettyPrinted])
        print("VOICE DETECTOR COMPARISON: "+String(decoding:data,as:UTF8.self))
        if let path=ProcessInfo.processInfo.environment["GRILLA_VOICE_METRICS"]{let url=URL(fileURLWithPath:path);try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true);try data.write(to:url)}
    }
    @Test func silenceAndNoiseDoNotBecomeMelodyNotes() throws {
        for detector in PitchDetector.allCases {
            #expect(try VoiceAnalyzer.analyze(Array(repeating:0,count:8000),sampleRate:8000,detector:detector).segments.isEmpty)
            #expect(try VoiceAnalyzer.analyze(Self.noise(8000),sampleRate:8000,detector:detector).segments.isEmpty)
        }
        #expect(throws:VoiceAnalysisError.self){try VoiceAnalyzer.analyze([.nan],sampleRate:8000)}
        #expect(throws:VoiceAnalysisError.self){try VoiceAnalyzer.analyze([0],sampleRate:0)}
    }
    @Test func repeatedNotesRemainSeparateAcrossARealPause() throws {
        let samples=Self.tone(57,0.35)+Array(repeating:Float(0),count:1200)+Self.tone(57,0.35)
        let result=try VoiceAnalyzer.analyze(samples,sampleRate:8000)
        #expect(result.segments.map(\.pitch)==[57,57]);#expect(result.waveform.count==256)
        #expect(abs(result.segments[0].start-0)<0.08)
        #expect(abs(result.segments[1].start-0.5)<0.08)
        #expect(result.segments[0].start+result.segments[0].duration<result.segments[1].start)
        #expect(result.segments.allSatisfy{$0.confidence>0.8})
    }
    @Test func sampleRateConversionKeepsPitchAndDuration() throws {
        let result=try VoiceAnalyzer.analyze(Self.tone(60,0.6,rate:44100),sampleRate:44100)
        #expect(result.segments.map(\.pitch)==[60]);#expect(abs(result.duration-0.6)<0.001)
        #expect(result.segments[0].duration>0.5)
    }
    @Test func rhythmAndScaleProjectionKeepSourceAnalysisAvailable() throws {
        let analysis=try VoiceAnalyzer.analyze(Self.tone(61,0.4),sampleRate:8000)
        #expect(analysis.segments.map(\.pitch)==[61])
        let notes=VoiceAnalyzer.notes(analysis,bpm:120,length:barTicks,quantize:.sixteenth,scaleRoot:0)
        #expect(notes.count==1);#expect(notes[0].pitch==60);#expect(notes[0].tick%240==0);#expect(notes[0].duration%240==0)
        #expect(notes[0].confidence != nil);#expect(analysis.segments[0].pitch==61)
        #expect(VoiceAnalyzer.notes(analysis,bpm:0,length:barTicks).isEmpty)
    }
    @Test func cancelledAnalysisStopsWithoutProducingAResult() async throws {
        let input=Self.tone(57,5)
        let task=Task.detached{try VoiceAnalyzer.analyze(input,sampleRate:8000)};task.cancel()
        do{_ = try await task.value;Issue.record("Cancelled transcription returned a result")}catch is CancellationError{}catch{Issue.record("Unexpected error: \(error)")}
    }
}
