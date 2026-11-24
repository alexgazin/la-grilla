import SwiftUI

/// U20 · A placeholder in the shape of what is coming, instead of a spinner. It glows softly while
/// waiting (still under Reduce Motion) and reads as the caption for VoiceOver.
struct LoadingSkeleton: View {
    var rows = 3
    let caption: LocalizedStringKey
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glow = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<rows, id: \.self) { row in
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.raised)
                    .frame(maxWidth: row == rows - 1 ? 180 : .infinity, minHeight: 14, maxHeight: 14)
            }
            Text(caption).font(.caption).foregroundStyle(Color.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(glow ? 1 : 0.55)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: glow)
        .onAppear { glow = !reduceMotion }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(caption))
        .accessibilityAddTraits(.updatesFrequently)
    }
}
