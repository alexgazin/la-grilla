import SwiftUI
import LocalAuthentication
import MusicDomain
import UniformTypeIdentifiers
struct ProjectsView: View {
    @Bindable var session: Session
    @AppStorage("studio.pitchSpelling") private var spellingValue=PitchSpelling.automatic.rawValue
    @State private var showImport=false
    @State private var mergeImport=false
    @State private var openingExample=false
    @State private var deleting: UUID?;@State private var renameID: UUID?;@State private var name=""
    @State private var query=""
    @State private var deleted:[ProjectStore.TrashedProject]=[]
    /// U34: order and pinned projects, kept on this device.
    @AppStorage("projects.order") private var orderRaw=ProjectOrdering.modified.rawValue
    @AppStorage("projects.pinned") private var pinnedRaw=""
    private var pinned:Set<UUID>{Set(pinnedRaw.split(separator:",").compactMap{UUID(uuidString:String($0))})}
    /// I65: projects hidden behind Face ID or the passcode (kept on this device).
    @AppStorage("projects.private") private var privateRaw=""
    private var privateIDs:Set<UUID>{Set(privateRaw.split(separator:",").compactMap{UUID(uuidString:String($0))})}
    private func togglePrivate(_ id:UUID){var set=privateIDs;if set.contains(id){set.remove(id)}else{set.insert(id)};privateRaw=set.map(\.uuidString).sorted().joined(separator:",")}
    private func open(_ id:UUID){
        guard privateIDs.contains(id) else{Task{await session.openStored(id)};return}
        let context=LAContext()
        context.evaluatePolicy(.deviceOwnerAuthentication,localizedReason:NSLocalizedString("Open a private project",comment:"Face ID reason")){ok,_ in
            if ok{Task{@MainActor in await session.openStored(id)}}
        }
    }
    private func togglePin(_ id:UUID){var set=pinned;if set.contains(id){set.remove(id)}else{set.insert(id)};pinnedRaw=set.map(\.uuidString).sorted().joined(separator:",")}
    private var ordered:[ProjectStore.SummaryEntry]{
        let order=ProjectOrdering(rawValue:orderRaw) ?? .modified
        let summaries=order.sorted(session.entries.compactMap(\.summary),pinned:pinned)
        let rank=Dictionary(uniqueKeysWithValues:summaries.enumerated().map{($0.element.id,$0.offset)})
        return session.entries.sorted{(rank[$0.id] ?? Int.max)<(rank[$1.id] ?? Int.max)}
    }
    /// I74: match name, tempo or key ("90", "D minor", "ре минор").
    private var visibleEntries:[ProjectStore.SummaryEntry]{
        let text=query.trimmingCharacters(in:.whitespaces).lowercased()
        guard !text.isEmpty else{return ordered}
        return ordered.filter{entry in
            guard let p=entry.summary else{return false}
            let key=(Chord.roots[p.keyRoot]+" "+(p.minor ? "minor":"major")+" "+NSLocalizedString(p.minor ? "minor":"major",comment:"Key mode")).lowercased()
            return p.name.lowercased().contains(text) || "\(Int(p.bpm))".hasPrefix(text) || key.contains(text) || MusicalNotation.pitchClassName(p.keyRoot,keyRoot:p.keyRoot,minor:p.minor,spelling:.automatic).lowercased()==text
        }
    }
    var body: some View {NavigationStack{ScrollView{VStack(alignment:.leading,spacing:22){
        HStack{VStack(alignment:.leading,spacing:7){Text("Your next idea\nstarts here.").font(StudioTypography.display);Text("A little studio. A world of possibilities.").font(.system(.caption)).foregroundStyle(Color.muted)};Spacer();Image(systemName:"square.grid.3x3").font(.system(size:42,weight:.ultraLight)).foregroundStyle(Color.mint)}.padding(.vertical,15)
        Button{session.sheet = .newProject}label:{Label("New project",systemImage:"plus")}.buttonStyle(StudioActionStyle()).accessibilityIdentifier("project.new")
        if !Luz.uiTesting || ProcessInfo.processInfo.arguments.contains("--daily"){DailyIdeaCard(session:session)}
        Button{showImport=true}label:{Label("Import project",systemImage:"square.and.arrow.down").font(.system(.subheadline,weight:.medium)).frame(maxWidth:.infinity,minHeight:44)}.buttonStyle(StudioQuietButtonStyle()).tint(.mint).accessibilityIdentifier("project.import")
        Button{guard !openingExample else{return};openingExample=true;Task{_ = await session.openExample();openingExample=false}}label:{Label("Open an example",systemImage:"music.note.list").frame(maxWidth:.infinity,minHeight:44)}.buttonStyle(StudioQuietButtonStyle()).tint(.mint).accessibilityIdentifier("project.example")
        if openingExample{ProgressView("Opening example…")}
        Button{mergeImport=true;showImport=true}label:{Label("Merge a co-author's copy",systemImage:"arrow.triangle.merge").frame(maxWidth:.infinity,minHeight:44)}.buttonStyle(StudioQuietButtonStyle()).accessibilityIdentifier("project.merge-copy")
        Text("Brings their edits of a shared .grillapack into the open project. One Undo reverts it.").font(.caption).foregroundStyle(Color.muted)
        Text("Opens a separate copy. Your current project is saved first.").font(.caption).foregroundStyle(Color.muted)
        if session.projectChangeQAEnabled{Button{Task{await session.runProjectChangeQA()}}label:{Text(verbatim:"Run project change checks").frame(minHeight:44)}.accessibilityIdentifier("project.change-probe")}
        HStack{SmallHeading(text:"ON THIS IPHONE");Spacer();Text("\(session.entries.count) projects").font(.system(.caption)).foregroundStyle(Color.muted)
            Menu{Picker("Sort by",selection:$orderRaw){ForEach(ProjectOrdering.allCases,id:\.rawValue){order in Text(LocalizedStringKey(order.title)).tag(order.rawValue)}}}label:{Image(systemName:"arrow.up.arrow.down").frame(width:44,height:44)}.accessibilityLabel("Sort projects").accessibilityIdentifier("project.sort")}
        if session.entries.count>3{HStack(spacing:8){Image(systemName:"magnifyingglass").foregroundStyle(Color.muted).accessibilityHidden(true);TextField("Search by name, tempo or key",text:$query).textFieldStyle(.plain).accessibilityIdentifier("project.search");if !query.isEmpty{Button{query=""}label:{Image(systemName:"xmark.circle.fill").foregroundStyle(Color.muted)}.accessibilityLabel("Clear")}}.padding(.horizontal,12).frame(minHeight:44).background(Color.panel,in:Capsule(style:.continuous)).overlay{Capsule(style:.continuous).strokeBorder(Color.outline.opacity(0.8),lineWidth:0.75)}}
        ForEach(visibleEntries){entry in
            if let p=entry.summary {HStack(spacing:14){VStack(spacing:3){ForEach(0..<3){row in HStack(spacing:2){ForEach(0..<4){bar in RoundedRectangle(cornerRadius:1,style:.continuous).fill((row==0 ? Color.harmony:row==1 ? Color.drums:Color.bass).opacity(row==2 && p.trackCount<3 ? 0.08:0.6)).frame(width:8,height:row==0 ? 12:4)}}}}.frame(width:48,height:48).background(Color.raised,in:RoundedRectangle(cornerRadius:7,style:.continuous))
                Button{open(entry.id)}label:{VStack(alignment:.leading,spacing:6){HStack(spacing:4){if privateIDs.contains(entry.id){Image(systemName:"lock.fill").font(.caption).foregroundStyle(Color.muted).accessibilityLabel("Private")};Text(privateIDs.contains(entry.id) ? NSLocalizedString("Private project",comment:"Hidden name"):p.name).font(.system(.body,weight:.medium)).foregroundStyle(.primary)};Text("\(Int(p.bpm)) BPM · \(MusicalNotation.pitchClassName(p.keyRoot,keyRoot:p.keyRoot,minor:p.minor,spelling:PitchSpelling(rawValue:spellingValue) ?? .automatic)+" "+NSLocalizedString(p.minor ? "minor":"major",comment:"Key mode")) · \(p.length/barTicks) bars").font(.system(.caption)).foregroundStyle(Color.muted);Text(p.modified,style:.relative).font(.system(.caption2)).foregroundStyle(Color.muted)}}.buttonStyle(StudioQuietButtonStyle()).accessibilityIdentifier("project.open."+entry.id.uuidString);Spacer();Menu{Button("Open"){open(entry.id)};Button(privateIDs.contains(entry.id) ? "Stop hiding":"Hide behind Face ID",systemImage:privateIDs.contains(entry.id) ? "lock.open":"lock"){togglePrivate(entry.id)};Button(pinned.contains(entry.id) ? "Unpin":"Pin to top",systemImage:pinned.contains(entry.id) ? "pin.slash":"pin"){togglePin(entry.id)};Button("Rename"){renameID=entry.id;name=p.name};Button("Duplicate"){Task{await session.duplicateStored(entry.id)}};Button("Delete",role:.destructive){deleting=entry.id}}label:{Image(systemName:"ellipsis").foregroundStyle(Color.muted).frame(width:44,height:44)}}.padding(.vertical,8).overlay(alignment:.bottom){Rectangle().fill(Color.raised).frame(height:1)}
                .luzScrollDepth().luzEntrance(session.entries.firstIndex(where:{$0.id==entry.id}) ?? 0)
            }else{VStack(alignment:.leading,spacing:8){Label("Project needs recovery",systemImage:"exclamationmark.triangle");Text(LocalizedStringKey(entry.error ?? "Could not read project")).font(.caption).foregroundStyle(Color.muted);Button("Retry"){Task{await session.openStored(entry.id)}};if entry.hasBackup{Button("Recover last working copy"){Task{await session.recover(entry.id)}}}}.padding()}
        }
        if session.entries.isEmpty{LuzEmptyState(symbol:"music.note.list",title:"Start with chords or a beat.",action:("New project",{session.sheet = .newProject}))}
        if session.entries.count>1{Button{session.exportAllProjects()}label:{Label("Export all projects (.zip)",systemImage:"archivebox").frame(maxWidth:.infinity,minHeight:44)}.buttonStyle(StudioQuietButtonStyle()).disabled(session.exportInProgress).accessibilityIdentifier("project.export-all")}
        if !deleted.isEmpty{RecentlyDeletedList(items:deleted){id in Task{await session.restoreDeleted(id);deleted=await session.store.recentlyDeleted()}}}
    }.animation(Luz.Motion.snap,value:query).padding(22)}.background(LuzAurora()).navigationTitle("La Grilla").navigationBarTitleDisplayMode(.inline).toolbar{ToolbarItem(placement:.confirmationAction){Button("Done"){session.sheet=nil}}}}
    .disabled(openingExample).interactiveDismissDisabled(openingExample)
    .task{await session.refreshLibrary();deleted=await session.store.recentlyDeleted();guard !Task.isCancelled else{return};await session.save()}
    .fileImporter(isPresented:$showImport,allowedContentTypes:[UTType(exportedAs:"com.alexgazin.grillapack",conformingTo:.zip),.zip,.midi],allowsMultipleSelection:false){result in
        let merging=mergeImport;mergeImport=false
        switch result{case .success(let urls):if let url=urls.first{Task{if merging{await session.mergeCopy(url)}else{await session.importProject(url)}}};case .failure(let error):session.message=error.localizedDescription}
    }
    .alert("Delete project?",isPresented:Binding(get:{deleting != nil},set:{if !$0{deleting=nil}})){Button("Delete",role:.destructive){if let id=deleting{Task{if id==session.project.id{await session.create(name:"Untitled",bpm:120,root:0,minor:false,bars:4)};if session.project.id != id{await session.delete(id);deleted=await session.store.recentlyDeleted()}}};deleting=nil};Button("Cancel",role:.cancel){deleting=nil}}message:{Text("The project moves to Recently Deleted and can be restored for 30 days.")}
    .alert("Rename project",isPresented:Binding(get:{renameID != nil},set:{if !$0{renameID=nil}})){TextField("Name",text:$name);Button("Save"){if let id=renameID,let p=session.entries.first(where:{$0.id==id})?.summary,!name.isEmpty{let title=name;Task{if id==session.project.id{session.edit{$0.name=title};await session.save()}else{await session.renameStored(id,expectedRevision:p.revision,to:title)}}};renameID=nil};Button("Cancel",role:.cancel){renameID=nil}}
    }
}
struct NewProjectView: View {
    @Bindable var session: Session
    @AppStorage("studio.pitchSpelling") private var spellingValue=PitchSpelling.automatic.rawValue
    @State private var name = ""
    @State private var bpm = 120.0
    @State private var root = 0
    @State private var minor = false
    @State private var bars = 4
    @State private var template:ProjectTemplate = .empty
    @State private var creating = false
    @State private var creationError:String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Starting point") {
                    Button { session.openTrackBuilder(name:name) } label: {
                        Label("Build a track",systemImage:"slider.horizontal.3")
                    }
                    HStack {
                        templateButton(.empty,title:"Empty")
                        templateButton(.starter,title:"Starter groove")
                    }
                    Text(LocalizedStringKey(template == .empty ? "Start empty, then add chords or record a beat.":"Editable chords, drums and root bass in your chosen key. A local starting point, not AI generation."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let usual=StyleProfile.from(session.entries.compactMap(\.summary)) {
                    // I50: computed on this iPhone from your own projects.
                    Section {
                        Button{bpm=usual.bpm;root=usual.keyRoot;minor=usual.minor;bars=usual.bars}label:{
                            Label(String(format:NSLocalizedString("Use my usual: %d BPM · %@ · %d bars",comment:"Style profile"),Int(usual.bpm),MusicalNotation.pitchClassName(usual.keyRoot,keyRoot:usual.keyRoot,minor:usual.minor,spelling:PitchSpelling(rawValue:spellingValue) ?? .automatic)+" "+NSLocalizedString(usual.minor ? "minor":"major",comment:"Key mode"),usual.bars),systemImage:"person.crop.circle.badge.checkmark")
                        }.accessibilityIdentifier("project.usual")
                    } footer: { Text(String(format:NSLocalizedString("From your %d projects on this iPhone.",comment:"Style profile"),usual.projects)) }
                }
                Section {
                    TextField("Project name", text: $name).accessibilityIdentifier("project.name")
                    Stepper("\(Int(bpm)) BPM", value: $bpm, in: 40...240).accessibilityIdentifier("project.tempo")
                    Picker("Key", selection: $root) {
                        ForEach(0..<12, id: \.self) { i in Text(MusicalNotation.pitchClassName(i,keyRoot:i,minor:minor,spelling:PitchSpelling(rawValue:spellingValue) ?? .automatic)).tag(i) }
                    }.accessibilityIdentifier("project.key")
                    Toggle("Minor", isOn: $minor).accessibilityIdentifier("project.minor")
                    Picker("Loop length", selection: $bars) {
                        ForEach([1,2,4,8,16,32,64], id: \.self) { n in Text("\(n) bars").tag(n) }
                    }.accessibilityIdentifier("project.bars")
                }
                if let creationError{Section{Text(LocalizedStringKey(creationError)).foregroundStyle(Color.record).accessibilityIdentifier("project.create-error")}}
                if creating{Section{ProgressView("Creating project…")}}
            }
            .disabled(creating)
            .navigationTitle("New project")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { session.sheet = nil }.disabled(creating) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        guard !creating else{return}
                        creating=true;creationError=nil
                        Task {
                            let created=await session.create(name: name, bpm: bpm, root: root, minor: minor, bars: bars,template:template)
                            if !created,session.sheet == .newProject{creationError=session.message ?? session.saveError;session.message=nil}
                            creating=false
                        }
                    }.disabled(creating).accessibilityIdentifier("project.create")
                }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(creating)
    }
    private func templateButton(_ option:ProjectTemplate,title:LocalizedStringKey)->some View {
        Button{template=option}label:{Text(title).frame(maxWidth:.infinity,minHeight:44).foregroundStyle(template==option ? Color.ink:Color.studioText).background(template==option ? Color.mint:Color.raised,in:RoundedRectangle(cornerRadius:Luz.Radius.cell,style:.continuous))}
            .buttonStyle(StudioQuietButtonStyle()).accessibilityIdentifier("project.template."+option.rawValue)
            .accessibilityAddTraits(template==option ? .isSelected:[])
    }
}

/// I73: projects deleted in the last 30 days, restorable with their sounds.
private struct RecentlyDeletedList: View {
    let items: [ProjectStore.TrashedProject]
    let restore: (UUID) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SmallHeading(text: "RECENTLY DELETED")
            Text("Kept for 30 days, then removed.").font(.caption).foregroundStyle(Color.muted)
            ForEach(items) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: item.name).font(.subheadline)
                        Text(item.deletedAt, style: .relative).font(.caption2).foregroundStyle(Color.muted)
                    }
                    Spacer()
                    Button("Restore") { restore(item.id) }.frame(minHeight: 44).accessibilityIdentifier("project.restore." + item.id.uuidString)
                }
            }
        }
    }
}
