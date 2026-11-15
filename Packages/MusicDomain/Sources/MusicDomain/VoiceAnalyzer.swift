import Foundation

public enum PitchDetector:String,CaseIterable,Sendable {case yin,autocorrelation}
public struct PitchFrame:Sendable {
    public let time:Double;public let frequency:Double?;public let confidence:Double;public let rms:Double
    public var midi:Double?{frequency.map{69+12*log2($0/440)}}
}
public struct VoiceSegment:Sendable {
    public let start:Double;public let duration:Double;public let pitch:Int;public let confidence:Double;public let cents:Double;public let level:Double
}
public struct VoiceAnalysis:Sendable {
    public let segments:[VoiceSegment];public let duration:Double;public let waveform:[Float];public let detector:PitchDetector
    public var uncertainCount:Int{segments.filter{$0.confidence<0.9}.count}
}
public enum VoiceAnalysisError:Error,LocalizedError {
    case invalidInput
    public var errorDescription:String?{NSLocalizedString("Use a mono recording of up to 30 seconds with a valid sample rate.",comment:"Voice analysis")}
}
public enum VoiceAnalyzer {
    private static let rate=8000.0,window=512,hop=80,minLag=8,maxLag=123
    /// Both candidate detectors consume identical downsampled, DC-free windows.
    public static func frames(_ input:[Float],sampleRate:Double,detector:PitchDetector = .yin,progress:@Sendable(Double)->Void={_ in})throws->[PitchFrame] {
        guard sampleRate.isFinite,(8000...192000).contains(sampleRate),!input.isEmpty,Double(input.count)<=sampleRate*30.25,input.allSatisfy(\.isFinite)else{throw VoiceAnalysisError.invalidInput}
        let peak=Double(input.map{abs($0)}.max() ?? 0)
        let gain=peak<0.005 ? 1:min(8,0.8/max(0.01,peak))
        var filtered=[Double]();filtered.reserveCapacity(input.count)
        let alpha=1-exp(-2*Double.pi*1600/sampleRate);var a=0.0,b=0.0
        for (i,x) in input.enumerated(){if i%65536==0{try Task.checkCancellation()};a+=alpha*(Double(x)*gain-a);b+=alpha*(a-b);filtered.append(b)}
        let count=max(1,Int(Double(input.count)/sampleRate*rate))
        var samples=[Double](repeating:0,count:max(window,count))
        for i in 0..<count{let position=Double(i)*sampleRate/rate,j=min(filtered.count-1,Int(position)),next=min(filtered.count-1,j+1);samples[i]=filtered[j]+(filtered[next]-filtered[j])*(position-Double(j))}
        var result:[PitchFrame]=[]
        for start in stride(from:0,through:max(0,samples.count-window),by:hop){
            if result.count%16==0{try Task.checkCancellation();progress(Double(start)/Double(max(1,count)))}
            var frame=Array(samples[start..<start+window]);let mean=frame.reduce(0,+)/Double(window)
            for i in frame.indices{frame[i]-=mean}
            let rms=sqrt(frame.reduce(0){$0+$1*$1}/Double(window))
            let found:(Double,Double)?=rms>=0.008 ? (detector == .yin ? yin(frame):correlation(frame)):nil
            result.append(PitchFrame(time:Double(start+window/2)/rate,frequency:found.map{rate/$0.0},confidence:found?.1 ?? 0,rms:rms))
        }
        progress(1);return result
    }
    private static func refined(_ values:[Double],_ index:Int)->Double {
        guard index>0,index+1<values.count else{return Double(index)}
        let left=values[index-1],center=values[index],right=values[index+1],denominator=left-2*center+right
        return Double(index)+(abs(denominator)>1e-12 ? min(0.5,max(-0.5,0.5*(left-right)/denominator)):0)
    }
    private static func yin(_ samples:[Double])->(Double,Double)? {
        var difference=[Double](repeating:0,count:maxLag+2);var running=0.0
        for lag in 1...maxLag+1{var sum=0.0;for j in 0..<window-lag{let d=samples[j]-samples[j+lag];sum+=d*d};sum/=Double(window-lag);running+=sum;difference[lag]=running>1e-14 ? sum*Double(lag)/running:1}
        var chosen:Int?
        var lag=minLag
        while lag<=maxLag{if difference[lag]<0.15{while lag<maxLag,difference[lag+1]<difference[lag]{lag+=1};chosen=lag;break};lag+=1}
        if chosen==nil{chosen=(minLag...maxLag).min{difference[$0]<difference[$1]}}
        guard let chosen,difference[chosen]<0.25 else{return nil}
        return (refined(difference,chosen),max(0,min(1,1-difference[chosen])))
    }
    private static func correlation(_ samples:[Double])->(Double,Double)? {
        var values=[Double](repeating:0,count:maxLag+2)
        for lag in minLag-1...maxLag+1{var cross=0.0,left=0.0,right=0.0;for j in 0..<window-lag{cross+=samples[j]*samples[j+lag];left+=samples[j]*samples[j];right+=samples[j+lag]*samples[j+lag]};values[lag]=cross/max(1e-14,sqrt(left*right))}
        for lag in minLag...maxLag where values[lag]>=0.82 && values[lag]>=values[lag-1] && values[lag]>values[lag+1]{return (refined(values,lag),max(0,min(1,values[lag])))}
        return nil
    }
    public static func analyze(_ input:[Float],sampleRate:Double,detector:PitchDetector = .yin,progress:@Sendable(Double)->Void={_ in})throws->VoiceAnalysis {
        let frames=try frames(input,sampleRate:sampleRate,detector:detector,progress:progress)
        let duration=Double(input.count)/sampleRate
        var pitches=frames.map{$0.confidence>=0.72 ? $0.midi.map{Int($0.rounded())}:nil}
        let original=pitches
        for i in pitches.indices where original[i] != nil {
            let neighbors=original[max(0,i-2)...min(original.count-1,i+2)].compactMap{$0}.sorted()
            if neighbors.count>=3{pitches[i]=neighbors[neighbors.count/2]}
        }
        if pitches.count>=3{for i in 1..<pitches.count-1 where pitches[i]==nil && pitches[i-1] != nil && pitches[i-1]==pitches[i+1]{pitches[i]=pitches[i-1]}}
        var segments:[VoiceSegment]=[];var start=0
        while start<pitches.count {
            guard let pitch=pitches[start] else{start+=1;continue}
            var end=start+1;while end<pitches.count,pitches[end]==pitch{end+=1}
            let first=max(0,frames[start].time-Double(window/2)/rate+0.015)
            let last=min(duration,frames[end-1].time-Double(window/2)/rate+Double(hop)/rate+0.035)
            if last-first>=0.08 {
                let slice=frames[start..<end],confidence=slice.reduce(0){$0+$1.confidence}/Double(slice.count)
                let voiced=slice.compactMap(\.midi);let mean=voiced.isEmpty ? Double(pitch):voiced.reduce(0,+)/Double(voiced.count)
                segments.append(VoiceSegment(start:first,duration:last-first,pitch:min(127,max(0,pitch)),confidence:min(1,max(0,confidence)),cents:(mean-Double(pitch))*100,level:slice.map(\.rms).max() ?? 0))
            }
            start=end
        }
        var waveform:[Float]=[]
        let step=max(1,input.count/256)
        for i in stride(from:0,to:input.count,by:step){waveform.append(input[i..<min(input.count,i+step)].map{abs($0)}.max() ?? 0)}
        return VoiceAnalysis(segments:segments,duration:duration,waveform:Array(waveform.prefix(256)),detector:detector)
    }
    public static func notes(_ analysis:VoiceAnalysis,bpm:Double,length:Int,quantize:Quantize = .off,scaleRoot:Int?=nil,minor:Bool=false,offset:Double=0)->[NoteEvent] {
        guard bpm.isFinite,(40...240).contains(bpm),length>0,length<=64*barTicks,offset.isFinite,abs(offset)<=1 else{return []}
        let ticksPerSecond=bpm/60*Double(ppq),scale=minor ? [0,2,3,5,7,8,10]:[0,2,4,5,7,9,11]
        let peak=max(0.001,analysis.segments.map(\.level).max() ?? 0.001)
        var result:[NoteEvent]=[]
        for segment in analysis.segments {
            var start=max(0,Int(((segment.start-offset)*ticksPerSecond).rounded())),end=min(length,Int(((segment.start+segment.duration-offset)*ticksPerSecond).rounded()))
            guard end>start,start<length else{continue}
            if quantize != .off{let grid=quantize.rawValue;start=min(length-grid,max(0,Int((Double(start)/Double(grid)).rounded())*grid));end=min(length,max(start+grid,Int((Double(end)/Double(grid)).rounded())*grid))}
            var pitch=segment.pitch
            if let root=scaleRoot,(0..<12).contains(root){let range=max(0,pitch-6)...min(127,pitch+6);let allowed=range.filter{scale.contains(($0-root+12)%12)};let sourcePitch=pitch;pitch=allowed.min{abs($0-sourcePitch)<abs($1-sourcePitch)} ?? pitch}
            result.append(NoteEvent(tick:start,duration:end-start,pitch:pitch,velocity:min(120,max(30,Int(segment.level/peak*90+30))),confidence:segment.confidence))
        }
        return result
    }
}
