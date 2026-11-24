import SwiftUI
import MusicDomain
import UIKit

// Luz: light on graphite. Matte content, glass chrome, instruments that light up
// in their track colour. Rules: docs/DESIGN_SYSTEM_RU.md.
extension Color {
    private static func adaptive(
        _ dark: UInt32,
        _ light: UInt32,
        contrastDark: UInt32? = nil,
        contrastLight: UInt32? = nil
    ) -> Color {
        Color(uiColor: UIColor { trait in
            let high = trait.accessibilityContrast == .high
            let hex = trait.userInterfaceStyle == .dark
                ? (high ? contrastDark ?? dark : dark)
                : (high ? contrastLight ?? light : light)
            return UIColor(
                red: CGFloat((hex >> 16) & 255) / 255,
                green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255,
                alpha: 1
            )
        })
    }

    static let ink = adaptive(0x0E0F12, 0xF5F4F0, contrastDark: 0x050609, contrastLight: 0xFFFFFF)
    static let panel = adaptive(0x16181D, 0xFFFFFF, contrastDark: 0x10141A, contrastLight: 0xFFFFFF)
    static let raised = adaptive(0x1E2127, 0xECEAE4, contrastDark: 0x1D2631, contrastLight: 0xE4EBF2)
    /// Third elevation: pressed controls and the selected segment.
    static let lifted = adaptive(0x272B33, 0xE2DFD7, contrastDark: 0x2A3442, contrastLight: 0xD5DCE4)
    static let studioText = adaptive(0xF3F5F0, 0x19232E, contrastDark: 0xFFFFFF, contrastLight: 0x09111C)
    static let muted = adaptive(0xA8B2BE, 0x536171, contrastDark: 0xCFD8E3, contrastLight: 0x354455)
    static let outline = adaptive(0x343E4C, 0xCDD6E1, contrastDark: 0x8797AB, contrastLight: 0x66788C)

    static let mint = adaptive(0xD8F780, 0x405900, contrastDark: 0xE0FF86, contrastLight: 0x304800)
    static let drums = adaptive(0xB7BCEF, 0x4B4E99, contrastDark: 0xCCD1FF, contrastLight: 0x343878)
    static let harmony = adaptive(0xE5BE69, 0x795000, contrastDark: 0xF7D58B, contrastLight: 0x624000)
    static let bass = adaptive(0x85D6C3, 0x00675A, contrastDark: 0x9FE8D7, contrastLight: 0x005044)
    static let record = adaptive(0xFF858D, 0xAA2D3D, contrastDark: 0xFFA9AF, contrastLight: 0x8F1C2C)
    // Physical piano keys retain their familiar polarity in either app appearance.
    static let keyboardIvory = adaptive(0xF2F0E7, 0xF2F0E7, contrastDark: 0xFFFFFF, contrastLight: 0xFFFFFF)
    static let keyboardGraphite = adaptive(0x171C23, 0x171C23, contrastDark: 0x050609, contrastLight: 0x050609)

    static func track(_ role: TrackRole) -> Color {
        role == .harmony ? .harmony : role == .drums ? .drums : role == .bass ? .bass : .mint
    }
    /// U47: the five track colours a person can choose (all meet the Luz contrast tokens).
    static let trackPalette: [Color] = [.harmony, .drums, .bass, .mint, .record]
    /// U31: clip colours (ClipEditing.clipColorCount of them).
    static let clipPalette: [Color] = [.harmony, .drums, .bass, .mint, .record, .yellow]
    static func track(_ track: Track) -> Color {
        track.color.flatMap { trackPalette.indices.contains($0) ? trackPalette[$0] : nil } ?? Color.track(track.role)
    }
}

enum StudioMetrics {
    static let micro: CGFloat = 4
    static let tight: CGFloat = 8
    static let compact: CGFloat = 12
    static let standard: CGFloat = 16
    static let section: CGFloat = 24
    static let generous: CGFloat = 32
    static let hitTarget: CGFloat = 44
    static let actionHeight: CGFloat = 48
    static let controlRadius: CGFloat = 12
    static let surfaceRadius: CGFloat = 18
    static let navigationRadius: CGFloat = 22
}

enum StudioTypography {
    /// Screen titles and empty states: wide SF Pro.
    static let display = Font.system(.largeTitle, design: .default, weight: .semibold).width(.expanded)
    static let title = Font.system(.title2, design: .default, weight: .semibold)
    static let action = Font.system(.subheadline, design: .default, weight: .semibold)
    static let label = Font.system(.caption, design: .default, weight: .semibold)
    static let detail = Font.system(.caption2, design: .default, weight: .medium)
    static let icon = Font.system(.body, design: .default, weight: .medium)
    static let value = Font.system(.body, design: .monospaced, weight: .medium)
    /// Pad names and big friendly numbers.
    static let pad = Font.system(.caption, design: .rounded, weight: .semibold)
    /// Transport position, gain and other large numeric readouts.
    static let readout = Font.system(.title2, design: .monospaced, weight: .medium)
    static let index = Font.system(.caption2, design: .monospaced, weight: .medium)
}

