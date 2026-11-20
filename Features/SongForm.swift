import SwiftUI
import UIKit
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
            .clipShape(RoundedRectangle(cornerRadius:5,style:.continuous))
        }
        .frame(height: 12)
        .accessibilityHidden(true)
    }
}

@MainActor enum SongFormStyle {
    static let choices: [(index: Int, color: Color, name: LocalizedStringKey)] = [(0, .harmony, "Amber"), (1, .drums, "Lavender"), (2, .bass, "Teal"), (3, .mint, "Mint")]
    static func color(for section: MusicDomain.Section) -> Color {
        if let chosen = section.color, let choice = choices.first(where: { $0.index == chosen }) { return choice.color }
        // Familiar section names share a color in the editor and Assistant.
        let kind = section.name.lowercased().split(whereSeparator: \.isWhitespace).first
        switch kind {
        case "verse", "куплет": return .harmony
        case "chorus", "припев": return .drums
        case "bridge", "бридж": return .bass
        case "intro", "outro", "вступление", "финал": return .mint
        default: break
        }
        switch section.id.uuid.0 % 4 {
        case 0: return .harmony
        case 1: return .drums
        case 2: return .bass
        default: return .mint
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
        .background(Color.panel, in: RoundedRectangle(cornerRadius:StudioMetrics.controlRadius,style:.continuous))
        .contentShape(Rectangle())
    }
}

struct SongFormLane: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Bindable var session: Session
    let editingLocked: Bool
    @State private var drag: CardDrag?

    private struct CardDrag {
        let payload: ArrangementDragPayload
        let translation: CGSize
        let target: UUID?
    }

