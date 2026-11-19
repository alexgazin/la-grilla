import SwiftUI
import MusicDomain
import UniformTypeIdentifiers
struct ProjectsView: View {
    @Bindable var session: Session
    @AppStorage("studio.pitchSpelling") private var spellingValue=PitchSpelling.automatic.rawValue
    @State private var showImport=false
    @State private var openingExample=false
    @State private var deleting: UUID?;@State private var renameID: UUID?;@State private var name=""
    @State private var query=""
    @State private var deleted:[ProjectStore.TrashedProject]=[]
    /// I74: match name, tempo or key ("90", "D minor", "ре минор").
    private var visibleEntries:[ProjectStore.SummaryEntry]{
        let text=query.trimmingCharacters(in:.whitespaces).lowercased()
        guard !text.isEmpty else{return session.entries}
        return session.entries.filter{entry in
            guard let p=entry.summary else{return false}
            let key=(Chord.roots[p.keyRoot]+" "+(p.minor ? "minor":"major")+" "+NSLocalizedString(p.minor ? "minor":"major",comment:"Key mode")).lowercased()
            return p.name.lowercased().contains(text) || "\(Int(p.bpm))".hasPrefix(text) || key.contains(text) || MusicalNotation.pitchClassName(p.keyRoot,keyRoot:p.keyRoot,minor:p.minor,spelling:.automatic).lowercased()==text
        }
    }
    var body: some View {NavigationStack{ScrollView{VStack(alignment:.leading,spacing:22){
        HStack{VStack(alignment:.leading,spacing:7){Text("Your next idea\nstarts here.").font(.system(size:30,weight:.medium));Text("A little studio. A world of possibilities.").font(.system(.caption)).foregroundStyle(Color.muted)};Spacer();Image(systemName:"square.grid.3x3").font(.system(size:42,weight:.ultraLight)).foregroundStyle(Color.mint)}.padding(.vertical,15)
        Button{session.sheet = .newProject}label:{Label("New project",systemImage:"plus").font(.system(.body,weight:.semibold)).foregroundStyle(Color.ink).frame(maxWidth:.infinity,minHeight:52).background(Color.mint,in:RoundedRectangle(cornerRadius:12))}.buttonStyle(StudioQuietButtonStyle()).accessibilityIdentifier("project.new")
        Button{showImport=true}label:{Label("Import project",systemImage:"square.and.arrow.down").font(.system(.subheadline,weight:.medium)).frame(maxWidth:.infinity,minHeight:44)}.buttonStyle(StudioQuietButtonStyle()).tint(.mint).accessibilityIdentifier("project.import")
        Button{guard !openingExample else{return};openingExample=true;Task{_ = await session.openExample();openingExample=false}}label:{Label("Open an example",systemImage:"music.note.list").frame(maxWidth:.infinity,minHeight:44)}.buttonStyle(StudioQuietButtonStyle()).tint(.mint).accessibilityIdentifier("project.example")
        if openingExample{ProgressView("Opening example…")}
        Text("Opens a separate copy. Your current project is saved first.").font(.caption).foregroundStyle(Color.muted)
        if session.projectChangeQAEnabled{Button{Task{await session.runProjectChangeQA()}}label:{Text(verbatim:"Run project change checks").frame(minHeight:44)}.accessibilityIdentifier("project.change-probe")}
        HStack{SmallHeading(text:"ON THIS IPHONE");Spacer();Text("\(session.entries.count) projects").font(.system(.caption)).foregroundStyle(Color.muted)}
        if session.entries.count>3{TextField("Search by name, tempo or key",text:$query).textFieldStyle(.roundedBorder).frame(minHeight:44).accessibilityIdentifier("project.search")}
        ForEach(visibleEntries){entry in
            if let p=entry.summary {HStack(spacing:14){VStack(spacing:3){ForEach(0..<3){row in HStack(spacing:2){ForEach(0..<4){bar in RoundedRectangle(cornerRadius:1).fill((row==0 ? Color.harmony:row==1 ? Color.drums:Color.bass).opacity(row==2 && p.trackCount<3 ? 0.08:0.6)).frame(width:8,height:row==0 ? 12:4)}}}}.frame(width:48,height:48).background(Color.raised,in:RoundedRectangle(cornerRadius:7))
                Button{Task{await session.openStored(entry.id)}}label:{VStack(alignment:.leading,spacing:6){Text(p.name).font(.system(.body,weight:.medium)).foregroundStyle(.primary);Text("\(Int(p.bpm)) BPM · \(MusicalNotation.pitchClassName(p.keyRoot,keyRoot:p.keyRoot,minor:p.minor,spelling:PitchSpelling(rawValue:spellingValue) ?? .automatic)+" "+NSLocalizedString(p.minor ? "minor":"major",comment:"Key mode")) · \(p.length/barTicks) bars").font(.system(.caption)).foregroundStyle(Color.muted);Text(p.modified,style:.relative).font(.system(.caption2)).foregroundStyle(Color.muted)}}.buttonStyle(StudioQuietButtonStyle()).accessibilityIdentifier("project.open."+entry.id.uuidString);Spacer();Menu{Button("Open"){Task{await session.openStored(entry.id)}};Button("Rename"){renameID=entry.id;name=p.name};Button("Duplicate"){Task{await session.duplicateStored(entry.id)}};Button("Delete",role:.destructive){deleting=entry.id}}label:{Image(systemName:"ellipsis").foregroundStyle(Color.muted).frame(width:44,height:44)}}.padding(.vertical,8).overlay(alignment:.bottom){Rectangle().fill(Color.raised).frame(height:1)}
            }else{VStack(alignment:.leading,spacing:8){Label("Project needs recovery",systemImage:"exclamationmark.triangle");Text(LocalizedStringKey(entry.error ?? "Could not read project")).font(.caption).foregroundStyle(Color.muted);Button("Retry"){Task{await session.openStored(entry.id)}};if entry.hasBackup{Button("Recover last working copy"){Task{await session.recover(entry.id)}}}}.padding()}
        }
        if session.entries.isEmpty{Text("Start with chords or a beat.").foregroundStyle(Color.muted)}
        if !deleted.isEmpty{RecentlyDeletedList(items:deleted){id in Task{await session.restoreDeleted(id);deleted=await session.store.recentlyDeleted()}}}
    }.padding(22)}.background(Color.ink).navigationTitle("La Grilla").navigationBarTitleDisplayMode(.inline).toolbar{ToolbarItem(placement:.confirmationAction){Button("Done"){session.sheet=nil}}}}
    .disabled(openingExample).interactiveDismissDisabled(openingExample)
    .task{await session.refreshLibrary();deleted=await session.store.recentlyDeleted();guard !Task.isCancelled else{return};await session.save()}
    .fileImporter(isPresented:$showImport,allowedContentTypes:[UTType(exportedAs:"com.alexgazin.grillapack",conformingTo:.zip),.zip,.midi],allowsMultipleSelection:false){result in
        switch result{case .success(let urls):if let url=urls.first{Task{await session.importProject(url)}};case .failure(let error):session.message=error.localizedDescription}
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
        Button{template=option}label:{Text(title).frame(maxWidth:.infinity,minHeight:44).foregroundStyle(template==option ? Color.ink:Color.studioText).background(template==option ? Color.mint:Color.raised,in:RoundedRectangle(cornerRadius:10))}
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
