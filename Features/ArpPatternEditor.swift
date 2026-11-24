import MusicDomain
import SwiftUI

/// I29 · Editing a custom arpeggio: rows are the held notes from the lowest, columns the steps.
/// A tap plays that note on the step, a second tap makes a rest; ↑ raises a step by an octave.
struct ArpPatternEditor: View {
    @Binding var text: String
    @Binding var libraryRaw: String
    @Environment(\.dismiss) private var dismiss
    @State private var pattern: ArpPattern
    @State private var naming = false
    @State private var newName = ""

    private static let rows = 4

    init(text: Binding<String>, libraryRaw: Binding<String>) {
        _text = text
        _libraryRaw = libraryRaw
        _pattern = State(initialValue: ArpPattern(name: "Custom", encoded: text.wrappedValue) ?? ArpPattern.presets[0])
    }

    private var library: ArpPatternLibrary { ArpPatternLibrary(stored: libraryRaw) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Rows are the held notes, the lowest at the bottom. Tap a cell to play that note on the step, tap it again for a rest. ↑ raises a step by an octave.")
                        .font(.subheadline).foregroundStyle(Color.muted)
                    Picker("Steps", selection: Binding(get: { pattern.steps.count }, set: { pattern.setLength($0) })) {
                        Text(verbatim: "8").tag(8)
                        Text(verbatim: "16").tag(16)
                    }
                    .pickerStyle(.segmented).accessibilityIdentifier("arp.length")
                    grid
                    Text(verbatim: pattern.encoded)
                        .font(.footnote.monospaced()).foregroundStyle(Color.muted)
                        .accessibilityIdentifier("arp.encoded")
                    presets
                }
                .padding(16)
            }
            .background(Color.ink)
            .navigationTitle("Arpeggio pattern").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { text = pattern.encoded; dismiss() }
                        .disabled(!pattern.plays).accessibilityIdentifier("arp.done")
                }
            }
            .alert("Save pattern", isPresented: $naming) {
                TextField("Name", text: $newName)
                Button("Save") {
                    var named = pattern
                    named.name = String(newName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
                    var next = library
                    if next.save(named) { libraryRaw = next.stored; pattern = named }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .tint(.mint)
    }

    private var grid: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach((0..<Self.rows).reversed(), id: \.self) { row in
                    HStack(spacing: 4) {
                        Text("Note \(row + 1)").font(.caption2.weight(.semibold)).foregroundStyle(Color.muted).frame(width: 52, alignment: .leading)
                        ForEach(pattern.steps.indices, id: \.self) { step in cell(step: step, row: row) }
                    }
                }
                HStack(spacing: 4) {
                    Text("Octave").font(.caption2.weight(.semibold)).foregroundStyle(Color.muted).frame(width: 52, alignment: .leading)
                    ForEach(pattern.steps.indices, id: \.self) { step in octave(step) }
                }
            }
        }
    }

    private func cell(step: Int, row: Int) -> some View {
        let on: Bool = {
            if case let .note(index, _) = pattern.steps[step] { return index == row }
            return false
        }()
        return Button { pattern.toggle(step: step, note: row); Luz.Haptics.selection() } label: {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(on ? Color.mint : (step % 4 == 0 ? Color.lifted : Color.raised))
                .frame(width: 32, height: 36)
        }
        .buttonStyle(StudioQuietButtonStyle(radius: 6, plate: false))
        .accessibilityLabel(Text("Step \(step + 1), note \(row + 1)"))
        .accessibilityValue(Text(LocalizedStringKey(on ? "On" : "Off")))
        .accessibilityIdentifier("arp.step.\(step).\(row)")
    }

    private func octave(_ step: Int) -> some View {
        let value: Int? = {
            if case let .note(_, octave) = pattern.steps[step] { return octave }
            return nil
        }()
        return Button { pattern.cycleOctave(step: step); Luz.Haptics.selection() } label: {
            Text(verbatim: value.map { $0 == 0 ? "·" : "↑\($0)" } ?? " ")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(value ?? 0 > 0 ? Color.mint : Color.muted)
                .frame(width: 32, height: 32)
                .background(Color.raised, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(StudioQuietButtonStyle(radius: 6, plate: false))
        .disabled(value == nil)
        .accessibilityLabel(Text("Octave of step \(step + 1)"))
        .accessibilityValue(Text(verbatim: "+\(value ?? 0)"))
        .accessibilityIdentifier("arp.octave.\(step)")
    }

    private var presets: some View {
        VStack(alignment: .leading, spacing: 8) {
            SmallHeading(text: "PATTERNS")
            ForEach(library.all) { item in
                HStack {
                    Button {
                        withAnimation(Luz.Motion.snap) { pattern = item }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(LocalizedStringKey(item.name)).font(.subheadline.weight(.semibold)).foregroundStyle(Color.studioText)
                            Text(verbatim: item.encoded).font(.caption2.monospaced()).foregroundStyle(Color.muted)
                        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("arp.preset.\(item.name)")
                    if !ArpPattern.presets.contains(where: { $0.name == item.name }) {
                        Button(role: .destructive) {
                            var next = library; next.remove(item.name); libraryRaw = next.stored
                        } label: { Image(systemName: "trash").frame(width: 44, height: 44) }
                        .accessibilityLabel(Text("Delete \(item.name)"))
                    }
                }
            }
            Button {
                newName = ""; naming = true
            } label: { Label("Save as my pattern", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity, minHeight: 44) }
            .buttonStyle(StudioActionStyle(color: .mint, prominent: false))
            .disabled(!pattern.plays)
            .accessibilityIdentifier("arp.save")
        }
    }
}