    var body: some View {
        GeometryReader { geometry in
            let bars = max(1, session.project.length / barTicks)
            let barWidth = min(76, max(48, geometry.size.width / CGFloat(bars)))
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(session.project.sections) { section in
                        let width = barWidth * CGFloat(section.length / barTicks)
                        card(section, width: width, barWidth: barWidth)
                            .frame(width: width)
                            .zIndex(drag?.payload.objectID == section.id ? 1 : 0)
                    }
                }
                .padding(.bottom, 8)
            }
            .accessibilityIdentifier("sections.timeline")
        }
        .frame(height: typeSize.isAccessibilitySize ? 166 : 104)
        .onChange(of: editingLocked) { _, locked in if locked { drag = nil } }
        .onDisappear { drag = nil }
    }

    private func card(_ section: MusicDomain.Section, width: CGFloat, barWidth: CGFloat) -> some View {
        let selected = section.id == session.selectedSection
        let color = SongFormStyle.color(for: section)
        let moving = drag?.payload.objectID == section.id
        let highlighted = selected || drag?.target == section.id
        let payload = ArrangementDragPayload(project: session.project, sectionID: section.id)
        return Button { session.select(section) } label: {
            VStack(alignment: .leading, spacing: 4) {
                if width >= 84 {
                    Text(verbatim: String(format: "%02d", section.start / barTicks + 1))
                        .font(.caption.monospacedDigit()).foregroundStyle(color)
                        .frame(maxWidth: .infinity, minHeight: 36, alignment: .trailing)
                } else {
                    Color.clear.frame(height: 36).accessibilityHidden(true)
                }
                Text(section.name).font(.headline).lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                    .foregroundStyle(Color.studioText)
                Text("\(section.length / barTicks) bars").font(.caption.monospacedDigit())
                    .lineLimit(1).foregroundStyle(Color.muted)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, minHeight: typeSize.isAccessibilitySize ? 158 : 96, alignment: .topLeading)
            .background(Color.panel, in: RoundedRectangle(cornerRadius:StudioMetrics.controlRadius,style:.continuous))
            .overlay {
                RoundedRectangle(cornerRadius:StudioMetrics.controlRadius,style:.continuous)
                    .strokeBorder(highlighted || moving ? Color.mint : Color.outline,
                                  lineWidth: highlighted || moving ? 2 : 1)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(StudioQuietButtonStyle())
        .disabled(editingLocked)
        .accessibilityIdentifier("sections.card.\(section.id)")
        .accessibilityLabel(section.name)
        .accessibilityValue(Text("Bars \(section.start / barTicks + 1)–\((section.start + section.length) / barTicks)"))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .offset(x: moving ? drag?.translation.width ?? 0 : 0)
        // Leave the input surface at its original position until release.
        .overlay(alignment: .topLeading) {
            ZStack {
                Image(systemName: "line.3.horizontal").foregroundStyle(color)
                    .offset(x: moving ? drag?.translation.width ?? 0 : 0)
                    .allowsHitTesting(false)
                SongFormDragGrip(enabled: !editingLocked) { event in
                    handle(event, section: section, payload: payload, pointsPerBar: barWidth)
                }
            }
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 2)
    }

    private func handle(_ event: SongFormDragGrip.Event, section: MusicDomain.Section,
                        payload: ArrangementDragPayload, pointsPerBar: CGFloat) {
        switch event {
        case .changed(let translation):
            if drag?.payload.objectID != section.id {
                drag = CardDrag(payload: payload, translation: .zero, target: nil)
            }
            guard let source = drag?.payload else { return }
            drag = CardDrag(payload: source, translation: translation,
                            target: target(for: section, translation: translation, pointsPerBar: pointsPerBar))
        case .ended(let translation):
            let source = drag?.payload
            drag = nil
            if let source, source.objectID == section.id,
               let target = target(for: section, translation: translation, pointsPerBar: pointsPerBar) {
                session.reorderSection(drop: [source.encoded()], onto: target)
            }
        case .cancelled:
            drag = nil
        }
    }

    private func target(for section: MusicDomain.Section, translation: CGSize, pointsPerBar: CGFloat) -> UUID? {
        guard !editingLocked, abs(translation.height) < 90, translation.width.isFinite else { return nil }
        let local = CGFloat(section.start / barTicks) + (24 + translation.width) / pointsPerBar
        let bar = min(max(0, Int(local.rounded(.down))), session.project.length / barTicks - 1)
        return session.project.sections.first { $0.start <= bar * barTicks && bar * barTicks < $0.start + $0.length }?.id
    }
}

/// Local reordering uses a grip, independent of iOS's file drag/drop service.
private struct SongFormDragGrip: UIViewRepresentable {
    enum Event { case changed(CGSize), ended(CGSize), cancelled }
    let enabled: Bool
    let emit: (Event) -> Void

    func makeUIView(context: Context) -> GripView { GripView(frame: .zero) }

    func updateUIView(_ view: GripView, context: Context) {
        view.emit = emit
        view.isUserInteractionEnabled = enabled
    }

    final class GripView: UIView {
        var emit: ((Event) -> Void)?
        private let pan = UIPanGestureRecognizer()

        override init(frame: CGRect) {
            super.init(frame: frame)
            isAccessibilityElement = false
            pan.maximumNumberOfTouches = 1
            pan.addTarget(self, action: #selector(handlePan))
            addGestureRecognizer(pan)
        }

        required init?(coder: NSCoder) { return nil }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            var ancestor = superview
            while let view = ancestor {
                if let scroll = view as? UIScrollView {
                    // Only a touch that begins on a grip takes precedence over scrolling.
                    scroll.panGestureRecognizer.require(toFail: pan)
                }
                ancestor = view.superview
            }
        }

        @objc private func handlePan() {
            let offset = pan.translation(in: window)
            let translation = CGSize(width: offset.x, height: offset.y)
            switch pan.state {
            case .began, .changed: emit?(.changed(translation))
            case .ended: emit?(.ended(translation))
            case .cancelled, .failed: emit?(.cancelled)
            default: break
            }
        }
    }
}
