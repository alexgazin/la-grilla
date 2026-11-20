import SwiftUI

/// Luz motion layer: transitions and interface effects shared by every screen.
/// Rules (docs/DESIGN_SYSTEM_RU.md, "Переходы и эффекты"):
/// - motion explains where something came from or went; it never decorates a played instrument;
/// - every effect has a Reduce Motion form (a short cross-fade or nothing);
/// - nothing here reads the transport tick, so the 30 Hz playhead path stays untouched;
/// - effects are GPU-cheap: opacity, scale, offset, blur on small views only.
extension Luz {
    /// UI tests check behaviour, not motion: structural transitions are skipped so a
    /// snapshot never catches a half-faded duplicate of a control (like Reduce Motion).
    static let uiTesting = ProcessInfo.processInfo.arguments.contains("--uitesting")

    @MainActor enum Transition {
        /// Content that replaces content in place (tabs, steps, states): soft blur cross-fade.
        static func replace(_ reduceMotion: Bool) -> AnyTransition {
            Luz.uiTesting ? .identity : reduceMotion ? .opacity : AnyTransition(.blurReplace(.downUp))
        }
        /// Something new arriving from below (rows, notices, inline panels).
        static func rise(_ reduceMotion: Bool) -> AnyTransition {
            Luz.uiTesting ? .identity : reduceMotion ? .opacity : .asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: AnyTransition(.blurReplace)),
                removal: .opacity.combined(with: .scale(scale: 0.96)))
        }
        /// A banner from the top edge (toasts, notices).
        static func drop(_ reduceMotion: Bool) -> AnyTransition {
            Luz.uiTesting ? .identity : reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity).combined(with: AnyTransition(.blurReplace))
        }
        /// A small element that pops into place (badges, chips, errors).
        static func pop(_ reduceMotion: Bool) -> AnyTransition {
            Luz.uiTesting ? .identity : reduceMotion ? .opacity : .scale(scale: 0.86).combined(with: .opacity).combined(with: AnyTransition(.blurReplace))
        }
    }
}

// MARK: - Zoom presentation

/// iOS 18 zoom transitions: a sheet grows out of the control that opened it and
/// shrinks back into it. The source and destination share an id in one namespace.
struct LuzZoomSource<ID: Hashable>: ViewModifier {
    let id: ID
    let namespace: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || Luz.uiTesting }
    func body(content: Content) -> some View {
        if reduceMotion { content } else { content.matchedTransitionSource(id: id, in: namespace) }
    }
}

struct LuzZoomDestination<ID: Hashable>: ViewModifier {
    let id: ID
    let namespace: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || Luz.uiTesting }
    func body(content: Content) -> some View {
        if reduceMotion { content } else { content.navigationTransition(.zoom(sourceID: id, in: namespace)) }
    }
}

extension View {
    func luzZoomSource<ID: Hashable>(_ id: ID, in namespace: Namespace.ID) -> some View {
        modifier(LuzZoomSource(id: id, namespace: namespace))
    }
    func luzZoomDestination<ID: Hashable>(_ id: ID, in namespace: Namespace.ID) -> some View {
        modifier(LuzZoomDestination(id: id, namespace: namespace))
    }
}

// MARK: - Scroll effects

/// Cards ease in at the edges of a scroll view: slightly smaller and dimmer
/// until they reach the visible area. Axis-aware, Reduce Motion keeps them still.
struct LuzScrollDepth: ViewModifier {
    var axis: Axis = .vertical
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || Luz.uiTesting }
    func body(content: Content) -> some View {
        if reduceMotion { content } else {
            content.scrollTransition(.interactive, axis: axis) { view, phase in
                view.scaleEffect(phase.isIdentity ? 1 : 0.94)
                    .opacity(phase.isIdentity ? 1 : 0.55)
                    .blur(radius: phase.isIdentity ? 0 : 1.5)
            }
        }
    }
}

/// Artwork drifts a little against its card while scrolling (parallax).
struct LuzParallax: ViewModifier {
    var axis: Axis = .horizontal
    var amount: CGFloat = 18
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || Luz.uiTesting }
    func body(content: Content) -> some View {
        if reduceMotion { content } else {
            content.scrollTransition(.interactive, axis: axis) { view, phase in
                view.offset(x: axis == .horizontal ? phase.value * -amount : 0,
                            y: axis == .vertical ? phase.value * -amount : 0)
            }
        }
    }
}

extension View {
    func luzScrollDepth(_ axis: Axis = .vertical) -> some View { modifier(LuzScrollDepth(axis: axis)) }
    func luzParallax(_ axis: Axis = .horizontal, amount: CGFloat = 18) -> some View { modifier(LuzParallax(axis: axis, amount: amount)) }
}

// MARK: - Entrance

