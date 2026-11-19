import AVFoundation
import MusicDomain
import SwiftUI

struct PadSampleEditor: View {
    let session: Session
    let projectID: UUID
    let trackID: UUID
    let revision: Int
    let pad: Int
    let sample: SampleAsset
    let record: PadSampleEditRecord?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var source: OneShotSource?
    @State private var edit: OneShotEdit?
    @State private var failure: String?
    @State private var applying = false
    @State private var applyingTask: Task<Void, Never>?
    @State private var audition: Task<Void, Never>?
    @State private var player: AVAudioPlayer?
    @State private var previewTrace = ""
    @State private var levels: OneShotLevels?
    @State private var measuredEdit: OneShotEdit?

    private var isCurrent: Bool {
        session.project.id == projectID && session.project.revision == revision &&
            session.project.tracks.first(where: { $0.id == trackID })?.padSamples?[pad] == sample &&
            !session.armed && !session.recording && !session.performance.contextActive
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(LocalizedStringKey(Compiler.padNames[pad])).font(.subheadline).foregroundStyle(Color.muted)
                        Text(verbatim: sample.name).font(.title2.bold()).foregroundStyle(Color.studioText)
                    }
                    if !isCurrent {
                        Text(SampleError.stale.localizedDescription).foregroundStyle(Color.record)
                    } else if let source, let edit {
                        waveform(source, edit)
                        VStack(spacing: 0) {
                            ForEach(SampleParameter.allCases, id: \.self) { parameter in
                                parameterRow(parameter, source: source, edit: edit)
                                if parameter != .fadeOut { Divider() }
                            }
                        }
                        .padding(.horizontal, 14)
                        .background(Color.panel, in: RoundedRectangle(cornerRadius: 16))
                        if measuredEdit == edit, let gain = levels?.headroomGainDB {
                            Button("Leave 1 dB headroom") { adjust(.gain, to: gain, source: source) }
                                .buttonStyle(.bordered).font(.subheadline)
                                .frame(minHeight: 44).disabled(applying)
                                .accessibilityIdentifier("pad-editor.headroom")
                        }
                        // I52: cut the silence before and after the hit in one step.
                        Button("Trim silence") { update(source.autoTrim()) }
                            .font(.subheadline).disabled(applying).accessibilityIdentifier("pad-editor.trim-silence")
                        Button("Reset sample edits") { update(source.initialEdit) }
                            .font(.subheadline).disabled(edit == source.initialEdit || applying)
                    } else if failure == nil {
                        ProgressView("Preparing samples…").frame(maxWidth: .infinity)
                    }
                    if let failure { Text(failure).foregroundStyle(Color.record) }
                }
                .padding(16)
            }
            .background(Color.ink)
            .navigationTitle("Edit sample").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { applyingTask?.cancel(); stopPreview(); dismiss() }
                        .accessibilityIdentifier("pad-editor.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { apply() }
                        .disabled(!isCurrent || applying || edit == nil || edit == (record?.edit ?? source?.initialEdit))
                        .accessibilityIdentifier("pad-editor.apply")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let source, let edit, isCurrent {
                    Button {
                        if audition != nil { stopPreview() } else { preview(source, edit) }
                    } label: {
                        Label(audition == nil ? "Hear edit" : "Stop preview", systemImage: audition == nil ? "play.fill" : "stop.fill")
                            .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent).foregroundStyle(Color.ink).disabled(applying)
                    .accessibilityValue(Text(verbatim: session.runtimeTraceEnabled ? previewTrace : ""))
                    .accessibilityIdentifier("pad-editor.preview")
                    .padding(.horizontal, 16).padding(.vertical, 8).background(Color.ink)
                }
            }
        }
        .tint(.drums)
        .task {
            do {
                let original = record?.source ?? sample
                let loaded = try await DrumSamplePreparation.shared.openEditor(asset: original, store: session.store, projectID: projectID)
                try Task.checkCancellation()
                guard isCurrent else { throw SampleError.stale }
                source = loaded
                edit = record?.edit ?? loaded.initialEdit
            } catch is CancellationError { return }
            catch { failure = error.localizedDescription }
        }
        .onDisappear { applyingTask?.cancel(); stopPreview() }
        .onChange(of: isCurrent) { _, current in if !current { stopPreview() } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { stopPreview() } }
    }

    private func waveform(_ source: OneShotSource, _ edit: OneShotEdit) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            PadSampleWaveform(source: source, edit: edit) { parameter, frame in
                adjust(parameter, to: Double(frame), source: source)
            }
            .frame(height: 142)
            .disabled(applying)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Sample waveform")
            .accessibilityValue(Text(verbatim: duration(edit.endFrame - edit.startFrame, rate: source.sampleRate)))
            .accessibilityIdentifier("pad-editor.waveform")
            HStack {
                Text(verbatim: duration(0, rate: source.sampleRate))
                Spacer()
                Text(verbatim: duration(source.frameCount, rate: source.sampleRate))
            }.font(.caption.monospacedDigit()).foregroundStyle(Color.muted).accessibilityHidden(true)
            peakDisplay(edit)
        }
        .task(id: edit) {
            do {
                try await Task.sleep(for: .milliseconds(95))
                let result = try await DrumSamplePreparation.shared.editorLevels(source: source, edit: edit)
                try Task.checkCancellation()
                guard self.edit == edit, isCurrent else { return }
                levels = result
                measuredEdit = edit
            } catch is CancellationError { return }
            catch { failure = error.localizedDescription }
        }
    }

    @ViewBuilder
    private func peakDisplay(_ edit: OneShotEdit) -> some View {
        if measuredEdit == edit, let levels {
            let peak = levels.peakDBFS?.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always())) ?? "−∞"
            let clipped = levels.clippedFrames > 0
            let format = clipped ? NSLocalizedString("Peak %@ dBFS · CLIP %lld", comment: "Input peak and saturated frames") :
                NSLocalizedString("Peak %@ dBFS", comment: "Input peak before clipping")
            let label = clipped ? String.localizedStringWithFormat(format, peak, Int64(levels.clippedFrames)) :
                String.localizedStringWithFormat(format, peak)
            Label(label, systemImage: clipped ? "exclamationmark.triangle.fill" : "waveform")
                .font(.caption.monospacedDigit()).foregroundStyle(clipped ? Color.record : Color.muted)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(clipped ? String.localizedStringWithFormat(
                    NSLocalizedString("Peak %@ dBFS, %lld clipped frames", comment: "VoiceOver input peak and clipped frames"),
                    peak, Int64(levels.clippedFrames)) : label)
                .accessibilityIdentifier("pad-editor.peak")
        } else {
            Text("Measuring peak…").font(.caption).foregroundStyle(Color.muted).accessibilityHidden(true)
        }
    }

    private func parameterRow(_ parameter: SampleParameter, source: OneShotSource, edit: OneShotEdit) -> some View {
        let range = parameter.range(source: source, edit: edit)
        let value = parameter.value(in: edit)
        let step = parameter == .gain ? 0.5 : Double(max(1, Int((Double(source.sampleRate) / 1_000).rounded())))
        let display = parameter == .gain ? value.formatted(.number.precision(.fractionLength(0...1))) + " dB" :
            duration(Int(value), rate: source.sampleRate)
        let info = VStack(alignment: .leading, spacing: 3) {
            Text(parameter.title).font(.subheadline.weight(.medium))
            Text(verbatim: display).font(.caption.monospacedDigit()).foregroundStyle(Color.muted)
                .accessibilityIdentifier("pad-editor.\(parameter.rawValue).value")
        }
        let controls = HStack(spacing: 4) {
            nudge("minus", parameter: parameter, enabled: value > range.lowerBound) {
                adjust(parameter, to: value - step, source: source)
            }
            if range.lowerBound < range.upperBound {
                Slider(value: Binding(get: { value }, set: { adjust(parameter, to: $0, source: source) }), in: range)
                    .accessibilityLabel(parameter.title)
                    .accessibilityValue(Text(verbatim: display))
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: adjust(parameter, to: value + step, source: source)
                        case .decrement: adjust(parameter, to: value - step, source: source)
                        @unknown default: break
                        }
                    }
            }
            nudge("plus", parameter: parameter, enabled: value < range.upperBound) {
                adjust(parameter, to: value + step, source: source)
            }
        }
        return Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 0) { info; controls }
            } else {
                HStack(spacing: 8) { info.frame(minWidth: 76, alignment: .leading); controls }
            }
        }
        .foregroundStyle(Color.studioText)
        .padding(.vertical, 4)
        .disabled(applying)
    }

    private func nudge(_ symbol: String, parameter: SampleParameter, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.caption.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(Color.drums).disabled(!enabled)
        .accessibilityLabel(Text(parameter.title) + Text(verbatim: ", ") + Text(symbol == "plus" ? "Increase" : "Decrease"))
        .accessibilityIdentifier("pad-editor.\(parameter.rawValue).\(symbol)")
    }

    private func duration(_ frame: Int, rate: Int) -> String {
        let milliseconds = Double(frame) * 1_000 / Double(rate)
        return milliseconds.formatted(.number.precision(.fractionLength(0...1))) + " " + NSLocalizedString("ms", comment: "Milliseconds")
    }

    private func adjust(_ parameter: SampleParameter, to value: Double, source: OneShotSource) {
        guard var edit, !applying else { return }
        let range = parameter.range(source: source, edit: edit)
        let bounded = min(range.upperBound, max(range.lowerBound, value))
        switch parameter {
        case .start: edit.startFrame = Int(bounded.rounded())
        case .end: edit.endFrame = Int(bounded.rounded())
        case .gain: edit.gainDB = (bounded * 10).rounded() / 10
        case .fadeIn: edit.fadeInFrames = Int(bounded.rounded())
        case .fadeOut: edit.fadeOutFrames = Int(bounded.rounded())
        }
        let maxFade = source.maximumFadeFrames(for: edit)
        edit.fadeInFrames = min(edit.fadeInFrames, maxFade)
        edit.fadeOutFrames = min(edit.fadeOutFrames, maxFade)
        update(edit)
    }

    private func update(_ proposed: OneShotEdit) {
        guard proposed != edit else { return }
        stopPreview()
        previewTrace = ""
        failure = nil
        edit = proposed
    }

    private func apply() {
        guard isCurrent, !applying, let source, let edit else { return }
        stopPreview()
        failure = nil
        applying = true
        applyingTask = Task {
            defer { applying = false }
            do {
                if record != nil && edit == source.initialEdit {
                    try await session.resetPadEdit(pad: pad, trackID: trackID, projectID: projectID, revision: revision)
                    dismiss()
                    return
                }
                let sound = try await DrumSamplePreparation.shared.editedSample(source: source, edit: edit)
                try Task.checkCancellation()
                let record = PadSampleEditRecord(source: source, edit: edit, renderedID: sound.asset.id)
                try await session.assignSounds([(pad, sound)], trackID: trackID, projectID: projectID, revision: revision, padEdit: record)
                dismiss()
            } catch is CancellationError { return }
            catch { failure = error.localizedDescription }
        }
    }

    private func preview(_ source: OneShotSource, _ edit: OneShotEdit) {
        failure = nil
        audition = Task {
            do {
                let bytes = try await DrumSamplePreparation.shared.editorPreview(source: source, edit: edit)
                try Task.checkCancellation()
                guard isCurrent, session.ensureAudio() else { throw SampleError.unavailable }
                let audio = try AVAudioPlayer(data: bytes)
                guard audio.play() else { throw SampleError.unavailable }
                player = audio
                if session.runtimeTraceEnabled {
                    let rate = audio.format.sampleRate
                    previewTrace = "frames=\(Int((audio.duration * rate).rounded())) rate=\(Int(rate.rounded()))"
                }
                try await Task.sleep(for: .seconds(audio.duration))
                stopPreview()
            } catch is CancellationError { return }
            catch { failure = error.localizedDescription; stopPreview() }
        }
    }

    private func stopPreview() {
        audition?.cancel()
        audition = nil
        player?.stop()
        player = nil
    }
}

