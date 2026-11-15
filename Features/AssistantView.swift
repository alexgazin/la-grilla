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
    @State private var proposalSource:Project?
    @State private var error:String?
    @State private var ambiguous=false
    @State private var previewB=false
    @State private var language="ru-RU"
    @State private var dictation=DictationController()
    @State private var ai=AIComposerController()
    @State private var mode:AssistantMode = .automatic
    @State private var generatedWithAI=false
    @State private var generationID=0
    @State private var generationTask:Task<Void,Never>?
    @State private var timeoutTask:Task<Void,Never>?
    @State private var microphoneLease:UUID?
    @State private var showExamples=false
    var body:some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:18){
                    Text("An idea, in your words.").font(.system(.title2,weight:.semibold)).tracking(-0.6)
                    Text("Describe a song form, chords or a harmonic change. Review every change before applying.").font(.caption).foregroundStyle(Color.muted)
                    HStack{Text(session.section.name).fontWeight(.medium);Spacer();Text("\(session.section.length/barTicks) bars · \(Int(session.project.bpm)) BPM").font(.caption.monospaced()).foregroundStyle(Color.muted);CapsuleLabel(text:generatedWithAI ? "ON-DEVICE AI":"LOCAL",color:.mint)}
                    StudioSegments(title:"Assistant mode",selection:$mode,options:AssistantMode.allCases.map{($0,LocalizedStringKey($0.title))}).disabled(dictation.recording || dictation.requesting || dictation.finalizing)
                    Text(ai.availabilityMessage).font(.caption).foregroundStyle(Color.muted).accessibilityIdentifier("assistant.ai-status")
                    Text(LocalizedStringKey(session.audio.playing ? "PLAYING":"STOPPED")).font(.caption.monospaced()).foregroundStyle(Color.muted)
                        .accessibilityValue(LocalizedStringKey(session.harmonyPreview ? "Preview":"Original")).accessibilityIdentifier("assistant.preview-state")
                    TextEditor(text:$input).focused($focused).disabled(dictation.recording || dictation.requesting || dictation.finalizing).frame(height:110).scrollContentBackground(.hidden).padding(8).modifier(StudioSurface()).overlay(alignment:.topLeading){if input.isEmpty && !focused{Text("Try: Tempo 110").font(.subheadline).foregroundStyle(Color.muted).padding(16).allowsHitTesting(false).accessibilityHidden(true)}}.accessibilityLabel("Command").accessibilityIdentifier("assistant.input")
                        .onChange(of:input){_,value in if value.count>2000{input=String(value.prefix(2000))};if value != generatedInput{cancelGeneration();proposal=nil;candidate=nil;proposalSource=nil};session.endHarmonyPreview()}
                    HStack {
                        Button("Examples"){focused=false;showExamples=true}.frame(minHeight:44).disabled(dictation.recording || dictation.requesting || dictation.finalizing).accessibilityIdentifier("assistant.examples")
                        Spacer()
                        languageControl.disabled(dictation.recording || dictation.requesting || dictation.finalizing)
                        Button{toggleDictation()}label:{Image(systemName:dictation.recording ? "stop.circle.fill":"mic.fill").frame(width:44,height:44).foregroundStyle(dictation.recording ? Color.record:Color.mint)}.accessibilityLabel(LocalizedStringKey(dictation.recording ? "Stop dictation":"Dictate a command")).disabled(dictation.requesting || dictation.finalizing)
                    }
                    if dictation.requesting{ProgressView("Preparing dictation…")}
                    if dictation.finalizing{ProgressView("Finishing dictation…")}
                    if dictation.recording{Label("LISTENING · COMMAND",systemImage:"waveform").font(.caption.monospaced()).foregroundStyle(Color.record)}
                    DisclosureGroup{Text("Dictation uses on-device recognition. You can always type. Humming has a separate melody recording.").font(.caption).foregroundStyle(Color.muted).padding(.vertical,8)}label:{Text("Dictation details").frame(maxWidth:.infinity,minHeight:44,alignment:.leading)}.font(.caption).foregroundStyle(Color.muted)
                    if let error=dictation.error{Text(LocalizedStringKey(error)).font(.caption).foregroundStyle(Color.record)}
                    Button{generate()}label:{Label("Review command",systemImage:"sparkles")}.buttonStyle(StudioActionStyle()).disabled(input.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || dictation.requesting || dictation.recording || dictation.finalizing || generationTask != nil).accessibilityIdentifier("assistant.generate")
                    if generationTask != nil{HStack{ProgressView("Preparing proposal…");Spacer();Button("Cancel generation"){cancelGeneration()}.frame(minHeight:44)}}
                    if let error{Text(LocalizedStringKey(error)).font(.callout).foregroundStyle(Color.record)}
                    if ambiguous {VStack(spacing:8){Button("Stretch chords evenly"){generate(.stretch)};Button("Repeat, one bar per chord"){generate(.repeatBars)}}.buttonStyle(.bordered).frame(maxWidth:.infinity)}
                    if let proposal,let candidate,let proposalSource{review(proposal,source:proposalSource,candidate:candidate)}
                }.padding(18)
            }.accessibilityIdentifier("assistant.review-scroll").scrollDismissesKeyboard(.interactively).background(Color.ink).navigationTitle("Assistant").navigationBarTitleDisplayMode(.inline)
                .toolbar{ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}}}
        }.tint(.mint)
        .sheet(isPresented:$showExamples){AssistantExamplesView(language:language){text,requiresAI in input=text;if requiresAI{mode = .onDeviceAI};showExamples=false}}
        .onChange(of:dictation.text){_,value in if !value.isEmpty{input=value}}
        .onChange(of:mode){_,_ in session.endHarmonyPreview();cancelGeneration();proposal=nil;candidate=nil;proposalSource=nil;error=nil}
        .onChange(of:language){_,value in session.endHarmonyPreview();cancelGeneration();proposal=nil;candidate=nil;proposalSource=nil;ai.refresh(localeIdentifier:value)}
        .onChange(of:dictation.recording){_,recording in if !recording{restoreAudio()}}
        .onChange(of:phase){_,p in if p == .background{cancelGeneration();dictation.cancel();restoreAudio()}else if p == .active{ai.refresh(localeIdentifier:language)}}
        .onReceive(NotificationCenter.default.publisher(for:AVAudioSession.interruptionNotification).receive(on:RunLoop.main)){_ in dictation.cancel();restoreAudio()}
        .onDisappear{cancelGeneration();dictation.cancel();restoreAudio();session.endHarmonyPreview()}
        .onAppear{ai.refresh(localeIdentifier:language);if let i=ProcessInfo.processInfo.arguments.firstIndex(of:"--screen"),ProcessInfo.processInfo.arguments.count>i+1{let target=ProcessInfo.processInfo.arguments[i+1];if target=="assistant-proposal"{input="Tempo 110; Chorus 8 bars: Am F C G each 2 bars";generate()}else if target=="assistant-song-proposal"{input="Song: Tempo 108; Key D minor; Intro 4 bars: Dm Gm A Dm; Chorus 8 bars: Dm Gm C F each 2 bars";generate()}}}
    }
    private var languageControl:some View {
        HStack(spacing:3){
            ForEach(["ru-RU","en-US"],id:\.self){code in
                Button{language=code}label:{
                    Text(verbatim:String(code.prefix(2)).uppercased()).font(.caption.weight(.semibold))
                        .frame(minWidth:44,minHeight:44)
                        .foregroundStyle(language==code ? Color.ink:Color.muted)
                        .background(language==code ? Color.mint:Color.clear,in:RoundedRectangle(cornerRadius:11,style:.continuous))
                }.buttonStyle(StudioQuietButtonStyle())
                    .accessibilityIdentifier("assistant.language."+String(code.prefix(2)))
                    .accessibilityAddTraits(language==code ? .isSelected:[])
            }
        }.padding(3).modifier(StudioSurface()).accessibilityElement(children:.contain).accessibilityLabel("Dictation language")
    }
    func review(_ proposal:AssistantProposal,source:Project,candidate:Project)->some View {
        VStack(alignment:.leading,spacing:14){
            SmallHeading(text:"PROPOSAL")
            if proposal.operations.contains(where:{$0.type == .arrangeSong}){formComparison(source:source,candidate:candidate)}
            ForEach(Array(proposal.operations.enumerated()),id:\.offset){_,op in Text(summary(op,scope:proposal.scopeSectionID,source:source,candidate:candidate)).padding(12).frame(maxWidth:.infinity,alignment:.leading).modifier(StudioSurface())}
            AssistantHarmonyReview(proposal:proposal,source:source,candidate:candidate)
            if !proposal.assumptions.isEmpty{SmallHeading(text:"ASSUMPTIONS");ForEach(proposal.assumptions,id:\.self){Text($0).font(.caption).foregroundStyle(Color.muted)}}
            ForEach(proposal.warnings,id:\.self){Label($0,systemImage:"exclamationmark.triangle").font(.caption).foregroundStyle(Color.harmony)}
            HStack(spacing:10){Button{previewB=false;session.previewAssistant(source,wholeSong:proposal.changesWholeSong,sectionID:proposal.scopeSectionID)}label:{Text("A · Original").frame(maxWidth:.infinity,minHeight:48).background(session.harmonyPreview && !previewB ? Color.mint.opacity(0.2):Color.raised,in:RoundedRectangle(cornerRadius:10))}.accessibilityIdentifier("assistant.a");Button{previewB=true;session.previewAssistant(candidate,wholeSong:proposal.changesWholeSong,sectionID:proposal.scopeSectionID)}label:{Text("B · Proposal").frame(maxWidth:.infinity,minHeight:48).background(session.harmonyPreview && previewB ? Color.mint.opacity(0.2):Color.raised,in:RoundedRectangle(cornerRadius:10))}.accessibilityIdentifier("assistant.b")}
            if session.harmonyPreview{Button("Stop preview"){session.endHarmonyPreview()}.frame(minHeight:44).accessibilityIdentifier("assistant.stop-preview")}
            Button{apply(proposal)}label:{Text("Apply proposal")}.buttonStyle(StudioActionStyle()).accessibilityIdentifier("assistant.apply")
            Text("One Undo restores the whole change.").font(.caption).foregroundStyle(Color.muted)
        }
    }
    func formComparison(source:Project,candidate:Project)->some View {VStack(alignment:.leading,spacing:10){
        SmallHeading(text:"ORIGINAL FORM")
        Text(source.sections.map{$0.name+" · "+String($0.length/barTicks)}.joined(separator:" → ")).font(.caption).foregroundStyle(Color.muted)
        SmallHeading(text:"PROPOSED FORM")
        ForEach(candidate.sections){section in HStack{Text(section.name);Spacer();Text("\(section.length/barTicks) bars").font(.caption.monospaced())}.font(.subheadline).padding(.vertical,4)}
    }.padding(12).modifier(StudioSurface()).accessibilityIdentifier("assistant.form-review")}
    func summary(_ op:AssistantOperation,scope:UUID,source:Project,candidate:Project)->String {
        let scopeName=source.sections.first{$0.id==scope}?.name ?? ""
        let section=candidate.sections.first{$0.id==op.sectionID}?.name ?? scopeName
        switch op.type {
        case .setTempo:return "\(Int(op.bpm ?? 120)) BPM"
        case .setKey:return NSLocalizedString("Key",comment:"")+": "+Chord.roots[op.root ?? 0]+" "+NSLocalizedString((op.minor ?? false) ? "minor":"major",comment:"Key mode")
        case .renameSection:return (source.sections.first{$0.id==op.sectionID}?.name ?? scopeName)+" → "+(op.name ?? "")
        case .resizeSection:return section+": \(op.bars ?? 4) "+NSLocalizedString("bars",comment:"")
        case .setProgression:return section+" · "+zip(op.chords ?? [],op.durations ?? []).map{"\($0.symbol) (\($1))"}.joined(separator:" · ")+" "+NSLocalizedString("bars per chord",comment:"")
        case .arrangeSong:return (op.sections ?? []).map{part in
            let sourceName=source.sections.first{$0.id==part.sourceSectionID}?.name ?? ""
            return part.name+" · \(part.bars) "+NSLocalizedString("bars",comment:"")+" · "+zip(part.chords,part.durations).map{"\($0.symbol) (\($1))"}.joined(separator:" · ")+"\n"+NSLocalizedString("Rhythm and melody source",comment:"Assistant")+": "+sourceName
        }.joined(separator:"\n\n")
        case .styleHarmony,.styleSong:return (op.type == .styleSong ? NSLocalizedString("Whole song",comment:"Assistant"):section)+" · "+NSLocalizedString(HarmonyStyle(rawValue:op.style ?? "")?.title ?? "Harmony",comment:"Assistant")
        }
    }
    func generate(_ distribution:ChordDistribution?=nil){
        cancelGeneration();focused=false;session.endHarmonyPreview();ambiguous=false;generatedInput=input;proposal=nil;candidate=nil;proposalSource=nil;error=nil;generatedWithAI=false
        let snapshot=session.project,scope=session.section.id
        if mode != .onDeviceAI {
            do{let p=try AssistantEngine.propose(input,project:snapshot,sectionID:scope,distribution:distribution);candidate=try p.candidate(for:snapshot);proposalSource=snapshot;proposal=p;return}
            catch{if case AssistantError.ambiguous=error{self.error=error.localizedDescription;ambiguous=true;return};if mode == .commands{self.error=error.localizedDescription;return};if !(error is AssistantError){self.error=error.localizedDescription;return};if case AssistantError.unsupported=error{}else{self.error=error.localizedDescription;return}}
        }
        ai.refresh(localeIdentifier:language)
        guard ai.available else{error=ai.availabilityMessage;return}
        let request=input,locale=language,attempt=generationID
        generationTask=Task { @MainActor in
            do {
                let p=try await ai.propose(request,project:snapshot,sectionID:scope,localeIdentifier:locale)
                guard !Task.isCancelled,generationID==attempt,input==request else{return}
                candidate=try p.candidate(for:session.project);proposalSource=snapshot;proposal=p;generatedWithAI=true;error=nil
            }catch{guard generationID==attempt,!Task.isCancelled else{return};self.error=error.localizedDescription;proposal=nil;candidate=nil;proposalSource=nil}
            guard generationID==attempt else{return};generationTask=nil;timeoutTask?.cancel();timeoutTask=nil
        }
        timeoutTask=Task { @MainActor in
            do{try await Task.sleep(for:.seconds(45))}catch{return}
            guard generationID==attempt,generationTask != nil else{return}
            cancelGeneration();error=NSLocalizedString("The AI proposal timed out. Try a shorter description or use Commands.",comment:"Assistant")
        }
    }
    func cancelGeneration(){generationID+=1;generationTask?.cancel();generationTask=nil;timeoutTask?.cancel();timeoutTask=nil}
    func apply(_ proposal:AssistantProposal){
        do{_ = try proposal.candidate(for:session.project)}catch{self.error=error.localizedDescription;return}
        session.endHarmonyPreview();session.finishTake();let revision=session.project.revision
        session.edit{try proposal.apply(to:&$0)}
        if session.project.revision>revision{if let section=session.project.sections.first(where:{$0.id==proposal.scopeSectionID}){session.select(section)};dismiss()}
    }
    func toggleDictation(){
        focused=false
        if dictation.recording{dictation.stop();restoreAudio();return}
        guard !dictation.finalizing,let lease=session.beginMicrophone(stop:{dictation.cancel()})else{return};microphoneLease=lease
        Task{guard session.ownsMicrophone(lease)else{return};await dictation.start(locale:language,audio:session.audio);if !dictation.recording{session.endMicrophone(lease);if microphoneLease==lease{microphoneLease=nil}}}
    }
    func restoreAudio(){if let lease=microphoneLease{microphoneLease=nil;session.endMicrophone(lease)}}
}

