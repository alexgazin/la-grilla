import AVFoundation
import MusicDomain
import SwiftUI

/// Beat machine · A groovebox inside the song: pick a genre and a ready beat, change
/// the kit and the 808, tap steps and pads, hear it with the song's chords, then put
/// it into a section or the whole song in one Undo.
struct BeatMachineView: View {
    @Bindable var session: Session
    @State private var genre: BeatPreset.Genre = .trap
    @State private var draft = BeatDraft(BeatPreset.library[0])
    @State private var selectedPad = 0
    @State private var page = 0
    @State private var bassStep: Int?
    @State private var wholeSong = false
    @State private var useTempo = true
    @State private var muteChordBass = true
    @State private var kits: [FactoryDrumKit: [(pad: Int, asset: SampleAsset, data: Data)]] = [:]
    @State private var basses: [FactorySynth: (asset: SampleAsset, data: Data)] = [:]
    @State private var player: AVAudioPlayer?
    @State private var flash: Int?
    @State private var error: String?
    @State private var applying = false
    @State private var varySeed: UInt64 = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    display
                    genres
                    presets
                    padGrid
                    sequencer
                    bassLane
                    kitPicker
                    soundPicker
                    applyPanel
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
            .background(Color.ink)
            .navigationTitle("Beat machine").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { close() }.accessibilityIdentifier("beat.close")
                }
            }
        }
        .tint(.mint)
        .task(id: draft.kit) { await loadKit(draft.kit) }
        .task(id: draft.bass) { if let bass = draft.bass { await loadBass(bass) } }
        .onChange(of: draft) { _, _ in if session.harmonyPreview { play() } }
        .onDisappear { session.endHarmonyPreview(); player?.stop() }
    }

    // MARK: Display

    private var preset: BeatPreset? { BeatPreset.preset(draft.presetID) }

    private var display: some View {
        let hues = (preset?.genre ?? genre).hues
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(preset?.title ?? "Your beat")).font(.title2.weight(.bold)).foregroundStyle(.white)
                        .accessibilityIdentifier("beat.title")
                    Text(verbatim: "\(NSLocalizedString(preset?.genre.title ?? genre.title, comment: "Genre")) · \(draft.kit.title)")
                        .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.75))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(verbatim: "\(draft.bpm)").font(.system(.largeTitle, design: .monospaced, weight: .bold)).foregroundStyle(.white)
                        .contentTransition(.numericText()).accessibilityIdentifier("beat.bpm")
                    Text("BPM").font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.7))
                }
            }
            BeatLights(session: session, steps: draft.steps, start: session.section.start, active: session.harmonyPreview)
                .frame(height: 10)
            HStack(spacing: 8) {
                stepper(symbol: "minus") { draft.bpm = max(60, draft.bpm - 1) }.accessibilityLabel("Slower").accessibilityIdentifier("beat.tempo.down")
                stepper(symbol: "plus") { draft.bpm = min(200, draft.bpm + 1) }.accessibilityLabel("Faster").accessibilityIdentifier("beat.tempo.up")
                Spacer(minLength: 4)
                Menu {
                    ForEach([50, 54, 58, 62, 66], id: \.self) { value in
                        Button { draft.swing = Double(value) / 100 } label: {
                            let text = value == 50 ? NSLocalizedString("Straight", comment: "Swing") : "\(value)%"
                            if Int((draft.swing * 100).rounded()) == value { Label(text, systemImage: "checkmark") } else { Text(verbatim: text) }
                        }
                    }
                } label: { chip(symbol: "metronome", text: Text(verbatim: swingText)) }
                    .accessibilityLabel("Swing").accessibilityValue(Text(verbatim: swingText)).accessibilityIdentifier("beat.swing")
                Button { withAnimation(Luz.Motion.snap) { draft.setBars(draft.bars == 1 ? 2 : 1); page = 0 } } label: {
                    chip(symbol: "square.split.2x1", text: Text("\(draft.bars) bars"))
                }.buttonStyle(.plain).accessibilityIdentifier("beat.bars")
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: Luz.Radius.card + 4, style: .continuous)
                .fill(LinearGradient(colors: [Color(hue: hues.0, saturation: 0.75, brightness: 0.55), Color(hue: hues.1, saturation: 0.8, brightness: 0.3)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(alignment: .topTrailing) {
                    Image(systemName: (preset?.genre ?? genre).symbol).font(.system(size: 92, weight: .bold)).foregroundStyle(.white.opacity(0.08))
                        .offset(x: 10, y: -8).accessibilityHidden(true)
                }
                .clipShape(RoundedRectangle(cornerRadius: Luz.Radius.card + 4, style: .continuous))
        }
        .animation(reduceMotion ? nil : Luz.Motion.morph, value: draft.presetID)
    }

    private var swingText: String {
        draft.swing <= 0.5 ? NSLocalizedString("Straight", comment: "Swing") : "\(Int((draft.swing * 100).rounded()))%"
    }

    private func stepper(symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.headline).frame(width: 44, height: 36)
                .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous)).foregroundStyle(.white)
        }.buttonStyle(.plain)
    }

    private func chip(symbol: String, text: Text) -> some View {
        Label { text } icon: { Image(systemName: symbol) }.font(.caption.weight(.semibold)).foregroundStyle(.white)
            .padding(.horizontal, 10).frame(minHeight: 36)
            .background(.white.opacity(0.16), in: Capsule())
    }

    // MARK: Genres and presets

    private var genres: some View {
        VStack(alignment: .leading, spacing: 8) {
            header("Genres")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(BeatPreset.Genre.allCases) { item in
                        Button { withAnimation(Luz.Motion.snap) { genre = item } } label: { GenreArt(genre: item, selected: genre == item) }
                            .buttonStyle(.plain)
                            .accessibilityLabel(LocalizedStringKey(item.title))
                            .accessibilityAddTraits(genre == item ? .isSelected : [])
                            .accessibilityIdentifier("beat.genre.\(item.rawValue)")
                    }
                }.padding(.vertical, 2)
            }
        }
    }

    private var presets: some View {
        VStack(alignment: .leading, spacing: 8) {
            header("Ready beats")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(BeatPreset.presets(genre)) { item in
                        Button { choose(item) } label: { PresetCard(preset: item, selected: draft.presetID == item.id) }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(draft.presetID == item.id ? .isSelected : [])
                            .accessibilityIdentifier("beat.preset.\(item.id)")
                    }
                }.padding(.vertical, 2)
            }
        }
    }

    private func choose(_ item: BeatPreset) {
        withAnimation(reduceMotion ? nil : Luz.Motion.morph) { draft = BeatDraft(item); page = 0; bassStep = nil }
        Luz.Haptics.selection()
    }

    // MARK: Pads

    private var padGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            header("Pads")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(Self.padOrder, id: \.self) { pad in
                    Button { tapPad(pad) } label: {
                        BeatPad(pad: pad, selected: selectedPad == pad, used: draft.grid[pad] != nil, flashing: flash == pad,
                                session: session, draft: draft, active: session.harmonyPreview)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(LocalizedStringKey(Compiler.padNames[pad]))
                    .accessibilityAddTraits(selectedPad == pad ? .isSelected : [])
                    .accessibilityIdentifier("beat.pad.\(pad)")
                }
            }
        }
    }

    /// Kick, snare, clap, hats first — the order beats are built in.
    static let padOrder = [0, 1, 4, 5, 2, 3, 9, 10, 6, 7, 8, 15, 11, 12, 13, 14]

    private func tapPad(_ pad: Int) {
        selectedPad = pad
        flash = pad
        Luz.Haptics.hit(velocity: 110)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(160))
            if flash == pad { flash = nil }
        }
        let kit = draft.kit
        Task { @MainActor in
            guard session.ensureAudio(), let wave = try? await Task.detached(operation: { try kit.oneShotWAV(pad: pad) }).value,
                  let audio = try? AVAudioPlayer(data: wave) else { return }
            player?.stop(); player = audio; audio.play()
        }
    }

    // MARK: Step sequencer

    private var lanes: [Int] {
        let used = Set(draft.activePads).union([selectedPad])
        return Self.padOrder.filter(used.contains)
    }

    private var sequencer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                header("Steps")
                Spacer()
                if draft.bars == 2 {
                    StudioSegments(title: "Bar", selection: $page, options: [(0, "Bar 1"), (1, "Bar 2")], identifier: "beat.page").frame(width: 170)
                }
            }
            VStack(spacing: 6) {
                ForEach(lanes, id: \.self) { pad in stepRow(pad) }
            }
            HStack(spacing: 8) {
                Button { varySeed &+= 1; withAnimation(Luz.Motion.snap) { draft.vary(seed: varySeed) } } label: {
                    Label("Variation", systemImage: "dice").frame(maxWidth: .infinity, minHeight: 40)
                }.buttonStyle(StudioActionStyle(color: .drums, prominent: false)).accessibilityIdentifier("beat.vary")
                Button { withAnimation(Luz.Motion.snap) { draft.clear(); bassStep = nil } } label: {
                    Label("Clear", systemImage: "trash").frame(maxWidth: .infinity, minHeight: 40)
                }.buttonStyle(StudioActionStyle(color: .record, prominent: false)).accessibilityIdentifier("beat.clear")
            }
            Text("Tap a step to add a hit, touch and hold for accent, ghost or a roll.").font(.caption).foregroundStyle(Color.muted)
        }
    }

    private func stepRow(_ pad: Int) -> some View {
        HStack(spacing: 6) {
            Button { tapPad(pad) } label: {
                HStack(spacing: 5) {
                    Circle().fill(BeatPad.color(pad)).frame(width: 8, height: 8)
                    Text(LocalizedStringKey(Compiler.padNames[pad])).font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                        .foregroundStyle(selectedPad == pad ? Color.studioText : Color.muted)
                }.frame(width: 62, alignment: .leading)
            }.buttonStyle(.plain)
            HStack(spacing: 3) {
                ForEach(0..<16, id: \.self) { index in
                    let step = page * 16 + index
                    StepCell(hit: draft.hit(pad: pad, step: step), color: BeatPad.color(pad), downbeat: index % 4 == 0)
                        .onTapGesture { withAnimation(.snappy(duration: 0.15)) { draft.toggle(pad: pad, step: step) }; Luz.Haptics.selection() }
                        .contextMenu { stepMenu(pad: pad, step: step) }
                        .accessibilityElement()
                        .accessibilityLabel(Text(verbatim: "\(NSLocalizedString(Compiler.padNames[pad], comment: "Pad")) \(step + 1)"))
                        .accessibilityValue(LocalizedStringKey(Self.hitName(draft.hit(pad: pad, step: step))))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { draft.toggle(pad: pad, step: step) }
                        .accessibilityIdentifier("beat.step.\(pad).\(step)")
                }
            }
            .overlay { StepPlayhead(session: session, steps: draft.steps, page: page, start: session.section.start, active: session.harmonyPreview) }
        }
    }

    static func hitName(_ hit: StepHit) -> String {
        switch hit {
        case .off: "Off"
        case .ghost: "Ghost"
        case .normal: "Hit"
        case .accent: "Accent"
        case .roll: "Roll"
        }
    }

    @ViewBuilder private func stepMenu(pad: Int, step: Int) -> some View {
        Button("Accent", systemImage: "exclamationmark") { draft.set(pad: pad, step: step, .accent) }
        Button("Hit", systemImage: "circle.fill") { draft.set(pad: pad, step: step, .normal) }
        Button("Ghost", systemImage: "circle.dotted") { draft.set(pad: pad, step: step, .ghost) }
        Button("Roll ×2", systemImage: "2.circle") { draft.set(pad: pad, step: step, .roll(2)) }
        Button("Roll ×3", systemImage: "3.circle") { draft.set(pad: pad, step: step, .roll(3)) }
        Button("Roll ×4", systemImage: "4.circle") { draft.set(pad: pad, step: step, .roll(4)) }
        Button("Off", systemImage: "xmark", role: .destructive) { draft.set(pad: pad, step: step, .off) }
    }

    // MARK: 808 lane

    private var bassLane: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                header("808 and bass")
                Spacer()
                if let step = bassStep, let note = draft.bassNotes.first(where: { $0.step == step }) {
                    Text(verbatim: noteName(note.semitones)).font(.caption.monospaced().weight(.bold)).foregroundStyle(Color.bass)
                        .accessibilityIdentifier("beat.bass.note")
                }
            }
            HStack(spacing: 3) {
                ForEach(0..<16, id: \.self) { index in
                    let step = page * 16 + index
                    BassCell(note: draft.bassNote(at: step), step: step, selected: bassStep != nil && draft.bassNote(at: step)?.step == bassStep,
                             downbeat: index % 4 == 0, label: draft.bassNotes.first { $0.step == step }.map { noteName($0.semitones) })
                        .onTapGesture { tapBass(step) }
                        .accessibilityElement()
                        .accessibilityLabel(Text(verbatim: "808 \(step + 1)"))
                        .accessibilityValue(Text(verbatim: draft.bassNote(at: step).map { noteName($0.semitones) } ?? NSLocalizedString("Off", comment: "Step")))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { tapBass(step) }
                        .accessibilityIdentifier("beat.bass.\(step)")
                }
            }.padding(.leading, 68)
            if let step = bassStep, draft.bassNotes.contains(where: { $0.step == step }) {
                HStack(spacing: 8) {
                    bassKey("chevron.down", "Lower") { draft.transposeBass(step: step, by: -1) }.accessibilityIdentifier("beat.bass.down")
                    bassKey("chevron.up", "Higher") { draft.transposeBass(step: step, by: 1) }.accessibilityIdentifier("beat.bass.up")
                    bassKey("arrow.down.to.line", "Octave down") { draft.transposeBass(step: step, by: -12) }
                    bassKey("arrow.up.to.line", "Octave up") { draft.transposeBass(step: step, by: 12) }
                    Spacer()
                    bassKey("minus", "Shorter") { if let note = draft.bassNotes.first(where: { $0.step == step }) { draft.setBassLength(step: step, note.length - 1) } }
                    bassKey("plus", "Longer") { if let note = draft.bassNotes.first(where: { $0.step == step }) { draft.setBassLength(step: step, note.length + 1) } }
                }
            }
            Text("Notes follow the song's key. Tap a step for a note, tap it again to pick its pitch and length.").font(.caption).foregroundStyle(Color.muted)
        }
    }

    private func tapBass(_ step: Int) {
        Luz.Haptics.selection()
        if let note = draft.bassNote(at: step), bassStep != note.step { bassStep = note.step; return }
        withAnimation(.snappy(duration: 0.15)) {
            draft.toggleBass(step: step)
            bassStep = draft.bassNotes.first { $0.step == step }?.step
        }
    }

    private func noteName(_ semitones: Int) -> String {
        let pitch = BeatDraft.bassRoot(keyRoot: session.project.keyRoot) + BeatDraft.fitted(semitones, writtenMinor: draft.minor, songMinor: session.project.minor)
        return PitchSpelling.pitchClassName(pitch % 12, keyRoot: session.project.keyRoot, minor: session.project.minor) + String(pitch / 12 - 1)
    }

    private func bassKey(_ symbol: String, _ label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.subheadline.weight(.semibold)).frame(width: 40, height: 36) }
            .buttonStyle(StudioActionStyle(color: .bass, prominent: false)).accessibilityLabel(label)
    }

    // MARK: Sounds

    private var kitPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            header("Drum kit")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(FactoryDrumKit.allCases, id: \.self) { kit in
                        Button { draft.kit = kit; tapPad(selectedPad) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Image(systemName: kit == draft.kit ? "checkmark.circle.fill" : "square.grid.2x2.fill")
                                    .foregroundStyle(kit == draft.kit ? Color.mint : Color.drums)
                                Text(verbatim: kit.title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.studioText)
                                Text(LocalizedStringKey(kit.brief)).font(.caption2).foregroundStyle(Color.muted).lineLimit(2)
                            }
                            .padding(10).frame(width: 150, height: 96, alignment: .topLeading)
                            .background(Color.panel, in: RoundedRectangle(cornerRadius: Luz.Radius.card, style: .continuous))
                            .overlay { RoundedRectangle(cornerRadius: Luz.Radius.card, style: .continuous).strokeBorder(kit == draft.kit ? Color.mint : Color.outline, lineWidth: kit == draft.kit ? 2 : 0.75) }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(kit == draft.kit ? .isSelected : [])
                        .accessibilityIdentifier("beat.kit.\(kit.rawValue)")
                    }
                }.padding(.vertical, 2)
            }
        }
    }

    private var soundPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            header("Bass sound")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    soundChip(nil)
                    ForEach(FactorySynth.basses) { synth in soundChip(synth) }
                }.padding(.vertical, 2)
            }
        }
    }

    private func soundChip(_ synth: FactorySynth?) -> some View {
        let selected = draft.bass == synth
        return Button {
            draft.bass = synth
            if let synth { audition(synth) }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: synth == nil ? "speaker.slash" : "waveform").foregroundStyle(selected ? Color.mint : Color.bass)
                Text(LocalizedStringKey(synth?.title ?? "No bass")).font(.subheadline.weight(.semibold)).foregroundStyle(Color.studioText).lineLimit(1)
                Text(LocalizedStringKey(synth?.brief ?? "Drums only; the song's bass stays.")).font(.caption2).foregroundStyle(Color.muted).lineLimit(2)
            }
            .padding(10).frame(width: 150, height: 96, alignment: .topLeading)
            .background(Color.panel, in: RoundedRectangle(cornerRadius: Luz.Radius.card, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: Luz.Radius.card, style: .continuous).strokeBorder(selected ? Color.mint : Color.outline, lineWidth: selected ? 2 : 0.75) }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("beat.sound.\(synth?.rawValue ?? "none")")
    }

    private func audition(_ synth: FactorySynth) {
        Task { @MainActor in
            guard session.ensureAudio(), let wave = try? await Task.detached(operation: { try synth.previewWAV() }).value,
                  let audio = try? AVAudioPlayer(data: wave) else { return }
            player?.stop(); player = audio; audio.play()
        }
    }

    // MARK: Apply

    private var applyPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            let sectionLabel = String(format: NSLocalizedString("Section · %@", comment: "Beat scope"), session.section.name)
            StudioSegments(title: "Where", selection: $wholeSong, options: [(false, LocalizedStringKey(sectionLabel)), (true, "Whole song")],
                           identifier: "beat.scope")
            Toggle(isOn: $useTempo) { Text(String(format: NSLocalizedString("Use the beat's tempo (%lld BPM)", comment: "Beat machine"), draft.bpm)) }
                .accessibilityIdentifier("beat.use-tempo")
            if draft.bass != nil && !draft.bassNotes.isEmpty && session.project.tracks.contains(where: { $0.role == .bass }) {
                Toggle("Mute the chord bass while the 808 plays", isOn: $muteChordBass).accessibilityIdentifier("beat.mute-bass")
            }
            Button { session.harmonyPreview ? session.endHarmonyPreview() : play() } label: {
                Label(LocalizedStringKey(session.harmonyPreview ? "Stop" : "Play with the song"), systemImage: session.harmonyPreview ? "stop.fill" : "play.fill")
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(StudioActionStyle(color: session.harmonyPreview ? .record : .mint))
            .disabled(!ready)
            .accessibilityIdentifier("beat.play")
            Button { apply() } label: {
                Group {
                    if applying { ProgressView() } else { Label("Put the beat in the song", systemImage: "square.and.arrow.down.on.square") }
                }.font(.headline).frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(StudioActionStyle(color: .drums))
            .disabled(!ready || applying || session.recording || session.armed)
            .accessibilityIdentifier("beat.apply")
            if let error { Text(error).font(.caption).foregroundStyle(Color.record).accessibilityIdentifier("beat.error") }
            Text("Nothing changes until you put the beat in. One Undo takes it back. Every sound is made on this iPhone and is yours to use.")
                .font(.caption).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Color.panel, in: RoundedRectangle(cornerRadius: Luz.Radius.card, style: .continuous))
    }

    private func header(_ title: LocalizedStringKey) -> some View {
        Text(title).font(.caption.weight(.semibold)).textCase(.uppercase).tracking(1.1).foregroundStyle(Color.muted)
    }

    private var ready: Bool {
        guard kits[draft.kit] != nil, draft.hitCount > 0 || !draft.bassNotes.isEmpty else { return false }
        if let bass = draft.bass, !draft.bassNotes.isEmpty { return basses[bass] != nil }
        return true
    }

    private var sounds: [(pad: Int, asset: SampleAsset, data: Data)] {
        var result = kits[draft.kit] ?? []
        if let bass = draft.bass, let sound = basses[bass] { result.append((pad: -1, asset: sound.asset, data: sound.data)) }
        return result
    }

    private func candidate() throws -> Project? {
        guard ready, let kit = kits[draft.kit] else { return nil }
        let assets = Dictionary(uniqueKeysWithValues: kit.map { ($0.pad, $0.asset) })
        let bass = draft.bass.flatMap { basses[$0]?.asset }
        return try BeatMachine.candidate(session.project, draft: draft, scope: wholeSong ? .song : .section(session.section.id), kit: assets, bass: bass,
                                         options: .init(useTempo: useTempo, muteChordBass: muteChordBass))
    }

    private func play() {
        do {
            guard let project = try candidate() else { return }
            error = nil
            let section = session.section
            session.previewPalette(project, range: section.start..<min(project.length, section.start + section.length), samples: try session.paletteLibrary(sounds))
        } catch { self.error = error.localizedDescription }
    }

    private func apply() {
        let id = session.project.id, revision = session.project.revision
        do {
            guard let project = try candidate() else { return }
            applying = true
            let staged = sounds
            Task { @MainActor in
                do {
                    try await session.applyPalette(project, kit: staged, projectID: id, revision: revision)
                    applying = false
                    session.showToast("Beat added")
                    Luz.Haptics.success()
                    close()
                } catch {
                    applying = false
                    self.error = error.localizedDescription
                }
            }
        } catch { self.error = error.localizedDescription }
    }

    private func close() { session.endHarmonyPreview(); player?.stop(); session.sheet = nil }

    private func loadKit(_ kit: FactoryDrumKit) async {
        guard kits[kit] == nil else { return }
        do {
            let made = try await Task.detached(priority: .userInitiated) { try PaletteEngine.kit(kit) }.value
            kits[kit] = made
            if session.harmonyPreview { play() }
        } catch { self.error = error.localizedDescription }
    }

    private func loadBass(_ synth: FactorySynth) async {
        guard basses[synth] == nil else { return }
        do {
            let made = try await Task.detached(priority: .userInitiated) { try synth.asset() }.value
            basses[synth] = made
            if session.harmonyPreview { play() }
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: - Graphics

/// Genre artwork: a gradient tile with the genre's symbol and soft rings.
private struct GenreArt: View {
    let genre: BeatPreset.Genre
    let selected: Bool
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hue: genre.hues.0, saturation: 0.7, brightness: 0.85), Color(hue: genre.hues.1, saturation: 0.85, brightness: 0.4)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Canvas { context, size in
                    for ring in 1...3 {
                        let radius = size.width * 0.22 * Double(ring)
                        let rect = CGRect(x: size.width * 0.78 - radius, y: size.height * 0.82 - radius, width: radius * 2, height: radius * 2)
                        context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.13)), lineWidth: 1.5)
                    }
                }
                Image(systemName: genre.symbol).font(.system(size: 28, weight: .bold)).foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
            }
            .frame(width: 76, height: 76)
            .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(selected ? Color.mint : .clear, lineWidth: 3) }
            .scaleEffect(selected ? 1.04 : 1)
            .shadow(color: selected ? Color(hue: genre.hues.0, saturation: 0.8, brightness: 0.9).opacity(0.5) : .clear, radius: 10)
            Text(LocalizedStringKey(genre.title)).font(.caption.weight(.semibold)).foregroundStyle(selected ? Color.studioText : Color.muted)
                .lineLimit(1).frame(width: 84)
        }
        .animation(Luz.Motion.snap, value: selected)
    }
}

