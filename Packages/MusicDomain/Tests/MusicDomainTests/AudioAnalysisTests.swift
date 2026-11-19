import Foundation
import Testing
@testable import MusicDomain
import AudioDSP

struct NoteSelectionTests {
    private func pattern() -> (Pattern, [UUID]) {
        let notes = [NoteEvent(tick: 0, duration: 240, pitch: 60, velocity: 80),
                     NoteEvent(tick: 480, duration: 240, pitch: 64, velocity: 90),
                     NoteEvent(tick: 1440, duration: 480, pitch: 67, velocity: 100),
                     NoteEvent(tick: 3000, duration: 240, pitch: 72, velocity: 110)]
        var p = Pattern(length: barTicks); p.notes = notes
        return (p, notes.map(\.id))
    }

    @Test func lassoAndGroupShiftKeepShapeAndClamp() {
        var (p, ids) = pattern()
        let picked = NoteSelection.ids(in: p.notes!, ticks: 0..<1500, pitches: 60...67)
        #expect(picked == Set(ids.prefix(3)))
        // Moving left past zero clamps the whole group, preserving spacing.
        let applied = NoteSelection.shift(&p, ids: picked, ticks: -500, semitones: 70)
        #expect(applied.ticks == 0 && applied.semitones == 60)
        #expect(p.notes!.map(\.tick) == [0, 480, 1440, 3000] && p.notes!.map(\.pitch) == [120, 124, 127, 72])
        NoteSelection.shift(&p, ids: picked, ticks: 5000, semitones: 0)
        #expect(p.notes![2].tick + p.notes![2].duration == barTicks && p.notes![1].tick - p.notes![0].tick == 480)
    }

    @Test func stretchDeleteAndVelocityStayInRange() {
        var (p, ids) = pattern()
        let first = Set(ids.prefix(2))
        NoteSelection.stretch(&p, ids: first, factor: 2)
        #expect(p.notes![0].tick == 0 && p.notes![1].tick == 960 && p.notes![1].duration == 480)
        NoteSelection.stretch(&p, ids: [ids[3]], factor: 10)
        #expect(p.notes![3].tick + p.notes![3].duration <= barTicks)
        NoteSelection.offsetVelocity(&p, ids: Set(ids), by: 30)
        #expect(p.notes!.map(\.velocity) == [110, 120, 127, 127])
        NoteSelection.setVelocity(&p, ids: [ids[0]], to: -4)
        #expect(p.notes![0].velocity == 1)
        NoteSelection.ramp(&p, ids: Set(ids), from: 40, to: 120)
        #expect(p.notes!.first!.velocity == 40 && p.notes!.last!.velocity == 120 && p.notes![1].velocity > 40)
        NoteSelection.delete(&p, ids: first)
        #expect(p.notes!.count == 2)
        #expect(NoteSelection.freeTick(-7, duration: 100, length: 1000) == 0 && NoteSelection.freeTick(997, duration: 100, length: 1000) == 900 && NoteSelection.freeTick(333, duration: 100, length: 1000) == 333)
    }
}

struct AudioAnalysisTests {
    @Test func autoTrimFindsTheHitAndIgnoresRoomNoise() throws {
        let rate = 16000
        var frames = [Int16](repeating: 0, count: rate)
        var seed: UInt64 = 7
        for i in frames.indices { seed = seed &* 6364136223846793005 &+ 1; frames[i] = Int16(truncatingIfNeeded: Int(seed >> 60) - 8) } // ≈ −72 dBFS noise
        for i in 4000..<6000 { frames[i] = Int16(20000 * exp(-Double(i - 4000) / 400) * sin(Double(i) * 0.3)) }
        let pcm = SamplePCM(rate: rate, zones: [.init(pitch: 60, samples: frames)])
        let bytes = try pcm.encode(kind: .oneShot)
        let source = try OneShotSource(asset: SampleAsset(kind: .oneShot, name: "Mic", bytes: bytes), data: bytes)
        let edit = source.autoTrim()
        #expect((3960...4000).contains(edit.startFrame))
        #expect((4800...6000).contains(edit.endFrame))
        #expect(edit.fadeOutFrames == 160)
        _ = try source.render(edit)
        let silent = SamplePCM(rate: rate, zones: [.init(pitch: 60, samples: [Int16](repeating: 0, count: 400))])
        let quiet = try silent.encode(kind: .oneShot)
        let empty = try OneShotSource(asset: SampleAsset(kind: .oneShot, name: "Silence", bytes: quiet), data: quiet)
        #expect(empty.autoTrim() == empty.initialEdit)
    }

