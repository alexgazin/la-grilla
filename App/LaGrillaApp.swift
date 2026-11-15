import SwiftUI
import AVFoundation
import MusicDomain
@main struct LaGrillaApp: App {
    @State private var session = Session()
    @AppStorage("studio.appearance") private var appearance=0
    @Environment(\.scenePhase) private var phase
    var body: some Scene {WindowGroup {StudioView(session:session).preferredColorScheme(appearance==1 ? .light:appearance==2 ? .dark:nil).tint(.mint).task {
        if ProcessInfo.processInfo.arguments.contains("--uitesting"){appearance=2}
        await session.bootstrap()
        if let index=ProcessInfo.processInfo.arguments.firstIndex(of:"--screen"),ProcessInfo.processInfo.arguments.count>index+1 {
            let target=ProcessInfo.processInfo.arguments[index+1]
            if target=="midi" || target=="midi-mapped" {
                if let source=session.midi.createFixture(){session.edit{p in var settings=MIDISettings();settings.enabled=true;settings.inputIDs=[source];settings.outputID=session.midi.fixtureOutputID;settings.trackID=p.tracks[0].id;p.midi=settings}}
                session.sheet = .midiDevices;session.togglePlay()
                if target=="midi-mapped"{session.midi.learning = .filter;try? await Task.sleep(for:.milliseconds(500));session.midi.sendFixture()}
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
            };if target.hasPrefix("voice"){session.sheet = .voice};if target.hasPrefix("assistant"){session.sheet = .assistant};if target.hasPrefix("harmony"){session.sheet = .harmony};if target=="jam"{session.tab=1};if target=="mixer"{session.tab=2};if target=="projects"{session.sheet = .projects};if target.hasPrefix("export"){session.exportPreset=target=="export-wav" ? "wav":target=="export-stems" ? "stems":"midi";session.sheet = .export}
        }
    }.onOpenURL{url in Task{await session.importProject(url)}}
    .onChange(of:phase){_,value in if value != .active{session.finishTake();Task{await session.save()}}}
    .onReceive(NotificationCenter.default.publisher(for:AVAudioSession.interruptionNotification).receive(on:RunLoop.main)){_ in session.interrupt()}
    .onReceive(NotificationCenter.default.publisher(for:AVAudioSession.routeChangeNotification).receive(on:RunLoop.main)){n in
        if let raw=n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt, let reason=AVAudioSession.RouteChangeReason(rawValue:raw), reason == .oldDeviceUnavailable || reason == .newDeviceAvailable {session.interrupt()}
    }
    .onReceive(NotificationCenter.default.publisher(for:AVAudioSession.mediaServicesWereResetNotification).receive(on:RunLoop.main)){_ in session.interrupt()}
    }}
}
