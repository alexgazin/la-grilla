import SwiftUI
import MusicDomain

struct MixerView: View {
    @Bindable var session: Session
    @State private var synthTrack: SynthTarget?
    /// U48: a double tap on a channel name renames the track.
    @State private var renamingTrack: UUID?
    @State private var renameText = ""
    /// Gain when the current fader drag began; the drag moves relative to it.
    @State private var dragStartGain: Double?
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var activeFader: Int?
    @State private var equalizer: EQDestination?
    /// U60: simple mode keeps inserts and automation behind "Show more".
    @AppStorage(InterfacePreferences.featureLevelKey) private var featureLevel = FeatureLevel.full.rawValue
    @State private var showMore = false
    private var advanced: Bool { showMore || (FeatureLevel(rawValue: featureLevel) ?? .full) == .full }

    var body: some View {
        Group {
            if dynamicType.isAccessibilitySize { accessibleMixer }
            else { standardMixer }
        }
        .sheet(item:$equalizer) { EqualizerView(session:session,destination:$0) }
        .renameAlert("Rename track", item: $renamingTrack, text: $renameText, limit: 40) { id, name in
            session.edit { p in if let i = p.tracks.firstIndex(where: { $0.id == id }) { p.tracks[i].name = name } }
        }
        .sheet(item:$synthTrack) { SynthEditorView(session: session, trackID: $0.id) }
        .onAppear { StudioSignposts.endMixer() }
        .onDisappear { finishGesture() }
        .onChange(of: session.performance.replaying) { _, replaying in
            if replaying { finishGesture() }
        }
    }

