import Foundation

/// Times use source frames. The frame at endFrame is excluded, just like a
/// Swift Range. PCM fades affect only the selected region, after trimming.
public struct OneShotEdit: Codable, Equatable, Sendable {
    public static let minimumFrames = 32
    public static let gainRange: ClosedRange<Double> = -24...12
    public var startFrame: Int
    public var endFrame: Int
    public var gainDB: Double
    public var fadeInFrames: Int
    public var fadeOutFrames: Int

    public init(startFrame: Int, endFrame: Int, gainDB: Double = 0, fadeInFrames: Int = 0, fadeOutFrames: Int = 0) {
        self.startFrame = startFrame
        self.endFrame = endFrame
        self.gainDB = gainDB
        self.fadeInFrames = fadeInFrames
        self.fadeOutFrames = fadeOutFrames
    }

    func validate(frameCount: Int, sampleRate: Int) throws {
        guard (8000...48000).contains(sampleRate), (Self.minimumFrames...sampleRate*8).contains(frameCount),
              (0...frameCount).contains(startFrame), (0...frameCount).contains(endFrame),
              endFrame - startFrame >= Self.minimumFrames, gainDB.isFinite, Self.gainRange.contains(gainDB) else {
            throw SampleError.invalid
        }
        let maximumFade = min(endFrame - startFrame, sampleRate / 4)
        guard (0...maximumFade).contains(fadeInFrames), (0...maximumFade).contains(fadeOutFrames) else {
            throw SampleError.invalid
        }
    }
}

public struct OneShotWaveformBin: Equatable, Sendable {
    public let min: Float
    public let max: Float
}

public struct OneShotLevels: Equatable, Sendable {
    /// Peak of the selected, gained, faded signal before conversion to PCM16.
    /// For digital silence the peak has no finite logarithmic value.
    public let peakDBFS: Double?
    public let clippedFrames: Int
    public let headroomGainDB: Double?
}

public struct OneShotSource: Sendable {
    public let asset: SampleAsset
    public let sampleRate: Int
    public let waveform: [OneShotWaveformBin]
    let zone: SamplePCM.Zone

    public var frameCount: Int { zone.samples.count }
    public var initialEdit: OneShotEdit { OneShotEdit(startFrame: 0, endFrame: frameCount) }

    public init(asset: SampleAsset, data: Data) throws {
        guard asset.kind == .oneShot else { throw SampleError.invalid }
        let pcm = try SamplePCM.decode(data, asset: asset)
        guard let zone = pcm.zones.first else { throw SampleError.invalid }
        self.asset = asset
        self.zone = zone
        sampleRate = pcm.rate
        let bins = min(256, zone.samples.count)
        var peaks: [OneShotWaveformBin] = []
        peaks.reserveCapacity(bins)
        for bin in 0..<bins {
            try Task.checkCancellation()
            let start = bin * zone.samples.count / bins
            let end = (bin+1) * zone.samples.count / bins
            var low = zone.samples[start], high = low
            for sample in zone.samples[start..<end] {
                low = min(low, sample); high = max(high, sample)
            }
            peaks.append(OneShotWaveformBin(min: Float(low)/32768, max: Float(high)/32768))
        }
        waveform = peaks
    }

    public func maximumFadeFrames(for edit: OneShotEdit) -> Int {
        guard (0...frameCount).contains(edit.startFrame), (edit.startFrame...frameCount).contains(edit.endFrame) else { return 0 }
        return min(edit.endFrame - edit.startFrame, sampleRate / 4)
    }

    public func render(_ edit: OneShotEdit) throws -> SamplePCM {
        try edit.validate(frameCount: frameCount, sampleRate: sampleRate)
        var output = [Int16]()
        output.reserveCapacity(edit.endFrame-edit.startFrame)
        try forEachOutputSample(edit) { value in
            output.append(Int16(clamping: Int(value.rounded())))
        }
        return SamplePCM(rate: sampleRate, zones: [.init(pitch: zone.pitch, samples: output)])
    }

    public func levels(for edit: OneShotEdit) throws -> OneShotLevels {
        try edit.validate(frameCount: frameCount, sampleRate: sampleRate)
        var peak = 0.0
        var clipped = 0
        try forEachOutputSample(edit) { value in
            peak = max(peak, abs(value))
            let quantized = value.rounded()
            if quantized > Double(Int16.max) || quantized < Double(Int16.min) { clipped += 1 }
        }
        guard peak > 0 else { return OneShotLevels(peakDBFS: nil, clippedFrames: 0, headroomGainDB: nil) }
        let decibels = 20*log10(peak/32768)
        var suggested: Double?
        if clipped > 0 {
            let tenths = ((edit.gainDB-decibels-1)*10 + 1e-10).rounded(.down)
            suggested = min(OneShotEdit.gainRange.upperBound, max(OneShotEdit.gainRange.lowerBound, tenths/10))
        }
        return OneShotLevels(peakDBFS: decibels, clippedFrames: clipped, headroomGainDB: suggested)
    }

