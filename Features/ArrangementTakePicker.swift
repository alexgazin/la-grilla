import SwiftUI
import MusicDomain

struct ArrangementTakePicker: View {
    @Binding var selection: ArrangementTake

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Compare performances")
            Picker("Compare performances", selection: $selection) {
                ForEach(ArrangementTake.allCases, id: \.self) { take in
                    Text(verbatim: take.rawValue).tag(take)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("builder.arrangement-take")
            .accessibilityHint("The project will use the selected performance.")
        }
    }
}
