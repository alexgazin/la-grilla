import SwiftUI
import MusicDomain
struct ChordEditor: View {
    @Bindable var session: Session; let selection: ChordSelection
    @Environment(\.dismiss) var dismiss
    @State private var duration=barTicks; @State private var chord=Chord(); @State private var text=""; @State private var error: String?
    var body: some View {
        NavigationStack{ScrollView{VStack(alignment:.leading,spacing:22){
            HStack(alignment:.firstTextBaseline){Text(chord.symbol).font(.system(size:42,weight:.medium)).foregroundStyle(Color.harmony);Spacer();Text(chord.notes.map(String.init).joined(separator:" · ")).font(.system(.subheadline,design:.monospaced)).foregroundStyle(Color.muted)}
            HStack{TextField("Chord symbol",text:$text).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder).onSubmit{parse()};Button("Set"){parse()}}
            if let error{Text(LocalizedStringKey(error)).font(.caption).foregroundStyle(Color.record)}
            SmallHeading(text:"ROOT")
            LazyVGrid(columns:Array(repeating:GridItem(.flexible()),count:6),spacing:8){ForEach(0..<12,id:\.self){root in Button{chord.root=root;chord.voicedNotes=nil;text=chord.symbol;error=nil}label:{Text(Chord.roots[root]).font(.system(.body,weight:.medium)).foregroundStyle(chord.root==root ? Color.ink:Color.harmony).frame(maxWidth:.infinity,minHeight:44).background(chord.root==root ? Color.harmony:Color.raised,in:RoundedRectangle(cornerRadius:8))}.buttonStyle(.plain)}}
            SmallHeading(text:"QUALITY")
            LazyVGrid(columns:Array(repeating:GridItem(.flexible()),count:4),spacing:8){ForEach(Quality.allCases,id:\.rawValue){q in Button{chord.quality=q;chord.inversion=0;chord.voicedNotes=nil;text=chord.symbol;error=nil}label:{Text(q.label).font(.system(.caption,weight:.medium)).foregroundStyle(chord.quality==q ? Color.ink:Color.harmony).frame(maxWidth:.infinity,minHeight:44).background(chord.quality==q ? Color.harmony:Color.raised,in:RoundedRectangle(cornerRadius:8))}.buttonStyle(.plain)}}
            Picker("Inversion",selection:Binding(get:{chord.inversion},set:{chord.inversion=$0;chord.voicedNotes=nil})){ForEach(0..<chord.quality.intervals.count,id:\.self){i in Text(LocalizedStringKey(i==0 ? "Root position":"Inversion \(i)")).tag(i)}}.pickerStyle(.menu)
            Picker("Slash bass",selection:Binding(get:{chord.slashBass ?? -1},set:{chord.slashBass=$0<0 ? nil:$0;chord.voicedNotes=nil;text=chord.symbol})){Text("None").tag(-1);ForEach(0..<12,id:\.self){i in Text(Chord.roots[i]).tag(i)}}.pickerStyle(.menu)
            Stepper("Duration: \(duration/240) sixteenths",value:$duration,in:240...max(240,(session.project.patterns.first(where:{$0.id==selection.patternID})?.length ?? barTicks)-selection.tick),step:240)
            HStack{Button{if session.ensureAudio(){session.audio.preview(chord)}}label:{Label("Preview",systemImage:"speaker.wave.2").frame(maxWidth:.infinity,minHeight:48).background(Color.raised,in:RoundedRectangle(cornerRadius:10))};Button{apply()}label:{Text("Apply").fontWeight(.semibold).foregroundStyle(Color.ink).frame(maxWidth:.infinity,minHeight:48).background(Color.harmony,in:RoundedRectangle(cornerRadius:10))}}.buttonStyle(.plain)
        }.padding(22)}.background(Color.panel).navigationTitle("Edit chord").navigationBarTitleDisplayMode(.inline).toolbar{ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}}}}
        .onAppear{chord=selection.chord;text=chord.symbol;duration=selection.duration}
    }
    func parse(){do{chord=try Chord.parse(text);error=nil}catch{self.error=error.localizedDescription}}
    func apply(){if text != chord.symbol{do{chord=try Chord.parse(text)}catch{self.error=error.localizedDescription;return}};session.edit{p in guard let i=p.patterns.firstIndex(where:{$0.id==selection.patternID})else{return};p.patterns[i].chords.removeAll(where:{$0.tick<selection.tick+duration && $0.tick+$0.duration>selection.tick});p.patterns[i].chords.append(ChordEvent(tick:selection.tick,duration:duration,chord:chord))};dismiss()}
}
struct SettingsView: View {
    @AppStorage("studio.appearance") private var appearance=0
    @Bindable var session: Session
    var body: some View {NavigationStack{Form{
        Section("Appearance"){Picker("Theme",selection:$appearance){Text("System").tag(0);Text("Light").tag(1);Text("Dark").tag(2)}}
        Section("Tempo"){Stepper(value:Binding(get:{session.project.bpm},set:{v in session.edit{$0.bpm=v}}),in:40...240,step:1){Text("\(Int(session.project.bpm)) BPM").monospacedDigit()}.disabled(session.recording || session.armed)}
        Section("Key"){Picker("Root",selection:Binding(get:{session.project.keyRoot},set:{v in session.edit{$0.keyRoot=v}})){ForEach(0..<12,id:\.self){i in Text(Chord.roots[i]).tag(i)}};Toggle("Minor",isOn:Binding(get:{session.project.minor},set:{v in session.edit{$0.minor=v}}));Text("Changing the key updates suggestions. Existing notes stay as written.").font(.caption).foregroundStyle(.secondary)}
        Section("Transport"){Toggle("Loop",isOn:Binding(get:{session.loop},set:{session.setLoop(enabled:$0)}));Picker("Loop length",selection:Binding(get:{session.loopBars},set:{session.setLoop(bars:$0)})){ForEach([1,2,4,8],id:\.self){n in Text("\(n) bars").tag(n)}}}
        Section("MIDI"){Button("MIDI devices"){session.sheet = .midiDevices}}
        Section("Audio"){LabeledContent("Sample rate",value:"\(Int(session.audio.sampleRate)) Hz");Text("Wireless headphones add latency. For live pads, use the speaker or wired audio.").font(.caption).foregroundStyle(.secondary)}
    }.navigationTitle("Project settings").toolbar{ToolbarItem(placement:.confirmationAction){Button("Done"){session.sheet=nil}}}}.presentationDetents([.medium,.large])}
}
struct BassView: View {
    @Bindable var session: Session
    var enabled: Bool{session.project.tracks.contains(where:{$0.role == .bass})}
    var body: some View {NavigationStack{Form{
        Section{Toggle("Root bass",isOn:Binding(get:{enabled},set:{on in session.edit{p in if on{p.tracks.append(Track(role:.bass))}else{if let id=p.tracks.first(where:{$0.role == .bass})?.id{try p.deleteTrack(id)}}}}));Text("Bass follows the roots of your chords.").foregroundStyle(.secondary).font(.caption)}
        if enabled {Section{Picker("Register",selection:Binding(get:{session.project.bassOctave},set:{v in session.edit{$0.bassOctave=v}})){Text("Low").tag(-1);Text("Natural").tag(0);Text("High").tag(1)};HStack{Text("Gate");Slider(value:Binding(get:{session.project.bassGate},set:{v in session.edit{$0.bassGate=v}}),in:0.1...1).accessibilityLabel("Bass gate");Text("\(Int(session.project.bassGate*100))%").monospacedDigit()}}}
    }.tint(.bass).navigationTitle("Bass").toolbar{ToolbarItem(placement:.confirmationAction){Button("Done"){session.sheet=nil}}}}.presentationDetents([.medium])}
}
struct SectionsView: View {
    @Bindable var session: Session
    @State private var editing: UUID?;@State private var name="";@State private var stopPrompt=false;@State private var deleting: UUID?
    var body: some View {NavigationStack{List{
        Section{ForEach(session.project.sections){s in HStack{VStack(alignment:.leading,spacing:5){Text(s.name);Text("Bars \(s.start/barTicks+1)–\((s.start+s.length)/barTicks)").font(.caption).foregroundStyle(.secondary)};Spacer();Menu{Button("Rename"){name=s.name;editing=s.id};Button("Duplicate"){structural{session.edit{try $0.duplicateSection(s.id,name:s.name=="Verse" ? "Chorus":s.name+" copy")}}};Button("Move earlier"){structural{session.edit{try $0.moveSection(s.id,by:-1)}}};Button("Move later"){structural{session.edit{try $0.moveSection(s.id,by:1)}}};if session.project.sections.count>1{Button("Delete section",role:.destructive){deleting=s.id}}}label:{Image(systemName:"ellipsis").frame(width:44,height:44)}}}}
        Section{Text("Duplicated sections have independent chords and drums. Up to 8 sections and 64 bars.").font(.caption).foregroundStyle(.secondary)}
    }.navigationTitle("Song sections").toolbar{ToolbarItem(placement:.confirmationAction){Button("Done"){session.sheet=nil}}}}
        .alert("Rename section",isPresented:Binding(get:{editing != nil},set:{if !$0{editing=nil}})){TextField("Name",text:$name);Button("Save"){if let id=editing,!name.trimmingCharacters(in:.whitespaces).isEmpty{session.edit{p in if let i=p.sections.firstIndex(where:{$0.id==id}){p.sections[i].name=name}}};editing=nil};Button("Cancel",role:.cancel){editing=nil}}
        .alert("Delete section?",isPresented:Binding(get:{deleting != nil},set:{if !$0{deleting=nil}})) {
            Button("Delete",role:.destructive){if let id=deleting{structural{session.edit{try $0.deleteSection(id)}}};deleting=nil}
            Button("Cancel",role:.cancel){deleting=nil}
        } message: {Text("The following sections move earlier. You can undo this change.")}
        .alert("Stop playback first",isPresented:$stopPrompt){Button("Stop"){session.rewind()};Button("Cancel",role:.cancel){}}message:{Text("Stop the transport, then change the song structure.")}
    }
    func structural(_ action:()->Void){if session.audio.playing{stopPrompt=true}else{action()}}
}
