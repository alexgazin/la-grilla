import SwiftUI
import MusicDomain

struct ArrangementTakePicker: View {
    @Binding var selection: ArrangementTake

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Compare performances")
            StudioSegments(title: "Compare performances", selection: $selection,
                           options: ArrangementTake.allCases.map { ($0, LocalizedStringKey($0.rawValue)) })
            .accessibilityIdentifier("builder.arrangement-take")
            .accessibilityHint("The project will use the selected performance.")
        }
    }
}