    private func loop(bpm: Double, bars: Int, rate: Int, swingHats: Bool = true) -> [Float] {
        let beat = 60 / bpm
        let count = Int(Double(bars * 4) * beat * Double(rate))
        var out = [Float](repeating: 0, count: count)
        func hit(_ t: Double, _ amp: Float, _ freq: Double, _ decay: Double) {
            let start = Int(t * Double(rate))
            for i in 0..<Int(Double(rate) * 0.12) where start + i < count {
                out[start + i] += amp * Float(exp(-Double(i) / (decay * Double(rate))) * sin(2 * .pi * freq * Double(i) / Double(rate)))
            }
        }
        for b in 0..<(bars * 4) {
            let t = Double(b) * beat
            hit(t, b % 2 == 0 ? 0.9 : 0.6, b % 2 == 0 ? 60 : 180, 0.03)
            hit(t + beat / 2 + (swingHats ? beat * 0.08 : 0), 0.25, 6000, 0.008)
        }
        return out
    }

    @Test func loopTempoWithinHalfBPM() {
        for (bpm, bars) in [(93.0, 2), (120.0, 4), (87.5, 4), (140.0, 2)] {
            let estimate = AudioTempoEstimator.estimate(loop(bpm: bpm, bars: bars, rate: 22050), rate: 22050)
            #expect(estimate != nil)
            #expect(abs((estimate?.bpm ?? 0) - bpm) <= 0.5, "expected \(bpm), got \(String(describing: estimate))")
            #expect(estimate?.bars == bars)
        }
        #expect(AudioTempoEstimator.estimate([Float](repeating: 0, count: 100), rate: 22050) == nil)
    }

    private func zeroCrossingFrequency(_ x: [Float], rate: Int) -> Double {
        let body = x[(x.count / 5)..<(x.count * 4 / 5)]
        var crossings = 0
        var previous = body.first!
        for v in body.dropFirst() { if previous < 0 && v >= 0 { crossings += 1 }; previous = v }
        return Double(crossings) * Double(rate) / Double(body.count)
    }

    @Test func wsolaKeepsPitchAndChangesLength() {
        let rate = 22050
        let tone = (0..<rate).map { Float(0.5 * sin(2 * Double.pi * 440 * Double($0) / Double(rate))) }
        for ratio in [0.75, 1.5, 2.0] {
            let out = TimeStretch.wsola(tone, rate: rate, ratio: ratio)
            #expect(out.count == Int((Double(rate) * ratio).rounded()))
            #expect(abs(zeroCrossingFrequency(out, rate: rate) - 440) < 440 * 0.01)
            let body = out[(out.count / 5)..<(out.count * 4 / 5)]
            let rms = sqrt(body.reduce(0.0) { $0 + Double($1 * $1) } / Double(body.count))
            #expect(abs(rms - 0.5 / 2.0.squareRoot()) < 0.05)
        }
        #expect(TimeStretch.wsola(tone, rate: rate, ratio: 1) == tone)
        #expect(TimeStretch.wsola([], rate: rate, ratio: 1.3).isEmpty)
    }