/// A preset card with a miniature of its pattern: one row of dots per pad.
private struct PresetCard: View {
    let preset: BeatPreset
    let selected: Bool
    var body: some View {
        let draft = BeatDraft(preset)
        VStack(alignment: .leading, spacing: 8) {
            Canvas { context, size in
                let pads = draft.activePads.prefix(5)
                let rows = max(1, pads.count)
                let cell = min(size.width / Double(draft.steps), size.height / Double(rows))
                for (row, pad) in pads.enumerated() {
                    for step in 0..<draft.steps {
                        let hit = draft.hit(pad: pad, step: step)
                        let rect = CGRect(x: Double(step) * size.width / Double(draft.steps), y: Double(row) * size.height / Double(rows),
                                          width: max(1.5, cell - 1.5), height: max(1.5, cell - 1.5))
                        let level: Double = switch hit { case .off: 0.08; case .ghost: 0.35; case .accent: 1; default: 0.75 }
                        context.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(BeatPad.color(pad).opacity(level)))
                    }
                }
            }
            .frame(height: 40)
            Text(LocalizedStringKey(preset.title)).font(.subheadline.weight(.semibold)).foregroundStyle(Color.studioText).lineLimit(1)
            HStack(spacing: 6) {
                Text(verbatim: "\(preset.bpm) BPM").font(.caption2.monospacedDigit())
                Text(verbatim: "·")
                Text(verbatim: preset.kit.title).font(.caption2)
                if let bass = preset.bass { Text(verbatim: "·"); Text(LocalizedStringKey(bass.title)).font(.caption2) }
            }.foregroundStyle(Color.muted).lineLimit(1)
        }
        .padding(10).frame(width: 196, alignment: .leading)
        .background(selected ? Color(hue: preset.genre.hues.0, saturation: 0.5, brightness: 0.35).opacity(0.55) : Color.panel,
                    in: RoundedRectangle(cornerRadius: Luz.Radius.card, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: Luz.Radius.card, style: .continuous).strokeBorder(selected ? Color.mint : Color.outline, lineWidth: selected ? 2 : 0.75) }
    }
}

