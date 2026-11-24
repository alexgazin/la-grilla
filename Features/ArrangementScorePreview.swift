import SwiftUI
import MusicDomain

struct ArrangementScorePreview: View {
    let brief: TrackBrief
    let session: Session
    let playingPart: Int?
    let canPreview: Bool
    let play: (Int) -> Void

    @State private var chart: ArrangementOverview?
    @State private var renderedBrief: TrackBrief?
    @State private var error: String?
    @State private var showSections = false
    @ScaledMetric(relativeTo: .caption) private var rowHeight: CGFloat = 25
    @ScaledMetric(relativeTo: .caption2) private var rulerHeight: CGFloat = 23

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                ScoreHeading(session: session)
                Spacer(minLength: 8)
                if let chart {
                    Text("\(chart.bars) bars").font(.caption.monospacedDigit()).foregroundStyle(Color.muted)
                    Button { showSections.toggle() } label: {
                        Image(systemName: showSections ? "chevron.up" : "list.bullet")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(StudioQuietButtonStyle())
                    .accessibilityLabel("Listen to section")
                    .accessibilityIdentifier("builder.score.sectionsMenu")
                }
            }
            if showSections, let chart {
                VStack(spacing: 0) {
                    ForEach(chart.sections, id: \.index) { section in
                        Button {
                            showSections = false
                            play(section.index)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: playingPart == section.index ? "stop.fill" : "play.fill")
                                    .foregroundStyle(Color.mint)
                                Text(verbatim: section.name)
                                Spacer()
                                Text(verbatim: "\(section.startBar + 1)–\(section.startBar + section.bars)")
                                    .foregroundStyle(Color.muted).monospacedDigit()
                            }
                            .padding(.horizontal, 8)
                            .frame(maxWidth: .infinity, minHeight: StudioMetrics.hitTarget, alignment: .leading)
                        }
                        .buttonStyle(StudioQuietButtonStyle())
                        .accessibilityLabel(Text(verbatim: section.name))
                        .accessibilityHint(sectionHint(section, tracks: chart.tracks))
                        .accessibilityIdentifier("builder.score.menu.\(section.index)")
                    }
                }
                .disabled(!canPreview || renderedBrief != brief)
            }
            if let chart {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: rulerHeight)
                        ForEach(chart.tracks, id: \.index) { track in
                            HStack(spacing: 5) {
                                Circle().fill(Color.track(track.role)).frame(width: 5, height: 5)
                                Text(verbatim: track.name).font(.caption2.weight(.medium)).lineLimit(2)
                            }
                            .foregroundStyle(Color.studioText)
                            .frame(maxWidth: .infinity, minHeight: rowHeight, maxHeight: rowHeight, alignment: .leading)
                        }
                    }
                    .frame(width: min(118, rowHeight * 3.6), alignment: .leading)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            ScorePlot(chart: chart, rulerHeight: rulerHeight, rowHeight: rowHeight,
                                      selected: playingPart)
                                .accessibilityHidden(true)
                            ScoreCursor(session: session, bars: chart.bars)
                                .accessibilityHidden(true).allowsHitTesting(false)
                            HStack(spacing: 0) {
                                ForEach(chart.sections, id: \.index) { section in
                                    let width = proxy.size.width * CGFloat(section.bars) / CGFloat(chart.bars)
                                    Button { play(section.index) } label: {
                                        Color.clear.frame(width: width, height: proxy.size.height)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(Text(verbatim: section.name))
                                    .accessibilityValue(LocalizedStringKey(playingPart == section.index ? "Playing" : "Stopped"))
                                    .accessibilityHint(sectionHint(section, tracks: chart.tracks))
                                    .accessibilityIdentifier("builder.score.section.\(section.index)")
                                }
                            }.disabled(!canPreview || renderedBrief != brief)
                        }
                    }
                }
                .frame(height: rulerHeight + CGFloat(chart.tracks.count) * rowHeight)
            } else if let error {
                Text(verbatim: error).font(.footnote).foregroundStyle(Color.record)
            } else {
                LoadingSkeleton(rows: 4, caption: "Preparing score…").font(.caption)
            }
        }
        .padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 12)
        .background(Color.panel)
        .task(id: brief) { await render(brief) }
    }

    private func sectionHint(_ section: ArrangementOverview.SectionSummary,
                             tracks: [ArrangementOverview.TrackSummary]) -> Text {
        let instruments = zip(tracks, section.lanes).compactMap { track, lane in
            lane.bins.contains { $0.level > 0 } ? track.name : nil
        }.joined(separator: ", ")
        return Text("Bars \(section.startBar + 1)–\(section.startBar + section.bars). \(instruments)")
    }

    private func render(_ value: TrackBrief) async {
        if renderedBrief == value { return }
        let build = Task.detached(priority: .userInitiated) { try ArrangementOverview.make(brief: value) }
        do {
            let result = try await withTaskCancellationHandler {
                try await build.value
            } onCancel: {
                build.cancel()
            }
            try Task.checkCancellation()
            chart=result; renderedBrief=value; error=nil
        } catch {
            guard !Task.isCancelled else { return }
            chart=nil; renderedBrief=nil; self.error=error.localizedDescription
        }
    }
}

