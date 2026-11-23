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
    @AppStorage("keyboard.octaves") private var octaveSetting = 0       // I20: 0 automatic, 1…3
    @AppStorage("keyboard.keySize") private var keySize = 1              // I20: S/M/L
    @AppStorage("keyboard.grid") private var isomorphic = false          // I18
    @AppStorage("keyboard.arpRate") private var arpRate = 0              // I15: 0 off, else step ticks
    @AppStorage("keyboard.arpMode") private var arpMode = 0
    @AppStorage("keyboard.arpOctaves") private var arpOctaves = 1
    @State private var arpHeld: [Int] = []
    @AppStorage("keyboard.bendStrips") private var bendStrips = false   // I16
    /// I30: step input writes an eighth note per key at a cursor that advances when all keys are up.
    @State private var stepCursor: Int?
    @State private var stepHeld: Set<Int> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                                            .luzScrollDepth(.horizontal)
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
                        controlsRow(track, compact: compact)
                        if let error {
                            Text(error).font(.caption).foregroundStyle(Color.record).padding(.horizontal)
                        }
                        if chordStrip {
                            ChordStrip(keyRoot: session.project.keyRoot, minor: session.project.minor, color: Color.track(track)) { pitch, down in key(pitch, down: down, track: track) }
                                .padding(.horizontal, 10)
                        }
                        keybedRow(track, width: geometry.size.width)
                    }.padding(.top, compact ? 0 : 8)
                }
            }
            .background(Color.ink).navigationTitle("Keyboard").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // I18 · I20: grid layout, number of octaves and key width.
                    layoutMenu
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
        .onDisappear { task?.cancel(); finishPhrase(); session.midi.releaseKeyboard(); arpHeld = []; session.audio.arp(identity: 0, pitches: [], step: 240, mode: 0, octaves: 1) }
    }

    private var stepCursorDescription: String { stepCursor.map { MusicalPosition(tick: $0).description } ?? "" }

    private func controlsRow(_ track: Track, compact: Bool) -> some View {
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
                }.accessibilityValue(Text(verbatim: stepCursorDescription))
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
    }

    private func keybedRow(_ track: Track, width: CGFloat) -> some View {
        let size = KeyboardLayout.KeySize(rawValue: keySize) ?? .medium
        let available = width - 20 - (bendStrips ? 92 : 0)
        let columns = isomorphic ? max(5, min(12, Int(available / size.minimumWidth / 1.2))) : 0
        return HStack(spacing: 8) {
        if bendStrips {
            BendStrips { semitones, modulation in
                session.audio.pitchBend(identity: MIDIController.trackIdentity(track.id), semitones: semitones, modulation: modulation)
            }
        }
        InstrumentKeybed(root: root, octaves: KeyboardLayout.octaves(requested: octaveSetting, width: available, size: size),
                         keyRoot: session.project.keyRoot, minor: session.project.minor, scaleOnly: scaleOnly,
                         gridColumns: columns,
                         color: Color.track(track),
                         play: { pitch, down in key(pitch, down: down, track: track) })
            .id(surfaceID)
        }.padding(.horizontal, 10).padding(.bottom, 10)

    }

    private var layoutMenu: some View {
        Menu {
            Toggle("Isomorphic grid", isOn: Binding(get: { isomorphic }, set: { resetKeys(); isomorphic = $0 }))
            Picker("Octaves", selection: Binding(get: { octaveSetting }, set: { resetKeys(); octaveSetting = $0 })) {
                Text("Automatic").tag(0); Text(verbatim: "1").tag(1); Text(verbatim: "2").tag(2); Text(verbatim: "3").tag(3)
            }
            Picker("Key size", selection: Binding(get: { keySize }, set: { resetKeys(); keySize = $0 })) {
                Text("Small").tag(0); Text("Medium").tag(1); Text("Large").tag(2)
            }
            Toggle("Bend and modulation strips", isOn: Binding(get: { bendStrips }, set: { resetKeys(); bendStrips = $0 }))
            Picker("Arpeggiator", selection: Binding(get: { arpRate }, set: { resetKeys(); arpRate = $0 })) {
                Text("Off").tag(0); Text(verbatim: "1/8").tag(480); Text(verbatim: "1/16").tag(240); Text(verbatim: "1/16T").tag(160); Text(verbatim: "1/32").tag(120)
            }
            if arpRate > 0 {
                Picker("Arpeggio order", selection: Binding(get: { arpMode }, set: { resetKeys(); arpMode = $0 })) {
                    Text("Up").tag(0); Text("Down").tag(1); Text("Up and down").tag(2); Text("As played").tag(3)
                }
                Picker("Arpeggio octaves", selection: Binding(get: { arpOctaves }, set: { resetKeys(); arpOctaves = $0 })) {
                    Text(verbatim: "1").tag(1); Text(verbatim: "2").tag(2); Text(verbatim: "3").tag(3)
                }
            }
        } label: {
            Image(systemName: isomorphic ? "square.grid.4x3.fill" : "rectangle.split.3x1").foregroundStyle(isomorphic ? Color.mint : Color.muted).frame(minWidth: 44, minHeight: 44)
        }.accessibilityLabel("Keyboard layout").accessibilityIdentifier("keyboard.layout")
            .disabled(take != nil)

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
                InstrumentArtwork(instrument: current)
                    .id(current.id).transition(Luz.Transition.replace(reduceMotion))
                    .frame(width: height * 1.2, height: height).clipped()
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0),
                                                 .init(color: .black, location: 0.22),
                                                 .init(color: .black, location: 1)],
                                         startPoint: .leading, endPoint: .trailing))
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "waveform").font(.system(size: 44, weight: .light))
                    .foregroundStyle(Color.track(track)).padding(.trailing, 22).accessibilityHidden(true)
            }
        }.frame(maxWidth: .infinity).frame(height: height)
            .animation(Luz.Motion.morph, value: current?.id)
            .background(Color.panel, in: RoundedRectangle(cornerRadius:Luz.Radius.card,style:.continuous))
            .clipShape(RoundedRectangle(cornerRadius:Luz.Radius.card,style:.continuous))
            .overlay { RoundedRectangle(cornerRadius:Luz.Radius.card,style:.continuous).strokeBorder(Color.outline, lineWidth: 0.7) }
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
                InstrumentArtwork(instrument: instrument)
                    .frame(width: compact ? 42 : 66, height: compact ? 42 : 72).clipped()
                Text(instrument.displayName).font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.studioText).lineLimit(2)
                if loading == instrument { ProgressView() }
                else if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.mint) }
            }.padding(.trailing, 10)
                .background(Color.panel, in: RoundedRectangle(cornerRadius:StudioMetrics.controlRadius,style:.continuous))
                .clipShape(RoundedRectangle(cornerRadius:StudioMetrics.controlRadius,style:.continuous))
                .overlay { RoundedRectangle(cornerRadius:StudioMetrics.controlRadius,style:.continuous).stroke(selected ? Color.mint : Color.outline, lineWidth: selected ? 2 : 1) }
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
        if arpRate > 0 {
            // I15: held keys feed the kernel arpeggiator on the transport grid (live only).
            if down { if !arpHeld.contains(pitch) { arpHeld.append(pitch) } } else { arpHeld.removeAll { $0 == pitch } }
            session.audio.arp(identity: MIDIController.trackIdentity(track.id), pitches: arpHeld, step: arpRate, mode: arpMode, octaves: arpOctaves)
            return
        }
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
        if !arpHeld.isEmpty { arpHeld = []; session.audio.arp(identity: 0, pitches: [], step: 240, mode: 0, octaves: 1) }
        session.audio.pitchBend(identity: 0, semitones: 0, modulation: 0)
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
    /// I18: 0 = piano keys; otherwise an isomorphic grid with this many columns.
    var gridColumns = 0
    /// Luz: held keys light up in the track's colour.
    var color: Color = .mint
    let play: (Int, Bool) -> Void

    func makeUIView(context: Context) -> KeybedView { KeybedView() }

    func updateUIView(_ view: KeybedView, context: Context) {
        view.play = play
        view.accent = UIColor(color)
        if gridColumns > 0 { view.configureGrid(base: root, columns: gridColumns, keyRoot: keyRoot, minor: minor) }
        else { view.configure(root: root, octaves: octaves, keyRoot: keyRoot, minor: minor, scaleOnly: scaleOnly) }
    }

    static func dismantleUIView(_ view: KeybedView, coordinator: ()) { view.releaseAll() }
}

