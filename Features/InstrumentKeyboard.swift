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
    @State private var selectedTrackID: UUID?
    @State private var root = 60
    @State private var loading: FactoryInstrument?
    @State private var task: Task<Void, Never>?
    @State private var error: String?
    @State private var take: KeyboardPhrase?
    @State private var recordingLength = 0
    @State private var finishTask: Task<Void, Never>?
    @State private var soundBanks = false
    @State private var surfaceID = UUID()
    /// I13: only the notes of the project key, as equal keys.
    @AppStorage("keyboard.scaleOnly") private var scaleOnly = false
    @State private var sustain = false
    @AppStorage("keyboard.chordStrip") private var chordStrip = false
    /// I30: step input writes an eighth note per key at a cursor that advances when all keys are up.
    @State private var stepCursor: Int?
    @State private var stepHeld: Set<Int> = []

    private var track: Track? {
        session.project.tracks.first { $0.id == (selectedTrackID ?? trackID) && $0.role != .drums }
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
                        ScrollViewReader { shelf in
                            ScrollView(.horizontal) {
                                HStack(spacing: 9) {
                                    ForEach(FactoryInstrument.allCases) { instrument in
                                        instrumentCard(instrument, track: track, compact: compact)
                                            .id(instrument.id)
                                    }
                                }.padding(.horizontal, 14)
                            }.scrollIndicators(.hidden).accessibilityIdentifier("keyboard.instruments")
                                .onChange(of: track.instrumentSample, initial: true) { _, sample in
                                    if let current = factorySound(sample?.name) {
                                        shelf.scrollTo(current.id, anchor: .center)
                                    }
                                }
                        }
                        if !compact {
                            instrumentPanel(track, height: min(170, max(88, geometry.size.height * 0.20)))
                        }
                        HStack(spacing: 6) {
                            if compact { trackMenu(track, compact: true) }
                            IconButton(symbol: "minus", label: "Octave down") { changeOctave(-12) }
                                .disabled(root == 24)
                            Text(verbatim: MusicalNotation.noteName(root, keyRoot: session.project.keyRoot,
                                                                   minor: session.project.minor))
                                .font(.body.monospacedDigit()).accessibilityIdentifier("keyboard.octave")
                            IconButton(symbol: "plus", label: "Octave up") { changeOctave(12) }
                                .disabled(root == 96)
                            IconButton(symbol: scaleOnly ? "music.note.list" : "pianokeys", label: "Notes of the key only",
                                       color: scaleOnly ? .mint : .muted) { resetKeys(); scaleOnly.toggle() }
                                .accessibilityValue(LocalizedStringKey(scaleOnly ? "On" : "Off"))
                                .accessibilityIdentifier("keyboard.scale-only")
                            IconButton(symbol: "pedal.accelerator", label: "Sustain", color: sustain ? .mint : .muted) { setSustain(!sustain) }
                                .accessibilityValue(LocalizedStringKey(sustain ? "On" : "Off"))
                                .accessibilityIdentifier("keyboard.sustain")
                            IconButton(symbol: "music.quarternote.3", label: "One-finger chords", color: chordStrip ? .mint : .muted) { resetKeys(); chordStrip.toggle() }
                                .accessibilityValue(LocalizedStringKey(chordStrip ? "On" : "Off"))
                                .accessibilityIdentifier("keyboard.chord-strip")
                            if track.role == .melody {
                                IconButton(symbol: "text.insert", label: "Step input", color: stepCursor != nil ? .mint : .muted) {
                                    resetKeys(); stepCursor = stepCursor == nil ? 0 : nil; stepHeld = []
                                }.accessibilityValue(Text(verbatim: stepCursor.map { MusicalPosition(tick: $0).description } ?? ""))
                                    .accessibilityIdentifier("keyboard.step-input").disabled(take != nil)
                            }
                            Spacer()
                            if track.role == .melody, let clip = sourceClip(track) {
                                IconButton(symbol: take == nil ? "record.circle" : "stop.circle.fill",
                                           label: take == nil ? "Record phrase" : "Finish phrase", color: .record) {
                                    if take != nil { finishPhrase() }
                                    else if let pattern = session.project.patterns.first(where: { $0.id == clip.patternID }) {
                                        take = KeyboardPhrase(patternID: clip.patternID, bpm: session.project.bpm)
                                        recordingLength = pattern.length
                                    }
                                }.accessibilityIdentifier("keyboard.record")
                            }
                            IconButton(symbol: session.audio.playing ? "stop.fill" : "play.fill",
                                       label: session.audio.playing ? "Stop" : "Play") { session.togglePlay() }
                        }.padding(.horizontal, 14)
                        if let error {
                            Text(error).font(.caption).foregroundStyle(Color.record).padding(.horizontal)
                        }
                        if chordStrip {
                            ChordStrip(keyRoot: session.project.keyRoot, minor: session.project.minor) { pitch, down in key(pitch, down: down, track: track) }
                                .padding(.horizontal, 10)
                        }
                        InstrumentKeybed(root: root, octaves: geometry.size.width >= 660 ? 2 : 1,
                                         keyRoot: session.project.keyRoot, minor: session.project.minor, scaleOnly: scaleOnly,
                                         play: { pitch, down in key(pitch, down: down, track: track) })
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

    private func factorySound(_ name: String?) -> FactoryInstrument? {
        FactoryInstrument.allCases.first { $0.matches(name: name) }
    }

    private func instrumentPanel(_ track: Track, height: CGFloat) -> some View {
        let current = factorySound(track.instrumentSample?.name)
        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                trackMenu(track, compact: false)
                Text(current?.displayName ?? TrackSoundNames.current(track))
                    .font(.title2.weight(.semibold)).foregroundStyle(Color.studioText)
                    .lineLimit(2).minimumScaleFactor(0.8)
                    .accessibilityIdentifier("keyboard.current-sound")
            }.padding(.leading, 14)
            Spacer(minLength: 4)
            if let current {
                Image(current.artwork).resizable().scaledToFill()
                    .frame(width: height * 1.2, height: height).clipped()
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0),
                                                 .init(color: .black, location: 0.22),
                                                 .init(color: .black, location: 1)],
                                         startPoint: .leading, endPoint: .trailing))
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "waveform").font(.system(size: 44, weight: .light))
                    .foregroundStyle(Color.track(track.role)).padding(.trailing, 22).accessibilityHidden(true)
            }
        }.frame(maxWidth: .infinity).frame(height: height)
            .background(Color.panel, in: RoundedRectangle(cornerRadius: 14))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(Color.outline, lineWidth: 0.7) }
            .padding(.horizontal, 14)
    }

    private func trackMenu(_ active: Track, compact: Bool) -> some View {
        Menu {
            ForEach(session.project.tracks.filter { $0.role != .drums }) { option in
                Button {
                    resetKeys()
                    selectedTrackID = option.id
                } label: {
                    if active.id == option.id { Label(option.displayName, systemImage: "checkmark") }
                    else { Text(option.displayName) }
                }
            }
            Button("Add melody", systemImage: "plus") {
                resetKeys()
                let count = session.project.tracks.count
                session.addMelody()
                if session.project.tracks.count > count { selectedTrackID = session.noteTrackID }
            }.disabled(session.project.tracks.count >= 8)
        } label: {
            HStack(spacing: 6) {
                if compact { Image(systemName: "music.note.list") } else { Text(active.displayName) }
                Image(systemName: "chevron.down").font(.caption)
            }.frame(minWidth: 44, minHeight: 44)
        }.disabled(loading != nil || take != nil).accessibilityLabel("Track")
            .accessibilityValue(active.displayName).accessibilityIdentifier("keyboard.track")
    }

    private func instrumentCard(_ instrument: FactoryInstrument, track: Track, compact: Bool) -> some View {
        let selected = instrument.matches(name: track.instrumentSample?.name)
        return Button { choose(instrument, track: track) } label: {
            HStack(spacing: 8) {
                Image(instrument.artwork).resizable().scaledToFill()
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
        guard !instrument.matches(name: track.instrumentSample?.name) else { return }
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
            // The keybed connection can be created by this key; send the pedal state to it.
            if down && sustain { _ = session.midi.keyboardSustain(true) }
            if stepCursor != nil { step(pitch, down: down, track: track) }
            if down, take != nil, finishTask == nil {
                session.audio.refreshClock()
                if let clip = sourceClip(track), recordingLength > 0 {
                    let position = Int(session.audio.tick) - clip.start
                    let played = session.audio.playing && (0..<clip.length).contains(position) ? position : 0
                    take?.offset = (clip.offset + played) % recordingLength
                }
                let remaining = max(1, recordingLength - (take?.offset ?? 0))
                let limit = Double(remaining) * 60 / (Double(ppq) * session.project.bpm)
                finishTask = Task { @MainActor in
                    do { try await Task.sleep(for: .seconds(limit)) }
                    catch { return }
                    finishPhrase()
                }
            }
            take?.receive(pitch, down: down)
        } else if down {
            error = NSLocalizedString("Keyboard input unavailable. Release the keys and try again.", comment: "Instrument input")
        }
    }

    private func changeOctave(_ delta: Int) { resetKeys(); root += delta }

    private func step(_ pitch: Int, down: Bool, track: Track) {
        guard var cursor = stepCursor, let clip = sourceClip(track) else { return }
        let length = ppq / 2
        if down {
            stepHeld.insert(pitch)
            let patternID = clip.patternID, at = cursor
            session.edit { project in
                guard let i = project.patterns.firstIndex(where: { $0.id == patternID }), at < project.patterns[i].length else { return }
                let note = NoteEvent(tick: at, duration: min(length, project.patterns[i].length - at), pitch: pitch, velocity: KeyboardPerformance.velocity)
                try NoteEditing.insert(note, into: &project.patterns[i], step: 1)
            }
        } else {
            stepHeld.remove(pitch)
            if stepHeld.isEmpty {
                cursor += length
                let patternLength = session.project.patterns.first { $0.id == clip.patternID }?.length ?? barTicks
                stepCursor = cursor >= patternLength ? 0 : cursor
            }
        }
    }

    private func setSustain(_ on: Bool) {
        sustain = on
        _ = session.midi.keyboardSustain(on)
        take?.setSustain(on)
    }

    private func resetKeys() {
        if sustain { setSustain(false) }
        take?.releaseHeld()
        session.midi.releaseKeyboard()
        surfaceID = UUID()
    }

    private func finishPhrase() {
        finishTask?.cancel()
        finishTask = nil
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
    var offset = 0
    private var start: TimeInterval?
    private var held = [Int: Int]()
    private var sustained = false
    /// Keys released while the pedal is down keep sounding until it is lifted.
    private var pedalHeld = [Int: Int]()
    private(set) var notes = [NoteEvent]()

    init(patternID: UUID, bpm: Double) { self.patternID = patternID; self.bpm = bpm }

    mutating func receive(_ pitch: Int, down: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        if start == nil && down { start = now }
        guard let start else { return }
        let tick = offset + Int(((now - start) * bpm * Double(ppq) / 60).rounded())
        if down {
            // A key struck again under the pedal ends its sustained note first.
            if let onset = pedalHeld.removeValue(forKey: pitch), notes.count < 4096 {
                notes.append(NoteEvent(tick: onset, duration: max(1, tick - onset), pitch: pitch, velocity: KeyboardPerformance.velocity))
            }
            held[pitch] = tick
        }
        else if let onset = held.removeValue(forKey: pitch) {
            if sustained { pedalHeld[pitch] = onset }
            else if notes.count < 4096 { notes.append(NoteEvent(tick: onset, duration: max(1, tick - onset), pitch: pitch, velocity: KeyboardPerformance.velocity)) }
        }
    }

    mutating func setSustain(_ on: Bool) {
        sustained = on
        guard !on, let start else { return }
        let tick = offset + Int(((ProcessInfo.processInfo.systemUptime - start) * bpm * Double(ppq) / 60).rounded())
        for (pitch, onset) in pedalHeld where notes.count < 4096 {
            notes.append(NoteEvent(tick: onset, duration: max(1, tick - onset), pitch: pitch, velocity: KeyboardPerformance.velocity))
        }
        pedalHeld = [:]
    }

    mutating func releaseHeld() {
        for pitch in Array(held.keys) { receive(pitch, down: false) }
        setSustain(false)
    }
}

private struct InstrumentKeybed: UIViewRepresentable {
    let root: Int
    let octaves: Int
    let keyRoot: Int
    let minor: Bool
    var scaleOnly = false
    let play: (Int, Bool) -> Void

    func makeUIView(context: Context) -> KeybedView { KeybedView() }

    func updateUIView(_ view: KeybedView, context: Context) {
        view.play = play
        view.configure(root: root, octaves: octaves, keyRoot: keyRoot, minor: minor, scaleOnly: scaleOnly)
    }

    static func dismantleUIView(_ view: KeybedView, coordinator: ()) { view.releaseAll() }
}

private final class KeybedView: UIView {
    var play: ((Int, Bool) -> Void)?
    private var configuration: [Int] = []
    private var whiteKeys = [UIButton]()
    private var blackKeys = [(after: Int, button: UIButton)]()
    private var contactPitches = [ObjectIdentifier: Int]()
    private var accessibleNotes = [Int: Task<Void, Never>]()
    private var heldNotes: Set<Int> { Set(contactPitches.values).union(accessibleNotes.keys) }
    private let blackClasses: Set<Int> = [1, 3, 6, 8, 10]

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        layer.cornerRadius = 12
        clipsToBounds = true
        backgroundColor = UIColor(Color.keyboardGraphite)
    }

    required init?(coder: NSCoder) { return nil }

    private var flat = false

    func configure(root: Int, octaves: Int, keyRoot: Int, minor: Bool, scaleOnly: Bool = false) {
        let next = [root, octaves, keyRoot, minor ? 1 : 0, scaleOnly ? 1 : 0]
        guard configuration != next else { return }
        releaseAll()
        configuration = next
        subviews.forEach { $0.removeFromSuperview() }
        whiteKeys = []
        blackKeys = []
        flat = scaleOnly
        let pitches = scaleOnly ? ScaleKeyboard.pitches(root: keyRoot, minor: minor, low: root, high: root + octaves * 12) : Array(root...(root + octaves * 12))
        for pitch in pitches {
            let black = !scaleOnly && blackClasses.contains(pitch % 12)
            let key = UIButton(type: .custom)
            key.tag = pitch
            let name = MusicalNotation.noteName(pitch, keyRoot: keyRoot, minor: minor)
            key.accessibilityLabel = name
            key.accessibilityIdentifier = "keyboard.key." + String(pitch)
            key.accessibilityTraits.insert(.playsSound)
            key.setTitle(name, for: .normal)
            key.titleLabel?.font = .monospacedSystemFont(ofSize: black ? 11 : 13, weight: .semibold)
            key.contentVerticalAlignment = .bottom
            key.contentEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: black ? 10 : 18, right: 0)
            key.layer.cornerRadius = black ? 5 : 7
            key.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            key.addAction(UIAction { [weak self] _ in self?.activateKey(pitch) }, for: .primaryActionTriggered)
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
        let black = !flat && blackClasses.contains(key.tag % 12)
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
        let before = heldNotes
        for touch in touches {
            let id = ObjectIdentifier(touch), point = touch.location(in: self)
            if releasing { contactPitches.removeValue(forKey: id) }
            else { contactPitches[id] = subviews.reversed().first { $0.frame.contains(point) }?.tag }
        }
        let after = heldNotes
        for pitch in before.subtracting(after) { change(pitch, held: false) }
        for pitch in after.subtracting(before) { change(pitch, held: true) }
    }

    private func change(_ pitch: Int, held: Bool) {
        play?(pitch, held)
        if let key = viewWithTag(pitch) as? UIButton { style(key, held: held) }
    }

    private func activateKey(_ pitch: Int) {
        let alreadyHeld = heldNotes.contains(pitch)
        accessibleNotes[pitch]?.cancel()
        if !alreadyHeld { change(pitch, held: true) }
        accessibleNotes[pitch] = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(320)) }
            catch { return }
            guard let self else { return }
            self.accessibleNotes.removeValue(forKey: pitch)
            if !self.heldNotes.contains(pitch) { self.change(pitch, held: false) }
        }
    }

    func releaseAll() {
        let pitches = heldNotes
        for task in accessibleNotes.values { task.cancel() }
        accessibleNotes.removeAll()
        contactPitches.removeAll()
        for pitch in pitches { change(pitch, held: false) }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { update(touches, releasing: false) }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { update(touches, releasing: false) }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { update(touches, releasing: true) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { update(touches, releasing: true) }
}

/// I14: seven scale-degree buttons; each plays the diatonic chord voiced
/// closest to the previous one, through the same keybed path (and recording).
private struct ChordStrip: View {
    let keyRoot: Int
    let minor: Bool
    let play: (Int, Bool) -> Void
    @State private var previous: [Int] = []
    @State private var held: [Int: [Int]] = [:]
    private let numerals = ["I", "II", "III", "IV", "V", "VI", "VII"]
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { degree in
                Text(verbatim: label(degree))
                    .font(.caption.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 48)
                    .background(held[degree] != nil ? Color.mint : Color.raised, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(held[degree] != nil ? Color.ink : Color.studioText)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { _ in press(degree) }
                        .onEnded { _ in release(degree) })
                    .accessibilityLabel(Text(verbatim: label(degree))).accessibilityAddTraits(.isButton)
                    .accessibilityAction { press(degree); release(degree) }
                    .accessibilityIdentifier("keyboard.chord.\(degree)")
            }
        }
        .onDisappear { for degree in Array(held.keys) { release(degree) } }
    }
    private func label(_ degree: Int) -> String {
        let scale = NoteTools.scale(root: keyRoot, minor: minor)
        let third = (scale[(degree + 2) % 7] - scale[degree] + 12) % 12
        let numeral = numerals[degree]
        return third == 3 ? numeral.lowercased() : numeral
    }
    private func press(_ degree: Int) {
        guard held[degree] == nil else { return }
        let chord = ScaleKeyboard.chord(degree: degree, root: keyRoot, minor: minor, previous: previous)
        held[degree] = chord
        previous = chord
        for pitch in chord { play(pitch, true) }
    }
    private func release(_ degree: Int) {
        guard let chord = held.removeValue(forKey: degree) else { return }
        for pitch in chord { play(pitch, false) }
    }
}
