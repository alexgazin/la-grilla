import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct SoundBankView: View {
    private enum Choice: Equatable {
        case included(FactoryInstrument)
        case imported(SoundBankProgram)

        var name: String {
            switch self {
            case .included(let instrument): instrument.displayName
            case .imported(let program): program.name
            }
        }
    }

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
    @State private var applying = false
    @State private var applyTask: Task<Void, Never>?
    @State private var selection: Choice?
    @State private var error: String?
    @State private var auditionTask: Task<Void, Never>?
    @State private var auditionChoice: Choice?
    @State private var search = ""
    @State private var output: URL?
    @State private var player: AVAudioPlayer?

    private var bank: ImportedSoundBank? { banks.first { $0.id == bankID } }
    private var query: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var matchingIncluded: [FactoryInstrument] {
        FactoryInstrument.allCases.filter { matches($0.displayName) }
    }
    private var matchingPrograms: [SoundBankProgram] {
        (bank?.programs ?? []).filter { matches($0.name) }
    }
    private func matches(_ name: String) -> Bool { query.isEmpty || name.localizedStandardContains(query) }

    var body: some View {
        NavigationStack {
            List {
                if !matchingIncluded.isEmpty {
                    Section("Studio instruments") {
                        ForEach(matchingIncluded) { instrument in
                            soundRow(.included(instrument), identifier: "sound-bank.included.\(instrument.id)")
                        }
                    }
                }
                Section {
                    Button { showImporter = true } label: { Label("Import SoundFont", systemImage: "square.and.arrow.down") }
                        .disabled(importing || applying).accessibilityIdentifier("sound-bank.import")
                    if importing { ProgressView("Importing sound bank…") }
                    if !banks.isEmpty {
                        Picker("Sound bank", selection: $bankID) {
                            ForEach(banks) { item in Text(item.name).tag(Optional(item.id)) }
                        }.disabled(applying)
                    }
                } footer: {
                    Text("Import an .sf2 bank, audition a sound, then use it on this track.")
                }
                if !matchingPrograms.isEmpty {
                    Section("Instruments") {
                        ForEach(matchingPrograms, id: \.self) { program in
                            let detail = Text("Bank \(Int(program.bank)) · Program \(Int(program.program) + 1)")
                            soundRow(.imported(program), detail: detail,
                                     identifier: "sound-bank.program.\(program.bank).\(program.program)", assignable: program.bank != 128)
                        }
                    }
                }
                if matchingPrograms.isEmpty && matchingIncluded.isEmpty {
                    Text("No matching instruments").foregroundStyle(Color.muted)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.ink)
            .navigationTitle("Sound banks")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search instruments")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    if let error { Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(Color.record) }
                    Button {
                        if let selection { apply(selection, bank: bank) }
                    } label: {
                        if applying { ProgressView("Preparing instrument…").frame(maxWidth: .infinity) }
                        else { Text("Use instrument").frame(maxWidth: .infinity) }
                    }
                    .buttonStyle(StudioActionStyle())
                    .disabled(selection == nil || importing || applying)
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
        .onChange(of: bankID) { _, _ in
            stopAudition()
            if case .imported = selection { selection = nil }
        }
        .onChange(of: search) { _, _ in
            if let selection, !matches(selection.name) { self.selection = nil }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { stopAudition() } }
        .onDisappear { stopAudition(); applyTask?.cancel() }
    }

    private func soundRow(_ choice: Choice, detail: Text? = nil, identifier: String, assignable: Bool = true) -> some View {
        let active = auditionChoice == choice
        let selected = selection == choice
        return HStack(spacing: 8) {
            Button { selection = choice; error = nil } label: {
                HStack(spacing: 12) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? Color.mint : Color.muted)
                    if case .included(let instrument) = choice {
                        Image(instrument.artwork).resizable().scaledToFill()
                            .frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius:9,style:.continuous))
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(choice.name).font(.headline).foregroundStyle(Color.studioText)
                        if let detail { detail.font(.caption.monospacedDigit()).foregroundStyle(Color.muted) }
                    }
                    Spacer(minLength: 0)
                }.frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain)
                .disabled(!assignable || applying)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
                .accessibilityIdentifier(identifier)
            Button {
                if active { stopAudition() } else { audition(choice, bank: bank) }
            } label: {
                if active && player == nil { ProgressView() }
                else { Image(systemName: active ? "stop.fill" : "speaker.wave.2").foregroundStyle(Color.mint).contentTransition(.symbolEffect(.replace)) }
            }
            .buttonStyle(.plain)
            .frame(width: 44, height: 44)
            .disabled(applying)
            .accessibilityLabel(active ? "Stop preview" : "Hear sound")
            .accessibilityValue(choice.name)
        }
    }

    private func apply(_ choice: Choice, bank: ImportedSoundBank?) {
        stopAudition()
        error = nil
        applying = true
        applyTask = Task {
            defer { applying = false }
            do {
                let sound: PreparedSound
                switch choice {
                case .included(let instrument):
                    sound = try await SoundBankLibrary.shared.prepareFactoryInstrument(instrument)
                case .imported(let program):
                    guard let bank else { throw SoundBankError.invalid }
                    sound = try await SoundBankLibrary.shared.prepareInstrument(program, in: bank)
                }
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

    private func audition(_ choice: Choice, bank: ImportedSoundBank?) {
        stopAudition()
        error = nil
        auditionChoice = choice
        auditionTask = Task {
            do {
                let rendered: URL
                switch choice {
                case .included(let instrument):
                    rendered = try await SoundBankLibrary.shared.auditionFactoryInstrument(instrument)
                case .imported(let program):
                    guard let bank else { throw SoundBankError.invalid }
                    rendered = try await SoundBankLibrary.shared.audition(program, in: bank)
                }
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
        auditionChoice = nil
    }
}