private struct ScoreHeading: View {
    let session: Session
    var body: some View {
        Text("Score").font(.headline).foregroundStyle(Color.studioText)
            .accessibilityAddTraits(.isHeader)
            .accessibilityValue(Text(verbatim: session.runtimeTraceEnabled ? session.runtimeTraceReport : ""))
            .accessibilityIdentifier("builder.score.title")
    }
}

private struct ScoreCursor: View {
    let session: Session
    let bars: Int

    var body: some View {
        if session.harmonyPreview && session.audio.playing {
            GeometryReader { proxy in
                let fraction = max(0, min(1, session.audio.tick / Double(bars * barTicks)))
                let x = proxy.size.width * CGFloat(fraction)
                Rectangle().fill(Color.mint)
                    .frame(width: 1.5, height: proxy.size.height)
                    .position(x: x, y: proxy.size.height / 2)
                Circle().fill(Color.mint).frame(width: 5, height: 5)
                    .position(x: x, y: 3)
            }
            .clipped()
        }
    }
}

private struct ScorePlot: View {
    let chart: ArrangementOverview
    let rulerHeight: CGFloat
    let rowHeight: CGFloat
    let selected: Int?

    var body: some View {
        Canvas { context, size in
            let chartHeight = size.height - rulerHeight
            let unit = size.width / CGFloat(chart.bars)
            for section in chart.sections {
                let x = CGFloat(section.startBar) * unit
                let width = CGFloat(section.bars) * unit
                let area = CGRect(x: x, y: 0, width: width, height: size.height)
                if selected == section.index {
                    context.fill(Path(area), with: .color(Color.mint.opacity(0.12)))
                } else if section.index.isMultiple(of: 2) {
                    context.fill(Path(area), with: .color(Color.raised.opacity(0.52)))
                }
                context.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .color(.outline))
                if width >= 16 {
                    let bar = Text(verbatim: String(format: "%02d", section.startBar+1))
                        .font(.caption2.monospacedDigit()).foregroundColor(.muted)
                    context.draw(bar, at: CGPoint(x: x+3, y: rulerHeight/2), anchor: .leading)
                }
            }
            for (row, track) in chart.tracks.enumerated() {
                let top = rulerHeight + CGFloat(row) * rowHeight
                let baseline = CGRect(x: 0, y: top, width: size.width, height: 0.5)
                context.fill(Path(baseline), with: .color(.outline))
                let bounds = pitchBounds(row: row)
                let color = Color.track(track.role)
                for section in chart.sections {
                    let bins = section.lanes[row].bins
                    let cell = CGFloat(section.bars) * unit / CGFloat(bins.count)
                    let start = CGFloat(section.startBar) * unit
                    for (i, bin) in bins.enumerated() {
                        guard let low = bin.minimumPitch, let high = bin.maximumPitch else { continue }
                        let x = start + CGFloat(i) * cell
                        let y = top + 4 + (1 - CGFloat(high - bounds.lowerBound) / CGFloat(bounds.count)) * (rowHeight - 9)
                        let span = CGFloat(high - low) / CGFloat(bounds.count) * (rowHeight - 9)
                        let width = max(0.5, cell - min(0.75,cell * 0.15))
                        let mark = CGRect(x: x, y: y, width: width, height: max(2,span))
                        let alpha = (bin.onsets > 0 ? 0.58 : 0.34) + 0.4*bin.level
                        context.fill(Path(roundedRect: mark, cornerRadius: min(1,width / 2)), with: .color(color.opacity(alpha)))
                    }
                }
            }
            context.fill(Path(CGRect(x: 0, y: rulerHeight+chartHeight-0.5, width: size.width, height: 0.5)), with: .color(.outline))
        }
        .clipShape(RoundedRectangle(cornerRadius:6,style:.continuous))
    }

    private func pitchBounds(row: Int) -> ClosedRange<Int> {
        let bins = chart.sections.flatMap { $0.lanes[row].bins }
        let low = bins.compactMap(\.minimumPitch).min() ?? 60
        let high = bins.compactMap(\.maximumPitch).max() ?? low
        let pad = max(2, (7 - (high - low))/2)
        return (low-pad)...(high+pad)
    }
}
