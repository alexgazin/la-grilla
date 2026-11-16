import SwiftUI

/// The project is not interactive until its stored document and audio graph
/// have finished bootstrapping. A launch surface never adds an artificial delay.
struct AppStartView: View {
    @Bindable var session: Session
    @AppStorage private var welcomeCompleted: Bool
    @State private var showWelcome = false

    init(session: Session) {
        self.session = session
        let testing = ProcessInfo.processInfo.arguments.contains("--uitesting")
        _welcomeCompleted = AppStorage(wrappedValue: false, testing ? "studio.qa.welcomeCompleted" : "studio.welcomeCompleted")
    }

    var body: some View {
        Group {
            if session.ready {
                StudioView(session: session)
            } else {
                ZStack {
                    Color.ink
                    Image("LaunchMark").resizable().scaledToFit().frame(width: 80, height: 80).accessibilityHidden(true)
                    ProgressView("Opening your studio…").tint(.mint).font(.callout).foregroundStyle(Color.muted)
                        .frame(maxWidth: 280).multilineTextAlignment(.center).offset(y: 96)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .accessibilityIdentifier("studio.starting")
            }
        }
        .onChange(of: session.ready, initial: true) { _, ready in
            guard ready else { return }
            let arguments = ProcessInfo.processInfo.arguments
            let testing = arguments.contains("--uitesting")
            if testing && arguments.contains("--show-welcome") { welcomeCompleted = false }
            let respectsWelcome = !testing || arguments.contains("--respect-welcome") || arguments.contains("--show-welcome")
            showWelcome = !welcomeCompleted && respectsWelcome
        }
        .sheet(isPresented: $showWelcome, onDismiss: { welcomeCompleted = true }) {
            GettingStartedView {
                welcomeCompleted = true
                showWelcome = false
            }
            .presentationDragIndicator(.visible)
            .presentationBackground(Color.panel)
        }
    }
}
