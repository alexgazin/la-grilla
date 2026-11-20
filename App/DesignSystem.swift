import SwiftUI
import UIKit
import MusicDomain

/// Luz design system: motion, haptics, radii and the shared instrument and
/// empty-state components. Rules and sources: docs/DESIGN_SYSTEM_RU.md.
enum Luz {
    /// Springs in Apple's duration/bounce model.
    enum Motion {
        static let tap = Animation.spring(duration: 0.18, bounce: 0)
        static let release = Animation.spring(duration: 0.32, bounce: 0.25)
        static let snap = Animation.spring(duration: 0.30, bounce: 0.15)
        static let morph = Animation.spring(duration: 0.45, bounce: 0.12)
        static let gentle = Animation.spring(duration: 0.6, bounce: 0)
        /// Light on an instrument fades after release; contact itself is never animated.
        static let glowDecay = Animation.easeOut(duration: 0.22)
        static let drag = Animation.interactiveSpring(response: 0.25, dampingFraction: 0.86)
    }

    enum Radius {
        static let key: CGFloat = 6
        static let cell: CGFloat = 10
        static let pad: CGFloat = 14
        static let card: CGFloat = 14
        static let surface: CGFloat = 18
        static let sheet: CGFloat = 22
    }

    /// One haptic vocabulary for the whole app (generators are kept prepared).
    @MainActor enum Haptics {
        private static let selector = UISelectionFeedbackGenerator()
        private static let light = UIImpactFeedbackGenerator(style: .light)
        private static let medium = UIImpactFeedbackGenerator(style: .medium)
        private static let soft = UIImpactFeedbackGenerator(style: .soft)
        private static let notifier = UINotificationFeedbackGenerator()

        /// Detents, snapping, segment changes, 0 dB on a fader.
        static func selection() { selector.selectionChanged(); selector.prepare() }
        /// A played instrument; intensity follows velocity (1...127).
        static func hit(velocity: Int) { light.impactOccurred(intensity: CGFloat(min(127, max(1, velocity))) / 127); light.prepare() }
        static func transportStart() { medium.impactOccurred(); medium.prepare() }
        static func transportStop() { soft.impactOccurred(); soft.prepare() }
        static func success() { notifier.notificationOccurred(.success) }
        static func warning() { notifier.notificationOccurred(.warning) }
        static func error() { notifier.notificationOccurred(.error) }
    }
}

/// An instrument face: opaque, slightly raised; when played it sinks 3% and
/// lights from inside in its track colour. Contact is drawn in the same frame;
/// only the light's decay animates, and only after release.
struct LitInstrument: ViewModifier {
    let color: Color
    let isDown: Bool
    var radius: CGFloat = Luz.Radius.pad
    /// 0...1, e.g. the hit velocity; scales the light.
    var intensity: Double = 1
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let high = contrast == .increased
        content
            .background {
                // Halo outside the face: a precomputed gradient, never a blur (real-time rule).
                if !high {
                    RoundedRectangle(cornerRadius: radius + 8, style: .continuous)
                        .fill(RadialGradient(colors: [color.opacity(0.45 * intensity), color.opacity(0)], center: .center, startRadius: 0, endRadius: 90))
                        .padding(-8)
                        .opacity(isDown ? 1 : 0)
                        .animation(isDown || reduceMotion ? nil : Luz.Motion.glowDecay, value: isDown)
                        .allowsHitTesting(false)
                }
            }
            .background {
                ZStack {
                    shape.fill(LinearGradient(colors: [Color.raised, Color.panel], startPoint: .top, endPoint: .bottom))
                    // The lit layer: solid track colour plus a centred bloom.
                    shape.fill(color).opacity(isDown ? (high ? 1 : 0.55 + 0.45 * intensity) : 0)
                    shape.fill(RadialGradient(colors: [Color.white.opacity(high ? 0 : 0.35 * intensity), .clear], center: .center, startRadius: 0, endRadius: 80))
                        .opacity(isDown ? 1 : 0)
                }
                .animation(isDown || reduceMotion ? nil : Luz.Motion.glowDecay, value: isDown)
            }
            .overlay {
                shape.strokeBorder(isDown ? color : Color.outline.opacity(high ? 1 : 0.8), lineWidth: isDown || high ? 1.5 : 0.75)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .top) {
                // The light edge that makes a surface read as raised.
                if !high {
                    Capsule().fill(Color.studioText.opacity(isDown ? 0.28 : 0.10)).frame(height: 1)
                        .padding(.horizontal, radius * 0.8).padding(.top, 1).allowsHitTesting(false)
                }
            }
            .scaleEffect(isDown && !reduceMotion ? 0.97 : 1)
            .transaction { if isDown { $0.animation = nil } }
    }
}