/// Read the exact proposal snapshots, including clip offsets/repeats, rather
/// than consulting a project that may change through MIDI while review is open.
private struct AssistantHarmonyReview:View {
    let proposal:AssistantProposal
    let source:Project
    let candidate:Project
    private var sections:[MusicDomain.Section] {
        let wholeSong=proposal.operations.contains{$0.type == .styleSong}
        let selected=Set(proposal.operations.filter{$0.type == .styleHarmony}.compactMap(\.sectionID))
        return source.sections.filter{selected.contains($0.id) || (wholeSong && !Arrangement.harmony(source,section:$0).isEmpty)}
    }
    var body:some View {
        if !sections.isEmpty {
            VStack(alignment:.leading,spacing:14){
                SmallHeading(text:"ORIGINAL → PROPOSAL").accessibilityIdentifier("assistant.harmony.heading")
                ForEach(Array(sections.enumerated()),id:\.offset){index,section in
                    if let proposed=candidate.sections.first(where:{$0.id==section.id}) {
                        AssistantHarmonySectionReview(section:section,proposed:proposed,
                            before:Arrangement.harmony(source,section:section),
                            after:Arrangement.harmony(candidate,section:proposed),
                            originalScale:scale(source),proposedScale:scale(candidate),index:index)
                    }
                }
            }
        }
    }
    private func scale(_ project:Project)->Set<Int>{
        Set((project.minor ? [0,2,3,5,7,8,10]:[0,2,4,5,7,9,11]).map{($0+project.keyRoot)%12})
    }
}