/// First appearance of a list item: rises 10 pt out of a light blur, staggered
/// by index (capped so long lists never wait). Runs once per view identity.
struct LuzEntrance: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || Luz.uiTesting }
    func body(content: Content) -> some View {
        content
            .opacity(shown || Luz.uiTesting ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 10)
            .blur(radius: shown || reduceMotion ? 0 : 4)
            .onAppear {
                guard !shown else { return }
                if reduceMotion { withAnimation(.easeOut(duration: 0.15)) { shown = true }; return }
                withAnimation(Luz.Motion.gentle.delay(Double(min(index, 8)) * 0.04)) { shown = true }
            }
    }
}

extension View {
    func luzEntrance(_ index: Int = 0) -> some View { modifier(LuzEntrance(index: index)) }
}

// MARK: - Feedback effects

/// A refusal shakes the element sideways (three damped swings) and plays the
/// error haptic. Trigger with any changing Equatable value, e.g. an error count.
struct LuzShake<Trigger: Equatable>: ViewModifier {
    let trigger: Trigger
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || Luz.uiTesting }
    func body(content: Content) -> some View {
        if reduceMotion { content } else {
            content.keyframeAnimator(initialValue: CGFloat(0), trigger: trigger) { view, x in
                view.offset(x: x)
            } keyframes: { _ in
                KeyframeTrack {
                    SpringKeyframe(-9, duration: 0.07)
                    SpringKeyframe(8, duration: 0.08)
                    SpringKeyframe(-5, duration: 0.08)
                    SpringKeyframe(3, duration: 0.08)
                    SpringKeyframe(0, duration: 0.12)
                }
            }
        }
    }
}

/// A confirmation: the element swells by 6% and settles (Apply, Save, Use).
struct LuzConfirm<Trigger: Equatable>: ViewModifier {
    let trigger: Trigger
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || Luz.uiTesting }
    func body(content: Content) -> some View {
        if reduceMotion { content } else {
            content.keyframeAnimator(initialValue: CGFloat(1), trigger: trigger) { view, scale in
                view.scaleEffect(scale)
            } keyframes: { _ in
                KeyframeTrack {
                    SpringKeyframe(1.06, duration: 0.12, spring: .snappy)
                    SpringKeyframe(1, duration: 0.3, spring: .bouncy)
                }
            }
        }
    }
}

/// A live state (recording, armed, listening) breathes: opacity 1 → 0.45 and back.
/// The phase animator stops entirely when inactive.
struct LuzBreathe: ViewModifier {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || Luz.uiTesting }
    func body(content: Content) -> some View {
        if active && !reduceMotion {
            content.phaseAnimator([1.0, 0.45]) { view, value in view.opacity(value) } animation: { _ in .easeInOut(duration: 0.7) }
        } else { content }
    }
}

extension View {
    func luzShake<T: Equatable>(_ trigger: T) -> some View { modifier(LuzShake(trigger: trigger)) }
    func luzConfirm<T: Equatable>(_ trigger: T) -> some View { modifier(LuzConfirm(trigger: trigger)) }
    func luzBreathe(_ active: Bool) -> some View { modifier(LuzBreathe(active: active)) }
    /// Numbers that change roll digit by digit instead of jumping.
    func luzNumeric(_ value: Double) -> some View { contentTransition(.numericText(value: value)) }
}

// MARK: - Ambient background

/// The start screens' living backdrop: a dark mesh in the four track colours
/// that drifts slowly. Static under Reduce Motion and Increase Contrast.
struct LuzAurora: View {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || Luz.uiTesting }
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if contrast == .increased {
            Color.ink
        } else if reduceMotion {
            mesh(time: 0)
        } else {
            TimelineView(.animation(minimumInterval: 1 / 20)) { context in
                mesh(time: context.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    private func mesh(time: Double) -> some View {
        let t = Float(time)
        func drift(_ x: Float, _ y: Float, _ phase: Float) -> SIMD2<Float> {
            SIMD2(x + 0.06 * sin(t * 0.21 + phase), y + 0.05 * cos(t * 0.17 + phase))
        }
        let dim = scheme == .dark ? 0.55 : 0.28
        let points: [SIMD2<Float>] = [
            SIMD2(0, 0), SIMD2(0.5, 0), SIMD2(1, 0),
            SIMD2(0, 0.5), drift(0.5, 0.5, 0), SIMD2(1, 0.5),
            SIMD2(0, 1), drift(0.5, 1, 1.7), SIMD2(1, 1)
        ]
        let colors: [Color] = [
            Color.ink, Color.harmony.opacity(dim * 0.6), Color.ink,
            Color.drums.opacity(dim * 0.7), Color.mint.opacity(dim * 0.45), Color.bass.opacity(dim * 0.6),
            Color.ink, Color.record.opacity(dim * 0.35), Color.ink
        ]
        return MeshGradient(width: 3, height: 3, points: points, colors: colors)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