extension View {
    func litInstrument(_ color: Color, isDown: Bool, radius: CGFloat = Luz.Radius.pad, intensity: Double = 1) -> some View {
        modifier(LitInstrument(color: color, isDown: isDown, radius: radius, intensity: intensity))
    }
}

/// One symbol, one line, one action, over a quiet mesh of the accent colours.
struct LuzEmptyState: View {
    let symbol: String
    let title: LocalizedStringKey
    var detail: LocalizedStringKey? = nil
    var action: (title: LocalizedStringKey, run: () -> Void)? = nil
    var secondary: (title: LocalizedStringKey, run: () -> Void)? = nil
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var scheme
    @ScaledMetric(relativeTo: .largeTitle) private var symbolSize: CGFloat = 40

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: symbolSize, weight: .medium))
                .foregroundStyle(Color.mint)
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)
            Text(title).font(StudioTypography.title.width(.expanded)).multilineTextAlignment(.center)
            if let detail { Text(detail).font(.callout).foregroundStyle(Color.muted).multilineTextAlignment(.center) }
            if let action { Button(action.title, action: action.run).buttonStyle(StudioActionStyle()).frame(maxWidth: 280) }
            if let secondary { Button(secondary.title, action: secondary.run).buttonStyle(StudioActionStyle(prominent: false)).frame(maxWidth: 280) }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background {
            if !reduceTransparency {
                MeshGradient(width: 2, height: 2, points: [[0, 0], [1, 0], [0, 1], [1, 1]],
                             colors: [.mint, .drums, .harmony, .bass])
                    .opacity(scheme == .dark ? 0.20 : 0.12)
                    .clipShape(RoundedRectangle(cornerRadius: Luz.Radius.surface, style: .continuous))
                    .accessibilityHidden(true)
            }
        }
    }
}

/// Circular transport key: sinks on press, glows (gradient, no blur) while on.
struct TransportKeyStyle: ButtonStyle {
    var color: Color = .mint
    var isOn = false
    var diameter: CGFloat = 58
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .foregroundStyle(Color.ink)
            .frame(width: diameter, height: diameter)
            .background(color, in: Circle())
            .overlay { Circle().strokeBorder(Color.studioText.opacity(contrast == .increased ? 0.6 : 0.15), lineWidth: 1) }
            .background {
                if contrast != .increased {
                    Circle().fill(RadialGradient(colors: [color.opacity(0.5), color.opacity(0)], center: .center, startRadius: diameter * 0.3, endRadius: diameter * 0.85))
                        .padding(-diameter * 0.3).opacity(isOn ? 1 : 0).allowsHitTesting(false)
                }
            }
            .scaleEffect(pressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : pressed ? Luz.Motion.tap : Luz.Motion.release, value: pressed)
            .animation(reduceMotion ? nil : Luz.Motion.snap, value: isOn)
    }
}

/// System forms on the Luz ink background with mint tint and 52 pt rows.
struct LuzForm: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(Color.ink)
            .tint(.mint)
            .environment(\.defaultMinListRowHeight, 52)
    }
}

extension View {
    func luzForm() -> some View { modifier(LuzForm()) }
}

