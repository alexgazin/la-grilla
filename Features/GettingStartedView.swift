import SwiftUI

/// A short, skippable first session guide. It can always be opened from Settings.
struct GettingStartedView: View {
    let close: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image("LaunchMark").resizable().scaledToFit().frame(width: 80, height: 80).accessibilityHidden(true)
                    Text("Your idea. Your groove. Your track.").font(.largeTitle.weight(.semibold)).tracking(-0.8)
                        .accessibilityIdentifier("welcome.title")
                    Text("A little studio, ready when inspiration arrives.").font(.body).foregroundStyle(Color.muted)
                    step("square.grid.3x3", title: "Shape it in Grid", detail: "Choose chords and sections. Move clips to build your song.", color: .harmony)
                    step("square.grid.2x2.fill", title: "Play it in Jam", detail: "Tap the pads, record a loop, then add a melody while the groove keeps going.", color: .drums)
                    step("square.and.arrow.up", title: "Take it further", detail: "Find your balance in Mixer, then export MIDI, WAV or stems to your DAW.", color: .bass)
                    Text("Your projects save automatically on this iPhone. Microphone access is requested only when you record or dictate.")
                        .font(.callout).foregroundStyle(Color.muted)
                    Button(action: close) { Text("Start creating") }.buttonStyle(StudioActionStyle()).accessibilityIdentifier("welcome.start")
                    Text("Find this guide again in Settings → Getting started.").font(.caption).foregroundStyle(Color.muted)
                }.padding(24)
            }
            .background(Color.ink)
            .navigationTitle("Getting started")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Skip", action: close).accessibilityIdentifier("welcome.skip") } }
        }.tint(.mint)
    }

    private func step(_ symbol: String, title: LocalizedStringKey, detail: LocalizedStringKey, color: Color) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol).font(.title2).foregroundStyle(color).frame(width: 32).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(Color.muted)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