enum StudioMotion {
    // Contact is immediate. Only release settles; repeated musical input never waits.
    static let release = Luz.Motion.release
    static let selection = Luz.Motion.snap
    static let panel = Luz.Motion.morph
}

struct IconButton: View {
    let symbol: String
    let label: LocalizedStringKey
    var color: Color = .primary
    /// Luz toggle: when set, on = mint glyph on a 12 % mint circle, plus an accessibility value.
    var isOn: Bool? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(StudioTypography.icon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isOn == true ? Color.mint : color)
                .contentTransition(.symbolEffect(.replace))
                .frame(minWidth: StudioMetrics.hitTarget, minHeight: StudioMetrics.hitTarget)
                .background { if isOn == true { Circle().fill(Color.mint.opacity(0.12)) } }
                .contentShape(Rectangle())
        }
        .buttonStyle(StudioQuietButtonStyle(radius: StudioMetrics.hitTarget / 2))
        .accessibilityLabel(label)
        .modifier(ToggleAccessibilityValue(isOn: isOn))
    }
}

/// Adds On/Off only to toggles, so callers' own accessibility values stay untouched.
private struct ToggleAccessibilityValue: ViewModifier {
    let isOn: Bool?
    @ViewBuilder func body(content: Content) -> some View {
        if let isOn { content.accessibilityValue(Text(LocalizedStringKey(isOn ? "On" : "Off"))) } else { content }
    }
}

struct CapsuleLabel: View {
    @Environment(\.colorSchemeContrast) private var contrast
    let text: String
    var color: Color = .muted

    var body: some View {
        Text(LocalizedStringKey(text))
            .font(StudioTypography.detail)
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(contrast == .increased ? 0.15 : 0.08), in: Capsule())
            .overlay {
                Capsule().strokeBorder(color.opacity(contrast == .increased ? 0.75 : 0.22), lineWidth: 0.75)
                    .allowsHitTesting(false)
            }
    }
}

struct SmallHeading: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(StudioTypography.detail.weight(.semibold))
            .tracking(0.55)
            .foregroundStyle(Color.muted)
    }
}

struct ScrollableForLargeType: ViewModifier {
    @Environment(\.dynamicTypeSize) private var size

    @ViewBuilder func body(content: Content) -> some View {
        if size.isAccessibilitySize {
            ScrollView(.vertical) { content }
        } else {
            content
        }
    }
}

struct StudioQATypeSize: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if ProcessInfo.processInfo.arguments.contains("--large-type") {
            content.dynamicTypeSize(.accessibility3)
        } else {
            content
        }
    }
}

// Solid editing surfaces: a fine seam and a restrained light edge, never glass on glass.
struct StudioSurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var color: Color = .panel

    init(color: Color = .panel) { self.color = color }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: StudioMetrics.surfaceRadius, style: .continuous)
    }

    func body(content: Content) -> some View {
        content
            .background(color, in: shape)
            .overlay {
                shape.strokeBorder(Color.outline, lineWidth: contrast == .increased ? 1.25 : 0.75)
                    .allowsHitTesting(false)
            }
            .overlay {
                if contrast != .increased && !reduceTransparency {
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [Color.studioText.opacity(0.055), .clear, .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.75
                    )
                    .allowsHitTesting(false)
                }
            }
            .shadow(
                color: .black.opacity(contrast == .increased ? 0 : scheme == .dark ? 0.12 : 0.035),
                radius: 6,
                x: 0,
                y: 3
            )
    }
}

struct StudioActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var color: Color = .mint
    var prominent = true

    init(color: Color = .mint, prominent: Bool = true) {
        self.color = color
        self.prominent = prominent
    }

    func makeBody(configuration: Configuration) -> some View {
        let pressed = enabled && configuration.isPressed
        let shape = Capsule(style: .continuous)
        return configuration.label
            .font(StudioTypography.action)
            .foregroundStyle(prominent ? Color.ink : color)
            .frame(maxWidth: .infinity, minHeight: StudioMetrics.actionHeight)
            .padding(.horizontal, StudioMetrics.compact)
            .background {
                shape.fill(prominent ? color : Color.raised)
                    .overlay { shape.fill(Color.black.opacity(pressed ? 0.08 : 0)) }
            }
            .overlay {
                shape.strokeBorder(
                    focused ? Color.studioText : prominent ? Color.ink.opacity(0.12) : Color.outline,
                    lineWidth: focused || contrast == .increased ? 1.5 : 0.75
                )
                .allowsHitTesting(false)
            }
            .opacity(enabled ? 1 : contrast == .increased ? 0.6 : 0.42)
            .scaleEffect(pressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : pressed ? Luz.Motion.tap : Luz.Motion.release, value: pressed)
    }
}

