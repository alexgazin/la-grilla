import SwiftUI
import MusicDomain

/// U6 · Turns structured project changes into one short history line.
enum HistoryText {
    private static func t(_ key: String) -> String { NSLocalizedString(key, comment: "Edit history") }
    private static func f(_ key: String, _ args: CVarArg...) -> String { String(format: t(key), locale: Locale.current, arguments: args) }

    static func line(_ changes: [ProjectChange]) -> String {
        guard let first = changes.first else { return t("No musical change") }
        let text = line(first)
        return changes.count > 1 ? text + " · " + f("+%lld more", changes.count - 1) : text
    }

    static func symbol(_ changes: [ProjectChange]) -> String {
        switch changes.first?.area {
        case .tempo: "metronome"
        case .key: "tuningfork"
        case .structure: "rectangle.split.3x1"
        case .harmony: "pianokeys"
        case .drums: "square.grid.2x2"
        case .layers: "square.3.layers.3d"
        case .bass: "waveform.path"
        case .melody: "music.note"
        case .mix: "slider.vertical.3"
        case .sound: "speaker.wave.2"
        case .takes: "record.circle"
        case .voice: "mic"
        case .project: "pencil"
        case nil: "circle"
        }
    }

    static func line(_ change: ProjectChange) -> String {
        let subject = change.subject ?? ""
        var text: String
        switch change.area {
        case .project: text = f("Renamed to %@", change.to ?? "")
        case .tempo: text = f("Tempo %@ → %@ BPM", change.from ?? "", change.to ?? "")
        case .key: text = f("Key %@ → %@", change.from ?? "", change.to ?? "")
        case .structure:
            switch change.kind {
            case .added: text = f("Section %@ added", subject)
            case .removed: text = f("Section %@ removed", subject)
            case .changed:
                if let from = change.from, let to = change.to, Int(from) != nil, Int(to) != nil { text = f("%@: %@ → %@ bars", subject, from, to) }
                else if let from = change.from, let to = change.to { text = f("Section %@ → %@", from, to) }
                else if change.subject != nil { text = f("%@: clips changed", subject) }
                else { text = t("Sections reordered") }
            }
        case .harmony, .drums, .melody, .bass:
            if let count = change.count {
                text = events(change, change.area == .harmony ? "Chords" : change.area == .drums ? "Hits" : "Notes", count)
            } else if change.area == .bass && change.subject == nil {
                text = t("Bass settings changed")
            } else {
                text = f(change.kind == .added ? "%@ track added" : change.kind == .removed ? "%@ track removed" : "%@ changed", subject)
            }
        case .layers:
            text = f(change.to == "muted" ? "%@ muted" : change.to == "unmuted" ? "%@ unmuted" : "Layers changed: %@", subject)
        case .mix: text = change.subject.map { f("Mix: %@", $0) } ?? t("Master changed")
        case .sound: text = f("Sound: %@", subject)
        case .takes:
            switch change.kind {
            case .added: text = f("Take %@ recorded", subject)
            case .removed: text = f("Take %@ deleted", subject)
            case .changed: text = f(change.to == "muted" ? "Take %@ muted" : "Take %@ unmuted", subject)
            }
        case .voice: text = t(change.kind == .removed ? "Voice recording removed" : "Voice recording added")
        }
        if let bar = change.bar { text += " · " + f("bar %lld", bar) }
        return text
    }

    private static func events(_ change: ProjectChange, _ noun: String, _ count: Int) -> String {
        let key = switch change.kind {
        case .added: noun + " added: %lld"
        case .removed: noun + " removed: %lld"
        case .changed: noun + " changed: %lld"
        }
        return (change.subject.map { $0 + " · " } ?? "") + f(key, count)
    }
}

/// One state in the visual history: earlier (Undo), the current one, or later (Redo).
private struct HistoryRow: Identifiable {
    enum Place: Hashable { case earlier(Int), current, later(Int) }
    let place: Place
    let state: Project
    let changes: [ProjectChange]
    var id: Place { place }
    var identifier: String {
        switch place {
        case .earlier(let index): "history.row.\(index)"
        case .current: "history.current"
        case .later(let index): "history.redo.\(index)"
        }
    }
}

