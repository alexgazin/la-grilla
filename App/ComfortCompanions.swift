import AVFoundation
import MusicDomain
import SwiftUI

/// U41 · U43 · U57 · Small helpers that follow the transport: a haptic tick on every beat,
/// a spoken count-in before a take, and captions naming what plays.
struct ComfortCompanions: View {
    let session: Session
    @AppStorage("studio.hapticBeats") private var hapticBeats = false
    @AppStorage("studio.voiceCountIn") private var voiceCountIn = false
    @AppStorage("studio.hitCaptions") private var hitCaptions = false
    @State private var lastBeat = -1
    @State private var speaker = AVSpeechSynthesizer()
    @State private var countTask: Task<Void, Never>?

    var body: some View {
        let beat = session.audio.playing ? Int(session.audio.tick) / ppq : -1
        ZStack(alignment: .bottom) {
            Color.clear.frame(width: 0, height: 0)
            if hitCaptions && session.audio.playing {
                HitCaptions(session: session).padding(.bottom, 132).allowsHitTesting(false)
            }
        }
        .onChange(of: beat) { _, value in
            guard hapticBeats, value >= 0, value != lastBeat else { lastBeat = value; return }
            lastBeat = value
            if value % 4 == 0 { Luz.Haptics.hit(velocity: 127) } else { Luz.Haptics.selection() }
        }
        .onChange(of: session.armed) { _, armed in
            countTask?.cancel()
            guard armed, voiceCountIn, session.countIn else { return }
            let interval = 60 / max(40, session.project.bpm)
            let words = ["One", "Two", "Three", "Four"].map { NSLocalizedString($0, comment: "Spoken count-in") }
            let language = Locale.current.language.languageCode?.identifier == "ru" ? "ru-RU" : "en-US"
            countTask = Task { @MainActor in
                for word in words {
                    guard !Task.isCancelled, session.armed else { return }
                    let utterance = AVSpeechUtterance(string: word)
                    utterance.voice = AVSpeechSynthesisVoice(language: language)
                    utterance.rate = min(0.6, AVSpeechUtteranceDefaultSpeechRate * 1.25)
                    speaker.speak(utterance)
                    try? await Task.sleep(for: .seconds(interval))
                }
            }
        }
    }
}

/// Names of the drum and melodic parts sounding now, for players who cannot hear them.
private struct HitCaptions: View {
    let session: Session
    @State private var cache: (revision: Int, notes: [CompiledNote]) = (-1, [])

    var body: some View {
        let tick = Int(session.audio.tick)
        let notes = cache.revision == session.project.revision ? cache.notes : []
        let now = notes.filter { $0.tick <= tick && tick < $0.tick + max(120, min($0.duration, ppq)) }
        let names = Array(Set(now.map(label))).sorted().prefix(4)
        HStack(spacing: 6) {
            ForEach(Array(names), id: \.self) { name in
                Text(verbatim: name).font(.caption.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
        .transaction { $0.animation = nil }
        .accessibilityHidden(true)
        .task(id: session.project.revision) { cache = (session.project.revision, Compiler.notes(session.project)) }
    }

    private func label(_ note: CompiledNote) -> String {
        if note.pad >= 0 { return NSLocalizedString(Compiler.padNames[note.pad], comment: "Pad name") }
        guard session.project.tracks.indices.contains(note.track) else { return "" }
        return session.project.tracks[note.track].displayName
    }
}