private enum SampleParameter: String, CaseIterable {
    case start, end, gain, fadeIn = "fade-in", fadeOut = "fade-out"

    var title: LocalizedStringKey {
        switch self {
        case .start: "Trim start"
        case .end: "Trim end"
        case .gain: "Sample gain"
        case .fadeIn: "Fade in"
        case .fadeOut: "Fade out"
        }
    }

    func value(in edit: OneShotEdit) -> Double {
        switch self {
        case .start: Double(edit.startFrame)
        case .end: Double(edit.endFrame)
        case .gain: edit.gainDB
        case .fadeIn: Double(edit.fadeInFrames)
        case .fadeOut: Double(edit.fadeOutFrames)
        }
    }

    func range(source: OneShotSource, edit: OneShotEdit) -> ClosedRange<Double> {
        switch self {
        case .start: 0...Double(edit.endFrame - OneShotEdit.minimumFrames)
        case .end: Double(edit.startFrame + OneShotEdit.minimumFrames)...Double(source.frameCount)
        case .gain: OneShotEdit.gainRange
        case .fadeIn, .fadeOut: 0...Double(source.maximumFadeFrames(for: edit))
        }
    }
}

private struct PadSampleWaveform: View {
    let source: OneShotSource
    let edit: OneShotEdit
    let onDrag: (SampleParameter, Int) -> Void
    @State private var dragging: SampleParameter?

