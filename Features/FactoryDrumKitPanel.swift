import AVFoundation
import MusicDomain
import SwiftUI

struct FactoryDrumKitPanel: View {
    let session: Session
    let load: (FactoryDrumKit) -> Void

    @State private var kit: FactoryDrumKit = .pocket
    @State private var preview: Task<Void, Never>?
    @State private var player: AVAudioPlayer?
    @State private var error: String?
    @State private var lastAuditionSeconds: Double = 0
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            StudioSegments(title: "Factory kits", selection: $kit,
                           options: [(.pocket, "Pocket"), (.dusty, "Dusty"), (.coast, "Coast")])
            Picker("More kits", selection: $kit) {
                Text("Pocket").tag(FactoryDrumKit.pocket)
                Text("Dusty").tag(FactoryDrumKit.dusty)
                Text("Coast").tag(FactoryDrumKit.coast)
                Text("808 Trap").tag(FactoryDrumKit.trap808)
                Text("House").tag(FactoryDrumKit.house)
                Text("Brushes").tag(FactoryDrumKit.brushes)
                Text("World").tag(FactoryDrumKit.world)
            }.pickerStyle(.menu).accessibilityIdentifier("pad-samples.more-kits")
            Text(description)
                .font(.subheadline)
                .foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)
            if typeSize.isAccessibilitySize {
                VStack(spacing: 8) { controls }
            } else {
                HStack(spacing: 8) { controls }
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(Color.record)
            }
        }
        .onChange(of: kit) { _, _ in stopPreview(); error = nil; lastAuditionSeconds = 0 }
        .onChange(of: scenePhase) { _, phase in if phase != .active { stopPreview() } }
        .onDisappear { stopPreview() }
    }

    @ViewBuilder private var controls: some View {
        Button {
            if preview == nil { playPreview() } else { stopPreview() }
        } label: {
            actionLabel(preview == nil ? "Audition beat" : "Stop preview",
                        symbol: preview == nil ? "play.fill" : "stop.fill", primary: false)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pad-samples.preview-kit")
        .accessibilityValue(Text(verbatim: auditionValue))
        Button {
            stopPreview()
            load(kit)
        } label: {
            actionLabel(applyTitle, symbol: "square.grid.3x3.fill", primary: true)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(kit == .pocket ? "pad-samples.pocket-kit" : "pad-samples.load-" + kit.rawValue)
    }

    private func actionLabel(_ title: LocalizedStringKey, symbol: String, primary: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).accessibilityHidden(true)
            Text(title).fixedSize(horizontal: false, vertical: true)
        }
        .font(.subheadline.weight(.semibold))
        .multilineTextAlignment(.center)
        .foregroundStyle(primary ? Color.ink : Color.studioText)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(primary ? Color.mint : Color.ink, in: RoundedRectangle(cornerRadius: StudioMetrics.controlRadius))
        .contentShape(Rectangle())
    }

    private var auditionValue: String {
        if session.runtimeTraceEnabled {
            return "kit=\(kit.rawValue) duration=\(lastAuditionSeconds) revision=\(session.project.revision)"
        }
        guard lastAuditionSeconds > 0 else { return "" }
        return Duration.seconds(lastAuditionSeconds).formatted(.units(allowed: [.seconds], width: .wide))
    }

    private var description: LocalizedStringKey {
        switch kit {
        case .pocket: "Balanced kick, crisp hats and short percussion."
        case .dusty: "Dry kick, grainy snare and softened cymbals."
        case .coast: "Deep kick, layered clap and metallic hats."
        case .trap808: "Long 808 kick with a glide, tight snare and fast hats."
        case .house: "Punchy kick, big clap and bright open hats."
        case .brushes: "Felt kick, brushed snare and a warm ride."
        case .world: "Frame drum, congas, darbuka-style tek and bells."
        }
    }

    private var applyTitle: LocalizedStringKey {
        switch kit {
        case .pocket: "Load Pocket Kit"
        case .dusty: "Load Dusty Kit"
        case .coast: "Load Coast Kit"
        case .trap808: "Load 808 Trap Kit"
        case .house: "Load House Kit"
        case .brushes: "Load Brushes Kit"
        case .world: "Load World Kit"
        }
    }

    private func playPreview() {
        stopPreview()
        error = nil
        let selected = kit
        preview = Task {
            do {
                let wave = try await DrumSamplePreparation.shared.previewBeat(for: selected)
                try Task.checkCancellation()
                guard session.ensureAudio() else { throw SampleError.unavailable }
                let audio = try AVAudioPlayer(data: wave)
                guard audio.play() else { throw SampleError.unavailable }
                player = audio
                lastAuditionSeconds = audio.duration
                try await Task.sleep(for: .seconds(audio.duration))
                stopPreview()
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
                stopPreview()
            }
        }
    }

    private func stopPreview() {
        preview?.cancel()
        preview = nil
        player?.stop()
        player = nil
    }
}

extension DrumSamplePreparation {
    func previewBeat(for kit: FactoryDrumKit) throws -> Data {
        try kit.previewWAV()
    }
}
