import Foundation
import SwiftUI
import MusicDomain
import AVFoundation
import Observation

@MainActor @Observable final class Session {
    var project = Project.demo(); var history = History(); let audio = AudioController()
    var selectedSection: UUID?; var tab = 0; var loop = true; var loopBars = 4; var metronome = false
    var quantize: Quantize = .sixteenth; var overdub = true; var countIn = true
    var recording = false; var armed = false; var armClock: UInt64 = 0
    var passClock: UInt64 = 0; var replaceNextPass = false
    struct RawHit {let tick: Int;let sampleFrame: UInt64;let event: DrumEvent}
    var rawHits: [RawHit] = []
    var take: [DrumEvent] = []; var takePattern: UUID?; var takeStart = 0; var takeLength = 0
    private var saveGeneration = 0
    var savedRevision = -1; var saving = false; var saveError: String?; var message: String?
    var entries: [ProjectStore.Entry] = []; var sheet: Sheet?; var shareURL: URL?; var exportedURL: URL?
    var exportPreset:String?
    var exportTask: Task<Void,Never>?
    var exportInProgress=false; var exportProgress=0.0; var exportWarning:String?; var exportError:String?
    private var exportGeneration=0; private var exportedFolder:URL?
    var harmonyPreview=false;private var previewPosition=0;private var previewPlaying=false
    var noteTrackID:UUID?
    var importing=false
    var ready = false; private var bootstrapTask:Task<Void,Never>?; var saveTask: Task<Void,Never>?
    let store: ProjectStore
    enum Sheet: String, Identifiable {case projects, newProject, export, settings, bass, sections, notes, harmony, assistant, voice; var id: String { rawValue }}
    init() {
        let root = ProcessInfo.processInfo.arguments.contains("--uitesting") ? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) : FileManager.default.urls(for: .documentDirectory,in:.userDomainMask)[0].appendingPathComponent("Projects")
        store = ProjectStore(root: root)
    }
    var section: MusicDomain.Section { project.sections.first(where: {$0.id == selectedSection}) ?? project.sections[0] }
    var loopRange: Range<Int> { let start = section.start; return loop ? start..<min(project.length,start + loopBars*barTicks) : 0..<project.length }
    var pending: Bool { audio.playing && audio.appliedRevision != project.revision }
    func bootstrap() async {
        if let bootstrapTask {await bootstrapTask.value;return}
        let task=Task { @MainActor in
            do {
                entries=try await store.list()
                if let first=entries.first(where:{$0.project != nil})?.project {project=first}
                else if entries.isEmpty {try await store.save(project);entries=try await store.list()}
                selectedSection=project.sections[0].id
                try audio.prepare();sync();savedRevision=project.revision
            } catch {message=error.localizedDescription}
            ready=true
        }
        bootstrapTask=task;await task.value
    }
    func ensureAudio() -> Bool { if audio.isPrepared {return true}; do {try audio.prepare(); sync(); return true} catch {audio.error = error.localizedDescription; return false} }
    func sync() { audio.submit(project,loop:loop,range:loopRange); audio.metronome(metronome) }
    func edit(_ change: (inout Project) throws -> Void) {
        mixerGesture=false
        guard !recording && !armed else {message = "Finish the drum take before editing the project.";return}
        do {try history.apply(&project,change); sync(); scheduleSave()} catch {message = error.localizedDescription}
    }
    var mixerGesture = false
    func mixerEdit(_ change: (inout Project) throws -> Void) {
        do { try history.apply(&project, coalescing: mixerGesture, change); mixerGesture = true; sync(); scheduleSave() }
        catch { message = error.localizedDescription }
    }
    func mixerImmediate(_ change: (inout Project) throws -> Void) {
        mixerGesture=false; mixerEdit(change); mixerGesture=false
    }
    func undo() {guard !recording && !armed else {return}; mixerGesture=false;history.undo(&project); sync();scheduleSave()}
    func redo() {guard !recording && !armed else {return}; mixerGesture=false;history.redo(&project); sync();scheduleSave()}
    func scheduleSave() {saveTask?.cancel();saveTask = Task {try? await Task.sleep(for:.milliseconds(700));guard !Task.isCancelled else{return};await save()} }
    func save() async {
        saveGeneration += 1; let generation=saveGeneration
        saving=true; let snapshot=project
        do {
            let writtenRevision=try await store.save(snapshot)
            if project.id==snapshot.id {savedRevision=max(savedRevision,writtenRevision);saveError=nil}
            entries=try await store.list()
        } catch {if project.id==snapshot.id {saveError=error.localizedDescription}}
        if generation==saveGeneration {saving=false}
    }
    func togglePlay() {
        if audio.playing {finishTake();audio.stop()}else if ensureAudio(){if audio.tick>=Double(loopRange.upperBound){audio.seek(loopRange.lowerBound)};audio.play()}
    }
    func rewind() {finishTake();audio.stop();audio.seek(loopRange.lowerBound)}
    func record() {
        if recording || armed {finishTake();return}
        guard ensureAudio(), let t = project.tracks.first(where: {$0.role == .drums}),let clip=t.clips.first(where: {$0.start<=section.start && $0.start+$0.length>section.start}),let p=project.patterns.first(where: {$0.id==clip.patternID}) else{return}
        take = [];rawHits=[];takePattern=p.id;takeStart=clip.start;takeLength=p.length
        let barFrames=audio.sampleRate*240/project.bpm
        if audio.playing {
            let remainder=Double(barTicks)-audio.tick.truncatingRemainder(dividingBy:Double(barTicks))
            armClock=audio.clock+UInt64((remainder/960*60/project.bpm*audio.sampleRate).rounded())
        }else{
            audio.seek(loopRange.lowerBound);audio.play(countInBPM:countIn ? project.bpm : nil)
            armClock=audio.clock+UInt64(countIn ? barFrames : 0)
        }
        passClock=armClock; replaceNextPass = !overdub; armed=true
    }
    func pollRecording() {
        if armed && audio.clock>=armClock { armed=false; recording=true }
        guard recording else { return }
        let frames = UInt64(Double(loopRange.count)/960*60/project.bpm*audio.sampleRate)
        if frames > 0 && audio.clock >= passClock + frames {
            commitPass(); passClock += frames
        }
    }
    func commitPass() {
        guard let id=takePattern else {return}
        let events=take; let replace=replaceNextPass; let active=recording
        let range=loopRange; let start=takeStart
        recording=false
        edit {p in guard let i=p.patterns.firstIndex(where: {$0.id==id}) else{return}
            if replace { p.patterns[i].drums.removeAll { e in
                let absolute=e.tick+start
                return range.contains(absolute)
            }}
            p.patterns[i].drums.append(contentsOf:events)
        }
        recording=active; replaceNextPass=false; take=[];rawHits=[]
    }
    func hit(_ pad: Int) {
        guard ensureAudio() else{return}; audio.pad(pad);pollRecording()
        if recording {
            let local=(Int(audio.tick)-takeStart+takeLength)%takeLength
            let e=DrumEvent(tick:quantize.tick(local,length:takeLength),pad:pad)
            var draft=project
            if let id=takePattern,let i=draft.patterns.firstIndex(where:{$0.id==id}) {
                if replaceNextPass {let range=loopRange;let start=takeStart;draft.patterns[i].drums.removeAll{range.contains($0.tick+start)}}
                draft.patterns[i].drums.append(contentsOf:take+[e])
                do {try draft.validate();take.append(e);rawHits.append(RawHit(tick:local,sampleFrame:audio.clock,event:e))}
                catch {message=error.localizedDescription}
            }
        }
    }
    func finishTake() {
        let hadTake=recording;armed=false;recording=false
        guard hadTake,let id=takePattern else {take=[];return}
        _ = id
        commitPass()
        take=[];Task{await save()}
    }
    func previewHarmony(_ p:Project,section:MusicDomain.Section){
        finishTake();guard ensureAudio()else{return}
        if !harmonyPreview{previewPosition=Int(audio.tick);previewPlaying=audio.playing;harmonyPreview=true}
        audio.audition(p,range:section.start..<section.start+section.length)
    }
    func endHarmonyPreview(){
        guard harmonyPreview else{return};harmonyPreview=false
        if previewPlaying{audio.audition(project,range:loopRange,tick:min(loopRange.upperBound-1,max(loopRange.lowerBound,previewPosition)),loop:loop)}
        else{audio.stop();audio.seek(previewPosition);sync()}
    }
    func openNotes(_ id:UUID?=nil){
        finishTake()
        if let id{noteTrackID=id}
        else if project.tracks.first(where:{$0.id==noteTrackID && $0.role == .melody})==nil{noteTrackID=project.tracks.first{$0.role == .melody}?.id}
        if noteTrackID==nil{addMelody()}
        sheet = .notes
    }
    func addMelody(){finishTake();audio.stop();let count=project.tracks.count;edit{try $0.addMelody()};if project.tracks.count>count{noteTrackID=project.tracks.last?.id}}
    func duplicateMelody(_ id:UUID){finishTake();audio.stop();let count=project.tracks.count;edit{try $0.duplicateTrack(id)};if project.tracks.count>count{noteTrackID=project.tracks.last?.id}}
    func deleteMelody(_ id:UUID){finishTake();audio.stop();edit{try $0.deleteTrack(id)};noteTrackID=project.tracks.first{$0.role == .melody}?.id}
    func setLoop(bars: Int? = nil, enabled: Bool? = nil) {guard !recording && !armed else{message="Finish the take before changing the loop.";return};if let bars{loopBars=bars};if let enabled{loop=enabled};sync()}
    func select(_ section: MusicDomain.Section) {guard !recording && !armed else{return};selectedSection=section.id;sync();if !audio.playing{audio.seek(section.start)}}
    func open(_ p: Project, force: Bool = false) async {
        if !force && p.id==project.id {sheet=nil;return}
        if exportInProgress{cancelExport()}
        finishTake();audio.stop();await save()
        guard saveError==nil else {message="Save the current project or save a copy before opening another project.";return}
        project=p;history=History();selectedSection=p.sections[0].id;savedRevision=p.revision;audio.seek(0);sync();sheet=nil
    }
    func create(name: String,bpm: Double,root: Int,minor: Bool,bars: Int) async {
        var p=Project(name:name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? "Untitled" : name,bars:bars);p.bpm=bpm;p.keyRoot=root;p.minor=minor
        await open(p);await save()
    }
    func duplicateProject(_ p:Project) async {do{_ = try await store.duplicate(p.id==project.id ? project:p);entries=try await store.list()}catch{message=error.localizedDescription}}
    func delete(_ id: UUID) async {do{try await store.delete(id);entries=try await store.list()}catch{message=error.localizedDescription}}
    func recover(_ id:UUID)async{do{let original=try await store.load(id,backup:true);let p=try await store.duplicate(original,suffix:" recovered");await open(p,force:true);if project.id==p.id{await save();message="Recovered the last working copy."}}catch{message=error.localizedDescription}}
    enum ExportFormat:String,CaseIterable,Identifiable {
        case midi,wav,stems,project
        var id:String{rawValue}
        var title:String{switch self{case .midi:"Standard MIDI";case .wav:"Stereo WAV";case .stems:"Aligned stems";case .project:"Portable project"}}
        var fileExtension:String{switch self{case .midi:"mid";case .wav:"wav";case .stems:"zip";case .project:"grillapack"}}
    }
    func export(format:ExportFormat,settings:WAVSettings,range:Range<Int>,tracks:Set<UUID>) {
        finishTake();cancelExport();exportGeneration+=1;let generation=exportGeneration
        let snapshot=project;exportInProgress=true;exportProgress=0;exportWarning=nil
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("GrillaExport-"+UUID().uuidString)
        let safe=String(snapshot.name.prefix(80)).replacingOccurrences(of:"/",with:"-").replacingOccurrences(of:"\\",with:"-")
        let url=folder.appendingPathComponent(safe.isEmpty ? "La Grilla":safe).appendingPathExtension(format.fileExtension)
        exportError=nil
        exportTask=Task { @MainActor in
            do {
                try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                let progress:@Sendable(Double)->Void={ [weak self] value in Task { @MainActor in guard let self,self.exportGeneration==generation else{return};self.exportProgress=value } }
                switch format {
                case .midi:try MIDIExporter.data(snapshot,range:range).write(to:url,options:.atomic)
                case .project:try await store.portable(snapshot,to:url)
                case .wav:
                    let receipt=try await OfflineRenderer.render(snapshot,to:url,settings:settings,range:range,progress:progress)
                    if receipt.clipped{exportWarning="Clipping was detected. Lower track or master gain for a cleaner export."}
                case .stems:_ = try await StemExporter.render(snapshot,to:url,settings:settings,range:range,selected:tracks,progress:progress)
                }
                try Task.checkCancellation();guard generation==exportGeneration else{return}
                exportProgress=1;exportInProgress=false;exportedFolder=folder;exportedURL=url;sheet=nil;exportTask=nil
            } catch {
                try? FileManager.default.removeItem(at:folder)
                if generation==exportGeneration{exportInProgress=false;exportTask=nil;if !(error is CancellationError){exportError=error.localizedDescription}}
            }
        }
    }
    func cancelExport(){exportGeneration+=1;exportTask?.cancel();exportTask=nil;exportInProgress=false;exportProgress=0}
    func finishSharing() {
        if let folder=exportedFolder{Task{try? await Task.sleep(for:.seconds(1));try? FileManager.default.removeItem(at:folder)}}
        exportedFolder=nil
        if let warning=exportWarning{message=warning;exportWarning=nil}
    }
    func importProject(_ url:URL) async {
        await bootstrap();importing=true;defer{importing=false}
        let access=url.startAccessingSecurityScopedResource();defer{if access{url.stopAccessingSecurityScopedResource()}}
        do {
            let imported=try await Task.detached(priority:.userInitiated){
                let handle=try FileHandle(forReadingFrom:url);defer{try? handle.close()}
                let data=try handle.read(upToCount:128_000_001) ?? Data();guard data.count<=128_000_000 else{throw ExportError.archiveTooLarge}
                return try PortableProject.decodeBundle(data)
            }.value
            let installed=try await store.install(imported);await open(installed);if project.id==installed.id{await save()}
        }catch{message=error.localizedDescription}
    }
    func applyVoice(_ placement:VoicePlacement,data:Data,record:AudioAssetRecord,projectID:UUID,revision:Int)async throws->Bool {
        guard project.id==projectID,project.revision==revision,!recording,!armed else{throw AssistantError.stale}
        try await store.writeAsset(data,record:record,projectID:projectID)
        guard project.id==projectID,project.revision==revision else{await store.removeStagedAsset(record,projectID:projectID);throw AssistantError.stale}
        do{try history.apply(&project){$0=placement.project}}
        catch{await store.removeStagedAsset(record,projectID:projectID);throw error}
        noteTrackID=placement.trackID;sync();await save();return saveError==nil
    }
    func saveCopy()async{do{_ = try await store.duplicate(project);message="A copy has been saved.";entries=try await store.list()}catch{message=error.localizedDescription}}
    func interrupt() {harmonyPreview=false;finishTake();audio.reset();Task{await save()}}
}
