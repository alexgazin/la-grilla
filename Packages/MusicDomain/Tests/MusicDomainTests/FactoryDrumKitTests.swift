import Foundation
import Testing
@testable import MusicDomain

struct FactoryDrumKitTests {
    @Test func everyPadIsAnIndependentBoundedOneShot() throws {
        var samples = Set<Data>()
        for kit in FactoryDrumKit.allCases {
            for pad in Compiler.padNames.indices {
                let pcm = try kit.sample(pad: pad)
                #expect(pcm.count > 2000 && pcm.count <= 2 * FactoryDrumKit.sampleRate)
                #expect(pcm.first == 0 && pcm.last == 0)
                #expect(pcm.contains { abs(Int($0)) > 2048 })
                #expect(samples.insert(pcm.withUnsafeBytes { Data($0) }).inserted)
            }
            #expect(throws: SampleError.invalid) { try kit.sample(pad: -1) }
            #expect(throws: SampleError.invalid) { try kit.sample(pad: 16) }
        }
    }

    @Test func comparisonStartsWithTheActualAssignedKickAndHat() throws {
        var durations = Set<Int>()
        for kit in FactoryDrumKit.allCases {
            let wav = try kit.previewWAV()
            let kick = try kit.sample(pad: 0)
            let hat = try kit.sample(pad: 2)
            let byteCount = wav.count - 44
            #expect(wav.prefix(44) == pcmWAVHeader(rate: FactoryDrumKit.sampleRate, channels: 1,
                                                   bits: 16, byteCount: byteCount))
            durations.insert(byteCount)
            for frame in stride(from: 0, to: min(kick.count, hat.count), by: 83) {
                let offset = 44 + frame * 2
                let actual = Int16(bitPattern: UInt16(wav[offset]) | UInt16(wav[offset + 1]) << 8)
                let mixed = Float(hat[frame]) * 0.77 * 0.72 + Float(kick[frame]) * 0.72
                #expect(actual == Int16(clamping: Int(mixed.rounded())))
            }
        }
        #expect(durations.count == 1)
    }
}
