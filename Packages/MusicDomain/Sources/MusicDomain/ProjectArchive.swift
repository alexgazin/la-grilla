import Foundation

/// Standard ZIP, stored entries (method 0). Deliberately rejects encryption, ZIP64,
/// deflate and path extraction: portable projects contain bundled-preset references.
public enum ProjectArchive {
    public struct Entry: Sendable {public var name:String;public var data:Data;public init(_ name:String,_ data:Data){self.name=name;self.data=data}}
    /// I70: safe, unique file names for a batch archive ("Song.grillapack",
    /// "Song (2).grillapack"); path separators and control characters are removed.
    public static func fileNames(_ names:[String],extension ext:String)->[String] {
        var used=Set<String>();var result:[String]=[]
        for raw in names {
            var base=String(raw.prefix(80)).components(separatedBy:CharacterSet(charactersIn:"/\\:").union(.controlCharacters)).joined(separator:"-").trimmingCharacters(in:CharacterSet(charactersIn:". ").union(.whitespaces))
            if base.isEmpty{base="La Grilla"}
            var name=base+"."+ext,counter=2
            while used.contains(name.lowercased()){name="\(base) (\(counter))."+ext;counter+=1}
            used.insert(name.lowercased());result.append(name)
        }
        return result
    }
    public static func checksum(_ data:Data)->UInt32 {var crc=UInt32.max;for byte in data{crc=update(crc,byte)};return crc ^ UInt32.max}
    private static let table:[UInt32]=(0..<256).map{value in var c=UInt32(value);for _ in 0..<8{c=c&1 != 0 ? 0xedb88320^(c>>1):c>>1};return c}
    private static func update(_ crc:UInt32,_ byte:UInt8)->UInt32 {table[Int((crc^UInt32(byte))&255)]^(crc>>8)}
    private static func validate(_ name:String)throws {
        guard !name.isEmpty,name.utf8.count<=240,!name.hasPrefix("/"),!name.contains("\\"),!name.contains(":"),!name.contains("\0"),name.split(separator:"/",omittingEmptySubsequences:false).allSatisfy({!$0.isEmpty && $0 != "." && $0 != ".."})else{throw ExportError.invalidArchive}
    }
    private struct Descriptor {let name:String;let crc:UInt32;let size:UInt32;let offset:UInt32}
    private static func local(_ e:Descriptor)->Data {
        var d=Data();d.little(UInt32(0x04034b50));d.little(UInt16(20));d.little(UInt16(0x800));d.little(UInt16(0));d.little(UInt16(0));d.little(UInt16(0x5821));d.little(e.crc);d.little(e.size);d.little(e.size);d.little(UInt16(e.name.utf8.count));d.little(UInt16(0));d.append(contentsOf:e.name.utf8);return d
    }
    private static func directory(_ entries:[Descriptor],offset:UInt32)->Data {
        var d=Data()
        for e in entries {d.little(UInt32(0x02014b50));d.little(UInt16(20));d.little(UInt16(20));d.little(UInt16(0x800));d.little(UInt16(0));d.little(UInt16(0));d.little(UInt16(0x5821));d.little(e.crc);d.little(e.size);d.little(e.size);d.little(UInt16(e.name.utf8.count));d.little(UInt16(0));d.little(UInt16(0));d.little(UInt16(0));d.little(UInt16(0));d.little(UInt32(0));d.little(e.offset);d.append(contentsOf:e.name.utf8)}
        let count=UInt16(entries.count),size=UInt32(d.count)
        d.little(UInt32(0x06054b50));d.little(UInt16(0));d.little(UInt16(0));d.little(count);d.little(count);d.little(size);d.little(offset);d.little(UInt16(0));return d
    }
    public static func encode(_ entries:[Entry])throws->Data {
        guard entries.count<=64,Set(entries.map(\.name)).count==entries.count else {throw ExportError.invalidArchive}
        var data=Data(),descriptors:[Descriptor]=[]
        for e in entries {try validate(e.name);guard e.data.count<=16_000_000,data.count+e.data.count+1024<=128_000_000 else{throw ExportError.archiveTooLarge};let descriptor=Descriptor(name:e.name,crc:checksum(e.data),size:UInt32(e.data.count),offset:UInt32(data.count));data.append(local(descriptor));data.append(e.data);descriptors.append(descriptor)}
        data.append(directory(descriptors,offset:UInt32(data.count)));return data
    }
    /// Streaming archive for large stems. Only one 64 KiB file chunk is held in memory.
    public static func writeFiles(_ files:[(name:String,url:URL)],extras:[Entry]=[],to url:URL)throws {
        guard files.count+extras.count<=64,Set(files.map(\.name)+extras.map(\.name)).count==files.count+extras.count else{throw ExportError.invalidArchive}
        guard FileManager.default.createFile(atPath:url.path,contents:nil) else{throw CocoaError(.fileWriteUnknown)}
        let output=try FileHandle(forWritingTo:url);var complete=false
        defer{try? output.close();if !complete{try? FileManager.default.removeItem(at:url)}}
        var descriptors:[Descriptor]=[];var offset:UInt64=0
        for file in files {
            try Task.checkCancellation();try validate(file.name)
            let size=try file.url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
            guard size>=0,size<=Int(UInt32.max),offset+UInt64(size)+1024<UInt64(UInt32.max)else{throw ExportError.archiveTooLarge}
            let input=try FileHandle(forReadingFrom:file.url);defer{try? input.close()};var crc=UInt32.max;var actual=0
            while let chunk=try input.read(upToCount:65536),!chunk.isEmpty{try Task.checkCancellation();actual+=chunk.count;for byte in chunk{crc=update(crc,byte)}}
            guard actual==size else{throw ExportError.invalidArchive}
            let descriptor=Descriptor(name:file.name,crc:crc ^ UInt32.max,size:UInt32(size),offset:UInt32(offset));let header=local(descriptor);try output.write(contentsOf:header);offset+=UInt64(header.count)
            try input.seek(toOffset:0)
            while let chunk=try input.read(upToCount:65536),!chunk.isEmpty{try Task.checkCancellation();try output.write(contentsOf:chunk);offset+=UInt64(chunk.count)}
            descriptors.append(descriptor)
        }
        for e in extras{try validate(e.name);guard e.data.count<=16_000_000,offset+UInt64(e.data.count)+1024<UInt64(UInt32.max)else{throw ExportError.archiveTooLarge};let descriptor=Descriptor(name:e.name,crc:checksum(e.data),size:UInt32(e.data.count),offset:UInt32(offset));let header=local(descriptor);try output.write(contentsOf:header);try output.write(contentsOf:e.data);offset+=UInt64(header.count+e.data.count);descriptors.append(descriptor)}
        try output.write(contentsOf:directory(descriptors,offset:UInt32(offset)));try output.close();complete=true
    }
    public static func decode(_ data:Data,maxBytes:Int=20_000_000)throws->[Entry] {
        guard data.count>=22,data.count<=maxBytes else{throw ExportError.archiveTooLarge}
        let b=data
        func u16(_ i:Int)throws->Int{guard i>=0,i+2<=b.count else{throw ExportError.invalidArchive};return Int(b[i])|Int(b[i+1])<<8}
        func u32(_ i:Int)throws->Int{guard i>=0,i+4<=b.count else{throw ExportError.invalidArchive};return Int(b[i])|Int(b[i+1])<<8|Int(b[i+2])<<16|Int(b[i+3])<<24}
        var end:Int?
        for i in stride(from:b.count-22,through:max(0,b.count-65557),by:-1){if try u32(i)==0x06054b50,try i+22+u16(i+20)==b.count{end=i;break}}
        guard let end,try u16(end+4)==0,try u16(end+6)==0,try u16(end+8)==u16(end+10)else{throw ExportError.unsupportedArchive}
        let count=try u16(end+10),start=try u32(end+16),size=try u32(end+12)
        guard count>0,count<=64,start+size==end else{throw ExportError.invalidArchive}
        var cursor=start,total=0;var entries:[Entry]=[];var used:Set<String>=[]
        for _ in 0..<count {
            guard try u32(cursor)==0x02014b50 else{throw ExportError.invalidArchive}
            let flags=try u16(cursor+8),method=try u16(cursor+10),crc=try u32(cursor+16),compressed=try u32(cursor+20),length=try u32(cursor+24)
            guard flags & ~0x800 == 0,method==0,compressed==length else{throw ExportError.unsupportedArchive}
            let nameLength=try u16(cursor+28),extra=try u16(cursor+30),comment=try u16(cursor+32),offset=try u32(cursor+42)
            guard cursor+46+nameLength+extra+comment<=end,nameLength>0,offset+30<start else{throw ExportError.invalidArchive}
            guard let name=String(bytes:b[(cursor+46)..<(cursor+46+nameLength)],encoding:.utf8)else{throw ExportError.invalidArchive};try validate(name)
            guard used.insert(name).inserted else{throw ExportError.invalidArchive}
            total+=length;guard total<=maxBytes else{throw ExportError.archiveTooLarge}
            guard try u32(offset)==0x04034b50,try u16(offset+6)==flags,try u16(offset+8)==0,try u32(offset+14)==crc,try u32(offset+18)==length,try u32(offset+22)==length,try u16(offset+26)==nameLength else{throw ExportError.invalidArchive}
            let dataStart=try offset+30+nameLength+u16(offset+28)
            guard dataStart+length<=start,Array(b[(offset+30)..<(offset+30+nameLength)])==Array(name.utf8)else{throw ExportError.invalidArchive}
            let payload=Data(b[dataStart..<(dataStart+length)]);guard checksum(payload)==UInt32(crc)else{throw ExportError.invalidArchive}
            entries.append(Entry(name,payload));cursor+=46+nameLength+extra+comment
        }
        guard cursor==end else{throw ExportError.invalidArchive};return entries
    }
}
public struct PortableProjectBundle:Sendable {public var project:Project;public var assets:[String:Data]}
public enum PortableProject {
    static func documentEntries(_ project:Project)throws->[ProjectArchive.Entry] {
        try project.validate();let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys];let manifest=try encoder.encode(project)
        let version = project.referencedSamples.isEmpty ? ((project.audioAssets ?? []).isEmpty ? "1" : "2") : "3"
        let instruments = version == "3" ? "Built-in presets and referenced PCM sample assets. Voice recordings are included when present." : "Bundled synthetic presets version 1. Voice source recordings are included when present."
        let metadata:[String:String]=["format":"La Grilla portable project","version":version,"manifestCRC32":String(format:"%08x",ProjectArchive.checksum(manifest)),"instruments":instruments]
        return [.init("manifest.json",manifest),.init("metadata.json",try JSONSerialization.data(withJSONObject:metadata,options:[.sortedKeys]))]
    }
    public static func data(_ project:Project,assets:[String:Data]=[:])throws->Data {
        var entries=try documentEntries(project)
        guard Set(assets.keys)==Set((project.audioAssets ?? []).map(\.relativePath) + project.referencedSamples.map(\.relativePath))else{throw ExportError.invalidArchive}
        for record in project.audioAssets ?? []{guard let data=assets[record.relativePath]else{throw ExportError.invalidArchive};try AssetIntegrity.validate(data,record:record);entries.append(.init(record.relativePath,data))}
        for asset in project.referencedSamples.sorted(by: { $0.relativePath < $1.relativePath }) {
            guard let data = assets[asset.relativePath] else { throw SampleError.unavailable }
            let pcm = try SamplePCM.decode(data, asset: asset)
            try project.validatePadEditRate(for: asset, rate: pcm.rate)
            entries.append(.init(asset.relativePath, data))
        }
        return try ProjectArchive.encode(entries)
    }
    public static func decodeBundle(_ data:Data,asCopy:Bool=true)throws->PortableProjectBundle {
        let entries=try ProjectArchive.decode(data,maxBytes:128_000_000)
        guard let manifest=entries.first(where:{$0.name=="manifest.json"})?.data,manifest.count<=8_000_000,let meta=entries.first(where:{$0.name=="metadata.json"})?.data,meta.count<=64_000,let metadata=try JSONSerialization.jsonObject(with:meta) as? [String:String],["1","2","3"].contains(metadata["version"] ?? ""),metadata["manifestCRC32"]==String(format:"%08x",ProjectArchive.checksum(manifest))else{throw ExportError.invalidArchive}
        var p=try ProjectDocument.decode(manifest);let expected=Set(["manifest.json","metadata.json"]+(p.audioAssets ?? []).map(\.relativePath)+p.referencedSamples.map(\.relativePath))
        guard Set(entries.map(\.name))==expected, (metadata["version"] == "3") == !p.referencedSamples.isEmpty else{throw ExportError.invalidArchive}
        var assets:[String:Data]=[:]
        for record in p.audioAssets ?? []{guard let data=entries.first(where:{$0.name==record.relativePath})?.data else{throw ExportError.invalidArchive};try AssetIntegrity.validate(data,record:record);assets[record.relativePath]=data}
        for asset in p.referencedSamples {
            guard let data = entries.first(where: { $0.name == asset.relativePath })?.data else { throw SampleError.unavailable }
            let pcm = try SamplePCM.decode(data, asset: asset)
            try p.validatePadEditRate(for: asset, rate: pcm.rate)
            assets[asset.relativePath] = data
        }
        if asCopy{p.id=UUID();p.revision=0;p.modified=Date();p.name=String(p.name.prefix(110))+" imported"}
        return PortableProjectBundle(project:p,assets:assets)
    }
    public static func decode(_ data:Data,asCopy:Bool=true)throws->Project {try decodeBundle(data,asCopy:asCopy).project}
}
