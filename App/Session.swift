import Foundation
import SwiftUI
import UIKit
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
    var selectedSection: UUID?{didSet{if selectedSection != oldValue{noteClipID=nil;drumClipID=nil;rememberWorkspace()}}}; var tab = 0{didSet{if tab != oldValue{rememberWorkspace()}}}; var loop = true; var loopBars = 4; var metronome = false
    var quantize: Quantize = .sixteenth; var overdub = true; var countIn = true
    /// I06/I07: how far recorded hits move to the grid (1 = fully) and swing (0.5 = straight).
    var quantizeStrength = 1.0; var swing = 0.5
    var recording = false; var armed = false; var armClock: UInt64 = 0
    var passClock: UInt64 = 0; var replaceNextPass = false
    struct RawHit {let tick: Int;let sampleFrame: UInt64;let event: DrumEvent}
    var rawHits: [RawHit] = []
    private struct PadRecordingInput {let pad:Int;let tick:Int;let clock:UInt64;var velocity:Int=100}
    /// I09: recent live hits played without Record, kept for "Keep the last bars".
    @ObservationIgnored private var retroHits=PadRetroBuffer(capacity:1024)
    /// I04: take each hit's velocity from the touch (off: every hit is 100).
    var padVelocityFromTouch=false
    /// I01/I02: measured click-to-tap offset per output route (ms), applied to recorded hits only.
    var routeLatency:[String:Double]=(UserDefaults.standard.dictionary(forKey:"studio.routeLatency") as? [String:Double]) ?? [:]
    var currentRouteKey:String{AVAudioSession.sharedInstance().currentRoute.outputs.first.map{$0.portType.rawValue} ?? "unknown"}
    func saveRouteLatency(_ milliseconds:Double?){
        routeLatency[currentRouteKey]=milliseconds
        UserDefaults.standard.set(routeLatency,forKey:"studio.routeLatency")
    }
    @ObservationIgnored private var pendingPadInputs:[PadRecordingInput]=[]
    @ObservationIgnored private var drumPass:DrumRecordingPass?
    /// Read-only inspection of events already drained from the contact queue.
    var take:[DrumEvent]{drumPass?.events ?? []}
    @ObservationIgnored private var acceptedPadHits=0
    @ObservationIgnored private var lastPadDispatchMilliseconds=0.0
    var takePattern: UUID?; var takeStart = 0; var takeLength = 0
    private var drumDraft:DrumRecordingDraft?;private var drumPlayback:Project?
    private var saveGeneration = 0
    var savedRevision = -1; var saving = false; var saveError: String?; var message: String?
    /// U26: when the song last reached the disk, and how it was when it was opened.
    var savedAt: Date?
    var openedAt: Date?
    @ObservationIgnored var openedSnapshot: Project?
    var entries: [ProjectStore.SummaryEntry] = []; var sheet: Sheet?{didSet{if oldValue == .notes,sheet != .notes{selectedNoteID=nil};if sheet == .notes,oldValue != .notes{StudioSignposts.beginPianoRoll()}}}; var shareURL: URL?; var exportedURL: URL?
    private struct LibraryLoadFailure {let revision:Int;let modified:Date;let error:String}
    @ObservationIgnored private var libraryLoadFailures:[UUID:LibraryLoadFailure]=[:]
    private struct ProjectIdentity:Equatable {let id:UUID;let revision:Int}
    private enum ProjectChangeError:Error,LocalizedError {
        case busy,changed,needsWorkingCopy
        var errorDescription:String? {
            let key=switch self {
            case .busy:"Another project change is in progress. Try again when it finishes."
            case .changed:"Your project changed during this operation. Your latest edits are kept. Try again."
            case .needsWorkingCopy:"The stored project needs recovery. Save a copy of your working project before opening another project."
            }
            return NSLocalizedString(key,comment:"Safe project change")
        }
    }
    @ObservationIgnored private var projectChangeToken:UUID?
    @ObservationIgnored private var projectChangeQAInterleave:(@MainActor (String)async->Void)?
    @ObservationIgnored private var projectChangeQAGateObservation:[String:Any]=[:]
    var projectChangeQAReport=""
    var projectChangeQAEnabled:Bool{let a=ProcessInfo.processInfo.arguments;return a.contains("--uitesting") && a.contains("--project-change-probe")}
    var exportPreset:String?;var exportTake:PerformanceTake?
    var exportTask: Task<Void,Never>?
    var exportInProgress=false; var exportProgress=0.0; var exportWarning:String?; var exportError:String?
    private var exportGeneration=0; private var exportedFolder:URL?
    @ObservationIgnored private var previewingNewTrack = false
    @ObservationIgnored private var draftEndTick: Int?
    @ObservationIgnored private var draftTailStart: UInt64?
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
    let runtimeTraceEnabled=ProcessInfo.processInfo.arguments.contains("--uitesting") && ProcessInfo.processInfo.arguments.contains("--runtime-trace")
    private var runtimeTraceEvents:[String]=[]
    @ObservationIgnored private var runtimeTraceSequence=0
    private let runtimeTraceStart=ProcessInfo.processInfo.systemUptime
    let personalKits: PersonalKitStore
    let store: ProjectStore
    enum Sheet: String, Identifiable {case projects, newProject, trackBuilder, export, settings, gettingStarted, bass, sections, notes, harmony, assistant, voice, perform, midiDevices, palettes, history, versions, trash, commands, variations, comp, chordImport, melodyIdeas, lyrics, master, mood, doctor, earTraining, whatsNew, coNotes, vj, help, grooves, practicePlayer, beatMachine, tuner, markers, dynamics, automation, course, audioTracks, plugins, arpeggiator; var id: String { rawValue }}
    private static var qaProjectStoreID:UUID? {
        let arguments=ProcessInfo.processInfo.arguments
        guard arguments.contains("--uitesting"),let index=arguments.firstIndex(of:"--project-store-id"),arguments.indices.contains(index+1)else{return nil}
        return UUID(uuidString:arguments[index+1])
    }
    private var lastProjectKey:String {
        guard ProcessInfo.processInfo.arguments.contains("--uitesting")else{return "studio.lastProjectID"}
        if let id=Self.qaProjectStoreID{return "studio.qa.\(id.uuidString).lastProjectID"}
        return "studio.qa.lastProjectID"
    }
    private func generatedLoopKey(_ id:UUID)->String{lastProjectKey+".generatedLoop."+id.uuidString}
    private func restoreGeneratedLoop(){
        guard let value=UserDefaults.standard.dictionary(forKey:generatedLoopKey(project.id)),let bars=value["bars"] as? Int,(1...64).contains(bars),let enabled=value["enabled"] as? Bool else{return}
        loopBars=min(bars,max(1,(project.length-section.start)/barTicks));loop=enabled
    }
    private func saveGeneratedLoopPreference(){
        let key=generatedLoopKey(project.id)
        guard UserDefaults.standard.dictionary(forKey:key) != nil else{return}
        UserDefaults.standard.set(["bars":loopBars,"enabled":loop],forKey:key)
    }
    func adoptGeneratedSketchLoop(bars:Int){
        guard (1...64).contains(bars),!recording,!armed else{return}
        UserDefaults.standard.set(["bars":bars,"enabled":true],forKey:generatedLoopKey(project.id))
        setLoop(bars:bars,enabled:true)
    }
    private func copyGeneratedLoopPreference(from source:UUID,to copy:UUID){
        if let value=UserDefaults.standard.dictionary(forKey:generatedLoopKey(source)){UserDefaults.standard.set(value,forKey:generatedLoopKey(copy))}
    }
    private func initializeImportedListeningPreference(_ imported:Project){
        let key=generatedLoopKey(imported.id)
        // A finite song keeps its composed ending on a fresh device. Later
        // changes to loop mode and range belong to the imported document.
        guard UserDefaults.standard.dictionary(forKey:key)==nil else{return}
        UserDefaults.standard.set(["bars":imported.length/barTicks,"enabled":imported.hasComposedEnding != true],forKey:key)
    }
    init() {
        let root:URL
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            // A UUID-scoped native test may relaunch against the same real
            // documents. The default remains disposable per launch, and no
            // testing path or preference can address production projects.
            let folder=Self.qaProjectStoreID.map{"StudioQA-"+$0.uuidString} ?? UUID().uuidString
            root=FileManager.default.temporaryDirectory.appendingPathComponent(folder,isDirectory:true)
        }else{root=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("Projects")}
        personalKits = PersonalKitStore(root: root.appendingPathComponent("PersonalKits", isDirectory: true))
        store = ProjectStore(root: root)
        audio.onPoll={ [weak self] in self?.pollRecording() }
        if runtimeTraceEnabled{audio.onRuntimeTrace={ [weak self] event in self?.runtimeTrace(event) }}
    }
    func runtimeTrace(_ event:String){
        guard runtimeTraceEnabled else{return}
        runtimeTraceSequence+=1
        let elapsed=String(format:"%.3f",ProcessInfo.processInfo.systemUptime-runtimeTraceStart)
        runtimeTraceEvents.append("\(runtimeTraceSequence) +\(elapsed)s \(event) | \(runtimeTraceCurrentState)")
        if runtimeTraceEvents.count>96{runtimeTraceEvents.removeFirst(runtimeTraceEvents.count-96)}
    }
    private var runtimeTraceCurrentState:String{
        "ready=\(ready) backgrounded=\(backgrounded) project=\(project.id) revision=\(project.revision) preview=\(harmonyPreview) loopBars=\(loopBars) loopEnabled=\(loop) loopRangeStart=\(loopRange.lowerBound) loopRangeEnd=\(loopRange.upperBound) loopRangeCount=\(loopRange.count) outputPeak=\(audio.meters[masterBus]) padAccepted=\(acceptedPadHits) padUIWaitMs=\(lastPadDispatchMilliseconds) recordedHits=\(drumPass?.events.count ?? 0) saveError=\(saveError ?? "none") | \(audio.runtimeTraceState)"
    }
    var runtimeTraceReport:String{
        guard runtimeTraceEnabled else{return ""}
        return "CURRENT | \(runtimeTraceCurrentState)\n"+runtimeTraceEvents.joined(separator:"\n")+(projectChangeQAReport.isEmpty ? "":"\nPROJECT_CHANGE_QA "+projectChangeQAReport)
    }
    var section: MusicDomain.Section { displayProject.sections.first(where: {$0.id == selectedSection}) ?? displayProject.sections[0] }
    var loopLengthOptions:[Int]{Array(Set([1,2,4,8,16,32,64]+[loopBars])).sorted()}
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
        runtimeTrace("bootstrap.begin")
        defer{runtimeTrace("bootstrap.return")}
        await store.purgeTrash()
        if let bootstrapTask {await bootstrapTask.value;return}
        let task=Task { @MainActor in
            do {
                entries=try await store.listSummaries()
                let remembered=UserDefaults.standard.string(forKey:lastProjectKey).flatMap(UUID.init(uuidString:))
                let readable=entries.filter{$0.summary != nil}
                let candidates=readable.filter{$0.id==remembered}+readable.filter{$0.id != remembered}
                for entry in candidates {
                    do{
                        let previous=try await store.load(entry.id)
                        guard previous.id==entry.id else{throw MusicError.invalidProject}
                        audio.samples = try await store.loadSamples(for: previous)
                        project=previous;savedRevision=previous.revision
                        // I68: unsaved edits from a session that stopped before its save.
                        if let data=try? Data(contentsOf:journalURL),let found=EditJournal.decode(data),found.recovery(over:previous) != nil{recoverable=found}
                        break
                    }catch{markLibraryFailure(entry.id,error:error.localizedDescription)}
                }
                if entries.isEmpty {
                    savedRevision=try await store.save(project);await refreshLibraryEntry(project.id,validated:true)
                }
            } catch {message=error.localizedDescription;runtimeTrace("bootstrap.failure \(error.localizedDescription)")}
            // UI-test fixture: as if the last session stopped with the tempo changed but not saved.
            if Luz.uiTesting,ProcessInfo.processInfo.arguments.contains("--recovery-fixture"){
                var newer=project;newer.bpm=min(240,project.bpm+7);newer.revision=project.revision+1
                var found=EditJournal(saved:project,savedRevision:project.revision);found.record(newer,edit:"",savedRevision:project.revision)
                recoverable=found
            }
            // Loading and saving a document do not depend on an audio route.
            // A failed device engine must not turn a valid stored project into
            // an unsaved seed or lose the user's last-opened selection.
            selectedSection=project.sections[0].id
            restoreGeneratedLoop()
            if savedRevision>=0{UserDefaults.standard.set(project.id.uuidString,forKey:lastProjectKey)}
            runtimeTrace("bootstrap.prepare.before")
            do{try audio.prepare();sync()}
            catch{audio.error=error.localizedDescription;runtimeTrace("bootstrap.audio.failure \(error.localizedDescription)")}
            runtimeTrace("bootstrap.prepare.after")
            launchMilliseconds=LaunchClock.elapsedMilliseconds()
            ready=true
            runtimeTrace("bootstrap.ready")
        }
        bootstrapTask=task;await task.value
    }
    func ensureAudio() -> Bool {
        runtimeTrace("ensureAudio.before");defer{runtimeTrace("ensureAudio.after")}
        guard !backgrounded || remoteStarting else{return false}; if audio.isPrepared {return true}; do {try audio.prepare(); sync(); return true} catch {audio.error = error.localizedDescription; return false}
    }
    func syncMIDI(){
        guard !backgrounded || audio.playing || remoteStarting else{return}
        // Device consent and selection take effect at the touch, even while a
        // structural edit waits for its bar. Only UUID routing follows the
        // adopted layout; the hub resolves its current index at the boundary.
        let tracks=audio.activeMIDIRouting?.tracks ?? project.tracks
        var settings=project.midi ?? MIDISettings()
        if settings.trackID==nil{settings.trackID=MIDISettings.automaticTrack(tracks,focused:noteTrackID)}
        midi.configure(settings,tracks:tracks)
        audio.midiClock(settings.outputID != nil && settings.clockOut == true)
    }
    /// Share the real QA endpoint setup between launch and an explicit reconnect.
    /// A failed launch never creates an enabled project or a pretend mapping.
    func prepareMIDIFixture(){
        guard let source=midi.createFixture(),let destination=midi.fixtureOutputID else{return}
        var value=project.midi ?? MIDISettings()
        value.enabled=true;value.inputIDs=[source];value.outputID=destination;value.trackID=project.tracks[0].id
        if project.midi != value{let configured=value;edit{$0.midi=configured}}
        syncMIDI()
    }
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
    @ObservationIgnored private var takeSavedOnLeave=false
    func sceneChanged(_ phase:ScenePhase){
        runtimeTrace("scene.\(phase).before");defer{runtimeTrace("scene.\(phase).after")}
        if phase == .active{backgrounded=false;if ready{_ = ensureAudio();syncMIDI()};if takeSavedOnLeave{takeSavedOnLeave=false;showToast("Your take was kept when the app went to the background")};return}
        // U66: leaving the app mid-recording keeps the take as it is.
        if recording{takeSavedOnLeave=true}
        finishTake();Task{await save()}
        if phase == .background{backgrounded=true;stopMicrophone?();microphoneOwner=nil;stopMicrophone=nil;if harmonyPreview{endHarmonyPreview()};suspendIdleAudio();backupInBackground()}
    }
    // MARK: I77 · automatic backup to a Files folder
    var backupFolderName:String?=UserDefaults.standard.string(forKey:"backup.folderName")
    var lastBackup:Date?=UserDefaults.standard.object(forKey:"backup.last") as? Date
    @ObservationIgnored private var backingUp=false
    func chooseBackupFolder(_ url:URL) {
        let access=url.startAccessingSecurityScopedResource();defer{if access{url.stopAccessingSecurityScopedResource()}}
        do {
            let bookmark=try url.bookmarkData(options:[],includingResourceValuesForKeys:nil,relativeTo:nil)
            UserDefaults.standard.set(bookmark,forKey:"backup.folder");UserDefaults.standard.set(url.lastPathComponent,forKey:"backup.folderName")
            backupFolderName=url.lastPathComponent
            Task{await backupNow(force:true)}
        }catch{message=error.localizedDescription}
    }
    func stopBackup() {
        for key in ["backup.folder","backup.folderName","backup.last"]{UserDefaults.standard.removeObject(forKey:key)}
        backupFolderName=nil;lastBackup=nil
    }
    private final class BackgroundTaskBox:@unchecked Sendable{var id=UIBackgroundTaskIdentifier.invalid}
    private func backupInBackground() {
        guard UserDefaults.standard.data(forKey:"backup.folder") != nil,BackupPlanner.due(last:lastBackup,now:Date()) else{return}
        let box=BackgroundTaskBox()
        box.id=UIApplication.shared.beginBackgroundTask(withName:"La Grilla backup"){UIApplication.shared.endBackgroundTask(box.id);box.id = .invalid}
        Task{@MainActor in
            await backupNow(force:false)
            if box.id != .invalid{UIApplication.shared.endBackgroundTask(box.id);box.id = .invalid}
        }
    }
    /// `force` backs up every project now; otherwise only projects changed since the last backup, once a day.
    func backupNow(force:Bool) async {
        guard !backingUp,let bookmark=UserDefaults.standard.data(forKey:"backup.folder") else{return}
        guard force || BackupPlanner.due(last:lastBackup,now:Date()) else{return}
        backingUp=true;defer{backingUp=false}
        var stale=false
        guard let folder=try? URL(resolvingBookmarkData:bookmark,options:[],relativeTo:nil,bookmarkDataIsStale:&stale) else{
            if force{message=NSLocalizedString("The backup folder is no longer available. Choose it again in Settings.",comment:"Backup")};return
        }
        await save();await refreshLibrary()
        let ids=BackupPlanner.changed(entries.compactMap(\.summary),since:force ? nil:lastBackup)
        let now=Date()
        guard !ids.isEmpty else{lastBackup=now;UserDefaults.standard.set(now,forKey:"backup.last");return}
        let temporary=FileManager.default.temporaryDirectory.appendingPathComponent("backup-"+UUID().uuidString).appendingPathExtension("zip")
        defer{try? FileManager.default.removeItem(at:temporary)}
        do {
            try await store.portableBatch(ids,to:temporary)
            let access=folder.startAccessingSecurityScopedResource();defer{if access{folder.stopAccessingSecurityScopedResource()}}
            let target=folder.appendingPathComponent(BackupPlanner.fileName(now))
            var coordination:NSError?,failure:Error?
            NSFileCoordinator().coordinate(writingItemAt:target,options:.forReplacing,error:&coordination){url in
                do{if FileManager.default.fileExists(atPath:url.path){try FileManager.default.removeItem(at:url)};try FileManager.default.copyItem(at:temporary,to:url)}catch{failure=error}
            }
            if let error=coordination ?? failure{throw error}
            if stale,let fresh=try? folder.bookmarkData(options:[],includingResourceValuesForKeys:nil,relativeTo:nil){UserDefaults.standard.set(fresh,forKey:"backup.folder")}
            lastBackup=now;UserDefaults.standard.set(now,forKey:"backup.last")
            if force{showToast(String(format:NSLocalizedString("Backed up %d projects",comment:"Backup"),ids.count))}
        }catch{if force{message=error.localizedDescription}}
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
        restorePreviewTransport()
        if let drumDraft{drumPlayback=try? drumDraft.candidate(for:project)}else{drumPlayback=nil}
        audio.submit(drumPlayback ?? project,loop:loop,range:loopRange);audio.metronome(metronome);syncMIDI()
        // 54: an undo can bring back a clip whose take was let go; load it again.
        if project.hasAudioTracks,audioTakesMissing,!loadingTakes{Task{await loadAudioTakes()}}
        if project.masterPlugins != nil || !audio.masterSignature.isEmpty{syncMasterPlugins()}
    }
    /// Complete value mutations before publishing either observed property.
    /// A project willSet can synchronously render a view that reads history;
    /// holding an inout borrow of Session.history across that callback aborts.
    private func withHistoryTransaction<T>(_ change:(inout History,inout Project)throws->T) rethrows->T {
        var nextHistory=history
        var nextProject=project
        let result=try change(&nextHistory,&nextProject)
        history=nextHistory
        project=nextProject
        return result
    }
    func edit(_ change: (inout Project) throws -> Void) {
        mixerGesture=false
        guard !performance.contextActive else{message="Return to editing before changing the source project.";return}
        guard !recording && !armed else {message = "Finish the drum take before editing the project.";return}
        // I39: markers stay with their place in a section when the form changes.
        do {try withHistoryTransaction{h,p in try h.apply(&p){q in let before=q;try change(&q);MarkerEditing.remap(from:before,to:&q);AutomationEditing.remap(from:before,to:&q)}}; sync(); scheduleSave()} catch {message = error.localizedDescription}
    }
    var mixerGesture = false
    func mixerEdit(_ change: (inout Project) throws -> Void) {
        if performance.contextActive{do{try performance.editMix(change)}catch{message=error.localizedDescription};return}
        do { try withHistoryTransaction{h,p in try h.applyMix(&p, coalescing: mixerGesture, change)}; mixerGesture = true; sync(); scheduleSave() }
        catch { message = error.localizedDescription }
    }
    func coalescedMusicEdit(_ change:(inout Project)throws->Void){
        guard !performance.contextActive else{message="Return to editing before changing the source project.";return}
        guard !recording && !armed else{message="Finish the drum take before editing the project.";return}
        do{try withHistoryTransaction{h,p in try h.apply(&p,coalescing:mixerGesture,change)};mixerGesture=true;sync();scheduleSave()}catch{message=error.localizedDescription}
    }
    func mixerImmediate(_ change: (inout Project) throws -> Void) {
        mixerGesture=false; mixerEdit(change); mixerGesture=false
    }
    /// I43: open the Assistant listening, scoped to the section at `tick`.
    @ObservationIgnored var assistantListens=false
    func editByVoice(at tick:Int) {
        if let section=project.sections.first(where:{$0.start<=tick && tick<$0.start+$0.length}){select(section)}
        assistantListens=true;sheet = .assistant
    }
    /// I90: short confirmation shown over the studio.
    var toast:String?
    /// U11 · The demo tour, while it runs.
    var tour:DemoTour?
    /// Set by the tour's "Show me" on the chord step; Grid opens a chord when it is showing.
    var pendingTourChord=false
    /// U29 · Keys held down by a touch-and-hold preview (chord, note); released by `endHold()`.
    @ObservationIgnored private var heldKeys:[(pitch:Int,track:Track,index:Int)]=[]
    /// U29 · How many hold previews started (shown to UI tests).
    private(set) var holdPreviews=0
    private(set) var holdSounding=false
    /// U29 · Sounds `pitches` on a track for as long as a finger holds; nothing in the song changes.
    func previewHold(pitches:[Int],trackID:UUID){
        endHold()
        guard !recording,!armed,let index=project.tracks.firstIndex(where:{$0.id==trackID}),ensureAudio()else{return}
        let track=project.tracks[index]
        for pitch in Set(pitches.filter{(0...127).contains($0)}).sorted() where midi.playKey(pitch,down:true,track:track,index:index){
            heldKeys.append((pitch,track,index))
        }
        if !heldKeys.isEmpty{holdPreviews+=1;holdSounding=true}
    }
    /// U29 · A chord held on its harmony track (the bass follows in playback, not in the preview).
    func previewHold(chord:Chord){
        guard let harmony=project.tracks.first(where:{$0.role == .harmony})else{return}
        previewHold(pitches:chord.notes,trackID:harmony.id)
    }
    /// U33 · A held project card plays about ten seconds of that song's chorus (loaded from disk).
    @ObservationIgnored private var storedPreview:Task<Void,Never>?
    func previewStored(_ id:UUID)->Bool{
        storedPreview?.cancel()
        storedPreview=Task{@MainActor in
            guard let stored=try? await store.load(id),!Task.isCancelled else{return}
            let samples=try? await store.loadSamples(for:stored)
            guard !Task.isCancelled else{return}
            _ = holdPreview(stored,range:ProjectPreview.range(stored),samples:samples)
        }
        return true
    }
    func endStoredPreview(){
        storedPreview?.cancel();storedPreview=nil
        endHarmonyPreview()
    }
    func endHold(){
        for key in heldKeys{_ = midi.playKey(key.pitch,down:false,track:key.track,index:key.index)}
        heldKeys=[];holdSounding=false
    }
    /// U64 · The note selected in the piano roll (kept across rotation and re-layout).
    var selectedNoteID:UUID?
    /// U20 · Milliseconds from the app starting to the studio being ready.
    private(set) var launchMilliseconds=0
    func tourEvent(_ event:TourEvent){
        guard var current=tour,!current.finished else{return}
        if current.observe(event){Luz.Haptics.success()}
        tour=current
    }
    /// U11 · Opens the demo song and starts the five-step tour on it.
    func startTour()async{
        sheet=nil
        guard await openExample() else{return}
        tab=0
        tour=DemoTour()
    }
    func showToast(_ text:String){toast=text;Task{@MainActor in try? await Task.sleep(for:.seconds(1.2));if toast==text{toast=nil}}}
    /// Undo or redo from a gesture; true when something changed.
    func gestureUndo(_ forward:Bool)->Bool {
        guard !recording,!armed,!performance.contextActive,forward ? history.canRedo:history.canUndo else{return false}
        if forward{redo()}else{undo()}
        showToast(forward ? "Redo":"Undo");return true
    }
    func undo() {if performance.contextActive{Task{await leavePerformance();undo()};return};guard !recording && !armed else {return}; mixerGesture=false;withHistoryTransaction{h,p in h.undo(&p)};restoreGeneratedLoop();sync();scheduleSave()}
    func redo() {if performance.contextActive{Task{await leavePerformance();redo()};return};guard !recording && !armed else {return}; mixerGesture=false;withHistoryTransaction{h,p in h.redo(&p)};restoreGeneratedLoop();sync();scheduleSave()}
    /// U6 · Jump several states back (positive) or forward (negative) in one action.
    func jumpHistory(_ steps:Int) {
        guard steps != 0 else{return}
        if performance.contextActive{Task{await leavePerformance();jumpHistory(steps)};return}
        guard !recording && !armed else{message="Finish the drum take before editing the project.";return}
        endHarmonyPreview();mixerGesture=false
        let moved=withHistoryTransaction{h,p in steps>0 ? h.undo(&p,steps:steps):h.redo(&p,steps:-steps)}
        guard moved else{return}
        restoreGeneratedLoop();sync();scheduleSave();showToast("Restored")
    }
    /// U6 · U7 · Hear another state of this song (a history point or a saved version)
    /// without changing the project. Stop with `endHarmonyPreview()`.
    func previewSnapshot(_ snapshot:Project) {
        guard !performance.contextActive else{message="Return to editing before changing the source project.";return}
        finishTake();guard ensureAudio()else{return}
        var candidate=snapshot;candidate.id=project.id;candidate.revision=project.revision
        do{try candidate.validate()}catch{message=error.localizedDescription;return}
        guard candidate.length>0 else{return}
        auditionDraft(candidate,range:0..<candidate.length,loop:true)
    }
    /// U7 · Replace the song with a saved version in one Undo step. The current state is
    /// saved as a version first, so restoring never loses work.
    /// U26: back to how the song was when it was opened; the current state is kept as a version first.
    func returnToOpened() async {
        guard let snapshot=openedSnapshot,snapshot != project else{return}
        await restoreVersion(snapshot,keepingCurrentAs:NSLocalizedString("Before going back",comment:"Version name"))
    }
    func restoreVersion(_ version:Project,keepingCurrentAs name:String) async {
        endHarmonyPreview()
        do{_ = try await store.saveVersion(project,name:name)}catch{message=error.localizedDescription;return}
        let id=project.id
        edit{p in var restored=version;restored.id=id;restored.name=p.name;p=restored}
        showToast("Restored")
    }
    /// Stage 3 tools (variations, comping) work on this pattern.
    var toolPatternID:UUID?
    /// U51: the ready beat the beat machine opens with (from "Start with a beat").
    var beatMachinePreset:String?
    /// I28 · Copies the melody track that plays `patternID` into a new track with every
    /// note moved a third or sixth in the key, in one Undo.
    func addSecondVoice(patternID:UUID,interval:Harmonizer.Interval){
        guard let source=project.tracks.first(where:{$0.role == .melody && $0.clips.contains{$0.patternID==patternID}})else{return}
        let key=project.keyRoot,minor=project.minor
        edit{p in
            try p.duplicateTrack(source.id)
            guard let index=p.tracks.indices.last else{return}
            p.tracks[index].name=String((source.displayName+" · "+NSLocalizedString("2nd voice",comment:"Second voice")).prefix(40))
            for clip in p.tracks[index].clips{
                if let i=p.patterns.firstIndex(where:{$0.id==clip.patternID}){p.patterns[i].notes=Harmonizer.secondVoice(p.patterns[i].notes ?? [],keyRoot:key,minor:minor,interval:interval)}
            }
        }
    }
    /// U44 · Practice: hear the selected section slower, looping; the song does not change.
    var practicing=false
    func togglePractice(rate:Double=0.75){
        if practicing{practicing=false;endHarmonyPreview();return}
        previewAssistant(Practice.slowed(project,rate:rate),wholeSong:false,sectionID:section.id)
        practicing=harmonyPreview
        if practicing{showToast(String(format:NSLocalizedString("Practice at %lld%%",comment:"Practice"),Int(rate*100)))}
    }
    /// U22 · Focus: loop exactly the selected section (again to leave).
    var focused:Bool{loop && loopRange == section.start..<section.start+section.length}
    func toggleFocus(){
        if focused{setLoop(enabled:false);showToast("Focus off")}
        else{select(section);setLoop(bars:max(1,section.length/barTicks),enabled:true);showToast("Focus on the section")}
    }
    /// U3 · A request left by Siri, Shortcuts or Spotlight.
    func handleLaunch(_ request:LaunchRequest) async {
        switch request.kind {
        case .newBeat:
            var parts:[String]=[]
            if let bpm=request.bpm{parts.append("\(bpm) BPM")}
            if let root=request.keyRoot{parts.append(Chord.roots[(root%12+12)%12]+(request.minor == true ? " minor":" major"))}
            openTrackBuilder(idea:parts.joined(separator:", "))
        case .openProject:
            if let id=request.projectID{sheet=nil;await openStored(id)}
        case .recordIdea: presentEditor(.voice)
        case .export: finishTake();exportTake=nil;sheet = .export
        }
    }
    /// U4 · U13 · Runs a command from the search field or the quick bar. Commands with a
    /// missing value open the place where it is set.
    func run(_ id:CommandID,_ argument:CommandArgument?=nil) {
        // U65: Repeat runs the last action with its value again (⌘Y).
        if id == .repeatLast { if let last=CommandMemory.lastRun, last.command != .repeatLast { run(last.command,last.argument) }; return }
        CommandMemory.remember(id)
        CommandMemory.lastRun=CommandMatch(command:id,argument:argument,score:1)
        switch id {
        case .play: togglePlay()
        case .record: tab=1;record()
        case .undo: undo()
        case .redo: redo()
        case .loop: setLoop(enabled:!loop)
        case .tempo:
            if case .bpm(let value)? = argument { edit{$0.bpm=Double(value)};showToast(String(format:NSLocalizedString("Tempo %lld BPM",comment:"Command"),value)) }
            else { presentEditor(.settings) }
        case .key:
            if case .key(let root,let minor)? = argument { edit{$0.keyRoot=root;$0.minor=minor};showToast(project.keyName) }
            else { presentEditor(.settings) }
        case .transpose:
            if case .semitones(let amount)? = argument { edit{$0=try MusicalEditing.transpose($0,semitones:amount).candidate} }
            else { presentEditor(.settings) }
        case .addSection:
            var name="Chorus"
            if case .name(let value)? = argument { name=value }
            let bars=max(1,section.length/barTicks)
            edit{try SectionEditing.append(name:NSLocalizedString(name,comment:"Section name"),bars:bars,to:&$0)}
            if let added=project.sections.last{select(added)}
        case .duplicateSection:
            let current=section
            edit{try $0.duplicateSection(current.id,name:String((current.name+" 2").prefix(120)))}
        case .addMelody: edit{try $0.addMelody()}
        case .deleteLastTake:
            let current=section
            guard let drums=project.tracks.first(where:{$0.role == .drums}),
                  let clip=drums.clips.first(where:{$0.start<current.start+current.length && $0.start+$0.length>current.start}),
                  let pattern=project.patterns.first(where:{$0.id==clip.patternID}),
                  let latest=DrumTakes.latest(in:pattern) else{message="There is no recorded take in this section.";return}
            edit{try ProjectTrash.deleteTake(latest.id,pattern:pattern.id,in:&$0)}
        case .grid: sheet=nil;tab=0
        case .jam: sheet=nil;tab=1
        case .mixer: sheet=nil;tab=2
        case .notes: presentEditor(.notes)
        case .voice: presentEditor(.voice)
        case .assistant: presentEditor(.assistant)
        case .harmony: presentEditor(.harmony)
        case .palettes: presentEditor(.palettes)
        case .sections: presentEditor(.sections)
        case .bass: presentEditor(.bass)
        case .perform: sheet = .perform
        case .settings: presentEditor(.settings)
        case .projects: sheet = .projects
        case .newProject: sheet = .newProject
        case .export: finishTake();exportTake=nil;sheet = .export
        case .history: presentEditor(.history)
        case .versions: presentEditor(.versions)
        case .trash: presentEditor(.trash)
        case .midiDevices: presentEditor(.midiDevices)
        case .chordImport: presentEditor(.chordImport)
        case .lyrics: presentEditor(.lyrics)
        case .master: presentEditor(.master)
        case .focusSection: toggleFocus()
        case .practice: togglePractice()
        case .mood: presentEditor(.mood)
        case .repeatLast: break
        case .coNotes: presentEditor(.coNotes)
        case .vj: sheet = .vj
        case .help: presentEditor(.help)
        case .grooves: presentEditor(.grooves)
        case .beatMachine: presentEditor(.beatMachine)
        case .tuner: presentEditor(.tuner)
        case .louder, .quieter, .brighter, .warmer, .moreSpace:
            // I61: mastering in words, one Undo each.
            let tweak: MasterTweak = switch id { case .louder: .louder; case .quieter: .quieter; case .brighter: .brighter; case .warmer: .warmer; default: .moreSpace }
            edit { tweak.apply(to: &$0) }
            showToast(tweak.title)
        case .markers: presentEditor(.markers)
        case .dynamics: presentEditor(.dynamics)
        case .practicePlayer: presentEditor(.practicePlayer)
        case .continueIdea:
            let current=section
            edit{try ContinueIdea.extend(current.id,name:NSLocalizedString("Continuation",comment:"Section name"),seed:UInt64(project.revision) &+ 1,in:&$0)}
            if let index=project.sections.firstIndex(where:{$0.id==current.id}),index+1<project.sections.count{select(project.sections[index+1])}
        case .doctor: presentEditor(.doctor)
        case .earTraining: presentEditor(.earTraining)
        case .course: presentEditor(.course)
        case .audioTracks: presentEditor(.audioTracks)
        case .plugins: presentEditor(.plugins)
        case .arpeggiator: openArpeggiator()
        }
    }
    /// U8 · Bring back a deleted track, take or clip in one Undo step.
    func restoreDeleted(_ id:UUID){edit{try ProjectTrash.restore(id,in:&$0)};if message==nil{showToast("Restored")}}
    func scheduleSave() {saveTask?.cancel();saveTask = Task {try? await Task.sleep(for:.milliseconds(700));guard !Task.isCancelled else{return};await save()};journalEdit()}
    /// I68 · Edits since the last save, kept on disk until that save lands (written off the main thread).
    @ObservationIgnored private var journal:EditJournal?
    @ObservationIgnored private var journalTask:Task<Void,Never>?
    /// I68 · Found at launch: unsaved edits from a session that stopped before saving.
    var recoverable:EditJournal?
    private var journalURL:URL{store.root.appendingPathComponent("journal.json")}
    private func journalEdit(){
        guard ready,!performance.contextActive,project.revision>savedRevision else{return}
        var next=journal ?? EditJournal(saved:project,savedRevision:savedRevision)
        next.record(project,edit:"",savedRevision:savedRevision)
        journal=next
        let url=journalURL
        journalTask?.cancel()
        journalTask=Task.detached(priority:.utility){
            try? await Task.sleep(for:.milliseconds(120))
            guard !Task.isCancelled,let data=try? next.encoded() else{return}
            try? data.write(to:url,options:.atomic)
        }
    }
    private func clearJournal(){
        journal=nil;journalTask?.cancel();journalTask=nil
        try? FileManager.default.removeItem(at:journalURL)
    }
    /// I68 · Puts the unsaved edits back as one Undo step, then saves.
    func restoreRecoverable(){
        guard let journal=recoverable,let recovered=journal.recovery(over:project)else{recoverable=nil;return}
        recoverable=nil
        edit{p in var next=recovered;next.revision=p.revision;p=next}
    }
    func discardRecoverable(){recoverable=nil;clearJournal()}
    func save() async {
        // Scene/background notifications may arrive while the catalogue is
        // suspended. Never persist the temporary seed before bootstrap loads
        // the user's document; a later ready save uses the restored project.
        guard ready else{return}
        guard !hasKnownLibraryFailure(project.id)else{saveError=ProjectChangeError.needsWorkingCopy.localizedDescription;return}
        saveGeneration += 1; let generation=saveGeneration
        saving=true; let snapshot=project
        do {
            let writtenRevision=try await store.save(snapshot)
            if project.id==snapshot.id {savedRevision=max(savedRevision,writtenRevision);saveError=nil;savedAt=Date();if journal?.isSaved(at:snapshot.revision) ?? true,recoverable==nil{clearJournal()}}
            await refreshLibraryEntry(snapshot.id,validated:true)
        } catch {if project.id==snapshot.id {saveError=error.localizedDescription}}
        if generation==saveGeneration {saving=false}
    }
    func refreshLibrary()async {
        do{
            let summaries=try await store.listSummaries()
            entries=summaries.map{keepingKnownLibraryFailure($0)}
            sortLibrary()
        }catch{message=error.localizedDescription}
    }
    func refreshLibraryEntry(_ id:UUID,validated:Bool=false)async {
        if validated{libraryLoadFailures.removeValue(forKey:id)}
        let observed=await store.summary(id)
        let entry=keepingKnownLibraryFailure(observed)
        if let index=entries.firstIndex(where:{$0.id==id}){entries[index]=entry}else{entries.append(entry)}
        sortLibrary()
    }
    private func sortLibrary(){
        entries.sort{let a=$0.summary?.modified ?? .distantPast,b=$1.summary?.modified ?? .distantPast;return a==b ? $0.id.uuidString<$1.id.uuidString:a>b}
    }
    private func keepingKnownLibraryFailure(_ entry:ProjectStore.SummaryEntry)->ProjectStore.SummaryEntry {
        guard let failure=libraryLoadFailures[entry.id],let summary=entry.summary else{return entry}
        guard summary.revision==failure.revision,summary.modified==failure.modified else{libraryLoadFailures.removeValue(forKey:entry.id);return entry}
        return ProjectStore.SummaryEntry(id:entry.id,summary:nil,error:failure.error,hasBackup:entry.hasBackup)
    }
    private func markLibraryFailure(_ id:UUID,error:String){
        guard let index=entries.firstIndex(where:{$0.id==id})else{return}
        if let summary=entries[index].summary{libraryLoadFailures[id]=LibraryLoadFailure(revision:summary.revision,modified:summary.modified,error:error)}
        entries[index]=ProjectStore.SummaryEntry(id:id,summary:nil,error:error,hasBackup:entries[index].hasBackup)
    }
    private func hasKnownLibraryFailure(_ id:UUID)->Bool {
        libraryLoadFailures[id] != nil || entries.first(where:{$0.id==id})?.error != nil
    }
    // MARK: I37 · Automation recording
    /// While on, level and pan moves in the mixer during playback are written into lanes.
    var automationRecording = false { didSet { if !automationRecording { commitAutomation() } } }
    /// The track the automation editor shows.
    var automationTrackID: UUID?
    @ObservationIgnored private var automationCapture: [UUID: [AutomationLane.Parameter: [(tick: Int, value: Double)]]] = [:]
    /// Records one control value at the playhead; the first value of a pass silences the old lane.
    func captureAutomation(track index: Int, _ parameter: AutomationLane.Parameter, value: Double) {
        guard automationRecording, audio.playing, project.tracks.indices.contains(index), index < masterBus else { return }
        let id = project.tracks[index].id
        if automationCapture[id]?[parameter] == nil { audio.suspendAutomation(track: index, parameter: parameter) }
        automationCapture[id, default: [:]][parameter, default: []].append((tick: Int(audio.tick), value: value))
    }
    /// Writes every captured pass as one edit.
    func commitAutomation() {
        guard !automationCapture.isEmpty else { return }
        let capture = automationCapture
        automationCapture = [:]
        edit { p in
            for (id, parameters) in capture {
                guard let i = p.tracks.firstIndex(where: { $0.id == id }) else { continue }
                var lanes = p.tracks[i].automation ?? []
                for (parameter, samples) in parameters {
                    guard let lane = AutomationEditing.record(samples, parameter: parameter, into: lanes.first { $0.parameter == parameter }) else { continue }
                    lanes.removeAll { $0.parameter == parameter }
                    lanes.append(lane)
                }
                p.tracks[i].automation = lanes.isEmpty ? nil : lanes.sorted { $0.parameter.rawValue < $1.parameter.rawValue }
            }
        }
    }
    func togglePlay() {
        runtimeTrace("togglePlay.before");defer{runtimeTrace("togglePlay.after")}
        if performance.contextActive{if performance.playing || performance.starting{Task{await performance.stop();pollPerformance()}}else if performance.replaying,let take=performance.replayTake{replayPerformance(take)}else{startPerformance(record:false)};return}
        if audio.playing {finishTake();audio.stop();commitAutomation();Luz.Haptics.transportStop()}else if ensureAudio(){if audio.tick>=Double(loopRange.upperBound){audio.seek(loopRange.lowerBound)};audio.play();Luz.Haptics.transportStart()}
    }
    func rewind() {if performance.contextActive{Task{await leavePerformance();rewind()};return};finishTake();audio.stop();audio.seek(loopRange.lowerBound)}
    /// U16 · Set when recording would start on a late route; the studio asks first.
    var routeWarningPending=false
    @ObservationIgnored private var routeWarningAccepted=false
    var routeKind:AudioRouteKind{AudioRouteAdvice.kind(portTypes:audio.outputPortTypes)}
    var routeLatencyDisplay:(milliseconds:Int,measured:Bool){AudioRouteAdvice.latency(routeKind,measured:routeLatency[currentRouteKey])}
    func recordAnyway(){routeWarningAccepted=true;routeWarningPending=false;record()}
    func record() {
        guard !performance.contextActive else{message="Return to editing before recording a drum loop.";return}
        if recording || armed {finishTake();return}
        if !routeWarningAccepted,!ProcessInfo.processInfo.arguments.contains("--uitesting") || ProcessInfo.processInfo.arguments.contains("--route-bluetooth"),
           AudioRouteAdvice.warnsBeforeRecording(ProcessInfo.processInfo.arguments.contains("--route-bluetooth") ? .bluetooth:routeKind,measured:routeLatency[currentRouteKey]) {
            routeWarningPending=true;return
        }
        guard ensureAudio(),let track=project.tracks.first(where:{$0.role == .drums}),let clip=focusedDrumClip ?? track.clips.first(where:{$0.start<=section.start && $0.start+$0.length>section.start})else{return}
        do{drumDraft=try DrumRecordingDraft(project:project,clipID:clip.id)}catch{message=error.localizedDescription;return}
        audio.refreshClock()
        rawHits=[];pendingPadInputs=[];takePattern=drumDraft?.patternID;takeStart=clip.start;takeLength=clip.length
        do{if let drumDraft{drumPass=try DrumRecordingPass(draft:drumDraft,replacing:overdub ? nil:loopRange)}}
        catch{drumDraft=nil;drumPass=nil;message=error.localizedDescription;return}
        let barFrames=audio.sampleRate*240/project.bpm
        if audio.playing {
            let remainder=Double(barTicks)-audio.tick.truncatingRemainder(dividingBy:Double(barTicks))
            armClock=audio.clock+UInt64((remainder/960*60/project.bpm*audio.sampleRate).rounded())
        }else{
            audio.seek(loopRange.lowerBound);audio.play(countInBPM:countIn ? project.bpm : nil)
            armClock=audio.clock+UInt64(countIn ? barFrames : 0)
        }
        passClock=armClock;replaceNextPass = !overdub;armed=true;sync();Luz.Haptics.transportStart()
    }
    func pollRecording() {
        if let end = draftEndTick, harmonyPreview, !audio.playing, Int(audio.tick) == end {
            if draftTailStart == nil { draftTailStart = audio.clock }
            let start = draftTailStart ?? audio.clock
            let elapsed = Double(audio.clock >= start ? audio.clock - start : 0) / audio.sampleRate
            // Let the gong and delay return decay after the musical endpoint.
            // A tap on Stop or another section still ends the audition immediately.
            if elapsed >= 5 || (elapsed >= 2 && audio.meters[masterBus] < 0.0005) {
                if runtimeTraceEnabled { runtimeTrace("draft.preview-finished end=\(end)") }
                endHarmonyPreview()
            }
        }
        flushRepeatHits()
        drainPadRecordingInputs()
        syncMIDI();midi.poll(replaying:performance.replaying);pollPerformance()
        updateNowPlaying()
        // A finite arrangement can stop itself without a transport tap. Keep
        // the final partial drum pass and release the recording/editing lock.
        if (recording || armed),!audio.playing{finishTake();if backgrounded{suspendIdleAudio()};return}
        if backgrounded,!audio.playing{suspendIdleAudio();return}
        if armed && audio.clock>=armClock { armed=false; recording=true }
        guard recording else { return }
        let frames = UInt64(Double(loopRange.count)/960*60/project.bpm*audio.sampleRate)
        if frames > 0 && audio.clock >= passClock + frames {
            commitPass(); passClock += frames
        }
    }
    /// 55 · How hits recorded now sit in time: as played, or pulled to the chosen grid and strength.
    var recordingTiming:TakeTiming{TakeTiming(quantize,strength:quantizeStrength,swing:swing)}
    /// I09: put the hits played without Record during the last `bars` bars into
    /// the current drum clip, quantized, as one undoable edit.
    @discardableResult func keepRecentHits(bars:Int)->Int {
        guard !recording,!armed,!performance.contextActive,let track=project.tracks.first(where:{$0.role == .drums}),
              let clip=focusedDrumClip ?? track.clips.first(where:{$0.start<=section.start && $0.start+$0.length>section.start}) else{return 0}
        audio.refreshClock()
        let framesPerBar=UInt64((Double(barTicks)/Double(ppq)*60/project.bpm*audio.sampleRate).rounded())
        let window=UInt64(max(1,bars))*framesPerBar
        let since=audio.clock>window ? audio.clock-window:0
        let events=retroHits.events(since:since,clipStart:clip.start,clipLength:clip.length,quantizer:recordingTiming.quantizer)
        guard !events.isEmpty else{message=NSLocalizedString("Play the pads while the loop runs, then keep what you played.",comment:"Keep recent hits");return 0}
        do{
            var draft=try DrumRecordingDraft(project:project,clipID:clip.id)
            try draft.commitPass(events,timing:recordingTiming)
            let candidate=try draft.candidate(for:project)
            edit{$0=candidate}
            retroHits=PadRetroBuffer(capacity:1024)
            return events.count
        }catch{message=error.localizedDescription;return 0}
    }
    /// I3: note repeat rate while a pad is held (nil = off), and the running hold.
    var noteRepeat:NoteRepeat.Rate?=UserDefaults.standard.object(forKey:"jam.noteRepeat").flatMap{($0 as? Int).flatMap(NoteRepeat.Rate.init(rawValue:))}{didSet{UserDefaults.standard.set(noteRepeat?.rawValue,forKey:"jam.noteRepeat");if noteRepeat==nil{endRepeat()}}}
    @ObservationIgnored private var lastPadVelocity=100
    @ObservationIgnored private var repeatHold:(pad:Int,tick:Int,clock:UInt64,velocity:Int,step:Int,emitted:Int)?
    /// Called with the set of held pads; the last pad pressed repeats.
    func padsHeld(_ held:Set<Int>) {
        if let hold=repeatHold,!held.contains(hold.pad){endRepeat()}
        guard let rate=noteRepeat,repeatHold==nil,let pad=held.sorted().last,!performance.replaying,audio.isPrepared else{return}
        audio.refreshClock()
        let velocity=lastPadVelocity
        guard audio.padRepeat(pad,step:rate.rawValue,velocity:velocity) else{return}
        repeatHold=(pad,Int(audio.tick),audio.clock,velocity,rate.rawValue,Int(audio.tick))
    }
    private func endRepeat() {
        guard repeatHold != nil else{return}
        audio.padRepeat(nil);audio.refreshClock()
        flushRepeatHits()
        repeatHold=nil
    }
    /// The kernel fires on every grid tick after the press; the same ticks go to
    /// the recording (or the retro buffer) as they pass, so passes stay in order.
    private func flushRepeatHits() {
        guard var hold=repeatHold,audio.playing,audio.clock>hold.clock else{return}
        let framesPerTick=audio.sampleRate*60/(project.bpm*Double(ppq))
        let now=hold.tick+Int(Double(audio.clock-hold.clock)/framesPerTick)
        guard now>hold.emitted else{return}
        let ticks=NoteRepeat.hits(from:hold.emitted+1,to:now+1,rate:NoteRepeat.Rate(rawValue:hold.step) ?? .sixteenth).prefix(512)
        let span=max(1,loopRange.count)
        for unwrapped in ticks {
            var tick=unwrapped
            if loop,tick>=loopRange.upperBound{tick=loopRange.lowerBound+(tick-loopRange.lowerBound)%span}
            let clock=hold.clock+UInt64((Double(unwrapped-hold.tick)*framesPerTick).rounded())
            if recording || armed{
                guard pendingPadInputs.count<4096 else{break}
                pendingPadInputs.append(PadRecordingInput(pad:hold.pad,tick:tick,clock:clock,velocity:hold.velocity))
            }else{retroHits.append(.init(tick:tick,pad:hold.pad,velocity:hold.velocity,clock:clock))}
        }
        hold.emitted=now;repeatHold=hold
    }
    /// I8: while recording, the first tap discards what was played in the current
    /// pass; with an empty pass it removes the previous committed pass. The loop
    /// and the recording keep going.
    var canUndoPass:Bool{recording && (!(drumPass?.events.isEmpty ?? true) || drumDraft?.canUndoPass == true)}
    func undoPass() {
        guard recording,var draft=drumDraft else{return}
        drainPadRecordingInputs()
        if drumPass?.events.isEmpty ?? true{guard draft.undoLastPass() else{return}}
        do{drumDraft=draft;drumPass=try DrumRecordingPass(draft:draft,replacing:replaceNextPass ? loopRange:nil);rawHits=[];sync()}
        catch{message=error.localizedDescription;drumPass=nil;rawHits=[]}
    }
    func commitPass() {
        guard var draft=drumDraft else{return}
        do{
            try draft.commitPass(drumPass?.events ?? [],replacing:replaceNextPass ? loopRange:nil,timing:recordingTiming)
            drumDraft=draft;replaceNextPass=false;rawHits=[]
            drumPass=try DrumRecordingPass(draft:draft)
            sync()
        }catch{message=error.localizedDescription;drumPass=nil;rawHits=[]}
    }
    /// Keep the contact path bounded: enqueue sound, snapshot the transport and
    /// return. Recording bookkeeping is drained in order by the existing poll.
    @discardableResult func hit(_ pad:Int,touchTime:TimeInterval?=nil,velocity:Int?=nil)->Bool {
        guard !backgrounded,!performance.replaying,(0..<16).contains(pad),audio.isPrepared || ensureAudio() else{return false}
        let strength=min(127,max(1,velocity ?? 100))
        guard audio.pad(pad,velocity:strength) else{return false}
        lastPadVelocity=strength
        acceptedPadHits+=1
        if tour != nil{tourEvent(.padHit)}
        if let touchTime,touchTime.isFinite{lastPadDispatchMilliseconds=max(0,(ProcessInfo.processInfo.systemUptime-touchTime)*1000)}
        if recording || armed {
            audio.refreshClock()
            guard pendingPadInputs.count<4096 else{message=MusicError.tooDense.localizedDescription;return true}
            pendingPadInputs.append(PadRecordingInput(pad:pad,tick:Int(audio.tick),clock:audio.clock,velocity:strength))
        } else if audio.playing {
            audio.refreshClock()
            retroHits.append(.init(tick:Int(audio.tick),pad:pad,velocity:strength,clock:audio.clock))
        }
        return true
    }
    private func drainPadRecordingInputs(){
        guard !pendingPadInputs.isEmpty else{return}
        let inputs=pendingPadInputs;pendingPadInputs=[]
        let frames=UInt64((Double(loopRange.count)/Double(ppq)*60/project.bpm*audio.sampleRate).rounded())
        for input in inputs {
            if armed && input.clock>=armClock{armed=false;recording=true}
            guard recording else{continue}
            if frames>0,input.clock>=passClock,input.clock-passClock>=frames{
                let passes=(input.clock-passClock)/frames
                commitPass();passClock+=passes*frames
            }
            // Recorded position follows what the musician heard on this route.
            var heard=routeLatency[currentRouteKey].map{RouteLatencyCalibration.heardTick(input.tick,milliseconds:$0,bpm:project.bpm)} ?? input.tick
            // Heard just before the loop restarted: it belongs at the loop's end.
            if heard<loopRange.lowerBound,input.tick>=loopRange.lowerBound{heard+=loopRange.count}
            guard let draft=drumDraft,let local=draft.localTick(heard) ?? draft.localTick(input.tick),drumPass != nil else{continue}
            var event=DrumEvent(tick:recordingTiming.tick(local,length:takeLength),pad:input.pad,velocity:input.velocity)
            event.played=local
            do{
                try drumPass?.append(event)
                rawHits.append(RawHit(tick:local,sampleFrame:input.clock,event:event))
            }catch{message=error.localizedDescription}
        }
    }
    func finishTake() {
        flushRepeatHits()
        drainPadRecordingInputs()
        let hadTake=recording;armed=false;recording=false
        if hadTake{commitPass()}
        let finished=drumDraft;drumDraft=nil;drumPass=nil;drumPlayback=nil;pendingPadInputs=[];rawHits=[];takePattern=nil
        if let finished,finished.changed{edit{$0=try finished.candidate(for:$0)}}else if finished != nil{sync()}
    }
    func previewHarmony(_ p:Project,section:MusicDomain.Section){
        previewAssistant(p,wholeSong:false,sectionID:section.id)
    }
    func previewAssistant(_ candidate:Project,wholeSong:Bool,sectionID:UUID,rangeOverride:Range<Int>?=nil,loopOverride:Bool?=nil){
        guard !performance.contextActive else{message="Return to editing before changing the source project.";return}
        finishTake();guard ensureAudio()else{return}
        guard candidate.id==project.id,candidate.revision==project.revision,let section=candidate.sections.first(where:{$0.id==sectionID})else{message=AssistantError.stale.localizedDescription;return}
        if let rangeOverride{guard rangeOverride.lowerBound>=0,rangeOverride.upperBound<=candidate.length,!rangeOverride.isEmpty else{message=MusicError.invalidProject.localizedDescription;return}}
        do{try candidate.validate()}catch{message=error.localizedDescription;return}
        auditionDraft(candidate, range:rangeOverride ?? (wholeSong ? 0..<candidate.length:section.start..<section.start+section.length), loop:loopOverride ?? true)
    }
    /// Plays a prepared draft; false (with `message` or `audio.error` set) when it cannot start.
    @discardableResult func previewNewTrack(_ draft: PreparedTrackDraft, range: Range<Int>? = nil) -> Bool {
        let candidate = draft.project
        guard !performance.contextActive else { message = "Return to editing before changing the source project."; return false }
        guard candidate.id != project.id, ensureAudio() else { return false }
        let bounds = range ?? 0..<candidate.length
        guard !bounds.isEmpty, bounds.lowerBound >= 0, bounds.upperBound <= candidate.length else {
            message = MusicError.invalidProject.localizedDescription
            return false
        }
        finishTake()
        let loops = draft.loops && range == nil
        audio.refreshClock()
        if !harmonyPreview { previewPosition = Int(audio.tick); previewPlaying = audio.playing }
        guard audio.audition(candidate, range: bounds, loop: loops, samples: draft.samples, restart: true) else { return false }
        previewingNewTrack = true
        draftTailStart = nil
        draftEndTick = loops ? nil : bounds.upperBound
        harmonyPreview = true
        if runtimeTraceEnabled { runtimeTrace("draft.preview-start range=\(bounds.lowerBound)..<\(bounds.upperBound)") }
        syncMIDI()
        return true
    }
    private func auditionDraft(_ candidate:Project, range:Range<Int>, loop:Bool) {
        if !harmonyPreview{previewPosition=Int(audio.tick);previewPlaying=audio.playing;harmonyPreview=true}
        audio.audition(candidate,range:range,loop:loop);syncMIDI()
    }
    /// U67 · Plays four bars of any project (a template, style, beat or palette) while a card is
    /// held. Nothing is saved; `endHarmonyPreview()` returns the transport to where it was.
    @discardableResult func holdPreview(_ candidate:Project,range:Range<Int>,samples:SampleLibrary?=nil)->Bool{
        guard !performance.contextActive,!recording,!armed else{return false}
        finishTake();guard ensureAudio()else{return false}
        guard !range.isEmpty,range.lowerBound>=0,range.upperBound<=candidate.length,(try? candidate.validate()) != nil else{return false}
        audio.refreshClock()
        if !harmonyPreview{previewPosition=Int(audio.tick);previewPlaying=audio.playing;harmonyPreview=true}
        guard audio.audition(candidate,range:range,loop:true,samples:samples,restart:true)else{restorePreviewTransport();return false}
        previewingNewTrack=candidate.id != project.id
        syncMIDI()
        return true
    }
    func endHarmonyPreview(){
        practicing=false
        guard harmonyPreview else{return};restorePreviewTransport();sync()
    }
    private func restorePreviewTransport(){
        guard harmonyPreview else{return};harmonyPreview=false
        // Any normal source sync replaces an audition. A preview started from
        // idle returns to its stopped position; a running song keeps its phase.
        if previewingNewTrack && previewPlaying { audio.restartAt(previewPosition) }
        else if !previewPlaying { audio.stop(); audio.seek(previewPosition) }
        previewingNewTrack = false
        draftEndTick = nil
        draftTailStart = nil
    }
    private(set) var trackIdea = ""
    private(set) var trackDraftName = ""
    private(set) var suggestedTrackBrief: TrackBrief?
    private(set) var editingArrangementCopy = false
    private(set) var trackSuggestionUsesApple = false
    func openTrackBuilder(idea:String = "", name:String = "", suggestion: TrackBrief? = nil, asCopy: Bool = false, usesApple: Bool = false) {
        trackSuggestionUsesApple = usesApple
        editingArrangementCopy = asCopy
        suggestedTrackBrief = suggestion
        endHarmonyPreview()
        trackIdea=idea
        trackDraftName=name
        sheet = .trackBuilder
    }
    func presentEditor(_ sheet:Sheet){if performance.contextActive{Task{await leavePerformance();self.sheet=sheet}}else{finishTake();self.sheet=sheet}}
    /// 55 · The track the arpeggiator opens on (nil = the first harmony or melody track).
    var arpeggiatorTrackID:UUID?
    func openArpeggiator(_ id:UUID?=nil){
        arpeggiatorTrackID=id ?? project.tracks.first{$0.role == .harmony || $0.role == .melody}?.id
        presentEditor(.arpeggiator)
    }
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
    func deleteMelody(_ id:UUID){finishTake();edit{try ProjectTrash.deleteTrack(id,in:&$0)};noteTrackID=project.tracks.first{$0.role == .melody}?.id}
    func setLoop(bars: Int? = nil, enabled: Bool? = nil) {guard !recording && !armed else{message="Finish the take before changing the loop.";return};if let bars{loopBars=bars};if let enabled{loop=enabled};saveGeneratedLoopPreference();sync()}
    func select(_ section: MusicDomain.Section) {if performance.contextActive{performance.queueSection(section.id);return};guard !recording && !armed else{return};selectedSection=section.id;sync();if !audio.playing{audio.seek(section.start)}}
    @discardableResult
    func reorderSection(drop items: [String], onto targetID: UUID) -> Bool {
        guard !performance.contextActive, !recording, !armed, items.count == 1 else { return false }
        do {
            let payload = try ArrangementDragPayload.decode(items[0])
            try payload.validate(in: project, kind: .section)
            if payload.objectID == targetID {
                return project.sections.contains { $0.id == targetID }
            }
            let before = project.revision
            edit { try ClipEditing.reorderSection(payload, to: targetID, in: &$0) }
            return project.revision != before
        } catch {
            message = error.localizedDescription
            return false
        }
    }
    func open(_ p: Project, force: Bool = false) async {
        if p.id==project.id{await openStored(p.id);return}
        guard let token=beginProjectChange()else{return}
        defer{endProjectChange(token)}
        do{
            try p.validate()
            let expected=try await prepareProjectChange(token,checkpoint:true)
            let samples = try await store.loadSamples(for: p)
            try verifyProjectChange(token,expected:expected)
            activateProject(p,savedRevision:p.revision,samples:samples)
        }catch{message=error.localizedDescription}
    }
    func openStored(_ id:UUID)async {
        guard let token=beginProjectChange()else{return}
        defer{endProjectChange(token)}
        let active=id==project.id
        do{
            // An active document is validated BEFORE any checkpoint write. A
            // recovery Retry must never replace corrupt/future disk bytes.
            let expected=try await prepareProjectChange(token,checkpoint:!active)
            let stored=try await store.load(id)
            guard stored.id==id else{throw MusicError.invalidProject}
            let samples = try await store.loadSamples(for: stored)
            try await projectChangeBoundary(token,expected:expected,stage:"stored.loaded")
            if active {
                let hasUnsavedWork=project.revision>savedRevision || saveError != nil
                if stored != project && hasUnsavedWork {
                    await refreshLibraryEntry(id,validated:true)
                    try verifyProjectChange(token,expected:expected)
                    message=NSLocalizedString("The stored project is valid. Your unsaved edits are kept. Save or save a copy before replacing them.",comment:"Safe active project retry")
                    return
                }
                if stored==project {
                    await refreshLibraryEntry(id,validated:true)
                    try verifyProjectChange(token,expected:expected)
                    saveError=nil;sheet=nil;return
                }
            }
            try verifyProjectChange(token,expected:expected)
            activateProject(stored,savedRevision:stored.revision,samples:samples)
            await refreshLibraryEntry(id,validated:true)
        }catch{
            message=error.localizedDescription
            if !(error is ProjectChangeError),!(error is CancellationError){markLibraryFailure(id,error:error.localizedDescription)}
        }
    }
    private var projectIdentity:ProjectIdentity{ProjectIdentity(id:project.id,revision:project.revision)}
    private func beginProjectChange()->UUID? {
        guard projectChangeToken==nil else{message=ProjectChangeError.busy.localizedDescription;return nil}
        let token=UUID();projectChangeToken=token;return token
    }
    private func endProjectChange(_ token:UUID){if projectChangeToken==token{projectChangeToken=nil}}
    private func verifyProjectChange(_ token:UUID,expected:ProjectIdentity?=nil)throws {
        try Task.checkCancellation()
        guard projectChangeToken==token else{throw ProjectChangeError.busy}
        if let expected,projectIdentity != expected{throw ProjectChangeError.changed}
    }
    private func projectChangeBoundary(_ token:UUID,expected:ProjectIdentity,stage:String)async throws {
        try verifyProjectChange(token,expected:expected)
        if ProcessInfo.processInfo.arguments.contains("--uitesting"),let interleave=projectChangeQAInterleave {
            await interleave(stage)
            try verifyProjectChange(token,expected:expected)
        }
    }
    private func prepareProjectChange(_ token:UUID,checkpoint:Bool)async throws->ProjectIdentity {
        let beforeBootstrap=ready ? projectIdentity:nil
        await bootstrap()
        try verifyProjectChange(token,expected:beforeBootstrap)
        // Finalize our own recording changes synchronously before taking the
        // source revision. Every later accepted music/mix edit invalidates it.
        if performance.contextActive{performance.finalizeBeforeReset();pollPerformance()}
        finishTake();endHarmonyPreview()
        let expected=projectIdentity
        if performance.contextActive{
            await leavePerformance()
            try verifyProjectChange(token,expected:expected)
        }
        if exportInProgress{cancelExport()}
        audio.stop()
        if checkpoint{try await checkpointProjectChange(token,expected:expected);try verifyProjectChange(token,expected:expected)}
        return expected
    }
    private func checkpointProjectChange(_ token:UUID,expected:ProjectIdentity)async throws {
        try verifyProjectChange(token,expected:expected)
        guard !hasKnownLibraryFailure(project.id)else{saveError=ProjectChangeError.needsWorkingCopy.localizedDescription;throw ProjectChangeError.needsWorkingCopy}
        let snapshot=project
        let revision:Int
        do{revision=try await store.save(snapshot)}catch{saveError=error.localizedDescription;throw error}
        try await projectChangeBoundary(token,expected:expected,stage:"checkpoint.saved")
        guard revision==snapshot.revision else{throw ProjectChangeError.changed}
        savedRevision=max(savedRevision,revision);saveError=nil
        await refreshLibraryEntry(snapshot.id,validated:true)
        try verifyProjectChange(token,expected:expected)
    }
    private func retainUnopenedProject(_ candidate:Project)async {
        await refreshLibraryEntry(candidate.id,validated:true)
        // The copy really exists. Expose it instead of leaving Create active
        // with a hidden successful write that a blind retry would duplicate.
        sheet = .projects
        message=NSLocalizedString("A separate project was saved but not opened. Your current project and latest edits are kept. Open the saved project from Projects.",comment:"Safe project change")
    }
    private func activateProject(_ p:Project,savedRevision:Int,samples:SampleLibrary=SampleLibrary()){
        audio.samples = samples
        restoringWorkspace=true
        project=p;history=History();noteTrackID=nil;noteClipID=nil;drumClipID=nil;selectedSection=p.sections[0].id;self.savedRevision=savedRevision
        openedSnapshot=p;openedAt=Date();savedAt=savedRevision==p.revision ? Date():nil
        // U36: come back to the same screen and section of this song.
        if !Luz.uiTesting,let saved=UserDefaults.standard.string(forKey:"workspace."+p.id.uuidString)?.split(separator:"|"),saved.count==2 {
            if let value=Int(saved[0]),(0...2).contains(value){tab=value}
            if let id=UUID(uuidString:String(saved[1])),p.sections.contains(where:{$0.id==id}){selectedSection=id}
        }
        restoringWorkspace=false
        restoreGeneratedLoop();audio.seek(section.start);sync();sheet=nil
        UserDefaults.standard.set(p.id.uuidString,forKey:lastProjectKey)
    }
    @ObservationIgnored private var restoringWorkspace=false
    private func rememberWorkspace(){
        guard !restoringWorkspace,let id=selectedSection else{return}
        UserDefaults.standard.set("\(tab)|\(id.uuidString)",forKey:"workspace."+project.id.uuidString)
    }
    @discardableResult func create(name: String,bpm: Double,root: Int,minor: Bool,bars: Int,template:ProjectTemplate = .empty) async -> Bool {
        do {
            // U35: an empty name becomes "A minor · 92 · Tuesday".
            let title=name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? ProjectNaming.suggest(keyRoot:root,minor:minor,bpm:bpm):name
            let project = try ProjectTemplates.make(name:title,bpm:bpm,root:root,minor:minor,bars:bars,template:template)
            return await saveNewProject(project)
        } catch { message=error.localizedDescription; return false }
    }

    /// 54 · Track in a minute: a new project in `genre` with beat, 808, chords, bass and melody as
    /// a verse and a chorus, applied as one undoable edit so "Another one" can swap it.
    var quickTrack:(genre:BeatPreset.Genre,seed:UInt32,projectID:UUID,revision:Int)?
    /// The card offering a clip and "Another one" shows while the track is as it was made.
    var quickTrackFresh:Bool{guard let quickTrack else{return false};return quickTrack.projectID==project.id && quickTrack.revision==project.revision}
    @discardableResult func createQuickTrack(_ genre:BeatPreset.Genre,name:String,root:Int,minor:Bool,seed:UInt32=0) async -> Bool {
        let title=name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? NSLocalizedString(genre.title,comment:"Genre") : name
        guard await create(name:title,bpm:QuickTrack.tempo(for:genre,seed:seed),root:root,minor:minor,bars:QuickTrack.sectionBars) else { return false }
        return await fillQuickTrack(genre,seed:seed)
    }
    /// 54 · "Another one": back to the empty project, then a different beat and melody.
    @discardableResult func anotherQuickTrack() async -> Bool {
        guard let current=quickTrack,quickTrackFresh,history.canUndo else { return false }
        undo()
        return await fillQuickTrack(current.genre,seed:current.seed &+ 1)
    }
    private func fillQuickTrack(_ genre:BeatPreset.Genre,seed:UInt32) async -> Bool {
        let base=project,id=project.id,revision=project.revision
        do {
            let result=try await Task.detached(priority:.userInitiated){try QuickTrack.make(from:base,genre:genre,seed:seed)}.value
            try await applyPalette(result.project,kit:result.sounds,projectID:id,revision:revision)
            quickTrack=(genre,seed,project.id,project.revision)
            if let verse=project.sections.first{select(verse)}
            return true
        } catch { message=error.localizedDescription; return false }
    }

    @discardableResult func saveGeneratedTrack(_ draft: PreparedTrackDraft) async -> Bool {
        await saveNewProject(draft.project, preparedDraft: draft)
    }
    @discardableResult func saveNewProject(_ p: Project, preparedDraft: PreparedTrackDraft? = nil) async -> Bool {
        guard let token = beginProjectChange() else { return false }
        defer { endProjectChange(token) }
        do { try p.validate() } catch { message=error.localizedDescription; return false }
        var written=false
        do {
            let expected=try await prepareProjectChange(token,checkpoint:true)
            let revision: Int
            if let preparedDraft {
                revision = try await store.install(preparedDraft.bundle).revision
            } else { revision = try await store.save(p) }
            written=true
            try await projectChangeBoundary(token,expected:expected,stage:"candidate.saved")
            try verifyProjectChange(token,expected:expected)
            loopBars=p.length/barTicks
            if let preparedDraft {
                UserDefaults.standard.set(["bars": loopBars, "enabled": preparedDraft.loops], forKey: generatedLoopKey(p.id))
            }
            activateProject(p,savedRevision:revision,samples:preparedDraft?.samples ?? SampleLibrary())
        }catch{if written{await retainUnopenedProject(p)}else{message=error.localizedDescription};return false}
        await refreshLibraryEntry(p.id,validated:true)
        return true
    }
    @discardableResult func openExample()async->Bool {
        guard let token=beginProjectChange()else{return false}
        defer{endProjectChange(token)}
        let example=Project.demo()
        var written=false
        do {
            let expected=try await prepareProjectChange(token,checkpoint:true)
            let revision=try await store.save(example)
            written=true
            try await projectChangeBoundary(token,expected:expected,stage:"candidate.saved")
            try verifyProjectChange(token,expected:expected)
            loopBars=4
            activateProject(example,savedRevision:revision)
        }catch{if written{await retainUnopenedProject(example)}else{message=error.localizedDescription};return false}
        await refreshLibraryEntry(example.id,validated:true)
        return true
    }

    func createFromPerformance(_ take: PerformanceTake) async -> Bool {
        guard let token = beginProjectChange() else { return false }
        defer { endProjectChange(token) }
        var written: Project?
        do {
            let expected = try await prepareProjectChange(token, checkpoint: true)
            guard project.performanceTake?.id == take.id else { throw ProjectChangeError.changed }
            let derived = try await store.createFromPerformance(take, projectID: expected.id)
            written = derived
            try await projectChangeBoundary(token, expected: expected, stage: "candidate.saved")
            let samples = try await store.loadSamples(for: derived)
            try verifyProjectChange(token, expected: expected)
            UserDefaults.standard.set(["bars": derived.length / barTicks, "enabled": false], forKey: generatedLoopKey(derived.id))
            activateProject(derived, savedRevision: derived.revision, samples: samples)
            tab = 0
            await refreshLibraryEntry(derived.id, validated: true)
            return true
        } catch {
            if let written { await retainUnopenedProject(written) }
            else { message = error.localizedDescription }
            return false
        }
    }

    func duplicateStored(_ id:UUID)async {
        do{
            let source:Project
            if id==project.id{source=project}else{source=try await store.load(id)}
            guard source.id==id else{throw MusicError.invalidProject}
            let copy=try await store.duplicate(source)
            copyGeneratedLoopPreference(from:source.id,to:copy.id)
            await refreshLibraryEntry(copy.id,validated:true)
        }catch{message=error.localizedDescription}
    }
    func renameStored(_ id:UUID,expectedRevision:Int,to title:String)async {
        var validated=false
        do{_ = try await store.rename(id,expectedRevision:expectedRevision,to:title);validated=true}catch{message=error.localizedDescription}
        await refreshLibraryEntry(id,validated:validated)
    }
    /// I73: deleting moves the project to Recently Deleted for 30 days.
    func delete(_ id: UUID) async {do{try await store.moveToTrash(id);entries.removeAll{$0.id==id};libraryLoadFailures.removeValue(forKey:id);UserDefaults.standard.removeObject(forKey:generatedLoopKey(id))}catch{message=error.localizedDescription}}
    func restoreDeleted(_ id:UUID)async {do{try await store.restoreFromTrash(id);await refreshLibrary()}catch{message=error.localizedDescription}}
    func recover(_ id:UUID)async {
        guard let token=beginProjectChange()else{return}
        defer{endProjectChange(token)}
        var written:Project?
        do{
            let expected=try await prepareProjectChange(token,checkpoint:false)
            let original=try await store.load(id,backup:true)
            try await projectChangeBoundary(token,expected:expected,stage:"backup.loaded")
            try await checkpointProjectChange(token,expected:expected)
            try verifyProjectChange(token,expected:expected)
            let candidate=try await store.duplicate(original,suffix:" recovered")
            written=candidate
            let samples = try await store.loadSamples(for: candidate)
            try await projectChangeBoundary(token,expected:expected,stage:"candidate.saved")
            activateProject(candidate,savedRevision:candidate.revision,samples:samples)
            await refreshLibraryEntry(candidate.id,validated:true)
            message="Recovered the last working copy."
        }catch{if let written{await retainUnopenedProject(written)}else{message=error.localizedDescription}}
    }
    enum ExportFormat:String,CaseIterable,Identifiable {
        case midi,wav,stems,project,aac,video,daw,dawproject,musicxml,ringtone
        var id:String{rawValue}
        var title:String{switch self{case .midi:"Standard MIDI";case .wav:"Stereo WAV";case .stems:"Aligned stems";case .project:"Portable project";case .aac:"AAC for sharing";case .video:"Video for social";case .daw:"For a DAW: stems, MIDI, README";case .dawproject:"DAWproject (Cubase, Studio One, Bitwig)";case .musicxml:"Lead sheet (MusicXML)";case .ringtone:"Ringtone (30 s)"}}
        var fileExtension:String{switch self{case .midi:"mid";case .wav:"wav";case .stems,.daw:"zip";case .dawproject:DAWProject.fileExtension;case .project:"grillapack";case .aac:"m4a";case .video:"mp4";case .musicxml:"musicxml";case .ringtone:"m4r"}}
    }
    /// 54: the picture and credit of the next video export, and a clip length the export sheet opens with.
    var videoStyle:VideoStyle = .map
    var videoCredit=true
    var exportClip:ShareClip.Length?
    func export(format:ExportFormat,settings:WAVSettings,range:Range<Int>,tracks:Set<UUID>,performance:PerformanceTake?=nil) {
        if performance != nil && format != .midi && format != .wav && format != .aac{exportError="Choose WAV or MIDI for a performance.";return}
        finishTake();cancelExport();exportGeneration+=1;let generation=exportGeneration
        let snapshot=performance?.source ?? project;let samples=audio.samples;let takes=audio.takes;let effects=PluginEditing.activeMasterEffects(snapshot);exportInProgress=true;exportProgress=0;exportWarning=nil
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
                    let receipt:RenderReceipt;if let performance{receipt=try await OfflineRenderer.renderPerformance(performance,to:url,settings:settings,samples:samples,progress:progress)}else{receipt=try await OfflineRenderer.render(snapshot,to:url,settings:settings,range:range,samples:samples,takes:takes,progress:progress)}
                    if receipt.clipped{exportWarning="Clipping was detected. Lower track or master gain for a cleaner export."}
                    // 54: the song's effect plugins process the mix, as heard live.
                    if !effects.isEmpty{try await PluginHost.process(url,through:effects)}
                    // I51: title, artist and tempo/key inside the file.
                    try? WAVMetadata.write(url,title:snapshot.name,artist:UserDefaults.standard.string(forKey:"notes.author"),comment:"\(Int(snapshot.bpm.rounded())) BPM · \(snapshot.keyName)")
                case .stems:_ = try await StemExporter.render(snapshot,to:url,settings:settings,range:range,selected:tracks,samples:samples,takes:takes,progress:progress)
                case .ringtone:
                    // I50: the first 30 seconds of the chosen range as an iPhone ringtone (AAC in .m4r).
                    let seconds=Int((30*snapshot.bpm/60*Double(ppq)).rounded(.down))
                    let short=range.lowerBound..<min(range.upperBound,range.lowerBound+max(barTicks,seconds))
                    let wav=folder.appendingPathComponent("ringtone.wav")
                    _ = try await OfflineRenderer.render(snapshot,to:wav,settings:WAVSettings(sampleRate:settings.sampleRate,bitDepth:settings.bitDepth,tailSeconds:0.5),range:short,samples:samples,takes:takes,progress:progress)
                    // 54: the song's effect plugins process the mix, as heard live.
                    if !effects.isEmpty{try await PluginHost.process(wav,through:effects)}
                    try await Task.detached(priority:.userInitiated){try AACEncoder.encode(wav:wav,to:url)}.value
                    try? FileManager.default.removeItem(at:wav)
                case .musicxml:
                    // I49: melody, chord symbols, lyrics and section marks for notation apps.
                    try MusicXMLExporter.data(snapshot).write(to:url,options:.atomic)
                case .dawproject:
                    // 54: notes and aligned audio per track, tempo, levels and markers in the open format.
                    let version=(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")+" ("+(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "")+")"
                    let entries=DAWProject.entries(snapshot,range:range,settings:settings,version:version)
                    _ = try await StemExporter.render(snapshot,to:url,settings:settings,range:range,selected:nil,samples:samples,takes:takes,extras:entries,progress:progress)
                case .daw:
                    // I14: every track as an aligned stem, plus song.mid and a README.
                    let extras=try DAWPackage.extras(snapshot,range:range,settings:settings)
                    _ = try await StemExporter.render(snapshot,to:url,settings:settings,range:range,selected:nil,samples:samples,takes:takes,extras:extras,progress:progress)
                case .aac:
                    let wav=folder.appendingPathComponent("mix.wav")
                    let receipt:RenderReceipt;if let performance{receipt=try await OfflineRenderer.renderPerformance(performance,to:wav,settings:settings,samples:samples,progress:progress)}else{receipt=try await OfflineRenderer.render(snapshot,to:wav,settings:settings,range:range,samples:samples,takes:takes,progress:progress)}
                    if receipt.clipped{exportWarning="Clipping was detected. Lower track or master gain for a cleaner export."}
                    // 54: the song's effect plugins process the mix, as heard live.
                    if !effects.isEmpty{try await PluginHost.process(wav,through:effects)}
                    try await Task.detached(priority:.userInitiated){try AACEncoder.encode(wav:wav,to:url)}.value
                    try? FileManager.default.removeItem(at:wav)
                case .video:
                    // I67: the same mix as WAV, then frames drawn offline and joined into an MP4.
                    let wav=folder.appendingPathComponent("mix.wav")
                    let half:@Sendable(Double)->Void={value in progress(value*0.5)}
                    let receipt=try await OfflineRenderer.render(snapshot,to:wav,settings:settings,range:range,samples:samples,takes:takes,progress:half)
                    if receipt.clipped{exportWarning="Clipping was detected. Lower track or master gain for a cleaner export."}
                    let style=videoStyle,credit=videoCredit
                    if !effects.isEmpty{try await PluginHost.process(wav,through:effects)}
                    try await Task.detached(priority:.userInitiated){try await VideoExporter.encode(wav:wav,project:snapshot,range:range,to:url,style:style,credit:credit,progress:progress)}.value
                    try? FileManager.default.removeItem(at:wav)
                }
                try Task.checkCancellation();guard generation==exportGeneration else{return}
                exportProgress=1;exportInProgress=false;exportedFolder=folder;exportedURL=url;sheet=nil;exportTask=nil;if exportWarning==nil{Luz.Haptics.success()}else{Luz.Haptics.warning()}
            } catch {
                try? FileManager.default.removeItem(at:folder)
                if generation==exportGeneration{exportInProgress=false;exportTask=nil;if !(error is CancellationError){exportError=error.localizedDescription}}
            }
        }
    }
    /// I70: every saved project (up to 64) in one zip for Files or AirDrop.
    func exportAllProjects() {
        finishTake();cancelExport();exportGeneration+=1;let generation=exportGeneration
        let ids=Array(entries.filter{$0.summary != nil}.map(\.id).prefix(64))
        guard !ids.isEmpty else{return}
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("GrillaExport-"+UUID().uuidString)
        let url=folder.appendingPathComponent(NSLocalizedString("La Grilla projects",comment:"Batch export file name")).appendingPathExtension("zip")
        exportInProgress=true;exportProgress=0;exportError=nil
        exportTask=Task { @MainActor in
            do {
                await save()
                try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                try await store.portableBatch(ids,to:url)
                try Task.checkCancellation();guard generation==exportGeneration else{return}
                exportProgress=1;exportInProgress=false;exportedFolder=folder;exportedURL=url;sheet=nil;exportTask=nil;if exportWarning==nil{Luz.Haptics.success()}else{Luz.Haptics.warning()}
            } catch {
                try? FileManager.default.removeItem(at:folder)
                if generation==exportGeneration{exportInProgress=false;exportTask=nil;if !(error is CancellationError){message=error.localizedDescription}}
            }
        }
    }
    func cancelExport(){exportGeneration+=1;exportTask?.cancel();exportTask=nil;exportInProgress=false;exportProgress=0}
    func finishSharing() {
        if let folder=exportedFolder{Task{try? await Task.sleep(for:.seconds(1));try? FileManager.default.removeItem(at:folder)}}
        exportedFolder=nil
        if let warning=exportWarning{message=warning;exportWarning=nil}
    }
    // MARK: 54 · Audio tracks

    /// Takes the audio tracks use, decoded into the engine (and for exports); unused ones are let go.
    @ObservationIgnored private var loadingTakes=false
    /// Takes that could not be read (shown on the audio tracks screen, not retried on every sync).
    private(set) var unreadableTakes:Set<UUID>=[]
    func loadAudioTakes() async {
        guard !loadingTakes else { return }
        loadingTakes=true;defer{loadingTakes=false}
        let projectID=project.id
        let used=Set((project.audioTracks ?? []).flatMap{$0.clips.map(\.assetID)})
        for record in (project.audioAssets ?? []) where used.contains(record.id) && !audio.hasTake(record.id) {
            guard !unreadableTakes.contains(record.id) else { continue }
            guard let url=try? await store.assetURL(record,projectID:projectID),project.id==projectID,
                  let read=try? await Task.detached(priority:.userInitiated,operation:{try AudioTakeReader.samples(Data(contentsOf:url))}).value else { unreadableTakes.insert(record.id); continue }
            audio.insertTake(record.id,samples:read.samples,rate:read.rate)
        }
        guard project.id==projectID else { return }
        audio.retainTakes(used)
        sync()
    }
    /// True while a take the song uses is not in the engine yet.
    var audioTakesMissing:Bool { (project.audioTracks ?? []).contains{$0.clips.contains{!audio.hasTake($0.assetID) && !unreadableTakes.contains($0.assetID)}} }

    @discardableResult func addAudioTrack() -> UUID? {
        var made:UUID?
        let name=String(format:NSLocalizedString("Audio %d",comment:"Audio track name"),(project.audioTracks?.count ?? 0)+1)
        edit{made=try AudioTrackEditing.addTrack(named:name,to:&$0)}
        return made
    }
    /// The compensation for this output: the calibrated value, else the system's round trip.
    var recordingLatency:Double {
        if let calibrated=routeLatency[currentRouteKey]{return max(0,calibrated/1000)}
        let session=AVAudioSession.sharedInstance()
        return max(0,min(0.5,session.inputLatency+session.outputLatency))
    }
    /// A finished take goes on its track where it was recorded, as one undoable edit.
    func applyAudioTake(_ result:AudioTakeResult,trackID:UUID,startTick:Int,projectID:UUID,latency:Double?=nil) async -> Bool {
        guard project.id==projectID,!recording,!armed,!performance.contextActive else { message=AssistantError.stale.localizedDescription; return false }
        do {
            try await store.writeAsset(result.data,record:result.record,projectID:projectID)
            guard project.id==projectID else { await store.removeStagedAsset(result.record,projectID:projectID); return false }
            var candidate=project
            try AudioTrackEditing.place(result.record,on:trackID,at:startTick,latency:latency ?? recordingLatency,in:&candidate)
            try withHistoryTransaction{h,p in try h.apply(&p){$0=candidate}}
            audio.insertTake(result.record.id,samples:result.samples,rate:result.record.sampleRate)
            sync();await save()
            showToast("Take added")
            return saveError==nil
        } catch {
            await store.removeStagedAsset(result.record,projectID:projectID)
            message=error.localizedDescription;return false
        }
    }

    /// UI tests: an audio track with a two-second synthetic take at bar 1 (there is no microphone in CI).
    func installAudioFixture() async {
        guard project.audioTracks == nil, let track=addAudioTrack() else { return }
        // A 330 Hz tone with a short fade-out, spelled out so the type checker stays quick.
        let count=96000
        var samples=[Float](repeating:0,count:count)
        for index in 0..<count {
            let phase:Double=Double(index)/48000.0*2.0*Double.pi*330.0
            let fade:Double=min(1.0,Double(count-index)/4800.0)
            samples[index]=Float(sin(phase)*0.3*fade)
        }
        let data=AudioTakeReader.caf(samples,rate:48000)
        guard let sha=try? AssetIntegrity.sha256(data) else { return }
        let record=AudioAssetRecord(sha256:sha,byteCount:data.count,sampleRate:48000,duration:2,origin:.syntheticFixture)
        _ = await applyAudioTake(AudioTakeResult(data:data,record:record,samples:samples),trackID:track,startTick:0,projectID:project.id,latency:0)
    }

    // MARK: 54 · Plugins (AUv3)

    @ObservationIgnored private var buildingMasterChain=false
    /// Connects the song's effect plugins after the mix when they change.
    func syncMasterPlugins() {
        let active=PluginEditing.activeMasterEffects(project)
        let signature=active.map(\.id.uuidString)
        guard !audio.masterChainCurrent(signature),!buildingMasterChain,audio.isPrepared else { return }
        buildingMasterChain=true
        Task{@MainActor in
            defer{buildingMasterChain=false}
            var units:[AVAudioUnit]=[]
            for reference in active{
                do{units.append(try await PluginHost.instantiateLive(reference))}
                catch{message=String(format:NSLocalizedString("“%@”: %@",comment:"Plugin error"),reference.name,error.localizedDescription)}
            }
            audio.setMasterEffects(units,signature:signature)
        }
    }
    /// The live instance of a master effect, for its own screen.
    func liveMasterUnit(_ id:UUID)->AVAudioUnit?{
        guard let index=PluginEditing.activeMasterEffects(project).firstIndex(where:{$0.id==id}),audio.masterUnits.indices.contains(index) else{return nil}
        return audio.masterUnits[index]
    }
    var bounceProgress:Double?
    /// Plays a MIDI track through an instrument plugin offline and puts the result on an audio
    /// track (the source is muted; "Bounce again" replaces the take).
    @discardableResult func bounce(trackID:UUID,plugin:PluginReference) async -> Bool {
        let projectID=project.id
        let notes=PluginEditing.bounceNotes(project,track:trackID)
        guard !notes.isEmpty else{message=NSLocalizedString("This track has no notes to play.",comment:"Bounce");return false}
        let seconds=AudioTrackEditing.seconds(ticks:project.length,bpm:project.bpm)+2
        bounceProgress=0;defer{bounceProgress=nil}
        do {
            let samples=try await PluginHost.bounce(plugin,notes:notes,seconds:seconds,progress:{value in Task{@MainActor in self.bounceProgress=value}})
            let data=AudioTakeReader.caf(samples,rate:48000)
            let record=AudioAssetRecord(sha256:try AssetIntegrity.sha256(data),byteCount:data.count,sampleRate:48000,duration:Double(samples.count)/48000,origin:.plugin,recordedAt:Date())
            guard project.id==projectID else{return false}
            try await store.writeAsset(data,record:record,projectID:projectID)
            var candidate=project
            try PluginEditing.placeBounce(record,source:trackID,plugin:plugin,in:&candidate)
            try withHistoryTransaction{h,p in try h.apply(&p){$0=candidate}}
            audio.insertTake(record.id,samples:samples,rate:48000)
            sync();await save()
            showToast("Bounced to an audio track")
            return saveError==nil
        } catch { message=error.localizedDescription;return false }
    }

    // MARK: 54 · Harmony course and assignments

    /// "Try it": an empty song in `root` with the lesson's exercise, checked as you write.
    @discardableResult func startLesson(_ lesson:Lesson,root:Int) async -> Bool {
        do {
            let name=NSLocalizedString(lesson.title,comment:"Lesson")
            return await saveNewProject(try HarmonyCourse.workspace(lesson,root:root,name:name))
        } catch { message=error.localizedDescription; return false }
    }
    /// A teacher's assignment as a new song, then the export sheet to send its project file.
    @discardableResult func shareAssignment(_ assignment:HarmonyAssignment,bars:Int=4) async -> Bool {
        do {
            let name=String(format:NSLocalizedString("Assignment: %@",comment:"Assignment project"),NSLocalizedString(assignment.title,comment:"Lesson"))
            guard await saveNewProject(try assignment.project(name:name,bars:bars)) else { return false }
            exportPreset=ExportFormat.project.rawValue;sheet = .export
            return true
        } catch { message=error.localizedDescription; return false }
    }
    /// The student signs the song and sends its project file back.
    func submitAssignment(student:String) {
        let name=student.trimmingCharacters(in:.whitespacesAndNewlines)
        guard project.harmonyAssignment != nil,!name.isEmpty else { return }
        edit{$0.harmonyAssignment?.student=String(name.prefix(60));$0.harmonyAssignment?.submittedAt=Date()}
        exportPreset=ExportFormat.project.rawValue;sheet = .export
    }
    /// Results of students' songs this teacher has opened, newest first (kept on this iPhone).
    private(set) var assignmentResults:[AssignmentResult]={
        guard let data=UserDefaults.standard.data(forKey:"teacher.results"),let list=try? JSONDecoder().decode([AssignmentResult].self,from:data) else{return []}
        return list
    }()
    func recordAssignmentResult(_ project:Project) {
        guard let result=AssignmentResult(project) else { return }
        assignmentResults.removeAll{$0.id==result.id}
        assignmentResults.insert(result,at:0)
        assignmentResults=Array(assignmentResults.prefix(200))
        if let data=try? JSONEncoder().encode(assignmentResults){UserDefaults.standard.set(data,forKey:"teacher.results")}
    }
    func clearAssignmentResults(){assignmentResults=[];UserDefaults.standard.removeObject(forKey:"teacher.results")}

    /// 54 · "Make your version": the song in a remix link becomes a new project of its own,
    /// with the original title and author kept as its credit.
    func openRemix(_ url:URL) async {
        guard let payload=RemixLink.payload(from:url) else { message=RemixLink.Failure.damaged.localizedDescription; return }
        do {
            let project=try await Task.detached(priority:.userInitiated){try RemixLink.project(from:payload)}.value
            guard await saveNewProject(project) else { return }
            let credit=project.remixOf
            showToast(credit?.author.map{String(format:NSLocalizedString("Your version of “%@” by %@",comment:"Remix opened"),credit?.title ?? "",$0)}
                      ?? String(format:NSLocalizedString("Your version of “%@”",comment:"Remix opened"),credit?.title ?? project.name))
        } catch { message=error.localizedDescription }
    }
    /// 54 · The link that shares this song for others to make their version.
    func remixLink(author:String?) throws -> URL {
        let name=author?.trimmingCharacters(in:.whitespacesAndNewlines) ?? ""
        return try RemixLink.link(project,author:name.isEmpty ? nil:name)
    }

    func importProject(_ url:URL) async {
        guard let token=beginProjectChange()else{return}
        importing=true;defer{importing=false;endProjectChange(token)}
        let access=url.startAccessingSecurityScopedResource();defer{if access{url.stopAccessingSecurityScopedResource()}}
        var written:Project?
        do {
            let expected=try await prepareProjectChange(token,checkpoint:true)
            let imported=try await Task.detached(priority:.userInitiated){
                let handle=try FileHandle(forReadingFrom:url);defer{try? handle.close()}
                let data=try handle.read(upToCount:128_000_001) ?? Data();guard data.count<=128_000_000 else{throw ExportError.archiveTooLarge}
                // I75: a Standard MIDI File becomes a new editable project.
                if ["mid","midi","smf"].contains(url.pathExtension.lowercased()) {
                    return try MIDIFileImport.read(data,name:url.deletingPathExtension().lastPathComponent).bundle
                }
                return try PortableProject.decodeBundle(data)
            }.value
            try await projectChangeBoundary(token,expected:expected,stage:"import.decoded")
            let installed=try await store.install(imported)
            written=installed
            let samples = try await store.loadSamples(for: installed)
            initializeImportedListeningPreference(installed)
            try await projectChangeBoundary(token,expected:expected,stage:"candidate.saved")
            activateProject(installed,savedRevision:installed.revision,samples:samples)
            await refreshLibraryEntry(installed.id,validated:true)
            // 54: a student's song sent back is scored for the teacher.
            recordAssignmentResult(installed)
        }catch{if let written{await retainUnopenedProject(written)}else{message=error.localizedDescription}}
    }
    /// I78: bring a co-author's edited copy into the open project as one Undo.
    func mergeCopy(_ url:URL) async {
        guard !recording,!armed,!performance.contextActive else{message="Return to editing before changing the source project.";return}
        let access=url.startAccessingSecurityScopedResource();defer{if access{url.stopAccessingSecurityScopedResource()}}
        let mine=project
        do {
            let theirs=try await Task.detached(priority:.userInitiated){
                let handle=try FileHandle(forReadingFrom:url);defer{try? handle.close()}
                let data=try handle.read(upToCount:128_000_001) ?? Data();guard data.count<=128_000_000 else{throw ExportError.archiveTooLarge}
                return try PortableProject.decodeBundle(data,asCopy:false).project
            }.value
            let base=await store.sharedBase(mine.id)
            let (merged,report)=try ProjectMerge.merge(base:base,mine:mine,theirs:theirs)
            guard project.id==mine.id,project.revision==mine.revision else{message=AssistantError.stale.localizedDescription;return}
            guard report.hasChanges else{message=NSLocalizedString("The copy has no changes to bring in.",comment:"Merge");return}
            edit{$0=merged}
            var text=String(format:NSLocalizedString("Merged: %d changes taken, %d added, %d removed.",comment:"Merge"),report.takenFromTheirs,report.added,report.removed)
            if report.conflicts>0{text+=" "+String(format:NSLocalizedString("%d places changed on both sides kept your version.",comment:"Merge"),report.conflicts)}
            if report.keptSounds>0{text+=" "+NSLocalizedString("Imported sounds stay as they were on this iPhone.",comment:"Merge")}
            if base==nil{text+=" "+NSLocalizedString("Without a shared version nothing was removed.",comment:"Merge")}
            message=text
        }catch{message=error.localizedDescription}
    }
    func applyVoice(_ placement:VoicePlacement,data:Data,record:AudioAssetRecord,projectID:UUID,revision:Int)async throws->Bool {
        guard project.id==projectID,project.revision==revision,!recording,!armed,!performance.contextActive else{throw AssistantError.stale}
        try await store.writeAsset(data,record:record,projectID:projectID)
        guard project.id==projectID,project.revision==revision,!recording,!armed,!performance.contextActive else{await store.removeStagedAsset(record,projectID:projectID);throw AssistantError.stale}
        do{try withHistoryTransaction{h,p in try h.apply(&p){$0=placement.project}}}
        catch{await store.removeStagedAsset(record,projectID:projectID);throw error}
        noteTrackID=placement.trackID;sync();await save();return saveError==nil
    }
    func resetPadEdit(pad: Int, trackID: UUID, projectID: UUID, revision: Int) async throws {
        func matches() -> Bool {
            project.id == projectID && project.revision == revision && projectChangeToken == nil &&
                !recording && !armed && !performance.contextActive
        }
        guard matches(), let index = project.tracks.firstIndex(where: { $0.id == trackID }) else { throw SampleError.stale }
        var candidate = project
        let original = try candidate.tracks[index].restoreOriginal(pad: pad)
        let bank = try await store.storedSampleBank(original, projectID: projectID)
        try Task.checkCancellation()
        guard matches() else { throw SampleError.stale }
        try withHistoryTransaction { history, project in try history.apply(&project) { $0 = candidate } }
        audio.samples.insert(bank)
        audio.samples.retainOnly(history.retainedSamples.union(project.referencedSamples))
        mixerGesture = false
        sync()
        scheduleSave()
    }
    func assignSounds(_ changes: [(pad: Int?, sound: PreparedSound)], trackID: UUID,
                      projectID: UUID, revision: Int, padEdit: PadSampleEditRecord? = nil) async throws {
        func matches() -> Bool {
            project.id == projectID && project.revision == revision && projectChangeToken == nil &&
                !recording && !armed && !performance.contextActive
        }
        guard matches(), let index = project.tracks.firstIndex(where: { $0.id == trackID }) else { throw SampleError.stale }
        guard !changes.isEmpty, Set(changes.map { $0.pad }).count == changes.count else { throw SampleError.invalid }
        if let padEdit {
            guard changes.count == 1, let pad = changes[0].pad,
                  let current = project.tracks[index].padSamples?[pad],
                  padEdit.source == (project.tracks[index].padEdits?[pad]?.source ?? current) else {
                throw SampleError.stale
            }
        }
        var candidate = project
        for (pad, sound) in changes {
            if let pad {
                try candidate.tracks[index].setPadSample(sound.asset, pad: pad, edit: padEdit)
            } else {
                candidate.tracks[index].instrumentSample = sound.asset
            }
        }
        try candidate.validate()
        let retained = history.retainedSamples.union(project.referencedSamples).union(candidate.referencedSamples)
        guard retained.reduce(0, { $0 + $1.byteCount }) <= 128_000_000 else { throw SampleError.limit }
        var prepared: [PreparedSampleBank] = []
        do {
            for change in changes {
                try Task.checkCancellation()
                guard matches() else { throw SampleError.stale }
                let sound = change.sound
                prepared.append(try await store.stageSample(sound.data, asset: sound.asset, projectID: projectID))
            }
            try Task.checkCancellation()
            guard matches() else { throw SampleError.stale }
            try withHistoryTransaction { history, project in try history.apply(&project) { $0 = candidate } }
        } catch {
            for bank in prepared { await store.removeStagedSample(bank.asset, projectID: projectID) }
            throw error
        }
        for bank in prepared { audio.samples.insert(bank) }
        audio.samples.retainOnly(history.retainedSamples.union(project.referencedSamples))
        mixerGesture = false
        sync()
        scheduleSave()
    }
    // MARK: Build 46 palettes

    /// The loaded sounds plus a palette's kit, for auditioning without staging anything.
    func paletteLibrary(_ kit: [(pad: Int, asset: SampleAsset, data: Data)]) throws -> SampleLibrary {
        try PaletteAudition.library(audio.samples, kit: kit)
    }

    /// Audition a palette candidate of the current revision. The project and
    /// its Undo history stay unchanged; Stop preview or any edit ends it.
    func previewPalette(_ candidate: Project, range: Range<Int>, samples: SampleLibrary) {
        guard !performance.contextActive else { message = "Return to editing before changing the source project."; return }
        finishTake()
        guard ensureAudio() else { return }
        guard candidate.id == project.id, candidate.revision == project.revision else { message = AssistantError.stale.localizedDescription; return }
        guard range.lowerBound >= 0, range.upperBound <= candidate.length, !range.isEmpty else { message = MusicError.invalidProject.localizedDescription; return }
        if !harmonyPreview { previewPosition = Int(audio.tick); previewPlaying = audio.playing; harmonyPreview = true }
        audio.audition(candidate, range: range, loop: true, samples: samples)
        syncMIDI()
    }

    /// Apply a palette candidate as one undoable change, staging its kit first.
    func applyPalette(_ candidate: Project, kit: [(pad: Int, asset: SampleAsset, data: Data)], projectID: UUID, revision: Int) async throws {
        func matches() -> Bool {
            project.id == projectID && project.revision == revision && projectChangeToken == nil &&
                !recording && !armed && !performance.contextActive
        }
        guard matches(), candidate.id == projectID, candidate.revision == revision else { throw SampleError.stale }
        try candidate.validate()
        endHarmonyPreview()
        let needed = Set(candidate.referencedSamples).subtracting(project.referencedSamples).subtracting(history.retainedSamples)
        let sounds = kit.filter { needed.contains($0.asset) }
        var prepared: [PreparedSampleBank] = []
        do {
            for sound in sounds {
                try Task.checkCancellation()
                guard matches() else { throw SampleError.stale }
                prepared.append(try await store.stageSample(sound.data, asset: sound.asset, projectID: projectID))
            }
            try Task.checkCancellation()
            guard matches() else { throw SampleError.stale }
            try withHistoryTransaction { history, project in try history.apply(&project) { $0 = candidate } }
        } catch {
            for bank in prepared { await store.removeStagedSample(bank.asset, projectID: projectID) }
            throw error
        }
        for bank in prepared { audio.samples.insert(bank) }
        audio.samples.retainOnly(history.retainedSamples.union(project.referencedSamples))
        mixerGesture = false
        sync()
        scheduleSave()
    }

    func listPersonalKits() async throws -> [PersonalKitSummary] { try await personalKits.list() }

    func deletePersonalKit(_ id: UUID) async throws { try await personalKits.delete(id) }

    private func kitTrack(_ id: UUID, projectID: UUID, revision: Int) throws -> Int {
        guard project.id == projectID, project.revision == revision, projectChangeToken == nil,
              !recording, !armed, !performance.contextActive,
              let index = project.tracks.firstIndex(where: { $0.id == id && $0.role == .drums }) else { throw SampleError.stale }
        return index
    }

    func savePersonalKit(name: String, trackID: UUID, projectID: UUID, revision: Int) async throws -> PersonalKitSummary {
        let index = try kitTrack(trackID, projectID: projectID, revision: revision)
        let kit = try await store.capturePersonalKit(name: name, track: project.tracks[index], projectID: projectID)
        try Task.checkCancellation()
        _ = try kitTrack(trackID, projectID: projectID, revision: revision)
        return try await personalKits.save(kit)
    }

    func loadPersonalKit(_ id: UUID, trackID: UUID, projectID: UUID, revision: Int) async throws {
        let kit = try await personalKits.load(id)
        let target = try kitTrack(trackID, projectID: projectID, revision: revision)
        let retained = history.retainedSamples.union(project.referencedSamples)
        let prepared = try await store.preparePersonalKit(kit, projectID: projectID, retaining: retained, replacing: project.tracks[target])
        do {
            try Task.checkCancellation()
            let index = try kitTrack(trackID, projectID: projectID, revision: revision)
            var candidate = project
            try prepared.apply(to: &candidate.tracks[index])
            guard candidate.tracks[index] != project.tracks[index] else { return }
            try candidate.validate()
            guard retained.union(candidate.referencedSamples).reduce(0, { $0 + $1.byteCount }) <= 128_000_000 else {
                throw SampleError.limit
            }
            try withHistoryTransaction { history, project in try history.apply(&project) { $0 = candidate } }
        } catch {
            for asset in prepared.staged { await store.removeStagedSample(asset, projectID: projectID) }
            throw error
        }
        for bank in prepared.banks { audio.samples.insert(bank) }
        audio.samples.retainOnly(history.retainedSamples.union(project.referencedSamples))
        mixerGesture = false
        sync()
        scheduleSave()
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
        do{try withHistoryTransaction{h,p in try h.apply(&p){$0.performanceTake=take}};performance.takeReady=nil;scheduleSave()}
        catch{performance.error=error.localizedDescription}
    }
    func leavePerformance()async{await performance.exit();pollPerformance();mixerGesture=false;audio.invalidateMusicSnapshot();sync();audio.seek(loopRange.lowerBound)}
    func commitPerformanceMix(){
        guard !performance.recording,!performance.replaying,let runtime=performance.runtimeProject,runtime.tracks.map(\.id)==project.tracks.map(\.id)else{return}
        do{try withHistoryTransaction{h,p in try h.apply(&p){p in for i in p.tracks.indices{p.tracks[i].gain=runtime.tracks[i].gain;p.tracks[i].pan=runtime.tracks[i].pan;p.tracks[i].mute=runtime.tracks[i].mute;p.tracks[i].solo=runtime.tracks[i].solo};p.master=runtime.master;p.masterFX=runtime.masterFX}};scheduleSave()}catch{performance.error=error.localizedDescription}
    }
    func applyMIDI(_ mapping:MIDIMapping,value:Double){
        guard !performance.replaying else{return}
        if performance.contextActive,mapping.target == .filter{performance.setEffects(filter:value);return}
        if performance.contextActive,mapping.target == .delay{performance.setEffects(delay:value);return}
        // I52: every mapped control goes through the same routing as the domain tests.
        mixerEdit{p in mapping.apply(value,to:&p)}
    }
    func saveCopy()async {
        guard let token=beginProjectChange()else{return}
        defer{endProjectChange(token)}
        var written:Project?
        do{
            let expected=try await prepareProjectChange(token,checkpoint:false)
            let working=project
            let escapingFailure=hasKnownLibraryFailure(working.id) || saveError != nil
            let copy=try await store.duplicate(working)
            written=copy
            try await projectChangeBoundary(token,expected:expected,stage:"candidate.saved")
            let verified=try await store.load(copy.id)
            let samples = escapingFailure ? try await store.loadSamples(for: verified) : SampleLibrary()
            try await projectChangeBoundary(token,expected:expected,stage:"copy.verified")
            copyGeneratedLoopPreference(from:working.id,to:verified.id)
            if escapingFailure{saveError=nil;activateProject(verified,savedRevision:verified.revision,samples:samples)}
            await refreshLibraryEntry(copy.id,validated:true)
            message="A copy has been saved."
        }catch{if let written{await retainUnopenedProject(written)}else{message=error.localizedDescription}}
    }
    /// An opt-in native probe uses genuine store operations and accepted MIDI
    /// callback edits. A continuation holds the production transition at an
    /// await boundary; no sleep, fabricated document, audio or PASS is supplied.
    func runProjectChangeQA()async {
        let arguments=ProcessInfo.processInfo.arguments
        if projectChangeQAEnabled,let index=arguments.firstIndex(of:"--portable-import-bars"),arguments.indices.contains(index+1),let bars=Int(arguments[index+1]),[8,16].contains(bars){await runPortableImportQA(bars:bars);return}
        guard projectChangeQAEnabled,projectChangeQAReport.isEmpty,projectChangeToken==nil else{return}
        var report:[String:Any]=["complete":false,"hardwareMIDIClaimed":false]
        var fixtureRestore:(URL,Data)?
        defer{if let (url,data)=fixtureRestore{try? data.write(to:url,options:.atomic)}}
        do{
            guard await create(name:"QA switch source",bpm:120,root:0,minor:false,bars:4,template:.starter)else{throw MusicError.invalidProject}
            var sourceID=project.id
            let target=try ProjectTemplates.make(name:"QA switch target",bpm:98,root:2,minor:true,bars:4,template:.starter)
            _ = try await store.save(target)
            await refreshLibraryEntry(target.id,validated:true)
            // Exercise the dedicated full music-edit path used by velocity.
            let velocity=project.patterns[1].drums[0].velocity
            coalescedMusicEdit{$0.patterns[1].drums[0].velocity=velocity+1};mixerGesture=false
            let working=project
            coalescedMusicEdit{$0.patterns[1].drums[0].velocity=128};mixerGesture=false
            let invalidVelocityRejected=project==working
            saveTask?.cancel()
            let root=store.root
            let manifest=root.appendingPathComponent(sourceID.uuidString).appendingPathExtension("grilla").appendingPathComponent("manifest.json")
            let originalBytes=try Data(contentsOf:manifest)
            guard var future=try JSONSerialization.jsonObject(with:originalBytes) as? [String:Any]else{throw MusicError.invalidProject}
            future["schemaVersion"]=Project.currentSchemaVersion+1
            let futureBytes=try JSONSerialization.data(withJSONObject:future,options:.sortedKeys)
            fixtureRestore=(manifest,originalBytes)
            try futureBytes.write(to:manifest,options:.atomic)
            await refreshLibraryEntry(sourceID)
            await openStored(sourceID)
            var retry:[String:Any]=["workingProjectRetained":project==working,"futureBytesRetained":try Data(contentsOf:manifest)==futureBytes,"canonicalLoadError":message ?? "","invalidVelocityRejected":invalidVelocityRejected,"acceptedVelocity":working.patterns[1].drums[0].velocity,"originalVelocity":velocity]
            await save()
            retry["blockedSaveRetainedFutureBytes"]=try Data(contentsOf:manifest)==futureBytes
            try originalBytes.write(to:manifest,options:.atomic)
            await openStored(sourceID)
            retry["validRetryKeptUnsavedWork"]=project==working
            retry["validRetryClearedLoadFailure"] = !hasKnownLibraryFailure(sourceID)
            await save()
            let persisted=try await store.load(sourceID)
            retry["savedVelocity"]=persisted.patterns[1].drums[0].velocity
            retry["savedWorkingProject"]=persisted==working
            // A healthy verified copy must actually let the user leave a bad
            // active package, without ever overwriting the original package.
            let workingBytes=try Data(contentsOf:manifest)
            guard var broken=try JSONSerialization.jsonObject(with:workingBytes) as? [String:Any]else{throw MusicError.invalidProject}
            broken["schemaVersion"]=Project.currentSchemaVersion+1
            let brokenBytes=try JSONSerialization.data(withJSONObject:broken,options:.sortedKeys)
            fixtureRestore=(manifest,workingBytes)
            try brokenBytes.write(to:manifest,options:.atomic)
            await refreshLibraryEntry(sourceID)
            await saveCopy()
            let escaped=project
            let escapedID=escaped.id
            retry["saveCopyEscapedToHealthyDocument"]=escapedID != sourceID && !hasKnownLibraryFailure(escapedID) && saveError==nil
            retry["saveCopyKeptWorkingMusic"]=escaped.patterns==working.patterns && escaped.tracks==working.tracks && escaped.bpm==working.bpm && escaped.master==working.master
            retry["saveCopyDidNotOverwriteBadSource"]=try Data(contentsOf:manifest)==brokenBytes
            await openStored(target.id)
            retry["escapedCopyCanOpenAnotherProject"]=project.id==target.id
            await openStored(escapedID)
            sourceID=project.id
            report["activeRetry"]=retry

            var cases:[[String:Any]]=[]
            for (stage,value) in [("checkpoint.saved",-9.0),("stored.loaded",-12.0),("candidate.saved",-15.0)] {
                let idsBefore=Set(try await store.listSummaries().map(\.id))
                projectChangeQAGateObservation=[:]
                projectChangeQAInterleave={ [weak self] reached in
                    guard let self,reached==stage,self.projectChangeQAGateObservation.isEmpty else{return}
                    await withCheckedContinuation{continuation in
                        Task { @MainActor in
                            let before=self.projectIdentity
                            let mapping=MIDIMapping(sourceID:1,channel:0,controller:7,target:.masterGain)
                            self.mixerGesture=false
                            self.applyMIDI(mapping,value:value)
                            self.mixerGesture=false
                            let accepted=self.projectIdentity
                            let busyResult=await self.openExample()
                            self.projectChangeQAGateObservation=["stage":stage,"beforeRevision":before.revision,"acceptedRevision":accepted.revision,"acceptedSourceID":accepted.id.uuidString,"acceptedMaster":self.project.master,"concurrentChangeRejected":!busyResult]
                            continuation.resume()
                        }
                    }
                }
                var createResult:Bool?
                if stage=="candidate.saved"{createResult=await create(name:"QA unopened candidate",bpm:112,root:5,minor:false,bars:4,template:.starter)}
                else{await openStored(target.id)}
                projectChangeQAInterleave=nil
                var observed=projectChangeQAGateObservation
                observed["activeID"]=project.id.uuidString;observed["activeRevision"]=project.revision;observed["masterAfterAbort"]=project.master
                observed["sourceRetained"]=project.id==sourceID
                observed["retryReason"]=message ?? ""
                let idsAfter=Set(try await store.listSummaries().map(\.id))
                let added=idsAfter.subtracting(idsBefore)
                observed["newDocumentCount"]=added.count
                if let createResult{
                    observed["createResult"]=createResult
                    observed["retainedCopyVisible"]=added.count==1 && entries.contains{added.contains($0.id) && $0.summary?.name=="QA unopened candidate"}
                    observed["returnedToProjects"]=sheet == .projects
                }
                await save()
                let canonical=try await store.load(sourceID)
                observed["savedMaster"]=canonical.master;observed["savedRevision"]=canonical.revision
                cases.append(observed)
                message=nil;sheet=nil
            }
            report["interleavings"]=cases

        }catch{report["error"]=error.localizedDescription}
        projectChangeQAInterleave=nil;message=nil;sheet=nil
        report["complete"]=true
        if let data=try? JSONSerialization.data(withJSONObject:report,options:.sortedKeys){projectChangeQAReport=String(decoding:data,as:UTF8.self)}
    }
    /// An opt-in fixture goes through the real portable encoder and production
    /// import transaction. XCTest separately relaunches this actual store and
    /// observes rendered ticks/output; this method supplies no success result.
    private func runPortableImportQA(bars:Int)async {
        guard projectChangeQAEnabled,projectChangeQAReport.isEmpty,projectChangeToken==nil else{return}
        var report:[String:Any]=["kind":"portableImport","requestedBars":bars,"invocation":"Session.importProject","physicalAudioClaimed":false]
        let file=FileManager.default.temporaryDirectory.appendingPathComponent("Portable-listening-"+UUID().uuidString).appendingPathExtension("grillapack")
        defer{try? FileManager.default.removeItem(at:file)}
        do{
            // Reproduce the former listening context: the current document is
            // explicitly set to four bars, regardless of the imported length.
            setLoop(bars:4,enabled:true)
            let original=project
            let originalPreference=UserDefaults.standard.dictionary(forKey:generatedLoopKey(original.id)) ?? [:]
            let blank=Project(name:"Portable listening "+String(bars))
            var fixture=try SketchComposer.compose(blank,plan:SketchPlan(style:.house,bpm:240,root:2,minor:false,bars:bars,seed:42),scope:blank.sections[0].id)
            fixture.sections=[MusicDomain.Section(name:"Verse",length:4*barTicks),MusicDomain.Section(name:"Chorus",start:4*barTicks,length:(bars-4)*barTicks)]
            try fixture.validate()
            let bytes=try PortableProject.data(fixture)
            try bytes.write(to:file,options:.atomic)
            report["beforeLoopBars"]=loopBars
            await importProject(file)
            guard project.id != original.id,project.id != fixture.id,project.length==fixture.length else{throw MusicError.invalidProject}
            let canonical=try await store.load(project.id)
            let prior=try await store.load(original.id)
            report["importedID"]=project.id.uuidString;report["archiveID"]=fixture.id.uuidString
            report["revision"]=project.revision;report["sectionCount"]=project.sections.count
            report["firstSectionBars"]=project.sections[0].length/barTicks
            report["totalBars"]=project.length/barTicks;report["loopBars"]=loopBars;report["loopEnabled"]=loop
            report["rangeStart"]=loopRange.lowerBound;report["rangeEnd"]=loopRange.upperBound;report["rangeCount"]=loopRange.count
            report["importedMusicMatchesArchive"]=canonical.patterns==fixture.patterns && canonical.tracks==fixture.tracks && canonical.sections==fixture.sections
            report["sourceMusicUnchanged"]=prior.patterns==original.patterns && prior.tracks==original.tracks && prior.sections==original.sections
            let after=UserDefaults.standard.dictionary(forKey:generatedLoopKey(original.id)) ?? [:]
            report["sourcePreferenceUnchanged"]=NSDictionary(dictionary:originalPreference).isEqual(to:after)
            report["archiveBytesUnchanged"]=try Data(contentsOf:file)==bytes
            report["compileNoteCount"]=Compiler.notes(canonical).count
        }catch{report["error"]=error.localizedDescription}
        message=nil;sheet=nil;report["complete"]=true
        if let data=try? JSONSerialization.data(withJSONObject:report,options:.sortedKeys){projectChangeQAReport=String(decoding:data,as:UTF8.self)}
    }
    /// Emergency MIDI stop must complete even if the current audio route is no
    /// longer delivering render callbacks to acknowledge a queued stop command.
    func panicMIDI(){interrupt();_ = ensureAudio()}
    func interrupt(reason:String="unspecified") {
        runtimeTrace("interrupt.before reason=\(reason)");defer{runtimeTrace("interrupt.after reason=\(reason)")}
        stopMicrophone?();microphoneOwner=nil;stopMicrophone=nil;if performance.contextActive{performance.finalizeBeforeReset();pollPerformance()};harmonyPreview=false;previewingNewTrack=false;draftEndTick=nil;finishTake();midi.suspend();midi.retry();audio.reset();Task{await save()}
    }
}
