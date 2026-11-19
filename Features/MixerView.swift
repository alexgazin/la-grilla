import SwiftUI
import MusicDomain

struct MixerView: View {
    @Bindable var session: Session
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var activeFader: Int?
    @State private var equalizer: EQDestination?

    var body: some View {
        Group {
            if dynamicType.isAccessibilitySize { accessibleMixer }
            else { standardMixer }
        }
        .sheet(item:$equalizer) { EqualizerView(session:session,destination:$0) }
        .onDisappear { finishGesture() }
        .onChange(of: session.performance.replaying) { _, replaying in
            if replaying { finishGesture() }
        }
    }

    private var standardMixer: some View {
        GeometryReader { geometry in
            // Keep useful fader travel even when the landscape workspace scrolls.
            let stripHeight = min(500, max(464, geometry.size.height - 88))
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    deskHeading
                    console(height: stripHeight)
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
                    .background(Color.raised.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }.buttonStyle(StudioQuietButtonStyle()).accessibilityIdentifier("mixer.palettes")
                .disabled(session.performance.contextActive)
            VStack(spacing: 5) {
                Image(systemName: "headphones")
                    .font(.system(size: 18, weight: .medium))
                Text("STEREO")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(0.8)
            }
            .foregroundStyle(Color.muted)
            .accessibilityHidden(true)
        }
    }

    private func console(height: CGFloat) -> some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(Array(session.displayProject.tracks.enumerated()), id: \.element.id) { index, track in
                        channel(index: index, track: track, height: height)
                            .frame(width: 120)
                            .overlay(alignment: .trailing) { consoleSeam }
                    }
                }
            }
            .scrollIndicators(.visible)
            channel(index: masterBus, track: nil, height: height)
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
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.mint)
                .padding(.top, 2)
                .accessibilityHidden(true)
            Text("A little space goes a long way.\nKeep the master below the red.")
                .font(.caption)
                .foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func channel(index: Int, track: Track?, height: CGFloat) -> some View {
        let color = track.map { Color.track($0.role) } ?? .mint
        let gain = track?.gain ?? session.displayProject.master
        return VStack(spacing: 0) {
            channelHeading(track: track, color: color)
                .frame(height: 34)
            soundSlot(track: track, color: color)
                .frame(height: 56)
            eqButton(track)
            gainReadout(index: index, gain: gain, color: color)
                .padding(.vertical, 4)
            fader(index: index, track: track, gain: gain, color: color)
                .padding(.vertical, 8)
            panSlot(index: index, track: track, color: color)
                .frame(height: 70)
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

    private func channelHeading(track: Track?, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: track.map { roleSymbol($0.role) } ?? "speaker.wave.2.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(track?.displayName ?? NSLocalizedString("Master", comment: "Master channel"))
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
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
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .tracking(0.4)
                Text("OUT")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(color)
            }
            .foregroundStyle(Color.muted)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Color.ink.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
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
                    .font(largeType ? .headline.monospaced() : .system(size: 20, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                Text("dB")
                    .font(largeType ? .caption : .system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.muted)
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Color.ink, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.outline.opacity(contrast == .increased ? 1 : 0.65), lineWidth: 0.75)
            }
        }
        .buttonStyle(StudioQuietButtonStyle())
        .accessibilityLabel("\(gain, specifier: "%.1f") decibels. Tap to reset.")
        .accessibilityIdentifier("mixer.reset.\(index)")
    }

    private func fader(index: Int, track: Track?, gain: Double, color: Color) -> some View {
        MixerFaderFace(gain: gain, level: session.audio.meters[index], color: color,
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
                                }
                                let travel = max(1, geometry.size.height - 32)
                                let position = min(1, max(0, (value.location.y - 16) / travel))
                                setGain(index, Double(1 - position) * 67 - 61)
                            }
                            .onEnded { _ in finishGesture() })
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
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.muted)
                    .accessibilityHidden(true)
                Slider(value: panBinding(index), in: -1...1,
                       onEditingChanged: { _ in session.mixerGesture = false })
                    .tint(color)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Pan \(track.displayName)")
                    .accessibilityIdentifier("mixer.pan.\(index)")
            }
        } else {
            Text("L  ·  R")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.muted)
        }
    }

    private func channelSwitches(index: Int, track: Track, color: Color) -> some View {
        HStack(spacing: 6) {
            channelSwitch(title: "M", active: track.mute, color: color) {
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
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(active ? Color.ink : Color.muted)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(active ? color : Color.ink, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(active ? color : Color.outline.opacity(contrast == .increased ? 1 : 0.75), lineWidth: 1)
                }
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
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(clipped ? Color.record : Color.muted)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(Color.ink, in: RoundedRectangle(cornerRadius: 8))
    }

    private var accessibleMixer: some View {
        Form {
            Button("Palettes") { session.endHarmonyPreview(); session.sheet = .palettes }
                .accessibilityIdentifier("mixer.palettes").disabled(session.performance.contextActive)
            ForEach(Array(session.displayProject.tracks.enumerated()), id: \.element.id) { index, track in
                SwiftUI.Section(track.displayName) {
                    TrackSoundButton(session: session, trackID: track.id)
                    eqButton(track)
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
                eqButton(nil)
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
                set: { value in session.mixerEdit { $0.tracks[index].pan = value } })
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
    }
}

/// The ruler describes fader gain. The adjacent meter reads only the engine's output.
private struct MixerFaderFace: View {
    let gain: Double
    let level: Float
    let color: Color
    let active: Bool
    let increasedContrast: Bool
    private let ticks: [Double] = [6, 0, -12, -24, -36, -48, -61]

    var body: some View {
        GeometryReader { geometry in
            let travel = max(1, geometry.size.height - 32)
            let railX = max(55, geometry.size.width * 0.56)
            let capY = 16 + CGFloat((6 - min(6, max(-61, gain))) / 67) * travel
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.ink)
                    .frame(width: 8, height: travel + 8)
                    .overlay { RoundedRectangle(cornerRadius: 4).stroke(Color.outline.opacity(0.5), lineWidth: 0.75) }
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
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(LinearGradient(colors: [Color.studioText, Color.studioText.opacity(0.72)],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: 38, height: 30)
            .overlay {
                VStack(spacing: 3) {
                    Rectangle().fill(Color.ink.opacity(0.3)).frame(width: 22, height: 1)
                    Rectangle().fill(Color.ink).frame(width: 28, height: 2)
                    Rectangle().fill(Color.ink.opacity(0.3)).frame(width: 22, height: 1)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(active ? color : Color.studioText.opacity(0.8), lineWidth: active ? 2 : 0.75)
            }
            .shadow(color: .black.opacity(0.35), radius: 3, y: 3)
    }

    private func engineMeter(height: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            Capsule().fill(Color.ink)
            LinearGradient(stops: [.init(color: .record, location: 0),
                                   .init(color: .harmony, location: 0.16),
                                   .init(color: color, location: 0.4),
                                   .init(color: color.opacity(0.75), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .mask(alignment: .bottom) {
                    Rectangle().frame(height: height * CGFloat(min(1, max(0, level))))
                }
        }
        .clipShape(Capsule())
        .overlay { Capsule().stroke(Color.outline.opacity(increasedContrast ? 1 : 0.65), lineWidth: 0.75) }
    }
}