struct StudioMark: View {
    var body: some View {
        Canvas { context, _ in
            let rows: [(CGFloat, CGFloat, CGFloat, Color)] = [
                (4, 1, 9, .studioText), (4, 16, 14, .drums),
                (13, 1, 6, .harmony), (13, 16, 9, .studioText),
                (22, 1, 9, .studioText), (22, 19, 11, .bass)
            ]
            for (y, x, width, color) in rows {
                context.fill(
                    Path(roundedRect: CGRect(x: x, y: y, width: width, height: 4), cornerRadius: 1.5),
                    with: .color(color)
                )
            }
            context.fill(
                Path(roundedRect: CGRect(x: 11, y: 0, width: 3, height: 30), cornerRadius: 1.5),
                with: .color(.mint)
            )
        }
        .frame(width: 30, height: 30)
        .accessibilityHidden(true)
    }
}

struct StudioSegments<Value: Equatable>: View {
    let title: LocalizedStringKey
    @Binding var selection: Value
    let options: [(Value, LocalizedStringKey)]
    /// Optional UI-test prefix: segment N gets "<identifier>.<N>".
    var identifier: String? = nil
    @Namespace private var puck
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: StudioMetrics.micro) {
            ForEach(options.indices, id: \.self) { index in
                segment(at: index)
            }
        }
        .padding(StudioMetrics.micro)
        .background(Color.ink, in: RoundedRectangle(cornerRadius: Luz.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Luz.Radius.card, style: .continuous)
                .strokeBorder(Color.outline, lineWidth: 0.75)
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private func segment(at index: Int) -> some View {
        let selected = selection == options[index].0
        return Button {
            guard selection != options[index].0 else { return }
            withAnimation(reduceMotion ? nil : Luz.Motion.snap) { selection = options[index].0 }
            Luz.Haptics.selection()
        } label: {
            Text(options[index].1)
                .font(StudioTypography.label)
                .lineLimit(2)
                .minimumScaleFactor(1)
                .frame(maxWidth: .infinity, minHeight: StudioMetrics.hitTarget)
                .foregroundStyle(selected ? Color.ink : Color.muted)
                .background {
                    // The selected puck slides between segments.
                    if selected {
                        RoundedRectangle(cornerRadius: Luz.Radius.cell, style: .continuous).fill(Color.mint)
                            .matchedGeometryEffect(id: "puck", in: puck)
                    }
                }
        }
        .buttonStyle(StudioQuietButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier.map { "\($0).\(index)" } ?? "")
    }
}

struct StudioQuietButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @Environment(\.colorSchemeContrast) private var contrast
    /// The press plate follows the control's own corner radius; `plate: false`
    /// leaves press feedback to the control (lit faces, transport keys).
    var radius: CGFloat
    var plate: Bool

    init(radius: CGFloat = Luz.Radius.cell, plate: Bool = true) { self.radius = radius; self.plate = plate }

    func makeBody(configuration: Configuration) -> some View {
        let pressed = enabled && configuration.isPressed && plate
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return configuration.label
            .contentShape(Rectangle())
            .background {
                shape.fill(pressed ? Color.lifted.opacity(contrast == .increased ? 1 : 0.85) : Color.clear)
            }
            .overlay {
                shape.strokeBorder(
                    focused ? Color.mint : pressed ? Color.outline : .clear,
                    lineWidth: focused ? 1.5 : 0.75
                )
                    .allowsHitTesting(false)
            }
            .opacity(enabled ? 1 : contrast == .increased ? 0.6 : 0.42)
    }
}

private struct StudioNavigationPlate: View {
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var solid = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: StudioMetrics.navigationRadius, style: .continuous)
    }

    var body: some View {
        Group {
            if solid || reduceTransparency || contrast == .increased {
                shape.fill(Color.panel)
            } else {
                shape.fill(.regularMaterial).overlay { shape.fill(Color.panel.opacity(0.72)) }
            }
        }
        .overlay {
            shape.strokeBorder(Color.outline, lineWidth: contrast == .increased ? 1.25 : 0.75)
        }
        .allowsHitTesting(false)
    }
}

struct StudioNavigationSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    /// Solid chrome where blur must not compete with real-time drawing (Jam).
    var solid: Bool

    init(solid: Bool = false) { self.solid = solid }

    @ViewBuilder func body(content: Content) -> some View {
        if solid {
            content.background { StudioNavigationPlate(solid: true) }
        } else {
            glass(content)
        }
    }

    @ViewBuilder private func glass(_ content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), !reduceTransparency, contrast != .increased {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: StudioMetrics.navigationRadius, style: .continuous))
        } else {
            content.background { StudioNavigationPlate() }
        }
        #else
        content.background { StudioNavigationPlate() }
        #endif
    }
}
