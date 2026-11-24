import SwiftUI

/// U12 · A short hint on an empty screen with up to three ways to start, so an empty
/// view is never a dead end. Identifiers: `empty.<screen>` and `empty.<screen>.<N>`.
struct EmptyStateCard: View {
    struct Action { let title: LocalizedStringKey; let symbol: String; let run: () -> Void }
    let screen: String
    let symbol: String
    let message: LocalizedStringKey
    let actions: [Action]
    /// One line with the first action beside it, for screens where height is precious.
    var compact = false

    var body: some View {
        if compact { compactBody } else { fullBody }
    }

    private var compactBody: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(Color.mint).accessibilityHidden(true)
            Text(message).font(.caption).foregroundStyle(Color.studioText).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if let first = actions.first {
                Button(action: first.run) {
                    Label(first.title, systemImage: first.symbol).font(.caption.weight(.semibold)).padding(.horizontal, 10).frame(minHeight: 44)
                }
                .buttonStyle(StudioActionStyle(color: .mint, prominent: true))
                .fixedSize()
                .accessibilityIdentifier("empty.\(screen).0")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Color.panel, in: RoundedRectangle(cornerRadius: Luz.Radius.card, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("empty.\(screen)")
    }

    private var fullBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbol).font(.title3).foregroundStyle(Color.mint).accessibilityHidden(true)
                Text(message).font(.callout).foregroundStyle(Color.studioText).fixedSize(horizontal: false, vertical: true)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { buttons }
                VStack(alignment: .leading, spacing: 8) { buttons }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.panel, in: RoundedRectangle(cornerRadius: Luz.Radius.card, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: Luz.Radius.card, style: .continuous).strokeBorder(Color.mint.opacity(0.25), lineWidth: 0.75) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("empty.\(screen)")
    }

    @ViewBuilder private var buttons: some View {
        ForEach(actions.indices, id: \.self) { index in
            Button(action: actions[index].run) {
                Label(actions[index].title, systemImage: actions[index].symbol).font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(StudioActionStyle(color: .mint, prominent: index == 0))
            .accessibilityIdentifier("empty.\(screen).\(index)")
        }
    }
}
