import SwiftUI
import MusicDomain

/// I15 · Prepare for release: measure the song offline (BS.1770), pick a loudness
/// target, hear before/after, apply master gain and limiter in one Undo step.
struct MasterAssistView: View {
    @Bindable var session: Session
    @State private var target = MasterTarget.streaming
    @State private var measured: LoudnessMeter.Measurement?
    @State private var measuring = false
    @State private var error: String?
    @State private var source = Source.after
    enum Source: Hashable { case before, after }

    private var suggestion: MasterSuggestion? {
        measured.map { MasterAssistant.suggest(measured: $0, currentMaster: session.project.master, target: target) }
    }
    private func candidate() -> Project? {
        guard let suggestion else { return nil }
        var project = session.project
        project.master = suggestion.master
        var fx = project.masterFX ?? MasterFX(); fx.limiter = suggestion.limiter ? true : fx.limiter; project.masterFX = fx
        return project
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("The whole song is measured on this iPhone the way streaming services do (integrated LUFS). Peaks stay under −1 dBFS.")
                        .font(.caption).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
                    Picker("Where it will play", selection: $target) {
                        ForEach(MasterTarget.allCases, id: \.self) { value in Text(LocalizedStringKey(value.title)).tag(value) }
                    }.pickerStyle(.inline).accessibilityIdentifier("master.target")
                    Button { Task { await measure() } } label: {
                        HStack { if measuring { ProgressView() }; Label(measured == nil ? "Measure the song" : "Measure again", systemImage: "gauge.with.dots.needle.67percent") }
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }.buttonStyle(StudioActionStyle(color: .mint, prominent: measured == nil)).disabled(measuring).accessibilityIdentifier("master.measure")
                    if let error { Text(LocalizedStringKey(error)).foregroundStyle(Color.record) }
                    if let measured, let suggestion {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Now: \(String(format: "%.1f", measured.integratedLUFS)) LUFS · peak \(String(format: "%.1f", measured.samplePeakDBFS)) dBFS").monospacedDigit()
                            Text("After: \(String(format: "%.1f", suggestion.predictedLUFS)) LUFS · master \(String(format: "%+.1f", suggestion.master)) dB").monospacedDigit().foregroundStyle(Color.mint)
                            if suggestion.limiter { Text("The limiter takes about \(String(format: "%.1f", suggestion.limiterReduction)) dB off the loudest peaks.").font(.caption) }
                            Text(LocalizedStringKey(adviceText(suggestion.advice))).font(.callout).foregroundStyle(suggestion.advice == "tooLoud" ? Color.drums : Color.studioText)
                        }
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.panel, in: RoundedRectangle(cornerRadius: Luz.Radius.card, style: .continuous))
                        .accessibilityElement(children: .combine).accessibilityIdentifier("master.result")
                        AuditionBar(screen: "master", source: $source, sources: [(.before, "Before"), (.after, "After")],
                                    playing: session.harmonyPreview, caption: "Before and after play from the same beat.", play: play, stop: { session.endHarmonyPreview() })
                        Button { apply() } label: { Text("Apply to the master").frame(maxWidth: .infinity, minHeight: 48) }
                            .buttonStyle(StudioActionStyle()).disabled(suggestion.advice == "silent" || session.recording || session.armed)
                            .accessibilityIdentifier("master.apply")
                        Text("One Undo returns the previous master.").font(.caption).foregroundStyle(Color.muted)
                    }
                }.padding(18)
            }
            .background(Color.ink)
            .navigationTitle("Prepare for release").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { session.endHarmonyPreview(); session.sheet = nil } } }
        }
        .tint(.mint)
        .onDisappear { session.endHarmonyPreview() }
    }

    private func adviceText(_ advice: String) -> String {
        switch advice {
        case "ready": "Already at the target. Nothing to change."
        case "louder": "The master goes up to reach the target."
        case "quieter": "The master comes down: the service would turn it down anyway."
        case "tooLoud": "This target needs more limiting than sounds good. The suggestion stops at 6 dB; lower the track levels for more."
        default: "The song is silent."
        }
    }

    private func play() {
        if source == .before { session.previewSnapshot(session.project) } else if let project = candidate() { session.previewSnapshot(project) }
    }

    private func measure() async {
        measuring = true; error = nil; defer { measuring = false }
        let project = session.project, samples = session.audio.samples
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Loudness-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            _ = try await OfflineRenderer.render(project, to: url, settings: WAVSettings(), samples: samples)
            measured = try await Task.detached(priority: .userInitiated) { () throws -> LoudnessMeter.Measurement in
                let wav = try LoudnessMeter.readWAV(url)
                return LoudnessMeter.measure(channels: wav.channels, rate: wav.rate)
            }.value
        } catch { self.error = NSLocalizedString("The song could not be measured. Try again.", comment: "Master assistant") }
    }

    private func apply() {
        guard let suggestion else { return }
        session.endHarmonyPreview()
        session.edit { p in
            p.master = suggestion.master
            if suggestion.limiter { var fx = p.masterFX ?? MasterFX(); fx.limiter = true; p.masterFX = fx }
        }
        session.showToast("Master ready")
    }
}
