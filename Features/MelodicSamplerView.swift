import AVFoundation
import MusicDomain
import SwiftUI
import UniformTypeIdentifiers

/// I31 · "Make an instrument from a sound": record (up to 8 s) or import a sound, find its note,
/// shape its start and end, then play it on every key of this track (one Undo).
struct MelodicSamplerView: View {
    let session: Session
    let trackID: UUID
    let projectID: UUID
    let revision: Int
    let done: () -> Void

    @State private var samples: [Float] = []
    @State private var root = 60
    @State private var detectedCents: Double?
    @State private var attack = 0.005
    @State private var ringsOut = true
    @State private var voice: VoicePreset?
    @State private var name = ""
    @State private var recording = false
    @State private var importing = false
    @State private var working = false
    @State private var error: String?
    @State private var microphone: LiveMicrophone?
    @State private var owner: UUID?
    @State private var player: AVAudioPlayer?
    @State private var capture = TunerCapture()

    var body: some View {
        List {
            Section {
                HStack(spacing: 10) {
                    Button { recording ? stopRecording() : startRecording() } label: {
                        Label(LocalizedStringKey(recording ? "Stop" : "Record"), systemImage: recording ? "stop.fill" : "record.circle")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(StudioActionStyle(color: .record, prominent: recording))
                    .accessibilityIdentifier("sampler.record")
                    Button { importing = true } label: {
                        Label("Import", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(StudioActionStyle(color: .mint, prominent: false))
                    .disabled(recording || working)
                    .accessibilityIdentifier("sampler.import")
                }
                if recording { Text("Play or sing one note, up to 8 seconds.").font(.footnote).foregroundStyle(Color.muted) }
            } footer: { Text("One clear note works best: a voice, a glass, a string, a bottle.") }

            if !samples.isEmpty {
                Section("The note") {
                    Stepper(value: $root, in: 24...96) {
                        LabeledContent("Played as") {
                            Text(verbatim: MelodicSampler.name(root: root, label: "").replacingOccurrences(of: " · ", with: "")).monospacedDigit()
                        }
                    }
                    .accessibilityIdentifier("sampler.root")
                    if let detectedCents {
                        Text("Found \(MelodicSampler.name(root: root, label: "").replacingOccurrences(of: " · ", with: "")), \(Int(detectedCents.rounded())) cents")
                            .font(.footnote).foregroundStyle(Color.muted).accessibilityIdentifier("sampler.detected")
                    } else {
                        Text("No clear note found: set it by ear.").font(.footnote).foregroundStyle(Color.muted)
                    }
                    Button { hear() } label: { Label("Hear the sound", systemImage: "speaker.wave.2") }
                        .accessibilityIdentifier("sampler.hear")
                }
                Section("Shape") {
                    VStack(alignment: .leading) {
                        Text("Soft start \(Int(attack * 1000)) ms").font(.subheadline)
                        Slider(value: $attack, in: 0.001...1).accessibilityIdentifier("sampler.attack")
                    }
                    Picker("Each note", selection: $ringsOut) {
                        Text("Rings to its end").tag(true)
                        Text("Holds while pressed").tag(false)
                    }
                    .accessibilityIdentifier("sampler.release")
                    Picker("Voice treatment", selection: Binding(get: { voice?.rawValue ?? 0 }, set: { voice = VoicePreset(rawValue: $0) })) {
                        Text("None").tag(0)
                        ForEach(VoicePreset.allCases, id: \.self) { preset in Text(LocalizedStringKey(preset.title)).tag(preset.rawValue) }
                    }
                    .accessibilityIdentifier("sampler.voice")
                    TextField("Name", text: $name).accessibilityIdentifier("sampler.name")
                }
            }
            if let error { Text(error).foregroundStyle(Color.record).accessibilityIdentifier("sampler.error") }
        }
        .scrollContentBackground(.hidden).background(Color.ink)
        .navigationTitle("Instrument from a sound").navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button { apply() } label: {
                Label("Play it on this track", systemImage: "pianokeys").frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(StudioActionStyle())
            .disabled(samples.isEmpty || recording || working)
            .padding(16).background(Color.ink)
            .accessibilityIdentifier("sampler.apply")
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio, .movie]) { result in
            if case let .success(url) = result { load(url) } else if case let .failure(failure) = result { error = failure.localizedDescription }
        }
        .onDisappear { stopRecording(); player?.stop() }
    }

    private func use(_ raw: [Float], rate: Double) {
        let prepared = MelodicSampler.prepare(raw, rate: rate)
        guard prepared.count >= 2048 else { error = NSLocalizedString("The sound is too short or silent. Try again a little louder.", comment: "Sampler"); return }
        samples = prepared
        error = nil
        if let found = MelodicSampler.detectRoot(prepared, rate: Double(MelodicSampler.rate)) {
            root = min(96, max(24, found.pitch)); detectedCents = found.cents
        } else { detectedCents = nil }
    }

    private func startRecording() {
        error = nil
        Task {
            guard await AVAudioApplication.requestRecordPermission() else {
                error = NSLocalizedString("Recording a sound needs the microphone. Allow it for La Grilla in Settings.", comment: "Sampler"); return
            }
            guard session.ensureAudio() else { error = session.audio.error; return }
            let sink = TunerCapture(); capture = sink
            do {
                let mic = try LiveMicrophone(audio: session.audio, delay: 0, duration: MelodicSampler.maxSeconds,
                                             receiver: { _ in LiveInputReceiver(receive: { @Sendable buffer in sink.append(buffer) }, finish: { @Sendable in }) },
                                             onFailure: { message in error = message; recording = false })
                microphone = mic
                owner = session.beginMicrophone { try? mic.stop() }
                recording = true
                try? await Task.sleep(for: .seconds(MelodicSampler.maxSeconds))
                if recording { stopRecording() }
            } catch { self.error = error.localizedDescription }
        }
    }

    private func stopRecording() {
        guard recording || microphone != nil else { return }
        try? microphone?.stop()
        microphone = nil
        if let owner { session.endMicrophone(owner) }
        owner = nil
        recording = false
        let taken = capture.take()
        if !taken.samples.isEmpty { use(taken.samples, rate: taken.rate) }
    }

    private func load(_ url: URL) {
        working = true
        Task {
            defer { working = false }
            do {
                let wav = try await AudioExtraction.wavIfNeeded(url, limit: MelodicSampler.maxSeconds + 2)
                let granted = wav.startAccessingSecurityScopedResource()
                defer { if granted { wav.stopAccessingSecurityScopedResource() } }
                let file = try AVAudioFile(forReading: wav, commonFormat: .pcmFormatFloat32, interleaved: false)
                let frames = min(file.length, AVAudioFramePosition(file.processingFormat.sampleRate * (MelodicSampler.maxSeconds + 2)))
                guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(frames)),
                      let _ = try? file.read(into: buffer, frameCount: AVAudioFrameCount(frames)), let channels = buffer.floatChannelData else { throw SampleError.invalid }
                let count = Int(buffer.frameLength), channelCount = Int(buffer.format.channelCount)
                let mono = (0..<count).map { index in (0..<channelCount).reduce(Float(0)) { $0 + channels[$1][index] } / Float(channelCount) }
                if name.isEmpty { name = url.deletingPathExtension().lastPathComponent }
                use(mono, rate: file.processingFormat.sampleRate)
            } catch { self.error = error.localizedDescription }
        }
    }

    private func hear() {
        guard !samples.isEmpty else { return }
        let sound = voice.map { VoiceTreatment.apply(samples, rate: MelodicSampler.rate, preset: $0) } ?? samples
        guard session.ensureAudio(), let audio = try? AVAudioPlayer(data: MelodicSampler.previewWAV(sound)) else { return }
        player?.stop(); player = audio; audio.play()
    }

    private func apply() {
        working = true; error = nil
        let shape = MelodicSampler.Shape(attack: attack, ringsOut: ringsOut), voice = voice, samples = samples
        Task {
            defer { working = false }
            do {
                let sound = voice.map { VoiceTreatment.apply(samples, rate: MelodicSampler.rate, preset: $0) } ?? samples
                let pcm = try MelodicSampler.instrument(sound, root: root, shape: shape)
                let data = try pcm.encode(kind: .instrument)
                let sound = try PreparedSound(name: MelodicSampler.name(root: root, label: name), instrumentData: data, ringsOut: ringsOut)
                try await session.assignSounds([(pad: nil, sound: sound)], trackID: trackID, projectID: projectID, revision: revision)
                Luz.Haptics.selection()
                done()
            } catch { self.error = error.localizedDescription }
        }
    }
}

/// Collects microphone audio for the sampler (thread-safe, at most 10 s).
final class TunerCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
    private var rate: Double = 48_000
    func append(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return }
        let count = Int(buffer.frameLength), channelCount = max(1, Int(buffer.format.channelCount))
        let mono = (0..<count).map { index in (0..<channelCount).reduce(Float(0)) { $0 + channels[$1][index] } / Float(channelCount) }
        lock.lock(); defer { lock.unlock() }
        rate = buffer.format.sampleRate
        if samples.count < Int(rate * 10) { samples.append(contentsOf: mono) }
    }
    func take() -> (samples: [Float], rate: Double) {
        lock.lock(); defer { lock.unlock() }
        let result = (samples, rate); samples = []
        return result
    }
}
