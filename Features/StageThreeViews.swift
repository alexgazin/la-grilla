import SwiftUI
import MusicDomain

/// I7 · Variations of a part: pick a character and how bold, listen against the
/// original, apply in one Undo step.
struct VariationsView: View {
    @Bindable var session: Session
    @State private var character: PartVariator.Character = .ghostNotes
    @State private var boldness = 0.6
    @State private var seed: UInt64 = 1
    @State private var source = Source.variant
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    enum Source: Hashable { case original, variant }

    private var pattern: Pattern? { session.project.patterns.first { $0.id == session.toolPatternID } }
    private var role: TrackRole {
        session.project.tracks.first { $0.clips.contains { $0.patternID == session.toolPatternID } }?.role ?? .drums
    }
    private var characters: [PartVariator.Character] { PartVariator.characters(for: role) }
    private var variant: Pattern? {
        pattern.map { PartVariator.variant($0, role: role, character: character, boldness: boldness, seed: seed) }
    }
    private func candidate(_ value: Pattern?) -> Project? {
        guard let value, let index = session.project.patterns.firstIndex(where: { $0.id == value.id }) else { return nil }
        var project = session.project; project.patterns[index] = value; return project
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if pattern == nil {
                        Text("Open the beat or part you want to vary first.").foregroundStyle(Color.muted)
                    } else {
                        Text("CHARACTER").font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(Color.muted)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(Array(characters.enumerated()), id: \.element) { index, value in
                                Button { character = value; refresh() } label: {
                                    Text(LocalizedStringKey(value.title)).font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity, minHeight: 52)
                                        .background(character == value ? Color.mint.opacity(0.2) : Color.panel, in: RoundedRectangle(cornerRadius: Luz.Radius.cell, style: .continuous))
                                }
                                .buttonStyle(StudioQuietButtonStyle())
                                .accessibilityAddTraits(character == value ? .isSelected : [])
                                .accessibilityIdentifier("variations.card.\(index)")
                            }
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            HStack { Text("How bold"); Spacer(); Text("\(Int(boldness * 100))%").monospacedDigit().foregroundStyle(Color.muted) }
                            Slider(value: $boldness, in: 0.1...1, step: 0.1) { Text("How bold") } onEditingChanged: { editing in if !editing { refresh() } }
                                .accessibilityIdentifier("variations.boldness")
                            Button { seed &+= 1; refresh() } label: { Label("Another version", systemImage: "dice") }
                                .frame(minHeight: 44).accessibilityIdentifier("variations.reroll")
                        }
                        AuditionBar(screen: "variations", source: $source, sources: [(.original, "Original"), (.variant, "Variation")],
                                    playing: session.harmonyPreview, caption: "The part changes only when you apply the variation.",
                                    play: play, stop: { session.endHarmonyPreview() })
                        Button { apply() } label: { Text("Apply variation").frame(maxWidth: .infinity, minHeight: 48) }
                            .buttonStyle(StudioActionStyle()).accessibilityIdentifier("variations.apply")
                            .disabled(session.recording || session.armed)
                        Text("One Undo returns the original part.").font(.caption).foregroundStyle(Color.muted)
                    }
                }.padding(18)
            }
            .background(Color.ink)
            .navigationTitle("Variations").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { session.endHarmonyPreview(); session.sheet = nil }.accessibilityIdentifier("variations.cancel") } }
        }
        .tint(.mint)
        .onAppear { if !characters.contains(character) { character = characters.first ?? .simpler } }
        .onDisappear { session.endHarmonyPreview() }
    }

    private func play() {
        guard let project = candidate(source == .variant ? variant : pattern) else { return }
        session.previewSnapshot(project)
    }

    /// A running audition follows the new choice without stopping.
    private func refresh() { if session.harmonyPreview { play() } }

    private func apply() {
        guard let value = variant, let id = pattern?.id else { return }
        session.endHarmonyPreview()
        session.edit { p in
            guard let index = p.patterns.firstIndex(where: { $0.id == id }) else { return }
            p.patterns[index] = value
        }
        session.sheet = nil
        Luz.Haptics.success()
    }
}

/// I3 · Comping: choose, bar by bar, which take plays. The result is a new Comp take;
/// the source takes are muted, never deleted.
struct CompView: View {
    @Bindable var session: Session
    @State private var choices: [Int: UUID] = [:]
    @State private var source = Source.comp
    enum Source: Hashable { case current, comp }

    private var pattern: Pattern? { session.project.patterns.first { $0.id == session.toolPatternID } }
    private var takes: [DrumTakes.Summary] { DrumTakes.takes(in: pattern).filter { $0.label != "Comp" } }
    private var bars: Int { max(1, (pattern?.length ?? barTicks) / barTicks) }

