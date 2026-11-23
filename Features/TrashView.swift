import SwiftUI
import MusicDomain

/// U8 · Recently deleted tracks, takes and clips of this song (30 days). Each comes
/// back to its place in one Undo step.
struct TrashView: View {
    @Bindable var session: Session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var items: [DeletedItem] { ProjectTrash.items(in: session.project) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Deleted tracks, drum takes and clips stay here for 30 days, even after you close the app.")
                        .font(.caption).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
                    if items.isEmpty {
                        Text("Nothing deleted recently.").font(.callout).foregroundStyle(Color.studioText).padding(.vertical, 24)
                            .accessibilityIdentifier("trash.empty")
                    }
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in row(item, index: index) }
                }.padding(18)
                    .animation(reduceMotion ? nil : Luz.Motion.snap, value: items.map(\.id))
            }
            .accessibilityIdentifier("trash.scroll")
            .background(Color.ink)
            .navigationTitle("Recently deleted").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { session.sheet = nil }.accessibilityIdentifier("trash.done") } }
        }.tint(.mint)
    }

    private func title(_ item: DeletedItem) -> String {
        switch item.kind {
        case .track: String(format: NSLocalizedString("Track %@", comment: "Recently deleted"), locale: Locale.current, item.name)
        case .take: String(format: NSLocalizedString("Take %@", comment: "Recently deleted"), locale: Locale.current, item.name)
        case .clip: String(format: NSLocalizedString("Clip on %@ · bar %lld", comment: "Recently deleted"), locale: Locale.current,
                           item.name, (item.clip?.start ?? 0) / barTicks + 1)
        }
    }

    private func symbol(_ item: DeletedItem) -> String {
        switch item.kind { case .track: "music.note.list"; case .take: "record.circle"; case .clip: "rectangle.portrait" }
    }

    private func row(_ item: DeletedItem, index: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol(item)).frame(width: 28).foregroundStyle(Color.muted).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title(item)).font(.subheadline.weight(.semibold))
                Text(String(format: NSLocalizedString("Deleted %@ · %lld days left", comment: "Recently deleted"), locale: Locale.current,
                            item.deletedAt.formatted(.relative(presentation: .named)), ProjectTrash.daysLeft(item)))
                    .font(.caption).foregroundStyle(Color.muted)
            }
            Spacer(minLength: 8)
            Button { session.restoreDeleted(item.id) } label: {
                Label("Restore", systemImage: "arrow.uturn.backward").frame(minHeight: 44).padding(.horizontal, 6)
            }
            .buttonStyle(StudioActionStyle(color: .mint, prominent: false))
            .disabled(session.recording || session.armed)
            .accessibilityLabel(Text("Restore \(title(item))"))
            .accessibilityIdentifier("trash.restore.\(index)")
        }
        .padding(12)
        .background(Color.panel, in: RoundedRectangle(cornerRadius: Luz.Radius.card, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trash.row.\(index)")
    }
}