    private func forEachOutputSample(_ edit: OneShotEdit, _ body: (Double) -> Void) throws {
        let gain = pow(10, edit.gainDB/20)
        let length = edit.endFrame-edit.startFrame
        for (index, sample) in zone.samples[edit.startFrame..<edit.endFrame].enumerated() {
            if index.isMultiple(of: 4096) { try Task.checkCancellation() }
            let attack = Self.fade(position: index, frames: edit.fadeInFrames)
            let release = Self.fade(position: length-1-index, frames: edit.fadeOutFrames)
            body(Double(sample)*gain*attack*release)
        }
    }

    /// A zero-length fade preserves the endpoint. A single-frame fade zeros
    /// just that endpoint. Longer linear ramps reach unity at their last frame.
    private static func fade(position: Int, frames: Int) -> Double {
        guard position < frames else { return 1 }
        return Double(position)/Double(max(1, frames-1))
    }

    public func previewWAV(_ edit: OneShotEdit) throws -> Data {
        let pcm = try render(edit)
        return pcm.monoWAV()
    }
}

extension SamplePCM {
    /// Only used for validated one-shot content (exactly one zone).
    func monoWAV() -> Data {
        let samples = zones[0].samples
        var data = pcmWAVHeader(rate: rate, channels: 1, bits: 16, byteCount: samples.count*2)
        samples.map(\.littleEndian).withUnsafeBytes { data.append(contentsOf: $0) }
        return data
    }
}

/// Keeps the immutable full-size source alongside the audible processed copy
/// in the project package, through history, duplication and portable export.
public struct PadSampleEditRecord: Equatable, Codable, Sendable {
    public let source: SampleAsset
    public let sourceFrameCount: Int
    public let sourceRate: Int
    public let edit: OneShotEdit
    public let renderedID: UUID

    public init(source: OneShotSource, edit: OneShotEdit, renderedID: UUID) {
        self.source = source.asset
        self.sourceFrameCount = source.frameCount
        self.sourceRate = source.sampleRate
        self.edit = edit
        self.renderedID = renderedID
    }

    init(remapping record: Self, source: SampleAsset, renderedID: UUID) {
        self.source = source
        self.sourceFrameCount = record.sourceFrameCount
        self.sourceRate = record.sourceRate
        self.edit = record.edit
        self.renderedID = renderedID
    }

    func validate(rendered: SampleAsset?) throws {
        try edit.validate(frameCount: sourceFrameCount, sampleRate: sourceRate)
        guard let rendered, rendered.kind == .oneShot, source.kind == .oneShot, rendered.id == renderedID,
              source.id != renderedID, source.byteCount == 24 + sourceFrameCount*2,
              rendered.byteCount == 24 + (edit.endFrame-edit.startFrame)*2 else { throw SampleError.invalid }
    }
}

public extension Track {
    mutating func setPadSample(_ sample: SampleAsset?, pad: Int, edit: PadSampleEditRecord? = nil) throws {
        guard role == .drums, (0..<16).contains(pad), sample == nil || sample?.kind == .oneShot else { throw SampleError.invalid }
        try edit?.validate(rendered: sample)
        var sounds = padSamples ?? [:], edits = padEdits ?? [:]
        sounds[pad] = sample
        edits[pad] = edit
        padSamples = sounds.isEmpty ? nil : sounds
        padEdits = edits.isEmpty ? nil : edits
    }

    @discardableResult mutating func restoreOriginal(pad: Int) throws -> SampleAsset {
        guard let record = padEdits?[pad] else { throw SampleError.stale }
        try record.validate(rendered: padSamples?[pad])
        try setPadSample(record.source, pad: pad)
        return record.source
    }

    mutating func clearPadSamples() {
        padSamples = nil
        padEdits = nil
    }
}

extension Project {
    /// Both source and result use the source rate. Validate against decoded PCM
    /// on package import/loading before presenting frame positions as times.
    func validatePadEditRate(for asset: SampleAsset, rate: Int) throws {
        for track in tracks + (performanceTake?.source.tracks ?? []) {
            for record in (track.padEdits ?? [:]).values where record.source.id == asset.id || record.renderedID == asset.id {
                guard record.sourceRate == rate else { throw SampleError.invalid }
            }
        }
    }
}
