import SwiftUI

/// U67 · Holding a card plays a short preview; letting go stops it. A tap keeps doing what it did.
/// The accessibility value reports how many previews were heard and whether one is playing.
struct HoldToPreview: ViewModifier {
    /// Starts the preview; false when it could not start.
    let start: () -> Bool
    let stop: () -> Void
    /// Set while a hold is under way and just after it, so the card's tap action can ignore the
    /// release that ends a hold.
    var suppressTap: Binding<Bool>?
    @GestureState private var held = false
    @State private var playing = false
    @State private var heard = 0

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.35, maximumDistance: 14)
                    .sequenced(before: DragGesture(minimumDistance: 0))
                    .updating($held) { value, state, _ in
                        if case .second(true, _) = value { state = true }
                    }
            )
            .onChange(of: held) { _, now in
                if now {
                    suppressTap?.wrappedValue = true
                    guard start() else { return }
                    playing = true; heard += 1
                    Luz.Haptics.selection()
                } else {
                    if playing { playing = false; stop() }
                    if let suppressTap { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { suppressTap.wrappedValue = false } }
                }
            }
            .onDisappear { if playing { playing = false; stop() } }
            .accessibilityValue(Text(String(format: NSLocalizedString("%lld previews, %@", comment: "Hold to preview"), Int64(heard),
                                            NSLocalizedString(playing ? "playing" : "not playing", comment: "Hold to preview"))))
            .accessibilityHint(Text("Touch and hold to hear four bars"))
    }
}

extension View {
    func holdToPreview(suppressTap: Binding<Bool>? = nil, start: @escaping () -> Bool, stop: @escaping () -> Void) -> some View {
        modifier(HoldToPreview(start: start, stop: stop, suppressTap: suppressTap))
    }
}
