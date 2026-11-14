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
    var take: [DrumEvent] = []; var takePattern: UUID?; var takeStart = 0; var takeLength = 0
    var savedRevision = -1; var saving = false; var saveError: String?; var message: String?
    var entries: [ProjectStore.Entry] = []; var sheet: Sheet?; var shareURL: URL?; var exportedURL: URL?
    var ready = false; var saveTask: Task<Void,Never>?
    let store: ProjectStore
    enum Sheet: String, Identifiable {case projects, newProject, export, settings, bass, sections; var id: String { rawValue }}
    init() {
        let root = ProcessInfo.processInfo.arguments.contains("--uitesting") ? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) : FileManager.default.urls(for: .documentDirectory,in:.userDomainMask)[0].appendingPathComponent("Projects")
        store = ProjectStore(root: root)
    }
    var section: MusicDomain.Section { project.sections.first(where: {$0.id == selectedSection}) ?? project.sections[0] }
    var loopRange: Range<Int> { let start = section.start; return loop ? start..<min(project.length,start + loopBars*barTicks) : 0..<project.length }
    var pending: Bool { audio.playing && audio.appliedRevision != project.revision }
    func bootstrap() async {
        guard !ready else { return }; ready = true
        do {
            entries = try await store.list()
            if let first = entries.first(where: {$0.project != nil})?.project { project = first }
            else if entries.isEmpty {try await store.save(project); entries = try await store.list()}
            selectedSection = project.sections[0].id
            try audio.prepare(); sync(); savedRevision = project.revision
        } catch { message = error.localizedDescription }
    }
    func ensureAudio() -> Bool { if audio.isPrepared {return true}; do {try audio.prepare(); sync(); return true} catch {audio.error = error.localizedDescription; return false} }
    func sync() { audio.submit(project,loop:loop,range:loopRange); audio.metronome(metronome) }
    func edit(_ change: (inout Project) throws -> Void) {
        guard !recording && !armed else {message = "Finish the drum take before editing the project.";return}
        do {try history.apply(&project,change); sync(); scheduleSave()} catch {message = error.localizedDescription}
    }
    var mixerGesture = false
    func mixerEdit(_ change: (inout Project) throws -> Void) {
        do { try history.apply(&project, coalescing: mixerGesture, change); mixerGesture = true; sync(); scheduleSave() }
        catch { message = error.localizedDescription }
    }
    func undo() {guard !recording && !armed else {return}; history.undo(&project); sync();scheduleSave()}
    func redo() {guard !recording && !armed else {return}; history.redo(&project); sync();scheduleSave()}
    func scheduleSave() {saveTask?.cancel();saveTask = Task {try? await Task.sleep(for:.milliseconds(700));guard !Task.isCancelled else{return};await save()} }
    func save() async {saving = true;let snapshot = project;do {try await store.save(snapshot);savedRevision = snapshot.revision; saveError = nil;entries = try await store.list()}catch{saveError=error.localizedDescription};saving=false}
    func togglePlay() {
        if audio.playing {finishTake();audio.stop()}else if ensureAudio(){if audio.tick>=Double(loopRange.upperBound){audio.seek(loopRange.lowerBound)};audio.play()}
    }
    func rewind() {finishTake();audio.stop();audio.seek(loopRange.lowerBound)}
    func record() {
        if recording || armed {finishTake();return}
        guard ensureAudio(), let t = project.tracks.first(where: {$0.role == .drums}),let clip=t.clips.first(where: {$0.start<=section.start && $0.start+$0.length>section.start}),let p=project.patterns.first(where: {$0.id==clip.patternID}) else{return}
        take = [];takePattern=p.id;takeStart=clip.start;takeLength=p.length
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
        recording=active; replaceNextPass=false; take=[]
    }
    func hit(_ pad: Int) {
        guard ensureAudio() else{return}; audio.pad(pad);pollRecording()
        if recording {
            let local=(Int(audio.tick)-takeStart+takeLength)%takeLength
            let e=DrumEvent(tick:quantize.tick(local,length:takeLength),pad:pad)
            take.append(e)
        }
    }
    func finishTake() {
        let hadTake=recording;armed=false;recording=false
        guard hadTake,let id=takePattern else {take=[];return}
        _ = id
        commitPass()
        take=[];Task{await save()}
    }
    func setLoop(bars: Int? = nil, enabled: Bool? = nil) {guard !recording && !armed else{message="Finish the take before changing the loop.";return};if let bars{loopBars=bars};if let enabled{loop=enabled};sync()}
    func select(_ section: MusicDomain.Section) {guard !recording && !armed else{return};selectedSection=section.id;sync();if !audio.playing{audio.seek(section.start)}}
    func open(_ p: Project) async {
        finishTake();audio.stop();await save();project=p;history=History();selectedSection=p.sections[0].id;savedRevision=p.revision;audio.seek(0);sync();sheet=nil
    }
    func create(name: String,bpm: Double,root: Int,minor: Bool,bars: Int) async {
        var p=Project(name:name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? "Untitled" : name,bars:bars);p.bpm=bpm;p.keyRoot=root;p.minor=minor
        await open(p);await save()
    }
    func duplicateProject(_ p: Project) async {var copy=p;copy.id=UUID();copy.name += " copy";copy.modified=Date();do{try await store.save(copy);entries=try await store.list()}catch{message=error.localizedDescription}}
    func delete(_ id: UUID) async {do{try await store.delete(id);entries=try await store.list()}catch{message=error.localizedDescription}}
    func recover(_ id: UUID) async {do{let p=try await store.load(id,backup:true);await open(p);await save();message="Recovered the last working copy."}catch{message=error.localizedDescription}}
    func export(sectionOnly: Bool) async {
        let snapshot=project;let range=sectionOnly ? section.start..<section.start+section.length : 0..<snapshot.length
        do {let data=try MIDIExporter.data(snapshot,range:range);let name=snapshot.name.replacingOccurrences(of:"/",with:"-");let url=FileManager.default.temporaryDirectory.appendingPathComponent(name).appendingPathExtension("mid");try data.write(to:url,options:.atomic);exportedURL=url;sheet=nil}catch{message=error.localizedDescription}
    }
    func saveCopy() async {
        var copy=project; copy.id=UUID(); copy.name += " copy"
        do {try await store.save(copy); message="A copy has been saved.";entries=try await store.list()}catch{message=error.localizedDescription}
    }
    func interrupt() {finishTake();audio.reset();Task{await save()}}
}
