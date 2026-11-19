import SwiftUI
import MusicDomain

/// Build 45 review of an edit described in words: the parsed operations, the
/// parts that stay as they are, highlighted score cells, problems with their
/// fragment, choices for an ambiguous target, A/B from one place and Apply.
struct SongEditReview: View {
    @Bindable var session: Session
    let plan: SongEditPlan
    let source: Project
    let candidate: Project?
    let choose: (Int) -> Void
    let recalculate: () -> Void
    let apply: () -> Void
    @State private var previewB = false

    private var stale: Bool { session.project.id != plan.projectID || session.project.revision != plan.baseRevision }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SmallHeading(text: "EDIT PLAN")
            Text("Built locally from your words. Nothing changes until you apply.")
                .font(.caption).foregroundStyle(Color.muted).accessibilityIdentifier("assistant.edit.provenance")
            ForEach(Array(plan.operations.enumerated()), id: \.offset) { index, op in
                Label(op.summary(in: source), systemImage: icon(op.kind))
                    .font(.subheadline).padding(12).frame(maxWidth: .infinity, alignment: .leading).modifier(StudioSurface())
                    .accessibilityIdentifier("assistant.edit.op.\(index)")
            }
            if !keptNames.isEmpty {
                Label(String(format: NSLocalizedString("Kept unchanged: %@", comment: "Song edit"), keptNames.joined(separator: ", ")), systemImage: "lock")
                    .font(.caption).foregroundStyle(Color.mint).accessibilityIdentifier("assistant.edit.protected")
            }
            ForEach(Array(plan.problems.enumerated()), id: \.offset) { index, problem in
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "«\(problem.fragment)»").font(.callout.weight(.semibold)).foregroundStyle(Color.record)
                    Text(LocalizedStringKey(reason(problem.reason))).font(.caption).foregroundStyle(Color.muted)
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading).modifier(StudioSurface())
                    .accessibilityElement(children: .combine).accessibilityIdentifier("assistant.edit.problem.\(index)")
            }
            if !plan.problems.isEmpty {
                Text("Your text is kept as a draft. Change the highlighted part and review again.")
                    .font(.caption).foregroundStyle(Color.muted)
            }
            if plan.needsClarification {
                Text("Which one do you mean?").font(.subheadline.weight(.semibold))
                ForEach(Array(plan.choices.enumerated()), id: \.offset) { index, choice in
                    Button { choose(index) } label: {
                        Text(verbatim: choice.label).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }.buttonStyle(.bordered).accessibilityIdentifier("assistant.edit.choice.\(index)")
                }
            }
            if plan.isApplicable, let candidate {
                ScoreCells(project: source, cells: Set(plan.affectedCells(in: source)))
                diffSummary(candidate)
                if stale {
                    Label("The project changed after this plan was made.", systemImage: "exclamationmark.arrow.circlepath")
                        .font(.caption).foregroundStyle(Color.harmony)
                    Button("Recalculate", action: recalculate).buttonStyle(.bordered).frame(minHeight: 44)
                        .accessibilityIdentifier("assistant.edit.recalculate")
                } else {
                    HStack(spacing: 10) {
                        Button { previewB = false; audition(source) } label: {
                            Text("A · Original").frame(maxWidth: .infinity, minHeight: 48)
                                .background(session.harmonyPreview && !previewB ? Color.mint.opacity(0.2) : Color.raised, in: RoundedRectangle(cornerRadius: 10))
                        }.accessibilityIdentifier("assistant.a")
                        Button { previewB = true; audition(candidate) } label: {
                            Text("B · Proposal").frame(maxWidth: .infinity, minHeight: 48)
                                .background(session.harmonyPreview && previewB ? Color.mint.opacity(0.2) : Color.raised, in: RoundedRectangle(cornerRadius: 10))
                        }.accessibilityIdentifier("assistant.b")
                    }
                    Text(String(format: NSLocalizedString("Both versions play bars %d–%d at the same level.", comment: "Song edit audition"), window.lowerBound / barTicks + 1, window.upperBound / barTicks))
                        .font(.caption).foregroundStyle(Color.muted).accessibilityIdentifier("assistant.edit.window")
                    if session.harmonyPreview { Button("Stop preview") { session.endHarmonyPreview() }.frame(minHeight: 44).accessibilityIdentifier("assistant.stop-preview") }
                    Button(action: apply) { Text("Apply proposal") }.buttonStyle(StudioActionStyle()).accessibilityIdentifier("assistant.apply")
                    Text("One Undo restores the whole change.").font(.caption).foregroundStyle(Color.muted)
                }
            }
        }
    }

    private var keptNames: [String] {
        var names = plan.protectedTracks.compactMap { id in source.tracks.first { $0.id == id }?.displayName }
        for kept in plan.protectedPads {
            names += (kept.pads ?? []).map { NSLocalizedString(Compiler.padNames[$0], comment: "Drum pad") }
        }
        return names
    }

    /// From the bar before the first change to one bar after the last, so a
    /// fill is heard together with the section boundary it leads into.
    private var window: Range<Int> {
        let edited = plan.operations.flatMap { ($0.kind == .fill || $0.kind == .stopBreak) ? [$0.bars.upperBound - 1] : $0.editedBars }
        let lower = max(0, (edited.min() ?? 0) - 1), upper = min(source.length / barTicks, (edited.max() ?? 0) + 2)
        return lower * barTicks..<max(lower + 1, upper) * barTicks
    }

    private func audition(_ project: Project) {
        guard let section = project.sections.first(where: { $0.start <= window.lowerBound && $0.start + $0.length > window.lowerBound }) else { return }
        session.previewAssistant(project, wholeSong: false, sectionID: section.id, rangeOverride: window, loopOverride: true)
    }

    private func diffSummary(_ candidate: Project) -> some View {
        let rows: [String] = Self.differenceRows(source: source, candidate: candidate)
        return VStack(alignment: .leading, spacing: 4) {
            SmallHeading(text: "MIDI DIFFERENCE")
            if rows.isEmpty { Text("No audible change.").font(.caption).foregroundStyle(Color.harmony) }
            ForEach(rows, id: \.self) { Text(verbatim: $0).font(.caption.monospaced()) }
        }.accessibilityElement(children: .combine).accessibilityIdentifier("assistant.edit.diff")
    }

    static func differenceRows(source: Project, candidate: Project) -> [String] {
        let diff = SongEditDiff(before: source, after: candidate)
        let format = NSLocalizedString("%@: +%lld / −%lld notes", comment: "Song edit MIDI difference")
        var rows: [String] = []
        for track in candidate.tracks {
            let events = diff.events(on: track.id)
            let added: Int = events.added.count
            let removed: Int = events.removed.count
            if added == 0 && removed == 0 { continue }
            rows.append(String(format: format, track.displayName, Int64(added), Int64(removed)))
        }
        return rows
    }

    private func icon(_ kind: SongEditOperation.Kind) -> String {
        switch kind {
        case .remove: "minus.circle"
        case .fill: "drum"
        case .denser: "plus.circle"
        case .sparser: "circle.dotted"
        case .arpeggiate: "arrow.up.and.down.text.horizontal"
        case .hook: "music.quarternote.3"
        case .stopBreak: "pause.circle"
        case .humanize: "hand.raised"
        case .swing: "metronome"
        case .scaleShift: "arrow.up.arrow.down"
        case .bassFromKick: "waveform.path"
        case .reharmonize: "pianokeys"
        case .duplicateSection: "plus.square.on.square"
        case .delay: "clock.arrow.circlepath"
        case .fadeIn: "speaker.wave.1"
        case .fadeOut: "speaker.slash"
        }
    }

    private func reason(_ reason: SongEditProblem.Reason) -> String {
        switch reason {
        case .unsupported: "This part of the request is not supported yet."
        case .contradiction: "This keeps and changes the same part. Choose one."
        case .missing: "This part, section or bar is not in the song."
        case .noBarBefore: "There is no bar before the start of the song."
        case .derivedBass: "The bass is built from the chords, so this would change the bass you asked to keep."
        case .trackLimit: "A project can contain up to eight tracks."
        case .silent: "This part does not play there, so nothing would change."
        }
    }
}

