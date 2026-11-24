import MusicDomain
import SwiftUI

/// I34 · Two to four sounds on one pad: soft to hard by hit strength, or in turn so repeated
/// hits do not sound the same. The result replaces the pad's sound with one Undo.
struct PadLayersBuilder: View {
    let pad: Int
    let samples: [SampleAsset]
    let use: (PreparedSound) -> Void

    enum Source: Hashable, Identifiable {
        case factory(FactoryDrumKit)
        case library(SampleAsset)
        var id: String {
            switch self {
            case let .factory(kit): "factory." + kit.rawValue
            case let .library(asset): "library." + asset.id.uuidString
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var chosen: [Source] = []
    @State private var mode: PadLayerMode = .velocity
    @State private var working = false
    @State private var error: String?

    private func name(_ source: Source) -> String {
        switch source {
        case let .factory(kit): DrumSamplePreparation.factoryName(kit, pad: pad)
        case let .library(asset): asset.name
        }
    }

    private var candidates: [Source] {
        FactoryDrumKit.allCases.map(Source.factory) + samples.filter { $0.layers == nil }.map(Source.library)
    }

    var body: some View {
        List {
            Section {
                Picker("Layers play", selection: $mode) {
                    ForEach(PadLayerMode.allCases, id: \.self) { item in Text(LocalizedStringKey(item.title)).tag(item) }
                }
                .pickerStyle(.segmented).accessibilityIdentifier("layers.mode")
            } footer: {
                Text(LocalizedStringKey(mode == .velocity
                    ? "The first layer sounds on soft hits, the last on hard ones."
                    : "Each hit plays the next layer, so a roll does not sound like a machine gun."))
            }
            Section {
                if chosen.isEmpty {
                    Text("Add two to four sounds below.").foregroundStyle(Color.muted)
                }
                ForEach(Array(chosen.enumerated()), id: \.element.id) { index, source in
                    HStack {
                        Text(verbatim: "\(index + 1)").font(.caption.monospacedDigit().weight(.bold)).foregroundStyle(Color.drums).frame(width: 24)
                        Text(verbatim: name(source)).foregroundStyle(Color.studioText)
                        Spacer()
                        Button { chosen.remove(at: index) } label: { Image(systemName: "minus.circle.fill").foregroundStyle(Color.record) }
                            .buttonStyle(.plain).frame(width: 44, height: 44)
                            .accessibilityLabel(Text("Remove layer \(index + 1)"))
                            .accessibilityIdentifier("layers.remove.\(index)")
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("layers.chosen.\(index)")
                }
                .onMove { chosen.move(fromOffsets: $0, toOffset: $1) }
            } header: { Text(LocalizedStringKey(mode == .velocity ? "Soft to hard" : "Order")) }
            Section("Add a layer") {
                ForEach(candidates) { source in
                    Button {
                        guard chosen.count < PadLayers.counts.upperBound, !chosen.contains(source) else { return }
                        withAnimation(Luz.Motion.snap) { chosen.append(source) }
                        Luz.Haptics.selection()
                    } label: {
                        Label { Text(verbatim: name(source)) } icon: { Image(systemName: chosen.contains(source) ? "checkmark.circle.fill" : "plus.circle") }
                            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                    }
                    .disabled(chosen.contains(source) || chosen.count >= PadLayers.counts.upperBound)
                    .accessibilityIdentifier("layers.add.\(source.id)")
                }
            }
            if let error { Text(error).foregroundStyle(Color.record) }
        }
        .scrollContentBackground(.hidden).background(Color.ink)
        .navigationTitle("Layers on this pad").navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button { apply() } label: {
                Label("Use \(chosen.count) layers", systemImage: "square.stack.3d.up.fill").frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(StudioActionStyle(color: .drums))
            .disabled(!PadLayers.counts.contains(chosen.count) || working)
            .padding(16).background(Color.ink)
            .accessibilityIdentifier("layers.apply")
        }
    }

    private func apply() {
        working = true; error = nil
        let sources = chosen, pad = pad, mode = mode
        Task {
            do {
                var sounds: [SamplePCM] = []
                for source in sources {
                    switch source {
                    case let .factory(kit):
                        let sound = try await DrumSamplePreparation.shared.factorySound(kit, pad: pad)
                        sounds.append(try SamplePCM.decode(sound.data, asset: sound.asset))
                    case let .library(asset):
                        let bytes = try await DrumSamplePreparation.library.get().bytes(for: asset)
                        sounds.append(try SamplePCM.decode(bytes, asset: asset))
                    }
                }
                let layered = try PreparedSound(layered: sounds, names: sources.map(name), mode: mode)
                Luz.Haptics.selection()
                use(layered)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            working = false
        }
    }
}