    private var standardMixer: some View {
        GeometryReader { geometry in
            // Keep useful fader travel even when the landscape workspace scrolls.
            // Small iPhones: strips follow the visible height so Mute, Solo and Pan stay on screen.
            let tight = geometry.size.height < 560
            let stripHeight = tight ? max(300, geometry.size.height - 92) : min(500, max(464, geometry.size.height - 88))
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    deskHeading
                    console(height: stripHeight, tight: tight)
                    MasterSpectrum(audio: session.audio)
                    deskFootnote
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 18)
                .disabled(session.performance.replaying)
            }
        }
    }

    private var deskHeading: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Find your balance.")
                    .font(.system(size: 25, weight: .semibold))
                    .tracking(-0.7)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            Button { session.endHarmonyPreview(); session.sheet = .palettes } label: {
                Label("Palettes", systemImage: "paintpalette").font(.caption.weight(.semibold))
                    .frame(minHeight: 44).padding(.horizontal, 10)
                    .background(Color.raised.opacity(0.55), in: RoundedRectangle(cornerRadius: StudioMetrics.controlRadius, style: .continuous))
            }.buttonStyle(StudioQuietButtonStyle()).accessibilityIdentifier("mixer.palettes")
                .disabled(session.performance.contextActive)
            // I37: write level and pan moves into automation while playing.
            if advanced {
            Button { session.automationRecording.toggle(); Luz.Haptics.selection() } label: {
                Label("Automation", systemImage: session.automationRecording ? "record.circle.fill" : "record.circle")
                    .labelStyle(.iconOnly).font(.system(size: 18, weight: .medium))
                    .foregroundStyle(session.automationRecording ? Color.record : Color.muted)
                    .frame(width: 44, height: 44)
                    .background(Color.raised.opacity(0.55), in: RoundedRectangle(cornerRadius: StudioMetrics.controlRadius, style: .continuous))
            }
            .buttonStyle(StudioQuietButtonStyle())
            .accessibilityLabel(Text(LocalizedStringKey(session.automationRecording ? "Stop writing automation" : "Write automation")))
            .accessibilityAddTraits(session.automationRecording ? .isSelected : [])
            .accessibilityIdentifier("mixer.automation")
            .disabled(session.performance.contextActive)
            } else {
                Button { withAnimation(Luz.Motion.morph) { showMore = true } } label: {
                    Label("Show more", systemImage: "ellipsis.circle").labelStyle(.iconOnly).font(.system(size: 18, weight: .medium))
                        .frame(width: 44, height: 44)
                        .background(Color.raised.opacity(0.55), in: RoundedRectangle(cornerRadius: StudioMetrics.controlRadius, style: .continuous))
                }
                .buttonStyle(StudioQuietButtonStyle())
                .accessibilityLabel("Show more")
                .accessibilityIdentifier("mixer.show-more")
            }
            MixPresetMenu(session: session)
            VStack(spacing: 5) {
                Image(systemName: "headphones")
                    .font(.system(size: 18, weight: .medium))
                Text("STEREO")
                    .font(.system(.caption2, design: .monospaced, weight: .semibold))
                    .tracking(0.8)
            }
            .foregroundStyle(Color.muted)
            .accessibilityHidden(true)
        }
    }

    private func console(height: CGFloat, tight: Bool = false) -> some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(Array(session.displayProject.tracks.enumerated()), id: \.element.id) { index, track in
                        channel(index: index, track: track, height: height, tight: tight)
                            .frame(width: 120)
                            .overlay(alignment: .trailing) { consoleSeam }
                    }
                }
            }
            .scrollIndicators(.visible)
            channel(index: masterBus, track: nil, height: height, tight: tight)
                .frame(width: 108)
                .background(Color.raised.opacity(0.45))
                .overlay(alignment: .leading) { consoleSeam }
        }
        .frame(height: height)
        .background(Color.panel)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.outline.opacity(contrast == .increased ? 1 : 0.8), lineWidth: 1)
        }
        .overlay(alignment: .top) {
            Capsule().fill(Color.studioText.opacity(0.12))
                .frame(height: 1).padding(.horizontal, 20)
        }
    }

    private var consoleSeam: some View {
        Rectangle().fill(Color.outline.opacity(contrast == .increased ? 1 : 0.6))
            .frame(width: 1)
            .padding(.vertical, 12)
            .accessibilityHidden(true)
    }

    private var deskFootnote: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "waveform.path")
                .font(.system(.subheadline, weight: .medium))
                .foregroundStyle(Color.mint)
                .padding(.top, 2)
                .accessibilityHidden(true)
            Text("A little space goes a long way.\nKeep the master below the red.")
                .font(.caption)
                .foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// `tight`: compact height; the per-track sound slot moves out (it stays on the Jam
    /// screen and the grid's track labels) and the pan row is shorter.
    private func channel(index: Int, track: Track?, height: CGFloat, tight: Bool = false) -> some View {
        let color = track.map { Color.track($0) } ?? .mint
        let gain = track?.gain ?? session.displayProject.master
        return VStack(spacing: 0) {
            channelHeading(track: track, color: color)
                .frame(height: 34)
            if !tight {
                soundSlot(track: track, color: color)
                    .frame(height: 56)
            }
            if advanced { eqButton(track) }
            gainReadout(index: index, gain: gain, color: color)
                .padding(.vertical, tight ? 0 : 4)
            fader(index: index, track: track, gain: gain, color: color)
                .padding(.vertical, tight ? 4 : 8)
            panSlot(index: index, track: track, color: color)
                .frame(height: tight ? 66 : 84)
            if let track {
                channelSwitches(index: index, track: track, color: color)
            } else {
                outputState.frame(height: 44)
            }
        }
        .padding(.horizontal, 9)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .frame(height: height)
    }

    @ViewBuilder private func channelHeading(track: Track?, color: Color) -> some View {
        if let track {
            // I39: the heading opens a menu to lock the part against generators and phrase edits.
            Menu {
                // U30 menu: track — Listen · Rename · Duplicate · Colour · … · Delete (last, red).
                Button(track.solo ? "Stop hearing it alone" : "Hear it alone", systemImage: "headphones") {
                    let id = track.id
                    session.mixerEdit { p in if let i = p.tracks.firstIndex(where: { $0.id == id }) { p.tracks[i].solo.toggle() } }
                }.accessibilityIdentifier("mixer.track.listen")
                Button("Rename…", systemImage: "pencil") { renameText = track.displayName; renamingTrack = track.id }
                    .accessibilityIdentifier("mixer.track.rename")
                if track.role == .melody {
                    Button("Duplicate", systemImage: "plus.square.on.square") { session.duplicateMelody(track.id) }
                        .disabled(session.project.tracks.count >= masterBus).accessibilityIdentifier("mixer.track.duplicate")
                }
                // U47: a colour of your own for this track.
                Picker("Colour", selection: Binding(get: { track.color ?? -1 }, set: { value in
                    let id = track.id
                    session.edit { p in if let i = p.tracks.firstIndex(where: { $0.id == id }) { p.tracks[i].color = value < 0 ? nil : value } }
                })) {
                    Text("By role").tag(-1)
                    ForEach(Array(["Gold", "Coral", "Violet", "Mint", "Red"].enumerated()), id: \.offset) { index, name in Text(LocalizedStringKey(name)).tag(index) }
                }.accessibilityIdentifier("mixer.track.color")
                Button(track.locked == true ? "Unlock part" : "Lock part", systemImage: track.locked == true ? "lock.open" : "lock") {
                    let id = track.id
                    session.edit { p in if let i = p.tracks.firstIndex(where: { $0.id == id }) { p.tracks[i].locked = p.tracks[i].locked == true ? nil : true } }
                }
                if advanced {
                    dynamicsMenu(track)
                    Button("Automation…", systemImage: "point.topleft.down.to.point.bottomright.curvepath") {
                        session.automationTrackID = track.id; session.presentEditor(.automation)
                    }
                }
                if track.role == .melody, session.project.tracks.filter({ $0.role == .melody }).count > 1 {
                    Button("Delete track", systemImage: "trash", role: .destructive) { session.deleteMelody(track.id) }
                        .accessibilityIdentifier("mixer.track.delete")
                }
                // U30 end
            } label: { headingLabel(track: track, color: color) }
                .accessibilityIdentifier("mixer.track-menu.\(track.role.rawValue)")
                .disabled(session.performance.contextActive)
        } else {
            // I59: a look-ahead limiter keeps the master under −1 dBFS (live and export).
            Menu {
                Toggle("Limiter at −1 dBFS", isOn: Binding(get: { session.project.masterFX?.limiter == true }, set: { on in
                    session.edit { p in var fx = p.masterFX ?? MasterFX(); fx.limiter = on ? true : nil; p.masterFX = fx }
                }))
                // I33: the space the reverb sends go into.
                Picker("Reverb space", selection: Binding(get: { session.project.masterFX?.space?.rawValue ?? 0 }, set: { value in
                    session.edit { p in var fx = p.masterFX ?? MasterFX(); fx.space = ReverbSpace(rawValue: value); p.masterFX = fx }
                })) {
                    Text("Classic").tag(0)
                    ForEach(ReverbSpace.allCases, id: \.self) { space in Text(LocalizedStringKey(space.title)).tag(space.rawValue) }
                }
                Button("Prepare for release…", systemImage: "gauge.with.dots.needle.67percent") { session.presentEditor(.master) }
                // I58: a starting mix by role (one Undo).
                Button("Balance by role", systemImage: "slider.horizontal.3") { session.mixerImmediate { RoleBalance.apply(to: &$0) } }
            } label: { headingLabel(track: nil, color: color) }
                .accessibilityIdentifier("mixer.master-menu")
                .disabled(session.performance.contextActive)
        }
    }

    /// I5 · I56 · I57: per-part colour and dynamics, each one undoable edit.
    @ViewBuilder private func dynamicsMenu(_ track: Track) -> some View {
        let value = track.dynamics ?? TrackDynamics()
        if track.role == .drums {
            Toggle("Hats choke each other", isOn: Binding(get: { value.chokeGroups.contains([2, 3]) }, set: { on in
                setDynamics(track.id) { d in d.chokeGroups.removeAll { $0 == [2, 3] }; if on { d.chokeGroups.append([2, 3]) } }
            }))
            Toggle("Crash and ride choke each other", isOn: Binding(get: { value.chokeGroups.contains([9, 10]) }, set: { on in
                setDynamics(track.id) { d in d.chokeGroups.removeAll { $0 == [9, 10] }; if on { d.chokeGroups.append([9, 10]) } }
            }))
        } else {
            Picker("Duck under the kick", selection: Binding(get: { value.sidechainDB }, set: { db in setDynamics(track.id) { $0.sidechainDB = db } })) {
                Text("Off").tag(0.0)
                ForEach([3.0, 6.0, 9.0, 12.0], id: \.self) { db in Text(String(format: NSLocalizedString("%.0f dB", comment: "Sidechain depth"), db)).tag(db) }
            }
        }
        Picker("Reverb send", selection: Binding(get: { value.reverbSend }, set: { send in setDynamics(track.id) { $0.reverbSend = send } })) {
            Text("Off").tag(0.0); Text("Small").tag(0.15); Text("Medium").tag(0.3); Text("Large").tag(0.5)
        }
        if track.role != .drums {
            Button("Synth…", systemImage: "waveform.path") { synthTrack = SynthTarget(id: track.id) }
        }
        Picker("Drive", selection: Binding(get: { value.drive }, set: { amount in setDynamics(track.id) { $0.drive = amount } })) {
            Text("Off").tag(0.0); Text("Light").tag(0.3); Text("Heavy").tag(0.7)
        }
        Picker("Bit depth", selection: Binding(get: { value.crushBits }, set: { bits in setDynamics(track.id) { $0.crushBits = bits } })) {
            Text("Off").tag(0); Text("12-bit").tag(12); Text("8-bit").tag(8)
        }
    }

    private func setDynamics(_ id: UUID, _ change: @escaping (inout TrackDynamics) -> Void) {
        session.edit { p in
            guard let i = p.tracks.firstIndex(where: { $0.id == id }) else { return }
            var d = p.tracks[i].dynamics ?? TrackDynamics()
            change(&d)
            p.tracks[i].dynamics = d.isNeutral ? nil : d
        }
    }

    private func headingLabel(track: Track?, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: track.map { roleSymbol($0.role) } ?? "speaker.wave.2.fill")
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(track?.displayName ?? NSLocalizedString("Master", comment: "Master channel"))
                .font(.system(.caption, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { if let track, !session.performance.contextActive { renameText = track.displayName; renamingTrack = track.id } }
            if track?.locked == true {
                Image(systemName: "lock.fill").font(.system(.caption2, weight: .semibold)).foregroundStyle(Color.muted)
                    .accessibilityLabel("Locked")
            }
            if let track, let index = session.displayProject.tracks.firstIndex(where: { $0.id == track.id }) {
                SoundingDot(session: session, track: index, color: color)
            }
        }
        .overlay(alignment: .topLeading) {
            Capsule().fill(color).frame(width: 20, height: 2).offset(y: -5)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private func soundSlot(track: Track?, color: Color) -> some View {
        if let track {
            TrackSoundButton(session: session, trackID: track.id, compact: true)
        } else {
            VStack(spacing: 5) {
                Text("STEREO")
                    .font(.system(.caption2, design: .monospaced, weight: .medium))
                    .tracking(0.4)
                Text("OUT")
                    .font(.system(.caption, design: .monospaced, weight: .semibold))
                    .foregroundStyle(color)
            }
            .foregroundStyle(Color.muted)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Color.ink.opacity(0.7), in: RoundedRectangle(cornerRadius:Luz.Radius.cell,style:.continuous))
        }
    }

    private func eqButton(_ track:Track?)->some View {
        Button {
            finishGesture()
            equalizer=track.map{.track($0.id)} ?? .master
        } label:{
            Label("EQ",systemImage:"slider.horizontal.3")
                .font(.caption.weight(.semibold)).frame(maxWidth:.infinity,minHeight:44)
        }
        .buttonStyle(StudioQuietButtonStyle())
        .foregroundStyle(Color.mint)
        .disabled(session.performance.contextActive)
        .accessibilityLabel("Parametric EQ")
        .accessibilityValue(Text(track?.displayName ?? NSLocalizedString("Master",comment:"Mixer channel")))
        .accessibilityIdentifier("mixer.eq."+(track?.id.uuidString ?? "master"))
    }

    private func gainReadout(index: Int, gain: Double, color: Color, largeType: Bool = false) -> some View {
        Button {
            finishGesture()
            setGain(index, 0)
            finishGesture()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: gain <= -61 ? "−∞" : String(format: "%.1f", gain))
                    .font(largeType ? .headline.monospaced() : .system(.title3, design: .monospaced, weight: .medium))
                    .monospacedDigit()
                Text("dB")
                    .font(largeType ? .caption : .system(.caption2, design: .monospaced, weight: .medium))
                    .foregroundStyle(Color.muted)
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Color.ink, in: RoundedRectangle(cornerRadius:8,style:.continuous))
            .overlay {
                RoundedRectangle(cornerRadius:8,style:.continuous)
                    .stroke(Color.outline.opacity(contrast == .increased ? 1 : 0.65), lineWidth: 0.75)
            }
        }
        .buttonStyle(StudioQuietButtonStyle())
        .accessibilityLabel("\(gain, specifier: "%.1f") decibels. Tap to reset.")
        .accessibilityIdentifier("mixer.reset.\(index)")
    }

    private func fader(index: Int, track: Track?, gain: Double, color: Color) -> some View {
        MixerFaderFace(gain: gain, level: session.audio.meters[index], peak: session.audio.peakHolds[index], color: color,
                       active: activeFader == index, increasedContrast: contrast == .increased)
            .contentShape(Rectangle())
            .overlay {
                GeometryReader { geometry in
                    Color.clear.contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if activeFader != index {
                                    session.mixerGesture = false
                                    activeFader = index
                                    dragStartGain = gain
                                }
                                let travel = max(1, geometry.size.height - 32)
                                // Luz: relative drag; the cap never jumps to the finger.
                                var target = min(6, max(-61, (dragStartGain ?? gain) - Double(value.translation.height / travel) * 67))
                                // Luz detent: 0 dB catches the cap and ticks once.
                                if abs(target) < 0.75 { target = 0 }
                                if (target == 0) != (gain == 0) && target == 0 { Luz.Haptics.selection() }
                                setGain(index, target)
                            }
                            .onEnded { _ in dragStartGain = nil; finishGesture() })
                        .simultaneousGesture(TapGesture(count: 2).onEnded {
                            finishGesture(); setGain(index, 0); finishGesture(); Luz.Haptics.selection()
                        })
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(track?.displayName ?? NSLocalizedString("Master", comment: "Master channel"))
            .accessibilityValue("\(Int(gain)) dB")
            .accessibilityAdjustableAction { direction in
                finishGesture()
                setGain(index, min(6, max(-61, gain + (direction == .increment ? 1 : -1))))
                finishGesture()
            }
    }

    @ViewBuilder private func panSlot(index: Int, track: Track?, color: Color) -> some View {
        if let track {
            VStack(spacing: 0) {
                Text("Pan")
                    .font(.system(.caption2, weight: .medium))
                    .foregroundStyle(Color.muted)
                    .accessibilityHidden(true)
                // Luz: a bipolar knob with a centre detent and double-tap reset.
                LuzKnob(title: "Pan", value: panBinding(index), range: -1...1, defaultValue: 0, detents: [0], bipolar: true, tint: color,
                        format: { v in abs(v) < 0.01 ? "C" : v < 0 ? "L\(Int((-v * 50).rounded()))" : "R\(Int((v * 50).rounded()))" },
                        onEditingChanged: { _ in session.mixerGesture = false }, identifier: "mixer.pan.\(index)", size: 44, showsTitle: false)
            }
        } else {
            Text("L  ·  R")
                .font(.system(.caption2, design: .monospaced, weight: .medium))
                .foregroundStyle(Color.muted)
        }
    }

    private func channelSwitches(index: Int, track: Track, color: Color) -> some View {
        HStack(spacing: 6) {
            // Luz: mute reads as "off" (light on lifted), solo lights in the track colour.
            channelSwitch(title: "M", active: track.mute, color: .studioText) {
                session.mixerImmediate { $0.tracks[index].mute.toggle() }
            }
            .accessibilityLabel("Mute \(track.displayName)")
            .accessibilityIdentifier("mixer.mute.\(index)")
            .accessibilityValue(LocalizedStringKey(track.mute ? "On" : "Off"))
            channelSwitch(title: "S", active: track.solo, color: color) {
                session.mixerImmediate { $0.tracks[index].solo.toggle() }
            }
            .accessibilityLabel("Solo \(track.displayName)")
            .accessibilityIdentifier("mixer.solo.\(index)")
            .accessibilityValue(LocalizedStringKey(track.solo ? "On" : "Off"))
        }
    }

    private func channelSwitch(title: LocalizedStringKey, active: Bool, color: Color,
                               action: @escaping () -> Void) -> some View {
        Button { action(); Luz.Haptics.selection() } label: {
            // Luz lit toggle: a latching key that glows in the track colour when on.
            Text(title)
                .font(.system(.footnote, design: .monospaced, weight: .semibold))
                .foregroundStyle(active ? Color.ink : Color.muted)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(active ? color : Color.ink, in: RoundedRectangle(cornerRadius: Luz.Radius.cell, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Luz.Radius.cell, style: .continuous)
                        .stroke(active ? color : Color.outline.opacity(contrast == .increased ? 1 : 0.75), lineWidth: 1)
                }
                .shadow(color: color.opacity(active && contrast != .increased ? 0.5 : 0), radius: 6)
        }
        .buttonStyle(StudioQuietButtonStyle())
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private var outputState: some View {
        let clipped = session.audio.meters[masterBus] >= 0.98
        return HStack(spacing: 5) {
            Circle().fill(clipped ? Color.record : Color.mint).frame(width: 5, height: 5)
                .accessibilityHidden(true)
            Text(LocalizedStringKey(clipped ? "CLIP" : "OUT"))
                .font(.system(.caption2, design: .monospaced, weight: .semibold))
                .foregroundStyle(clipped ? Color.record : Color.muted)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(Color.ink, in: RoundedRectangle(cornerRadius:8,style:.continuous))
    }

    private var accessibleMixer: some View {
        Form {
            Button("Palettes") { session.endHarmonyPreview(); session.sheet = .palettes }
                .accessibilityIdentifier("mixer.palettes").disabled(session.performance.contextActive)
            ForEach(Array(session.displayProject.tracks.enumerated()), id: \.element.id) { index, track in
                SwiftUI.Section(track.displayName) {
                    TrackSoundButton(session: session, trackID: track.id)
                    if advanced { eqButton(track) }
                    gainReadout(index: index, gain: track.gain, color: .track(track.role), largeType: true)
                    Slider(value: gainBinding(index), in: -61...6, step: 1,
                           onEditingChanged: { _ in session.mixerGesture = false })
                        .accessibilityLabel("Gain \(track.displayName)")
                    Slider(value: panBinding(index), in: -1...1,
                           onEditingChanged: { _ in session.mixerGesture = false })
                        .accessibilityLabel("Pan \(track.displayName)")
                        .accessibilityIdentifier("mixer.pan.\(index)")
                    Toggle("Mute", isOn: Binding(get: { session.displayProject.tracks[index].mute },
                                                 set: { value in session.mixerImmediate { $0.tracks[index].mute = value } }))
                        .accessibilityLabel("Mute \(track.displayName)")
                        .accessibilityIdentifier("mixer.mute.\(index)")
                    Toggle("Solo", isOn: Binding(get: { session.displayProject.tracks[index].solo },
                                                 set: { value in session.mixerImmediate { $0.tracks[index].solo = value } }))
                        .accessibilityLabel("Solo \(track.displayName)")
                        .accessibilityIdentifier("mixer.solo.\(index)")
                }
                .listRowBackground(Color.panel)
            }
            SwiftUI.Section("Master") {
                if advanced { eqButton(nil) }
                gainReadout(index: masterBus, gain: session.displayProject.master, color: .mint, largeType: true)
                Slider(value: gainBinding(masterBus), in: -61...6, step: 1,
                       onEditingChanged: { _ in session.mixerGesture = false })
                    .accessibilityLabel("Master gain")
            }
            .listRowBackground(Color.panel)
        }
        .scrollContentBackground(.hidden)
        .background(Color.ink)
        .tint(.mint)
        .disabled(session.performance.replaying)
    }

    private func gainBinding(_ index: Int) -> Binding<Double> {
        Binding(get: { index == masterBus ? session.displayProject.master : session.displayProject.tracks[index].gain },
                set: { setGain(index, $0) })
    }

    private func panBinding(_ index: Int) -> Binding<Double> {
        Binding(get: { session.displayProject.tracks[index].pan },
                set: { value in session.mixerEdit { $0.tracks[index].pan = value }; session.captureAutomation(track: index, .pan, value: value) })
    }

    private func roleSymbol(_ role: TrackRole) -> String {
        switch role {
        case .harmony: return "pianokeys"
        case .drums: return "square.grid.2x2.fill"
        case .bass: return "waveform"
        case .melody: return "music.note"
        }
    }

    private func finishGesture() {
        activeFader = nil
        session.mixerGesture = false
    }

    private func setGain(_ index: Int, _ value: Double) {
        session.mixerEdit { project in
            if index == masterBus { project.master = value }
            else { project.tracks[index].gain = value }
        }
        if index < masterBus { session.captureAutomation(track: index, .level, value: max(-60, value)) }
    }
}

/// The ruler describes fader gain. The adjacent meter reads only the engine's output.
private struct MixerFaderFace: View {
    let gain: Double
    let level: Float
    var peak: Float = 0
    let color: Color
    let active: Bool
    let increasedContrast: Bool
    private let ticks: [Double] = [6, 0, -12, -24, -36, -48, -61]
    private static let segments = 24
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let travel = max(1, geometry.size.height - 32)
            let railX = max(55, geometry.size.width * 0.56)
            let capY = 16 + CGFloat((6 - min(6, max(-61, gain))) / 67) * travel
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius:4,style:.continuous)
                    .fill(Color.ink)
                    .frame(width: 8, height: travel + 8)
                    .overlay { RoundedRectangle(cornerRadius:4,style:.continuous).stroke(Color.outline.opacity(0.5), lineWidth: 0.75) }
                    .position(x: railX, y: geometry.size.height / 2)
                ForEach(ticks, id: \.self) { value in
                    rulerMark(value, y: 16 + CGFloat((6 - value) / 67) * travel)
                }
                engineMeter(height: travel)
                    .frame(width: 7, height: travel)
                    .position(x: geometry.size.width - 5, y: geometry.size.height / 2)
                faderCap.position(x: railX, y: capY)
            }
        }
    }

    private func rulerMark(_ value: Double, y: CGFloat) -> some View {
        HStack(spacing: 4) {
            Text(verbatim: value == -61 ? "−∞" : value > 0 ? "+\(Int(value))" : "\(Int(value))")
                .font(.system(size: 11, weight: value == 0 ? .semibold : .regular, design: .monospaced))
                .foregroundStyle(value == 0 ? Color.studioText : Color.muted)
                .frame(width: 23, alignment: .trailing)
            Rectangle().fill(value == 0 ? color : Color.muted.opacity(increasedContrast ? 1 : 0.65))
                .frame(width: value == 0 ? 9 : 5, height: 1)
        }
        .frame(height: 12)
        .offset(y: y - 6)
    }

    private var faderCap: some View {
        // Luz fader: a fat capsule cap with a lit centre line in the track colour.
        Capsule(style: .continuous)
            .fill(LinearGradient(colors: [Color.lifted, Color.raised], startPoint: .top, endPoint: .bottom))
            .frame(width: 40, height: 28)
            .overlay {
                Capsule().fill(color).frame(width: 26, height: active ? 3 : 2)
                    .shadow(color: color.opacity(active && !increasedContrast ? 0.8 : 0), radius: 4)
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(active ? color : Color.outline.opacity(increasedContrast ? 1 : 0.9), lineWidth: active || increasedContrast ? 1.5 : 0.75)
            }
            .overlay(alignment: .top) {
                if !increasedContrast { Capsule().fill(Color.studioText.opacity(0.18)).frame(width: 24, height: 1).padding(.top, 2) }
            }
            .shadow(color: .black.opacity(active ? 0.45 : 0.3), radius: active ? 6 : 3, y: active ? 4 : 2)
            .scaleEffect(active && !reduceMotion ? 1.06 : 1)
            .animation(reduceMotion ? nil : Luz.Motion.snap, value: active)
    }

    /// LED segments with a held peak; colours change at -12 and -3 dBFS.
    private func engineMeter(height: CGFloat) -> some View {
        let count = Self.segments
        let lit = Int((CGFloat(min(1, max(0, level))) * CGFloat(count)).rounded(.up))
        let held = min(count - 1, max(0, Int((CGFloat(min(1, max(0, peak))) * CGFloat(count)).rounded(.up)) - 1))
        return VStack(spacing: 1.5) {
            ForEach((0..<count).reversed(), id: \.self) { segment in
                let fraction = Double(segment + 1) / Double(count)
                let hue: Color = fraction > 0.92 ? .record : fraction > 0.75 ? .harmony : color
                RoundedRectangle(cornerRadius:1.5,style:.continuous)
                    .fill(segment < lit || (peak > 0.01 && segment == held) ? hue : Color.ink)
                    .opacity(segment < lit || (peak > 0.01 && segment == held) ? 1 : (increasedContrast ? 1 : 0.8))
            }
        }
        .frame(height: height)
        .padding(1.5)
        .background(Color.ink, in: Capsule())
        .overlay { Capsule().stroke(Color.outline.opacity(increasedContrast ? 1 : 0.65), lineWidth: 0.75) }
        .accessibilityHidden(true)
    }
}

