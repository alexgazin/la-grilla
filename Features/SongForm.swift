import SwiftUI
import MusicDomain

/// Projects straight from the ordered sections used by the sequencer and Assistant.
struct SongFormOverview: View {
    let sections: [MusicDomain.Section]
    var selectedID: UUID? = nil

    var body: some View {
        GeometryReader { geometry in
            let length = max(1, sections.reduce(0) { $0 + $1.length })
            HStack(spacing: 0) {
                ForEach(sections) { section in
                    Rectangle()
                        .fill(SongFormStyle.color(for: section).opacity(selectedID == nil || selectedID == section.id ? 0.9 : 0.56))
                        .overlay(alignment: .leading) {
                            if section.start != 0 {
                                Rectangle().fill(Color.ink).frame(width: 1)
                            }
                        }
                        .frame(width: geometry.size.width * CGFloat(section.length) / CGFloat(length))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .frame(height: 12)
        .accessibilityHidden(true)
    }
}

enum SongFormStyle {
    static func color(for section: MusicDomain.Section) -> Color {
        // Keep a section's accent stable when it moves or is renamed.
        switch section.id.uuid.0 % 4 {
        case 0: .harmony
        case 1: .drums
        case 2: .bass
        default: .mint
        }
    }
}

struct SongFormLegend: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let sections: [MusicDomain.Section]
    var actions: ((MusicDomain.Section) -> Void)? = nil
    var editingLocked = false

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top),
                            count: typeSize.isAccessibilitySize ? 1 : 2)
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(sections) { section in
                if let actions {
                    Button { actions(section) } label: {
                        label(section, hasActions: true)
                    }
                    .buttonStyle(StudioQuietButtonStyle())
                    .disabled(editingLocked)
                    .accessibilityLabel(section.name)
                    .accessibilityValue(Text("Bars \(section.start / barTicks + 1)–\((section.start + section.length) / barTicks)"))
                    .accessibilityHint("Section actions")
                    .accessibilityIdentifier("section.menu.\(section.id)")
                } else {
                    label(section, hasActions: false)
                }
            }
        }
    }

    private func label(_ section: MusicDomain.Section, hasActions: Bool) -> some View {
        HStack(spacing: 8) {
            Capsule().fill(SongFormStyle.color(for: section)).frame(width: 3, height: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(section.name).font(.subheadline.weight(.semibold))
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                Text("Bars \(section.start / barTicks + 1)–\((section.start + section.length) / barTicks)")
                    .font(.caption.monospacedDigit()).foregroundStyle(Color.muted)
            }
            Spacer(minLength: 0)
            if hasActions {
                Image(systemName: "ellipsis").foregroundStyle(Color.muted).accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .background(Color.panel, in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
    }
}

struct SongFormLane: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Bindable var session: Session
    let editingLocked: Bool
    @State private var dropTarget: UUID?

    var body: some View {
        GeometryReader { geometry in
            let bars = max(1, session.project.length / barTicks)
            let barWidth = min(76, max(48, geometry.size.width / CGFloat(bars)))
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(session.project.sections) { section in
                        card(section)
                            .frame(width: barWidth * CGFloat(section.length / barTicks))
                    }
                }
                .padding(.bottom, 8)
            }
            .accessibilityIdentifier("sections.timeline")
        }
        .frame(height: typeSize.isAccessibilitySize ? 158 : 96)
    }

    private func card(_ section: MusicDomain.Section) -> some View {
        let selected = section.id == session.selectedSection
        let color = SongFormStyle.color(for: section)
        let payload = ArrangementDragPayload(project: session.project, sectionID: section.id)
        return Button { session.select(section) } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: String(format: "%02d", section.start / barTicks + 1))
                    .font(.caption.monospacedDigit()).foregroundStyle(color)
                Text(section.name).font(.headline).lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                    .foregroundStyle(Color.studioText)
                Text("\(section.length / barTicks) bars").font(.caption.monospacedDigit())
                    .foregroundStyle(Color.muted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: typeSize.isAccessibilitySize ? 150 : 88, alignment: .leading)
            .background(Color.panel, in: RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .top) {
                Capsule().fill(color).frame(height: 2).padding(.horizontal, 10).padding(.top, 2)
                    .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(dropTarget == section.id || selected ? Color.mint : Color.outline,
                                  lineWidth: dropTarget == section.id || selected ? 2 : 1)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(StudioQuietButtonStyle())
        .disabled(editingLocked)
        .padding(.horizontal, 2)
        .accessibilityIdentifier("sections.card.\(section.id)")
        .accessibilityLabel(section.name)
        .accessibilityValue(Text("Bars \(section.start / barTicks + 1)–\((section.start + section.length) / barTicks)"))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .modifier(ArrangementDragSource(payload: editingLocked ? nil : payload.encoded()))
        .dropDestination(for: String.self) { items, _ in
            session.reorderSection(drop: items, onto: section.id)
        } isTargeted: { targeted in
            if targeted && !editingLocked { dropTarget = section.id }
            else if dropTarget == section.id { dropTarget = nil }
        }
    }
}
