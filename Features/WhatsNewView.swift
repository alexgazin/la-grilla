import SwiftUI
import MusicDomain

/// U70 · What's new in this build, once after an update, each with a Try button.
struct WhatsNewView: View {
    @Bindable var session: Session
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("New in La Grilla").font(StudioTypography.display)
                    ForEach(Array(WhatsNew.items.enumerated()), id: \.offset) { index, item in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: item.symbol).font(.title3).foregroundStyle(Color.mint).frame(width: 32).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(LocalizedStringKey(item.title)).font(.headline)
                                Text(LocalizedStringKey(item.detail)).font(.callout).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
                                if let command = item.command {
                                    Button("Try it") { session.sheet = nil; session.run(command) }.font(.callout.weight(.semibold)).frame(minHeight: 44)
                                        .accessibilityIdentifier("whatsnew.try.\(index)")
                                }
                            }
                        }
                    }
                }.padding(20)
            }
            .background(Color.ink)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { session.sheet = nil }.accessibilityIdentifier("whatsnew.done") } }
        }.tint(.mint)
    }
}
