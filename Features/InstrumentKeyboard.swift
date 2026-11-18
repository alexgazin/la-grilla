import SwiftUI
import UIKit
import MusicDomain

struct InstrumentKeyboardButton: View {
    let session: Session
    var trackID: UUID?
    var clipID: UUID?
    var compact = false
    @State private var showing = false

    var body: some View {
        Button {
            showing = true
        } label: {
            if compact {
                Image(systemName: "pianokeys").frame(width: 44, height: 44)
            } else {
                Label("Keyboard", systemImage: "pianokeys").frame(minHeight: 44)
            }
        }
        .accessibilityLabel("Keyboard").accessibilityIdentifier("keyboard.open")
        .disabled(session.performance.contextActive || session.armed || session.recording)
        .fullScreenCover(isPresented: $showing) {
            InstrumentKeyboard(session: session, trackID: trackID, clipID: clipID)
        }
    }
}

private struct InstrumentKeyboard: View {
    let session: Session
    let trackID: UUID?
    let clipID: UUID?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var root = 60
    @State private var loading: FactoryInstrument?
    @State private var task: Task<Void, Never>?
    @State private var error: String?
    @State private var take: KeyboardPhrase?
    @State private var soundBanks = false
    @State private var surfaceID = UUID()

    private var track: Track? {
        session.project.tracks.first { $0.id == trackID && $0.role != .drums }
            ?? session.project.tracks.first { $0.role == .melody }
            ?? session.project.tracks.first { $0.role == .harmony }
    }

