import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import MusicDomain

/// I42 · A player for working out a song by ear: loop a passage, slow it down without
/// changing pitch, shift the pitch, while the studio's transport is stopped.
@MainActor @Observable final class PracticePlayer {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private var file: AVAudioFile?
    var title = ""
    var duration: Double = 0
    var loopStart: Double = 0
    var loopEnd: Double = 0
    var rate: Double = 1 { didSet { timePitch.rate = Float(rate) } }
    var semitones: Double = 0 { didSet { timePitch.pitch = Float(semitones * 100) } }
    var playing = false
    var error: String?

    init() {
        engine.attach(node); engine.attach(timePitch)
        engine.connect(node, to: timePitch, format: nil)
        engine.connect(timePitch, to: engine.mainMixerNode, format: nil)
    }

    func load(_ url: URL) {
        stop()
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            // Copy first: the security scope ends when this returns, the player reads later.
            let local = FileManager.default.temporaryDirectory.appendingPathComponent("Practice-" + UUID().uuidString).appendingPathExtension(url.pathExtension)
            try FileManager.default.copyItem(at: url, to: local)
            let opened = try AVAudioFile(forReading: local)
            file = opened
            title = url.deletingPathExtension().lastPathComponent
            duration = Double(opened.length) / opened.processingFormat.sampleRate
            loopStart = 0; loopEnd = duration
            engine.disconnectNodeOutput(node)
            engine.connect(node, to: timePitch, format: opened.processingFormat)
            error = nil
        } catch { self.error = NSLocalizedString("This file could not be read as audio.", comment: "Chord import") }
    }

    func play() {
        guard let file, loopEnd > loopStart else { return }
        do { if !engine.isRunning { try engine.start() } } catch { self.error = error.localizedDescription; return }
        node.stop()
        scheduleLoop(file)
        node.play()
        playing = true
    }

    private func scheduleLoop(_ file: AVAudioFile) {
        let rate = file.processingFormat.sampleRate
        let start = AVAudioFramePosition(loopStart * rate), frames = AVAudioFrameCount(max(1, (loopEnd - loopStart) * rate))
        node.scheduleSegment(file, startingFrame: start, frameCount: frames, at: nil) { [weak self] in
            Task { @MainActor in guard let self, self.playing, let file = self.file else { return }; self.scheduleLoop(file) }
        }
    }

    func stop() { playing = false; node.stop(); if engine.isRunning { engine.pause() } }
}

struct PracticePlayerView: View {
    @Bindable var session: Session
    @State private var player = PracticePlayer()
    @State private var importing = false

    private func time(_ seconds: Double) -> String { String(format: "%d:%04.1f", Int(seconds) / 60, seconds.truncatingRemainder(dividingBy: 60)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Load a song to work out its chords or melody. The studio stops while this plays.").font(.caption).foregroundStyle(Color.muted)
                    Button { importing = true } label: { Label(player.title.isEmpty ? "Choose a song" : player.title, systemImage: "music.note").frame(maxWidth: .infinity, minHeight: 48) }
                        .buttonStyle(StudioActionStyle(color: .mint, prominent: player.title.isEmpty)).accessibilityIdentifier("practice.load")
                    if let error = player.error { Text(LocalizedStringKey(error)).foregroundStyle(Color.record) }
                    if player.duration > 0 {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack { Text("Loop from"); Spacer(); Text(verbatim: time(player.loopStart)).monospacedDigit() }
                            Slider(value: Binding(get: { player.loopStart }, set: { player.loopStart = min($0, player.loopEnd - 0.5) }), in: 0...max(0.5, player.duration))
                            HStack { Text("to"); Spacer(); Text(verbatim: time(player.loopEnd)).monospacedDigit() }
                            Slider(value: Binding(get: { player.loopEnd }, set: { player.loopEnd = max($0, player.loopStart + 0.5) }), in: 0...max(0.5, player.duration))
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            HStack { Text("Speed"); Spacer(); Text("\(Int(player.rate * 100))%").monospacedDigit() }
                            Slider(value: $player.rate, in: 0.5...1, step: 0.05).accessibilityIdentifier("practice.speed")
                            HStack { Text("Pitch"); Spacer(); Text(verbatim: String(format: "%+.0f", player.semitones)).monospacedDigit() }
                            Slider(value: $player.semitones, in: -6...6, step: 1)
                        }
                        Button { player.playing ? player.stop() : { session.audio.stop(); player.play() }() } label: {
                            Label(LocalizedStringKey(player.playing ? "Stop" : "Play"), systemImage: player.playing ? "stop.fill" : "play.fill").font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                        }.buttonStyle(StudioActionStyle(color: player.playing ? .record : .mint)).accessibilityIdentifier("practice.play")
                        Text("Changes apply on the next loop.").font(.caption2).foregroundStyle(Color.muted)
                    }
                }.padding(18)
            }
            .background(Color.ink)
            .navigationTitle("Work out a song").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { player.stop(); session.sheet = nil } } }
        }
        .tint(.mint)
        .onDisappear { player.stop() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio, .mp3, .wav, .aiff, .mpeg4Audio]) { result in
            if case .success(let url) = result { player.load(url) }
        }
    }
}
