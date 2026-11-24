import MusicDomain
import SwiftUI

/// U26 · What "saved" means for this song: when it reached this iPhone, save now, go back to how it
/// was when opened (the current state is kept as a version first) or save a copy.
struct SaveCard: View {
    @Bindable var session: Session
    @Environment(\.dismiss) private var dismiss
    @State private var confirmBack = false

    private var status: String {
        if let error = session.saveError { return String(format: NSLocalizedString("Not saved: %@", comment: "Save card"), error) }
        if session.saving { return NSLocalizedString("Saving…", comment: "Save card") }
        if session.savedRevision == session.project.revision, let time = session.savedAt {
            return String(format: NSLocalizedString("Saved at %@ on this iPhone", comment: "Save card"), time.formatted(date: .omitted, time: .shortened))
        }
        return NSLocalizedString("Unsaved changes", comment: "Save card")
    }
    private var canGoBack: Bool { session.openedSnapshot.map { $0 != session.project } ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(status, systemImage: session.saveError != nil ? "exclamationmark.triangle.fill" : session.savedRevision == session.project.revision ? "checkmark.circle.fill" : "circle.dotted")
                .font(.headline).foregroundStyle(session.saveError != nil ? Color.record : Color.studioText)
                .accessibilityIdentifier("save.status")
            Text("Your song saves itself a moment after each change. Versions keep the moments you name.")
                .font(.footnote).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
            if session.savedRevision != session.project.revision || session.saveError != nil {
                Button { Task { await session.save() } } label: { Label("Save now", systemImage: "arrow.down.doc") }
                    .disabled(session.saving).accessibilityIdentifier("save.now")
            }
            Button { confirmBack = true } label: {
                Label(session.openedAt.map { String(format: NSLocalizedString("Back to how it was at %@", comment: "Save card"), $0.formatted(date: .omitted, time: .shortened)) }
                      ?? NSLocalizedString("Back to how it was when opened", comment: "Save card"), systemImage: "arrow.uturn.backward.circle")
            }
            .disabled(!canGoBack).accessibilityIdentifier("save.back")
            Button { Task { await session.saveCopy(); dismiss() } } label: { Label("Save a copy", systemImage: "plus.square.on.square") }
                .accessibilityIdentifier("save.copy")
            Button { dismiss(); session.presentEditor(.versions) } label: { Label("Versions…", systemImage: "clock.arrow.circlepath") }
                .accessibilityIdentifier("save.versions")
        }
        .buttonStyle(.borderless)
        .padding(16)
        .frame(minWidth: 280, maxWidth: 340, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("save.card")
        .alert("Go back to how it was when opened?", isPresented: $confirmBack) {
            Button("Go back", role: .destructive) { Task { await session.returnToOpened(); dismiss() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("The song as it is now is kept in Versions, so you can return to it.") }
    }
}
