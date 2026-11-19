import MusicDomain
import SwiftUI

struct PersonalDrumKitsView: View {
    let session: Session
    let trackID: UUID
    let projectID: UUID
    let revision: Int

    @Environment(\.dismiss) private var dismiss
    @FocusState private var editingName: Bool
    @State private var name = ""
    @State private var kits: [PersonalKitSummary] = []
    @State private var loading = true
    @State private var needsRetry = false
    @State private var deleting: PersonalKitSummary?
    @State private var action: Task<Void, Never>?
    @State private var failure: String?
    @State private var savedName: String?

    private var isCurrent: Bool {
        session.project.id == projectID && session.project.revision == revision &&
            session.project.tracks.contains { $0.id == trackID && $0.role == .drums } &&
            !session.armed && !session.recording && !session.performance.contextActive
    }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var busy: Bool { loading || action != nil }
    private var canSave: Bool {
        isCurrent && !busy && !needsRetry && !trimmedName.isEmpty && trimmedName.count <= 60
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Kit name", text: $name)
                        .focused($editingName).textInputAutocapitalization(.sentences)
                        .submitLabel(.done).onSubmit { save() }
                        .disabled(busy || !isCurrent)
                        .accessibilityIdentifier("pad-kits.name")
                    Button { save() } label: { Label("Save kit", systemImage: "tray.and.arrow.down") }
                        .disabled(!canSave).accessibilityIdentifier("pad-kits.save")
                    if trimmedName.count > 60 {
                        Text("Use up to 60 characters.").font(.footnote).foregroundStyle(Color.record)
                    }
                } header: {
                    Text("Save current kit")
                } footer: {
                    Text("Keep all 16 pad sounds and their edits for other projects on this iPhone.")
                }
                if !isCurrent {
                    Text(SampleError.stale.localizedDescription).foregroundStyle(Color.record)
                }
                if let failure {
                    Label(failure, systemImage: "exclamationmark.circle").foregroundStyle(Color.record)
                }
                if let savedName {
                    Text(String.localizedStringWithFormat(NSLocalizedString("Saved kit “%@”", comment: "Kit save confirmation"), savedName))
                        .font(.subheadline).foregroundStyle(Color.drums)
                }
                Section {
                    if busy { ProgressView().frame(maxWidth: .infinity) }
                    if needsRetry {
                        Button("Retry") { run { await refresh() } }.disabled(busy)
                    } else if !loading && kits.isEmpty {
                        Text("No saved kits yet").foregroundStyle(Color.muted)
                    }
                    ForEach(kits, id: \.id) { kit in row(kit) }
                } header: { Text("Saved kits") }
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollContentBackground(.hidden).background(Color.ink)
            .navigationTitle("My kits").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { action?.cancel(); dismiss() }
                        .accessibilityIdentifier("pad-kits.close")
                }
            }
            .alert("Delete kit?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                   presenting: deleting) { kit in
                Button("Delete", role: .destructive) { remove(kit) }
                    .accessibilityIdentifier("pad-kits.confirm-delete")
                Button("Cancel", role: .cancel) {}
            } message: { kit in
                Text(String.localizedStringWithFormat(
                    NSLocalizedString("Remove “%@” from My kits? Projects where you used it keep their sounds.", comment: "Kit deletion confirmation"),
                    kit.name))
            }
        }
        .tint(.drums)
        .task { await refresh() }
        .onDisappear { action?.cancel() }
        .onChange(of: name) { _, value in if !value.isEmpty { savedName = nil } }
    }

    private func row(_ kit: PersonalKitSummary) -> some View {
        let detail = kit.assignedCount == 0 ? NSLocalizedString("16 built-in pad sounds", comment: "Personal kit with no custom pad samples") :
            String.localizedStringWithFormat(NSLocalizedString("Pads with samples · %lld/16", comment: "Number of assigned samples in a personal kit"), Int64(kit.assignedCount))
        return HStack(spacing: 8) {
            Button { load(kit) } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: kit.name).font(.headline).foregroundStyle(Color.studioText)
                        Text(verbatim: detail).font(.caption).foregroundStyle(Color.muted)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.down.to.line").imageScale(.small)
                        .foregroundStyle(Color.drums).accessibilityHidden(true)
                }
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(busy || !isCurrent)
            .accessibilityLabel(kit.name).accessibilityValue(detail)
            .accessibilityHint("Load these sounds on all 16 pads")
            .accessibilityIdentifier("pad-kits.load.\(kit.id.uuidString)")
            Button { editingName = false; deleting = kit } label: {
                Image(systemName: "trash").frame(width: 44, height: 44)
            }
            .buttonStyle(.plain).foregroundStyle(Color.muted).disabled(busy)
            .accessibilityLabel("Delete kit").accessibilityValue(kit.name)
            .accessibilityIdentifier("pad-kits.delete.\(kit.id.uuidString)")
        }
    }

    private func refresh() async {
        loading = true
        defer { loading = false }
        do {
            let list = try await session.listPersonalKits()
            try Task.checkCancellation()
            kits = list
            needsRetry = false
        } catch is CancellationError { return }
        catch { failure = error.localizedDescription; needsRetry = true }
    }

    private func save() {
        guard canSave else { return }
        let title = trimmedName
        run {
            let kit = try await session.savePersonalKit(name: title, trackID: trackID, projectID: projectID, revision: revision)
            try Task.checkCancellation()
            kits.removeAll { $0.id == kit.id }
            kits.append(kit)
            kits.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            name = ""
            savedName = kit.name
        }
    }

    private func load(_ kit: PersonalKitSummary) {
        guard isCurrent else { return }
        run {
            try await session.loadPersonalKit(kit.id, trackID: trackID, projectID: projectID, revision: revision)
            try Task.checkCancellation()
            dismiss()
        }
    }

    private func remove(_ kit: PersonalKitSummary) {
        run {
            try await session.deletePersonalKit(kit.id)
            try Task.checkCancellation()
            kits.removeAll { $0.id == kit.id }
        }
    }

    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        editingName = false
        failure = nil
        savedName = nil
        action = Task {
            defer { action = nil }
            do { try await operation() }
            catch is CancellationError { return }
            catch { if !Task.isCancelled { failure = error.localizedDescription } }
        }
    }
}