    private func comped() -> Project? {
        guard var value = pattern, let index = session.project.patterns.firstIndex(where: { $0.id == value.id }),
              DrumTakes.comp(&value, choices: choices) != nil else { return nil }
        var project = session.project; project.patterns[index] = value; return project
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Tap a bar in a take to use it there. Bars you leave empty keep only the programmed beat.")
                        .font(.caption).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
                    ScrollView(.horizontal) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(takes) { take in
                                HStack(spacing: 4) {
                                    Text(DrumLayersView.title(take)).font(.caption.weight(.semibold)).frame(width: 64, alignment: .leading)
                                    ForEach(0..<bars, id: \.self) { bar in cell(take: take, bar: bar) }
                                }
                            }
                        }
                    }
                    AuditionBar(screen: "comp", source: $source, sources: [(.current, "As it is"), (.comp, "Comp")],
                                playing: session.harmonyPreview, enabled: source == .current || !choices.isEmpty,
                                caption: "The beat changes only when you apply the comp.", play: play, stop: { session.endHarmonyPreview() })
                    Button { apply() } label: { Text("Apply comp").frame(maxWidth: .infinity, minHeight: 48) }
                        .buttonStyle(StudioActionStyle()).disabled(choices.isEmpty || session.recording || session.armed)
                        .accessibilityIdentifier("comp.apply")
                    Text("The takes you comped from are muted, not deleted. One Undo returns everything.").font(.caption).foregroundStyle(Color.muted)
                }.padding(18)
            }
            .background(Color.ink)
            .navigationTitle("Best take").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { session.endHarmonyPreview(); session.sheet = nil } } }
        }
        .tint(.mint)
        .onDisappear { session.endHarmonyPreview() }
    }

    private func cell(take: DrumTakes.Summary, bar: Int) -> some View {
        let chosen = choices[bar] == take.id
        let hits = (pattern?.drums ?? []).filter { $0.take == take.id && $0.tick / barTicks == bar }.count
        return Button {
            choices[bar] = chosen ? nil : take.id
            Luz.Haptics.selection()
            if session.harmonyPreview { play() }
        } label: {
            Text("\(hits)").font(.caption.monospacedDigit())
                .frame(width: 44, height: 44)
                .background(chosen ? Color.mint : Color.panel, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .foregroundStyle(chosen ? Color.ink : (hits == 0 ? Color.muted : Color.studioText))
        }
        .buttonStyle(StudioQuietButtonStyle(plate: false))
        .accessibilityLabel(Text("\(DrumLayersView.title(take)), bar \(bar + 1)"))
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .accessibilityIdentifier("comp.cell.\(take.number).\(bar)")
    }

    private func play() {
        if source == .current { session.previewSnapshot(session.project) }
        else if let project = comped() { session.previewSnapshot(project) }
    }

    private func apply() {
        guard let id = pattern?.id else { return }
        let picked = choices
        session.endHarmonyPreview()
        session.edit { p in
            guard let index = p.patterns.firstIndex(where: { $0.id == id }) else { return }
            guard DrumTakes.comp(&p.patterns[index], choices: picked) != nil else { throw MusicError.invalidProject }
        }
        session.sheet = nil
        Luz.Haptics.success()
    }
}

/// I20 · Song structure from a template, shown as section chips before applying.
struct FormTemplatesView: View {
    @Bindable var session: Session
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("An empty song gets exactly these sections. A song with music keeps it: sections are renamed in order and the rest are added after.")
                    .font(.caption).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
                ForEach(Array(FormTemplate.all.enumerated()), id: \.element.id) { index, template in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(LocalizedStringKey(template.title)).font(.headline)
                            Spacer()
                            Text("\(template.sections.reduce(0) { $0 + $1.bars }) bars").font(.caption.monospacedDigit()).foregroundStyle(Color.muted)
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(Array(template.sections.enumerated()), id: \.offset) { _, section in
                                    Text("\(Text(LocalizedStringKey(section.name))) · \(section.bars)").font(.caption2)
                                        .padding(.horizontal, 8).padding(.vertical, 6)
                                        .background(Color.raised, in: Capsule())
                                }
                            }
                        }
                        Button { apply(template) } label: { Text("Use this structure").frame(maxWidth: .infinity, minHeight: 44) }
                            .buttonStyle(StudioActionStyle(color: .mint, prominent: false))
                            .disabled(session.recording || session.armed)
                            .accessibilityIdentifier("form.template.\(index)")
                    }
                    .padding(12)
                    .background(Color.panel, in: RoundedRectangle(cornerRadius: Luz.Radius.card, style: .continuous))
                }
            }.padding(16)
        }
        .background(Color.ink)
        .navigationTitle("Structure from a template").navigationBarTitleDisplayMode(.inline)
    }

    private func apply(_ template: FormTemplate) {
        let sections = template.sections
        session.edit { try FormEditing.apply(sections, to: &$0) }
        session.showToast("Structure applied")
        dismiss()
    }
}
