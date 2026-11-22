import SwiftUI
import MusicDomain

/// Pocket beat layers: every pad that plays in the current drum pattern, with one-tap
/// Mute and Solo and a menu to clear that layer in this bar or the whole pattern.
/// Mute keeps the hits (playback and export skip them); clear removes them. Each action
/// is a single project edit, so one Undo restores it.
struct DrumLayersView: View {
    @Bindable var session: Session
    let pattern: Pattern?
    /// The bar the step editor shows; nil in Pads mode (whole pattern).
    let bar: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var trackIndex: Int? { session.project.tracks.firstIndex { $0.role == .drums } }
    private var track: Track? { trackIndex.map { session.project.tracks[$0] } }
    private var layers: [DrumLayers.Layer] { DrumLayers.layers(in: pattern, track: track) }
    private var locked: Bool { session.performance.contextActive || session.recording || session.armed }

    var body: some View {
        let layers = layers
        if !layers.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    SmallHeading(text: "LAYERS")
                    Spacer(minLength: 8)
                    DrumLayerActions.clearBeatMenu(session: session, pattern: pattern, bar: bar, layers: layers)
                        .disabled(locked)
                }
                ForEach(layers) { layer in
                    row(layer, among: layers.map(\.pad))
                        .transition(Luz.Transition.pop(reduceMotion))
                }
            }
            .padding(12)
            .modifier(StudioSurface())
            .animation(reduceMotion ? nil : Luz.Motion.snap, value: layers)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("jam.layers")
        }
    }

    private func row(_ layer: DrumLayers.Layer, among pads: [Int]) -> some View {
        HStack(spacing: 6) {
            Circle().fill(Color.drums.opacity(layer.muted ? 0.25 : 1)).frame(width: 8, height: 8).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(LocalizedStringKey(Compiler.padNames[layer.pad])).font(.subheadline.weight(.semibold))
                    .foregroundStyle(layer.muted ? Color.muted : Color.studioText)
                    .strikethrough(layer.muted, color: Color.muted)
                Text("\(layer.hits) hits").font(.caption2.monospacedDigit()).foregroundStyle(Color.muted)
            }
            Spacer(minLength: 4)
            Button { DrumLayerActions.toggleMute(session: session, pad: layer.pad) } label: {
                Image(systemName: layer.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(layer.muted ? Color.record : Color.drums)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(StudioQuietButtonStyle(plate: false))
            .accessibilityLabel(Text("Mute \(Text(LocalizedStringKey(Compiler.padNames[layer.pad])))"))
            .accessibilityValue(LocalizedStringKey(layer.muted ? "On" : "Off"))
            .accessibilityIdentifier("jam.layer.mute.\(layer.pad)")
            Button { DrumLayerActions.solo(session: session, pad: layer.pad, among: pads) } label: {
                Text(verbatim: "S").font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.drums)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(StudioQuietButtonStyle(plate: false))
            .accessibilityLabel(Text("Solo \(Text(LocalizedStringKey(Compiler.padNames[layer.pad])))"))
            .accessibilityIdentifier("jam.layer.solo.\(layer.pad)")
            DrumLayerActions.layerMenu(session: session, pattern: pattern, pad: layer.pad, bar: bar, hits: layer.hits)
        }
        .disabled(locked)
        .frame(minHeight: 44)
    }
}