private final class KeybedView: UIView, MusicalTouchSurface {
    var play: ((Int, Bool) -> Void)?
    var accent = UIColor(Color.mint)
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
    private var gridKeys = [(row: Int, column: Int, button: UIButton)]()
    private var gridRows = 0, gridColumns = 0
    private var gridKeyRoot = 0, gridMinor = false

    /// I18: rows a fourth apart, semitones across; scale tones are light, the
    /// key's root is mint-outlined. Duplicated pitches light up together.
    func configureGrid(base: Int, columns: Int, keyRoot: Int, minor: Bool) {
        let rows = 4
        let next = [-1, base, columns, keyRoot, minor ? 1 : 0]
        guard configuration != next else { return }
        releaseAll()
        configuration = next
        subviews.forEach { $0.removeFromSuperview() }
        whiteKeys = []; blackKeys = []; gridKeys = []
        flat = true; gridRows = rows; gridColumns = columns; gridKeyRoot = keyRoot; gridMinor = minor
        for (row, pitches) in IsomorphicLayout.grid(rows: rows, columns: columns, base: base).enumerated() {
            for (column, pitch) in pitches.enumerated() {
                let key = UIButton(type: .custom)
                key.tag = pitch
                let name = MusicalNotation.noteName(pitch, keyRoot: keyRoot, minor: minor)
                key.accessibilityLabel = name
                key.accessibilityIdentifier = "keyboard.grid.\(row).\(column)"
                key.accessibilityTraits.insert(.playsSound)
                key.setTitle(name, for: .normal)
                key.titleLabel?.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
                key.layer.cornerRadius = 8
                key.addAction(UIAction { [weak self] _ in self?.activateKey(pitch) }, for: .primaryActionTriggered)
                gridKeys.append((row, column, key))
                addSubview(key)
                style(key, held: false)
            }
        }
        setNeedsLayout()
    }