/// Track × section overview with the cells the plan touches highlighted.
private struct ScoreCells: View {
    let project: Project
    let cells: Set<SongEditCell>
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SmallHeading(text: "AFFECTED CELLS")
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 3) {
                    ScoreHeaderRow(sections: project.sections)
                    ForEach(project.tracks) { track in
                        ScoreTrackRow(name: track.displayName, trackID: track.id, sections: project.sections, cells: cells)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Affected cells")
        .accessibilityValue(Text(verbatim: description))
        .accessibilityIdentifier("assistant.edit.cells")
    }
    private var description: String {
        project.tracks.compactMap { track in
            let names = project.sections.filter { cells.contains(SongEditCell(trackID: track.id, sectionID: $0.id)) }.map(\.name)
            return names.isEmpty ? nil : "\(track.displayName): \(names.joined(separator: ", "))"
        }.joined(separator: "; ")
    }
}

private func scoreCellWidth(_ section: MusicDomain.Section) -> CGFloat {
    max(28, CGFloat(section.length / barTicks) * 12)
}

private struct ScoreHeaderRow: View {
    let sections: [MusicDomain.Section]
    var body: some View {
        HStack(spacing: 3) {
            Color.clear.frame(width: 64, height: 12)
            ForEach(sections) { section in
                Text(verbatim: section.name).font(.caption2).foregroundStyle(Color.muted).lineLimit(1)
                    .frame(width: scoreCellWidth(section))
            }
        }
    }
}

private struct ScoreTrackRow: View {
    let name: String
    let trackID: UUID
    let sections: [MusicDomain.Section]
    let cells: Set<SongEditCell>
    var body: some View {
        HStack(spacing: 3) {
            Text(verbatim: name).font(.caption2).lineLimit(1).frame(width: 64, alignment: .leading)
            ForEach(sections) { section in
                ScoreCell(highlighted: cells.contains(SongEditCell(trackID: trackID, sectionID: section.id)), width: scoreCellWidth(section))
            }
        }
    }
}

private struct ScoreCell: View {
    let highlighted: Bool
    let width: CGFloat
    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(highlighted ? Color.mint : Color.raised.opacity(0.6))
            .frame(width: width, height: 14)
    }
}
