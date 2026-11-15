import Foundation
import MusicDomain
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

struct BenchmarkInputError: Error, CustomStringConvertible {
    let description: String
}

func uint16(_ data: Data, at offset: Int) -> Int {
    Int(UInt16(littleEndian: data.withUnsafeBytes {
        $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self)
    }))
}

func uint32(_ data: Data, at offset: Int) -> Int {
    Int(UInt32(littleEndian: data.withUnsafeBytes {
        $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
    }))
}

func readWave(_ url: URL) throws -> (samples: [Float], rate: Double, rawFrames: Int) {
    let data = try Data(contentsOf: url)
    guard data.count >= 44,
          String(decoding: data[0..<4], as: UTF8.self) == "RIFF",
          String(decoding: data[8..<12], as: UTF8.self) == "WAVE" else {
        throw BenchmarkInputError(description: "Expected RIFF/WAVE: \(url.lastPathComponent)")
    }
    var position = 12, rate = 0, sampleStart = 0, sampleBytes = 0
    while position <= data.count - 8 {
        let name = String(decoding: data[position..<position + 4], as: UTF8.self)
        let length = uint32(data, at: position + 4), start = position + 8
        guard length <= data.count - start else {
            throw BenchmarkInputError(description: "Truncated WAV chunk: \(url.lastPathComponent)")
        }
        if name == "fmt " {
            guard length >= 16, uint16(data, at: start) == 1,
                  uint16(data, at: start + 2) == 1, uint16(data, at: start + 14) == 16 else {
                throw BenchmarkInputError(description: "Expected original mono PCM16")
            }
            rate = uint32(data, at: start + 4)
        }
        if name == "data" { sampleStart = start; sampleBytes = length }
        position = start + length + length % 2
    }
    guard rate == 44_100, sampleBytes > 0, sampleBytes % 2 == 0 else {
        throw BenchmarkInputError(description: "Expected original 44.1 kHz PCM16 audio")
    }
    let total = sampleBytes / 2, count = min(total, rate * 30)
    let samples = (0..<count).map { index in
        Float(Int16(bitPattern: UInt16(uint16(data, at: sampleStart + index * 2)))) / 32_768
    }
    return (samples, Double(rate), total)
}

do {
    guard CommandLine.arguments.count == 3 else {
        throw BenchmarkInputError(description: "Usage: VoiceBenchmark <external corpus path> <external analysis.json>")
    }
    let root = URL(fileURLWithPath: CommandLine.arguments[1])
    let output = URL(fileURLWithPath: CommandLine.arguments[2]), started = Date()
    var reports = [[String: Any]]()
    // Fixed development split only. Reserved holdout IDs 9–16 are never read.
    for id in 1...8 {
        let input = try readWave(root.appendingPathComponent("Audio/vocadito_\(id).wav"))
        let frames = try VoiceAnalyzer.frames(input.samples, sampleRate: input.rate, detector: .yin)
        let analysis = try VoiceAnalyzer.analyze(input.samples, sampleRate: input.rate, detector: .yin)
        let notes = VoiceAnalyzer.notes(analysis, bpm: 120, length: 64 * barTicks, quantize: .off)
        let frameRows: [[String: Any]] = frames.map {
            ["time": $0.time, "frequency": $0.frequency.map { $0 as Any } ?? NSNull(),
             "confidence": $0.confidence, "rms": $0.rms]
        }
        let segmentRows: [[String: Any]] = analysis.segments.map {
            ["start": $0.start, "duration": $0.duration, "pitch": $0.pitch,
             "confidence": $0.confidence, "cents": $0.cents]
        }
        let noteRows: [[String: Any]] = notes.map {
            ["tick": $0.tick, "duration": $0.duration, "pitch": $0.pitch,
             "confidence": $0.confidence.map { $0 as Any } ?? NSNull()]
        }
        reports.append([
            "id": id, "rawSampleFrames": input.rawFrames, "inputSamples": input.samples.count,
            "sampleRate": input.rate, "duration": Double(input.samples.count) / input.rate,
            "frames": frameRows, "segments": segmentRows, "notes": noteRows
        ])
        print("Vocadito \(id): \(input.samples.count) input samples, \(frames.count) frames, \(notes.count) notes")
    }
    let result: [String: Any] = [
        "detector": "yin", "bpmForMIDIConversion": 120, "ppq": ppq,
        "temporalQuantization": "off", "scaleProjection": false,
        "trim": "First min(30.000 seconds, full duration), offset 0",
        "reports": reports, "elapsedSeconds": Date().timeIntervalSince(started)
    ]
    try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]).write(to: output, options: .atomic)
} catch {
    FileHandle.standardError.write(Data("Voice benchmark: \(error)\n".utf8))
    exit(1)
}