    func configure(root: Int, octaves: Int, keyRoot: Int, minor: Bool, scaleOnly: Bool = false) {
        let next = [root, octaves, keyRoot, minor ? 1 : 0, scaleOnly ? 1 : 0]
        guard configuration != next else { return }
        releaseAll()
        configuration = next
        subviews.forEach { $0.removeFromSuperview() }
        whiteKeys = []
        blackKeys = []
        gridKeys = []; gridRows = 0; gridColumns = 0
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
            // Luz: a quiet keybed; only C and the key's root carry a printed name.
            let pitchClass = (pitch % 12 + 12) % 12
            key.setTitle(scaleOnly || pitchClass == 0 || pitchClass == keyRoot ? name : nil, for: .normal)
            key.titleLabel?.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: .monospacedSystemFont(ofSize: black ? 11 : 13, weight: .semibold), maximumPointSize: 18)
            key.layer.cornerCurve = .continuous
            key.contentVerticalAlignment = .bottom
            key.contentEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: black ? 10 : 18, right: 0)
            key.layer.cornerRadius = black ? 5 : Luz.Radius.key
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
        if gridRows > 0, gridColumns > 0 {
            let width = bounds.width / CGFloat(gridColumns), height = bounds.height / CGFloat(gridRows)
            for (row, column, key) in gridKeys {
                key.frame = CGRect(x: width * CGFloat(column) + 1.5, y: height * CGFloat(gridRows - 1 - row) + 1.5, width: max(0, width - 3), height: max(0, height - 3))
            }
            return
        }
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
        if gridRows > 0 {
            let inScale = IsomorphicLayout.inScale(key.tag, root: gridKeyRoot, minor: gridMinor)
            key.backgroundColor = UIColor(held ? Color.mint : (inScale ? .keyboardIvory : .keyboardGraphite))
            key.setTitleColor(UIColor(held ? Color.ink : (inScale ? .keyboardGraphite : .keyboardIvory)), for: .normal)
            let root = (key.tag % 12 + 12) % 12 == gridKeyRoot
            key.layer.borderWidth = root ? 2 : 1
            key.layer.borderColor = (root ? UIColor(Color.mint) : UIColor(Color.outline)).cgColor
            if held { key.backgroundColor = accent }
            depth(key, held: held)
            return
        }
        let black = !flat && blackClasses.contains(key.tag % 12)
        key.backgroundColor = held ? accent : UIColor(black ? .keyboardGraphite : .keyboardIvory)
        key.setTitleColor(UIColor(held ? Color.ink : (black ? .keyboardIvory : .keyboardGraphite)), for: .normal)
        key.layer.borderWidth = black ? 1 : 0
        key.layer.borderColor = UIColor(Color.outline).cgColor
        depth(key, held: held)
    }

    /// Luz depth press: a held key sinks a little and glows in the track colour.
    /// Layer changes outside an animation block draw in the same frame.
    private func depth(_ key: UIButton, held: Bool) {
        let highContrast = traitCollection.accessibilityContrast == .high
        key.layer.transform = held && !UIAccessibility.isReduceMotionEnabled ? CATransform3DTranslate(CATransform3DMakeScale(0.97, 0.985, 1), 0, 1.5, 0) : CATransform3DIdentity
        key.layer.shadowColor = accent.cgColor
        key.layer.shadowOpacity = held && !highContrast ? 0.55 : 0
        key.layer.shadowRadius = held ? 8 : 0
        key.layer.shadowOffset = .zero
        // An explicit path keeps the glow off the offscreen render path.
        key.layer.shadowPath = held ? UIBezierPath(roundedRect: key.bounds, cornerRadius: key.layer.cornerRadius).cgPath : nil
        key.layer.masksToBounds = false
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
        for case let key as UIButton in subviews where key.tag == pitch {
            // Contact draws at once; only the release fades (0.22 s ease-out).
            if held || UIAccessibility.isReduceMotionEnabled { style(key, held: held) }
            else { UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]) { self.style(key, held: false) } }
        }
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
    var color: Color = .mint
    let play: (Int, Bool) -> Void
    @State private var previous: [Int] = []
    @State private var held: [Int: [Int]] = [:]
    private let numerals = ["I", "II", "III", "IV", "V", "VI", "VII"]
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { degree in
                Text(verbatim: label(degree))
                    .font(StudioTypography.pad).frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(held[degree] != nil ? Color.ink : Color.studioText)
                    .litInstrument(color, isDown: held[degree] != nil, radius: Luz.Radius.cell)
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

/// I16: a spring-loaded pitch-bend strip (±2 semitones, back to centre on
/// release) and a modulation strip (vibrato depth, stays where it is left).
private struct BendStrips: View {
    let apply: (Float, Float) -> Void
    @State private var bend: Float = 0
    @State private var modulation: Float = 0
    var body: some View {
        HStack(spacing: 6) {
            strip(fill: (bend + 2) / 4, centre: true, label: "Pitch bend",
                  value: String(format: "%+.1f", bend)) { fraction, ended in
                bend = ended ? 0 : (fraction * 2 - 1) * 2
            } adjust: { up in bend = min(2, max(-2, bend + (up ? 0.5 : -0.5))) }
            strip(fill: modulation, centre: false, label: "Modulation",
                  value: String(format: "%.0f%%", modulation * 100)) { fraction, ended in
                if !ended { modulation = fraction }
            } adjust: { up in modulation = min(1, max(0, modulation + (up ? 0.1 : -0.1))) }
        }
        .frame(width: 84)
        .onChange(of: bend) { _, _ in apply(bend, modulation) }
        .onChange(of: modulation) { _, _ in apply(bend, modulation) }
    }

    private func strip(fill: Float, centre: Bool, label: LocalizedStringKey, value: String,
                       drag: @escaping (Float, Bool) -> Void, adjust: @escaping (Bool) -> Void) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: Luz.Radius.cell, style: .continuous).fill(Color.raised)
                RoundedRectangle(cornerRadius: Luz.Radius.cell, style: .continuous).fill(Color.mint.opacity(0.55))
                    .frame(height: max(6, geometry.size.height * CGFloat(fill)))
                if centre { Rectangle().fill(Color.outline).frame(height: 1).offset(y: -geometry.size.height / 2) }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in drag(Float(max(0, min(1, 1 - g.location.y / max(1, geometry.size.height)))), false) }
                .onEnded { g in drag(Float(max(0, min(1, 1 - g.location.y / max(1, geometry.size.height)))), true) })
        }
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(Text(verbatim: value))
        .accessibilityAdjustableAction { direction in adjust(direction == .increment) }
    }
}
