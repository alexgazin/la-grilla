import SwiftUI
import UIKit
import MusicDomain
import UniformTypeIdentifiers
struct ChordEditor: View {
    @Bindable var session: Session; let selection: ChordSelection
    /// The chord just before this one in its pattern (for I16's root-motion note).
    private var previousChord:Chord?{session.project.patterns.first{$0.id==selection.patternID}?.chords.filter{$0.tick<selection.tick}.max{$0.tick<$1.tick}?.chord}
    @AppStorage("studio.pitchSpelling") private var spellingValue = PitchSpelling.automatic.rawValue
    @AppStorage("studio.showDegrees") private var showDegrees = false
    private var spelling:PitchSpelling { PitchSpelling(rawValue:spellingValue) ?? .automatic }
    @Environment(\.dismiss) var dismiss
    @State private var duration=barTicks; @State private var chord=Chord(); @State private var text=""; @State private var error: String?
    @State private var family:ChordFamily = .basic
    @State private var formulaText=""
    private enum InputField:Hashable{case symbol,formula}
    @FocusState private var focusedField:InputField?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        NavigationStack{ScrollView{VStack(alignment:.leading,spacing:22){
            VStack(alignment:.leading,spacing:8){
                if chord.customIntervals != nil{HStack(alignment:.firstTextBaseline){Text(chordRootName).font(.system(size:42,weight:.medium));Text("Custom chord").font(.title3)}}else{Text(MusicalNotation.chordSymbol(chord,keyRoot:session.project.keyRoot,minor:session.project.minor,spelling:spelling)).accessibilityIdentifier("chord.display-symbol").font(.system(size:42,weight:.medium)).lineLimit(2).minimumScaleFactor(0.6)}
                if showDegrees{Text(MusicalNotation.degreeSymbol(chord,keyRoot:session.project.keyRoot,minor:session.project.minor)).font(.title3).accessibilityIdentifier("chord.degree")}
                Text(MusicalNotation.chordNoteNames(chord,keyRoot:session.project.keyRoot,minor:session.project.minor,spelling:spelling).joined(separator:" · ")).font(.system(.subheadline,design:.monospaced)).foregroundStyle(Color.muted).accessibilityIdentifier("chord.notes")
            }.foregroundStyle(Color.harmony)
                // Luz: the symbol and its notes morph as the chord changes (inversion, octave, quality).
                .contentTransition(.interpolate).animation(Luz.Motion.morph,value:chord)
            // I16: why this chord sounds the way it does in this key, after the chord before it.
            ChordWhyRow(chord:chord,previous:previousChord,keyRoot:session.project.keyRoot,minor:session.project.minor)
            HStack{TextField("Chord symbol",text:$text).focused($focusedField,equals:.symbol).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder).frame(minHeight:44).onSubmit{parse()}.accessibilityIdentifier("chord.symbol");Button{parse()}label:{Text("Set").frame(minWidth:44,minHeight:44).contentShape(Rectangle())}.accessibilityIdentifier("chord.set-symbol")}.luzShake(error)
            if let error{Text(LocalizedStringKey(error)).font(.caption).foregroundStyle(Color.record).accessibilityIdentifier("chord.error").transition(Luz.Transition.pop(reduceMotion))}
            SmallHeading(text:"ROOT")
            LazyVGrid(columns:Array(repeating:GridItem(.flexible()),count:6),spacing:8){ForEach(0..<12,id:\.self){root in Button{chord.root=root;chord.voicedNotes=nil;text=chord.symbol;error=nil}label:{Text(pitchName(root)).font(.system(.body,weight:.medium)).foregroundStyle(chord.root==root ? Color.ink:Color.harmony).frame(maxWidth:.infinity,minHeight:44).background(chord.root==root ? Color.harmony:Color.raised,in:RoundedRectangle(cornerRadius:8,style:.continuous))}.buttonStyle(StudioQuietButtonStyle())}}
            SmallHeading(text:"QUALITY")
            Toggle("Custom intervals",isOn:Binding(get:{chord.customIntervals != nil},set:{enabled in chord.customIntervals=enabled ? chord.quality.intervals:nil;if enabled{chord.quality = .major};chord.inversion=0;chord.voicedNotes=nil;formulaText=chord.effectiveIntervals.map(String.init).joined(separator:", ");text=chord.symbol;error=nil})).accessibilityIdentifier("chord.custom")
            if chord.customIntervals != nil {
                TextField("0, 4, 7, 10, 14",text:$formulaText).focused($focusedField,equals:.formula).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.numbersAndPunctuation).textFieldStyle(.roundedBorder).onSubmit{setFormula()}.accessibilityLabel("Semitone offsets").accessibilityIdentifier("chord.formula")
                Text("Use 2–8 increasing semitone offsets from 0 to 48, starting with 0. Every custom tone is preserved.").font(.caption).foregroundStyle(Color.muted)
                Button("Set formula"){setFormula()}.frame(minHeight:44).accessibilityIdentifier("chord.set-formula")
            }else{
                Picker("Chord family",selection:$family){ForEach(ChordFamily.allCases,id:\.self){value in Text(LocalizedStringKey(value.rawValue)).tag(value)}}.pickerStyle(.menu).frame(minHeight:44)
                LazyVGrid(columns:Array(repeating:GridItem(.flexible()),count:4),spacing:8){ForEach(Quality.allCases.filter{$0.family==family},id:\.rawValue){q in Button{chord.quality=q;chord.inversion=0;chord.voicedNotes=nil;text=chord.symbol;error=nil}label:{Text(q.label).font(.system(.caption,weight:.medium)).foregroundStyle(chord.quality==q ? Color.ink:Color.harmony).frame(maxWidth:.infinity,minHeight:44).background(chord.quality==q ? Color.harmony:Color.raised,in:RoundedRectangle(cornerRadius:8,style:.continuous))}.buttonStyle(StudioQuietButtonStyle())}}
            }
            HStack {
                Text("Inversion")
                Spacer(minLength:8)
                Picker("Inversion",selection:Binding(get:{chord.inversion},set:{value in guard value != chord.inversion || chord.voicedNotes != nil else{return};chord.inversion=value;chord.voicedNotes=nil;chord.rootBassPitch=nil;Luz.Haptics.selection();audition()})){ForEach(0..<chord.effectiveIntervals.count,id:\.self){i in
                    if i==0{Text("Root position").tag(i)}else{Text("Inversion \(i)").tag(i)}
                }}
                    .labelsHidden().pickerStyle(.menu).frame(minHeight:44).contentShape(Rectangle()).accessibilityIdentifier("chord.inversion")
            }.frame(minHeight:44)
            HStack(spacing:10) {
                Text("Octave")
                Spacer(minLength:8)
                Button{shiftOctave(-1)}label:{Image(systemName:"minus").frame(width:44,height:44).contentShape(Rectangle())}.buttonStyle(StudioQuietButtonStyle()).disabled(!canShift(-1)).accessibilityLabel("Octave down").accessibilityIdentifier("chord.octave-down")
                Text(octaveLabel).font(.system(.body,design:.monospaced,weight:.medium)).monospacedDigit().frame(minWidth:40).luzNumeric(Double(chord.octave ?? 0)).animation(Luz.Motion.snap,value:octaveLabel).accessibilityIdentifier("chord.octave")
                Button{shiftOctave(1)}label:{Image(systemName:"plus").frame(width:44,height:44).contentShape(Rectangle())}.buttonStyle(StudioQuietButtonStyle()).disabled(!canShift(1)).accessibilityLabel("Octave up").accessibilityIdentifier("chord.octave-up")
            }.frame(minHeight:44)
            HStack {
                Text("Slash bass")
                Spacer(minLength:8)
                Picker("Slash bass",selection:Binding(get:{chord.slashBass ?? -1},set:{chord.slashBass=$0<0 ? nil:$0;chord.voicedNotes=nil;text=chord.symbol})){Text("None").tag(-1);ForEach(0..<12,id:\.self){i in Text(pitchName(i)).tag(i)}}
                    .labelsHidden().pickerStyle(.menu).frame(minHeight:44).contentShape(Rectangle()).accessibilityIdentifier("chord.slash-bass")
            }.frame(minHeight:44)
            Stepper("Duration: \(duration/240) sixteenths",value:$duration,in:240...max(240,(session.project.patterns.first(where:{$0.id==selection.patternID})?.length ?? barTicks)-selection.tick),step:240).accessibilityIdentifier("chord.duration")
        }.animation(Luz.Motion.snap,value:error).padding(22)}.background(Color.panel)
            .safeAreaInset(edge:.bottom,spacing:0){
                chordActions.padding(.horizontal,22).padding(.vertical,12).background(Color.panel)
            }
            .navigationTitle("Edit chord").navigationBarTitleDisplayMode(.inline).toolbar{ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}}}}
        .onAppear{chord=selection.chord;text=chord.symbol;duration=selection.duration;family=chord.quality.family;formulaText=chord.effectiveIntervals.map(String.init).joined(separator:", ")}
    }
    // Keep the two frequent actions reachable while the chord catalog scrolls.
    private var chordActions:some View {
        HStack{Button{preview()}label:{Label("Preview",systemImage:"speaker.wave.2")}.buttonStyle(StudioActionStyle(color:.harmony,prominent:false)).accessibilityIdentifier("chord.preview");Button{apply();Luz.Haptics.success()}label:{Text("Apply")}.buttonStyle(StudioActionStyle(color:.harmony)).accessibilityIdentifier("chord.apply")}
    }
    private var octaveLabel:String {
        let value:Int
        if let voiced=chord.voicedNotes,let low=voiced.min(){value=Int((Double(low-(chord.root==0 ? 60:48+chord.root))/12).rounded())}else{value=chord.octave ?? 0}
        return value==0 ? "0":(value>0 ? "+\(value)":"\(value)")
    }
    private func canShift(_ octaves:Int)->Bool{var copy=chord;return copy.shiftOctave(by:octaves)}
    private func shiftOctave(_ octaves:Int){guard chord.shiftOctave(by:octaves)else{Luz.Haptics.warning();return};Luz.Haptics.selection();audition()}
    /// Lets the musician hear an inversion or octave change at once.
    private func audition(){if session.ensureAudio(){session.audio.preview(chord)}}
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
/// I16 · "Why it sounds": degree, function and the root motion from the chord before.
struct ChordWhyRow: View {
    let chord: Chord
    let previous: Chord?
    let keyRoot: Int
    let minor: Bool
    @State private var open = false
    var body: some View {
        let why = HarmonyExplainer.explain(chord, previous: previous, keyRoot: keyRoot, minor: minor)
        DisclosureGroup(isExpanded: $open) {
            // I30: how to play it on guitar and ukulele (x = not played).
            HStack(spacing: 16) {
                ForEach(ChordShapes.Instrument.allCases, id: \.self) { instrument in
                    if let shape = ChordShapes.shape(for: chord, on: instrument) {
                        Text("\(Text(LocalizedStringKey(instrument == .guitar ? "Guitar" : "Ukulele"))): \(Text(verbatim: shape.frets.map { $0 < 0 ? "x" : String($0) }.joined(separator: " ")))")
                            .font(.caption.monospaced())
                    }
                }
            }.padding(.top, 6).accessibilityIdentifier("chord.shapes")
            Text(verbatim: why.sentences.map { NSLocalizedString($0, comment: "Why it sounds") }.joined(separator: " ")).font(.callout).foregroundStyle(Color.studioText).fixedSize(horizontal: false, vertical: true).padding(.top, 6)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "questionmark.circle").accessibilityHidden(true)
                Text("Why it sounds like this")
                Spacer()
                Text(verbatim: why.degree).font(.callout.monospaced().weight(.semibold))
                Text(LocalizedStringKey(why.function.capitalized)).font(.caption).foregroundStyle(Color.muted)
            }.frame(minHeight: 44)
        }
        .font(.subheadline).tint(.harmony)
        .accessibilityIdentifier("chord.why")
    }
}
struct SettingsView: View {
    @AppStorage("studio.appearance") private var appearance=0
    @AppStorage("studio.visualMetronome") private var visualMetronome=false
    @AppStorage("studio.leftHanded") private var leftHanded=false
    @AppStorage("studio.recordLock") private var recordLock=false
    @AppStorage("studio.showSeconds") private var showSeconds=false
    @State private var settingsFile:URL?
    @State private var importingSettings=false
    @AppStorage("nextStep.off") private var nextStepOff=false
    @State private var temporaryBytes:Int64=StorageUsage.bytes(of:FileManager.default.temporaryDirectory)
    private func clearTemporary(){
        let folder=FileManager.default.temporaryDirectory
        for url in (try? FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil)) ?? [] where url.lastPathComponent.hasPrefix("GrillaExport-") || url.lastPathComponent.hasPrefix("Loudness-") || url.lastPathComponent.hasPrefix("stems-") {
            try? FileManager.default.removeItem(at:url)
        }
        temporaryBytes=StorageUsage.bytes(of:folder)
    }
    @AppStorage("studio.pitchSpelling") private var spellingValue = PitchSpelling.automatic.rawValue
    @AppStorage("studio.showDegrees") private var showDegrees = false
    @Bindable var session: Session
    var body: some View {NavigationStack{Form{
        Section("App preferences"){
            Picker("Theme",selection:$appearance){Text("System").tag(0);Text("Light").tag(1);Text("Dark").tag(2)}.pickerStyle(.menu).accessibilityIdentifier("settings.theme")
            Button{if let url=URL(string:UIApplication.openSettingsURLString){UIApplication.shared.open(url)}}label:{Label("Language and permissions",systemImage:"arrow.up.forward.app")}.accessibilityIdentifier("settings.system")
            Text("Change this app’s language and permissions in iOS Settings. Available options depend on your device.").font(.caption).foregroundStyle(.secondary)
        }
        Section("Project tempo"){Stepper(value:Binding(get:{session.project.bpm},set:{v in session.edit{$0.bpm=v}}),in:40...240,step:1){Text("\(Int(session.project.bpm)) BPM").monospacedDigit()}.disabled(session.recording || session.armed);TapTempoRow(session:session)}
        Section("Project key"){
            Picker("Root",selection:Binding(get:{session.project.keyRoot},set:{v in session.edit{$0.keyRoot=v}})){ForEach(0..<12,id:\.self){i in Text(MusicalNotation.pitchClassName(i,keyRoot:session.project.keyRoot,minor:session.project.minor,spelling:PitchSpelling(rawValue:spellingValue) ?? .automatic)).tag(i).accessibilityIdentifier("settings.key-option.\(i)")}}.pickerStyle(.navigationLink).accessibilityIdentifier("settings.key-root")
            Toggle("Minor",isOn:Binding(get:{session.project.minor},set:{v in session.edit{$0.minor=v}})).accessibilityIdentifier("settings.key-minor")
            Text("Changing the key updates suggestions. Existing notes stay as written.").font(.caption).foregroundStyle(.secondary)
            NavigationLink{TransposeEditor(session:session)}label:{Label("Transpose arrangement",systemImage:"arrow.up.arrow.down")}.accessibilityIdentifier("settings.transpose")
                .disabled(session.recording || session.armed || session.performance.contextActive)
        }
        Section("Musical notation"){
            Picker("Note names",selection:$spellingValue){Text("Auto (key)").tag(PitchSpelling.automatic.rawValue).accessibilityIdentifier("settings.spelling-option.automatic");Text("Sharps").tag(PitchSpelling.sharps.rawValue).accessibilityIdentifier("settings.spelling-option.sharps");Text("Flats").tag(PitchSpelling.flats.rawValue).accessibilityIdentifier("settings.spelling-option.flats");Text("Do Re Mi").tag(PitchSpelling.solfege.rawValue).accessibilityIdentifier("settings.spelling-option.solfege")}.pickerStyle(.navigationLink).accessibilityIdentifier("settings.pitch-spelling")
            HStack {
                Text("Show scale degrees")
                Spacer()
                StudioSwitch(isOn:$showDegrees,enabled:true,identifier:"settings.show-degrees",label:"Show scale degrees",tint:.mint).frame(width:64,height:48)
            }
            Text("Names and degrees change the display, not the sound. Auto keeps the chord spelling you entered and otherwise follows the key. Minor degrees use the natural minor scale.").font(.caption).foregroundStyle(.secondary)
        }
        Section("Transport"){Toggle("Loop",isOn:Binding(get:{session.loop},set:{session.setLoop(enabled:$0)}));Picker("Loop length",selection:Binding(get:{session.loopBars},set:{session.setLoop(bars:$0)})){ForEach(session.loopLengthOptions,id:\.self){n in Text("\(n) bars").tag(n)}}}
        Section("MIDI"){Button("MIDI devices"){session.sheet = .midiDevices}}
        Section("Timing"){LatencyCalibrationRow(session:session)}
        Section("Metronome"){MetronomeSettingsRows(audio:session.audio);Toggle("Visual metronome",isOn:$visualMetronome).accessibilityIdentifier("settings.visual-metronome")}
        Section("Comfort"){
            Toggle("Left-handed pads",isOn:$leftHanded).accessibilityIdentifier("settings.left-handed")
            Toggle("Lock the screen while recording",isOn:$recordLock).accessibilityIdentifier("settings.record-lock")
            Toggle("Show time in minutes and seconds",isOn:$showSeconds).accessibilityIdentifier("settings.show-seconds")
            Toggle("Suggest the next step",isOn:Binding(get:{!nextStepOff},set:{nextStepOff = !$0})).accessibilityIdentifier("settings.next-step")
        }
        audioSettings
        Section("Backup"){BackupRows(session:session)
            // I67: settings travel as a small file (never project data).
            Button{if let url=try? SettingsTransfer.export(){settingsFile=url}}label:{Label("Export settings",systemImage:"square.and.arrow.up")}.accessibilityIdentifier("settings.export-settings")
            Button{importingSettings=true}label:{Label("Import settings",systemImage:"square.and.arrow.down")}.accessibilityIdentifier("settings.import-settings")
        }
        .sheet(isPresented:Binding(get:{settingsFile != nil},set:{if !$0{settingsFile=nil}})){if let url=settingsFile{ShareView(url:url)}}
        .fileImporter(isPresented:$importingSettings,allowedContentTypes:[.json]){result in
            if case .success(let url)=result{do{let count=try SettingsTransfer.importFile(url);session.showToast(String(format:NSLocalizedString("%lld settings imported",comment:"Settings transfer"),count))}catch{session.message="This file is not a La Grilla settings file."}}
        }
        // U62: how much room songs and temporary files take, and clearing the temporary ones.
        Section("Storage"){
            LabeledContent("Songs and versions",value:ByteCountFormatter.string(fromByteCount:StorageUsage.bytes(of:session.store.root),countStyle:.file))
            LabeledContent("Temporary files",value:ByteCountFormatter.string(fromByteCount:temporaryBytes,countStyle:.file))
            Button("Clear temporary files"){clearTemporary()}.accessibilityIdentifier("settings.clear-temporary").disabled(session.exportInProgress)
        }
        Section("This project"){
            Button{session.sheet = .history}label:{Label("Edit history",systemImage:"clock.arrow.circlepath")}.accessibilityIdentifier("settings.history")
            Button{session.sheet = .versions}label:{Label("Song versions",systemImage:"bookmark")}.accessibilityIdentifier("settings.versions")
            Button{session.sheet = .trash}label:{Label("Recently deleted",systemImage:"trash")}.accessibilityIdentifier("settings.trash")
            Button{session.sheet = .coNotes}label:{Label("Notes for co-authors",systemImage:"note.text")}.accessibilityIdentifier("settings.notes")
            // I48: how others may use the song when it is shared.
            Picker("When shared",selection:Binding(get:{session.project.license ?? ""},set:{value in session.edit{$0.license=value.isEmpty ? nil:value}})){
                Text("Not set").tag("")
                ForEach(SongLicense.allCases,id:\.rawValue){license in Text(LocalizedStringKey(license.title)).tag(license.rawValue)}
            }.pickerStyle(.menu).accessibilityIdentifier("settings.license")
            // I59: offline name ideas from the key and tempo.
            Menu{
                ForEach(SongNames.suggestions(keyRoot:session.project.keyRoot,minor:session.project.minor,bpm:session.project.bpm,seed:UInt64(session.project.revision),russian:Locale.current.language.languageCode?.identifier=="ru"),id:\.self){name in
                    Button(name){session.edit{$0.name=name}}
                }
            }label:{Label("Suggest a song name",systemImage:"textformat.alt")}.accessibilityIdentifier("settings.names")
            Text("Hear and return to any recent edit, keep named versions of the song, or bring back deleted tracks, takes and clips.").font(.caption).foregroundStyle(.secondary)
        }
        Section("About La Grilla"){
            Button("Getting started"){session.sheet = .gettingStarted}.accessibilityIdentifier("settings.help")
            LabeledContent("Version",value:"\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""))")
            Link("Privacy policy",destination:URL(string:"https://github.com/alexgazin/la-grilla/blob/main/docs/privacy/"+(Locale.current.language.languageCode?.identifier=="ru" ? "ru":"en")+".md")!)
            Link("Support",destination:URL(string:"https://github.com/alexgazin/la-grilla/issues")!)
            Text("Projects and recordings stay on your iPhone. Portable project exports include their original voice recordings.").font(.caption).foregroundStyle(.secondary)
        }

    }.navigationTitle("Settings").navigationBarTitleDisplayMode(.inline).toolbar{ToolbarItem(placement:.confirmationAction){Button("Done"){session.sheet=nil}}}}
        // A presented Form owns its appearance boundary. Apply the observed
        // preference here as well as to the window so live changes update the
        // current sheet, rather than only its presenter or the next opening.
        .preferredColorScheme(appearance==1 ? .light:appearance==2 ? .dark:nil)
        // Project tools and notation need a full working viewport. A medium
        // Form only exposed preferences/tempo and deferred the key actions.
        .presentationDetents([.large])}
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
            if let report=LocalDiagnostics.shared.latestReport {
                ShareLink(item:report){
                    Label("Share the latest crash report",systemImage:"ladybug").frame(minHeight:44)
                }.accessibilityIdentifier("settings.crash-report")
                Text("Kept only on this iPhone. Contains system stack traces, never your music.").font(.caption).foregroundStyle(.secondary)
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
            else if let id=project.tracks.first(where:{$0.role == .bass})?.id{try ProjectTrash.deleteTrack(id,in:&project)}
        }
    })}
    var body:some View {NavigationStack{Form{
        Section {
            HStack {
                Text("Root bass")
                Spacer()
                // Keep the platform switch's hit region independent of the
                // Form cell and its descriptive/status rows on iOS 26.
                StudioSwitch(isOn:bassEnabled,enabled:!editingLocked,identifier:"bass.enabled",label:"Root bass",tint:.bass).frame(width:64,height:48)
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

/// One host owns the whole 64×48 touch surface, including the displayed thumb.
/// The UISwitch supplies its real state and accessibility; every successful
/// touch or VoiceOver activation reaches the same single valueChanged path.
@MainActor private struct StudioSwitch:UIViewRepresentable {
    @Binding var isOn:Bool
    let enabled:Bool
    let identifier:String
    let label:String
    let tint:Color
    func makeUIView(context:Context)->StudioSwitchHost {
        let host=StudioSwitchHost()
        host.control.addTarget(context.coordinator,action:#selector(Coordinator.changed(_:)),for:.valueChanged)
        return host
    }
    func updateUIView(_ host:StudioSwitchHost,context:Context){
        context.coordinator.value=$isOn
        let control=host.control
        control.isEnabled=enabled && context.environment.isEnabled
        host.isUserInteractionEnabled=control.isEnabled
        control.accessibilityIdentifier=identifier
        control.accessibilityLabel=NSLocalizedString(label,comment:"Studio switch")
        control.onTintColor=UIColor(tint)
        if control.isOn != isOn{control.setOn(isOn,animated:control.window != nil)}
    }
    func makeCoordinator()->Coordinator{Coordinator(value:$isOn)}
    func sizeThatFits(_ proposal:ProposedViewSize,uiView:StudioSwitchHost,context:Context)->CGSize?{CGSize(width:64,height:48)}
    static func dismantleUIView(_ uiView:StudioSwitchHost,coordinator:Coordinator){uiView.control.removeTarget(coordinator,action:#selector(Coordinator.changed(_:)),for:.valueChanged)}
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

@MainActor private final class StudioSwitchHost:UIView,UIGestureRecognizerDelegate {
    let control=StudioUISwitch()
    override init(frame:CGRect){
        super.init(frame:frame)
        isAccessibilityElement=false
        addSubview(control);control.hitAreaHost=self;control.isAccessibilityElement=true
        // The display must not start a second, ineffective UIKit tracking path.
        // Keep isEnabled intact for the actual state and accessibility traits.
        control.isUserInteractionEnabled=false
        accessibilityElements=[control]
        let tap=UITapGestureRecognizer(target:self,action:#selector(tapped(_:)))
        let pan=UIPanGestureRecognizer(target:self,action:#selector(dragged(_:)))
        tap.delegate=self;pan.delegate=self
        pan.maximumNumberOfTouches=1
        tap.require(toFail:pan)
        addGestureRecognizer(tap);addGestureRecognizer(pan)
    }
    required init?(coder:NSCoder){fatalError("init(coder:) is unavailable")}
    override var intrinsicContentSize:CGSize{CGSize(width:64,height:48)}
    override func layoutSubviews(){
        super.layoutSubviews();control.sizeToFit();control.center=CGPoint(x:bounds.midX,y:bounds.midY)
    }
    override func hitTest(_ point:CGPoint,with event:UIEvent?)->UIView? {
        guard isUserInteractionEnabled,!isHidden,alpha>0.01,bounds.contains(point)else{return nil}
        return self
    }
    override func gestureRecognizerShouldBegin(_ gestureRecognizer:UIGestureRecognizer)->Bool {
        guard control.isEnabled else{return false}
        if let pan=gestureRecognizer as? UIPanGestureRecognizer {
            let movement=pan.translation(in:self)
            return abs(movement.x)>abs(movement.y)
        }
        return true
    }
    @discardableResult func activate()->Bool{commit(!control.isOn)}
    @discardableResult private func commit(_ desired:Bool)->Bool {
        guard control.isEnabled,isUserInteractionEnabled else{return false}
        if desired != control.isOn {
            control.setOn(desired,animated:true)
            control.sendActions(for:.valueChanged)
        }
        return true
    }
    @objc private func tapped(_ gesture:UITapGestureRecognizer){
        guard gesture.state == .ended,bounds.contains(gesture.location(in:self)) else{return}
        activate()
    }
    @objc private func dragged(_ gesture:UIPanGestureRecognizer){
        // Vertical motion belongs to the Form. Cancelled drags never change
        // the display or binding; a horizontal release commits at most once.
        guard gesture.state == .ended else{return}
        let movement=gesture.translation(in:self)
        guard abs(movement.x)>=8,abs(movement.x)>abs(movement.y),bounds.contains(gesture.location(in:self)) else{return}
        commit(movement.x>0)
    }
}

@MainActor private final class StudioUISwitch:UISwitch {
    weak var hitAreaHost:StudioSwitchHost?
    override func accessibilityActivate()->Bool{hitAreaHost?.activate() ?? false}
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
    @State private var adding = false
    var body:some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Whole song").font(StudioTypography.title)
                        Spacer()
                        Text("\(session.project.length / barTicks) bars")
                            .font(.caption.monospacedDigit()).foregroundStyle(Color.muted)
                    }
                    SongFormOverview(sections: session.project.sections, selectedID: session.selectedSection)
                    SongFormLegend(sections: session.project.sections, actions: { actions = $0 }, editingLocked: editingLocked)
                    SongFormLane(session: session, editingLocked: editingLocked)
                    Text("Drag the handle to move a section. Tap its menu for more actions.")
                        .font(.caption).foregroundStyle(Color.muted)
                    Button { adding = true } label: { Label("Add section", systemImage: "plus") }
                        .buttonStyle(StudioActionStyle(prominent: false))
                        .disabled(editingLocked || remainingBars == 0 || session.project.sections.count >= maximumSections)
                        .accessibilityIdentifier("sections.add")
                    // I23: one more bar on the home chord with a final hit; the song then plays once.
                    Button { session.edit { try EndingGenerator.append(to: &$0, name: NSLocalizedString("Ending", comment: "Section name")) }; session.showToast("Ending added") } label: { Label("Add an ending", systemImage: "flag.checkered") }
                        .buttonStyle(StudioActionStyle(color: .mint, prominent: false))
                        .disabled(editingLocked || remainingBars == 0 || session.project.sections.count >= maximumSections)
                        .accessibilityIdentifier("sections.ending")
                    NavigationLink { FormTemplatesView(session: session) } label: { Label("Structure from a template", systemImage: "rectangle.split.3x1") }
                        .buttonStyle(StudioActionStyle(color: .mint, prominent: false))
                        .disabled(editingLocked)
                        .accessibilityIdentifier("form.open")
                    HStack(spacing: 4) {
                        IconButton(symbol: "arrow.uturn.backward", label: "Undo") { session.undo() }
                            .disabled(editingLocked || !session.history.canUndo)
                            .accessibilityIdentifier("sections.undo")
                        IconButton(symbol: "arrow.uturn.forward", label: "Redo") { session.redo() }
                            .disabled(editingLocked || !session.history.canRedo)
                            .accessibilityIdentifier("sections.redo")
                        Spacer()
                        Text(LocalizedStringKey(session.audio.playing ? "PLAYING" : "STOPPED"))
                            .font(.caption.monospacedDigit()).foregroundStyle(Color.muted)
                            .accessibilityIdentifier("section.playback-state")
                    }
                }
                .padding(16)
            }
            .background(Color.ink)
            .navigationTitle("Song sections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { session.sheet = nil } } }
        }
        .sheet(isPresented: $adding) {
            if remainingBars > 0 {
                AddSongSection(maximumBars: remainingBars) { title, bars in
                    let revision = session.project.revision
                    session.edit { try SectionEditing.append(name: title, bars: bars, to: &$0) }
                    return session.project.revision != revision
                }
            }
        }
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
    private var remainingBars: Int { 64 - session.project.length / barTicks }
    private var editingLocked:Bool{session.performance.contextActive || session.recording || session.armed}
    private func actionList(_ section:MusicDomain.Section)->some View {NavigationStack{List{
        Button("Rename"){pendingRename=section.id;actions=nil}
        Button("Duplicate"){session.edit{try SectionEditing.duplicate(section.id,name:section.name=="Verse" ? "Chorus":String((section.name+" copy").prefix(120)),in:&$0)};actions=nil}
        // I40: the same section again with a snare fill at the end of the copy.
        Button("Continue for me"){let id=section.id;session.edit{try ContinueIdea.extend(id,name:NSLocalizedString("Continuation",comment:"Section name"),seed:UInt64(session.project.revision) &+ 1,in:&$0)};actions=nil}.accessibilityIdentifier("section.continue")
        Button("Duplicate with a fill"){session.edit{try SectionEditing.duplicateWithVariation(section.id,name:String((section.name+" 2").prefix(120)),in:&$0)};actions=nil}.accessibilityIdentifier("section.duplicate-fill")
            .disabled(session.project.sections.count>=maximumSections || session.project.length+section.length>songTickLimit).accessibilityIdentifier("section.duplicate")
        Picker("Colour",selection:Binding(get:{section.color ?? -1},set:{value in let id=section.id;session.edit{p in if let i=p.sections.firstIndex(where:{$0.id==id}){p.sections[i].color=value<0 ? nil:value}};actions=nil})){
            Text("Automatic").tag(-1)
            ForEach(SongFormStyle.choices,id:\.index){choice in Label{Text(choice.name)}icon:{Image(systemName:"circle.fill").foregroundStyle(choice.color)}.tag(choice.index)}
        }.accessibilityIdentifier("section.color")
        Picker("Filter sweep",selection:Binding(get:{sweepTag(section.filterSweep)},set:{tag in let id=section.id,value=sweep(tag);session.edit{p in if let i=p.sections.firstIndex(where:{$0.id==id}){p.sections[i].filterSweep=value}};actions=nil})){
            Text("None").tag(0);Text("Open up").tag(1);Text("Close down").tag(2);Text("Rise").tag(3);Text("Drop in").tag(4)
        }.accessibilityIdentifier("section.filter-sweep")
        // I22: this section in another key (drums stay).
        Picker("Key of this section",selection:Binding(get:{section.transpose ?? 0},set:{value in let id=section.id;session.edit{p in if let i=p.sections.firstIndex(where:{$0.id==id}){p.sections[i].transpose=value==0 ? nil:value}};actions=nil})){
            ForEach(-6...6,id:\.self){value in Text(value==0 ? NSLocalizedString("As the song",comment:"Section key"):String(format:"%+d",value)).tag(value)}
        }.accessibilityIdentifier("section.key")
        // U32: copy this section's music to another project (or paste what was copied).
        Menu("Copy music"){
            Button("Copy chords"){copyMusic(.chords,section)}
            Button("Copy the beat"){copyMusic(.beat,section)}
            Button("Copy the melody"){copyMusic(.melody,section)}
        }.accessibilityIdentifier("section.copy")
        Button("Paste copied music"){pasteMusic(into:section)}.disabled(!UIPasteboard.general.contains(pasteboardTypes:[MusicClipboard.pasteboardType])).accessibilityIdentifier("section.paste")
        Button("Move earlier"){move(section.id,by:-1);actions=nil}.disabled(session.project.sections.first?.id==section.id).accessibilityIdentifier("section.earlier")
        Button("Move later"){move(section.id,by:1);actions=nil}.disabled(session.project.sections.last?.id==section.id).accessibilityIdentifier("section.later")
        if session.project.sections.count>1{Button("Delete section",role:.destructive){pendingDelete=section.id;actions=nil}.accessibilityIdentifier("section.delete")}
    }.environment(\.defaultMinListRowHeight,52).disabled(editingLocked).navigationTitle(section.name).navigationBarTitleDisplayMode(.inline)
        .toolbar{ToolbarItem(placement:.cancellationAction){Button("Cancel"){actions=nil}}}}
        .presentationDetents([.medium,.large]).tint(.mint)
    }
    private func sweep(_ tag:Int)->FilterSweep?{[nil,FilterSweep.openUp,.closeDown,.riseUp,.dropIn][max(0,min(4,tag))]}
    private func sweepTag(_ value:FilterSweep?)->Int{[FilterSweep.openUp,.closeDown,.riseUp,.dropIn].firstIndex{$0==value}.map{$0+1} ?? 0}
    private func copyMusic(_ kind:MusicClipboard.Kind,_ section:MusicDomain.Section){
        guard let value=MusicClipboard.copy(kind,section:section,from:session.project),let data=try? JSONEncoder().encode(value) else{session.message="There is no music of that kind in this section.";actions=nil;return}
        UIPasteboard.general.setData(data,forPasteboardType:MusicClipboard.pasteboardType)
        session.showToast("Copied");actions=nil
    }
    private func pasteMusic(into section:MusicDomain.Section){
        guard let data=UIPasteboard.general.data(forPasteboardType:MusicClipboard.pasteboardType),let value=try? JSONDecoder().decode(MusicClipboard.self,from:data)else{actions=nil;return}
        let id=section.id
        session.edit{p in guard let target=p.sections.first(where:{$0.id==id})else{return};try value.paste(into:target,project:&p)}
        session.showToast("Pasted");actions=nil
    }
    private func finishAction(){
        if let id=pendingRename,let section=session.project.sections.first(where:{$0.id==id}){name=section.name;editing=id}
        if let id=pendingDelete,session.project.sections.contains(where:{$0.id==id}){deleting=id}
        pendingRename=nil;pendingDelete=nil
    }
    func move(_ id:UUID,by delta:Int){
        guard let index=session.project.sections.firstIndex(where:{$0.id==id}),session.project.sections.indices.contains(index+delta)else{return}
        let token=ArrangementDragPayload(project:session.project,sectionID:id),target=session.project.sections[index+delta].id
        session.reorderSection(drop: [token.encoded()], onto: target)
    }
}

private struct AddSongSection: View {
    @Environment(\.dismiss) private var dismiss
    let maximumBars: Int
    let create: (String, Int) -> Bool
    @State private var name = ""
    @State private var bars = 1
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name).accessibilityIdentifier("sections.new-name")
                Menu("Section templates") {
                    Button("Verse") { name = NSLocalizedString("Verse", comment: "Section template") }
                    Button("Chorus") { name = NSLocalizedString("Chorus", comment: "Section template") }
                    Button("Bridge") { name = NSLocalizedString("Bridge", comment: "Section template") }
                }
                Stepper(value: $bars, in: 1...max(1, maximumBars)) {
                    Text("\(bars) bars")
                }
                if failed { Text("Could not add this section.").foregroundStyle(Color.record) }
            }
            .navigationTitle("Add section")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        if create(name, bars) { dismiss() } else { failed = true }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 120)
                    .accessibilityIdentifier("sections.create")
                }
            }
        }
        .tint(.mint)
        .onAppear { bars = min(4, maximumBars) }
    }
}

/// I11: tap four or more times; the median interval proposes a tempo.
private struct TapTempoRow: View {
    @Bindable var session: Session
    @State private var taps: [TimeInterval] = []
    private var estimate: Double? { TempoEstimator.fromTaps(taps) }
    var body: some View {
        HStack(spacing: 12) {
            Button("Tap tempo") {
                let now = ProcessInfo.processInfo.systemUptime
                if let last = taps.last, now - last > 2 { taps = [] }
                taps.append(now)
                if taps.count > 12 { taps.removeFirst(taps.count - 12) }
            }.frame(minHeight: 44).accessibilityIdentifier("settings.tap-tempo")
            Spacer(minLength: 0)
            if let estimate {
                Button(String(format: NSLocalizedString("Use %.0f BPM", comment: "Tap tempo"), estimate)) {
                    let value = estimate.rounded()
                    session.edit { $0.bpm = value }
                    taps = []
                }.frame(minHeight: 44).disabled(session.recording || session.armed).accessibilityIdentifier("settings.tap-tempo.use")
            }
        }
    }
}

/// I01: tap along with the metronome; the median offset becomes this route's
/// recording compensation. The live sound is never delayed.
/// I77: a Files folder (iCloud Drive or on this iPhone) gets a daily zip of changed projects.
private struct BackupRows: View {
    @Bindable var session: Session
    @State private var choosing = false
    var body: some View {
        if let name = session.backupFolderName {
            LabeledContent("Folder", value: name)
            if let last = session.lastBackup { LabeledContent("Last backup", value: last.formatted(date: .abbreviated, time: .shortened)) }
            Button("Back up now") { Task { await session.backupNow(force: true) } }.frame(minHeight: 44).accessibilityIdentifier("settings.backup.now")
            Button("Stop automatic backup", role: .destructive) { session.stopBackup() }.frame(minHeight: 44)
        } else {
            Button("Choose a backup folder") { choosing = true }.frame(minHeight: 44).accessibilityIdentifier("settings.backup.choose")
        }
        Text("Once a day, when you leave the app, projects changed since the last backup are saved as one zip in that folder.").font(.caption).foregroundStyle(.secondary)
            .fileImporter(isPresented: $choosing, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result { session.chooseBackupFolder(url) }
            }
    }
}

/// I10: metronome level, accent, sound and count-in only.
private struct MetronomeSettingsRows: View {
    @Bindable var audio: AudioController
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent("Level", value: String(format: NSLocalizedString("%+.0f dB", comment: "Metronome level"), audio.metronomeSettings.gainDB))
            Slider(value: Binding(get: { audio.metronomeSettings.gainDB }, set: { audio.metronomeSettings.gainDB = ($0).rounded() }), in: -24...6, step: 1)
                .accessibilityLabel("Metronome level").accessibilityIdentifier("settings.metronome.level")
        }
        Toggle("Accent the first beat", isOn: $audio.metronomeSettings.accent).accessibilityIdentifier("settings.metronome.accent")
        Picker("Sound", selection: $audio.metronomeSettings.sound) {
            Text("Beep").tag(MetronomeSettings.Sound.beep)
            Text("High").tag(MetronomeSettings.Sound.high)
            Text("Low").tag(MetronomeSettings.Sound.low)
        }.accessibilityIdentifier("settings.metronome.sound")
        Toggle("Only during the count-in", isOn: $audio.metronomeSettings.countInOnly).accessibilityIdentifier("settings.metronome.count-in-only")
    }
}

