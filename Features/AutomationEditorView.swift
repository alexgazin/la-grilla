import MusicDomain
import SwiftUI

/// I37 · A track's level or pan over the song: tap to add a point, drag to move it, select to
/// delete. Each change is one Undo. Recording happens in the Mixer (● while playing).
struct AutomationEditorView: View {
    @Bindable var session: Session
    @Environment(\.dismiss) private var dismiss
    @State private var parameter: AutomationLane.Parameter = .level
    @State private var selected: Int?
    @State private var dragging: AutomationLane?

    private var trackIndex: Int? {
        session.project.tracks.firstIndex { $0.id == session.automationTrackID } ?? (session.project.tracks.isEmpty ? nil : 0)
    }
    private var track: Track? { trackIndex.map { session.project.tracks[$0] } }
    private var stored: AutomationLane? { track?.automation?.first { $0.parameter == parameter } }
    private var lane: AutomationLane? { dragging ?? stored }
    private var songLength: Int { max(barTicks, session.project.length) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Track", selection: Binding(get: { track?.id ?? UUID() }, set: { session.automationTrackID = $0; selected = nil })) {
                        ForEach(session.project.tracks.prefix(masterBus)) { item in Text(verbatim: item.displayName).tag(item.id) }
                    }
                    .accessibilityIdentifier("automation.track")
                    Picker("Parameter", selection: $parameter) {
                        ForEach(AutomationLane.Parameter.allCases, id: \.self) { item in Text(LocalizedStringKey(item.title)).tag(item) }
                    }
                    .pickerStyle(.segmented).accessibilityIdentifier("automation.parameter")
                    .onChange(of: parameter) { _, _ in selected = nil }
                    chart.frame(height: 220)
                    Text("Tap the chart to add a point, drag a point to move it. To record, turn on ● in the Mixer and move a fader or pan while the song plays.")
                        .font(.footnote).foregroundStyle(Color.muted)
                    if let selected, let lane, lane.points.indices.contains(selected) {
                        HStack {
                            Text(verbatim: "\(MarkerEditing.position(lane.points[selected].tick)) · \(format(lane.points[selected].value))")
                                .font(.subheadline.monospacedDigit()).foregroundStyle(Color.studioText)
                                .accessibilityIdentifier("automation.selected")
                            Spacer()
                            Button("Delete point", role: .destructive) { delete(selected) }
                                .accessibilityIdentifier("automation.delete-point")
                        }
                    }
                    pointList
                    Button(role: .destructive) { clear() } label: {
                        Label("Clear this lane", systemImage: "trash").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(StudioActionStyle(color: .record, prominent: false))
                    .disabled(stored == nil)
                    .accessibilityIdentifier("automation.clear")
                }
                .padding(16)
            }
            .background(Color.ink)
            .navigationTitle("Automation").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .tint(.mint)
    }

    private func format(_ value: Double) -> String {
        parameter == .level ? String(format: "%.1f dB", value) : (abs(value) < 0.01 ? "C" : value < 0 ? "L\(Int((-value * 50).rounded()))" : "R\(Int((value * 50).rounded()))")
    }

    private func x(_ tick: Int, _ width: CGFloat) -> CGFloat { CGFloat(tick) / CGFloat(songLength) * width }
    private func y(_ value: Double, _ height: CGFloat) -> CGFloat {
        let range = parameter.range
        return (1 - CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))) * height
    }
    private func tick(_ x: CGFloat, _ width: CGFloat) -> Int {
        let raw = Int((x / max(1, width)) * CGFloat(songLength))
        return min(songLength - 1, max(0, raw / 120 * 120))
    }
    private func value(_ y: CGFloat, _ height: CGFloat) -> Double {
        let range = parameter.range
        let fraction = 1 - Double(min(max(0, y), height) / max(1, height))
        let raw = range.lowerBound + fraction * (range.upperBound - range.lowerBound)
        return parameter == .level ? (raw * 2).rounded() / 2 : (raw * 50).rounded() / 50
    }

    private var chart: some View {
        GeometryReader { proxy in
            let width = proxy.size.width, height = proxy.size.height
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.raised)
                // Bars.
                Path { path in
                    for bar in stride(from: 0, through: songLength, by: barTicks) {
                        let position = x(bar, width)
                        path.move(to: CGPoint(x: position, y: 0)); path.addLine(to: CGPoint(x: position, y: height))
                    }
                }.stroke(Color.outline.opacity(0.4), lineWidth: 0.5)
                if let lane, let first = lane.points.first, let last = lane.points.last {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: y(first.value, height)))
                        for point in lane.points { path.addLine(to: CGPoint(x: x(point.tick, width), y: y(point.value, height))) }
                        path.addLine(to: CGPoint(x: width, y: y(last.value, height)))
                    }.stroke(Color.mint, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                    ForEach(Array(lane.points.enumerated()), id: \.offset) { index, point in
                        Circle().fill(selected == index ? Color.studioText : Color.mint)
                            .frame(width: 18, height: 18)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                            .position(x: x(point.tick, width), y: y(point.value, height))
                            .gesture(DragGesture(minimumDistance: 0)
                                .onChanged { drag in
                                    guard var moving = dragging ?? stored else { return }
                                    AutomationEditing.move(&moving, index: index, tick: tick(drag.location.x, width), value: value(drag.location.y, height))
                                    dragging = moving; selected = index
                                }
                                .onEnded { _ in if let dragging { commit(dragging) }; dragging = nil })
                            .accessibilityHidden(true)
                    }
                } else {
                    Text("No movement yet").font(.caption).foregroundStyle(Color.muted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                // Playhead.
                Rectangle().fill(Color.studioText.opacity(0.5)).frame(width: 1, height: height)
                    .offset(x: x(Int(session.audio.tick) % songLength, width))
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { location in add(tick: tick(location.x, width), value: value(location.y, height)) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Automation chart"))
            .accessibilityAction(named: Text("Add a point at the playhead")) {
                add(tick: min(songLength - 1, Int(session.audio.tick) / 120 * 120), value: lane?.value(at: Int(session.audio.tick)) ?? 0)
            }
            .accessibilityIdentifier("automation.chart")
        }
    }

    private var pointList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array((lane?.points ?? []).enumerated()), id: \.offset) { index, point in
                Button { selected = index } label: {
                    HStack {
                        Text(verbatim: "\(index + 1)").foregroundStyle(Color.muted).frame(width: 24, alignment: .leading)
                        Text(verbatim: MarkerEditing.position(point.tick)).monospacedDigit()
                        Spacer()
                        Text(verbatim: format(point.value)).monospacedDigit()
                    }.font(.footnote).foregroundStyle(Color.studioText).frame(minHeight: 32)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("automation.point.\(index)")
            }
        }
    }

    private func write(_ change: @escaping (inout [AutomationLane]) -> Void) {
        guard let id = track?.id else { return }
        session.edit { p in
            guard let i = p.tracks.firstIndex(where: { $0.id == id }) else { return }
            var lanes = p.tracks[i].automation ?? []
            change(&lanes)
            lanes.removeAll { $0.points.isEmpty }
            p.tracks[i].automation = lanes.isEmpty ? nil : lanes
        }
    }

    private func commit(_ lane: AutomationLane) {
        write { lanes in lanes.removeAll { $0.parameter == lane.parameter }; lanes.append(lane) }
    }

    private func add(tick: Int, value: Double) {
        var next = stored ?? AutomationLane(parameter: parameter, points: [])
        guard AutomationEditing.set(&next, tick: tick, value: value) else { return }
        commit(next)
        selected = next.points.firstIndex { $0.tick == tick }
        Luz.Haptics.selection()
    }

    private func delete(_ index: Int) {
        guard var next = stored, next.points.indices.contains(index) else { return }
        next.points.remove(at: index)
        let parameter = parameter
        write { lanes in lanes.removeAll { $0.parameter == parameter }; if !next.points.isEmpty { lanes.append(next) } }
        selected = nil
    }

    private func clear() {
        let parameter = parameter
        write { lanes in lanes.removeAll { $0.parameter == parameter } }
        selected = nil
    }
}
