import Foundation
public enum StemExporter {
    public static func render(_ project:Project,to destination:URL,settings:WAVSettings=WAVSettings(),range:Range<Int>?=nil,selected:Set<UUID>?=nil,progress:@Sendable(Double)->Void={_ in})async throws->URL {
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
            let receipt=try await OfflineRenderer.render(project,to:url,settings:settings,range:range,isolatedTrack:track.id){value in progress((Double(index)+value)/Double(tracks.count+1))}
            files.append((name,url));info.append(["file":name,"trackID":track.id.uuidString,"role":track.role.rawValue,"gainDB":track.gain,"pan":track.pan,"audible":!track.mute && (!anySolo || track.solo),"frames":receipt.frames,"peak":receipt.peak,"clipped":receipt.clipped])
        }
        let manifest:[String:Any] = ["format":"La Grilla aligned stems","version":1,"tempoBPM":project.bpm,"key":project.keyName,"ppq":ppq,"timeSignature":"4/4","sampleRate":settings.sampleRate,"bitDepth":settings.bitDepth,"channels":2,"tailSeconds":settings.tailSeconds,"startTick":range?.lowerBound ?? 0,"endTick":range?.upperBound ?? project.length,"projectRevision":project.revision,"masterGainApplied":false,"muteSoloApplied":true,"mixNote":"Track gain/pan applied. Master gain excluded. Output protection/PCM rounding can prevent an exact sum when clipping occurs.","tracks":info]
        try Task.checkCancellation();try ProjectArchive.writeFiles(files,extras:[.init("manifest.json",try JSONSerialization.data(withJSONObject:manifest,options:[.sortedKeys,.prettyPrinted]))],to:destination);progress(1);return destination
    }
}