private struct AssistantHarmonySectionReview:View {
    let section:MusicDomain.Section
    let proposed:MusicDomain.Section
    let before:[ChordEvent]
    let after:[ChordEvent]
    let originalScale:Set<Int>
    let proposedScale:Set<Int>
    let index:Int
    @Environment(\.dynamicTypeSize) private var dynamicType
    var body:some View {
        VStack(alignment:.leading,spacing:12){
            Text(verbatim:section.name==proposed.name ? section.name:section.name+" → "+proposed.name)
                .font(.headline).fixedSize(horizontal:false,vertical:true)
                .accessibilityIdentifier("assistant.harmony.section.\(index)")
            if dynamicType.isAccessibilitySize {
                original
                proposal
            }else{
                HStack(alignment:.top,spacing:14){original;proposal}
            }
        }.padding(12).modifier(StudioSurface())
    }
    private var original:some View {
        AssistantHarmonyColumn(title:"A · Original",events:before,scale:originalScale,sectionStart:section.start,identifier:"assistant.harmony.before.\(index)",color:.studioText)
    }
    private var proposal:some View {
        AssistantHarmonyColumn(title:"B · Proposal",events:after,scale:proposedScale,sectionStart:proposed.start,identifier:"assistant.harmony.after.\(index)",color:.harmony)
    }
}

