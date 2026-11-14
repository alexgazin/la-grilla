import SwiftUI
import MusicDomain
import AVFoundation

struct AssistantView:View {
    @Bindable var session:Session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @FocusState private var focused:Bool
    @State private var input=""
    @State private var generatedInput=""
    @State private var proposal:AssistantProposal?
    @State private var candidate:Project?
    @State private var error:String?
    @State private var ambiguous=false
    @State private var previewB=false
    @State private var language="ru-RU"
    @State private var dictation=DictationController()
    @State private var microphoneSession=false
    var body:some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:18){
                    HStack{Image(systemName:"text.bubble").font(.system(size:32)).foregroundStyle(Color.mint);Spacer();CapsuleLabel(text:"LOCAL",color:.mint)}
                    Text("An idea, in your words.").font(.system(size:27,weight:.medium))
                    Text("Commands create a proposal. Review the section, durations and assumptions before applying.").font(.subheadline).foregroundStyle(Color.muted)
                    HStack{Text(session.section.name).fontWeight(.medium);Spacer();Text("\(session.section.length/barTicks) bars · \(Int(session.project.bpm)) BPM").font(.caption.monospaced()).foregroundStyle(Color.muted)}
                    TextEditor(text:$input).focused($focused).frame(height:110).scrollContentBackground(.hidden).padding(8).background(Color.panel,in:RoundedRectangle(cornerRadius:12)).accessibilityLabel("Command").accessibilityIdentifier("assistant.input")
                        .onChange(of:input){_,value in if value.count>2000{input=String(value.prefix(2000))};if value != generatedInput{proposal=nil;candidate=nil};session.endHarmonyPreview()}
                    HStack {
                        Menu("Examples"){
                            Button("Tempo 110"){input="Tempo 110"}
                            Button("Key D minor"){input="Key D minor"}
                            Button("Chorus 8 bars: Am F C G each 2 bars"){input="Chorus 8 bars: Am F C G each 2 bars"}
                            Button("Припев 8 тактов: Am F C G по два такта"){input="Припев 8 тактов: Am F C G по два такта"}
                        }.frame(minHeight:44)
                        Spacer()
                        Picker("Dictation language",selection:$language){Text("RU").tag("ru-RU");Text("EN").tag("en-US")}.pickerStyle(.menu).disabled(dictation.recording || dictation.requesting)
                        Button{toggleDictation()}label:{Image(systemName:dictation.recording ? "stop.circle.fill":"mic.fill").frame(width:44,height:44).foregroundStyle(dictation.recording ? Color.record:Color.mint)}.accessibilityLabel(dictation.recording ? "Stop dictation":"Dictate a command").disabled(dictation.requesting)
                    }
                    if dictation.requesting{ProgressView("Preparing dictation…")}
                    if dictation.recording{Label("LISTENING · COMMAND",systemImage:"waveform").font(.caption.monospaced()).foregroundStyle(Color.record)}
                    Text("Dictation stops playback and requires on-device recognition. You can always type. Humming requires a separate melody recording.").font(.caption).foregroundStyle(Color.muted)
                    if let error=dictation.error{Text(error).font(.caption).foregroundStyle(Color.record)}
                    Button{generate()}label:{Label("Review command",systemImage:"sparkles").frame(maxWidth:.infinity,minHeight:48).background(Color.mint,in:RoundedRectangle(cornerRadius:12)).foregroundStyle(Color.ink).fontWeight(.semibold)}.disabled(input.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || dictation.requesting || dictation.recording).accessibilityIdentifier("assistant.generate")
                    if let error{Text(error).font(.callout).foregroundStyle(Color.record)}
                    if ambiguous {VStack(spacing:8){Button("Stretch chords evenly"){generate(.stretch)};Button("Repeat, one bar per chord"){generate(.repeatBars)}}.buttonStyle(.bordered).frame(maxWidth:.infinity)}
                    if let proposal,let candidate{review(proposal,candidate:candidate)}
                }.padding(20)
            }.scrollDismissesKeyboard(.interactively).background(Color.ink).navigationTitle("Assistant").navigationBarTitleDisplayMode(.inline)
                .toolbar{ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}}}
        }.tint(.mint)
        .onChange(of:dictation.text){_,value in if !value.isEmpty{input=value}}
        .onChange(of:dictation.recording){_,recording in if !recording{restoreAudio()}}
        .onChange(of:phase){_,p in if p == .background{dictation.stop();restoreAudio()}}
        .onReceive(NotificationCenter.default.publisher(for:AVAudioSession.interruptionNotification).receive(on:RunLoop.main)){_ in dictation.stop();microphoneSession=false}
        .onDisappear{dictation.stop();restoreAudio();session.endHarmonyPreview()}
        .onAppear{if let i=ProcessInfo.processInfo.arguments.firstIndex(of:"--screen"),ProcessInfo.processInfo.arguments.count>i+1,ProcessInfo.processInfo.arguments[i+1]=="assistant-proposal"{input="Tempo 110; Chorus 8 bars: Am F C G each 2 bars";generate()}}
    }
    func review(_ proposal:AssistantProposal,candidate:Project)->some View {
        VStack(alignment:.leading,spacing:14){
            SmallHeading(text:"PROPOSAL")
            ForEach(Array(proposal.operations.enumerated()),id:\.offset){_,op in Text(summary(op,candidate:candidate)).padding(12).frame(maxWidth:.infinity,alignment:.leading).background(Color.panel,in:RoundedRectangle(cornerRadius:10))}
            if !proposal.assumptions.isEmpty{SmallHeading(text:"ASSUMPTIONS");ForEach(proposal.assumptions,id:\.self){Text($0).font(.caption).foregroundStyle(Color.muted)}}
            ForEach(proposal.warnings,id:\.self){Label($0,systemImage:"exclamationmark.triangle").font(.caption).foregroundStyle(Color.harmony)}
            HStack(spacing:10){Button{if let section=session.project.sections.first(where:{$0.id==proposal.scopeSectionID}){previewB=false;session.previewHarmony(session.project,section:section)}}label:{Text("A · Original").frame(maxWidth:.infinity,minHeight:48).background(session.harmonyPreview && !previewB ? Color.mint.opacity(0.2):Color.raised,in:RoundedRectangle(cornerRadius:10))};Button{if let section=candidate.sections.first(where:{$0.id==proposal.scopeSectionID}){previewB=true;session.previewHarmony(candidate,section:section)}}label:{Text("B · Proposal").frame(maxWidth:.infinity,minHeight:48).background(session.harmonyPreview && previewB ? Color.mint.opacity(0.2):Color.raised,in:RoundedRectangle(cornerRadius:10))}}
            if session.harmonyPreview{Button("Stop preview"){session.endHarmonyPreview()}.frame(minHeight:44)}
            Button{apply(proposal)}label:{Text("Apply proposal").fontWeight(.semibold).frame(maxWidth:.infinity,minHeight:48).foregroundStyle(Color.ink).background(Color.mint,in:RoundedRectangle(cornerRadius:12))}.accessibilityIdentifier("assistant.apply")
            Text("One Undo restores the whole change.").font(.caption).foregroundStyle(Color.muted)
        }
    }
    func summary(_ op:AssistantOperation,candidate:Project)->String {
        let section=candidate.sections.first{$0.id==op.sectionID}?.name ?? session.section.name
        switch op.type {
        case .setTempo:return "\(Int(op.bpm ?? 120)) BPM"
        case .setKey:return NSLocalizedString("Key",comment:"")+": "+Chord.roots[op.root ?? 0]+((op.minor ?? false) ? " minor":" major")
        case .renameSection:return session.section.name+" → "+(op.name ?? "")
        case .resizeSection:return section+": \(op.bars ?? 4) "+NSLocalizedString("bars",comment:"")
        case .setProgression:return section+" · "+zip(op.chords ?? [],op.durations ?? []).map{"\($0.symbol) (\($1))"}.joined(separator:" · ")+" "+NSLocalizedString("bars per chord",comment:"")
        }
    }
    func generate(_ distribution:ChordDistribution?=nil){
        focused=false;session.endHarmonyPreview();ambiguous=false;generatedInput=input
        do{let p=try AssistantEngine.propose(input,project:session.project,sectionID:session.section.id,distribution:distribution);candidate=try p.candidate(for:session.project);proposal=p;error=nil}
        catch{proposal=nil;candidate=nil;self.error=error.localizedDescription;if case AssistantError.ambiguous=error{ambiguous=true}}
    }
    func apply(_ proposal:AssistantProposal){
        do{_ = try proposal.candidate(for:session.project)}catch{self.error=error.localizedDescription;return}
        session.endHarmonyPreview();session.audio.stop();let revision=session.project.revision
        session.edit{try proposal.apply(to:&$0)}
        if session.project.revision>revision{if let section=session.project.sections.first(where:{$0.id==proposal.scopeSectionID}){session.select(section)};dismiss()}
    }
    func toggleDictation(){
        focused=false
        if dictation.recording{dictation.stop();restoreAudio();return}
        session.endHarmonyPreview();session.finishTake();session.audio.reset();microphoneSession=true
        Task{await dictation.start(locale:language);if !dictation.recording{restoreAudio()}}
    }
    func restoreAudio(){if microphoneSession{microphoneSession=false;_ = session.ensureAudio()}}
}