/// I64: one undoable master EQ and lead balance for a listening situation.
private struct MixPresetMenu: View {
    @Bindable var session: Session
    var body: some View {
        Menu {
            ForEach(MixPreset.allCases, id: \.self) { preset in
                Button { session.edit { $0 = try preset.applied(to: $0) } } label: {
                    Text(LocalizedStringKey(preset.title))
                }
            }
        } label: {
            Image(systemName: "dial.medium").font(.system(.body, weight: .medium))
                .frame(width: 44, height: 44)
                .background(Color.raised.opacity(0.55), in: RoundedRectangle(cornerRadius: StudioMetrics.controlRadius, style: .continuous))
        }
        .accessibilityLabel("Mix presets").accessibilityIdentifier("mixer.mix-presets")
        .disabled(session.performance.contextActive)
    }
}

/// I63: a live master spectrum (30 Hz–16 kHz, 24 bands), drawn while audio plays.
struct MasterSpectrum: View {
    let audio: AudioController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 0.25 : 1.0 / 20, paused: !audio.playing)) { _ in
            let bands = audio.playing ? Spectrum.bands(audio.scope(2048), rate: audio.sampleRate) : [Float](repeating: -90, count: 24)
            Canvas { context, size in
                let width = size.width / CGFloat(bands.count)
                for (i, level) in bands.enumerated() {
                    let height = max(1, CGFloat((level + 72) / 72) * size.height)
                    let rect = CGRect(x: CGFloat(i) * width + 1, y: size.height - height, width: max(1, width - 2), height: height)
                    context.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(level > -6 ? Color.record : Color.mint.opacity(0.8)))
                }
            }
        }
        .frame(height: 44)
        .padding(.horizontal, 4)
        .background(Color.ink.opacity(0.7), in: RoundedRectangle(cornerRadius:Luz.Radius.cell,style:.continuous))
        .accessibilityElement()
        .accessibilityLabel("Master spectrum")
        .accessibilityIdentifier("mixer.spectrum")
    }
}

