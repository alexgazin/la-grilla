import SwiftUI
import AVFoundation
import MusicDomain
@main struct LaGrillaApp: App {
    @State private var session = Session()
    @AppStorage("studio.appearance") private var appearance=0
    @Environment(\.scenePhase) private var phase
    init(){LaunchClock.mark();InterfacePreferences.prepareForTesting()}
    var body: some Scene {WindowGroup {AppStartView(session:session).modifier(StudioDensityModifier()).modifier(StudioQATypeSize()).preferredColorScheme(appearance==1 ? .light:appearance==2 ? .dark:nil).tint(.mint).task {
        if ProcessInfo.processInfo.arguments.contains("--uitesting") && !ProcessInfo.processInfo.arguments.contains("--respect-appearance"){appearance=2}
        if let index=ProcessInfo.processInfo.arguments.firstIndex(of:"--appearance"),ProcessInfo.processInfo.arguments.count>index+1{appearance=ProcessInfo.processInfo.arguments[index+1]=="light" ? 1:2}
        await session.bootstrap()
        if !ProcessInfo.processInfo.arguments.contains("--uitesting") { LocalDiagnostics.shared.start() }
        // UI fixture: behave as if Siri or Shortcuts had just run an intent.
        if ProcessInfo.processInfo.arguments.contains("--uitesting"), let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--launch-intent"),
           ProcessInfo.processInfo.arguments.count > index + 1, let kind = LaunchRequest.Kind(rawValue: ProcessInfo.processInfo.arguments[index + 1]) {
            LaunchRequest.post(LaunchRequest(kind: kind, bpm: kind == .newBeat ? 92 : nil))
        }
        if let request = LaunchRequest.take() { await session.handleLaunch(request) }
        Task { await ProjectSpotlight.refresh() }
        // I55: a connected game controller plays the pads.
        GamepadPads.shared.attach(session)
        // U70: once after an update, show what is new in this build.
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        let lastShown = UserDefaults.standard.string(forKey: "whatsNew.lastBuild")
        if !ProcessInfo.processInfo.arguments.contains("--uitesting"), WhatsNew.shouldShow(lastShownBuild: lastShown, currentBuild: build), session.sheet == nil { session.sheet = .whatsNew }
        UserDefaults.standard.set(build, forKey: "whatsNew.lastBuild")
        if let index=ProcessInfo.processInfo.arguments.firstIndex(of:"--screen"),ProcessInfo.processInfo.arguments.count>index+1 {
            let target=ProcessInfo.processInfo.arguments[index+1]
            if target=="midi" || target=="midi-mapped" {
                session.prepareMIDIFixture()
                session.sheet = .midiDevices;session.togglePlay()
                if target=="midi-mapped"{session.midi.learning = .filter;try? await Task.sleep(for:.milliseconds(500));session.midi.sendFixture()}
            }
            if target=="audio-tracks"{await session.installAudioFixture();session.sheet = .audioTracks}
            if target=="assistant-song-edit", let demo=try? SongEditDemo.project(name:NSLocalizedString("Two choruses",comment:"Song edit demo project")) {
                await session.open(demo)
            }
            // U12 fixtures: a blank song to check the empty-screen hints.
            if target=="empty-jam" || target=="empty-notes" {
                await session.open(Project(name:"Blank"))
                if target=="empty-jam"{session.tab=1}
                else{session.edit{try $0.addMelody()};session.sheet = .notes}
            }
            if target.hasPrefix("perform") {
                session.edit{p in try p.duplicateSection(p.sections[0].id,name:"Chorus")}
                session.sheet = .perform
                if target != "perform" {
                    session.startPerformance(record:true)
                    try? await Task.sleep(for:.milliseconds(900))
                    session.performance.queueSection(session.project.sections[1].id)
                    session.performance.setEffects(filter:-0.35,delay:0.2)
                    session.audio.pad(0)
                    try? await Task.sleep(for:.milliseconds(2500))
                    session.performance.stopRecording()
                    try? await Task.sleep(for:.milliseconds(200))
                    session.pollPerformance()
                    if target=="perform-export",let take=session.project.performanceTake{session.exportTake=take;session.exportPreset="wav";session.sheet = .export}
                }
            }
            if target=="notes" || target=="notes-mixer"{
                session.addMelody();if let id=session.noteTrackID,let t=session.project.tracks.first(where:{$0.id==id}),let pid=t.clips.first?.patternID{session.edit{p in if let i=p.patterns.firstIndex(where:{$0.id==pid}){p.patterns[i].notes=[NoteEvent(tick:0,duration:960,pitch:79),NoteEvent(tick:960,duration:480,pitch:76),NoteEvent(tick:1920,duration:1440,pitch:72),NoteEvent(tick:3840,duration:960,pitch:76),NoteEvent(tick:4800,duration:1920,pitch:79)]}}}
                if target=="notes"{session.sheet = .notes}else{for _ in 0..<4{session.addMelody()};session.tab=2}
            };if target.hasPrefix("voice"){session.sheet = .voice};if target.hasPrefix("assistant"){session.sheet = .assistant};if target.hasPrefix("harmony"){session.sheet = .harmony};if target=="settings"{session.sheet = .settings};if target=="jam"{session.tab=1};if target=="mixer"{session.tab=2};if target=="projects"{session.sheet = .projects};if target.hasPrefix("export"){session.exportPreset=target=="export-wav" ? "wav":target=="export-stems" ? "stems":"midi";session.sheet = .export}
        }
    }.onOpenURL{url in
        // 54: a remix link (lagrilla://remix#… or the remix page) opens as a new project with credit.
        if url.scheme?.lowercased()==RemixLink.scheme || RemixLink.payload(from:url) != nil{Task{await session.openRemix(url)}}
        else{Task{await session.importProject(url)}}
    }
    .onReceive(NotificationCenter.default.publisher(for:.laGrillaLaunchRequest).receive(on:RunLoop.main)){_ in if let request=LaunchRequest.take(){Task{await session.handleLaunch(request)}}}
    .onChange(of:phase){_,value in session.sceneChanged(value)}
    .onReceive(NotificationCenter.default.publisher(for:AVAudioSession.interruptionNotification).receive(on:RunLoop.main)){n in
        let type=n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
        let options=n.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
        session.runtimeTrace("notification.interruption type=\(type.map(String.init) ?? "none") options=\(options.map(String.init) ?? "none")")
        session.interrupt(reason:"interruption type=\(type.map(String.init) ?? "none")")
    }
    .onReceive(NotificationCenter.default.publisher(for:AVAudioSession.routeChangeNotification).receive(on:RunLoop.main)){n in
        let raw=n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
        session.runtimeTrace("notification.route reason=\(raw.map(String.init) ?? "none")")
        if let raw, let reason=AVAudioSession.RouteChangeReason(rawValue:raw), reason == .oldDeviceUnavailable || reason == .newDeviceAvailable {session.interrupt(reason:"route reason=\(raw)")}
    }
    .onReceive(NotificationCenter.default.publisher(for:AVAudioSession.mediaServicesWereResetNotification).receive(on:RunLoop.main)){_ in session.interrupt(reason:"media services reset")}
    }}
}
