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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            StudioSegments(title: "Factory kits", selection: $kit,
                           options: [(.pocket, "Pocket"), (.dusty, "Dusty"), (.coast, "Coast")])
            Text(description)
                .font(.subheadline)
                .foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { controls }
                VStack(alignment: .leading, spacing: 4) { controls }
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
            Label(preview == nil ? "Audition beat" : "Stop preview",
                  systemImage: preview == nil ? "play.fill" : "stop.fill")
                .fixedSize(horizontal: true, vertical: false)
                .frame(minHeight: 44)
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier("pad-samples.preview-kit")
        .accessibilityValue(Text(verbatim: auditionValue))
        Button {
            stopPreview()
            load(kit)
        } label: {
            Label(applyTitle, systemImage: "square.grid.4x3.fill")
                .fixedSize(horizontal: true, vertical: false)
                .frame(minHeight: 44)
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier(kit == .pocket ? "pad-samples.pocket-kit" : "pad-samples.load-" + kit.rawValue)
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
        }
    }

    private var applyTitle: LocalizedStringKey {
        switch kit {
        case .pocket: "Load Pocket Kit"
        case .dusty: "Load Dusty Kit"
        case .coast: "Load Coast Kit"
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
