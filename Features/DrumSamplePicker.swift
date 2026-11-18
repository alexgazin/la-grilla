import MusicDomain
import SwiftUI
import UniformTypeIdentifiers

struct DrumSamplePicker: View {
    private struct LibraryTarget: Identifiable {
        let id: Int
    }

    let session: Session
    let trackID: UUID
    let sourceID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var pendingPad: Int?
    @State private var showImporter = false
    @State private var libraryTarget: LibraryTarget?
    @State private var busy = false
    @State private var task: Task<Void, Never>?
    @State private var error: String?

    private var track: Track? {
        guard session.project.id == sourceID else { return nil }
        return session.project.tracks.first { $0.id == trackID && $0.role == .drums }
    }

    private var editable: Bool {
        track != nil && !session.armed && !session.recording && !session.performance.contextActive && !busy
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { loadPocketKit() } label: {
                        Label("Load Pocket Kit", systemImage: "square.grid.4x3.fill")
                    }.accessibilityIdentifier("pad-samples.pocket-kit")
                    if let pads = track?.padSamples, !pads.isEmpty {
                        Button("Restore built-in kit") { restore(pad: nil) }
                    }
                } footer: { Text("16 original one-shots. Loading the kit replaces all pad sounds and can be undone.") }
                    .disabled(!editable)
                if busy { ProgressView("Preparing samples…") }
                if let error { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(Color.record) }
                Section {
                    ForEach(Compiler.padNames.indices, id: \.self) { padRow($0) }
                } header: { Text("Pads") }
                footer: { Text("Import mono or stereo WAV or AIFF files up to 8 seconds at 8–48 kHz.") }
                    .disabled(!editable)
            }
            .scrollContentBackground(.hidden).background(Color.ink)
            .navigationTitle("Pad samples").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .tint(.drums)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.wav, .aiff]) { result in
            guard let pendingPad else { return }
            switch result {
            case .success(let url):
                prepare {
                    let sound = try await DrumSamplePreparation.shared.importAndKeep(url)
                    return [(pendingPad, sound)]
                }
            case .failure(let failure): error = failure.localizedDescription
            }
        }
        .sheet(item: $libraryTarget) { target in
            PadSampleLibraryView(session: session, pad: target.id) { sound in
                prepare { [(target.id, sound)] }
            }
        }
        .onDisappear { task?.cancel() }
    }

    private func padRow(_ pad: Int) -> some View {
        let name = LocalizedStringKey(Compiler.padNames[pad])
        let sample = track?.padSamples?[pad]
        return HStack(spacing: 8) {
            Button {
                error = nil
                guard session.ensureAudio(), session.audio.pad(pad) else {
                    error = session.audio.error ?? SampleError.unavailable.localizedDescription
                    return
                }
            } label: {
                Image(systemName: "speaker.wave.2").frame(width: 44, height: 44)
            }.buttonStyle(.plain).foregroundStyle(Color.drums)
                .accessibilityLabel("Hear sound").accessibilityValue(name)
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.headline).foregroundStyle(Color.studioText)
                Group {
                    if let sample { Text(sample.name) }
                    else { Text("Built-in pad") }
                }.font(.caption).foregroundStyle(Color.muted)
                    .accessibilityIdentifier("pad-samples.name.\(pad)")
            }
            Spacer(minLength: 0)
            Menu {
                Button { libraryTarget = LibraryTarget(id: pad) } label: {
                    Label("Choose from library", systemImage: "waveform")
                }
                Button { pendingPad = pad; showImporter = true } label: {
                    Label("Import sample", systemImage: "square.and.arrow.down")
                }
                if sample != nil {
                    Button { restore(pad: pad) } label: { Label("Restore built-in pad", systemImage: "arrow.uturn.backward") }
                }
            } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                .accessibilityLabel("Pad sound options").accessibilityValue(name)
                .accessibilityIdentifier("pad-samples.options.\(pad)")
        }
    }

    private func loadPocketKit() {
        prepare { try await DrumSamplePreparation.shared.pocketKit() }
    }

    private func prepare(_ sounds: @escaping () async throws -> [(pad: Int?, sound: PreparedSound)]) {
        guard editable else { return }
        let revision = session.project.revision
        busy = true
        error = nil
        task = Task {
            defer { busy = false }
            do {
                let changes = try await sounds()
                try Task.checkCancellation()
                try await session.assignSounds(changes, trackID: trackID, projectID: sourceID, revision: revision)
            } catch is CancellationError { return }
            catch { self.error = error.localizedDescription }
        }
    }

    private func restore(pad: Int?) {
        guard editable else { return }
        error = nil
        let previous = session.project.revision
        session.edit { project in
            guard let index = project.tracks.firstIndex(where: { $0.id == trackID }) else { throw SampleError.stale }
            if let pad {
                project.tracks[index].padSamples?.removeValue(forKey: pad)
                if project.tracks[index].padSamples?.isEmpty == true { project.tracks[index].padSamples = nil }
            } else { project.tracks[index].padSamples = nil }
        }
        if session.project.revision == previous { error = session.message }
    }
}
