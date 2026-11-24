import SwiftUI

/// The project is not interactive until its stored document and audio graph
/// have finished bootstrapping. A launch surface never adds an artificial delay.
struct AppStartView: View {
    @Bindable var session: Session
    @AppStorage private var welcomeCompleted: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showWelcome = false

    private var splashPreview: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--uitesting") && arguments.contains("--splash-preview")
    }

    private var previewReducesMotion: Bool {
        splashPreview && ProcessInfo.processInfo.arguments.contains("--splash-reduce-motion")
    }

    init(session: Session) {
        self.session = session
        let testing = ProcessInfo.processInfo.arguments.contains("--uitesting")
        _welcomeCompleted = AppStorage(wrappedValue: false, testing ? "studio.qa.welcomeCompleted" : "studio.welcomeCompleted")
    }

    var body: some View {
        Group {
            if session.ready && !splashPreview {
                StudioView(session: session)
                    .transition(.opacity)
            } else {
                LoadingSplashView(bootstrapReady: session.ready, qaPreview: splashPreview,
                                  qaReduceMotion: previewReducesMotion)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: session.ready)
        .onChange(of: session.ready, initial: true) { _, ready in
            guard ready, !splashPreview else { return }
            // Keep first-launch guidance from covering bootstrap errors and
            // recovery controls. The next successful launch can show it.
            guard session.message == nil, session.audio.error == nil else { return }
            let arguments = ProcessInfo.processInfo.arguments
            let testing = arguments.contains("--uitesting")
            if testing && arguments.contains("--show-welcome") { welcomeCompleted = false }
            let respectsWelcome = !testing || arguments.contains("--respect-welcome") || arguments.contains("--show-welcome")
            showWelcome = !welcomeCompleted && respectsWelcome
        }
        .sheet(isPresented: $showWelcome, onDismiss: { welcomeCompleted = true }) {
            GettingStartedView(close: {
                welcomeCompleted = true
                showWelcome = false
            }, tour: {
                // U11: the demo song with the five-step tour.
                welcomeCompleted = true
                showWelcome = false
                Task { await session.startTour() }
            })
            .presentationDragIndicator(.visible)
            .presentationBackground(Color.panel)
        }
    }
}

/// The same surface is used during real bootstrap and in an explicitly marked
/// QA visual preview. Neither path changes bootstrap work or invents progress.
private struct LoadingSplashView: View {
    let bootstrapReady: Bool
    let qaPreview: Bool
    let qaReduceMotion: Bool
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var scanning = false

    private var reduceMotion: Bool { systemReduceMotion || (qaPreview && qaReduceMotion) }

    var body: some View {
        GeometryReader { geometry in
            let fullHeight = geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom
            let centerY = fullHeight / 2 - geometry.safeAreaInsets.top - 24
            let compact = geometry.size.height < 430
            ZStack {
                Color.ink.ignoresSafeArea()
                splashGrid
                    .frame(width: 280, height: 280)
                    .position(x: geometry.size.width / 2, y: centerY)
                VStack(spacing: 22) {
                    SplashStudioMark(scanning: scanning, reduceMotion: reduceMotion)
                        .frame(width: 96, height: 96)
                    Text(verbatim: "La Grilla")
                        .font(StudioTypography.display)
                        .foregroundStyle(Color.studioText)
                        .lineLimit(1).minimumScaleFactor(0.55)
                        .frame(maxWidth: 280).background(Color.ink)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("splash.brand")
                }
                .frame(maxWidth: max(0, geometry.size.width - 48))
                .position(x: geometry.size.width / 2, y: centerY)
                VStack {
                    Spacer(minLength: 0)
                    VStack(spacing: 16) {
                        if !compact && !typeSize.isAccessibilitySize {
                            Text("Your idea. Your groove. Your track.")
                                .font(.subheadline).foregroundStyle(Color.muted)
                                .multilineTextAlignment(.center)
                        }
                        loadingActivity
                        Text("Opening your studio…")
                            .font(.footnote).foregroundStyle(Color.muted)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("splash.status")
                            .accessibilityValue(Text(verbatim: diagnostics))
                    }
                    .frame(maxWidth: 300)
                    .padding(.horizontal, 24)
                    .padding(.bottom, compact ? 16 : 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("studio.starting")
        }
        .onAppear { scanning = !reduceMotion }
        .onChange(of: reduceMotion) { _, value in scanning = !value }
        .onDisappear { scanning = false }
    }

    private var splashGrid: some View {
        Canvas { context, size in
            var path = Path()
            for index in 0...6 {
                let offset = CGFloat(index) * 40 + 20
                path.move(to: CGPoint(x: offset, y: 0))
                path.addLine(to: CGPoint(x: offset, y: size.height))
                path.move(to: CGPoint(x: 0, y: offset))
                path.addLine(to: CGPoint(x: size.width, y: offset))
            }
            context.stroke(path, with: .color(Color("LaunchGrid")), lineWidth: 0.5)
        }.accessibilityHidden(true).allowsHitTesting(false)
    }

    private var loadingActivity: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.outline.opacity(0.45))
            Capsule().fill(Color.mint).frame(width: 24)
                .offset(x: scanning && !reduceMotion ? 48 : 0)
        }
        .frame(width: 72, height: 3)
        .animation(reduceMotion ? nil : .easeInOut(duration: 1.25).repeatForever(autoreverses: true), value: scanning)
        .accessibilityHidden(true)
    }

    private var diagnostics: String {
        guard qaPreview else { return "" }
        let state = SplashPreviewState(qaPreview: true, bootstrapReady: bootstrapReady,
                                       appearance: colorScheme == .dark ? "dark" : "light",
                                       reduceMotion: reduceMotion,
                                       systemReduceMotion: systemReduceMotion,
                                       qaReduceMotionOverride: qaPreview && qaReduceMotion,
                                       largeType: typeSize.isAccessibilitySize)
        guard let data = try? JSONEncoder().encode(state) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    private struct SplashPreviewState: Encodable {
        let qaPreview: Bool
        let bootstrapReady: Bool
        let appearance: String
        let reduceMotion: Bool
        let systemReduceMotion: Bool
        let qaReduceMotionOverride: Bool
        let largeType: Bool
    }
}

private struct SplashStudioMark: View {
    let scanning: Bool
    let reduceMotion: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                let rows: [[(CGFloat, CGFloat, Color)]] = [
                    [(8, 28, .studioText), (47, 27, .studioText), (79, 11, .harmony)],
                    [(12, 19, .studioText), (47, 13, .harmony), (64, 26, .studioText)],
                    [(8, 28, .studioText), (47, 27, .studioText), (79, 11, .harmony)]
                ]
                for row in rows.indices {
                    for (x, width, color) in rows[row] {
                        context.fill(Path(CGRect(x: x, y: CGFloat(row) * 23 + 22, width: width, height: 8)), with: .color(color))
                    }
                }
            }
            Rectangle().fill(Color.mint).frame(width: 6, height: 80)
                .offset(x: scanning && !reduceMotion ? 50 : 38, y: 8)
                .animation(reduceMotion ? nil : .easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: scanning)
        }.accessibilityHidden(true).allowsHitTesting(false)
    }
}
