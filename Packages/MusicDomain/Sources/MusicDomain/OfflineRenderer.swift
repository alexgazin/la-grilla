import Foundation
import AudioDSP

public struct WAVSettings: Sendable, Equatable {
    public var sampleRate: Int
    public var bitDepth: Int
    public var tailSeconds: Double
    public var dither: Bool
    /// I68: peak-normalize each stem to this level (dBFS); nil keeps the mix levels.
    public var normalizeStemsDBFS: Double?
    public init(sampleRate: Int = 48000, bitDepth: Int = 24, tailSeconds: Double = 2, dither: Bool = true, normalizeStemsDBFS: Double? = nil) {
        self.sampleRate = sampleRate; self.bitDepth = bitDepth; self.tailSeconds = tailSeconds; self.dither = dither; self.normalizeStemsDBFS = normalizeStemsDBFS
    }
    public func validate() throws {
        guard [44100,48000].contains(sampleRate), [16,24].contains(bitDepth), tailSeconds.isFinite, (0...10).contains(tailSeconds) else { throw ExportError.invalidSettings }
        if let target = normalizeStemsDBFS { guard target.isFinite, (-12...0).contains(target) else { throw ExportError.invalidSettings } }
    }
}
public enum ExportError: Error, LocalizedError {
    case invalidSettings, invalidRange, renderUnavailable, invalidArchive, archiveTooLarge, unsupportedArchive
    public var errorDescription: String? {
        let key = switch self {
        case .invalidSettings: "Choose 44.1 or 48 kHz, 16 or 24 bit, and a tail of 0–10 seconds."
        case .invalidRange: "Choose a non-empty range inside the song."
        case .renderUnavailable: "The offline audio renderer could not be prepared."
        case .invalidArchive: "This project archive is damaged or contains unsafe paths."
        case .archiveTooLarge: "This archive exceeds the supported size limit."
        case .unsupportedArchive: "This archive uses an unsupported format or compression method."
        }
        return NSLocalizedString(key, comment: "Export and import")
    }
}
public struct RenderReceipt: Sendable, Equatable {
    public let url: URL
    public let sampleRate: Int
    public let bitDepth: Int
    public let frames: Int
    public let peak: Float
    public let clipped: Bool
}
public enum OfflineRenderer {
    public static func renderPerformance(_ take:PerformanceTake,to url:URL,settings:WAVSettings=WAVSettings(tailSeconds:0),samples:SampleLibrary=SampleLibrary(),progress:@Sendable(Double)->Void={_ in})async throws->RenderReceipt {
        try take.validate();return try await render(take.source,to:url,settings:settings,performance:take,samples:samples,progress:progress)
    }
    /// Compiles an immutable value snapshot; the live AVAudioEngine is never touched.
    public static func render(_ project: Project, to url: URL, settings: WAVSettings = WAVSettings(), range requested: Range<Int>? = nil, isolatedTrack: UUID? = nil, performance:PerformanceTake?=nil, samples: SampleLibrary = SampleLibrary(), progress: @Sendable (Double) -> Void = { _ in }) async throws -> RenderReceipt {
        try Task.checkCancellation(); try project.validate(); try settings.validate()
        let range = requested ?? 0..<project.length
        guard range.lowerBound >= 0, range.upperBound <= project.length, !range.isEmpty else { throw ExportError.invalidRange }
        if let performance{try performance.validate();guard isolatedTrack==nil,project==performance.source,requested==nil else{throw ExportError.invalidSettings}}
        if let isolatedTrack, !project.tracks.contains(where: {$0.id == isolatedTrack}) { throw ExportError.invalidSettings }
        guard let kernel = lg_create(Double(settings.sampleRate)) else { throw ExportError.renderUnavailable }
        defer { lg_destroy(kernel) }
        for (index,track) in project.tracks.enumerated(){_ = lg_preset_version(kernel,Int32(index),Int32(track.presetVersion))}
        let anySolo=project.tracks.contains(where: \.solo)
        let audible=Set(project.tracks.enumerated().filter { _,track in !track.mute && (!anySolo || track.solo) && (isolatedTrack == nil || track.id==isolatedTrack) }.map(\.offset))
        let compiled = Compiler.notes(project, range: range).filter{performance != nil || audible.contains($0.track)}
        let notes = compiled.map { LGNote(tick: Int32($0.tick), duration: Int32($0.duration), pitch: Int32($0.pitch), velocity: Int32($0.velocity), track: Int32($0.track), pad: Int32($0.pad),instrument:Int32($0.instrument)) }
        let firstSection=performance.flatMap{take in take.source.sections.first{$0.id==take.events.first?.sectionID}}
        let start=firstSection?.start ?? 0,end=firstSection.map{$0.start+$0.length} ?? range.count
        let submitted = try samples.withRoutes(for: project) { instruments, pads in
            notes.withUnsafeBufferPointer {
                lg_submit_samples_eq(kernel, $0.baseAddress, Int32($0.count), project.bpm, Int32(start), Int32(end),
                                  performance == nil ? 0 : 1, Int32(clamping: project.revision), instruments, pads,project.equalizerBands(includeMaster:isolatedTrack == nil))
            }
        }
        guard submitted != 0 else { throw ExportError.renderUnavailable }
        let solo = project.tracks.contains(where: \.solo)
        for (index, track) in project.tracks.enumerated() {
            let audible = !track.mute && (!solo || track.solo) && (isolatedTrack == nil || isolatedTrack == track.id)
            lg_mix(kernel, Int32(index), Float(track.gain), Float(track.pan), audible ? 1 : 0)
        }
        // Stems retain track gain and pan, but exclude master gain. Mute/solo are honored.
        lg_master(kernel, Float(isolatedTrack == nil ? project.master : 0))
        let fx=isolatedTrack==nil ? (project.masterFX ?? MasterFX()):MasterFX();lg_effects(kernel,Float(fx.filter),Float(fx.delayWet))
        lg_metronome(kernel, 0); lg_tail_on_end(kernel, settings.tailSeconds > 0 ? 1 : 0)
        guard project.applyDynamics(to: kernel, includeMaster: isolatedTrack == nil) else { throw ExportError.renderUnavailable }
        var left = [Float](repeating: 0, count: 4096), right = left
        // Settle the exact same DSP ramps before the first written sample.
        left.withUnsafeMutableBufferPointer { l in right.withUnsafeMutableBufferPointer { r in lg_render(kernel,l.baseAddress,r.baseAddress,Int32(min(4096,settings.sampleRate / 20))) } }
        let contentFrames:Int
        if let performance,let firstSection {
            contentFrames=Int((performance.durationSeconds*Double(settings.sampleRate)).rounded())
            let events=try PerformanceCodec.kernelEvents(performance,targetRate:Double(settings.sampleRate))
            let ok=events.withUnsafeBufferPointer{lg_perform_replay_submit(kernel,$0.baseAddress,Int32($0.count),UInt64(contentFrames),1)}
            guard ok != 0 else{throw ExportError.renderUnavailable}
            lg_seek(kernel,Int32(firstSection.start));lg_perform_begin(kernel,Int32(project.sections.firstIndex{$0.id==firstSection.id}!+1),1,0,0)
        }else{lg_seek(kernel, 0);lg_play(kernel,1);contentFrames=Int((Double(range.count)*60/(project.bpm*Double(ppq))*Double(settings.sampleRate)).rounded())}
        let frames=contentFrames+Int((settings.tailSeconds*Double(settings.sampleRate)).rounded())
        // The limiter's look-ahead delays the master; drop it so the file starts on the beat.
        var latency=Int(lg_limiter_latency(kernel))
        while latency>0{let count=min(4096,latency);left.withUnsafeMutableBufferPointer{l in right.withUnsafeMutableBufferPointer{r in lg_render(kernel,l.baseAddress,r.baseAddress,Int32(count))}};latency-=count}
        var complete = false
        defer { if !complete {try? FileManager.default.removeItem(at:url)} }
        let writer = try PCMWriter(url: url, sampleRate: settings.sampleRate, bits: settings.bitDepth, frames: frames)
        defer {try? writer.close()}
        var position = 0; var peak: Float = 0; var random: UInt32 = 0x4C475741
        progress(0)
        while position < frames {
            try Task.checkCancellation()
            let count = min(4096, frames-position)
            left.withUnsafeMutableBufferPointer { l in right.withUnsafeMutableBufferPointer { r in lg_render(kernel,l.baseAddress,r.baseAddress,Int32(count)) } }
            peak = max(peak,lg_meter(kernel,Int32(masterBus)))
            try writer.append(left: left, right: right, count: count, dither: settings.dither && settings.bitDepth == 16, random: &random)
            position += count
            if position % (4096*16) == 0 { progress(Double(position)/Double(frames)); await Task.yield() }
        }
        try Task.checkCancellation(); try writer.close(); complete = true; progress(1)
        return RenderReceipt(url:url,sampleRate:settings.sampleRate,bitDepth:settings.bitDepth,frames:frames,peak:peak,clipped:peak>=0.98)
    }
}
private final class PCMWriter {
    private let handle: FileHandle
    private let bits: Int
    private var closed = false
    init(url: URL, sampleRate: Int, bits: Int, frames: Int) throws {
        self.bits = bits
        let bytes = frames * 2 * (bits/8)
        guard frames > 0, bytes <= Int(UInt32.max)-36 else { throw ExportError.archiveTooLarge }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard FileManager.default.createFile(atPath:url.path,contents:nil) else {throw CocoaError(.fileWriteUnknown)}
        handle = try FileHandle(forWritingTo:url)
        try handle.write(contentsOf: pcmWAVHeader(rate: sampleRate, channels: 2, bits: bits, byteCount: bytes))
    }
    func append(left:[Float],right:[Float],count:Int,dither:Bool,random:inout UInt32) throws {
        var data=Data(); data.reserveCapacity(count*2*(bits/8)); let scale = bits == 16 ? 32767.0 : 8388607.0
        func noise(_ state:inout UInt32)->Double {state ^= state<<13;state ^= state>>17;state ^= state<<5;return Double(state)/Double(UInt32.max)}
        for frame in 0..<count { for channel in 0..<2 {
            let sample = channel == 0 ? left[frame] : right[frame]
            let value=Double(sample.isFinite ? sample : 0)
            let quantized=Int32((max(-1,min(1,value))*scale+(dither ? noise(&random)-noise(&random):0)).rounded())
            let raw=UInt32(bitPattern:quantized)
            data.append(UInt8(raw&255)); data.append(UInt8((raw>>8)&255)); if bits == 24 {data.append(UInt8((raw>>16)&255))}
        }}
        try handle.write(contentsOf:data)
    }
    func close() throws {if !closed {closed=true;try handle.close()}}
}
func pcmWAVHeader(rate: Int, channels: Int, bits: Int, byteCount: Int) -> Data {
    let blockBytes = channels * (bits / 8)
    var header = Data("RIFF".utf8)
    header.little(UInt32(byteCount + 36)); header.append(contentsOf: "WAVEfmt ".utf8)
    header.little(UInt32(16)); header.little(UInt16(1)); header.little(UInt16(channels))
    header.little(UInt32(rate)); header.little(UInt32(rate * blockBytes)); header.little(UInt16(blockBytes)); header.little(UInt16(bits))
    header.append(contentsOf: "data".utf8); header.little(UInt32(byteCount))
    return header
}

extension Data {
    mutating func little<T: FixedWidthInteger>(_ value:T) {var v=value.littleEndian; Swift.withUnsafeBytes(of:&v){append(contentsOf:$0)}}
}
