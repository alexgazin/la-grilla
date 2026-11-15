import Foundation
import AudioDSP

public struct AudioAssetRecord:Codable,Equatable,Identifiable,Sendable {
    public enum Origin:String,Codable,Sendable{case microphone,syntheticFixture}
    public var origin:Origin;public var recordedAt:Date?;public var inputLatencySeconds:Double?;public var tempoBPM:Double?
    public var id:UUID
    public var sha256:String;public var byteCount:Int;public var sampleRate:Double;public var duration:Double
    public var relativePath:String{"Assets/"+id.uuidString+".caf"}
    public init(id:UUID=UUID(),sha256:String,byteCount:Int,sampleRate:Double,duration:Double,origin:Origin = .microphone,recordedAt:Date?=nil,inputLatencySeconds:Double?=nil,tempoBPM:Double?=nil){self.origin=origin;self.recordedAt=recordedAt;self.inputLatencySeconds=inputLatencySeconds;self.tempoBPM=tempoBPM;self.id=id;self.sha256=sha256;self.byteCount=byteCount;self.sampleRate=sampleRate;self.duration=duration}
    public func validate()throws {
        guard recordedAt==nil || recordedAt!.timeIntervalSinceReferenceDate.isFinite,inputLatencySeconds==nil || (inputLatencySeconds!.isFinite && (0...2).contains(inputLatencySeconds!)),tempoBPM==nil || (tempoBPM!.isFinite && (40...240).contains(tempoBPM!))else{throw MusicError.invalidProject}
        guard sha256.utf8.count==64,sha256.utf8.allSatisfy({(48...57).contains($0)||(97...102).contains($0)}),(64...12_000_000).contains(byteCount),sampleRate.isFinite,[44100.0,48000.0].contains(sampleRate),duration.isFinite,(0.05...30.25).contains(duration)else{throw MusicError.invalidProject}
    }
}
public enum AssetIntegrity {
    public static func sha256(_ data:Data)throws->String {
        guard data.count<=16_000_000 else{throw ExportError.archiveTooLarge}
        var output=[CChar](repeating:0,count:65)
        let success=data.withUnsafeBytes{bytes in lg_sha256(bytes.baseAddress?.assumingMemoryBound(to:UInt8.self),Int32(data.count),&output)}
        guard success==1 else{throw ExportError.invalidArchive}
        return String(decoding:output.prefix(64).map{UInt8(bitPattern:$0)},as:UTF8.self)
    }
    public static func validate(_ data:Data,record:AudioAssetRecord)throws {
        try record.validate()
        guard data.count==record.byteCount,try sha256(data)==record.sha256,Array(data.prefix(4))==Array("caff".utf8)else{throw ExportError.invalidArchive}
        let bytes=[UInt8](data)
        func integer(_ position:Int,_ count:Int)throws->UInt64{guard position>=0,position+count<=bytes.count else{throw ExportError.invalidArchive};return bytes[position..<position+count].reduce(0){($0<<8)|UInt64($1)}}
        guard try integer(4,2)==1 else{throw ExportError.invalidArchive}
        var cursor=8,foundFormat=false,foundData=false,steps=0
        while cursor+12<=bytes.count,steps<64 {
            let name=String(bytes:bytes[cursor..<cursor+4],encoding:.ascii),rawSize=try integer(cursor+4,8)
            let size=(rawSize==UInt64.max && name=="data") ? UInt64(bytes.count-cursor-12):rawSize
            guard size<=UInt64(bytes.count-cursor-12)else{throw ExportError.invalidArchive}
            let start=cursor+12
            if name=="desc"{guard size==32 else{throw ExportError.invalidArchive};let rate=Double(bitPattern:try integer(start,8));guard abs(rate-record.sampleRate)<0.5,Array(bytes[start+8..<start+12])==Array("lpcm".utf8),try integer(start+24,4)==1,try integer(start+28,4)==32 else{throw ExportError.invalidArchive};foundFormat=true}
            if name=="data"{guard size>=4,(size-4)%4==0 else{throw ExportError.invalidArchive};let duration=Double(size-4)/(record.sampleRate*4);guard abs(duration-record.duration)<0.1 else{throw ExportError.invalidArchive};foundData=true}
            cursor=start+Int(size);steps+=1
        }
        guard foundFormat,foundData,cursor==bytes.count else{throw ExportError.invalidArchive}
    }
}
