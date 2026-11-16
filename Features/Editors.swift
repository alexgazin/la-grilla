import SwiftUI
import UIKit
import MusicDomain
struct ChordEditor: View {
    @Bindable var session: Session; let selection: ChordSelection
    @AppStorage("studio.pitchSpelling") private var spellingValue = PitchSpelling.automatic.rawValue
    @AppStorage("studio.showDegrees") private var showDegrees = false
    private var spelling:PitchSpelling { PitchSpelling(rawValue:spellingValue) ?? .automatic }
    @Environment(\.dismiss) var dismiss
    @State private var duration=barTicks; @State private var chord=Chord(); @State private var text=""; @State private var error: String?
    @State private var family:ChordFamily = .basic
    @State private var formulaText=""
    private enum InputField:Hashable{case symbol,formula}
    @FocusState private var focusedField:InputField?
    var body: some View {
        NavigationStack{ScrollView{VStack(alignment:.leading,spacing:22){
            VStack(alignment:.leading,spacing:8){
                if chord.customIntervals != nil{HStack(alignment:.firstTextBaseline){Text(chordRootName).font(.system(size:42,weight:.medium));Text("Custom chord").font(.title3)}}else{Text(MusicalNotation.chordSymbol(chord,keyRoot:session.project.keyRoot,minor:session.project.minor,spelling:spelling)).accessibilityIdentifier("chord.display-symbol").font(.system(size:42,weight:.medium)).lineLimit(2).minimumScaleFactor(0.6)}
                if showDegrees{Text(MusicalNotation.degreeSymbol(chord,keyRoot:session.project.keyRoot,minor:session.project.minor)).font(.title3).accessibilityIdentifier("chord.degree")}
                Text(MusicalNotation.chordNoteNames(chord,keyRoot:session.project.keyRoot,minor:session.project.minor,spelling:spelling).joined(separator:" · ")).font(.system(.subheadline,design:.monospaced)).foregroundStyle(Color.muted).accessibilityIdentifier("chord.notes")
            }.foregroundStyle(Color.harmony)
            HStack{TextField("Chord symbol",text:$text).focused($focusedField,equals:.symbol).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder).frame(minHeight:44).onSubmit{parse()}.accessibilityIdentifier("chord.symbol");Button{parse()}label:{Text("Set").frame(minWidth:44,minHeight:44).contentShape(Rectangle())}.accessibilityIdentifier("chord.set-symbol")}
            if let error{Text(LocalizedStringKey(error)).font(.caption).foregroundStyle(Color.record).accessibilityIdentifier("chord.error")}
            SmallHeading(text:"ROOT")
            LazyVGrid(columns:Array(repeating:GridItem(.flexible()),count:6),spacing:8){ForEach(0..<12,id:\.self){root in Button{chord.root=root;chord.voicedNotes=nil;text=chord.symbol;error=nil}label:{Text(pitchName(root)).font(.system(.body,weight:.medium)).foregroundStyle(chord.root==root ? Color.ink:Color.harmony).frame(maxWidth:.infinity,minHeight:44).background(chord.root==root ? Color.harmony:Color.raised,in:RoundedRectangle(cornerRadius:8))}.buttonStyle(StudioQuietButtonStyle())}}
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
                Picker("Inversion",selection:Binding(get:{chord.inversion},set:{chord.inversion=$0;chord.voicedNotes=nil})){ForEach(0..<chord.effectiveIntervals.count,id:\.self){i in
                    if i==0{Text("Root position").tag(i)}else{Text("Inversion \(i)").tag(i)}
                }}
                    .labelsHidden().pickerStyle(.menu).frame(minHeight:44).contentShape(Rectangle()).accessibilityIdentifier("chord.inversion")
            }.frame(minHeight:44)
            HStack {
                Text("Slash bass")
                Spacer(minLength:8)
                Picker("Slash bass",selection:Binding(get:{chord.slashBass ?? -1},set:{chord.slashBass=$0<0 ? nil:$0;chord.voicedNotes=nil;text=chord.symbol})){Text("None").tag(-1);ForEach(0..<12,id:\.self){i in Text(pitchName(i)).tag(i)}}
                    .labelsHidden().pickerStyle(.menu).frame(minHeight:44).contentShape(Rectangle()).accessibilityIdentifier("chord.slash-bass")
            }.frame(minHeight:44)
            Stepper("Duration: \(duration/240) sixteenths",value:$duration,in:240...max(240,(session.project.patterns.first(where:{$0.id==selection.patternID})?.length ?? barTicks)-selection.tick),step:240).accessibilityIdentifier("chord.duration")
            HStack{Button{preview()}label:{Label("Preview",systemImage:"speaker.wave.2").frame(maxWidth:.infinity,minHeight:48).background(Color.raised,in:RoundedRectangle(cornerRadius:10))}.accessibilityIdentifier("chord.preview");Button{apply()}label:{Text("Apply").fontWeight(.semibold).foregroundStyle(Color.ink).frame(maxWidth:.infinity,minHeight:48).background(Color.harmony,in:RoundedRectangle(cornerRadius:10))}.accessibilityIdentifier("chord.apply")}.buttonStyle(StudioQuietButtonStyle())
        }.padding(22)}.background(Color.panel).navigationTitle("Edit chord").navigationBarTitleDisplayMode(.inline).toolbar{ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}}}}
        .onAppear{chord=selection.chord;text=chord.symbol;duration=selection.duration;family=chord.quality.family;formulaText=chord.effectiveIntervals.map(String.init).joined(separator:", ")}
    }
    private var chordRootName:String {spelling == .automatic ? (chord.rootSpelling ?? pitchName(chord.root)):pitchName(chord.root)}
    private func pitchName(_ value:Int)->String{MusicalNotation.pitchClassName(value,keyRoot:session.project.keyRoot,minor:session.project.minor,spelling:spelling)}
    func parse(){focusedField=nil;do{chord=try MusicalEditing.rebuildChord(from:text,preserving:chord);family=chord.quality.family;formulaText=chord.effectiveIntervals.map(String.init).joined(separator:", ");text=chord.symbol;error=nil}catch{self.error=error.localizedDescription}}
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
    @AppStorage("studio.pitchSpelling") private var spellingValue = PitchSpelling.automatic.rawValue
    @AppStorage("studio.showDegrees") private var showDegrees = false
    @Bindable var session: Session
    var body: some View {NavigationStack{Form{
        Section("App preferences"){
            Picker("Theme",selection:$appearance){Text("System").tag(0);Text("Light").tag(1);Text("Dark").tag(2)}.pickerStyle(.menu).accessibilityIdentifier("settings.theme")
            Button{if let url=URL(string:UIApplication.openSettingsURLString){UIApplication.shared.open(url)}}label:{Label("Language and permissions",systemImage:"arrow.up.forward.app")}.accessibilityIdentifier("settings.system")
            Text("Change this app’s language and permissions in iOS Settings. Available options depend on your device.").font(.caption).foregroundStyle(.secondary)
        }
        Section("Project tempo"){Stepper(value:Binding(get:{session.project.bpm},set:{v in session.edit{$0.bpm=v}}),in:40...240,step:1){Text("\(Int(session.project.bpm)) BPM").monospacedDigit()}.disabled(session.recording || session.armed)}
        Section("Project key"){
            Picker("Root",selection:Binding(get:{session.project.keyRoot},set:{v in session.edit{$0.keyRoot=v}})){ForEach(0..<12,id:\.self){i in Text(MusicalNotation.pitchClassName(i,keyRoot:session.project.keyRoot,minor:session.project.minor,spelling:PitchSpelling(rawValue:spellingValue) ?? .automatic)).tag(i)}}.accessibilityIdentifier("settings.key-root")
            Toggle("Minor",isOn:Binding(get:{session.project.minor},set:{v in session.edit{$0.minor=v}})).accessibilityIdentifier("settings.key-minor")
            Text("Changing the key updates suggestions. Existing notes stay as written.").font(.caption).foregroundStyle(.secondary)
            NavigationLink{TransposeEditor(session:session)}label:{Label("Transpose arrangement",systemImage:"arrow.up.arrow.down")}.accessibilityIdentifier("settings.transpose")
                .disabled(session.recording || session.armed || session.performance.contextActive)
        }
        Section("Musical notation"){
            Picker("Note names",selection:$spellingValue){Text("Auto (key)").tag(PitchSpelling.automatic.rawValue);Text("Sharps").tag(PitchSpelling.sharps.rawValue);Text("Flats").tag(PitchSpelling.flats.rawValue)}.accessibilityIdentifier("settings.pitch-spelling")
            Toggle("Show scale degrees",isOn:$showDegrees).accessibilityIdentifier("settings.show-degrees")
            Text("Names and degrees change the display, not the sound. Auto keeps the chord spelling you entered and otherwise follows the key. Minor degrees use the natural minor scale.").font(.caption).foregroundStyle(.secondary)
        }
        Section("Transport"){Toggle("Loop",isOn:Binding(get:{session.loop},set:{session.setLoop(enabled:$0)}));Picker("Loop length",selection:Binding(get:{session.loopBars},set:{session.setLoop(bars:$0)})){ForEach(session.loopLengthOptions,id:\.self){n in Text("\(n) bars").tag(n)}}}
        Section("MIDI"){Button("MIDI devices"){session.sheet = .midiDevices}}
        audioSettings
        Section("About La Grilla"){
            Button("Getting started"){session.sheet = .gettingStarted}.accessibilityIdentifier("settings.help")
            LabeledContent("Version",value:"\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""))")
            Link("Privacy policy",destination:URL(string:"https://github.com/alexgazin/la-grilla/blob/main/docs/privacy/"+(Locale.current.language.languageCode?.identifier=="ru" ? "ru":"en")+".md")!)
            Link("Support",destination:URL(string:"https://github.com/alexgazin/la-grilla/issues")!)
            Text("Projects and recordings stay on your iPhone. Portable project exports include their original voice recordings.").font(.caption).foregroundStyle(.secondary)
        }

    }.navigationTitle("Settings").toolbar{ToolbarItem(placement:.confirmationAction){Button("Done"){session.sheet=nil}}}}
        // A presented Form owns its appearance boundary. Apply the observed
        // preference here as well as to the window so live changes update the
        // current sheet, rather than only its presenter or the next opening.
        .preferredColorScheme(appearance==1 ? .light:appearance==2 ? .dark:nil)
        .presentationDetents([.medium,.large])}
    private var audioSettings:some View {
        Section("Audio"){
            LabeledContent("Sample rate",value:"\(Int(session.audio.sampleRate)) Hz")
            Text("Wireless headphones add latency. For live pads, use the speaker or wired audio.").font(.caption).foregroundStyle(.secondary)
            if !session.audio.failureReport.isEmpty {
                ShareLink(item:audioDiagnosticReport){
                    Label("Share audio diagnostics",systemImage:"square.and.arrow.up").frame(minHeight:44)
                }.accessibilityIdentifier("settings.audio-diagnostics")
                Text("Includes audio route types and error codes, never recordings.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var audioDiagnosticReport:String {
        let version=Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let build=Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        let heading=NSLocalizedString("Audio diagnostics",comment:"Audio support")
        return "La Grilla \(version) (\(build)) · iOS \(UIDevice.current.systemVersion)\n\(heading)\n\(session.audio.failureReport)"
    }
}
struct BassView: View {
    @Bindable var session: Session
    var enabled:Bool{session.project.tracks.contains(where:{$0.role == .bass})}
    private var editingLocked:Bool{session.performance.contextActive || session.recording || session.armed}
    private var bassEnabled:Binding<Bool>{Binding(get:{enabled},set:{on in
        guard on != enabled else{return}
        session.edit{project in
            if on{guard project.tracks.count<8 else{throw MusicError.trackLimit};project.tracks.append(Track(role:.bass))}
            else if let id=project.tracks.first(where:{$0.role == .bass})?.id{try project.deleteTrack(id)}
        }
    })}
    var body:some View {NavigationStack{Form{
        Section {
            HStack {
                Text("Root bass")
                Spacer()
                // Keep the platform switch's hit region independent of the
                // Form cell and its descriptive/status rows on iOS 26.
                RootBassSwitch(isOn:bassEnabled,enabled:!editingLocked).frame(width:64,height:48)
            }
            Text("Bass follows the roots of your chords.").foregroundStyle(.secondary).font(.caption)
            Text(LocalizedStringKey(session.audio.playing ? "PLAYING":"STOPPED")).font(.caption.monospaced()).foregroundStyle(Color.muted).accessibilityIdentifier("bass.playback-state")
        }
        if enabled {Section{
            Picker("Register",selection:Binding(get:{session.project.bassOctave},set:{v in session.edit{try MusicalEditing.setBassRegister(v,in:&$0)}})){Text("Low").tag(-1);Text("Natural").tag(0);Text("High").tag(1)}
            HStack{Text("Gate");Slider(value:Binding(get:{session.project.bassGate},set:{v in session.edit{$0.bassGate=v}}),in:0.1...1).accessibilityLabel("Bass gate");Text("\(Int(session.project.bassGate*100))%").monospacedDigit()}
        }.disabled(editingLocked)}
    }.tint(.bass).navigationTitle("Bass").toolbar{ToolbarItem(placement:.confirmationAction){Button("Done"){session.sheet=nil}}}}.presentationDetents([.medium])}
}

/// The native switch owns its inner frame; its host owns only the surrounding
/// padding. Both paths emit one native valueChanged event. The actual 64×48 host
/// remains a 44pt screen target after the system sheet's scale.
@MainActor private struct RootBassSwitch:UIViewRepresentable {
    @Binding var isOn:Bool
    let enabled:Bool
    func makeUIView(context:Context)->RootBassSwitchHost {
        let host=RootBassSwitchHost()
        host.control.addTarget(context.coordinator,action:#selector(Coordinator.changed(_:)),for:.valueChanged)
        return host
    }
    func updateUIView(_ host:RootBassSwitchHost,context:Context){
        context.coordinator.value=$isOn
        let control=host.control
        control.isEnabled=enabled && context.environment.isEnabled
        host.isUserInteractionEnabled=control.isEnabled
        control.accessibilityIdentifier="bass.enabled"
        control.accessibilityLabel=NSLocalizedString("Root bass",comment:"Bass switch")
        control.onTintColor=UIColor(Color.bass)
        if control.isOn != isOn{control.setOn(isOn,animated:control.window != nil)}
    }
    func makeCoordinator()->Coordinator{Coordinator(value:$isOn)}
    func sizeThatFits(_ proposal:ProposedViewSize,uiView:RootBassSwitchHost,context:Context)->CGSize?{CGSize(width:64,height:48)}
    static func dismantleUIView(_ uiView:RootBassSwitchHost,coordinator:Coordinator){uiView.control.removeTarget(coordinator,action:#selector(Coordinator.changed(_:)),for:.valueChanged)}
    @MainActor final class Coordinator:NSObject {
        var value:Binding<Bool>
        init(value:Binding<Bool>){self.value=value}
        @objc func changed(_ sender:UISwitch){
            value.wrappedValue=sender.isOn
            // A source-edit guard may reject a change. Reflect the authoritative
            // project value without emitting a second valueChanged event.
            if sender.isOn != value.wrappedValue{sender.setOn(value.wrappedValue,animated:true)}
        }
    }
}

@MainActor private final class RootBassSwitchHost:UIView,UIGestureRecognizerDelegate {
    let control=RootBassUISwitch()
    override init(frame:CGRect){
        super.init(frame:frame)
        isAccessibilityElement=false
        addSubview(control);control.hitAreaHost=self;control.isAccessibilityElement=true
        accessibilityElements=[control]
        let padding=UITapGestureRecognizer(target:self,action:#selector(paddingTapped(_:)))
        padding.delegate=self;padding.cancelsTouchesInView=false;addGestureRecognizer(padding)
    }
    required init?(coder:NSCoder){fatalError("init(coder:) is unavailable")}
    override var intrinsicContentSize:CGSize{CGSize(width:64,height:48)}
    override func layoutSubviews(){
        super.layoutSubviews();control.sizeToFit();control.center=CGPoint(x:bounds.midX,y:bounds.midY)
    }
    override func hitTest(_ point:CGPoint,with event:UIEvent?)->UIView? {
        guard isUserInteractionEnabled,!isHidden,alpha>0.01,bounds.contains(point)else{return nil}
        if control.frame.contains(point){return control.hitTest(convert(point,to:control),with:event) ?? control}
        return self
    }
    func gestureRecognizer(_ gestureRecognizer:UIGestureRecognizer,shouldReceive touch:UITouch)->Bool {
        // A touch dispatched to the native switch is never handled a second
        // time by its ancestor's padding recognizer.
        control.isEnabled && !control.frame.contains(touch.location(in:self))
    }
    @objc private func paddingTapped(_ gesture:UITapGestureRecognizer){
        guard gesture.state == .ended,control.isEnabled else{return}
        control.setOn(!control.isOn,animated:true)
        control.sendActions(for:.valueChanged)
    }
}

@MainActor private final class RootBassUISwitch:UISwitch {
    weak var hitAreaHost:RootBassSwitchHost?
    override var accessibilityFrame:CGRect {
        get{guard let host=hitAreaHost,host.window != nil else{return super.accessibilityFrame};return UIAccessibility.convertToScreenCoordinates(host.bounds,in:host)}
        set{super.accessibilityFrame=newValue}
    }
}

struct SectionsView: View {
    @Bindable var session: Session
    @State private var editing: UUID?
    @State private var name=""
    @State private var deleting:UUID?
    @State private var actions:MusicDomain.Section?
    @State private var pendingRename:UUID?
    @State private var pendingDelete:UUID?
    var body:some View {NavigationStack{List{
        Section{ForEach(session.project.sections){section in
            HStack {
                VStack(alignment:.leading,spacing:5){Text(section.name);Text("Bars \(section.start/barTicks+1)–\((section.start+section.length)/barTicks)").font(.caption).foregroundStyle(.secondary)}
                Spacer()
                Button{actions=section}label:{Image(systemName:"ellipsis").frame(width:44,height:44)}
                    .buttonStyle(.borderless).disabled(editingLocked).accessibilityLabel(section.name).accessibilityIdentifier("section.menu.\(section.id)")
            }
        }}
        Section{Text("Duplicated sections have independent chords and drums. Up to 8 sections and 64 bars.").font(.caption).foregroundStyle(.secondary);Text(LocalizedStringKey(session.audio.playing ? "PLAYING":"STOPPED")).font(.caption.monospaced()).foregroundStyle(Color.muted).accessibilityIdentifier("section.playback-state")}
    }.navigationTitle("Song sections").toolbar{ToolbarItem(placement:.confirmationAction){Button("Done"){session.sheet=nil}}}}
        .sheet(item:$actions,onDismiss:finishAction){section in actionList(section)}
        .alert("Rename section",isPresented:Binding(get:{editing != nil},set:{if !$0{editing=nil}})){
            TextField("Name",text:$name)
            Button("Save"){let value=String(name.trimmingCharacters(in:.whitespacesAndNewlines).prefix(120));if let id=editing,!value.isEmpty{session.edit{p in if let i=p.sections.firstIndex(where:{$0.id==id}){p.sections[i].name=value}}};editing=nil}
            Button("Cancel",role:.cancel){editing=nil}
        }
        .alert("Delete section?",isPresented:Binding(get:{deleting != nil},set:{if !$0{deleting=nil}})) {
            Button("Delete",role:.destructive){if let id=deleting{session.edit{try SectionEditing.delete(id,in:&$0)}};deleting=nil}
            Button("Cancel",role:.cancel){deleting=nil}
        } message: {Text("The following sections move earlier. You can undo this change.")}
    }
    private var editingLocked:Bool{session.performance.contextActive || session.recording || session.armed}
    private func actionList(_ section:MusicDomain.Section)->some View {NavigationStack{List{
        Button("Rename"){pendingRename=section.id;actions=nil}
        Button("Duplicate"){session.edit{try SectionEditing.duplicate(section.id,name:section.name=="Verse" ? "Chorus":String((section.name+" copy").prefix(120)),in:&$0)};actions=nil}
            .disabled(session.project.sections.count>=8 || session.project.length+section.length>64*barTicks).accessibilityIdentifier("section.duplicate")
        Button("Move earlier"){move(section.id,by:-1);actions=nil}.disabled(session.project.sections.first?.id==section.id).accessibilityIdentifier("section.earlier")
        Button("Move later"){move(section.id,by:1);actions=nil}.disabled(session.project.sections.last?.id==section.id).accessibilityIdentifier("section.later")
        if session.project.sections.count>1{Button("Delete section",role:.destructive){pendingDelete=section.id;actions=nil}.accessibilityIdentifier("section.delete")}
    }.environment(\.defaultMinListRowHeight,52).disabled(editingLocked).navigationTitle(section.name).navigationBarTitleDisplayMode(.inline)
        .toolbar{ToolbarItem(placement:.cancellationAction){Button("Cancel"){actions=nil}}}}
        .presentationDetents([.medium,.large]).tint(.mint)
    }
    private func finishAction(){
        if let id=pendingRename,let section=session.project.sections.first(where:{$0.id==id}){name=section.name;editing=id}
        if let id=pendingDelete,session.project.sections.contains(where:{$0.id==id}){deleting=id}
        pendingRename=nil;pendingDelete=nil
    }
    func move(_ id:UUID,by delta:Int){
        guard let index=session.project.sections.firstIndex(where:{$0.id==id}),session.project.sections.indices.contains(index+delta)else{return}
        let token=ArrangementDragPayload(project:session.project,sectionID:id),target=session.project.sections[index+delta].id
        session.edit{try ClipEditing.reorderSection(token,to:target,in:&$0)}
    }
}
