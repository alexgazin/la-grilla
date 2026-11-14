import SwiftUI
import MusicDomain
struct ProjectsView: View {
    @Bindable var session: Session
    @State private var deleting: UUID?;@State private var renameID: UUID?;@State private var name=""
    var body: some View {NavigationStack{ScrollView{VStack(alignment:.leading,spacing:22){
        HStack{VStack(alignment:.leading,spacing:7){Text("Your next idea\nstarts here.").font(.system(size:30,weight:.medium));Text("A little studio. A world of possibilities.").font(.system(size:12)).foregroundStyle(Color.muted)};Spacer();Image(systemName:"square.grid.3x3").font(.system(size:42,weight:.ultraLight)).foregroundStyle(Color.mint)}.padding(.vertical,15)
        Button{session.sheet = .newProject}label:{Label("New project",systemImage:"plus").font(.system(size:15,weight:.semibold)).foregroundStyle(Color.ink).frame(maxWidth:.infinity,minHeight:52).background(Color.mint,in:RoundedRectangle(cornerRadius:12))}.buttonStyle(.plain)
        HStack{SmallHeading(text:"ON THIS IPHONE");Spacer();Text("\(session.entries.count) projects").font(.system(size:11)).foregroundStyle(Color.muted)}
        ForEach(session.entries){entry in
            if let p=entry.project {HStack(spacing:14){VStack(spacing:3){ForEach(0..<3){row in HStack(spacing:2){ForEach(0..<4){bar in RoundedRectangle(cornerRadius:1).fill((row==0 ? Color.harmony:row==1 ? Color.drums:Color.bass).opacity(row==2 && p.tracks.count<3 ? 0.08:0.6)).frame(width:8,height:row==0 ? 12:4)}}}}.frame(width:48,height:48).background(Color.raised,in:RoundedRectangle(cornerRadius:7))
                Button{Task{await session.open(p)}}label:{VStack(alignment:.leading,spacing:6){Text(p.name).font(.system(size:17,weight:.medium)).foregroundStyle(.white);Text("\(Int(p.bpm)) BPM · \(p.keyName) · \(p.length/barTicks) bars").font(.system(size:11)).foregroundStyle(Color.muted);Text(p.modified,style:.relative).font(.system(size:9)).foregroundStyle(Color.muted)}}.buttonStyle(.plain);Spacer();Menu{Button("Open"){Task{await session.open(p)}};Button("Rename"){renameID=p.id;name=p.name};Button("Duplicate"){Task{await session.duplicateProject(p)}};Button("Delete",role:.destructive){deleting=p.id}}label:{Image(systemName:"ellipsis").foregroundStyle(Color.muted).frame(width:44,height:44)}}.padding(.vertical,8).overlay(alignment:.bottom){Rectangle().fill(Color.raised).frame(height:1)}
            }else{VStack(alignment:.leading,spacing:8){Label("Project needs recovery",systemImage:"exclamationmark.triangle");Text(entry.error ?? "Could not read project").font(.caption).foregroundStyle(Color.muted);Button("Recover last working copy"){Task{await session.recover(entry.id)}}}.padding()}
        }
        if session.entries.isEmpty{Text("Start with chords or a beat.").foregroundStyle(Color.muted);Button("Listen to an example"){Task{await session.open(Project.demo());await session.save()}}}
    }.padding(22)}.background(Color.ink).navigationTitle("La Grilla").navigationBarTitleDisplayMode(.inline).toolbar{ToolbarItem(placement:.confirmationAction){Button("Done"){session.sheet=nil}}}}
    .task{await session.save()}
    .alert("Delete project?",isPresented:Binding(get:{deleting != nil},set:{if !$0{deleting=nil}})){Button("Delete",role:.destructive){if let id=deleting{Task{if id==session.project.id{await session.create(name:"Untitled",bpm:120,root:0,minor:false,bars:4)};if session.project.id != id{await session.delete(id)}}};deleting=nil};Button("Cancel",role:.cancel){deleting=nil}}message:{Text("This removes the project and its backup from this iPhone.")}
    .alert("Rename project",isPresented:Binding(get:{renameID != nil},set:{if !$0{renameID=nil}})){TextField("Name",text:$name);Button("Save"){if let id=renameID,let p=session.entries.first(where:{$0.id==id})?.project,!name.isEmpty{Task{if id==session.project.id{session.edit{$0.name=name};await session.save()}else{var copy=p;copy.name=name;do{try await session.store.save(copy);session.entries=try await session.store.list()}catch{session.message=error.localizedDescription}}}};renameID=nil};Button("Cancel",role:.cancel){renameID=nil}}
    }
}
struct NewProjectView: View {
    @Bindable var session: Session
    @State private var name = ""
    @State private var bpm = 120.0
    @State private var root = 0
    @State private var minor = false
    @State private var bars = 4
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Project name", text: $name)
                    Stepper("\(Int(bpm)) BPM", value: $bpm, in: 40...240)
                    Picker("Key", selection: $root) {
                        ForEach(0..<12, id: \.self) { i in Text(Chord.roots[i]).tag(i) }
                    }
                    Toggle("Minor", isOn: $minor)
                    Picker("Loop length", selection: $bars) {
                        ForEach([1,2,4,8], id: \.self) { n in Text("\(n) bars").tag(n) }
                    }
                }
                Section {
                    Text("All instruments are ready. No downloads, no account, just your next idea.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("New project")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { session.sheet = nil } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            session.loopBars = bars
                            await session.create(name: name, bpm: bpm, root: root, minor: minor, bars: bars)
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
