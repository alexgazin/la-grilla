import SwiftUI
import MusicDomain

/// I9 · The words of the selected section, with syllables counted against the notes
/// of the melody and laid under them in one Undo step.
struct LyricsView: View {
    @Bindable var session: Session
    @State private var text = ""
    @State private var loadedSection: UUID?

    private var melody: (patternIndex: Int, notes: [NoteEvent])? {
        let section = session.section
        guard let track = session.project.tracks.first(where: { $0.id == session.noteTrackID }) ?? session.project.tracks.first(where: { $0.role == .melody }),
              let clip = track.clips.first(where: { $0.start <= section.start && section.start < $0.start + $0.length }),
              let index = session.project.patterns.firstIndex(where: { $0.id == clip.patternID }) else { return nil }
        return (index, session.project.patterns[index].notes ?? [])
    }
    private var syllableCount: Int { text.components(separatedBy: .newlines).flatMap(Syllables.line).count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Words for “\(session.section.name)”. One line per phrase; type hyphens to split syllables your way (лю-бовь).")
                        .font(.caption).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
                    TextEditor(text: $text).font(.body).frame(minHeight: 180).scrollContentBackground(.hidden)
                        .padding(8).background(Color.raised, in: RoundedRectangle(cornerRadius: Luz.Radius.cell, style: .continuous))
                        .accessibilityIdentifier("lyrics.text")
                    ForEach(Array(text.components(separatedBy: .newlines).enumerated()), id: \.offset) { _, line in
                        if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                            Text(verbatim: Syllables.line(line).joined(separator: " ")).font(.caption.monospaced()).foregroundStyle(Color.muted)
                        }
                    }
                    if let melody {
                        let balance = syllableCount - melody.notes.count
                        Text(balance == 0 ? "Every note has a syllable." : balance > 0 ? "\(balance) syllables more than notes." : "\(-balance) notes without words.")
                            .font(.callout).foregroundStyle(balance == 0 ? Color.mint : Color.drums).accessibilityIdentifier("lyrics.balance")
                        Button { apply(layOnNotes: true) } label: { Text("Save and place under the notes").frame(maxWidth: .infinity, minHeight: 48) }
                            .buttonStyle(StudioActionStyle()).disabled(melody.notes.isEmpty || session.recording || session.armed)
                            .accessibilityIdentifier("lyrics.place")
                    } else {
                        Text("Add a melody track to place the words under notes.").font(.caption).foregroundStyle(Color.muted)
                    }
                    Button { apply(layOnNotes: false) } label: { Text("Save words").frame(maxWidth: .infinity, minHeight: 44) }
                        .buttonStyle(StudioActionStyle(color: .mint, prominent: false)).disabled(session.recording || session.armed)
                        .accessibilityIdentifier("lyrics.save")
                    Text("Words travel with the project and are written into MIDI as lyrics.").font(.caption).foregroundStyle(Color.muted)
                }.padding(18)
            }
            .background(Color.ink)
            .navigationTitle("Lyrics").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { session.sheet = nil }.accessibilityIdentifier("lyrics.close") } }
        }
        .tint(.mint)
        .onAppear { if loadedSection != session.section.id { text = session.section.lyrics ?? ""; loadedSection = session.section.id } }
    }

    private func apply(layOnNotes: Bool) {
        let sectionID = session.section.id, words = String(text.prefix(4000))
        let laid = layOnNotes ? melody.map { ($0.patternIndex, Syllables.assign(words, to: $0.notes).notes) } : nil
        session.edit { p in
            if let index = p.sections.firstIndex(where: { $0.id == sectionID }) { p.sections[index].lyrics = words.isEmpty ? nil : words }
            if let laid { p.patterns[laid.0].notes = laid.1 }
        }
        session.showToast(layOnNotes ? "Words placed" : "Words saved")
    }
}
