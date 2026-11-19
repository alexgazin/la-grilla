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

/// A button that is played like an instrument: the lit face is its press state.
struct LitButtonStyle: ButtonStyle {
    let color: Color
    var radius: CGFloat = Luz.Radius.cell
    var isOn = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.litInstrument(color, isDown: configuration.isPressed || isOn, radius: radius)
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
