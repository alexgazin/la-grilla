import SwiftUI
import MusicDomain

/// I21 · Pick a mood, hear four progressions with a reason each, apply one to the
/// selected section's chords in one Undo.
struct MoodProgressionsView: View {
    @Bindable var session: Session
    @State private var mood = Mood.bright
    @State private var choice = 0
    @State private var source = Source.mood
    enum Source: Hashable { case current, mood }

    private var options: [MoodProgressions.Option] { MoodProgressions.options(mood, keyRoot: session.project.keyRoot) }
    private var target: (index: Int, length: Int)? {
        let section = session.section
        guard let track = session.project.tracks.first(where: { $0.role == .harmony }),
              let clip = track.clips.first(where: { $0.start <= section.start && section.start < $0.start + $0.length }),
              let index = session.project.patterns.firstIndex(where: { $0.id == clip.patternID }) else { return nil }
        return (index, session.project.patterns[index].length)
    }
    private func candidate() -> Project? {
        guard let target, options.indices.contains(choice) else { return nil }
        var project = session.project
        project.patterns[target.index].chords = MoodProgressions.events(options[choice], bars: target.length / barTicks)
        return project
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    StudioSegments(title: "Mood", selection: $mood, options: Mood.allCases.map { ($0, LocalizedStringKey($0.title)) }, identifier: "mood.kind")
                        .onChange(of: mood) { _, _ in choice = 0; if session.harmonyPreview { play() } }
                    ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                        Button { choice = index; if session.harmonyPreview { play() } } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: option.chords.map { MusicalNotation.chordSymbol($0, keyRoot: session.project.keyRoot, minor: session.project.minor) }.joined(separator: "  "))
                                    .font(.headline.monospaced())
                                Text(verbatim: option.numerals).font(.caption.monospaced()).foregroundStyle(Color.muted)
                                Text(LocalizedStringKey(option.reason)).font(.caption).foregroundStyle(Color.studioText).multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                            .background(choice == index ? Color.harmony.opacity(0.18) : Color.panel, in: RoundedRectangle(cornerRadius: Luz.Radius.card, style: .continuous))
                        }
                        .buttonStyle(StudioQuietButtonStyle())
                        .accessibilityAddTraits(choice == index ? .isSelected : [])
                        .accessibilityIdentifier("mood.option.\(index)")
                    }
                    AuditionBar(screen: "mood", source: $source, sources: [(.current, "As it is"), (.mood, "This progression")],
                                playing: session.harmonyPreview, enabled: candidate() != nil,
                                caption: "The chords change only when you apply the progression.", play: play, stop: { session.endHarmonyPreview() })
                    Button { apply() } label: { Text("Use this progression").frame(maxWidth: .infinity, minHeight: 48) }
                        .buttonStyle(StudioActionStyle()).disabled(candidate() == nil || session.recording || session.armed)
                        .accessibilityIdentifier("mood.apply")
                }.padding(18)
            }
            .background(Color.ink)
            .navigationTitle("Progression by mood").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { session.endHarmonyPreview(); session.sheet = nil } } }
        }
        .tint(.mint)
        .onDisappear { session.endHarmonyPreview() }
    }

    private func play() {
        if source == .current { session.previewSnapshot(session.project) } else if let project = candidate() { session.previewSnapshot(project) }
    }

    private func apply() {
        guard let project = candidate(), let target else { return }
        let chords = project.patterns[target.index].chords
        session.endHarmonyPreview()
        session.edit { $0.patterns[target.index].chords = chords }
        session.sheet = nil
        Luz.Haptics.success()
    }
}
