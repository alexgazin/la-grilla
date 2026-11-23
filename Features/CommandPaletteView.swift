import SwiftUI
import MusicDomain

/// U4 · "What to do?" — type an action in Russian or English (typos and the wrong
/// keyboard layout are fine), with values like "темп 92" or "в ля минор".
struct CommandPaletteView: View {
    @Bindable var session: Session
    @State private var query = ""
    @FocusState private var focused: Bool
    @AppStorage(CommandMemory.pinnedKey) private var pinnedRaw = ""

    private var matches: [CommandMatch] {
        let found = CommandMatcher.rank(query, recent: CommandMemory.recent)
        if query.trimmingCharacters(in: .whitespaces).isEmpty && found.isEmpty {
            return [CommandID.play, .undo, .history, .versions, .export].map { CommandMatch(command: $0, argument: nil, score: 0) }
        }
        return found
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Color.muted).accessibilityHidden(true)
                    TextField("What to do? Try “tempo 92” or “add chorus”", text: $query)
                        .focused($focused).submitLabel(.go).autocorrectionDisabled().textInputAutocapitalization(.never)
                        .onSubmit { if let first = matches.first { run(first) } }
                        .accessibilityIdentifier("commands.field")
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.muted) }
                            .accessibilityLabel("Clear").frame(minWidth: 44, minHeight: 44)
                    }
                }
                .padding(.horizontal, 12).frame(minHeight: 48)
                .background(Color.raised, in: RoundedRectangle(cornerRadius: Luz.Radius.cell, style: .continuous))
                Text(query.isEmpty ? "Recent and suggested" : "Best matches").font(.caption.weight(.semibold)).foregroundStyle(Color.muted)
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(Array(matches.enumerated()), id: \.offset) { index, match in row(match, index: index) }
                        if matches.isEmpty {
                            Text("Nothing found. Try other words, for example “record”, “mixer” or “key A minor”.")
                                .font(.callout).foregroundStyle(Color.muted).padding(.vertical, 20).accessibilityIdentifier("commands.empty")
                        }
                    }
                }
                Text("Touch and hold an action to pin it to the quick bar (up to four).").font(.caption).foregroundStyle(Color.muted)
            }
            .padding(16)
            .background(Color.ink)
            .navigationTitle("Search actions").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { session.sheet = nil }.accessibilityIdentifier("commands.close") } }
        }
        .tint(.mint)
        .onAppear { focused = true }
        .presentationDetents([.medium, .large])
    }

    private func detail(_ argument: CommandArgument?) -> String? {
        switch argument {
        case .bpm(let value)?: return "\(value) BPM"
        case .key(let root, let minor)?: return Chord.roots[root] + " " + NSLocalizedString(minor ? "minor" : "major", comment: "Key mode")
        case .semitones(let value)?: return String(format: NSLocalizedString("%@ semitones", comment: "Command"), value > 0 ? "+\(value)" : "\(value)")
        case .name(let value)?: return NSLocalizedString(value, comment: "Section name")
        case nil: return nil
        }
    }

    private func row(_ match: CommandMatch, index: Int) -> some View {
        let descriptor = CommandCatalog.descriptor(match.command)
        let pinned = CommandMemory.pinned(pinnedRaw).contains(match.command)
        return Button { run(match) } label: {
            HStack(spacing: 12) {
                Image(systemName: descriptor.symbol).frame(width: 28).foregroundStyle(index == 0 ? Color.mint : Color.muted).accessibilityHidden(true)
                Text(LocalizedStringKey(descriptor.title)).font(.body.weight(index == 0 ? .semibold : .regular))
                if let detail = detail(match.argument) {
                    Text(verbatim: detail).font(.body.monospacedDigit()).foregroundStyle(Color.mint)
                }
                Spacer(minLength: 0)
                if pinned { Image(systemName: "pin.fill").font(.caption).foregroundStyle(Color.muted).accessibilityLabel("Pinned") }
                if index == 0 { Image(systemName: "return").font(.caption).foregroundStyle(Color.muted).accessibilityHidden(true) }
            }
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading).padding(.horizontal, 10).contentShape(Rectangle())
            .background(index == 0 ? Color.mint.opacity(0.08) : Color.panel, in: RoundedRectangle(cornerRadius: Luz.Radius.cell, style: .continuous))
        }
        .buttonStyle(StudioQuietButtonStyle())
        .contextMenu {
            Button(pinned ? "Unpin from quick bar" : "Pin to quick bar", systemImage: pinned ? "pin.slash" : "pin") {
                pinnedRaw = CommandMemory.toggled(match.command, in: pinnedRaw)
            }.disabled(!pinned && CommandMemory.pinned(pinnedRaw).count >= CommandMemory.pinnedLimit)
        }
        .accessibilityIdentifier("commands.row.\(index)")
        .accessibilityAction(named: Text(pinned ? "Unpin from quick bar" : "Pin to quick bar")) { pinnedRaw = CommandMemory.toggled(match.command, in: pinnedRaw) }
    }

    private func run(_ match: CommandMatch) {
        session.sheet = nil
        session.run(match.command, match.argument)
    }
}

/// U13 · Up to four pinned actions above the transport, one touch each.
struct QuickBar: View {
    @Bindable var session: Session
    @AppStorage(CommandMemory.pinnedKey) private var pinnedRaw = ""
    var body: some View {
        let pinned = CommandMemory.pinned(pinnedRaw)
        if !pinned.isEmpty {
            HStack(spacing: 6) {
                ForEach(Array(pinned.enumerated()), id: \.element) { index, id in
                    let descriptor = CommandCatalog.descriptor(id)
                    Button { session.run(id) } label: {
                        Label(LocalizedStringKey(descriptor.title), systemImage: descriptor.symbol)
                            .font(.caption.weight(.medium)).lineLimit(1).minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .buttonStyle(StudioActionStyle(color: .mint, prominent: false))
                    .contextMenu { Button("Unpin from quick bar", systemImage: "pin.slash") { pinnedRaw = CommandMemory.toggled(id, in: pinnedRaw) } }
                    .accessibilityIdentifier("quickbar.\(index)")
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 4)
            .accessibilityElement(children: .contain).accessibilityIdentifier("quickbar")
        }
    }
}