/// One of the sixteen pads. It glows when its step plays in the audition.
private struct BeatPad: View {
    let pad: Int
    let selected: Bool
    let used: Bool
    let flashing: Bool
    let session: Session
    let draft: BeatDraft
    let active: Bool

    static func color(_ pad: Int) -> Color {
        switch pad {
        case 0: .record
        case 1, 4, 5: .harmony
        case 2, 3, 9, 10: .mint
        case 6, 7, 8: .drums
        default: .bass
        }
    }

    var body: some View {
        let color = Self.color(pad)
        let lit = flashing || playingNow
        VStack(spacing: 4) {
            Circle().fill(used ? color : color.opacity(0.25)).frame(width: 6, height: 6)
            Text(LocalizedStringKey(Compiler.padNames[pad])).font(StudioTypography.pad).foregroundStyle(lit ? Color.ink : Color.studioText)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity).frame(height: 64)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(lit ? AnyShapeStyle(color) : AnyShapeStyle(LinearGradient(colors: [color.opacity(used ? 0.32 : 0.14), color.opacity(0.06)], startPoint: .top, endPoint: .bottom)))
        }
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(selected ? color : Color.outline.opacity(0.6), lineWidth: selected ? 2 : 0.75) }
        .shadow(color: lit ? color.opacity(0.7) : .clear, radius: lit ? 12 : 0)
        .scaleEffect(flashing ? 0.95 : 1)
        .animation(.easeOut(duration: 0.12), value: lit)
    }

    private var playingNow: Bool {
        guard active else { return false }
        let tick = Int(session.audio.tick) - session.section.start
        guard tick >= 0 else { return false }
        let step = (tick % max(1, draft.length)) / 240
        return draft.hit(pad: pad, step: step).isOn
    }
}

