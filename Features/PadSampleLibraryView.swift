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
    @State private var factoryAudition: FactoryOneShot?

    /// One of the original on-device kits' one-shots: always available, nothing to import.
    struct FactoryOneShot: Hashable, Identifiable {
        let kit: FactoryDrumKit
        let pad: Int
        var id: String { "\(kit.rawValue).\(pad)" }
        var name: String { DrumSamplePreparation.factoryName(kit, pad: pad) }
    }

    private var factoryForPad: [FactoryOneShot] { FactoryDrumKit.allCases.map { FactoryOneShot(kit: $0, pad: pad) } }
    private var factoryMatches: [FactoryOneShot] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return FactoryDrumKit.allCases.flatMap { kit in Compiler.padNames.indices.map { FactoryOneShot(kit: kit, pad: $0) } }
            .filter { $0.name.localizedStandardContains(query) }
    }

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
                if !filtered.isEmpty {
                    Section("My samples") { ForEach(filtered, id: \.id) { sample in row(sample) } }
                }
                if search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Section("Factory sounds for this pad") {
                        ForEach(factoryForPad) { factoryRow($0) }
                    }
                    Section("All factory kits") {
                        ForEach(FactoryDrumKit.allCases, id: \.self) { kit in
                            DisclosureGroup {
                                ForEach(Compiler.padNames.indices, id: \.self) { factoryRow(FactoryOneShot(kit: kit, pad: $0)) }
                            } label: {
                                Text(verbatim: DrumSamplePreparation.factoryName(kit, pad: 0).components(separatedBy: " · ").first ?? kit.rawValue)
                                    .font(.headline).foregroundStyle(Color.studioText)
                            }.accessibilityIdentifier("pad-library.kit.\(kit.rawValue)")
                        }
                    }
                } else if !factoryMatches.isEmpty {
                    Section("Factory sounds") { ForEach(factoryMatches) { factoryRow($0) } }
                } else if filtered.isEmpty && !working {
                    Text("No matching samples").foregroundStyle(Color.muted)
                }
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
                Image(systemName: auditionID == sample.id ? "stop.fill" : "speaker.wave.2").contentTransition(.symbolEffect(.replace))
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

    private func factoryRow(_ item: FactoryOneShot) -> some View {
        let playing = factoryAudition == item
        return HStack(spacing: 8) {
            Button { chooseFactory(item) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: item.name).font(.headline).foregroundStyle(Color.studioText)
                    if item.pad != pad {
                        Text(LocalizedStringKey(Compiler.padNames[item.pad])).font(.caption).foregroundStyle(Color.muted)
                    }
                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(working)
                .accessibilityIdentifier("pad-library.factory.\(item.id)")
            Button {
                if playing { stopPreview() } else { previewFactory(item) }
            } label: {
                Image(systemName: playing ? "stop.fill" : "speaker.wave.2").contentTransition(.symbolEffect(.replace))
                    .frame(width: 44, height: 44).foregroundStyle(Color.drums)
            }.buttonStyle(.plain).disabled(working)
                .accessibilityLabel(playing ? "Stop preview" : "Hear sound")
                .accessibilityValue(item.name)
        }
    }

    private func chooseFactory(_ item: FactoryOneShot) {
        perform {
            let sound = try await DrumSamplePreparation.shared.factorySound(item.kit, pad: item.pad)
            try Task.checkCancellation()
            Luz.Haptics.selection()
            use(sound)
            dismiss()
        }
    }

    private func previewFactory(_ item: FactoryOneShot) {
        stopPreview()
        error = nil
        factoryAudition = item
        audition = Task {
            do {
                let wave = try await DrumSamplePreparation.shared.factoryPreview(item.kit, pad: item.pad)
                try Task.checkCancellation()
                try await play(wave)
            } catch is CancellationError { return }
            catch { self.error = error.localizedDescription; stopPreview() }
        }
    }

    private func play(_ wave: Data) async throws {
        guard session.ensureAudio() else { throw SampleError.unavailable }
        let audio = try AVAudioPlayer(data: wave)
        audio.volume = 0.65
        guard audio.play() else { throw SampleError.unavailable }
        player = audio
        try await Task.sleep(for: .seconds(audio.duration))
        stopPreview()
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
        factoryAudition = nil
        player?.stop()
        player = nil
    }
}