private struct LatencyCalibrationRow: View {
    @Bindable var session: Session
    @State private var running = false
    @State private var offsets: [Double] = []
    private var estimate: RouteLatencyCalibration? { RouteLatencyCalibration.estimate(offsets) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let saved = session.routeLatency[session.currentRouteKey] {
                Text(String(format: NSLocalizedString("This output: %.0f ms recording compensation", comment: "Latency calibration"), saved)).font(.caption)
            }
            if running {
                Button { tap() } label: {
                    Text("Tap on every click").frame(maxWidth: .infinity, minHeight: 88)
                        .background(Color.mint.opacity(0.25), in: RoundedRectangle(cornerRadius:Luz.Radius.card,style:.continuous))
                }.buttonStyle(.plain).accessibilityIdentifier("settings.latency.tap")
                Text(String(format: NSLocalizedString("%d taps", comment: "Latency calibration"), offsets.count)).font(.caption.monospacedDigit())
                if let estimate {
                    Button(String(format: NSLocalizedString("Save %.0f ms for this output", comment: "Latency calibration"), estimate.medianMilliseconds)) {
                        session.saveRouteLatency(estimate.medianMilliseconds); stop()
                    }.frame(minHeight: 44).accessibilityIdentifier("settings.latency.save")
                }
                Button("Stop") { stop() }.frame(minHeight: 44)
            } else {
                Button("Calibrate recording timing") { start() }.frame(minHeight: 44).accessibilityIdentifier("settings.latency.start")
                if session.routeLatency[session.currentRouteKey] != nil { Button("Reset for this output") { session.saveRouteLatency(nil) }.frame(minHeight: 44) }
            }
            Text("Tap 8 or more clicks. Useful for Bluetooth headphones; the live sound is unchanged.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func start() {
        offsets = []; running = true
        guard session.ensureAudio() else { running = false; return }
        session.metronome = true; session.audio.metronome(true)
        if !session.audio.playing { session.togglePlay() }
    }
    private func stop() {
        running = false
        if session.audio.playing { session.togglePlay() }
    }
    private func tap() {
        session.audio.refreshClock()
        let beat = Double(ppq)
        var phase = session.audio.tick.truncatingRemainder(dividingBy: beat)
        if phase > beat / 2 { phase -= beat }
        offsets.append(phase / beat * 60 / session.project.bpm * 1000)
    }
}
