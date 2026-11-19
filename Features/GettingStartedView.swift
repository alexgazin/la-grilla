import SwiftUI

/// I87 · A short, skippable first-session intro of real app actions. Pages
/// swipe; Start and Skip are always reachable. On iOS 26 the cards use Liquid
/// Glass (respecting Reduce Transparency and Increase Contrast); earlier
/// systems use the studio surface. It can always be opened from Settings.
struct GettingStartedView: View {
    let close: () -> Void
    @State private var page = 0

    private struct Page: Identifiable {
        let id: Int
        let symbol: String
        let title: LocalizedStringKey
        let detail: LocalizedStringKey
        let color: Color
    }
    private let pages: [Page] = [
        Page(id: 1, symbol: "square.grid.3x3", title: "Shape it in Grid", detail: "Choose chords and sections. Move clips to build your song.", color: .harmony),
        Page(id: 2, symbol: "square.grid.2x2.fill", title: "Play it in Jam", detail: "Tap the pads, record a loop, then add a melody while the groove keeps going.", color: .drums),
        Page(id: 3, symbol: "text.bubble", title: "Change it in your words", detail: "Tell the Assistant “remove the kick in the first two bars”. Hear before and after, then apply with one Undo.", color: .mint),
        Page(id: 4, symbol: "paintpalette", title: "Try a palette", detail: "Boom bap, West Coast or atmospheric chillhop on your own part, at matched loudness.", color: .bass),
        Page(id: 5, symbol: "square.and.arrow.up", title: "Take it further", detail: "Find your balance in Mixer, then export MIDI, WAV, stems or AAC to your DAW.", color: .harmony),
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Image("LaunchMark").resizable().scaledToFit().frame(width: 64, height: 64).accessibilityHidden(true)
                    Text("Your idea. Your groove. Your track.").font(.largeTitle.weight(.semibold)).tracking(-0.8)
                        .accessibilityIdentifier("welcome.title")
                    Text("A little studio, ready when inspiration arrives.").font(.body).foregroundStyle(Color.muted)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24).padding(.top, 12)
                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { index, item in
                        IntroCard(symbol: item.symbol, title: item.title, detail: item.detail, color: item.color)
                            .padding(.horizontal, 24).tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
                .frame(minHeight: 260)
                .accessibilityIdentifier("welcome.pages")
                VStack(spacing: 10) {
                    Text("Your projects save automatically on this iPhone. Microphone access is requested only when you record or dictate.")
                        .font(.callout).foregroundStyle(Color.muted).frame(maxWidth: .infinity, alignment: .leading)
                    Button(action: close) { Text("Start creating") }.buttonStyle(StudioActionStyle()).accessibilityIdentifier("welcome.start")
                    Text("Find this guide again in Settings → Getting started.").font(.caption).foregroundStyle(Color.muted)
                }.padding(.horizontal, 24).padding(.bottom, 16)
            }
            .background(Color.ink)
            .navigationTitle("Getting started")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Skip", action: close).accessibilityIdentifier("welcome.skip") } }
        }.tint(.mint)
    }
}

private struct IntroCard: View {
    let symbol: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let color: Color
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: symbol).font(.system(size: 34, weight: .medium)).foregroundStyle(color).accessibilityHidden(true)
            Text(title).font(.title3.weight(.semibold))
            Text(detail).font(.callout).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: 220, alignment: .topLeading)
        .modifier(IntroSurface(reduceTransparency: reduceTransparency, increasedContrast: contrast == .increased))
        .accessibilityElement(children: .combine)
    }
}

private struct IntroSurface: ViewModifier {
    let reduceTransparency: Bool
    let increasedContrast: Bool
    @ViewBuilder func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), !reduceTransparency, !increasedContrast {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        } else {
            content.modifier(StudioSurface())
        }
        #else
        content.modifier(StudioSurface())
        #endif
    }
}
