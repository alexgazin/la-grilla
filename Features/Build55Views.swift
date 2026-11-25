import SwiftUI
import MusicDomain

/// 55 · Arpeggiate the chords or notes of a track into MIDI notes the piano roll edits: order,
/// rate on the song's grid (with triplets), 1–3 octaves and note length. Listen first; nothing
/// reaches the song before "Write as notes", which is one Undo.
struct ArpeggiatorView: View {
    @Bindable var session: Session
    @AppStorage("arpeggiator.direction") private var directionRaw = Arpeggiator.Pattern.up.rawValue
    @AppStorage("arpeggiator.rate") private var rateRaw = ArpeggioSettings.Rate.sixteenth.rawValue
    @AppStorage("arpeggiator.octaves") private var octaves = 1
    @AppStorage("arpeggiator.gate") private var gate = 0.8
    @State private var trackID: UUID?
    /// nil = the whole song.
    @State private var sectionID: UUID?
    @State private var destination: ArpeggioTool.Destination = .newTrack
    @State private var removeChords = false
    @State private var listenSource = 0
    @State private var playing = false
    @State private var error: String?

    private var settings: ArpeggioSettings {
        ArpeggioSettings(direction: Arpeggiator.Pattern(rawValue: directionRaw) ?? .up,
                         rate: ArpeggioSettings.Rate(rawValue: rateRaw) ?? .sixteenth,
                         octaves: min(3, max(1, octaves)), gate: min(1, max(0.1, gate)))
    }
    private var sources: [Track] { session.project.tracks.filter { $0.role == .harmony || $0.role == .melody } }
    private var source: Track? { sources.first { $0.id == trackID } ?? sources.first }
    private var section: MusicDomain.Section? { session.project.sections.first { $0.id == sectionID } }
    private var request: ArpeggioTool.Request? {
        guard let source else { return nil }
        let range = section.map { $0.start..<($0.start + $0.length) }
        return ArpeggioTool.Request(trackID: source.id, range: range, settings: settings,
                                    destination: source.role == .melody ? destination : .newTrack,
                                    removeChords: source.role == .harmony && removeChords)
    }
    private var noteCount: Int { request.map { ArpeggioTool.render(session.project, $0).count } ?? 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Track", selection: Binding(get: { source?.id }, set: { trackID = $0; stop() })) {
                        ForEach(sources) { track in Text(verbatim: track.displayName).tag(Optional(track.id)) }
                    }.accessibilityIdentifier("arpeggiator.source")
                    Picker("Where", selection: Binding(get: { sectionID }, set: { sectionID = $0; stop() })) {
                        Text("Whole song").tag(UUID?.none)
                        ForEach(session.project.sections) { section in Text(verbatim: section.name).tag(Optional(section.id)) }
                    }.accessibilityIdentifier("arpeggiator.range")
                } header: { Text("Arpeggiate") } footer: {
                    Text(source?.role == .harmony ? "The chords of this track, as they change through the song." : "Notes that sound together are held and played one by one.")
                }
                Section {
                    Picker("Order", selection: Binding(get: { directionRaw }, set: { directionRaw = $0; restart() })) {
                        ForEach(Arpeggiator.Pattern.allCases) { order in Text(LocalizedStringKey(order.title)).tag(order.rawValue) }
                    }.accessibilityIdentifier("arpeggiator.direction")
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Rate").font(.subheadline)
                        StudioSegments(title: "Rate", selection: Binding(get: { rateRaw }, set: { rateRaw = $0; restart() }),
                                       options: ArpeggioSettings.Rate.allCases.map { ($0.rawValue, LocalizedStringKey($0.label)) }, identifier: "arpeggiator.rate")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Octaves").font(.subheadline)
                        StudioSegments(title: "Octaves", selection: Binding(get: { octaves }, set: { octaves = $0; restart() }),
                                       options: [(1, "1"), (2, "2"), (3, "3")], identifier: "arpeggiator.octaves")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Note length").font(.subheadline)
                        StudioSegments(title: "Note length", selection: Binding(get: { gate }, set: { gate = $0; restart() }),
                                       options: ArpeggioSettings.gates.map { ($0, LocalizedStringKey("\(Int($0 * 100))%")) }, identifier: "arpeggiator.gate")
                    }
                } header: { Text("Arpeggio") } footer: {
                    Text("Rates follow the song's tempo; 1/8T and 1/16T are triplets. Note length is the part of each step that sounds.")
                }
                Section {
                    if source?.role == .melody {
                        Picker("Write to", selection: $destination) {
                            Text("A new track").tag(ArpeggioTool.Destination.newTrack)
                            Text("This track, instead of its notes").tag(ArpeggioTool.Destination.replace)
                        }.accessibilityIdentifier("arpeggiator.destination")
                    } else {
                        Toggle("Silence the chords where the arpeggio plays", isOn: $removeChords).accessibilityIdentifier("arpeggiator.remove-chords")
                    }
                    Text(String(format: NSLocalizedString("%d notes, editable in the piano roll.", comment: "Arpeggiator"), noteCount))
                        .font(.footnote).foregroundStyle(Color.muted).accessibilityIdentifier("arpeggiator.count")
                }
                Section {
                    AuditionBar(screen: "arpeggiator", source: $listenSource, sources: [(0, "Arpeggio")], playing: playing && session.harmonyPreview,
                                enabled: noteCount > 0, caption: "Nothing changes in the song until you write the notes.",
                                play: play, stop: stop)
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                    if let error { Text(error).font(.footnote).foregroundStyle(Color.record).accessibilityIdentifier("arpeggiator.error") }
                    Button { write() } label: {
                        Label("Write as MIDI notes", systemImage: "pianokeys").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(StudioActionStyle()).disabled(noteCount == 0).accessibilityIdentifier("arpeggiator.apply")
                }
            }
            .navigationTitle("Arpeggiator").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { stop(); session.sheet = nil }.accessibilityIdentifier("arpeggiator.done") } }
            .onAppear { if trackID == nil { trackID = session.arpeggiatorTrackID ?? sources.first?.id } }
            .onDisappear { stop() }
        }
    }

    private func candidate() throws -> Project {
        guard let request else { throw ArpeggioToolError.nothingToArpeggiate }
        var project = session.project
        try ArpeggioTool.apply(request, to: &project)
        return project
    }

    private func play() {
        error = nil
        do {
            let project = try candidate()
            let target = section ?? project.sections.first
            guard let target else { return }
            session.previewAssistant(project, wholeSong: section == nil, sectionID: target.id)
            playing = session.harmonyPreview
        } catch { self.error = error.localizedDescription }
    }
    private func restart() { if playing && session.harmonyPreview { play() } }
    private func stop() { if playing { session.endHarmonyPreview() }; playing = false }

    private func write() {
        stop(); error = nil
        guard let request else { return }
        var result: UUID?
        session.edit { result = try ArpeggioTool.apply(request, to: &$0) }
        guard let result, session.project.tracks.contains(where: { $0.id == result }) else {
            error = session.message; session.message = nil; return
        }
        session.showToast(NSLocalizedString("Arpeggio written as notes", comment: "Arpeggiator"))
        session.openNotes(result)
    }
}
