import AVFoundation
import MusicDomain
import SwiftUI
import UniformTypeIdentifiers

struct PadSampleLibraryView: View {
    let session: Session
    let pad: Int
    let use: (PreparedSound) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var samples: [SampleAsset] = []
    @State private var search = ""
    @State private var importing = false
    @State private var working = false
    @State private var error: String?
    @State private var action: Task<Void, Never>?
    @State private var audition: Task<Void, Never>?
    @State private var auditionID: UUID?
    @State private var player: AVAudioPlayer?

    private var filtered: [SampleAsset] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? samples : samples.filter { $0.name.localizedStandardContains(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { importing = true } label: { Label("Import sample", systemImage: "square.and.arrow.down") }
                        .accessibilityIdentifier("pad-library.import")
                        .disabled(working)
                } footer: {
                    Text("Tap a sample to use it on this pad. Your library is available in every project.")
                }
                if let error { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(Color.record) }
                if working { ProgressView("Preparing samples…") }
                if filtered.isEmpty && !working {
                    Text(LocalizedStringKey(search.isEmpty ? "No saved samples" : "No matching samples"))
                        .foregroundStyle(Color.muted)
                }
                ForEach(filtered, id: \.id) { sample in row(sample) }
            }
            .scrollContentBackground(.hidden).background(Color.ink)
            .navigationTitle("Sample library").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Search samples")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                Text(LocalizedStringKey(Compiler.padNames[pad]))
                    .font(.caption.weight(.semibold)).foregroundStyle(Color.drums)
                    .frame(maxWidth: .infinity).padding(12).background(Color.ink)
            }
        }
        .tint(.drums)
        .task {
            do { samples = try await DrumSamplePreparation.library.get().list() }
            catch { self.error = error.localizedDescription }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.wav, .aiff]) { result in
            switch result {
            case .success(let url):
                perform {
                    _ = try await DrumSamplePreparation.shared.importAndKeep(url)
                    samples = try await DrumSamplePreparation.library.get().list()
                    search = ""
                }
            case .failure(let failure): error = failure.localizedDescription
            }
        }
        .onDisappear { action?.cancel(); stopPreview() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { stopPreview() } }
    }

    private func row(_ sample: SampleAsset) -> some View {
        HStack(spacing: 8) {
            Button { choose(sample) } label: {
                Text(sample.name).font(.headline).foregroundStyle(Color.studioText)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(working)
                .accessibilityIdentifier("pad-library.sample.\(sample.id.uuidString)")
            Button {
                if auditionID == sample.id { stopPreview() } else { preview(sample) }
            } label: {
                Image(systemName: auditionID == sample.id ? "stop.fill" : "speaker.wave.2")
                    .frame(width: 44, height: 44).foregroundStyle(Color.drums)
            }.buttonStyle(.plain).disabled(working)
                .accessibilityLabel(auditionID == sample.id ? "Stop preview" : "Hear sound")
                .accessibilityValue(sample.name)
        }
        .swipeActions(allowsFullSwipe: false) {
            Button(role: .destructive) {
                perform {
                    try await DrumSamplePreparation.library.get().remove(sample)
                    samples.removeAll { $0.id == sample.id }
                }
            } label: { Label("Remove from library", systemImage: "trash") }
                .disabled(working)
        }
    }

    private func choose(_ sample: SampleAsset) {
        perform {
            let bytes = try await DrumSamplePreparation.library.get().bytes(for: sample)
            try Task.checkCancellation()
            let sound = try PreparedSound(copying: sample, data: bytes)
            use(sound)
            dismiss()
        }
    }

    private func perform(_ operation: @escaping () async throws -> Void) {
        guard !working else { return }
        stopPreview()
        error = nil
        working = true
        action = Task {
            defer { working = false }
            do { try await operation() }
            catch is CancellationError { return }
            catch { self.error = error.localizedDescription }
        }
    }

    private func preview(_ sample: SampleAsset) {
        stopPreview()
        error = nil
        auditionID = sample.id
        audition = Task {
            do {
                let wave = try await DrumSamplePreparation.library.get().previewWAV(for: sample)
                try Task.checkCancellation()
                guard session.ensureAudio() else { throw SampleError.unavailable }
                let audio = try AVAudioPlayer(data: wave)
                audio.volume = 0.65
                guard audio.play() else { throw SampleError.unavailable }
                player = audio
                try await Task.sleep(for: .seconds(audio.duration))
                stopPreview()
            } catch is CancellationError { return }
            catch { self.error = error.localizedDescription; stopPreview() }
        }
    }

    private func stopPreview() {
        audition?.cancel()
        audition = nil
        auditionID = nil
        player?.stop()
        player = nil
    }
}
