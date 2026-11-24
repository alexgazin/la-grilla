import SwiftUI
import MusicDomain

/// I47 · Notes for co-authors: on the whole song or a section, resolved when done.
/// They travel in the portable package and merge with a co-author's copy.
struct CoAuthorNotesView: View {
    @Bindable var session: Session
    @AppStorage("notes.author") private var author = ""
    @State private var text = ""
    @State private var sectionID: UUID?

    private var notes: [ProjectNote] { (session.project.notes ?? []).sorted { $0.created > $1.created } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Your name", text: $author).textFieldStyle(.roundedBorder).accessibilityIdentifier("notes.author")
                        TextField("A note for your co-author", text: $text, axis: .vertical).lineLimit(2...5).textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("notes.text")
                        Picker("Where", selection: $sectionID) {
                            Text("Whole song").tag(nil as UUID?)
                            ForEach(session.project.sections) { section in Text(section.name).tag(Optional(section.id)) }
                        }.pickerStyle(.menu)
                        Button { add() } label: { Text("Add note").frame(maxWidth: .infinity, minHeight: 44) }
                            .buttonStyle(StudioActionStyle()).disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("notes.add-note")
                    }
                    .padding(12).background(Color.panel, in: RoundedRectangle(cornerRadius: Luz.Radius.card, style: .continuous))
                    if notes.isEmpty { Text("No notes yet. They travel with the song when you share it.").font(.callout).foregroundStyle(Color.muted) }
                    ForEach(notes) { note in row(note) }
                }.padding(18)
            }
            .background(Color.ink)
            .navigationTitle("Notes for co-authors").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { session.sheet = nil } } }
        }.tint(.mint)
    }

    private func row(_ note: ProjectNote) -> some View {
        let resolved = note.resolved == true
        let place = note.sectionID.flatMap { id in session.project.sections.first { $0.id == id }?.name }
        return HStack(alignment: .top, spacing: 10) {
            Button { setResolved(note, !resolved) } label: {
                Image(systemName: resolved ? "checkmark.circle.fill" : "circle").foregroundStyle(resolved ? Color.mint : Color.muted).frame(width: 44, height: 44)
            }.accessibilityLabel(LocalizedStringKey(resolved ? "Reopen" : "Mark as done"))
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: note.text).strikethrough(resolved).foregroundStyle(resolved ? Color.muted : Color.studioText)
                Text(verbatim: [note.author, place, note.created.formatted(.relative(presentation: .named))].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(Color.muted)
            }
            Spacer(minLength: 0)
            Button(role: .destructive) { delete(note) } label: { Image(systemName: "trash").frame(width: 44, height: 44) }.accessibilityLabel("Delete note")
        }
        .padding(8).background(Color.panel, in: RoundedRectangle(cornerRadius: Luz.Radius.card, style: .continuous))
    }

    private func add() {
        let note = ProjectNote(author: String(author.prefix(60)), text: String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1000)), sectionID: sectionID)
        session.edit { $0.notes = ($0.notes ?? []) + [note] }
        text = ""
    }
    private func setResolved(_ note: ProjectNote, _ value: Bool) {
        session.edit { p in if let i = p.notes?.firstIndex(where: { $0.id == note.id }) { p.notes?[i].resolved = value ? true : nil } }
    }
    private func delete(_ note: ProjectNote) {
        session.edit { p in p.notes?.removeAll { $0.id == note.id }; if p.notes?.isEmpty == true { p.notes = nil } }
    }
}