    @Test func latencyFromCrossCorrelationAndRobustSummary() {
        let rate = 48000
        let click = LatencyAnalyzer.click(rate: rate)
        var seed: UInt64 = 3
        for expectedMS in [12.0, 37.5, 120.0] {
            var recording = [Float](repeating: 0, count: rate / 2)
            for i in recording.indices { seed = seed &* 6364136223846793005 &+ 1; recording[i] = Float(Int(seed >> 52) - 2048) / 2048 * 0.05 }
            let at = Int(expectedMS * Double(rate) / 1000)
            for (i, v) in click.enumerated() { recording[at + i] += v * 0.3 }
            let measured = LatencyAnalyzer.delay(reference: click, recorded: recording, rate: rate)
            #expect(measured != nil && abs(measured! - expectedMS) < 0.05)
        }
        let noise = (0..<rate / 4).map { _ -> Float in seed = seed &* 6364136223846793005 &+ 1; return Float(Int(seed >> 52) - 2048) / 2048 }
        #expect(LatencyAnalyzer.delay(reference: click, recorded: noise, rate: rate) == nil)
        let summary = LatencyAnalyzer.summary([20, 21, 19, 20.5, 22, 20, 300])
        #expect(summary?.count == 6 && abs(summary!.medianMS - 20.25) < 0.01 && summary!.p95MS < 22.01)
        #expect(LatencyAnalyzer.summary([]) == nil)
    }
}

struct SpectrumTests {
    @Test func aSineLightsItsBand() throws {
        let rate = 48000.0
        let tone = (0..<4096).map { Float(0.5 * sin(2 * Double.pi * 1000 * Double($0) / rate)) }
        let bands = Spectrum.bands(tone, rate: rate)
        #expect(bands.count == 24)
        let loudest = bands.indices.max { bands[$0] < bands[$1] }!
        let center = 30 * pow(16_000.0 / 30, (Double(loudest) + 0.5) / 24)
        #expect(center > 700 && center < 1500)
        #expect(abs(Double(bands[loudest]) - 20 * log10(0.5)) < 1.5)
        #expect(bands.first! < -60 && bands.last! < -60)
        #expect(Spectrum.bands([], rate: rate).allSatisfy { $0 == -90 })
    }

    @Test func kernelScopeReturnsTheRenderedMaster() throws {
        let kernel = try #require(lg_create(48000))
        defer { lg_destroy(kernel) }
        var note = LGNote(tick: 0, duration: 960, pitch: 60, velocity: 110, track: 0, pad: -1, instrument: 0)
        #expect(lg_submit(kernel, &note, 1, 120, 0, 3840, 0, 1) != 0)
        lg_seek(kernel, 0); var a = [Float](repeating: 0, count: 512), b = a
        lg_render(kernel, &a, &b, 1); lg_play(kernel, 1)
        lg_render(kernel, &a, &b, 512)
        var scope = [Float](repeating: 9, count: 256)
        #expect(lg_scope_read(kernel, &scope, 256) == 256)
        for i in 0..<256 { #expect(abs(scope[i] - 0.5 * (a[256 + i] + b[256 + i])) < 1e-6) }
        #expect(scope.contains { $0 != 0 })
    }
}

struct VideoStoryboardTests {
    @Test func layoutStaysInFrameAndPlayheadFollowsTheMusic() {
        var project = Project.demo(); project.bpm = 120
        let board = VideoStoryboard(project: project, range: 0..<project.length, seconds: 8 + 2, fps: 30)
        #expect(board.frames == 300)
        let m = VideoStoryboard.map
        #expect(!board.blocks.isEmpty)
        #expect(board.blocks.allSatisfy { $0.x >= m.x - 0.001 && $0.x + $0.width <= m.x + m.width + 0.001 && $0.y >= m.y && $0.y + $0.height <= m.y + m.height + 0.001 })
        #expect(board.blocks.contains { $0.role == .drums } && board.blocks.contains { $0.role == .harmony })
        // 4 bars at 120 BPM = 8 s of music: halfway at frame 120, end from frame 240 (tail holds).
        #expect(abs(board.tick(frame: 120) - Double(project.length) / 2) < 1)
        #expect(board.tick(frame: 240) == Double(project.length) && board.tick(frame: 299) == Double(project.length))
        #expect(abs(board.playheadX(frame: 0) - m.x) < 0.001 && abs(board.playheadX(frame: 299) - (m.x + m.width)) < 0.001)
        #expect(board.sections.count == project.sections.count && board.section(frame: 0) == 0)
        #expect(board.subtitle.hasPrefix("120 BPM"))
    }
}
