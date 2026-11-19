import MusicDomain
import SwiftUI
import UniformTypeIdentifiers

struct DrumSamplePicker: View {
    private struct LibraryTarget: Identifiable {
        let id: Int
    }

    private struct KitTarget: Identifiable {
        let id: Int // The revision captured when the library opens.
    }

    private struct EditTarget: Identifiable {
        let id: UUID
        let pad: Int
        let revision: Int
        let sample: SampleAsset
        let record: PadSampleEditRecord?
    }

    let session: Session
    let trackID: UUID
    let sourceID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var pendingPad: Int?
    @State private var showImporter = false
    @State private var showSliceImporter = false
    @State private var libraryTarget: LibraryTarget?
    @State private var editTarget: EditTarget?
    @State private var kitTarget: KitTarget?
    @State private var busy = false
    @State private var task: Task<Void, Never>?
    @State private var error: String?
    @State private var loopTempo: Double?
    @State private var loopURL: URL?

    private var track: Track? {
        guard session.project.id == sourceID else { return nil }
        return session.project.tracks.first { $0.id == trackID && $0.role == .drums }
    }

    private var editable: Bool {
        track != nil && !session.armed && !session.recording && !session.performance.contextActive && !busy
    }

    private var padSummary: String {
        guard session.runtimeTraceEnabled, let track else { return "" }
        // The recipe can have new asset UUIDs after import. Observe audible PCM.
        let slots = Compiler.padNames.indices.map { pad in
            track.padSamples?[pad].map { String($0.sha256.prefix(16)) } ?? "-"
        }
        return "project=\(session.project.id) revision=\(session.project.revision) pads=\(slots.joined(separator: ","))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    FactoryDrumKitPanel(session: session) { kit in
                        prepare { try await DrumSamplePreparation.shared.kit(kit) }
                    }
                    if let pads = track?.padSamples, !pads.isEmpty {
                        Button("Restore built-in kit") { restore(pad: nil) }
                    }
                    Button("Slice a loop onto the pads") { showSliceImporter = true }
                        .accessibilityIdentifier("pad-samples.slice-loop")
                    if let loopTempo, abs(loopTempo - session.project.bpm) >= 0.05 {
                        Button(String(format: NSLocalizedString("Use the loop tempo: %.1f BPM", comment: "Loop tempo"), loopTempo)) {
                            let bpm = min(240, max(40, loopTempo))
                            session.edit { $0.bpm = bpm }
                            self.loopTempo = nil
                        }.accessibilityIdentifier("pad-samples.loop-tempo")
                        if let url = loopURL, (0.5...2).contains(loopTempo / session.project.bpm) {
                            // I54: or keep the song tempo and stretch the loop to it.
                            Button(String(format: NSLocalizedString("Fit the loop to %.0f BPM and slice again", comment: "Loop tempo"), session.project.bpm)) {
                                let from = loopTempo, to = session.project.bpm
                                self.loopTempo = nil
                                prepare {
                                    let slices = try await DrumSamplePreparation.shared.importSlices(url, fit: (from, to))
                                    return slices.prefix(16).enumerated().map { (pad: Optional($0.offset), sound: $0.element) }
                                }
                            }.accessibilityIdentifier("pad-samples.loop-fit")
                        }
                    }
                } header: { Text("Factory kits") }
                footer: { Text("Audition the same beat with each kit. Loading replaces the 16 pad sounds in one undoable edit.") }
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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("My kits") { kitTarget = KitTarget(id: session.project.revision) }
                        .disabled(!editable)
                        .accessibilityIdentifier("pad-samples.my-kits")
                        .accessibilityValue(Text(verbatim: padSummary))
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
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
        .fileImporter(isPresented: $showSliceImporter, allowedContentTypes: [.wav, .aiff]) { result in
            switch result {
            case .success(let url):
                loopTempo = nil; loopURL = url
                Task { loopTempo = try? await DrumSamplePreparation.shared.loopTempo(url) }
                prepare {
                    let slices = try await DrumSamplePreparation.shared.importSlices(url)
                    return slices.prefix(16).enumerated().map { (pad: Optional($0.offset), sound: $0.element) }
                }
            case .failure(let failure): error = failure.localizedDescription
            }
        }
        .sheet(item: $libraryTarget) { target in
            PadSampleLibraryView(session: session, pad: target.id) { sound in
                prepare { [(target.id, sound)] }
            }
        }
        .sheet(item: $editTarget) { target in
            PadSampleEditor(session: session, projectID: sourceID, trackID: trackID,
                            revision: target.revision, pad: target.pad,
                            sample: target.sample, record: target.record)
        }
        .sheet(item: $kitTarget) { target in
            PersonalDrumKitsView(session: session, trackID: trackID, projectID: sourceID, revision: target.id)
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
            Button { libraryTarget = LibraryTarget(id: pad) } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(name).font(.headline).foregroundStyle(Color.studioText)
                        (sample.map { Text($0.name) } ?? Text("Built-in pad"))
                            .font(.caption).foregroundStyle(Color.muted)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                        .foregroundStyle(Color.muted).accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityLabel(name)
                .accessibilityValue(sample.map { Text($0.name) } ?? Text("Built-in pad"))
                .accessibilityHint("Choose from library")
                .accessibilityIdentifier("pad-samples.library.\(pad)")
            if let sample {
                Button {
                    editTarget = EditTarget(id: sample.id, pad: pad, revision: session.project.revision,
                                            sample: sample, record: track?.padEdits?[pad])
                } label: {
                    Image(systemName: "waveform.path").frame(width: 44, height: 44)
                }.buttonStyle(.plain).foregroundStyle(Color.drums)
                    .accessibilityLabel("Edit sample").accessibilityValue(name)
                    .accessibilityIdentifier("pad-samples.edit.\(pad)")
            }
            Menu {
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
                try project.tracks[index].setPadSample(nil, pad: pad)
            } else { project.tracks[index].clearPadSamples() }
        }
        if session.project.revision == previous { error = session.message }
    }
}
