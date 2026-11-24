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

/// U5 · The same "Listen → Apply → Discard" block where a proposal is compared with the song as it
/// is (assistant, phrase edits): A plays the original, B the proposal, Stop while playing, then
/// Apply (one Undo) or Discard. Nothing reaches the song before Apply.
struct ABAuditionBar: View {
    struct Identifiers { var a = "assistant.a", b = "assistant.b", stop = "assistant.stop-preview", apply = "assistant.apply", discard = "assistant.discard" }
    var identifiers = Identifiers()
    var original: LocalizedStringKey = "A · Original"
    var proposal: LocalizedStringKey = "B · Proposal"
    var applyTitle: LocalizedStringKey = "Apply proposal"
    /// nil when silent; false while A plays, true while B plays.
    let playing: Bool?
    var enabled = true
    var caption: Text?
    let playA: () -> Void
    let playB: () -> Void
    let stop: () -> Void
    let apply: () -> Void
    var discard: (() -> Void)?
    var captionIdentifier: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LISTEN").font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(Color.muted)
            HStack(spacing: 10) {
                side(original, active: playing == false, identifier: identifiers.a, action: playA)
                side(proposal, active: playing == true, identifier: identifiers.b, action: playB)
            }
            if let caption { caption.font(.caption).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier(captionIdentifier ?? "") }
            if playing != nil {
                Button("Stop preview", action: stop).frame(minHeight: 44).accessibilityIdentifier(identifiers.stop)
            }
            Button(action: apply) { Text(applyTitle) }.buttonStyle(StudioActionStyle()).disabled(!enabled).accessibilityIdentifier(identifiers.apply)
            if let discard {
                Button(action: discard) { Text("Discard").frame(maxWidth: .infinity, minHeight: 44) }
                    .buttonStyle(StudioQuietButtonStyle()).foregroundStyle(Color.muted).accessibilityIdentifier(identifiers.discard)
            }
            Text("Nothing changes in the song until you apply. One Undo restores the whole change.").font(.caption).foregroundStyle(Color.muted)
        }
        .padding(14)
        .background(Color.panel, in: RoundedRectangle(cornerRadius: Luz.Radius.card, style: .continuous))
    }

    private func side(_ title: LocalizedStringKey, active: Bool, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label { Text(title) } icon: { Image(systemName: active ? "speaker.wave.2.fill" : "play.fill") }
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(active ? Color.mint.opacity(0.2) : Color.raised, in: RoundedRectangle(cornerRadius: Luz.Radius.cell, style: .continuous))
        }
        .buttonStyle(StudioQuietButtonStyle())
        .disabled(!enabled)
        .accessibilityAddTraits(active ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}

/// U5 · The frame around a screen's own listening controls (the track builder's sketch): the same
/// "LISTEN" heading and the promise that nothing is created or changed until the main action.
struct AuditionPanel<Content: View>: View {
    let caption: LocalizedStringKey
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LISTEN").font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(Color.muted)
            content
            Text(caption).font(.caption).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Color.panel, in: RoundedRectangle(cornerRadius: Luz.Radius.card, style: .continuous))
    }
}


/// U69 · Hints under a text field as small chips; a tap puts the hint into the field.
struct QueryHintsRow: View {
    let hints: [String]
    let identifier: String
    let pick: (String) -> Void
    var body: some View {
        if !hints.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(hints.enumerated()), id: \.offset) { index, hint in
                        Button { pick(hint) } label: {
                            Text(verbatim: hint).font(.caption).lineLimit(1).padding(.horizontal, 10).frame(minHeight: 36)
                                .background(Color.raised, in: Capsule())
                        }
                        .buttonStyle(StudioQuietButtonStyle())
                        .accessibilityIdentifier("\(identifier).\(index)")
                    }
                }
            }
            .accessibilityIdentifier(identifier + "s")
        }
    }
}