struct SynthTarget: Identifiable { let id: UUID }

/// I55: knobs for a melodic track's synth voice. Moving a knob is heard at
/// once; releasing it saves one undoable edit.
private struct SynthEditorView: View {
    @Bindable var session: Session
    let trackID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var patch = SynthPatch()
    private var index: Int? { session.project.tracks.firstIndex { $0.id == trackID } }
    private var track: Track? { index.map { session.project.tracks[$0] } }

    var body: some View {
        NavigationStack {
            Form {
                if let track {
                    Toggle("Use the synth", isOn: Binding(get: { track.synth != nil }, set: { on in commit(on ? patch : nil) }))
                        .accessibilityIdentifier("synth.enabled")
                    if track.instrumentSample != nil {
                        Text("This track plays an imported instrument. Choose a built-in sound to hear the synth.").font(.caption).foregroundStyle(Color.muted)
                    }
                    if track.synth != nil {
                        Section("Presets") {
                            ForEach(SynthPatch.presets, id: \.name) { preset in
                                Button(LocalizedStringKey(preset.name)) { patch = preset.patch; commit(patch) }.frame(minHeight: 44)
                            }
                        }
                        Section("Oscillator") {
                            Picker("Wave", selection: Binding(get: { patch.wave }, set: { patch.wave = $0; commit(patch) })) {
                                Text("Saw").tag(SynthPatch.Wave.saw); Text("Square").tag(SynthPatch.Wave.square); Text("Triangle").tag(SynthPatch.Wave.triangle)
                            }.pickerStyle(.segmented)
                        }
                        Section("Filter") {
                            HStack {
                                knob("Cutoff", \.cutoff, 0...1, default: 0.7, format: { String(format: "%.0f Hz", 80 * pow(200, $0)) })
                                knob("Resonance", \.resonance, 0...0.9, default: 0.2, format: { String(format: "%.0f%%", $0 / 0.9 * 100) })
                            }.frame(maxWidth: .infinity)
                        }
                        Section("Envelope") {
                            HStack {
                                knob("Attack", \.attack, 0.001...2, default: 0.01, format: seconds)
                                knob("Decay", \.decay, 0.01...3, default: 0.3, format: seconds)
                                knob("Sustain", \.sustain, 0...1, default: 0.7, format: { String(format: "%.0f%%", $0 * 100) })
                                knob("Release", \.release, 0.01...4, default: 0.3, format: seconds)
                            }.frame(maxWidth: .infinity)
                        }
                    }
                } else { Text("This track no longer exists.") }
            }
            .navigationTitle(track?.displayName ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .onAppear { if let synth = track?.synth { patch = synth } }
        .onDisappear { if let index { session.audio.previewSynth(track: index, session.project.tracks[index].synth) } }
    }

    private func seconds(_ value: Double) -> String { value < 1 ? String(format: "%.0f ms", value * 1000) : String(format: "%.2f s", value) }

    private func knob(_ title: LocalizedStringKey, _ key: WritableKeyPath<SynthPatch, Double>, _ range: ClosedRange<Double>, default initial: Double, format: @escaping (Double) -> String) -> some View {
        // Luz knob: heard while turning (preview), one Undo when released.
        LuzKnob(title: title, value: Binding(get: { patch[keyPath: key] }, set: { value in
            patch[keyPath: key] = value
            if let index { session.audio.previewSynth(track: index, patch) }
        }), range: range, defaultValue: initial, tint: Color.track(track?.role ?? .melody), format: format,
                onEditingChanged: { editing in if !editing { commit(patch) } })
            .frame(maxWidth: .infinity)
    }

    private func commit(_ value: SynthPatch?) {
        let id = trackID
        session.edit { p in if let i = p.tracks.firstIndex(where: { $0.id == id }) { p.tracks[i].synth = value } }
    }
}

/// U37 · Lights while the track has a note sounding at the playhead.
private struct SoundingDot: View {
    let session: Session
    let track: Int
    let color: Color
    var body: some View {
        let tick = Int(session.audio.tick)
        let lit = session.audio.playing && Self.sounding(session.audio.compiledNotes(session.displayProject), track: track, at: tick)
        Circle().fill(lit ? color : color.opacity(0.15)).frame(width: 7, height: 7)
            .transaction { $0.animation = nil }
            .accessibilityHidden(true)
    }

    /// Notes are sorted by start: find the last one that started, then look back one bar.
    static func sounding(_ notes: [CompiledNote], track: Int, at tick: Int) -> Bool {
        var low = 0, high = notes.count
        while low < high { let mid = (low + high) / 2; if notes[mid].tick <= tick { low = mid + 1 } else { high = mid } }
        var index = low - 1
        while index >= 0 && notes[index].tick > tick - barTicks {
            let note = notes[index]
            if note.track == track && tick < note.tick + max(90, note.duration) { return true }
            index -= 1
        }
        return false
    }
}
