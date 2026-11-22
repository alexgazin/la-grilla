import SwiftUI
import MusicDomain

/// Pocket beat lanes: kick, snare and hats (plus any other pad used in the bar)
/// as rows of sixteen steps, so a rhythm is written without switching pads.
/// Tapping a lane's name selects that pad for the velocity controls.
struct DrumLanesView: View {
    let pattern: Pattern?
    let bar: Int
    @Binding var selectedPad: Int
    let audio: AudioController
    let origin: Int
    /// Layers silenced in the Layers panel: shown dimmed with a crossed speaker.
    var mutedPads: Set<Int> = []
    let toggle: (_ pad: Int, _ tick: Int) -> Void

    static let corePads = [0, 1, 2, 3]
    private static let labelWidth: CGFloat = 58

    /// Core lanes first, then every other pad that has a hit in this bar.
    static func lanes(for pattern: Pattern?, bar: Int, selected: Int) -> [Int] {
        let used = Set((pattern?.drums ?? []).filter { $0.tick / barTicks == bar }.map(\.pad))
        let extra = used.union([selected]).subtracting(corePads).filter { (0..<16).contains($0) }.sorted()
        return corePads + extra
    }

    var body: some View {
        let lanes = Self.lanes(for: pattern, bar: bar, selected: selectedPad)
        let hits = Dictionary((pattern?.drums ?? []).filter { $0.tick / barTicks == bar }.map { ("\($0.pad).\($0.tick)", $0.velocity) },
                              uniquingKeysWith: max)
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                Color.clear.frame(width: Self.labelWidth, height: 1)
                LaneTicker(audio: audio, bar: bar, origin: origin, length: pattern?.length ?? barTicks)
            }
            ForEach(lanes, id: \.self) { pad in
                row(pad, hits: hits)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("jam.lanes")
    }

    private func row(_ pad: Int, hits: [String: Int]) -> some View {
        let selected = pad == selectedPad
        let muted = mutedPads.contains(pad)
        return HStack(spacing: 0) {
            Button { selectedPad = pad; Luz.Haptics.selection() } label: {
                HStack(spacing: 2) {
                    if muted { Image(systemName: "speaker.slash.fill").font(.caption2).foregroundStyle(Color.record).accessibilityLabel("Muted") }
                    Text(LocalizedStringKey(Compiler.padNames[pad]))
                }
                    .font(.caption.weight(selected ? .bold : .medium))
                    .foregroundStyle(selected ? Color.drums : Color.muted)
                    .lineLimit(2).minimumScaleFactor(0.7).multilineTextAlignment(.leading)
                    .frame(width: Self.labelWidth - 4, height: 46, alignment: .leading)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("jam.lane.\(pad)")
            Spacer(minLength: 4).frame(maxWidth: 4)
            HStack(spacing: 2) {
                ForEach(0..<16, id: \.self) { step in
                    let tick = bar * barTicks + step * 240
                    cell(pad: pad, step: step, tick: tick, velocity: hits["\(pad).\(tick)"], selected: selected)
                        .padding(.leading, step > 0 && step % 4 == 0 ? 4 : 0)
                }
            }
            .opacity(muted ? 0.4 : 1)
        }
    }

    private func cell(pad: Int, step: Int, tick: Int, velocity: Int?, selected: Bool) -> some View {
        let on = velocity != nil
        let level = Double(velocity ?? 0) / 127
        return Button { toggle(pad, tick); Luz.Haptics.selection() } label: {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(on ? Color.drums.opacity(0.45 + 0.55 * level) : Color.raised.opacity(step % 4 == 0 ? 1 : 0.6))
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(selected && !on ? Color.drums.opacity(0.35) : .clear, lineWidth: 1)
                }
                .frame(maxWidth: .infinity).frame(height: 46)
                .contentShape(Rectangle())
        }
        .buttonStyle(StudioQuietButtonStyle(plate: false))
        .accessibilityLabel(Text("\(Text(LocalizedStringKey(Compiler.padNames[pad]))), step \(step + 1)"))
        .accessibilityValue(LocalizedStringKey(on ? "On" : "Off"))
        .accessibilityIdentifier(selected ? "jam.step.\(step)" : "jam.lane.\(pad).\(step)")
    }
}

/// The only view of the lanes that reads the transport tick.
private struct LaneTicker: View {
    let audio: AudioController
    let bar: Int
    let origin: Int
    let length: Int

    var body: some View {
        let position = length > 0 ? ((Int(audio.tick) - origin) % length + length) % length : -1
        let current = audio.playing && position / barTicks == bar ? (position % barTicks) / 240 : -1
        HStack(spacing: 2) {
            ForEach(0..<16, id: \.self) { step in
                Capsule().fill(step == current ? Color.mint : Color.muted.opacity(step % 4 == 0 ? 0.55 : 0.2))
                    .frame(maxWidth: .infinity).frame(height: 3)
                    .padding(.leading, step > 0 && step % 4 == 0 ? 4 : 0)
            }
        }
        .transaction { $0.animation = nil }
        .accessibilityHidden(true)
    }
}
