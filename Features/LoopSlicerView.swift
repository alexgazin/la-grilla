import AVFoundation
import MusicDomain
import SwiftUI

/// I6 · "Slice a loop onto the pads" with the cuts in view: the waveform with its markers,
/// sensitivity and minimum interval to find them again, drag a marker to move it, tap the
/// waveform to add one, touch and hold a marker to remove it, tap a slice to hear it, then
/// "Put on pads" (one edit; pads 1–16 in order).
struct LoopSlicerView: View {
    let url: URL
    let done: ([PreparedSound]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var samples: [Int16] = []
    @State private var rate = 48_000
    @State private var name = ""
    @State private var markers = SliceMarkers(frames: [], length: 0)
    @State private var sensitivity = 0.7
    @State private var minimumGap = 0.07
    @State private var peaks: [Float] = []
    @State private var heard: Int?
    @State private var player: AVAudioPlayer?
    @State private var error: String?
    @State private var working = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if samples.isEmpty && error == nil {
                        LoadingSkeleton(rows: 3, caption: "Reading the loop…")
                    } else {
                        Text(String(format: NSLocalizedString("%lld slices", comment: "Loop slicer"), Int64(markers.frames.count)))
                            .font(.headline).accessibilityIdentifier("slicer.count")
                        waveform
                        Text("Tap the waveform to add a cut, drag a cut to move it, touch and hold a cut to remove it. Tap a slice to hear it.")
                            .font(.caption).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Sensitivity").font(.subheadline)
                            Slider(value: $sensitivity, in: 0...1) { editing in if !editing { detect() } }
                                .accessibilityIdentifier("slicer.sensitivity")
                        }
                        Stepper(value: $minimumGap, in: 0.03...0.5, step: 0.01) {
                            Text(String(format: NSLocalizedString("Minimum interval %lld ms", comment: "Loop slicer"), Int64((minimumGap * 1000).rounded())))
                        }
                        .onChange(of: minimumGap) { _, _ in detect() }
                        .accessibilityIdentifier("slicer.gap")
                    }
                    if let error { Text(error).foregroundStyle(Color.record).accessibilityIdentifier("slicer.error") }
                }
                .padding(16)
            }
            .background(Color.ink)
            .navigationTitle("Slice a loop").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { player?.stop(); dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                Button { place() } label: {
                    Text(String(format: NSLocalizedString("Put on pads 1–%lld", comment: "Loop slicer"), Int64(min(16, markers.frames.count))))
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(StudioActionStyle(color: .drums))
                .disabled(samples.isEmpty || working)
                .padding(16).background(Color.ink)
                .accessibilityIdentifier("slicer.apply")
            }
        }
        .task { await load() }
        .onDisappear { player?.stop() }
    }

    private var waveform: some View {
        GeometryReader { geometry in
            let width = geometry.size.width, height = geometry.size.height
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    guard !peaks.isEmpty else { return }
                    let step = size.width / CGFloat(peaks.count)
                    for (index, peak) in peaks.enumerated() {
                        let h = max(1, CGFloat(peak) * size.height)
                        context.fill(Path(CGRect(x: CGFloat(index) * step, y: (size.height - h) / 2, width: max(1, step - 0.5), height: h)), with: .color(Color.drums.opacity(0.7)))
                    }
                    if let heard, let range = markers.ranges(rate: rate).dropFirst(heard).first, markers.length > 0 {
                        let x0 = CGFloat(range.lowerBound) / CGFloat(markers.length) * size.width, x1 = CGFloat(range.upperBound) / CGFloat(markers.length) * size.width
                        context.fill(Path(CGRect(x: x0, y: 0, width: x1 - x0, height: size.height)), with: .color(Color.mint.opacity(0.18)))
                    }
                }
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { value in tapped(at: value.location.x / max(1, width)) })
                .accessibilityElement()
                .accessibilityLabel(Text("Loop waveform"))
                .accessibilityIdentifier("slicer.waveform")
                ForEach(Array(markers.frames.enumerated()), id: \.offset) { index, frame in
                    let x = markers.length > 0 ? CGFloat(frame) / CGFloat(markers.length) * width : 0
                    VStack(spacing: 0) {
                        Text(verbatim: "\(index + 1)").font(.caption2.weight(.bold)).foregroundStyle(Color.ink)
                            .frame(width: 22, height: 18).background(Color.mint, in: RoundedRectangle(cornerRadius: 4))
                        Rectangle().fill(Color.mint).frame(width: 2)
                    }
                    .frame(width: 44, height: height)
                    .contentShape(Rectangle())
                    .position(x: x, y: height / 2)
                    .gesture(DragGesture(minimumDistance: 4).onChanged { value in
                        markers.move(index, to: Int(value.location.x / max(1, width) * CGFloat(markers.length)))
                    })
                    .onLongPressGesture(minimumDuration: 0.5) { if markers.remove(at: index) { Luz.Haptics.selection() } }
                    .accessibilityElement()
                    .accessibilityLabel(Text(String(format: NSLocalizedString("Cut %lld", comment: "Loop slicer"), Int64(index + 1))))
                    .accessibilityAction(named: Text("Remove")) { markers.remove(at: index) }
                    .accessibilityIdentifier("slicer.marker.\(index)")
                }
            }
        }
        .frame(height: 140)
        .background(Color.panel, in: RoundedRectangle(cornerRadius: Luz.Radius.card, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Luz.Radius.card, style: .continuous))
    }

    private func load() async {
        do {
            let loop = try await DrumSamplePreparation.shared.loopSamples(url)
            samples = loop.samples; rate = loop.rate; name = loop.name
            let bins = 240, chunk = max(1, loop.samples.count / bins)
            peaks = stride(from: 0, to: loop.samples.count, by: chunk).map { start in
                Float(loop.samples[start..<min(loop.samples.count, start + chunk)].map { abs(Int($0)) }.max() ?? 0) / 32768
            }
            detect()
        } catch { self.error = error.localizedDescription }
    }

    private func detect() {
        guard !samples.isEmpty else { return }
        markers = SliceMarkers.detect(samples, rate: rate, sensitivity: sensitivity, minimumGap: minimumGap)
        heard = nil
    }

    /// A tap near a cut hears that slice; elsewhere it adds a cut there and hears the new slice.
    private func tapped(at share: CGFloat) {
        guard markers.length > 0 else { return }
        let frame = Int(share * CGFloat(markers.length))
        if !markers.frames.contains(where: { abs($0 - frame) < markers.length / 60 }) { _ = markers.add(frame) }
        if let index = markers.slice(containing: frame) { hear(index) }
    }

    private func hear(_ index: Int) {
        let ranges = markers.ranges(rate: rate)
        guard ranges.indices.contains(index), let audio = try? AVAudioPlayer(data: SliceMarkers.previewWAV(samples, ranges[index], rate: rate)) else { return }
        player?.stop(); player = audio; audio.play(); heard = index
    }

    private func place() {
        working = true
        let samples = samples, rate = rate, markers = markers, name = name
        Task { @MainActor in
            defer { working = false }
            do {
                let sounds = try await DrumSamplePreparation.shared.slices(samples, rate: rate, markers: markers, name: name)
                player?.stop()
                done(Array(sounds.prefix(16)))
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}
