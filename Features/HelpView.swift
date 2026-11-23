import SwiftUI
import MusicDomain

/// U25 · Short help for every screen, offline, in plain words.
struct HelpView: View {
    @Bindable var session: Session
    private struct Topic: Identifiable { let id: String; let symbol: String; let points: [String] }
    private let topics: [Topic] = [
        .init(id: "Grid", symbol: "square.grid.3x3", points: ["Tap a cell to write a chord; touch and hold to hear it.", "Chips at the top are sections; the target button loops just the selected one.", "Pinch to zoom the timeline."]),
        .init(id: "Jam", symbol: "square.grid.2x2", points: ["Play the pads or switch to Steps to place hits.", "Every recording is a take: mute, delete or keep it in Layers.", "Touch and hold a lit step for chance and ratchets; Beat tools add variations and fills."]),
        .init(id: "Mixer", symbol: "slider.vertical.3", points: ["Each track has level, pan, Mute and Solo; the menu holds sound, colour and EQ.", "The master menu has the limiter and Prepare for release."]),
        .init(id: "Undo and history", symbol: "clock.arrow.circlepath", points: ["Two fingers left or the Undo button undo one step.", "Touch and hold Undo for the edit history, song versions and recently deleted."]),
        .init(id: "Search actions", symbol: "magnifyingglass", points: ["The magnifier finds any action by words — “tempo 92”, “add a chorus”, “ля минор”.", "The microphone lets you say it; touch and hold a result to pin it to the quick bar."]),
    ]
    var body: some View {
        NavigationStack {
            List(topics) { topic in
                Section {
                    ForEach(topic.points, id: \.self) { point in Text(LocalizedStringKey(point)).font(.callout) }
                } header: { Label(LocalizedStringKey(topic.id), systemImage: topic.symbol) }
            }
            .scrollContentBackground(.hidden).background(Color.ink)
            .navigationTitle("Help").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Getting started") { session.sheet = .gettingStarted } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { session.sheet = nil }.accessibilityIdentifier("help.done") }
            }
        }.tint(.mint)
    }
}
