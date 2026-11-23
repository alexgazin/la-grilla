import SwiftUI

/// U5 · The one "Listen → Apply" pattern: choose what to hear, one Play/Stop button,
/// and a promise that nothing reaches the project before Apply. Switching the source
/// while it plays switches the sound. Identifiers: `<screen>.listen.N`, `<screen>.play`.
struct AuditionBar<Source: Hashable>: View {
    let screen: String
    @Binding var source: Source
    let sources: [(Source, LocalizedStringKey)]
    let playing: Bool
    var enabled = true
    let caption: LocalizedStringKey
    let play: () -> Void
    let stop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LISTEN").font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(Color.muted)
            if sources.count > 1 {
                StudioSegments(title: "Listen to", selection: $source, options: sources, identifier: "\(screen).listen")
            }
            Button { playing ? stop() : play() } label: {
                Label(LocalizedStringKey(playing ? "Stop" : "Play"), systemImage: playing ? "stop.fill" : "play.fill")
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(StudioActionStyle(color: playing ? .record : .mint))
            .disabled(!enabled && !playing)
            .accessibilityIdentifier("\(screen).play")
            Text(caption).font(.caption).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Color.panel, in: RoundedRectangle(cornerRadius: Luz.Radius.card, style: .continuous))
        .onChange(of: source) { _, _ in if playing { stop(); play() } }
    }
}
