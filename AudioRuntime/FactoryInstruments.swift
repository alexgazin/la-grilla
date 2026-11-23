import Foundation
import MusicDomain

enum FactoryInstrument: String, CaseIterable, Identifiable, Sendable {
    case piano
    case nylonGuitar = "nylon-guitar"

    case flute, bansuri, gong, ambientPad
    case electricPiano = "electric-piano"
    case marimba, vibraphone, organ
    case altoSax = "alto-sax", tenorSax = "tenor-sax", sopranoSax = "soprano-sax", baritoneSax = "baritone-sax"
    /// Beat machine synths: 808s and basses, then leads, keys and pads (rendered on the device).
    case sub808 = "synth-808-sub", punch808 = "synth-808-punch", dirty808 = "synth-808-dirty", logDrum = "synth-log-drum"
    case reeseBass = "synth-reese-bass", acidBass = "synth-acid-bass", fingerBass = "synth-finger-bass", squareBass = "synth-square-bass"
    case supersaw = "synth-supersaw", synthPluck = "synth-synth-pluck", bellKeys = "synth-bell-keys", lofiKeys = "synth-lofi-keys"
    case synthBrass = "synth-synth-brass", stringPad = "synth-string-pad", choirPad = "synth-choir-pad", chipLead = "synth-chip-lead"

    /// The on-device synth behind this instrument, if it is one.
    var synth: FactorySynth? { rawValue.hasPrefix("synth-") ? FactorySynth(rawValue: String(rawValue.dropFirst(6))) : nil }

    var artwork: String { self == .ambientPad ? "instrument-ambient-pad" : (saxVoice == nil ? "instrument-" + id : "instrument-sax") }

    private var saxVoice: ReedVoice? {
        switch self {
        case .altoSax: ReedVoice(formant:1180,brightness:0.66,breath:0.024,vibrato:0.55,attack:0.038)
        case .tenorSax: ReedVoice(formant:820,brightness:0.50,breath:0.052,vibrato:0.69,attack:0.060)
        case .sopranoSax: ReedVoice(formant:1700,brightness:0.76,breath:0.017,vibrato:0.43,attack:0.028)
        case .baritoneSax: ReedVoice(formant:610,brightness:0.57,breath:0.032,vibrato:0.34,attack:0.075)
        default:nil
        }
    }

    var isRecorded: Bool { self == .piano || self == .nylonGuitar }

    var id: String { rawValue }

    private var nameKey: String {
        if let synth { return synth.title }
        return switch self {
        case .piano: "Acoustic piano"
        case .nylonGuitar: "Nylon guitar"
        case .flute: "Synth flute"
        case .bansuri: "Bansuri"
        case .gong: "Gong"
        case .ambientPad: "Ambient pad"
        case .electricPiano: "Electric piano"
        case .marimba: "Marimba"
        case .vibraphone: "Vibraphone"
        case .organ: "Drawbar organ"
        case .altoSax: "Alto sax"
        case .tenorSax: "Tenor sax"
        case .sopranoSax: "Soprano sax"
        case .baritoneSax: "Baritone sax"
        default: rawValue
        }
    }

    var displayName: String { NSLocalizedString(nameKey, comment: "Studio instrument") }

    private static let persistedNames: [Self: Set<String>] = {
        let catalogs = ["en", "ru"].compactMap { language in
            Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:))
        }
        return Dictionary(uniqueKeysWithValues: allCases.map { instrument in
            let names = catalogs.map { $0.localizedString(forKey: instrument.nameKey, value: nil, table: nil) }
            return (instrument, Set(names + [instrument.nameKey]))
        })
    }()

    func matches(name: String?) -> Bool {
        guard let name else { return false }
        return Self.persistedNames[self]?.contains(name) == true
    }

}

extension SoundBankLibrary {
    func prepareTrackDraft(brief: TrackBrief, name: String, sourcePrompt: String = "") throws -> PreparedTrackDraft {
        let directory = Bundle.main.resourceURL?.appendingPathComponent("FactoryInstruments", isDirectory: true)
        return try PreparedTrackDraft.make(brief: brief, name: name, factoryDirectory: directory, sourcePrompt: sourcePrompt)
    }

    private struct FactoryManifest: Decodable {
        struct Instrument: Decodable { let sha256: String }
        let guitar: Instrument
    }

    func prepareFactoryInstrument(_ instrument: FactoryInstrument, directory: URL? = nil) throws -> PreparedSound {
        let factoryDirectory = directory ?? Bundle.main.resourceURL?.appendingPathComponent("FactoryInstruments", isDirectory: true)
        if let timbre = ArrangerTimbre(rawValue: instrument.rawValue) {
            return try PreparedSound(name: instrument.displayName, instrumentData: timbre.sampleData(factoryDirectory: factoryDirectory), ringsOut: timbre == .gong)
        }
        if let synth = instrument.synth {
            return try PreparedSound(name: instrument.displayName, kind: .instrument, pcm: synth.pcm())
        }
        if !instrument.isRecorded {
            return try PreparedSound(name: instrument.displayName, kind: .instrument, pcm: instrument.synthesize())
        }
        guard let root = factoryDirectory else {
            throw SampleError.unavailable
        }
        let manifest = try JSONDecoder().decode(FactoryManifest.self, from: Data(contentsOf: root.appendingPathComponent("manifest.json")))
        let record = manifest.guitar
        let url = root.appendingPathComponent(instrument.rawValue).appendingPathExtension("lgpcm")
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let sound = try PreparedSound(name: instrument.displayName, instrumentData: data)
        guard sound.asset.sha256 == record.sha256 else { throw SampleError.invalid }
        return sound
    }

