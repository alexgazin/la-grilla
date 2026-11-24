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

/// I70 · Starter grooves by genre: hear one in this section, then use it (one Undo).
struct StarterGroovesView: View {
    @Bindable var session: Session
    @State private var selected = StarterGrooves.all[0].id
    @State private var source = Source.groove
    @State private var heldCard = false
    enum Source: Hashable { case current, groove }

    private var groove: StarterGrooves.Groove { StarterGrooves.all.first { $0.id == selected } ?? StarterGrooves.all[0] }
    private func candidate() -> Project? {
        var project = session.project
        guard (try? groove.clipboard.paste(into: session.section, project: &project)) != nil else { return nil }
        return project
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("One bar, repeated across the section. Our own patterns: use them freely.").font(.caption).foregroundStyle(Color.muted)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(Array(StarterGrooves.all.enumerated()), id: \.element.id) { index, item in
                            Button { if heldCard { heldCard = false; return }; selected = item.id; if session.harmonyPreview { play() } } label: {
                                VStack(spacing: 4) {
                                    Text(LocalizedStringKey(item.title)).font(.headline)
                                    Text("\(item.bpm) BPM").font(.caption.monospacedDigit()).foregroundStyle(Color.muted)
                                }.frame(maxWidth: .infinity, minHeight: 64)
                                    .background(selected == item.id ? Color.drums.opacity(0.2) : Color.panel, in: RoundedRectangle(cornerRadius: Luz.Radius.card, style: .continuous))
                            }
                            .buttonStyle(StudioQuietButtonStyle())
                            .accessibilityAddTraits(selected == item.id ? .isSelected : [])
                            .accessibilityIdentifier("grooves.item.\(index)")
                            // U67: holding a groove plays it in this section for four bars.
                            .holdToPreview(suppressTap: $heldCard, start: {
                                var project = session.project
                                guard (try? item.clipboard.paste(into: session.section, project: &project)) != nil else { return false }
                                return session.holdPreview(project, range: HoldPreview.range(project, from: session.section.start))
                            }, stop: { session.endHarmonyPreview() })
                        }
                    }
                    AuditionBar(screen: "grooves", source: $source, sources: [(.current, "As it is"), (.groove, "This groove")],
                                playing: session.harmonyPreview, enabled: candidate() != nil,
                                caption: "The beat changes only when you use the groove. The song's tempo stays.", play: play, stop: { session.endHarmonyPreview() })
                    Button { apply() } label: { Text("Use this groove").frame(maxWidth: .infinity, minHeight: 48) }
                        .buttonStyle(StudioActionStyle()).disabled(candidate() == nil || session.recording || session.armed)
                        .accessibilityIdentifier("grooves.apply")
                }.padding(18)
            }
            .background(Color.ink)
            .navigationTitle("Starter grooves").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { session.endHarmonyPreview(); session.sheet = nil } } }
        }
        .tint(.mint)
        .onDisappear { session.endHarmonyPreview() }
    }
    private func play() {
        if source == .current { session.previewSnapshot(session.project) } else if let project = candidate() { session.previewSnapshot(project) }
    }
    private func apply() {
        let clip = groove.clipboard, target = session.section
        session.endHarmonyPreview()
        session.edit { try clip.paste(into: target, project: &$0) }
        session.sheet = nil
        Luz.Haptics.success()
    }
}