private struct AssistantHarmonyColumn:View {
    let title:String
    let events:[ChordEvent]
    let scale:Set<Int>
    let sectionStart:Int
    let identifier:String
    let color:Color
    var body:some View {
        VStack(alignment:.leading,spacing:14){
            Text(LocalizedStringKey(title)).font(.caption.weight(.semibold)).foregroundStyle(Color.muted)
            if events.isEmpty{Text("No chords in this section.").font(.caption).foregroundStyle(Color.muted)}
            ForEach(Array(events.enumerated()),id:\.offset){index,event in
                VStack(alignment:.leading,spacing:5){
                    Text(verbatim:event.chord.symbol).font(.system(.title3,weight:.semibold)).foregroundStyle(color)
                        .fixedSize(horizontal:false,vertical:true).accessibilityIdentifier(identifier+".\(index)")
                    Text(verbatim:timing(event)).font(.caption.monospaced()).foregroundStyle(Color.muted)
                        .fixedSize(horizontal:false,vertical:true).accessibilityIdentifier(identifier+".\(index).timing")
                    Text(verbatim:event.chord.notes.map{NoteEvent(tick:0,pitch:$0).name}.joined(separator:" · "))
                        .font(.caption2).foregroundStyle(Color.muted).fixedSize(horizontal:false,vertical:true)
                    if event.chord.notes.contains(where:{!scale.contains($0%12)}){
                        Label("Contains chromatic notes",systemImage:"circle.lefthalf.filled")
                            .font(.caption2).foregroundStyle(Color.harmony).fixedSize(horizontal:false,vertical:true)
                    }
                }
            }
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
    private func timing(_ event:ChordEvent)->String {
        let position=MusicalPosition(tick:sectionStart+event.tick).description
        let beats=(Double(event.duration)/Double(ppq)).formatted(.number.precision(.fractionLength(0...3)))
        return String(format:NSLocalizedString("Bar %@ · %@ beats (%d ticks)",comment:"Assistant harmony event timing"),position,beats,event.duration)
    }
}

/// Long musical examples remain ordinary list buttons with stable hit targets.
/// A sheet also lets VoiceOver and larger type browse the complete commands.
private struct AssistantExamplesView:View {
    let language:String
    let choose:(String,Bool)->Void
    @Environment(\.dismiss) private var dismiss
    var body:some View {NavigationStack{List{
        Button("Tempo 110"){choose("Tempo 110",false)}
        Button("Key D minor"){choose("Key D minor",false)}
        Button("Chorus 8 bars: Am F C G each 2 bars"){choose("Chorus 8 bars: Am F C G each 2 bars",false)}
        Button("Припев 8 тактов: Am F C G по два такта"){choose("Припев 8 тактов: Am F C G по два такта",false)}
        Button("Jazz up this section"){choose("Поджазуй",false)}.accessibilityIdentifier("assistant.example.jazzify")
        Button("Song: Intro 4 bars: Dm Gm A Dm; Chorus 8 bars: Dm Gm C F each 2 bars"){choose("Song: Intro 4 bars: Dm Gm A Dm; Chorus 8 bars: Dm Gm C F each 2 bars",false)}.accessibilityIdentifier("assistant.example.song-form")
        Button{choose(language.hasPrefix("ru") ? "Создай форму: интро 4 такта, куплет 8 тактов и припев 8 тактов. Тональность Ре минор, темп 108. Используй Dm7 Gm7 A7 Dm7.":"Create a song form: 4-bar intro, 8-bar verse and 8-bar chorus in D minor at 108 BPM, using Dm7 Gm7 A7 Dm7.",true)}label:{Label("Create a complete song form",systemImage:"sparkles")}
    }.environment(\.defaultMinListRowHeight,52).navigationTitle("Examples").navigationBarTitleDisplayMode(.inline).toolbar{ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}}}}
    .presentationDetents([.large]).tint(.mint)}
}
