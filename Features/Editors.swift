import SwiftUI
import MusicDomain
struct ChordEditor: View {
    @Bindable var session: Session; let selection: ChordSelection
    @Environment(\.dismiss) var dismiss
    @State private var duration=barTicks; @State private var chord=Chord(); @State private var text=""; @State private var error: String?
    @State private var family:ChordFamily = .basic
    @State private var formulaText=""
    private enum InputField:Hashable{case symbol,formula}
    @FocusState private var focusedField:InputField?
    var body: some View {
        NavigationStack{ScrollView{VStack(alignment:.leading,spacing:22){
            VStack(alignment:.leading,spacing:8){
                if chord.customIntervals != nil{HStack(alignment:.firstTextBaseline){Text(Chord.roots[chord.root]).font(.system(size:42,weight:.medium));Text("Custom chord").font(.title3)}}else{Text(chord.symbol).font(.system(size:42,weight:.medium)).lineLimit(2).minimumScaleFactor(0.6)}
                Text(chord.notes.map{NoteEvent(tick:0,pitch:$0).name}.joined(separator:" · ")).font(.system(.subheadline,design:.monospaced)).foregroundStyle(Color.muted).accessibilityIdentifier("chord.notes")
            }.foregroundStyle(Color.harmony)
            HStack{TextField("Chord symbol",text:$text).focused($focusedField,equals:.symbol).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder).frame(minHeight:44).onSubmit{parse()}.accessibilityIdentifier("chord.symbol");Button{parse()}label:{Text("Set").frame(minWidth:44,minHeight:44).contentShape(Rectangle())}.accessibilityIdentifier("chord.set-symbol")}
            if let error{Text(LocalizedStringKey(error)).font(.caption).foregroundStyle(Color.record).accessibilityIdentifier("chord.error")}
            SmallHeading(text:"ROOT")
            LazyVGrid(columns:Array(repeating:GridItem(.flexible()),count:6),spacing:8){ForEach(0..<12,id:\.self){root in Button{chord.root=root;chord.voicedNotes=nil;text=chord.symbol;error=nil}label:{Text(Chord.roots[root]).font(.system(.body,weight:.medium)).foregroundStyle(chord.root==root ? Color.ink:Color.harmony).frame(maxWidth:.infinity,minHeight:44).background(chord.root==root ? Color.harmony:Color.raised,in:RoundedRectangle(cornerRadius:8))}.buttonStyle(StudioQuietButtonStyle())}}
            SmallHeading(text:"QUALITY")
            Toggle("Custom intervals",isOn:Binding(get:{chord.customIntervals != nil},set:{enabled in chord.customIntervals=enabled ? chord.quality.intervals:nil;if enabled{chord.quality = .major};chord.inversion=0;chord.voicedNotes=nil;formulaText=chord.effectiveIntervals.map(String.init).joined(separator:", ");text=chord.symbol;error=nil})).accessibilityIdentifier("chord.custom")
            if chord.customIntervals != nil {
                TextField("0, 4, 7, 10, 14",text:$formulaText).focused($focusedField,equals:.formula).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.numbersAndPunctuation).textFieldStyle(.roundedBorder).onSubmit{setFormula()}.accessibilityLabel("Semitone offsets").accessibilityIdentifier("chord.formula")
                Text("Use 2–8 increasing semitone offsets from 0 to 48, starting with 0. Every custom tone is preserved.").font(.caption).foregroundStyle(Color.muted)
                Button("Set formula"){setFormula()}.frame(minHeight:44).accessibilityIdentifier("chord.set-formula")
            }else{
                Picker("Chord family",selection:$family){ForEach(ChordFamily.allCases,id:\.self){value in Text(LocalizedStringKey(value.rawValue)).tag(value)}}.pickerStyle(.menu).frame(minHeight:44)
                LazyVGrid(columns:Array(repeating:GridItem(.flexible()),count:4),spacing:8){ForEach(Quality.allCases.filter{$0.family==family},id:\.rawValue){q in Button{chord.quality=q;chord.inversion=0;chord.voicedNotes=nil;text=chord.symbol;error=nil}label:{Text(q.label).font(.system(.caption,weight:.medium)).foregroundStyle(chord.quality==q ? Color.ink:Color.harmony).frame(maxWidth:.infinity,minHeight:44).background(chord.quality==q ? Color.harmony:Color.raised,in:RoundedRectangle(cornerRadius:8))}.buttonStyle(StudioQuietButtonStyle())}}
            }
            HStack {
                Text("Inversion")
                Spacer(minLength:8)
                Picker("Inversion",selection:Binding(get:{chord.inversion},set:{chord.inversion=$0;chord.voicedNotes=nil})){ForEach(0..<chord.effectiveIntervals.count,id:\.self){i in Text(LocalizedStringKey(i==0 ? "Root position":"Inversion \(i)")).tag(i)}}
                    .labelsHidden().pickerStyle(.menu).frame(minHeight:44).contentShape(Rectangle()).accessibilityIdentifier("chord.inversion")
            }.frame(minHeight:44)
            HStack {
                Text("Slash bass")
                Spacer(minLength:8)
                Picker("Slash bass",selection:Binding(get:{chord.slashBass ?? -1},set:{chord.slashBass=$0<0 ? nil:$0;chord.voicedNotes=nil;text=chord.symbol})){Text("None").tag(-1);ForEach(0..<12,id:\.self){i in Text(Chord.roots[i]).tag(i)}}
                    .labelsHidden().pickerStyle(.menu).frame(minHeight:44).contentShape(Rectangle()).accessibilityIdentifier("chord.slash-bass")
            }.frame(minHeight:44)
            Stepper("Duration: \(duration/240) sixteenths",value:$duration,in:240...max(240,(session.project.patterns.first(where:{$0.id==selection.patternID})?.length ?? barTicks)-selection.tick),step:240)
            HStack{Button{preview()}label:{Label("Preview",systemImage:"speaker.wave.2").frame(maxWidth:.infinity,minHeight:48).background(Color.raised,in:RoundedRectangle(cornerRadius:10))}.accessibilityIdentifier("chord.preview");Button{apply()}label:{Text("Apply").fontWeight(.semibold).foregroundStyle(Color.ink).frame(maxWidth:.infinity,minHeight:48).background(Color.harmony,in:RoundedRectangle(cornerRadius:10))}.accessibilityIdentifier("chord.apply")}.buttonStyle(StudioQuietButtonStyle())
        }.padding(22)}.background(Color.panel).navigationTitle("Edit chord").navigationBarTitleDisplayMode(.inline).toolbar{ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}}}}
        .onAppear{chord=selection.chord;text=chord.symbol;duration=selection.duration;family=chord.quality.family;formulaText=chord.effectiveIntervals.map(String.init).joined(separator:", ")}
    }
    func parse(){focusedField=nil;do{chord=try Chord.parse(text);family=chord.quality.family;formulaText=chord.effectiveIntervals.map(String.init).joined(separator:", ");text=chord.symbol;error=nil}catch{self.error=error.localizedDescription}}
    @discardableResult func setFormula()->Bool{focusedField=nil;do{let formula=try Chord.parseCustomIntervals(formulaText);var candidate=chord;candidate.customIntervals=formula;candidate.quality = .major;candidate.inversion=0;candidate.voicedNotes=nil;try candidate.validate();chord=candidate;formulaText=chord.effectiveIntervals.map(String.init).joined(separator:", ");text=chord.symbol;error=nil;return true}catch{self.error=error.localizedDescription;return false}}
    func prepared()->Bool{
        if text != chord.symbol{parse();if error != nil{return false}}
        if chord.customIntervals != nil,formulaText != chord.effectiveIntervals.map(String.init).joined(separator:", "),!setFormula(){return false}
        do{try chord.validate();error=nil;return true}catch{self.error=error.localizedDescription;return false}
    }
    func preview(){guard prepared()else{return};if session.ensureAudio(){session.audio.preview(chord)}}
    func apply(){
        guard prepared()else{return}
        guard session.project.patterns.contains(where:{$0.id==selection.patternID})else{error=HarmonyError.stale.localizedDescription;return}
        let revision=session.project.revision
        session.edit{p in guard let i=p.patterns.firstIndex(where:{$0.id==selection.patternID})else{throw HarmonyError.stale};p.patterns[i].chords.removeAll(where:{$0.tick<selection.tick+duration && $0.tick+$0.duration>selection.tick});p.patterns[i].chords.append(ChordEvent(tick:selection.tick,duration:duration,chord:chord))}
        if session.project.revision>revision{dismiss()}
    }
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
        Section("About La Grilla"){
            LabeledContent("Version",value:"\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""))")
            Link("Privacy policy",destination:URL(string:"https://github.com/alexgazin/la-grilla/blob/main/docs/privacy/"+(Locale.current.language.languageCode?.identifier=="ru" ? "ru":"en")+".md")!)
            Link("Support",destination:URL(string:"https://github.com/alexgazin/la-grilla/issues")!)
            Text("Projects and recordings stay on your iPhone. Portable project exports include their original voice recordings.").font(.caption).foregroundStyle(.secondary)
        }

    }.navigationTitle("Project settings").toolbar{ToolbarItem(placement:.confirmationAction){Button("Done"){session.sheet=nil}}}}.presentationDetents([.medium,.large])}
}
struct BassView: View {
    @Bindable var session: Session
    var enabled: Bool{session.project.tracks.contains(where:{$0.role == .bass})}
    var body: some View {NavigationStack{Form{
        Section{Toggle("Root bass",isOn:Binding(get:{enabled},set:{on in session.edit{p in if on{guard p.tracks.count<8 else{throw MusicError.trackLimit};p.tracks.append(Track(role:.bass))}else{if let id=p.tracks.first(where:{$0.role == .bass})?.id{try p.deleteTrack(id)}}}})).disabled(session.performance.contextActive || session.recording || session.armed).accessibilityIdentifier("bass.enabled");Text("Bass follows the roots of your chords.").foregroundStyle(.secondary).font(.caption);Text(LocalizedStringKey(session.audio.playing ? "PLAYING":"STOPPED")).font(.caption.monospaced()).foregroundStyle(Color.muted).accessibilityIdentifier("bass.playback-state")}
        if enabled {Section{Picker("Register",selection:Binding(get:{session.project.bassOctave},set:{v in session.edit{$0.bassOctave=v}})){Text("Low").tag(-1);Text("Natural").tag(0);Text("High").tag(1)};HStack{Text("Gate");Slider(value:Binding(get:{session.project.bassGate},set:{v in session.edit{$0.bassGate=v}}),in:0.1...1).accessibilityLabel("Bass gate");Text("\(Int(session.project.bassGate*100))%").monospacedDigit()}}}
    }.tint(.bass).navigationTitle("Bass").toolbar{ToolbarItem(placement:.confirmationAction){Button("Done"){session.sheet=nil}}}}.presentationDetents([.medium])}
}
struct SectionsView: View {
    @Bindable var session: Session
    @State private var editing: UUID?;@State private var name="";@State private var deleting: UUID?
    var body: some View {NavigationStack{List{
        Section{ForEach(session.project.sections){s in HStack{VStack(alignment:.leading,spacing:5){Text(s.name);Text("Bars \(s.start/barTicks+1)–\((s.start+s.length)/barTicks)").font(.caption).foregroundStyle(.secondary)};Spacer();Menu{Button("Rename"){name=s.name;editing=s.id};Button("Duplicate"){session.edit{try SectionEditing.duplicate(s.id,name:s.name=="Verse" ? "Chorus":String((s.name+" copy").prefix(120)),in:&$0)}}.disabled(session.project.sections.count>=8 || session.project.length+s.length>64*barTicks).accessibilityIdentifier("section.duplicate");Button("Move earlier"){move(s.id,by:-1)}.disabled(session.project.sections.first?.id==s.id).accessibilityIdentifier("section.earlier");Button("Move later"){move(s.id,by:1)}.disabled(session.project.sections.last?.id==s.id).accessibilityIdentifier("section.later");if session.project.sections.count>1{Button("Delete section",role:.destructive){deleting=s.id}.accessibilityIdentifier("section.delete")}}label:{Image(systemName:"ellipsis").frame(width:44,height:44)}.disabled(session.performance.contextActive || session.recording || session.armed).accessibilityLabel(s.name).accessibilityIdentifier("section.menu.\(s.id)")}}}
        Section{Text("Duplicated sections have independent chords and drums. Up to 8 sections and 64 bars.").font(.caption).foregroundStyle(.secondary);Text(LocalizedStringKey(session.audio.playing ? "PLAYING":"STOPPED")).font(.caption.monospaced()).foregroundStyle(Color.muted).accessibilityIdentifier("section.playback-state")}
    }.navigationTitle("Song sections").toolbar{ToolbarItem(placement:.confirmationAction){Button("Done"){session.sheet=nil}}}}
        .alert("Rename section",isPresented:Binding(get:{editing != nil},set:{if !$0{editing=nil}})){TextField("Name",text:$name);Button("Save"){let value=String(name.trimmingCharacters(in:.whitespacesAndNewlines).prefix(120));if let id=editing,!value.isEmpty{session.edit{p in if let i=p.sections.firstIndex(where:{$0.id==id}){p.sections[i].name=value}}};editing=nil};Button("Cancel",role:.cancel){editing=nil}}
        .alert("Delete section?",isPresented:Binding(get:{deleting != nil},set:{if !$0{deleting=nil}})) {
            Button("Delete",role:.destructive){if let id=deleting{session.edit{try SectionEditing.delete(id,in:&$0)}};deleting=nil}
            Button("Cancel",role:.cancel){deleting=nil}
        } message: {Text("The following sections move earlier. You can undo this change.")}
    }
    func move(_ id:UUID,by delta:Int){
        guard let index=session.project.sections.firstIndex(where:{$0.id==id}),session.project.sections.indices.contains(index+delta)else{return}
        let token=ArrangementDragPayload(project:session.project,sectionID:id),target=session.project.sections[index+delta].id
        session.edit{try ClipEditing.reorderSection(token,to:target,in:&$0)}
    }
}
