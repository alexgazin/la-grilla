import SwiftUI
import MusicDomain

/// Build 46: compare three producer palettes on the selected section with the
/// same notes, velocities and start, loudness-matched to the current sound.
/// Auditioning never edits the project or its Undo history; Apply is one
/// undoable change. Tracks with the musician's own sounds are kept by default.
struct PaletteView: View {
    @Bindable var session: Session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selected: ProducerPalette.Style?
    @State private var keep: Set<UUID> = []
    @State private var result: PaletteAudition.Result?
    @State private var kit: [(pad: Int, asset: SampleAsset, data: Data)] = []
    @State private var library: SampleLibrary?
    @State private var loading = false
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    @State private var previewB = false
    @State private var baseRevision = -1
    @State private var palette: ProducerPalette?
    /// U67: a held card plays four bars; its release is not a tap.
    @State private var heldCard = false

    private var section: MusicDomain.Section { session.section }
    private var range: Range<Int> { section.start..<(section.start + section.length) }
    private var stale: Bool { baseRevision != session.project.revision }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Three treatments of your own part.").font(.headline)
                    Text(String(format: NSLocalizedString("Compares %@ at the same tempo, notes and start. Levels are matched; the master stays yours.", comment: "Palettes"), section.name))
                        .font(.caption).foregroundStyle(Color.muted).accessibilityIdentifier("palettes.scope")
                    ForEach(ProducerPalette.Style.allCases, id: \.self) { style in
                        PaletteCard(style: style, selected: selected == style) { if heldCard { heldCard = false } else { choose(style) } }
                            .holdToPreview(suppressTap: $heldCard, start: { holdPalette(style) }, stop: { session.endHarmonyPreview() })
                            .luzScrollDepth()
                            .luzEntrance(ProducerPalette.Style.allCases.firstIndex(of: style) ?? 0)
                    }
                    missingSounds
                    keepList
                    if loading { LoadingSkeleton(rows: 4, caption: "Matching levels on this section…").accessibilityIdentifier("palettes.loading").transition(Luz.Transition.pop(reduceMotion)) }
                    if let error { Text(LocalizedStringKey(error)).font(.callout).foregroundStyle(Color.record).accessibilityIdentifier("palettes.error").transition(Luz.Transition.pop(reduceMotion)) }
                    // Luz: the review rises in once the levels are matched.
                    if let result, !loading { review(result).transition(Luz.Transition.rise(reduceMotion)) }
                }.padding(18)
                .animation(reduceMotion ? .easeOut(duration: 0.15) : Luz.Motion.morph, value: loading)
                .animation(reduceMotion ? nil : Luz.Motion.snap, value: error)
            }
            .accessibilityIdentifier("palettes.scroll")
            .background(Color.ink).navigationTitle("Palettes").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { close() } } }
        }.tint(.mint)
        .onAppear { keep = PaletteEngine.defaultKept(session.project); baseRevision = session.project.revision }
        .onDisappear { task?.cancel(); session.endHarmonyPreview() }
    }

    private var keepList: some View {
        VStack(alignment: .leading, spacing: 6) {
            SmallHeading(text: "KEEP MY SOUND ON")
            ForEach(session.project.tracks) { track in
                Toggle(isOn: Binding(get: { keep.contains(track.id) }, set: { value in
                    if value { keep.insert(track.id) } else { keep.remove(track.id) }
                    if let selected { choose(selected) }
                })) {
                    Text(verbatim: track.displayName).font(.subheadline)
                }.frame(minHeight: 44).accessibilityIdentifier("palettes.keep.\(track.role.rawValue)")
            }
        }.padding(12).modifier(StudioSurface())
    }

    @ViewBuilder private var missingSounds: some View {
        let missing = PaletteEngine.missingSounds(session.project, available: session.audio.samples.assets)
        if !missing.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(missing.enumerated()), id: \.offset) { _, item in
                    MissingSoundRow(item: item, track: session.project.tracks.first { $0.id == item.trackID }?.displayName ?? "")
                }
            }.accessibilityIdentifier("palettes.missing")
        }
    }

    private func review(_ result: PaletteAudition.Result) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SmallHeading(text: "LEVEL")
            Text(levelText(result)).font(.caption.monospaced()).accessibilityIdentifier("palettes.level")
            SmallHeading(text: "CHANGES")
            ForEach(PaletteEngine.changes(from: session.project, to: result.candidate, keep: keep), id: \.trackID) { change in
                Text(verbatim: changeText(change)).font(.caption).frame(maxWidth: .infinity, alignment: .leading)
            }
            if let delay = palette?.masterDelayWet {
                Text(String(format: NSLocalizedString("Master delay: %.2f (the master level is unchanged)", comment: "Palettes"), delay)).font(.caption).foregroundStyle(Color.muted)
            }
            if stale {
                LuzNotice(kind: .caution, symbol: "exclamationmark.arrow.circlepath", text: "The project changed. Compare again before applying.")
            } else {
                ABCompare(playing: session.harmonyPreview ? (previewB ? .b : .a) : nil, b: "B · Palette",
                          audition: { side in
                              if side == .a { previewB = false; session.previewAssistant(session.project, wholeSong: false, sectionID: section.id, rangeOverride: range, loopOverride: true) }
                              else { previewB = true; if let library { session.previewPalette(result.candidate, range: range, samples: library) } }
                          },
                          stop: { session.endHarmonyPreview() },
                          identifiers: ("palettes.a", "palettes.b", "palettes.stop"))
                Button { apply(result) } label: { Text("Apply palette") }.buttonStyle(StudioActionStyle()).accessibilityIdentifier("palettes.apply")
                    .padding(.top, 4)
                Text("One Undo restores the previous sounds.").font(.caption).foregroundStyle(Color.muted)
            }
        }
    }

    private func levelText(_ result: PaletteAudition.Result) -> String {
        String(format: NSLocalizedString("Current %.1f LUFS · palette %.1f LUFS · difference %+.1f LU · peak %.1f dBFS", comment: "Palettes"),
               result.source.integratedLUFS, result.palette.integratedLUFS, result.differenceLU, result.palette.samplePeakDBFS)
    }

    private func changeText(_ change: PaletteChange) -> String {
        let name = session.project.tracks.first { $0.id == change.trackID }?.displayName ?? ""
        let before = soundName(change.soundBefore), after = soundName(change.soundAfter)
        var text = String(format: NSLocalizedString("%@: %@ → %@, %.1f → %.1f dB", comment: "Palette change"), name, before, after, change.gainBefore, change.gainAfter)
        if change.replacesKit { text += " · " + NSLocalizedString("new drum kit", comment: "Palette change") }
        return text
    }

    private func soundName(_ raw: Int) -> String {
        switch SoundPalette(rawValue: raw) {
        case .warm: NSLocalizedString("Warm", comment: "Sound palette")
        case .bright: NSLocalizedString("Bright", comment: "Sound palette")
        case .legacy: NSLocalizedString("Original", comment: "Sound palette")
        default: NSLocalizedString("Classic", comment: "Sound palette")
        }
    }

    /// U67 · Four bars of the section with this palette, at once (levels are matched only on choosing).
    private func holdPalette(_ style: ProducerPalette.Style) -> Bool {
        do {
            let palette = ProducerPalette.make(style, seed: 1)
            let sounds = try PaletteEngine.kit(palette)
            let assets = Dictionary(uniqueKeysWithValues: sounds.map { ($0.pad, $0.asset) })
            let candidate = try PaletteEngine.candidate(session.project, palette: palette, keep: keep, kit: assets)
            return session.holdPreview(candidate, range: HoldPreview.range(candidate, from: section.start), samples: try session.paletteLibrary(sounds))
        } catch { return false }
    }

    private func choose(_ style: ProducerPalette.Style) {
        task?.cancel()
        session.endHarmonyPreview()
        selected = style; result = nil; error = nil; loading = true; previewB = false
        let source = session.project, kept = keep, passage = range, base = session.audio.samples
        baseRevision = source.revision
        task = Task { @MainActor in
            do {
                let palette = ProducerPalette.make(style, seed: style == .surprise ? UInt64.random(in: 1...UInt64.max) : 1)
                let sounds = try PaletteEngine.kit(palette)
                let matched = try await PaletteAudition.matched(source, palette: palette, keep: kept, kit: sounds, range: passage, samples: base)
                try Task.checkCancellation()
                guard selected == style, session.project.id == source.id, session.project.revision == source.revision else { loading = false; return }
                kit = sounds
                self.palette = palette
                library = try session.paletteLibrary(sounds)
                result = matched
            } catch is CancellationError {
                return
            } catch {
                self.error = error.localizedDescription
            }
            loading = false
        }
    }

    private func apply(_ result: PaletteAudition.Result) {
        let project = session.project.id, revision = session.project.revision
        task?.cancel()
        task = Task { @MainActor in
            do {
                try await session.applyPalette(result.candidate, kit: kit, projectID: project, revision: revision)
                close()
            } catch is CancellationError {
                return
            } catch { self.error = error.localizedDescription }
        }
    }

    private func close() { session.endHarmonyPreview(); session.sheet = nil }
}

private struct PaletteCard: View {
    let style: ProducerPalette.Style
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(LocalizedStringKey(style.title)).font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.mint).transition(.scale(scale: 0.5).combined(with: .opacity)) }
                }
                Text(LocalizedStringKey(style.brief)).font(.caption).foregroundStyle(Color.muted).multilineTextAlignment(.leading)
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.panel, in: RoundedRectangle(cornerRadius: StudioMetrics.controlRadius, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: StudioMetrics.controlRadius, style: .continuous).stroke(selected ? Color.mint : Color.outline, lineWidth: selected ? 2 : 1) }
            .animation(Luz.Motion.snap, value: selected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("palettes.choose.\(style.rawValue)")
    }
}

private struct MissingSoundRow: View {
    let item: PaletteEngine.MissingSound
    let track: String
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(String(format: NSLocalizedString("%@ is missing on %@", comment: "Missing sound"), item.name, track), systemImage: "exclamationmark.triangle")
                .font(.caption.weight(.semibold)).foregroundStyle(Color.studioText)
            Text(verbatim: item.remedy).font(.caption).foregroundStyle(Color.muted)
        }
    }
}
