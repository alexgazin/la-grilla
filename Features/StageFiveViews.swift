import SwiftUI
import UIKit
import AVFoundation
import PhotosUI
import Vision
import UniformTypeIdentifiers
import MusicDomain

/// The harmony pattern under the selected section (where imported chords go).
@MainActor private func harmonyTarget(_ session: Session) -> (patternIndex: Int, length: Int)? {
    let section = session.section
    guard let track = session.project.tracks.first(where: { $0.role == .harmony }),
          let clip = track.clips.first(where: { $0.start <= section.start && section.start < $0.start + $0.length }),
          let index = session.project.patterns.firstIndex(where: { $0.id == clip.patternID }) else { return nil }
    return (index, session.project.patterns[index].length)
}

/// I4 · I17 · Chords from a song (audio file) or from text and photos of a songbook.
struct ChordImportView: View {
    @Bindable var session: Session
    enum Mode: Hashable { case song, text }
    enum Source: Hashable { case current, imported }
    @State private var mode = Mode.song
    @State private var source = Source.imported
    // From a song
    @State private var importing = false
    @State private var analysing = false
    @State private var tempo: Double?
    @State private var useTempo = true
    @State private var recognised: [AudioListening.RecognisedChord] = []
    // From text or photo
    @State private var text = ""
    @State private var photo: PhotosPickerItem?
    @State private var reading = false
    @State private var error: String?

    private var bars: [[Chord]] {
        switch mode {
        case .text: return ChordTextParser.parse(text).bars
        case .song:
            // One chord per segment; segments are one bar long. Repeats collapse.
            return recognised.map { [$0.chord] }
        }
    }

