import Foundation
import SwiftUI
import MusicDomain
import AVFoundation
import Observation

@MainActor @Observable final class Session {
    var project = Project.demo(){didSet{reconcileEditorSelection()}}; var history = History(); let audio = AudioController()
    @ObservationIgnored lazy var performance=PerformanceController(audio:audio)
    @ObservationIgnored lazy var midi:MIDIController={
        let controller=MIDIController(hub:audio.midiHub)
        controller.onConfigurationChange={ [weak self] in self?.syncMIDI() }
        controller.onLearn={ [weak self] mapping in self?.edit{p in var settings=p.midi ?? MIDISettings();settings.mappings.removeAll{$0.sourceID==mapping.sourceID && $0.channel==mapping.channel && $0.controller==mapping.controller};settings.mappings.append(mapping);p.midi=settings} }
        controller.onControl={ [weak self] mapping,value in self?.applyMIDI(mapping,value:value) }
        return controller
    }()
    var displayProject:Project{performance.contextActive ? (performance.runtimeProject ?? project):(drumPlayback ?? project)}
    var selectedSection: UUID?{didSet{if selectedSection != oldValue{noteClipID=nil;drumClipID=nil}}}; var tab = 0; var loop = true; var loopBars = 4; var metronome = false
    var quantize: Quantize = .sixteenth; var overdub = true; var countIn = true
    var recording = false; var armed = false; var armClock: UInt64 = 0
    var passClock: UInt64 = 0; var replaceNextPass = false
    struct RawHit {let tick: Int;let sampleFrame: UInt64;let event: DrumEvent}
    var rawHits: [RawHit] = []
    var take: [DrumEvent] = []; var takePattern: UUID?; var takeStart = 0; var takeLength = 0
    private var drumDraft:DrumRecordingDraft?;private var drumPlayback:Project?
    private var saveGeneration = 0
    var savedRevision = -1; var saving = false; var saveError: String?; var message: String?
    var entries: [ProjectStore.Entry] = []; var sheet: Sheet?; var shareURL: URL?; var exportedURL: URL?
    var exportPreset:String?;var exportTake:PerformanceTake?
    var exportTask: Task<Void,Never>?
    var exportInProgress=false; var exportProgress=0.0; var exportWarning:String?; var exportError:String?
    private var exportGeneration=0; private var exportedFolder:URL?
    var harmonyPreview=false;private var previewPosition=0;private var previewPlaying=false
    var noteTrackID:UUID?{didSet{if noteTrackID != oldValue{noteClipID=nil}}}
    var noteClipID:UUID?;var drumClipID:UUID?
    var importing=false
    private var backgrounded=false
    private var microphoneOwner:UUID?
    @ObservationIgnored private var stopMicrophone:(()->Void)?
    @ObservationIgnored private var remoteStarting=false
    private var remoteActive=false
    @ObservationIgnored private lazy var remote=NowPlayingController{ [weak self] action in self?.remoteCommand(action) }
    var ready = false; private var bootstrapTask:Task<Void,Never>?; var saveTask: Task<Void,Never>?
    let store: ProjectStore
    enum Sheet: String, Identifiable {case projects, newProject, export, settings, bass, sections, notes, harmony, assistant, voice, perform, midiDevices; var id: String { rawValue }}
    init() {
        let root = ProcessInfo.processInfo.arguments.contains("--uitesting") ? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) : FileManager.default.urls(for: .documentDirectory,in:.userDomainMask)[0].appendingPathComponent("Projects")
        store = ProjectStore(root: root)
        audio.onPoll={ [weak self] in self?.pollRecording() }
    }
    var section: MusicDomain.Section { displayProject.sections.first(where: {$0.id == selectedSection}) ?? displayProject.sections[0] }
    var loopRange: Range<Int> {if performance.contextActive{return section.start..<section.start+section.length};if loop,let clip=focusedDrumClip{return clip.start..<clip.start+clip.length};let start = section.start; return loop ? start..<min(project.length,start + loopBars*barTicks) : 0..<project.length }
    var pending: Bool { !performance.contextActive && audio.playing && audio.pendingSnapshot }
    private var focusedDrumClip:Clip?{guard let drumClipID else{return nil};return project.tracks.first{$0.role == .drums}?.clips.first{$0.id==drumClipID}}
    private func reconcileEditorSelection(){
        if !project.sections.contains(where:{$0.id==selectedSection}){selectedSection=project.sections.first?.id}
        if let noteTrackID,!project.tracks.contains(where:{$0.id==noteTrackID && $0.role == .melody}){self.noteTrackID=project.tracks.first{$0.role == .melody}?.id}
        if let noteClipID,!project.tracks.contains(where:{$0.id==noteTrackID && $0.clips.contains{$0.id==noteClipID}}){self.noteClipID=nil}
        if let drumClipID,!project.tracks.contains(where:{$0.role == .drums && $0.clips.contains{$0.id==drumClipID}}){self.drumClipID=nil}
    }
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
    func ensureAudio() -> Bool {guard !backgrounded || remoteStarting else{return false}; if audio.isPrepared {return true}; do {try audio.prepare(); sync(); return true} catch {audio.error = error.localizedDescription; return false} }
    func syncMIDI(){guard !backgrounded || audio.playing || remoteStarting else{return};if let adopted=audio.activeMIDIRouting{midi.configure(adopted.midi,tracks:adopted.tracks)}else if !audio.playing{midi.configure(project.midi ?? MIDISettings(),tracks:project.tracks)}}
    func ownsMicrophone(_ owner:UUID)->Bool{microphoneOwner==owner && !backgrounded}
    func beginMicrophone(stop:@escaping()->Void)->UUID? {
        guard !backgrounded else{return nil}
        stopMicrophone?()
        let owner=UUID();microphoneOwner=owner;stopMicrophone=stop;return owner
    }
    func endMicrophone(_ owner:UUID){
        guard microphoneOwner==owner else{return}
        microphoneOwner=nil;stopMicrophone=nil
        if !backgrounded,UIApplication.shared.applicationState == .active{syncMIDI()}
        else{suspendIdleAudio()}
    }
    func sceneChanged(_ phase:ScenePhase){
        if phase == .active{backgrounded=false;if ready{_ = ensureAudio();syncMIDI()};return}
        finishTake();Task{await save()}
        if phase == .background{backgrounded=true;stopMicrophone?();microphoneOwner=nil;stopMicrophone=nil;if harmonyPreview{endHarmonyPreview()};suspendIdleAudio()}
    }
    private func suspendIdleAudio(){
        guard backgrounded,!audio.playing,!performance.stopping else{return}
        midi.suspend();audio.reset();try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation)
    }
    private func updateNowPlaying(){
        guard !harmonyPreview else{return}
        if audio.playing{remoteActive=true}
        guard remoteActive else{return}
        let source=displayProject,seconds=performance.contextActive ? performance.seconds:audio.tick/Double(ppq)*60/source.bpm
        remote.update(title:source.name,seconds:seconds,duration:Double(source.length)/Double(ppq)*60/source.bpm,playing:audio.playing)
    }
    private func remoteCommand(_ action:StudioRemoteAction){
        switch action {
        case .play:if !audio.playing{remoteStarting=true;togglePlay();remoteStarting=false}
        case .pause:if audio.playing{togglePlay()}
        case .toggle:remoteStarting=true;togglePlay();remoteStarting=false
        case .stop:interrupt();remote.clear();remoteActive=false
        }
        updateNowPlaying();suspendIdleAudio()
    }
    func sync() {
        if performance.contextActive{if let p=performance.runtimeProject{audio.mix(p)};syncMIDI();return}
        if let drumDraft{drumPlayback=try? drumDraft.candidate(for:project)}else{drumPlayback=nil}
        audio.submit(drumPlayback ?? project,loop:loop,range:loopRange);audio.metronome(metronome);syncMIDI()
    }
    func edit(_ change: (inout Project) throws -> Void) {
        mixerGesture=false
        guard !performance.contextActive else{message="Return to editing before changing the source project.";return}
        guard !recording && !armed else {message = "Finish the drum take before editing the project.";return}
        do {try history.apply(&project,change); sync(); scheduleSave()} catch {message = error.localizedDescription}
    }
    var mixerGesture = false
    func mixerEdit(_ change: (inout Project) throws -> Void) {
        if performance.contextActive{do{try performance.editMix(change)}catch{message=error.localizedDescription};return}
        do { try history.apply(&project, coalescing: mixerGesture, change); mixerGesture = true; sync(); scheduleSave() }
        catch { message = error.localizedDescription }
    }
    func mixerImmediate(_ change: (inout Project) throws -> Void) {
        mixerGesture=false; mixerEdit(change); mixerGesture=false
    }
    func undo() {if performance.contextActive{Task{await leavePerformance();undo()};return};guard !recording && !armed else {return}; mixerGesture=false;history.undo(&project); sync();scheduleSave()}
    func redo() {if performance.contextActive{Task{await leavePerformance();redo()};return};guard !recording && !armed else {return}; mixerGesture=false;history.redo(&project); sync();scheduleSave()}
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
        if performance.contextActive{if performance.playing || performance.starting{Task{await performance.stop();pollPerformance()}}else if performance.replaying,let take=performance.replayTake{replayPerformance(take)}else{startPerformance(record:false)};return}
        if audio.playing {finishTake();audio.stop()}else if ensureAudio(){if audio.tick>=Double(loopRange.upperBound){audio.seek(loopRange.lowerBound)};audio.play()}
    }
    func rewind() {if performance.contextActive{Task{await leavePerformance();rewind()};return};finishTake();audio.stop();audio.seek(loopRange.lowerBound)}
    func record() {
        guard !performance.contextActive else{message="Return to editing before recording a drum loop.";return}
        if recording || armed {finishTake();return}
        guard ensureAudio(),let track=project.tracks.first(where:{$0.role == .drums}),let clip=focusedDrumClip ?? track.clips.first(where:{$0.start<=section.start && $0.start+$0.length>section.start})else{return}
        do{drumDraft=try DrumRecordingDraft(project:project,clipID:clip.id)}catch{message=error.localizedDescription;return}
        audio.refreshClock()
        take=[];rawHits=[];takePattern=drumDraft?.patternID;takeStart=clip.start;takeLength=clip.length
        let barFrames=audio.sampleRate*240/project.bpm
        if audio.playing {
            let remainder=Double(barTicks)-audio.tick.truncatingRemainder(dividingBy:Double(barTicks))
            armClock=audio.clock+UInt64((remainder/960*60/project.bpm*audio.sampleRate).rounded())
        }else{
            audio.seek(loopRange.lowerBound);audio.play(countInBPM:countIn ? project.bpm : nil)
            armClock=audio.clock+UInt64(countIn ? barFrames : 0)
        }
        passClock=armClock;replaceNextPass = !overdub;armed=true;sync()
    }
    func pollRecording() {
        syncMIDI();midi.poll(replaying:performance.replaying);pollPerformance()
        updateNowPlaying()
        if backgrounded,!audio.playing{suspendIdleAudio();return}
        if armed && audio.clock>=armClock { armed=false; recording=true }
        guard recording else { return }
        let frames = UInt64(Double(loopRange.count)/960*60/project.bpm*audio.sampleRate)
        if frames > 0 && audio.clock >= passClock + frames {
            commitPass(); passClock += frames
        }
    }
    func commitPass() {
        guard var draft=drumDraft else{return}
        do{try draft.commitPass(take,replacing:replaceNextPass ? loopRange:nil);drumDraft=draft;replaceNextPass=false;take=[];rawHits=[];sync()}
        catch{message=error.localizedDescription;take=[];rawHits=[]}
    }
    func hit(_ pad: Int) {
        guard !performance.replaying,ensureAudio() else{return};audio.refreshClock();audio.pad(pad);pollRecording()
        if recording {
            guard let draft=drumDraft,let local=draft.localTick(Int(audio.tick))else{return}
            let e=DrumEvent(tick:quantize.tick(local,length:takeLength),pad:pad)
            do{var check=draft;try check.commitPass(take+[e],replacing:replaceNextPass ? loopRange:nil);take.append(e);rawHits.append(RawHit(tick:local,sampleFrame:audio.clock,event:e))}
            catch{message=error.localizedDescription}
        }
    }
    func finishTake() {
        let hadTake=recording;armed=false;recording=false
        if hadTake{commitPass()}
        let finished=drumDraft;drumDraft=nil;drumPlayback=nil;take=[];rawHits=[];takePattern=nil
        if let finished,finished.changed{edit{$0=try finished.candidate(for:$0)}}else if finished != nil{sync()}
    }
    func previewHarmony(_ p:Project,section:MusicDomain.Section){
        previewAssistant(p,wholeSong:false,sectionID:section.id)
    }
    func previewAssistant(_ candidate:Project,wholeSong:Bool,sectionID:UUID){
        guard !performance.contextActive else{message="Return to editing before changing the source project.";return}
        finishTake();guard ensureAudio()else{return}
        guard candidate.id==project.id,candidate.revision==project.revision,let section=candidate.sections.first(where:{$0.id==sectionID})else{message=AssistantError.stale.localizedDescription;return}
        do{try candidate.validate()}catch{message=error.localizedDescription;return}
        if !harmonyPreview{previewPosition=Int(audio.tick);previewPlaying=audio.playing;harmonyPreview=true}
        audio.audition(candidate,range:wholeSong ? 0..<candidate.length:section.start..<section.start+section.length);syncMIDI()
    }
    func endHarmonyPreview(){
        guard harmonyPreview else{return};harmonyPreview=false
        if previewPlaying{audio.submit(project,loop:loop,range:loopRange);syncMIDI()}
        else{audio.stop();audio.seek(previewPosition);sync()}
    }
    func presentEditor(_ sheet:Sheet){if performance.contextActive{Task{await leavePerformance();self.sheet=sheet}}else{finishTake();self.sheet=sheet}}
    func openNotes(_ id:UUID?=nil,clipID:UUID?=nil){
        if performance.contextActive{Task{await leavePerformance();openNotes(id,clipID:clipID)};return}
        finishTake()
        if let id{noteTrackID=id}
        else if project.tracks.first(where:{$0.id==noteTrackID && $0.role == .melody})==nil{noteTrackID=project.tracks.first{$0.role == .melody}?.id}
        if noteTrackID==nil{addMelody()}
        noteClipID=clipID;reconcileEditorSelection()
        sheet = .notes
    }
    func openDrumClip(_ clipID:UUID){
        guard !performance.contextActive else{message="Return to editing before changing the source project.";return}
        finishTake();guard let clip=project.tracks.first(where:{$0.role == .drums})?.clips.first(where:{$0.id==clipID})else{return}
        if let section=project.sections.first(where:{$0.start<=clip.start && $0.start+$0.length>clip.start}){selectedSection=section.id}
        drumClipID=clipID;tab=1;sync();if !audio.playing{audio.seek(clip.start)}
    }
    func addMelody(){finishTake();let count=project.tracks.count;edit{try $0.addMelody()};if project.tracks.count>count{noteTrackID=project.tracks.last?.id}}
    func duplicateMelody(_ id:UUID){finishTake();let count=project.tracks.count;edit{try $0.duplicateTrack(id)};if project.tracks.count>count{noteTrackID=project.tracks.last?.id}}
    func deleteMelody(_ id:UUID){finishTake();edit{try $0.deleteTrack(id)};noteTrackID=project.tracks.first{$0.role == .melody}?.id}
    func setLoop(bars: Int? = nil, enabled: Bool? = nil) {guard !recording && !armed else{message="Finish the take before changing the loop.";return};if let bars{loopBars=bars};if let enabled{loop=enabled};sync()}
    func select(_ section: MusicDomain.Section) {if performance.contextActive{performance.queueSection(section.id);return};guard !recording && !armed else{return};selectedSection=section.id;sync();if !audio.playing{audio.seek(section.start)}}
    func open(_ p: Project, force: Bool = false) async {
        if performance.contextActive{await leavePerformance()}
        if !force && p.id==project.id {sheet=nil;return}
        if exportInProgress{cancelExport()}
        finishTake();audio.stop();await save()
        guard saveError==nil else {message="Save the current project or save a copy before opening another project.";return}
        project=p;history=History();noteTrackID=nil;noteClipID=nil;drumClipID=nil;selectedSection=p.sections[0].id;savedRevision=p.revision;audio.seek(0);sync();sheet=nil
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
    func export(format:ExportFormat,settings:WAVSettings,range:Range<Int>,tracks:Set<UUID>,performance:PerformanceTake?=nil) {
        if performance != nil && format != .midi && format != .wav{exportError="Choose WAV or MIDI for a performance.";return}
        finishTake();cancelExport();exportGeneration+=1;let generation=exportGeneration
        let snapshot=performance?.source ?? project;exportInProgress=true;exportProgress=0;exportWarning=nil
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("GrillaExport-"+UUID().uuidString)
        let safe=String((performance?.name ?? snapshot.name).prefix(80)).components(separatedBy:CharacterSet(charactersIn:"/\\").union(.controlCharacters)).joined(separator:"-").trimmingCharacters(in:CharacterSet(charactersIn:". "))
        let url=folder.appendingPathComponent(safe.isEmpty ? "La Grilla":safe).appendingPathExtension(format.fileExtension)
        exportError=nil
        exportTask=Task { @MainActor in
            do {
                try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                let progress:@Sendable(Double)->Void={ [weak self] value in Task { @MainActor in guard let self,self.exportGeneration==generation else{return};self.exportProgress=value } }
                switch format {
                case .midi:let data=try await Task.detached(priority:.userInitiated){if let performance{return try PerformanceTimeline.midi(performance)};return try MIDIExporter.data(snapshot,range:range)}.value;try Task.checkCancellation();try data.write(to:url,options:.atomic)
                case .project:try await store.portable(snapshot,to:url)
                case .wav:
                    let receipt:RenderReceipt;if let performance{receipt=try await OfflineRenderer.renderPerformance(performance,to:url,settings:settings,progress:progress)}else{receipt=try await OfflineRenderer.render(snapshot,to:url,settings:settings,range:range,progress:progress)}
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
        guard project.id==projectID,project.revision==revision,!recording,!armed,!performance.contextActive else{throw AssistantError.stale}
        try await store.writeAsset(data,record:record,projectID:projectID)
        guard project.id==projectID,project.revision==revision,!recording,!armed,!performance.contextActive else{await store.removeStagedAsset(record,projectID:projectID);throw AssistantError.stale}
        do{try history.apply(&project){$0=placement.project}}
        catch{await store.removeStagedAsset(record,projectID:projectID);throw error}
        noteTrackID=placement.trackID;sync();await save();return saveError==nil
    }
    func startPerformance(record:Bool){
        finishTake();guard ensureAudio()else{return};mixerGesture=false
        do{let id=project.sections.first(where:{$0.id==selectedSection})?.id ?? project.sections[0].id;try performance.begin(project,sectionID:id,record:record)}catch{performance.error=error.localizedDescription}
    }
    func replayPerformance(_ take:PerformanceTake){finishTake();guard ensureAudio()else{return};do{try performance.playTake(take)}catch{performance.error=error.localizedDescription}}
    func pollPerformance(){
        performance.poll()
        if performance.contextActive,let id=performance.activeSectionID{selectedSection=id}
        guard let take=performance.takeReady else{return}
        guard take.source.id==project.id else{performance.error="The project changed. Export the performance before closing it.";return}
        do{try history.apply(&project){$0.performanceTake=take};performance.takeReady=nil;scheduleSave()}
        catch{performance.error=error.localizedDescription}
    }
    func leavePerformance()async{await performance.exit();pollPerformance();mixerGesture=false;audio.invalidateMusicSnapshot();sync();audio.seek(loopRange.lowerBound)}
    func commitPerformanceMix(){
        guard !performance.recording,!performance.replaying,let runtime=performance.runtimeProject,runtime.tracks.map(\.id)==project.tracks.map(\.id)else{return}
        do{try history.apply(&project){p in for i in p.tracks.indices{p.tracks[i].gain=runtime.tracks[i].gain;p.tracks[i].pan=runtime.tracks[i].pan;p.tracks[i].mute=runtime.tracks[i].mute;p.tracks[i].solo=runtime.tracks[i].solo};p.master=runtime.master;p.masterFX=runtime.masterFX};scheduleSave()}catch{performance.error=error.localizedDescription}
    }
    func applyMIDI(_ mapping:MIDIMapping,value:Double){
        guard !performance.replaying else{return}
        if performance.contextActive,mapping.target == .filter{performance.setEffects(filter:value);return}
        if performance.contextActive,mapping.target == .delay{performance.setEffects(delay:value);return}
        mixerEdit{p in switch mapping.target {
        case .masterGain:p.master=value
        case .trackGain:if let i=p.tracks.firstIndex(where:{$0.id==mapping.trackID}){p.tracks[i].gain=value}
        case .trackPan:if let i=p.tracks.firstIndex(where:{$0.id==mapping.trackID}){p.tracks[i].pan=value}
        case .filter:var fx=p.masterFX ?? MasterFX();fx.filter=value;p.masterFX=fx
        case .delay:var fx=p.masterFX ?? MasterFX();fx.delayWet=value;p.masterFX=fx
        }}
    }
    func saveCopy()async{do{_ = try await store.duplicate(project);message="A copy has been saved.";entries=try await store.list()}catch{message=error.localizedDescription}}
    /// Emergency MIDI stop must complete even if the current audio route is no
    /// longer delivering render callbacks to acknowledge a queued stop command.
    func panicMIDI(){interrupt();_ = ensureAudio()}
    func interrupt() {stopMicrophone?();microphoneOwner=nil;stopMicrophone=nil;if performance.contextActive{performance.finalizeBeforeReset();pollPerformance()};harmonyPreview=false;finishTake();midi.suspend();midi.retry();audio.reset();Task{await save()}}
}