    private func sourceClip(_ track: Track) -> Clip? {
        track.clips.first { $0.id == clipID } ?? track.clips.first {
            $0.start <= session.section.start && session.section.start < $0.start + $0.length
        }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let compact = geometry.size.height < 450
                if let track {
                    VStack(alignment: .leading, spacing: compact ? 6 : 14) {
                        ScrollView(.horizontal) {
                            HStack(spacing: 9) {
                                ForEach(FactoryInstrument.allCases) { instrument in
                                    instrumentCard(instrument, track: track, compact: compact)
                                }
                            }.padding(.horizontal, 14)
                        }.scrollIndicators(.hidden).accessibilityIdentifier("keyboard.instruments")
                        if !compact {
                            HStack {
                                Text(track.displayName).font(.caption).foregroundStyle(Color.muted)
                                Spacer()
                                Text(TrackSoundNames.current(track)).font(.subheadline.weight(.semibold))
                                    .accessibilityIdentifier("keyboard.current-sound")
                            }.padding(.horizontal, 16)
                        }
                        HStack(spacing: 6) {
                            IconButton(symbol: "minus", label: "Octave down") { changeOctave(-12) }
                                .disabled(root == 24)
                            Text(verbatim: MusicalNotation.noteName(root, keyRoot: session.project.keyRoot,
                                                                   minor: session.project.minor))
                                .font(.body.monospacedDigit()).accessibilityIdentifier("keyboard.octave")
                            IconButton(symbol: "plus", label: "Octave up") { changeOctave(12) }
                                .disabled(root == 96)
                            Spacer()
                            if track.role == .melody, let clip = sourceClip(track) {
                                IconButton(symbol: take == nil ? "record.circle" : "stop.circle.fill",
                                           label: take == nil ? "Record phrase" : "Finish phrase", color: .record) {
                                    if take != nil { finishPhrase() }
                                    else { take = KeyboardPhrase(patternID: clip.patternID, bpm: session.project.bpm) }
                                }.accessibilityIdentifier("keyboard.record")
                            }
                            IconButton(symbol: session.audio.playing ? "stop.fill" : "play.fill",
                                       label: session.audio.playing ? "Stop" : "Play") { session.togglePlay() }
                        }.padding(.horizontal, 14)
                        if let error {
                            Text(error).font(.caption).foregroundStyle(Color.record).padding(.horizontal)
                        }
                        InstrumentKeybed(root: root, octaves: geometry.size.width >= 660 ? 2 : 1,
                                         keyRoot: session.project.keyRoot, minor: session.project.minor,
                                         play: { pitch, down in key(pitch, down: down, track: track) },
                                         audition: { pitch in
                                             guard session.ensureAudio(), let index = session.project.tracks.firstIndex(where: { $0.id == track.id }) else { return }
                                             session.audio.previewNote(pitch, track: index)
                                         })
                            .id(surfaceID).padding(.horizontal, 10).padding(.bottom, 10)
                    }.padding(.top, compact ? 0 : 8)
                }
            }
            .background(Color.ink).navigationTitle("Keyboard").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { resetKeys(); soundBanks = true } label: { Image(systemName: "slider.horizontal.3") }
                        .accessibilityLabel("Sound banks").disabled(loading != nil || take != nil)
                }
            }
            .sheet(isPresented: $soundBanks) {
                if let track {
                    SoundBankView(session: session, trackID: track.id,
                                  projectID: session.project.id, revision: session.project.revision)
                }
            }
        }.tint(.mint)
        .onAppear { _ = session.ensureAudio() }
        .onChange(of: phase) { _, phase in if phase != .active { finishPhrase(); resetKeys() } }
        .onDisappear { task?.cancel(); finishPhrase(); session.midi.releaseKeyboard() }
    }

    private func instrumentCard(_ instrument: FactoryInstrument, track: Track, compact: Bool) -> some View {
        let selected = track.instrumentSample?.name == instrument.displayName
        return Button { choose(instrument, track: track) } label: {
            HStack(spacing: 8) {
                Image("instrument-" + instrument.id).resizable().scaledToFill()
                    .frame(width: compact ? 42 : 66, height: compact ? 42 : 72).clipped()
                Text(instrument.displayName).font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.studioText).lineLimit(2)
                if loading == instrument { ProgressView() }
                else if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.mint) }
            }.padding(.trailing, 10)
                .background(Color.panel, in: RoundedRectangle(cornerRadius: 12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).stroke(selected ? Color.mint : Color.outline, lineWidth: selected ? 2 : 1) }
        }.buttonStyle(.plain).accessibilityLabel(instrument.displayName)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("keyboard.instrument." + instrument.id)
            .disabled(loading != nil || take != nil)
    }

    private func choose(_ instrument: FactoryInstrument, track: Track) {
        guard track.instrumentSample?.name != instrument.displayName else { return }
        resetKeys()
        let project = session.project.id, revision = session.project.revision
        loading = instrument
        error = nil
        task = Task {
            defer { loading = nil }
            do {
                let sound = try await SoundBankLibrary.shared.prepareFactoryInstrument(instrument)
                try Task.checkCancellation()
                try await session.assignSounds([(nil, sound)], trackID: track.id, projectID: project, revision: revision)
            } catch is CancellationError {
                return
            } catch { self.error = error.localizedDescription }
        }
    }

    private func key(_ pitch: Int, down: Bool, track: Track) {
        guard let index = session.project.tracks.firstIndex(where: { $0.id == track.id }) else { return }
        if down && !session.ensureAudio() { error = session.audio.error; return }
        if session.midi.playKey(pitch, down: down, track: track, index: index) {
            take?.receive(pitch, down: down)
        } else if down {
            error = NSLocalizedString("Keyboard input unavailable. Release the keys and try again.", comment: "Instrument input")
        }
    }

    private func changeOctave(_ delta: Int) { resetKeys(); root += delta }

    private func resetKeys() {
        take?.releaseHeld()
        session.midi.releaseKeyboard()
        surfaceID = UUID()
    }

    private func finishPhrase() {
        guard var phrase = take else { return }
        take = nil
        phrase.releaseHeld()
        guard !phrase.notes.isEmpty else { return }
        session.edit { project in
            guard let i = project.patterns.firstIndex(where: { $0.id == phrase.patternID }) else { throw MusicError.invalidProject }
            let length = project.patterns[i].length
            for var note in phrase.notes where note.tick < length {
                note.duration = min(note.duration, length - note.tick)
                try NoteEditing.insert(note, into: &project.patterns[i], step: 1)
            }
        }
    }
}

/// Capture from the first key down. A whole phrase is one undoable pattern edit.
private struct KeyboardPhrase {
    let patternID: UUID
    let bpm: Double
    private var start: TimeInterval?
    private var held = [Int: Int]()
    private(set) var notes = [NoteEvent]()

    init(patternID: UUID, bpm: Double) { self.patternID = patternID; self.bpm = bpm }

    mutating func receive(_ pitch: Int, down: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        if start == nil && down { start = now }
        guard let start else { return }
        let tick = Int(((now - start) * bpm * Double(ppq) / 60).rounded())
        if down { held[pitch] = tick }
        else if let onset = held.removeValue(forKey: pitch), notes.count < 4096 {
            notes.append(NoteEvent(tick: onset, duration: max(1, tick - onset), pitch: pitch))
        }
    }

    mutating func releaseHeld() {
        for pitch in Array(held.keys) { receive(pitch, down: false) }
    }
}

private struct InstrumentKeybed: UIViewRepresentable {
    let root: Int
    let octaves: Int
    let keyRoot: Int
    let minor: Bool
    let play: (Int, Bool) -> Void
    let audition: (Int) -> Void

    func makeUIView(context: Context) -> KeybedView { KeybedView() }

