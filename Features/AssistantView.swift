import SwiftUI
import MusicDomain
import AVFoundation

struct AssistantView:View {
    @Bindable var session:Session
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
    @State private var aiLanguage="ru-RU"
    @State private var dictation=DictationController()
    @State private var ai=AIComposerController()
    @State private var mode:AssistantMode = .automatic
    @State private var generatedWithAI=false
    @State private var usedUnavailableAIFallback=false
    @State private var availabilityError=false
    @State private var generationID=0
    @State private var generationTask:Task<Void,Never>?
    @State private var timeoutTask:Task<Void,Never>?
    @State private var microphoneLease:UUID?
    @State private var showExamples=false
    @State private var showAIOptions=false
    var body:some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:18){
                    Text("An idea, in your words.").font(.headline)
                    Text("Describe a song form, chords or a harmonic change. Review every change before applying.").font(.caption).foregroundStyle(Color.muted)
                    HStack{Text(session.section.name).fontWeight(.medium);Spacer();Text("\(session.section.length/barTicks) bars · \(Int(session.project.bpm)) BPM").font(.caption.monospaced()).foregroundStyle(Color.muted);CapsuleLabel(text:proposal != nil && generatedWithAI ? "ON-DEVICE AI":"LOCAL",color:.mint)}
                    Text(LocalizedStringKey(session.audio.playing ? "PLAYING":"STOPPED")).font(.caption.monospaced()).foregroundStyle(Color.muted)
                        .accessibilityValue(LocalizedStringKey(session.harmonyPreview ? "Preview":"Original")).accessibilityIdentifier("assistant.preview-state")
                    TextEditor(text:$input).focused($focused).disabled(dictation.recording || dictation.requesting || dictation.finalizing).frame(height:110).scrollContentBackground(.hidden).padding(8).modifier(StudioSurface()).overlay(alignment:.topLeading){if input.isEmpty && !focused{Text("Try: Tempo 110").font(.subheadline).foregroundStyle(Color.muted).padding(16).allowsHitTesting(false).accessibilityHidden(true)}}.accessibilityLabel("Command").accessibilityIdentifier("assistant.input")
                        .onChange(of:input){_,value in if value.count>2000{input=String(value.prefix(2000))};if value != generatedInput{cancelGeneration();proposal=nil;candidate=nil;proposalSource=nil;usedUnavailableAIFallback=false};session.endHarmonyPreview()}
                    HStack {
                        Button("Examples"){focused=false;showExamples=true}.frame(minHeight:44).disabled(dictation.recording || dictation.requesting || dictation.finalizing).accessibilityIdentifier("assistant.examples")
                        Spacer()
                        VStack(spacing:2){Text("Dictation language").font(.caption2).foregroundStyle(Color.muted);languageControl}.disabled(dictation.recording || dictation.requesting || dictation.finalizing)
                        Button{toggleDictation()}label:{Image(systemName:dictation.recording ? "stop.circle.fill":"mic.fill").frame(width:44,height:44).foregroundStyle(dictation.recording ? Color.record:Color.mint)}.accessibilityLabel(LocalizedStringKey(dictation.recording ? "Stop dictation":"Dictate a command")).accessibilityIdentifier("assistant.dictate").accessibilityValue(Text(verbatim:dictation.diagnosticState)).disabled(dictation.requesting || dictation.finalizing)
                    }
                    if dictation.requesting{ProgressView("Preparing dictation…")}
                    if dictation.finalizing{ProgressView("Finishing dictation…")}
                    if dictation.recording{Label("LISTENING · COMMAND",systemImage:"waveform").font(.caption.monospaced()).foregroundStyle(Color.record)}
                    StudioSegments(title:"Assistant mode",selection:$mode,options:AssistantMode.allCases.map{($0,LocalizedStringKey($0.title))}).disabled(dictation.recording || dictation.requesting || dictation.finalizing)
                    aiAvailability
                    if let error=dictation.error{Text(LocalizedStringKey(error)).font(.caption).foregroundStyle(Color.record).accessibilityIdentifier("assistant.dictation-error")}
                    Button{generate()}label:{Label("Review command",systemImage:"sparkles")}.buttonStyle(StudioActionStyle()).disabled(input.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || dictation.requesting || dictation.recording || dictation.finalizing || generationTask != nil).accessibilityIdentifier("assistant.generate")
                    if mode != .commands{aiOptions}
                    DisclosureGroup{Text("Dictation uses on-device recognition. You can always type. Humming has a separate melody recording.").font(.caption).foregroundStyle(Color.muted).padding(.vertical,8)}label:{Text("Dictation details").frame(maxWidth:.infinity,minHeight:44,alignment:.leading)}.font(.caption).foregroundStyle(Color.muted)
                    if generationTask != nil{HStack{ProgressView("Preparing proposal…");Spacer();Button("Cancel generation"){cancelGeneration()}.frame(minHeight:44)}}
                    if let error{
                        Text(LocalizedStringKey(error)).font(.callout).foregroundStyle(Color.record).accessibilityIdentifier("assistant.error")
                    }
                    if ambiguous {VStack(spacing:8){Button("Stretch chords evenly"){generate(.stretch)};Button("Repeat, one bar per chord"){generate(.repeatBars)}}.buttonStyle(.bordered).frame(maxWidth:.infinity)}
                    if let proposal,let candidate,let proposalSource{review(proposal,source:proposalSource,candidate:candidate)}
                }.padding(18)
            }.accessibilityIdentifier("assistant.review-scroll").scrollDismissesKeyboard(.interactively).background(Color.ink).navigationTitle("Assistant").navigationBarTitleDisplayMode(.inline)
                .toolbar{ToolbarItem(placement:.cancellationAction){Button("Cancel"){closeEditor()}}}
        }.tint(.mint)
        .sheet(isPresented:$showExamples){AssistantExamplesView(language:language){text,requiresAI in input=text;if requiresAI{mode = .onDeviceAI};showExamples=false}}
        .onChange(of:dictation.text){_,value in if !value.isEmpty{input=value}}
        .onChange(of:mode){_,_ in resetReview();refreshAIStatus()}
        .onChange(of:language){_,_ in resetReview();refreshAIStatus()}
        .onChange(of:aiLanguage){_,_ in resetReview();refreshAIStatus()}
        .onChange(of:dictation.recording){_,recording in if !recording{restoreAudio()}}
        .onChange(of:phase){_,p in if p == .background{cancelGeneration();dictation.cancel();restoreAudio()}else if p == .active{refreshAIStatus()}}
        .onReceive(NotificationCenter.default.publisher(for:AVAudioSession.interruptionNotification).receive(on:RunLoop.main)){_ in dictation.cancel();restoreAudio()}
        .onDisappear{cancelGeneration();dictation.cancel();restoreAudio();session.endHarmonyPreview()}
        .onAppear{refreshAIStatus();if let i=ProcessInfo.processInfo.arguments.firstIndex(of:"--screen"),ProcessInfo.processInfo.arguments.count>i+1{let target=ProcessInfo.processInfo.arguments[i+1];if target=="assistant-proposal"{input="Tempo 110; Chorus 8 bars: Am F C G each 2 bars";generate()}else if target=="assistant-song-proposal"{input="Song: Tempo 108; Key D minor; Intro 4 bars: Dm Gm A Dm; Chorus 8 bars: Dm Gm C F each 2 bars";generate()}}}
    }
    private var aiAvailability:some View {
        VStack(alignment:.leading,spacing:8){
            Text(mode == .commands ? NSLocalizedString("Commands work without Apple Intelligence.",comment:"Assistant availability"):ai.availabilityMessage)
                .font(.caption).foregroundStyle(Color.muted).accessibilityIdentifier("assistant.ai-status")
                .accessibilityValue(Text(verbatim:aiAvailabilityDiagnostic))
            if mode != .commands {
                if !ai.available {
                    Button("Use Commands"){mode = .commands}.frame(minHeight:44)
                        .accessibilityIdentifier("assistant.use-commands")
                        .disabled(dictation.recording || dictation.requesting || dictation.finalizing)
                }
            }
        }
    }
    private var aiOptions:some View {
        VStack(alignment:.leading,spacing:0){
            Button{showAIOptions.toggle()}label:{HStack{Text("AI language and setup");Spacer();Image(systemName:showAIOptions ? "chevron.up":"chevron.down").accessibilityHidden(true)}.frame(maxWidth:.infinity,minHeight:44).contentShape(Rectangle())}
                .buttonStyle(StudioQuietButtonStyle()).accessibilityIdentifier("assistant.ai-options")
                .accessibilityValue(LocalizedStringKey(showAIOptions ? "Expanded":"Collapsed"))
            if showAIOptions{VStack(alignment:.leading,spacing:10){
                HStack{Text("AI request language").font(.caption);Spacer();languageSelector($aiLanguage,title:"AI request language",identifier:"assistant.ai-language.")}
                Text("AI requests and dictation have separate languages. Neither changes automatically.")
                    .font(.caption).foregroundStyle(Color.muted).accessibilityIdentifier("assistant.ai-language-guidance")
                if let guidance=ai.availabilityGuidance{Text(guidance).font(.caption).foregroundStyle(Color.muted).accessibilityIdentifier("assistant.ai-setup")}
                Button("Recheck AI"){refreshAIStatus()}.frame(minHeight:44).accessibilityIdentifier("assistant.ai-recheck")
            }.padding(.vertical,8)}
        }.font(.caption).foregroundStyle(Color.muted).disabled(dictation.recording || dictation.requesting || dictation.finalizing)
    }
    private var aiAvailabilityDiagnostic:String {
        guard ProcessInfo.processInfo.arguments.contains("--uitesting")else{return ""}
        return mode == .commands ? "commands":ai.availabilityReason.rawValue
    }
    private var languageControl:some View {
        languageSelector($language,title:"Dictation language",identifier:"assistant.language.")
    }
    private func languageSelector(_ selection:Binding<String>,title:LocalizedStringKey,identifier:String)->some View {
        HStack(spacing:3){
            ForEach(["ru-RU","en-US"],id:\.self){code in
                Button{selection.wrappedValue=code}label:{
                    Text(verbatim:String(code.prefix(2)).uppercased()).font(.caption.weight(.semibold))
                        .frame(minWidth:44,minHeight:44)
                        .foregroundStyle(selection.wrappedValue==code ? Color.ink:Color.muted)
                        .background(selection.wrappedValue==code ? Color.mint:Color.clear,in:RoundedRectangle(cornerRadius:11,style:.continuous))
                }.buttonStyle(StudioQuietButtonStyle())
                    .accessibilityIdentifier(identifier+String(code.prefix(2)))
                    .accessibilityAddTraits(selection.wrappedValue==code ? .isSelected:[])
            }
        }.padding(3).modifier(StudioSurface()).accessibilityElement(children:.contain).accessibilityLabel(title)
    }
    func review(_ proposal:AssistantProposal,source:Project,candidate:Project)->some View {
        VStack(alignment:.leading,spacing:14){
            SmallHeading(text:"PROPOSAL")
            if usedUnavailableAIFallback && !ai.available {
                Text("Reviewed with Commands because on-device AI is unavailable.")
                    .font(.caption).foregroundStyle(Color.muted)
                    .accessibilityIdentifier("assistant.local-fallback")
            }
            if proposal.operations.contains(where:{$0.type == .arrangeSong}){
                Text("Creates form and chords. Existing drum and melody parts are reused; new parts are not generated.").font(.caption).foregroundStyle(Color.muted).accessibilityIdentifier("assistant.composition-scope")
                if reusedPartsContainEmptySections(proposal,source:source,role:.drums){Label("Source sections without drum notes stay empty. Add a beat in Jam.",systemImage:"exclamationmark.triangle").font(.caption).foregroundStyle(Color.harmony).accessibilityIdentifier("assistant.empty-drums")}
                if reusedPartsContainEmptySections(proposal,source:source,role:.melody){Label("Source sections without melody notes stay empty. Add notes or record a melody.",systemImage:"exclamationmark.triangle").font(.caption).foregroundStyle(Color.harmony).accessibilityIdentifier("assistant.empty-melody")}
                formComparison(source:source,candidate:candidate)
            }
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
    private func reusedPartsContainEmptySections(_ proposal:AssistantProposal,source:Project,role:TrackRole)->Bool {
        let parts=proposal.operations.filter{$0.type == .arrangeSong}.flatMap{$0.sections ?? []}
        guard !parts.isEmpty else{return false}
        return parts.contains{part in
            guard let section=source.sections.first(where:{$0.id==part.sourceSectionID})else{return false}
            return source.tracks.filter{$0.role==role}.allSatisfy{track in
                let material=Arrangement.materialize(source,track:track,section:section)
                return role == .drums ? material.drums.isEmpty:(material.notes ?? []).isEmpty
            }
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
        cancelGeneration();focused=false;session.endHarmonyPreview();ambiguous=false;generatedInput=input;proposal=nil;candidate=nil;proposalSource=nil;error=nil;generatedWithAI=false;usedUnavailableAIFallback=false;availabilityError=false
        let snapshot=session.project,scope=session.section.id
        ai.refresh(localeIdentifier:aiLanguage)
        // A disabled/unavailable model must not block an understood command.
        // Keep the proposal explicitly LOCAL and explain the fallback; never
        // describe the parser's result as a model-generated arrangement.
        if mode != .onDeviceAI || !ai.available {
            do{let p=try AssistantEngine.propose(input,project:snapshot,sectionID:scope,distribution:distribution);candidate=try p.candidate(for:snapshot);proposalSource=snapshot;proposal=p;usedUnavailableAIFallback=mode == .onDeviceAI && !ai.available;return}
            catch{if case AssistantError.ambiguous=error{self.error=error.localizedDescription;ambiguous=true;return};if mode == .commands{self.error=error.localizedDescription;return};if !(error is AssistantError){self.error=error.localizedDescription;return};if case AssistantError.unsupported=error{}else{self.error=error.localizedDescription;return}}
        }
        guard ai.available else{error=ai.availabilityMessage;availabilityError=true;return}
        let request=input,locale=aiLanguage,attempt=generationID
        generationTask=Task { @MainActor in
            do {
                let p=try await ai.propose(request,project:snapshot,sectionID:scope,localeIdentifier:locale)
                guard !Task.isCancelled,generationID==attempt,input==request else{return}
                candidate=try p.candidate(for:session.project);proposalSource=snapshot;proposal=p;generatedWithAI=true;error=nil
            }catch{
                guard generationID==attempt,!Task.isCancelled else{return}
                if let failure=error as? AIComposerFailure,case .unavailable=failure{self.error=ai.availabilityMessage;availabilityError=true}
                else{self.error=error.localizedDescription;availabilityError=false}
                proposal=nil;candidate=nil;proposalSource=nil
            }
            guard generationID==attempt else{return};generationTask=nil;timeoutTask?.cancel();timeoutTask=nil
        }
        timeoutTask=Task { @MainActor in
            do{try await Task.sleep(for:.seconds(45))}catch{return}
            guard generationID==attempt,generationTask != nil else{return}
            cancelGeneration();error=NSLocalizedString("The AI proposal timed out. Try a shorter description or use Commands.",comment:"Assistant")
        }
    }
    func cancelGeneration(){generationID+=1;generationTask?.cancel();generationTask=nil;timeoutTask?.cancel();timeoutTask=nil}
    private func resetReview(){
        session.endHarmonyPreview();cancelGeneration();proposal=nil;candidate=nil;proposalSource=nil;usedUnavailableAIFallback=false;error=nil;availabilityError=false
    }
    private func refreshAIStatus(){
        ai.refresh(localeIdentifier:aiLanguage)
        if availabilityError {
            error=ai.available ? nil:ai.availabilityMessage
            availabilityError = !ai.available
        }
    }
    private func closeEditor(){
        // Studio owns this editor's presentation. After changing mode or
        // removing a proposal, the environment dismiss action can leave the
        // Assistant covering Grid; close the authoritative presentation item.
        session.sheet=nil
    }
    func apply(_ proposal:AssistantProposal){
        do{_ = try proposal.candidate(for:session.project)}catch{self.error=error.localizedDescription;return}
        session.endHarmonyPreview();session.finishTake();let revision=session.project.revision
        session.edit{try proposal.apply(to:&$0)}
        if session.project.revision>revision{if let section=session.project.sections.first(where:{$0.id==proposal.scopeSectionID}){session.select(section)};closeEditor()}
    }
    func toggleDictation(){
        focused=false
        if dictation.recording{dictation.stop();restoreAudio();return}
        guard !dictation.finalizing else{return}
        guard session.ensureAudio()else{dictation.error=session.audio.error;return}
        guard let lease=session.beginMicrophone(stop:{dictation.cancel()})else{return};microphoneLease=lease
        Task{
            guard session.ownsMicrophone(lease)else{return}
            let previousEngine=session.audio.captureEngine
            await dictation.start(locale:language,audio:session.audio)
            if session.audio.captureEngine !== previousEngine,session.audio.isPrepared{session.sync()}
            if !dictation.recording{session.endMicrophone(lease);if microphoneLease==lease{microphoneLease=nil}}
        }
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
        return String(format:NSLocalizedString("Bar %@ · %@ beats",comment:"Assistant harmony event timing"),position,beats)
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
        Button{choose(language.hasPrefix("ru") ? "Создай форму: интро 4 такта, куплет 8 тактов и припев 8 тактов. Тональность Ре минор, темп 108. Используй Dm7 Gm7 A7 Dm7.":"Create a song form: 4-bar intro, 8-bar verse and 8-bar chorus in D minor at 108 BPM, using Dm7 Gm7 A7 Dm7.",true)}label:{Label("Create a complete song form",systemImage:"sparkles")}.accessibilityIdentifier("assistant.example.ai-song")
    }.environment(\.defaultMinListRowHeight,52).navigationTitle("Examples").navigationBarTitleDisplayMode(.inline).toolbar{ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}}}}
    .presentationDetents([.large]).tint(.mint)}
}
