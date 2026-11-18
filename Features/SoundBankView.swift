import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct SoundBankView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let session: Session

    @State private var banks: [ImportedSoundBank] = []
    @State private var bankID: UUID?
    @State private var showImporter = false
    @State private var importing = false
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
                        .disabled(importing).accessibilityIdentifier("sound-bank.import")
                    if importing { ProgressView("Importing sound bank…") }
                    if !banks.isEmpty {
                        Picker("Sound bank", selection: $bankID) {
                            ForEach(banks) { item in Text(item.name).tag(Optional(item.id)) }
                        }
                    }
                } footer: {
                    Text("Open an .sf2 file from Files and listen to its instruments. Bank previews leave the track sound unchanged.")
                }
                if let error { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(Color.record) }
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
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
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
        .onChange(of: bankID) { _, _ in stopAudition() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { stopAudition() } }
        .onDisappear { stopAudition() }
    }

    private func programRow(_ program: SoundBankProgram, bank: ImportedSoundBank) -> some View {
        let active = auditionProgram == program
        return Button {
            if active { stopAudition() } else { audition(program, bank: bank) }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(program.name).font(.headline).foregroundStyle(Color.studioText)
                    Text("Bank \(Int(program.bank)) · Program \(Int(program.program) + 1)")
                        .font(.caption.monospacedDigit()).foregroundStyle(Color.muted)
                }
                Spacer(minLength: 0)
                if active && player == nil { ProgressView() }
                else { Image(systemName: active ? "stop.fill" : "speaker.wave.2").foregroundStyle(Color.mint) }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(program.name)
        .accessibilityHint(active ? "Stop preview" : "Hear sound")
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