    func updateUIView(_ view: KeybedView, context: Context) {
        view.play = play
        view.audition = audition
        view.configure(root: root, octaves: octaves, keyRoot: keyRoot, minor: minor)
    }

    static func dismantleUIView(_ view: KeybedView, coordinator: ()) { view.releaseAll() }
}

private final class KeybedView: UIView {
    var play: ((Int, Bool) -> Void)?
    var audition: ((Int) -> Void)?
    private var configuration: [Int] = []
    private var whiteKeys = [UIButton]()
    private var blackKeys = [(after: Int, button: UIButton)]()
    private var contactPitches = [ObjectIdentifier: Int]()
    private let blackClasses: Set<Int> = [1, 3, 6, 8, 10]

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        layer.cornerRadius = 12
        clipsToBounds = true
        backgroundColor = UIColor(Color.keyboardGraphite)
    }

    required init?(coder: NSCoder) { return nil }

    func configure(root: Int, octaves: Int, keyRoot: Int, minor: Bool) {
        let next = [root, octaves, keyRoot, minor ? 1 : 0]
        guard configuration != next else { return }
        releaseAll()
        configuration = next
        subviews.forEach { $0.removeFromSuperview() }
        whiteKeys = []
        blackKeys = []
        for pitch in root...(root + octaves * 12) {
            let black = blackClasses.contains(pitch % 12)
            let key = UIButton(type: .custom)
            key.tag = pitch
            let name = MusicalNotation.noteName(pitch, keyRoot: keyRoot, minor: minor)
            key.accessibilityLabel = name
            key.accessibilityIdentifier = "keyboard.key." + String(pitch)
            key.accessibilityTraits.insert(.playsSound)
            key.accessibilityRespondsToUserInteraction = true
            key.setTitle(name, for: .normal)
            key.titleLabel?.font = .monospacedSystemFont(ofSize: black ? 11 : 13, weight: .semibold)
            key.contentVerticalAlignment = .bottom
            key.contentEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: black ? 10 : 18, right: 0)
            key.layer.cornerRadius = black ? 5 : 7
            key.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            key.addAction(UIAction { [weak self] _ in self?.audition?(pitch) }, for: .primaryActionTriggered)
            if black { blackKeys.append((whiteKeys.count, key)) } else { whiteKeys.append(key) }
            style(key, held: false)
        }
        whiteKeys.forEach { addSubview($0) }
        blackKeys.forEach { addSubview($0.button) }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !whiteKeys.isEmpty else { return }
        let step = bounds.width / CGFloat(whiteKeys.count)
        for (i, key) in whiteKeys.enumerated() {
            key.frame = CGRect(x: step * CGFloat(i) + 1, y: 0, width: max(0, step - 2), height: bounds.height)
        }
        for (after, key) in blackKeys {
            key.frame = CGRect(x: step * (CGFloat(after) - 0.30), y: 0,
                               width: step * 0.60, height: bounds.height * 0.60)
        }
    }

    private func style(_ key: UIButton, held: Bool) {
        let black = blackClasses.contains(key.tag % 12)
        key.backgroundColor = UIColor(held ? Color.mint : (black ? .keyboardGraphite : .keyboardIvory))
        key.setTitleColor(UIColor(held ? Color.ink : (black ? .keyboardIvory : .keyboardGraphite)), for: .normal)
        key.layer.borderWidth = black ? 1 : 0
        key.layer.borderColor = UIColor.gray.withAlphaComponent(0.45).cgColor
    }

    // Touches stay on one multi-touch surface. Scanning topmost keys first
    // makes black keys win overlaps and allows slides across key boundaries.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        super.hitTest(point, with: event) == nil ? nil : self
    }

    private func update(_ touches: Set<UITouch>, releasing: Bool) {
        let before = Set(contactPitches.values)
        for touch in touches {
            let id = ObjectIdentifier(touch), point = touch.location(in: self)
            if releasing { contactPitches.removeValue(forKey: id) }
            else { contactPitches[id] = subviews.reversed().first { $0.frame.contains(point) }?.tag }
        }
        let after = Set(contactPitches.values)
        for pitch in before.subtracting(after) { change(pitch, held: false) }
        for pitch in after.subtracting(before) { change(pitch, held: true) }
    }

    private func change(_ pitch: Int, held: Bool) {
        play?(pitch, held)
        if let key = viewWithTag(pitch) as? UIButton { style(key, held: held) }
    }

    func releaseAll() {
        let pitches = Set(contactPitches.values)
        contactPitches.removeAll()
        for pitch in pitches { change(pitch, held: false) }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { update(touches, releasing: false) }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { update(touches, releasing: false) }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { update(touches, releasing: true) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { update(touches, releasing: true) }
}