/// The same actions as a compact menu (landscape Jam header).
struct DrumLayersMenu: View {
    @Bindable var session: Session
    let pattern: Pattern?
    var body: some View {
        let track = session.project.tracks.first { $0.role == .drums }
        let layers = DrumLayers.layers(in: pattern, track: track)
        Menu {
            ForEach(layers) { layer in
                Menu {
                    Button(layer.muted ? "Unmute" : "Mute", systemImage: layer.muted ? "speaker.wave.2" : "speaker.slash") {
                        DrumLayerActions.toggleMute(session: session, pad: layer.pad)
                    }
                    Button("Solo", systemImage: "headphones") { DrumLayerActions.solo(session: session, pad: layer.pad, among: layers.map(\.pad)) }
                    Button("Clear layer", systemImage: "trash", role: .destructive) { DrumLayerActions.clear(session: session, pattern: pattern, pad: layer.pad, bar: nil) }
                } label: {
                    Label { Text("\(Text(LocalizedStringKey(Compiler.padNames[layer.pad]))) · \(layer.hits)") }
                        icon: { Image(systemName: layer.muted ? "speaker.slash" : "speaker.wave.2") }
                }
            }
            if !layers.isEmpty {
                Divider()
                Button("Clear whole beat", systemImage: "trash", role: .destructive) { DrumLayerActions.clearAll(session: session, pattern: pattern, bar: nil) }
            }
        } label: {
            Image(systemName: "square.3.layers.3d").foregroundStyle(Color.drums).frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .disabled(layers.isEmpty || session.performance.contextActive || session.recording || session.armed)
        .accessibilityLabel("Layers")
        .accessibilityIdentifier("jam.layers-menu")
    }
}

/// Every layer action is one undoable project edit.
@MainActor enum DrumLayerActions {
    static func toggleMute(session: Session, pad: Int) {
        guard let t = session.project.tracks.firstIndex(where: { $0.role == .drums }) else { return }
        let muted = !session.project.tracks[t].isPadMuted(pad)
        session.edit { p in DrumLayers.setMuted(&p.tracks[t], pad: pad, muted: muted) }
        Luz.Haptics.selection()
    }

    static func solo(session: Session, pad: Int, among pads: [Int]) {
        guard let t = session.project.tracks.firstIndex(where: { $0.role == .drums }) else { return }
        session.edit { p in DrumLayers.solo(&p.tracks[t], pad: pad, among: pads) }
        Luz.Haptics.selection()
    }

    static func clear(session: Session, pattern: Pattern?, pad: Int, bar: Int?) {
        guard let id = pattern?.id else { return }
        session.edit { p in
            guard let i = p.patterns.firstIndex(where: { $0.id == id }) else { return }
            DrumLayers.clear(&p.patterns[i], pad: pad, bar: bar)
        }
        Luz.Haptics.warning()
    }

    static func clearAll(session: Session, pattern: Pattern?, bar: Int?) {
        guard let id = pattern?.id else { return }
        session.edit { p in
            guard let i = p.patterns.firstIndex(where: { $0.id == id }) else { return }
            DrumLayers.clearAll(&p.patterns[i], bar: bar)
        }
        Luz.Haptics.warning()
    }

    /// The trailing ⋯ of a layer row: clearing is a menu step, never a single stray tap.
    static func layerMenu(session: Session, pattern: Pattern?, pad: Int, bar: Int?, hits: Int) -> some View {
        Menu {
            if let bar {
                Button("Clear in bar \(bar + 1)", systemImage: "eraser") { clear(session: session, pattern: pattern, pad: pad, bar: bar) }
            }
            Button("Clear layer", systemImage: "trash", role: .destructive) { clear(session: session, pattern: pattern, pad: pad, bar: nil) }
                .disabled(hits == 0)
        } label: {
            Image(systemName: "ellipsis").foregroundStyle(Color.muted).frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .accessibilityLabel(Text("More for \(Text(LocalizedStringKey(Compiler.padNames[pad])))"))
        .accessibilityIdentifier("jam.layer.more.\(pad)")
    }

    static func clearBeatMenu(session: Session, pattern: Pattern?, bar: Int?, layers: [DrumLayers.Layer]) -> some View {
        Menu {
            if let bar {
                Button("Clear bar \(bar + 1)", systemImage: "eraser") { clearAll(session: session, pattern: pattern, bar: bar) }
            }
            Button("Clear whole beat", systemImage: "trash", role: .destructive) { clearAll(session: session, pattern: pattern, bar: nil) }
            if layers.contains(where: \.muted) {
                Button("Unmute all", systemImage: "speaker.wave.2") {
                    guard let t = session.project.tracks.firstIndex(where: { $0.role == .drums }) else { return }
                    session.edit { p in p.tracks[t].mutedPads = nil }
                }
            }
        } label: {
            Label("Clear", systemImage: "trash").font(.caption.weight(.semibold)).foregroundStyle(Color.record)
                .frame(minHeight: 44).contentShape(Rectangle())
        }
        .accessibilityIdentifier("jam.layers.clear")
    }
}
