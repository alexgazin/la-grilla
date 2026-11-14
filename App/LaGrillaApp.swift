import SwiftUI
import AVFoundation
@main struct LaGrillaApp: App {
    @State private var session = Session()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {WindowGroup {StudioView(session:session).preferredColorScheme(.dark).tint(.mint).task {
        await session.bootstrap()
        if let index=ProcessInfo.processInfo.arguments.firstIndex(of:"--screen"),ProcessInfo.processInfo.arguments.count>index+1 {
            let target=ProcessInfo.processInfo.arguments[index+1]
            if target=="jam"{session.tab=1};if target=="mixer"{session.tab=2};if target=="projects"{session.sheet = .projects};if target.hasPrefix("export"){session.exportPreset=target=="export-wav" ? "wav":target=="export-stems" ? "stems":"midi";session.sheet = .export}
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