/// Highlights a song range while the playhead is inside it. Only this small view
/// observes the 30 Hz transport tick, so large screens do not re-render with it.
struct PlayingHighlight: View {
    let audio: AudioController
    let range: Range<Int>
    let color: Color
    var radius: CGFloat = Luz.Radius.cell
    var fill = true
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        let on = audio.playing && range.contains(Int(audio.tick))
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            if fill && contrast != .increased { shape.fill(color.opacity(0.14)) }
            shape.strokeBorder(color, lineWidth: 1.5)
        }
        .opacity(on ? 1 : 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The grid playhead line and marker, isolated from the grid body.
struct GridPlayhead: View {
    let audio: AudioController
    let barWidth: CGFloat
    let height: CGFloat
    var body: some View {
        let x = CGFloat(audio.tick) / CGFloat(barTicks) * barWidth
        ZStack(alignment: .topLeading) {
            Rectangle().fill(Color.mint).frame(width: 2, height: height).offset(x: x, y: 28)
            Image(systemName: "triangle.fill").font(StudioTypography.index).rotationEffect(.degrees(180)).foregroundStyle(Color.mint).offset(x: x - 4, y: 18)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Shared Luz components

/// A rotary control: vertical drag (100 pt = full range), detents with a tick,
/// double-tap to reset, adjustable with VoiceOver. Bipolar knobs fill from the centre.
struct LuzKnob: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    var defaultValue: Double
    var detents: [Double] = []
    var bipolar = false
    var tint: Color = .mint
    var step: Double? = nil
    let format: (Double) -> String
    var onEditingChanged: (Bool) -> Void = { _ in }
    var identifier: String = ""
    var size: CGFloat = 56
    var showsTitle = true
    @State private var origin: Double?
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorSchemeContrast) private var contrast

    private var unit: Double { (value - range.lowerBound) / max(1e-9, range.upperBound - range.lowerBound) }

    var body: some View {
        VStack(spacing: showsTitle ? 6 : 2) {
            Canvas { context, canvas in
                let side = min(canvas.width, canvas.height)
                let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
                let radius = side * 0.42
                func arc(_ from: Double, _ to: Double) -> Path {
                    var path = Path()
                    path.addArc(center: center, radius: radius, startAngle: .degrees(from), endAngle: .degrees(to), clockwise: false)
                    return path
                }
                // 270° sweep from 135° to 405°.
                context.stroke(arc(135, 405), with: .color(.lifted), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                let start = bipolar ? 270.0 : 135.0, end = 135 + 270 * unit
                if abs(end - start) > 0.5 { context.stroke(arc(min(start, end), max(start, end)), with: .color(tint), style: StrokeStyle(lineWidth: 4, lineCap: .round)) }
                let disc = CGRect(x: center.x - radius * 0.72, y: center.y - radius * 0.72, width: radius * 1.44, height: radius * 1.44)
                context.fill(Path(ellipseIn: disc), with: .linearGradient(Gradient(colors: [.lifted, .raised]), startPoint: CGPoint(x: disc.midX, y: disc.minY), endPoint: CGPoint(x: disc.midX, y: disc.maxY)))
                context.stroke(Path(ellipseIn: disc), with: .color(.outline.opacity(contrast == .increased ? 1 : 0.8)), lineWidth: contrast == .increased ? 1.5 : 0.75)
                let angle = (135 + 270 * unit) * Double.pi / 180
                let dx = CGFloat(cos(angle)), dy = CGFloat(sin(angle))
                var pointer = Path()
                pointer.move(to: CGPoint(x: center.x + dx * radius * 0.35, y: center.y + dy * radius * 0.35))
                pointer.addLine(to: CGPoint(x: center.x + dx * radius * 0.65, y: center.y + dy * radius * 0.65))
                context.stroke(pointer, with: .color(tint), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
            .frame(width: size, height: size)
            .contentShape(Rectangle().inset(by: min(0, (size - 44) / 2)))
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    guard enabled else { return }
                    if origin == nil { origin = value; onEditingChanged(true) }
                    let span = range.upperBound - range.lowerBound
                    var next = min(range.upperBound, max(range.lowerBound, (origin ?? value) - Double(drag.translation.height) / 100 * span))
                    if let step { next = (next / step).rounded() * step }
                    if let detent = detents.first(where: { abs($0 - next) < span * 0.02 }) {
                        if value != detent { Luz.Haptics.selection() }
                        next = detent
                    }
                    if next != value { value = next }
                }
                .onEnded { _ in origin = nil; onEditingChanged(false) })
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                guard enabled else { return }
                value = defaultValue; Luz.Haptics.selection(); onEditingChanged(false)
            })
            if showsTitle { Text(title).font(StudioTypography.detail).foregroundStyle(Color.muted).lineLimit(1) }
            Text(verbatim: format(value)).font(StudioTypography.index).foregroundStyle(Color.studioText).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(minWidth: 64)
        .opacity(enabled ? 1 : 0.42)
        // Assistive technologies and UI tests see a standard slider.
        .accessibilityRepresentation {
            Slider(value: $value, in: range) { Text(title) } onEditingChanged: { onEditingChanged($0) }
                .accessibilityValue(Text(verbatim: format(value)))
                .accessibilityIdentifier(identifier)
        }
    }
}

/// A selectable card: panel fill, a mint stroke that fades in, a checkmark that
/// morphs, and a tick on selection.
struct SelectableTile<Accessory: View>: View {
    let isSelected: Bool
    var tint: Color = .mint
    var symbol: String? = nil
    let title: LocalizedStringKey
    var detail: LocalizedStringKey? = nil
    var busy = false
    let action: () -> Void
    @ViewBuilder var accessory: () -> Accessory
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button { if !isSelected { Luz.Haptics.selection() }; action() } label: {
            HStack(alignment: .top, spacing: 12) {
                if let symbol {
                    Image(systemName: symbol).font(StudioTypography.icon).foregroundStyle(tint).frame(width: 28).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(StudioTypography.action).foregroundStyle(Color.studioText).multilineTextAlignment(.leading)
                    if let detail { Text(detail).font(.caption).foregroundStyle(Color.muted).multilineTextAlignment(.leading) }
                    accessory()
                }
                Spacer(minLength: 0)
                if busy { ProgressView().controlSize(.small) }
                else {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? tint : Color.outline)
                        .contentTransition(.symbolEffect(.replace))
                        .accessibilityHidden(true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(Color.panel, in: RoundedRectangle(cornerRadius: Luz.Radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Luz.Radius.card, style: .continuous)
                    .strokeBorder(isSelected ? tint : Color.outline.opacity(contrast == .increased ? 1 : 0.7), lineWidth: isSelected || contrast == .increased ? 1.5 : 0.75)
            }
            .animation(reduceMotion ? nil : Luz.Motion.snap, value: isSelected)
        }
        .buttonStyle(StudioQuietButtonStyle(radius: Luz.Radius.card))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension SelectableTile where Accessory == EmptyView {
    init(isSelected: Bool, tint: Color = .mint, symbol: String? = nil, title: LocalizedStringKey, detail: LocalizedStringKey? = nil, busy: Bool = false, action: @escaping () -> Void) {
        self.init(isSelected: isSelected, tint: tint, symbol: symbol, title: title, detail: detail, busy: busy, action: action, accessory: { EmptyView() })
    }
}

/// Banners, statuses and cautions. Only danger and recording use coral; a caution
/// is studio text with a triangle, so amber keeps meaning harmony.
struct LuzNotice: View {
    enum Kind { case info, caution, danger, recording }
    let kind: Kind
    var symbol: String? = nil
    let text: LocalizedStringKey
    var actions: [(title: LocalizedStringKey, run: () -> Void)] = []

    private var accent: Color { kind == .danger || kind == .recording ? .record : kind == .info ? .mint : .studioText }
    private var defaultSymbol: String {
        switch kind { case .info: "info.circle"; case .caution: "exclamationmark.triangle"; case .danger: "xmark.octagon"; case .recording: "record.circle.fill" }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol ?? defaultSymbol).foregroundStyle(accent).accessibilityHidden(true)
            Text(text).font(.callout).foregroundStyle(Color.studioText).frame(maxWidth: .infinity, alignment: .leading)
            ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                Button(action.title, action: action.run).font(StudioTypography.action).foregroundStyle(Color.mint)
                    .frame(minHeight: 44).buttonStyle(StudioQuietButtonStyle())
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.panel, in: RoundedRectangle(cornerRadius: Luz.Radius.card, style: .continuous))
        .overlay(alignment: .leading) { Capsule().fill(accent).frame(width: 3).padding(.vertical, 8) }
        .overlay { RoundedRectangle(cornerRadius: Luz.Radius.card, style: .continuous).strokeBorder(Color.outline.opacity(0.7), lineWidth: 0.75) }
        .accessibilityElement(children: .combine)
    }
}

/// The utility capsule used for menus and small options.
struct StudioPill: View {
    var symbol: String? = nil
    let title: LocalizedStringKey
    var value: String? = nil
    var tint: Color = .mint
    var isOn = false
    var chevron = false

    var body: some View {
        HStack(spacing: 6) {
            if let symbol { Image(systemName: symbol).foregroundStyle(isOn ? Color.ink : tint).accessibilityHidden(true) }
            Text(title)
            if let value { Text(verbatim: value).monospacedDigit().foregroundStyle(isOn ? Color.ink.opacity(0.75) : Color.muted) }
            if chevron { Image(systemName: "chevron.down").font(StudioTypography.index).accessibilityHidden(true) }
        }
        .font(StudioTypography.label)
        .foregroundStyle(isOn ? Color.ink : Color.studioText)
        .padding(.horizontal, 12)
        .frame(minHeight: StudioMetrics.hitTarget)
        .background(isOn ? tint : Color.raised, in: Capsule(style: .continuous))
        .overlay { Capsule(style: .continuous).strokeBorder(isOn ? tint : Color.outline.opacity(0.8), lineWidth: 0.75) }
        .contentShape(Capsule())
    }
}

/// A/B audition: two sides, the playing side shows a live speaker, a stop button.
struct ABCompare: View {
    enum Side { case a, b }
    let playing: Side?
    var a: LocalizedStringKey = "A · Current"
    let b: LocalizedStringKey
    let audition: (Side) -> Void
    let stop: () -> Void
    var identifiers: (a: String, b: String, stop: String) = ("ab.a", "ab.b", "ab.stop")

    var body: some View {
        HStack(spacing: 8) {
            side(.a, a, identifiers.a)
            side(.b, b, identifiers.b)
            if playing != nil {
                Button { stop(); Luz.Haptics.selection() } label: { Image(systemName: "stop.fill").frame(width: 48, height: 48) }
                    .buttonStyle(StudioQuietButtonStyle(radius: Luz.Radius.cell))
                    .accessibilityLabel("Stop preview").accessibilityIdentifier(identifiers.stop)
            }
        }
    }

    private func side(_ which: Side, _ title: LocalizedStringKey, _ id: String) -> some View {
        let on = playing == which
        return Button { audition(which); Luz.Haptics.selection() } label: {
            HStack(spacing: 6) {
                if on { Image(systemName: "speaker.wave.2.fill").symbolEffect(.variableColor.iterative, isActive: on).accessibilityHidden(true) }
                Text(title)
            }
            .font(StudioTypography.action)
            .foregroundStyle(on ? Color.ink : Color.studioText)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(on ? Color.mint : Color.raised, in: RoundedRectangle(cornerRadius: Luz.Radius.cell, style: .continuous))
        }
        .buttonStyle(StudioQuietButtonStyle(radius: Luz.Radius.cell))
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier(id)
    }
}