    var body: some View {
        GeometryReader { geometry in
            let inset: CGFloat = 12
            let width = max(1, geometry.size.width - inset * 2)
            let firstX = inset + width * CGFloat(edit.startFrame) / CGFloat(source.frameCount)
            let lastX = inset + width * CGFloat(edit.endFrame) / CGFloat(source.frameCount)
            ZStack {
                Canvas { context, size in
                    draw(in: context, size: size, width: width, inset: inset, firstX: firstX, lastX: lastX)
                }
                handle("chevron.right", x: firstX, y: 15)
                handle("chevron.left", x: lastX, y: geometry.size.height - 15)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.panel, in: RoundedRectangle(cornerRadius: 16))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 1).onChanged { gesture in
                let target: SampleParameter
                if let dragging {
                    target = dragging
                } else {
                    let initial = gesture.startLocation
                    if lastX - firstX < 44 {
                        target = initial.y <= geometry.size.height / 2 ? .start : .end
                    } else {
                        target = abs(initial.x - firstX) <= abs(initial.x - lastX) ? .start : .end
                    }
                    dragging = target
                }
                let fraction = min(1, max(0, (gesture.location.x - inset) / width))
                onDrag(target, Int((fraction * CGFloat(source.frameCount)).rounded()))
            }.onEnded { _ in dragging = nil })
        }
    }

    private func handle(_ symbol: String, x: CGFloat, y: CGFloat) -> some View {
        Image(systemName: symbol).font(.system(size: 11, weight: .bold))
            .foregroundStyle(Color.ink)
            .frame(width: 18, height: 20).background(Color.drums, in: RoundedRectangle(cornerRadius: 5))
            .position(x: x, y: y)
    }

    private func draw(in context: GraphicsContext, size: CGSize, width: CGFloat, inset: CGFloat,
                      firstX: CGFloat, lastX: CGFloat) {
        let middle = size.height / 2
        let amplitude = middle - 12
        let selection = CGRect(x: firstX, y: 0, width: max(1, lastX - firstX), height: size.height)
        context.fill(Path(selection), with: .color(Color.drums.opacity(0.10)))
        var center = Path()
        center.move(to: CGPoint(x: inset, y: middle))
        center.addLine(to: CGPoint(x: width + inset, y: middle))
        context.stroke(center, with: .color(Color.muted.opacity(0.35)), lineWidth: 1)

        let stride = width / CGFloat(source.waveform.count)
        let gain = CGFloat(pow(10, edit.gainDB / 20))
        var original = Path()
        var edited = Path()
        for (index, bin) in source.waveform.enumerated() {
            let fraction = (CGFloat(index) + 0.5) / CGFloat(source.waveform.count)
            let x = inset + fraction * width
            let frame = Int(fraction * CGFloat(source.frameCount))
            if edit.startFrame <= frame && frame < edit.endFrame {
                let attack = level(position: frame - edit.startFrame, length: edit.fadeInFrames)
                let release = level(position: edit.endFrame - 1 - frame, length: edit.fadeOutFrames)
                let multiplier = gain * attack * release
                let top = min(1, max(-1, CGFloat(bin.max) * multiplier))
                let bottom = min(1, max(-1, CGFloat(bin.min) * multiplier))
                edited.move(to: CGPoint(x: x, y: middle - top * amplitude))
                edited.addLine(to: CGPoint(x: x, y: middle - bottom * amplitude))
            } else {
                original.move(to: CGPoint(x: x, y: middle - CGFloat(bin.max) * amplitude))
                original.addLine(to: CGPoint(x: x, y: middle - CGFloat(bin.min) * amplitude))
            }
        }
        context.stroke(original, with: .color(Color.muted.opacity(0.50)), lineWidth: max(1, stride))
        context.stroke(edited, with: .color(Color.drums), lineWidth: max(1, stride))
        var edges = Path()
        for x in [firstX, lastX] {
            edges.move(to: CGPoint(x: x, y: 0))
            edges.addLine(to: CGPoint(x: x, y: size.height))
        }
        context.stroke(edges, with: .color(Color.drums), lineWidth: 1.5)
    }

    private func level(position: Int, length: Int) -> CGFloat {
        guard position < length else { return 1 }
        return CGFloat(position) / CGFloat(max(1, length - 1))
    }
}