struct HistoryView: View {
    @Bindable var session: Session
    @State private var selected: HistoryRow.Place?
    @State private var listening: HistoryRow.Place?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Newest first: undone states (farthest first), the current state, then earlier states.
    private var rows: [HistoryRow] {
        let earlier = session.history.earlierStates, later = session.history.laterStates, current = session.project
        var result: [HistoryRow] = []
        for (index, state) in later.enumerated().reversed() {
            let previous = index == 0 ? current : later[index - 1]
            result.append(HistoryRow(place: .later(index), state: state, changes: ProjectChanges.describe(from: previous, to: state)))
        }
        result.append(HistoryRow(place: .current, state: current,
                                 changes: earlier.last.map { ProjectChanges.describe(from: $0, to: current) } ?? []))
        for (index, state) in earlier.enumerated().reversed() {
            let changes = index > 0 ? ProjectChanges.describe(from: earlier[index - 1], to: state) : []
            result.append(HistoryRow(place: .earlier(index), state: state, changes: changes))
        }
        return result
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Tap a point to hear the song as it was. Return here replaces the project in one step; Redo brings everything back.")
                        .font(.caption).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
                    if rows.count == 1 {
                        Text("No edits yet in this session.").font(.callout).foregroundStyle(Color.studioText).padding(.vertical, 24)
                            .accessibilityIdentifier("history.empty")
                    }
                    ForEach(rows) { row in rowView(row) }
                }.padding(18)
            }
            .accessibilityIdentifier("history.scroll")
            .background(Color.ink)
            .navigationTitle("Edit history").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { stopListening(); session.sheet = nil }.accessibilityIdentifier("history.done") } }
        }
        .tint(.mint)
        .onDisappear { stopListening() }
        .onChange(of: session.harmonyPreview) { _, previewing in if !previewing { listening = nil } }
    }

    private func label(_ row: HistoryRow) -> String {
        switch row.place {
        case .current: return row.changes.isEmpty ? NSLocalizedString("Now", comment: "Edit history") : HistoryText.line(row.changes)
        case .earlier(0): return NSLocalizedString("Start of this session", comment: "Edit history")
        default: return HistoryText.line(row.changes)
        }
    }

    @ViewBuilder private func rowView(_ row: HistoryRow) -> some View {
        let isSelected = selected == row.place, isCurrent = row.place == .current
        let undone: Bool = { if case .later = row.place { return true }; return false }()
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(reduceMotion ? nil : Luz.Motion.snap) { selected = isSelected ? nil : row.place }
                Luz.Haptics.selection()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: HistoryText.symbol(row.changes)).font(.body).frame(width: 28).foregroundStyle(isCurrent ? Color.mint : Color.muted)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: label(row)).font(.subheadline.weight(isCurrent ? .semibold : .regular))
                            .foregroundStyle(undone ? Color.muted : Color.studioText).multilineTextAlignment(.leading)
                        HStack(spacing: 6) {
                            if isCurrent { Text("Current").foregroundStyle(Color.mint) }
                            if undone { Text("Undone") }
                            Text(row.state.modified, format: .relative(presentation: .named))
                        }.font(.caption).foregroundStyle(Color.muted)
                    }
                    Spacer(minLength: 0)
                    if listening == row.place { Image(systemName: "speaker.wave.2.fill").foregroundStyle(Color.mint).accessibilityLabel("Playing") }
                }
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(StudioQuietButtonStyle())
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityIdentifier(row.identifier)
            if isSelected {
                HStack(spacing: 10) {
                    Button { toggleListening(row) } label: {
                        Label(LocalizedStringKey(listening == row.place ? "Stop" : "Listen"), systemImage: listening == row.place ? "stop.fill" : "play.fill")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(StudioActionStyle(color: .mint, prominent: false)).accessibilityIdentifier("history.listen")
                    if !isCurrent {
                        Button { restore(row) } label: {
                            Label("Return here", systemImage: "clock.arrow.circlepath").frame(maxWidth: .infinity, minHeight: 44)
                        }.buttonStyle(StudioActionStyle()).accessibilityIdentifier("history.restore")
                            .disabled(session.recording || session.armed)
                    }
                }.transition(Luz.Transition.rise(reduceMotion))
            }
        }
        .padding(12)
        .background(isCurrent ? Color.mint.opacity(0.08) : Color.panel, in: RoundedRectangle(cornerRadius: Luz.Radius.card, style: .continuous))
    }

    private func toggleListening(_ row: HistoryRow) {
        if listening == row.place { stopListening(); return }
        session.previewSnapshot(row.state)
        listening = session.harmonyPreview ? row.place : nil
    }

    private func stopListening() { if listening != nil { session.endHarmonyPreview() }; listening = nil }

    private func restore(_ row: HistoryRow) {
        stopListening()
        switch row.place {
        case .earlier(let index): session.jumpHistory(session.history.earlierStates.count - index)
        case .later(let index): session.jumpHistory(-(index + 1))
        case .current: break
        }
        selected = .current
    }
}