    func auditionFactoryInstrument(_ instrument: FactoryInstrument) async throws -> URL {
        let prepared = try prepareFactoryInstrument(instrument)
        var project = Project.demo(), library = SampleLibrary()
        let harmony = project.tracks[0].id
        project = try TrackSoundPreview.project(from: project, trackID: harmony, palette: .classic)
        project.tracks[0].instrumentSample = prepared.asset
        library.insert(try PreparedSampleBank(asset: prepared.asset, data: prepared.data))
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")
        let settings = WAVSettings(sampleRate: 48_000, bitDepth: 16, tailSeconds: 0, dither: false)
        _ = try await OfflineRenderer.render(project, to: path, settings: settings, isolatedTrack: harmony, samples: library)
        return path
    }
}

private extension FactoryInstrument {
    func synthesize() throws -> SamplePCM {
        let rate = 32_000
        let zones = try stride(from: 36, through: 96, by: 6).map { pitch in
            try Task.checkCancellation()
            let frequency = 440 * pow(2.0, Double(pitch - 69) / 12)
            // Whole cycles at both ends of the organ loop keep held chords seamless.
            let cycles = Int(frequency.rounded())
            let periodFrames = Int((Double(rate * cycles) / frequency).rounded())
            let length = periodFrames * 2
            let reed = saxVoice
            let weights = reed?.weights(frequency:frequency,rate:rate) ?? []
            var noise = UInt32(pitch + 1)
            var previousNoise = 0.0
            var pcm = [Int16]()
            pcm.reserveCapacity(length)
            for frame in 0..<length {
                let t = Double(frame) / Double(rate)
                let phase = 2 * Double.pi * Double(frame * cycles) / Double(periodFrames)
                let sample: Double
                switch self {
                case .electricPiano:
                    let tine = 2.3 * exp(-4 * t) * sin(phase * 2)
                    sample = exp(-1.8 * t) * sin(phase + tine)
                case .marimba:
                    sample = 0.85 * exp(-3.8 * t) * sin(phase) + 0.36 * exp(-15 * t) * sin(phase * 4)
                case .vibraphone:
                    let metal = sin(phase) + 0.3 * exp(-6 * t) * sin(phase * 3.99)
                    sample = exp(-1.6 * t) * (0.83 + 0.17 * cos(2 * .pi * 5.4 * t)) * metal
                case .organ:
                    sample = 0.59 * sin(phase) + 0.27 * sin(2 * phase) + 0.14 * sin(3 * phase)
                case .altoSax, .tenorSax, .sopranoSax, .baritoneSax:
                    guard let reed else { throw SampleError.invalid }
                    // Periodic vibrato and whole cycles give the sustain loop a matching reed phase.
                    let vibrato = sin(2 * .pi * 5 * Double(frame) / Double(periodFrames))
                    let angle = phase + reed.vibrato * vibrato * min(1,t*3)
                    let c = 2 * cos(angle)
                    var previous=0.0, harmonic=sin(angle), tone=0.0
                    for weight in weights {
                        tone += weight * harmonic
                        (previous,harmonic)=(harmonic,c*harmonic-previous)
                    }
                    noise = noise &* 1664525 &+ 1013904223
                    let white = Double(noise)/Double(UInt32.max) * 2 - 1
                    let air = (white-previousNoise) * reed.breath * (0.4+exp(-22*t))
                    previousNoise=white
                    sample = (tone+air) * (1-exp(-t/reed.attack))
                default:
                    throw SampleError.invalid
                }
                let attack = min(1, t * 350)
                let tail = self == .organ || reed != nil ? 1 : min(1, Double(length - frame - 1) / 400)
                pcm.append(Int16(clamping: Int((sample * attack * tail * 9500).rounded())))
            }
            return SamplePCM.Zone(pitch: pitch, samples: pcm, loopStart: self == .organ || reed != nil ? periodFrames : 0)
        }
        return SamplePCM(rate: rate, zones: zones)
    }
}

/// Band-limited reed excitation shaped by two bore resonances.
private struct ReedVoice {
    let formant:Double, brightness:Double, breath:Double, vibrato:Double, attack:Double
    func weights(frequency:Double,rate:Int)->[Double] {
        let count=max(1,min(16,Int(Double(rate)*0.45/frequency)))
        let values=(1...count).map { n -> Double in
            let f=Double(n)*frequency
            let body=exp(-pow(log2(f/formant)/0.8,2))
            let edge=exp(-pow(log2(f/(formant*2.5))/0.63,2))
            return (0.52+1.5*body+brightness*edge)/pow(Double(n),1.46-brightness*0.5)
        }
        let norm=values.reduce(0,+)
        return values.map{1.5*$0/norm}
    }
}