    private func candidate() -> Project? {
        guard let target = harmonyTarget(session), !bars.isEmpty else { return nil }
        var project = session.project
        let events = ChordTextParser.events(bars).filter { $0.tick < target.length }.map { event -> ChordEvent in
            var clipped = event; clipped.duration = min(event.duration, target.length - event.tick); return clipped
        }
        project.patterns[target.patternIndex].chords = events
        if mode == .song, useTempo, let tempo { project.bpm = min(240, max(40, tempo)) }
        return (try? project.validate()) == nil ? nil : project
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    StudioSegments(title: "Take chords from", selection: $mode, options: [(.song, "A song"), (.text, "Text or photo")], identifier: "chords.mode")
                    if mode == .song { songPanel } else { textPanel }
                    if let error { Text(LocalizedStringKey(error)).font(.callout).foregroundStyle(Color.record) }
                    if !bars.isEmpty {
                        Text("\(bars.count) bars of chords · they replace the chords of “\(session.section.name)”").font(.caption).foregroundStyle(Color.muted)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(Array(bars.prefix(32).enumerated()), id: \.offset) { _, bar in
                                    Text(verbatim: bar.map(\.symbol).joined(separator: " ")).font(.caption.monospaced())
                                        .padding(.horizontal, 8).padding(.vertical, 6).background(Color.raised, in: Capsule())
                                }
                            }
                        }.accessibilityIdentifier("chords.preview")
                        AuditionBar(screen: "chords", source: $source, sources: [(.current, "As it is"), (.imported, "With these chords")],
                                    playing: session.harmonyPreview, enabled: candidate() != nil,
                                    caption: "Nothing changes until you apply the chords.", play: play, stop: { session.endHarmonyPreview() })
                        Button { apply() } label: { Text("Apply chords").frame(maxWidth: .infinity, minHeight: 48) }
                            .buttonStyle(StudioActionStyle()).disabled(candidate() == nil || session.recording || session.armed)
                            .accessibilityIdentifier("chords.apply")
                    }
                }.padding(18)
            }
            .background(Color.ink)
            .navigationTitle("Chords from…").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { session.endHarmonyPreview(); session.sheet = nil } } }
        }
        .tint(.mint)
        .onDisappear { session.endHarmonyPreview() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio, .mp3, .wav, .aiff, .mpeg4Audio]) { result in
            if case .success(let url) = result { Task { await analyse(url) } } else if case .failure(let failure) = result { error = failure.localizedDescription }
        }
        .onChange(of: photo) { _, item in if let item { Task { await read(item) } } }
    }

    private var songPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pick a song file. The first minute is analysed on this iPhone: tempo and one chord per bar.")
                .font(.caption).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
            Button { importing = true } label: {
                HStack { if analysing { ProgressView() }; Label("Choose a song", systemImage: "music.note") }.frame(maxWidth: .infinity, minHeight: 48)
            }.buttonStyle(StudioActionStyle(color: .mint, prominent: recognised.isEmpty)).disabled(analysing).accessibilityIdentifier("chords.song")
            if let tempo {
                Toggle(isOn: $useTempo) { Text("Use the song’s tempo: \(Int(tempo.rounded())) BPM") }.accessibilityIdentifier("chords.tempo")
                HStack {
                    Button("Half") { self.tempo = max(40, tempo / 2) }.frame(minHeight: 44)
                    Button("Double") { self.tempo = min(240, tempo * 2) }.frame(minHeight: 44)
                }.font(.caption)
            }
        }
    }

    private var textPanel: some View {
        // Older SDKs run the picker's label outside the main actor: read state first.
        let busy = reading
        return VStack(alignment: .leading, spacing: 10) {
            Text("Paste chords or a songbook page, or take them from a photo. Chord lines are found among the lyrics; | marks bars, |: :| and x2 repeat.")
                .font(.caption).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $text).font(.body.monospaced()).frame(minHeight: 140).scrollContentBackground(.hidden)
                .padding(8).background(Color.raised, in: RoundedRectangle(cornerRadius: Luz.Radius.cell, style: .continuous))
                .accessibilityIdentifier("chords.text")
            PhotosPicker(selection: $photo, matching: .images) {
                HStack { if busy { ProgressView() }; Label("Read chords from a photo", systemImage: "camera.viewfinder") }.frame(maxWidth: .infinity, minHeight: 48)
            }.buttonStyle(StudioActionStyle(color: .mint, prominent: false)).disabled(busy).accessibilityIdentifier("chords.photo")
        }
    }

    private func play() {
        if source == .current { session.previewSnapshot(session.project) } else if let project = candidate() { session.previewSnapshot(project) }
    }

    private func apply() {
        guard let project = candidate(), let target = harmonyTarget(session) else { return }
        let chords = project.patterns[target.patternIndex].chords, bpm = project.bpm
        session.endHarmonyPreview()
        session.edit { p in p.patterns[target.patternIndex].chords = chords; p.bpm = bpm }
        session.sheet = nil
        Luz.Haptics.success()
    }

    /// Decodes up to 60 s of the file as mono at its own rate, off the main thread.
    private func analyse(_ url: URL) async {
        analysing = true; error = nil; defer { analysing = false }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let (samples, rate) = try await Task.detached(priority: .userInitiated) { () throws -> ([Float], Double) in
                let file = try AVAudioFile(forReading: url)
                let format = file.processingFormat
                let frames = AVAudioFrameCount(min(Double(file.length), format.sampleRate * 60))
                guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { throw MusicError.invalidProject }
                try file.read(into: buffer, frameCount: frames)
                guard let channels = buffer.floatChannelData else { throw MusicError.invalidProject }
                let count = Int(buffer.frameLength), channelCount = Int(format.channelCount)
                var mono = [Float](repeating: 0, count: count)
                for channel in 0..<channelCount { for index in 0..<count { mono[index] += channels[channel][index] / Float(channelCount) } }
                return (mono, format.sampleRate)
            }.value
            let found = AudioListening.tempo(samples, sampleRate: rate)
            tempo = found
            let barSeconds = 60 / (found ?? session.project.bpm) * 4
            recognised = await Task.detached(priority: .userInitiated) { AudioListening.chords(samples, sampleRate: rate, segmentSeconds: barSeconds) }.value
            if recognised.isEmpty { error = "No chords were found in this file." }
        } catch { self.error = NSLocalizedString("This file could not be read as audio.", comment: "Chord import") }
    }

    /// On-device text recognition (English and Russian) of a songbook photo.
    private func read(_ item: PhotosPickerItem) async {
        reading = true; error = nil; defer { reading = false; photo = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data)?.cgImage else { error = "This photo could not be opened."; return }
        let lines: [String] = await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US", "ru-RU"]
            request.usesLanguageCorrection = false
            try? VNImageRequestHandler(cgImage: image).perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        }.value
        guard !lines.isEmpty else { error = "No text was found in this photo."; return }
        text = lines.joined(separator: "\n")
        if ChordTextParser.parse(text).bars.isEmpty { error = "Text was found, but no chords in it. You can correct it above." }
    }
}

