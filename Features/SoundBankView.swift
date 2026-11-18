import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct SoundBankView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let session: Session
    let trackID: UUID
    let projectID: UUID
    let revision: Int

    @State private var banks: [ImportedSoundBank] = []
    @State private var bankID: UUID?
    @State private var showImporter = false
    @State private var importing = false
    @State private var applying: SoundBankProgram?
    @State private var applyTask: Task<Void, Never>?
    @State private var selectedProgram: SoundBankProgram?
    @State private var error: String?
    @State private var auditionTask: Task<Void, Never>?
    @State private var auditionProgram: SoundBankProgram?
    @State private var output: URL?
    @State private var player: AVAudioPlayer?

    private var bank: ImportedSoundBank? { banks.first { $0.id == bankID } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { showImporter = true } label: { Label("Import SoundFont", systemImage: "square.and.arrow.down") }
                        .disabled(importing || applying != nil).accessibilityIdentifier("sound-bank.import")
                    if importing { ProgressView("Importing sound bank…") }
                    if !banks.isEmpty {
                        Picker("Sound bank", selection: $bankID) {
                            ForEach(banks) { item in Text(item.name).tag(Optional(item.id)) }
                        }.disabled(applying != nil)
                    }
                } footer: {
                    Text("Import an .sf2 bank, audition a sound, then use it on this track.")
                }
                if let bank {
                    Section("Instruments") {
                        ForEach(bank.programs, id: \.self) { program in
                            programRow(program, bank: bank)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.ink)
            .navigationTitle("Sound banks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    if let error { Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(Color.record) }
                    Button {
                        if let bank, let selectedProgram { apply(selectedProgram, bank: bank) }
                    } label: {
                        if applying != nil { ProgressView("Preparing instrument…").frame(maxWidth: .infinity) }
                        else { Text("Use instrument").frame(maxWidth: .infinity) }
                    }
                    .buttonStyle(StudioActionStyle())
                    .disabled(selectedProgram == nil || importing || applying != nil)
                    .accessibilityIdentifier("sound-bank.apply")
                }.padding(16).background(Color.ink)
            }
        }
        .tint(.mint)
        .task { await refreshBanks() }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [UTType(filenameExtension: "sf2") ?? .data]) { result in
            stopAudition()
            switch result {
            case .success(let url): importBank(url)
            case .failure(let failure): error = failure.localizedDescription
            }
        }
        .onChange(of: bankID) { _, _ in stopAudition(); selectedProgram = nil }
        .onChange(of: scenePhase) { _, phase in if phase != .active { stopAudition() } }
        .onDisappear { stopAudition(); applyTask?.cancel() }
    }

    private func programRow(_ program: SoundBankProgram, bank: ImportedSoundBank) -> some View {
        let active = auditionProgram == program
        let selected = selectedProgram == program
        return HStack(spacing: 8) {
            Button { selectedProgram = program; error = nil } label: {
                HStack(spacing: 12) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? Color.mint : Color.muted)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(program.name).font(.headline).foregroundStyle(Color.studioText)
                        Text("Bank \(Int(program.bank)) · Program \(Int(program.program) + 1)")
                            .font(.caption.monospacedDigit()).foregroundStyle(Color.muted)
                    }
                    Spacer(minLength: 0)
                }.frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain)
                .disabled(program.bank == 128 || applying != nil)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
                .accessibilityIdentifier("sound-bank.program.\(program.bank).\(program.program)")
            Button {
                if active { stopAudition() } else { audition(program, bank: bank) }
            } label: {
                if active && player == nil { ProgressView() }
                else { Image(systemName: active ? "stop.fill" : "speaker.wave.2").foregroundStyle(Color.mint) }
            }
            .buttonStyle(.plain)
            .frame(width: 44, height: 44)
            .disabled(applying != nil)
            .accessibilityLabel(active ? "Stop preview" : "Hear sound")
            .accessibilityValue(program.name)
        }
    }

    private func apply(_ program: SoundBankProgram, bank: ImportedSoundBank) {
        stopAudition()
        error = nil
        applying = program
        applyTask = Task {
            defer { applying = nil }
            do {
                let sound = try await SoundBankLibrary.shared.prepareInstrument(program, in: bank)
                try Task.checkCancellation()
                try await session.assignSounds([(nil, sound)], trackID: trackID, projectID: projectID, revision: revision)
                dismiss()
            } catch is CancellationError {
                return
            } catch { self.error = error.localizedDescription }
        }
    }

    private func refreshBanks() async {
        do {
            banks = try await SoundBankLibrary.shared.list()
            if bankID == nil { bankID = banks.first?.id }
        } catch { self.error = error.localizedDescription }
    }

    private func importBank(_ url: URL) {
        error = nil
        importing = true
        Task {
            defer { importing = false }
            do {
                let imported = try await SoundBankLibrary.shared.importBank(from: url)
                banks.append(imported)
                banks.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                bankID = imported.id
            } catch { self.error = error.localizedDescription }
        }
    }

    private func audition(_ program: SoundBankProgram, bank: ImportedSoundBank) {
        stopAudition()
        error = nil
        auditionProgram = program
        auditionTask = Task {
            do {
                let rendered = try await SoundBankLibrary.shared.audition(program, in: bank)
                guard !Task.isCancelled else {
                    try? FileManager.default.removeItem(at: rendered)
                    return
                }
                output = rendered
                guard session.ensureAudio() else { throw SoundBankError.cannotRender }
                let audition = try AVAudioPlayer(contentsOf: rendered)
                audition.volume = 0.65
                guard audition.play() else { throw SoundBankError.cannotRender }
                player = audition
                try await Task.sleep(for: .seconds(audition.duration))
                stopAudition()
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
                stopAudition()
            }
        }
    }

    private func stopAudition() {
        auditionTask?.cancel()
        auditionTask = nil
        player?.stop()
        player = nil
        if let output { try? FileManager.default.removeItem(at: output) }
        output = nil
        auditionProgram = nil
    }
}