private struct StepCell: View {
    let hit: StepHit
    let color: Color
    let downbeat: Bool
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        ZStack {
            shape.fill(fill)
            if case let .roll(count) = hit {
                HStack(spacing: 1) { ForEach(0..<count, id: \.self) { _ in Capsule().fill(Color.ink.opacity(0.7)).frame(width: 2) } }.padding(.vertical, 6)
            }
        }
        .frame(maxWidth: .infinity).frame(height: 30)
        .overlay { shape.strokeBorder(hit == .accent ? Color.studioText.opacity(0.8) : .clear, lineWidth: 1.5) }
        .contentShape(shape)
    }
    private var fill: Color {
        switch hit {
        case .off: downbeat ? Color.lifted : Color.raised
        case .ghost: color.opacity(0.4)
        case .normal, .roll: color.opacity(0.85)
        case .accent: color
        }
    }
}

private struct BassCell: View {
    let note: BassStep?
    let step: Int
    let selected: Bool
    let downbeat: Bool
    let label: String?
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        ZStack {
            shape.fill(note == nil ? (downbeat ? Color.lifted : Color.raised) : Color.bass.opacity(note?.step == step ? 0.95 : 0.55))
            if let label {
                Text(verbatim: label).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(Color.ink)
                    .lineLimit(1).minimumScaleFactor(0.5).padding(.horizontal, 1)
            }
        }
        .frame(maxWidth: .infinity).frame(height: 34)
        .overlay { shape.strokeBorder(selected ? Color.studioText : .clear, lineWidth: 1.5) }
        .contentShape(shape)
    }
}