/// I10 · Four melody ideas over the chords of this section, for the open melody part.
struct MelodyIdeasView: View {
    @Bindable var session: Session
    @State private var seed: UInt64 = 1
    @State private var density = 1
    @State private var source = Source.idea
    enum Source: Hashable { case current, idea }

    private var pattern: Pattern? { session.project.patterns.first { $0.id == session.toolPatternID } }
    private var clip: Clip? { session.project.tracks.flatMap(\.clips).first { $0.patternID == session.toolPatternID } }

    private func melody(_ seed: UInt64) -> [NoteEvent] {
        guard let pattern, let clip else { return [] }
        let section = MusicDomain.Section(name: "Ideas", start: clip.start, length: min(clip.length, pattern.length))
        let chords = Arrangement.harmony(session.project, section: section)
        return MelodySketcher.melody(chords: chords, length: section.length, keyRoot: session.project.keyRoot, minor: session.project.minor,
                                     density: [0.25, 0.5, 0.8][density], seed: seed)
    }

    private func candidate(_ seed: UInt64) -> Project? {
        guard let id = pattern?.id, let index = session.project.patterns.firstIndex(where: { $0.id == id }) else { return nil }
        var project = session.project; project.patterns[index].notes = melody(seed); return project
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Ideas follow the chords of this section and the song’s key. Hum over them, then keep the one you like.")
                        .font(.caption).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
                    StudioSegments(title: "Density", selection: $density, options: [(0, "Calm"), (1, "Flowing"), (2, "Busy")], identifier: "melody.density")
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(1...4, id: \.self) { index in
                            let value = UInt64(index) &+ (seed &* 10)
                            Button { selected = value; if session.harmonyPreview { play() } } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: "music.note.list").font(.title3)
                                    Text("Idea \(index)").font(.subheadline.weight(.semibold))
                                    Text("\(melody(value).count) notes").font(.caption2).foregroundStyle(Color.muted)
                                }.frame(maxWidth: .infinity, minHeight: 80)
                                    .background(selected == value ? Color.mint.opacity(0.2) : Color.panel, in: RoundedRectangle(cornerRadius: Luz.Radius.cell, style: .continuous))
                            }.buttonStyle(StudioQuietButtonStyle()).accessibilityIdentifier("melody.idea.\(index - 1)")
                        }
                    }
                    Button { seed &+= 1; selected = UInt64(1) &+ (seed &* 10) } label: { Label("Four new ideas", systemImage: "dice") }.frame(minHeight: 44)
                    AuditionBar(screen: "melody", source: $source, sources: [(.current, "As it is"), (.idea, "This idea")],
                                playing: session.harmonyPreview, caption: "The part changes only when you apply the idea.",
                                play: play, stop: { session.endHarmonyPreview() })
                    Button { apply() } label: { Text("Use this idea").frame(maxWidth: .infinity, minHeight: 48) }
                        .buttonStyle(StudioActionStyle()).disabled(pattern == nil || session.recording || session.armed)
                        .accessibilityIdentifier("melody.apply")
                    Text("It replaces the notes of this part. One Undo brings them back.").font(.caption).foregroundStyle(Color.muted)
                }.padding(18)
            }
            .background(Color.ink)
            .navigationTitle("Melody ideas").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { session.endHarmonyPreview(); session.sheet = .notes } } }
        }
        .tint(.mint)
        .onDisappear { session.endHarmonyPreview() }
        .onChange(of: density) { _, _ in if session.harmonyPreview { play() } }
    }

    @State private var selected: UInt64 = 11

    private func play() {
        if source == .current { session.previewSnapshot(session.project) } else if let project = candidate(selected) { session.previewSnapshot(project) }
    }

    private func apply() {
        guard let id = pattern?.id else { return }
        let notes = melody(selected)
        session.endHarmonyPreview()
        session.edit { p in if let index = p.patterns.firstIndex(where: { $0.id == id }) { p.patterns[index].notes = notes } }
        session.sheet = .notes
        Luz.Haptics.success()
    }
}
