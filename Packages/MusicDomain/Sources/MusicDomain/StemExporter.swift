import Foundation
public enum StemExporter {
    public static func render(_ project:Project,to destination:URL,settings:WAVSettings=WAVSettings(),range:Range<Int>?=nil,selected:Set<UUID>?=nil,samples:SampleLibrary=SampleLibrary(),extras:[ProjectArchive.Entry]=[],progress:@Sendable(Double)->Void={_ in})async throws->URL {
        try project.validate();let tracks=project.tracks.filter{selected == nil || selected!.contains($0.id)}
        guard !tracks.isEmpty else{throw ExportError.invalidSettings}
        let folder=destination.deletingLastPathComponent().appendingPathComponent("stems-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:folder)}
        var files:[(name:String,url:URL)]=[];var info:[[String:Any]]=[]
        let anySolo=project.tracks.contains(where:\.solo)
        for (index,track) in tracks.enumerated(){
            try Task.checkCancellation()
            let name=String(format:"%02d",index+1)+"-"+track.role.rawValue+".wav";let url=folder.appendingPathComponent(name)
            let receipt=try await OfflineRenderer.render(project,to:url,settings:settings,range:range,isolatedTrack:track.id,samples:samples){value in progress((Double(index)+value)/Double(tracks.count+1))}
            let normalizedGain=try settings.normalizeStemsDBFS.map{try WAVNormalizer.normalize(url,targetDBFS:$0)} ?? 0
            files.append((name,url));info.append(["file":name,"trackID":track.id.uuidString,"role":track.role.rawValue,"name":track.displayName,"gainDB":track.gain,"pan":track.pan,"audible":!track.mute && (!anySolo || track.solo),"frames":receipt.frames,"peak":receipt.peak,"clipped":receipt.clipped,"normalizedGainDB":normalizedGain])
        }
        let manifest:[String:Any] = ["format":"La Grilla aligned stems","version":1,"tempoBPM":project.bpm,"key":project.keyName,"ppq":ppq,"timeSignature":"4/4","sampleRate":settings.sampleRate,"bitDepth":settings.bitDepth,"channels":2,"tailSeconds":settings.tailSeconds,"startTick":range?.lowerBound ?? 0,"endTick":range?.upperBound ?? project.length,"projectRevision":project.revision,"masterGainApplied":false,"peakNormalizedDBFS":settings.normalizeStemsDBFS as Any,"muteSoloApplied":true,"mixNote":"Track gain/pan applied. Master gain excluded. Output protection/PCM rounding can prevent an exact sum when clipping occurs.","tracks":info]
        try Task.checkCancellation();try ProjectArchive.writeFiles(files,extras:[.init("manifest.json",try JSONSerialization.data(withJSONObject:manifest,options:[.sortedKeys,.prettyPrinted]))]+extras,to:destination);progress(1);return destination
    }
}

/// I68 · Peak-normalize a 16/24-bit PCM WAV in place. Silent files stay
/// untouched; the gain is bounded to +24 dB. Returns the applied gain (dB).
public enum WAVNormalizer {
    @discardableResult public static func normalize(_ url: URL, targetDBFS: Double) throws -> Double {
        var data = try Data(contentsOf: url)
        guard data.count > 44, String(decoding: data[0..<4], as: UTF8.self) == "RIFF" else { throw ExportError.invalidArchive }
        func u16(_ o: Int) -> Int { Int(data[o]) | Int(data[o + 1]) << 8 }
        func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
        var offset = 12, bits = 24, start = 0, end = 0
        while offset + 8 <= data.count {
            let id = String(decoding: data[offset..<offset + 4], as: UTF8.self), size = u32(offset + 4)
            if id == "fmt " { bits = u16(offset + 22) }
            if id == "data" { start = offset + 8; end = min(data.count, start + size); break }
            offset += 8 + size + (size & 1)
        }
        guard end > start, bits == 16 || bits == 24 else { throw ExportError.invalidArchive }
        let width = bits / 8, full = bits == 16 ? 32_767.0 : 8_388_607.0
        func read(_ o: Int) -> Int {
            if width == 2 { return Int(Int16(bitPattern: UInt16(data[o]) | UInt16(data[o + 1]) << 8)) }
            var v = Int(data[o]) | Int(data[o + 1]) << 8 | Int(data[o + 2]) << 16
            if v & 0x800000 != 0 { v -= 0x1000000 }
            return v
        }
        var peak = 0
        var o = start
        while o + width <= end { peak = max(peak, abs(read(o))); o += width }
        guard peak > 0 else { return 0 }
        let target = full * pow(10, targetDBFS / 20)
        let gain = min(pow(10, 24.0 / 20), target / Double(peak))
        o = start
        while o + width <= end {
            let value = Int(max(-full - 1, min(full, (Double(read(o)) * gain).rounded())))
            let bitsValue = value < 0 ? value + (1 << bits) : value
            data[o] = UInt8(bitsValue & 0xff); data[o + 1] = UInt8((bitsValue >> 8) & 0xff)
            if width == 3 { data[o + 2] = UInt8((bitsValue >> 16) & 0xff) }
            o += width
        }
        try data.write(to: url, options: .atomic)
        return 20 * log10(gain)
    }
}
