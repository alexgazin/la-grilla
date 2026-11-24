import SwiftUI
import MusicDomain

/// U7 · Named versions of the whole song: save, listen, compare A/B on the same beat,
/// restore in one Undo step (the current state is kept as a version first).
struct VersionsView: View {
    @Bindable var session: Session
    @State private var versions: [ProjectVersion] = []
    @State private var name = ""
    @State private var selected: UUID?
    @State private var listening: UUID?
    @State private var side = Side.version
    @State private var loaded: [UUID: Project] = [:]
    @State private var error: String?
    @State private var renaming: ProjectVersion?
    @State private var renameText = ""
    @State private var deleting: ProjectVersion?
    @State private var busy = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    enum Side: Hashable { case version, current }

    private var defaultName: String {
        String(format: NSLocalizedString("Version %lld · %@", comment: "Song versions"), locale: Locale.current,
               versions.count + 1, Date().formatted(date: .omitted, time: .shortened))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Keep a version before a bold change. Versions stay in this project, outside Undo, and survive closing the app.")
                        .font(.caption).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
                    saveCard
                    if let error { Text(LocalizedStringKey(error)).font(.callout).foregroundStyle(Color.record) }
                    if versions.isEmpty {
                        Text("No versions yet.").font(.callout).foregroundStyle(Color.studioText).padding(.vertical, 12)
                            .accessibilityIdentifier("versions.empty")
                    }
                    ForEach(Array(versions.enumerated()), id: \.element.id) { index, version in row(version, index: index) }
                }.padding(18)
            }
            .accessibilityIdentifier("versions.scroll")
            .background(Color.ink)
            .navigationTitle("Song versions").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { stopListening(); session.sheet = nil }.accessibilityIdentifier("versions.done") } }
        }
        .tint(.mint)
        .task { await reload() }
        .onDisappear { stopListening() }
        .onChange(of: session.harmonyPreview) { _, previewing in if !previewing { listening = nil } }
        .alert("Rename version", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText).accessibilityIdentifier("versions.rename-field")
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Rename") { if let version = renaming { Task { await rename(version) } } }
        }
        .confirmationDialog("Delete this version?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete version", role: .destructive) { if let version = deleting { Task { await delete(version) } } }.accessibilityIdentifier("versions.delete-confirm")
        } message: { Text("The song itself does not change.") }
    }

    private var saveCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SAVE THE SONG AS IT IS NOW").font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(Color.muted)
            TextField(defaultName, text: $name).textFieldStyle(.plain).padding(12).frame(minHeight: 44)
                .background(Color.raised, in: RoundedRectangle(cornerRadius: Luz.Radius.cell, style: .continuous))
                .accessibilityIdentifier("versions.name")
            Button { Task { await save() } } label: {
                HStack { if busy { ProgressView() }; Label("Save version", systemImage: "square.and.arrow.down.on.square") }.frame(maxWidth: .infinity, minHeight: 48)
            }.buttonStyle(StudioActionStyle()).disabled(busy || session.recording || session.armed).accessibilityIdentifier("versions.save")
        }
        .padding(14).background(Color.panel, in: RoundedRectangle(cornerRadius: Luz.Radius.card, style: .continuous))
    }

    @ViewBuilder private func row(_ version: ProjectVersion, index: Int) -> some View {
        let isSelected = selected == version.id
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(reduceMotion ? nil : Luz.Motion.snap) { selected = isSelected ? nil : version.id }
                Luz.Haptics.selection()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "bookmark.fill").foregroundStyle(Color.harmony).frame(width: 28).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: version.name).font(.subheadline.weight(.semibold)).multilineTextAlignment(.leading)
                        HStack(spacing: 6) {
                            Text(version.created, format: .relative(presentation: .named))
                            Text("·").accessibilityHidden(true)
                            Text("\(version.bars) bars")
                            Text("·").accessibilityHidden(true)
                            Text("\(Int(version.bpm)) BPM").monospacedDigit()
                        }.font(.caption).foregroundStyle(Color.muted)
                    }
                    Spacer(minLength: 0)
                    if listening == version.id { Image(systemName: "speaker.wave.2.fill").foregroundStyle(Color.mint).accessibilityLabel("Playing") }
                }.frame(maxWidth: .infinity, minHeight: 48, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(StudioQuietButtonStyle())
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityIdentifier("versions.row.\(index)")
            if isSelected { actions(version).transition(Luz.Transition.rise(reduceMotion)) }
        }
        .padding(12)
        .background(Color.panel, in: RoundedRectangle(cornerRadius: Luz.Radius.card, style: .continuous))
    }

    @ViewBuilder private func actions(_ version: ProjectVersion) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { Task { await toggleListening(version) } } label: {
                Label(LocalizedStringKey(listening == version.id ? "Stop" : "Listen"), systemImage: listening == version.id ? "stop.fill" : "play.fill")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(StudioActionStyle(color: .mint, prominent: false)).accessibilityIdentifier("versions.listen")
            if listening == version.id {
                StudioSegments(title: "Compare", selection: $side, options: [(.version, "This version"), (.current, "Now")], identifier: "versions.ab")
                    .onChange(of: side) { _, value in
                        if value == .current { session.previewSnapshot(session.project) }
                        else if let project = loaded[version.id] { session.previewSnapshot(project) }
                    }
                Text("Switch while it plays: both start from the same beat.").font(.caption).foregroundStyle(Color.muted)
            }
            HStack(spacing: 10) {
                Button { Task { await restore(version) } } label: {
                    Label("Restore", systemImage: "clock.arrow.circlepath").frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(StudioActionStyle()).disabled(busy || session.recording || session.armed).accessibilityIdentifier("versions.restore")
                Menu {
                    // U30 menu: version — Rename · … · Delete (last, red).
                    Button("Rename", systemImage: "pencil") { renameText = version.name; renaming = version }
                        .accessibilityIdentifier("versions.menu.rename")
                    Button("Delete version", systemImage: "trash", role: .destructive) { deleting = version }
                        .accessibilityIdentifier("versions.menu.delete")
                    // U30 end
                } label: {
                    Image(systemName: "ellipsis").frame(width: 44, height: 44).background(Color.raised, in: RoundedRectangle(cornerRadius: Luz.Radius.cell, style: .continuous))
                }.accessibilityLabel(Text("More for \(version.name)")).accessibilityIdentifier("versions.more")
            }
            Text("Restoring keeps the song as it is now as a version first. One Undo returns it.").font(.caption).foregroundStyle(Color.muted)
        }
    }

    private func reload() async { versions = await session.store.versions(of: session.project.id) }

    private func project(for version: ProjectVersion) async -> Project? {
        if let cached = loaded[version.id] { return cached }
        do {
            let project = try await session.store.loadVersion(version.id, of: session.project.id)
            loaded[version.id] = project
            return project
        } catch { self.error = error.localizedDescription; return nil }
    }

    private func save() async {
        busy = true; defer { busy = false }
        error = nil
        await session.save()
        do {
            _ = try await session.store.saveVersion(session.project, name: name.isEmpty ? defaultName : name)
            name = ""
            await reload()
            session.showToast("Version saved")
        } catch { self.error = error.localizedDescription }
    }

    private func toggleListening(_ version: ProjectVersion) async {
        if listening == version.id { stopListening(); return }
        guard let project = await project(for: version) else { return }
        side = .version
        session.previewSnapshot(project)
        listening = session.harmonyPreview ? version.id : nil
    }

    private func stopListening() { if listening != nil { session.endHarmonyPreview() }; listening = nil }

    private func restore(_ version: ProjectVersion) async {
        stopListening()
        guard let project = await project(for: version) else { return }
        busy = true; defer { busy = false }
        let keep = String(format: NSLocalizedString("Before restoring %@", comment: "Song versions"), locale: Locale.current, version.name)
        await session.restoreVersion(project, keepingCurrentAs: String(keep.prefix(60)))
        await reload()
    }

    private func rename(_ version: ProjectVersion) async {
        do { try await session.store.renameVersion(version.id, of: session.project.id, to: renameText); await reload() }
        catch { self.error = error.localizedDescription }
        renaming = nil
    }

    private func delete(_ version: ProjectVersion) async {
        stopListening()
        do { try await session.store.deleteVersion(version.id, of: session.project.id); loaded[version.id] = nil; await reload() }
        catch { self.error = error.localizedDescription }
        deleting = nil
    }
}