/// The playing step across the visible bar of the sequencer.
private struct StepPlayhead: View {
    let session: Session
    let steps: Int
    let page: Int
    let start: Int
    let active: Bool
    var body: some View {
        GeometryReader { proxy in
            if active, let index = index {
                let width = proxy.size.width / 16
                RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.18))
                    .frame(width: width, height: proxy.size.height)
                    .offset(x: Double(index) * width)
                    .transaction { $0.animation = nil }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
    private var index: Int? {
        let tick = Int(session.audio.tick) - start
        guard tick >= 0 else { return nil }
        let step = (tick % max(1, steps * 240)) / 240
        return step / 16 == page ? step % 16 : nil
    }
}

/// Sixteen or thirty-two lights that chase the playing step, like a drum machine's LEDs.
private struct BeatLights: View {
    let session: Session
    let steps: Int
    let start: Int
    let active: Bool
    var body: some View {
        let current: Int? = {
            guard active else { return nil }
            let tick = Int(session.audio.tick) - start
            return tick >= 0 ? (tick % max(1, steps * 240)) / 240 : nil
        }()
        HStack(spacing: steps > 16 ? 2 : 3) {
            ForEach(0..<steps, id: \.self) { step in
                Capsule().fill(step == current ? Color.white : Color.white.opacity(step % 4 == 0 ? 0.35 : 0.18))
                    .shadow(color: step == current ? .white : .clear, radius: 4)
            }
        }
        .transaction { $0.animation = nil }
        .accessibilityHidden(true)
    }
}

/// Artwork for an instrument: the photo for recorded and modelled ones, a drawn tile for synths.
struct InstrumentArtwork: View {
    let instrument: FactoryInstrument
    var body: some View {
        if let synth = instrument.synth {
            let hue = Self.hue(synth.family), symbol = Self.symbol(synth.family)
            ZStack {
                LinearGradient(colors: [Color(hue: hue, saturation: 0.65, brightness: 0.75), Color(hue: hue + 0.08, saturation: 0.8, brightness: 0.3)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: symbol).font(.system(size: 22, weight: .bold)).foregroundStyle(.white.opacity(0.9))
            }
            .accessibilityHidden(true)
        } else {
            Image(instrument.artwork).resizable().scaledToFill()
        }
    }
    private static func hue(_ family: FactorySynth.Family) -> Double {
        switch family { case .bass: 0.47; case .lead: 0.83; case .keys: 0.12; case .pad: 0.62 }
    }
    private static func symbol(_ family: FactorySynth.Family) -> String {
        switch family { case .bass: "waveform.path"; case .lead: "bolt.horizontal.fill"; case .keys: "pianokeys"; case .pad: "cloud.fill" }
    }
}

/// The Jam screen's way into the beat machine: a lit strip with the count of ready beats.
struct BeatMachineEntry: View {
    let open: () -> Void
    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                HStack(spacing: 3) {
                    ForEach(0..<4, id: \.self) { column in
                        VStack(spacing: 3) {
                            ForEach(0..<3, id: \.self) { row in
                                RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity((column + row) % 3 == 0 ? 0.95 : 0.35)).frame(width: 7, height: 7)
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Beat machine").font(.headline).foregroundStyle(.white)
                    Text(String(format: NSLocalizedString("%lld ready beats · 19 kits · 808", comment: "Beat machine entry"), BeatPreset.library.count))
                        .font(.caption).foregroundStyle(.white.opacity(0.8))
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.subheadline.weight(.bold)).foregroundStyle(.white.opacity(0.8))
            }
            .padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 56)
            .background(LinearGradient(colors: [Color(hue: 0.98, saturation: 0.7, brightness: 0.6), Color(hue: 0.75, saturation: 0.75, brightness: 0.45)],
                                       startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: Luz.Radius.card, style: .continuous))
        }
        .buttonStyle(StudioQuietButtonStyle(radius: Luz.Radius.card))
        .accessibilityIdentifier("jam.beat-machine")
    }
}
