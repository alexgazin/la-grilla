import SwiftUI
import MusicDomain
import AVFoundation

private struct VoiceReviewContext {
    let projectID:UUID
    var revision:Int
    let sectionID:UUID
    var sectionName:String
    var sectionStart:Int
    var sectionLength:Int
    let captureBPM:Double
    var scaleRoot:Int
    var minor:Bool
    let plan:VoiceCapturePlan
}

struct VoiceToMIDIView:View {
    @Bindable var session:Session
    @AppStorage("studio.pitchSpelling") private var spellingValue=PitchSpelling.automatic.rawValue
    private var spelling:PitchSpelling{PitchSpelling(rawValue:spellingValue) ?? .automatic}
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var capture=VoiceCaptureController()
    @State private var countIn=true
    @State private var notes:[NoteEvent]=[]
    @State private var selected:UUID?
    @State private var quantize:Quantize = .off
    @State private var snapScale=false
    @State private var offset=0.0
    @State private var target:UUID?
    @State private var error:String?
    @State private var applying=false
    @State private var applied=false
    @State private var microphoneLease:UUID?
    @State private var context:VoiceReviewContext?
    @State private var pendingContext:VoiceReviewContext?
    var draftLocked:Bool{applied || applying || capture.isCapturing || capture.state == .analyzing}
    var note:NoteEvent?{notes.first{$0.id==selected}}
    var synthetic:Bool{let args=ProcessInfo.processInfo.arguments;return args.contains("--uitesting") && args.contains("voice-draft")}
    private var displayContext:VoiceReviewContext?{capture.isCapturing ? pendingContext:context}
    private func noteName(_ pitch:Int)->String{MusicalNotation.noteName(pitch,keyRoot:displayContext?.scaleRoot ?? session.project.keyRoot,minor:displayContext?.minor ?? session.project.minor,spelling:spelling)}
    var sourceSectionName:String{displayContext?.sectionName ?? session.section.name}
    var sectionLength:Int{context?.sectionLength ?? session.section.length}
    var limit:Double{capture.isCapturing && capture.plannedDuration>0 ? capture.plannedDuration:(displayContext?.plan.duration ?? min(30,Double(session.section.length)/Double(ppq)*60/session.project.bpm))}
    var stale:Bool{guard let context else{return false};return context.projectID != session.project.id || context.revision != session.project.revision || !session.project.sections.contains{$0.id==context.sectionID && $0.start==context.sectionStart && $0.length==context.sectionLength}}
    var body:some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:18){
                    Text("Hum it. Shape it.").font(.system(.title2,weight:.semibold)).tracking(-0.6)
                    Text("Record one melody with headphones, then review the notes.").font(.caption).foregroundStyle(Color.muted)
                    DisclosureGroup{Text("Record one melody in a quiet room. Use headphones. Microphone monitoring is off. Review uncertain notes before applying.").font(.caption).foregroundStyle(Color.muted).padding(.vertical,8)}label:{Text("Recording guide").frame(maxWidth:.infinity,minHeight:44,alignment:.leading)}.font(.caption).foregroundStyle(Color.muted)
                    HStack{Text(sourceSectionName).fontWeight(.medium);Spacer();Text("\(Int(limit)) s · \(Int(displayContext?.captureBPM ?? session.project.bpm)) BPM").font(.caption.monospaced()).foregroundStyle(Color.muted);CapsuleLabel(text:"BETA · MONO",color:.record)}
                    if let displayContext{HStack{Text("Recording starts at bar");Text(String(displayContext.plan.startTick/barTicks+1)).monospacedDigit()}.font(.caption).foregroundStyle(Color.muted)}
                    Text("Capture ends at the section or loop edge. The beat plays during capture; microphone setup and finishing may briefly interrupt playback.").font(.caption).foregroundStyle(Color.muted)
                    if synthetic{Text("QA FIXTURE · SYNTHETIC SOURCE").font(.caption.monospaced()).foregroundStyle(Color.harmony)}
                    recordingControls
                    if let result=capture.result{draft(result).disabled(capture.isCapturing || capture.state == .analyzing)}
                    if let error=capture.error{Text(LocalizedStringKey(error)).font(.callout).foregroundStyle(Color.record)}
                    if let error{Text(LocalizedStringKey(error)).font(.callout).foregroundStyle(Color.record)}
                }.padding(18)
            }.accessibilityIdentifier("voice.review-scroll").background(Color.ink).navigationTitle("Voice to MIDI").navigationBarTitleDisplayMode(.inline)
                .toolbar{ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}.disabled(applying)}}
        }.tint(.record).interactiveDismissDisabled(applying)
        .onChange(of:capture.result?.record.id){_,id in if id != nil{if let pendingContext{context=pendingContext;self.pendingContext=nil};resetNotes()}}
        .onChange(of:capture.state){_,state in if state == .analyzing || state == .idle || state == .ready{restoreAudio()}}
        .onReceive(Timer.publish(every:0.1,on:.main,in:.common).autoconnect()){_ in capture.pollOriginal()}
        .onReceive(NotificationCenter.default.publisher(for:AVAudioSession.interruptionNotification).receive(on:RunLoop.main)){_ in capture.stop();capture.stopOriginal()}
        .onChange(of:phase){_,value in if value == .background{capture.stop();capture.stopOriginal();session.endHarmonyPreview()}}
        .onDisappear{capture.discard();session.endHarmonyPreview();restoreAudio()}
        .task{if synthetic{do{pendingContext=try makeContext(minimumLead:0,playing:false);await capture.loadFixture()}catch{self.error=error.localizedDescription}}}
    }
    var recordingControls:some View {
        VStack(spacing:12){
            if capture.state == .preparing{ProgressView("Preparing microphone…").tint(.record)}
            if capture.state == .waiting{HStack{ProgressView().tint(.record);Text("Waiting for the recording start…");Spacer();Text(String(format:NSLocalizedString("%.1f s",comment:"Countdown seconds"),capture.waitingSeconds)).monospacedDigit()}.font(.callout).accessibilityIdentifier("voice.waiting")}
            if capture.state == .countIn{Text("\(capture.remaining)").font(.system(size:64,weight:.medium,design:.monospaced)).foregroundStyle(Color.record)}
            if capture.state == .recording{HStack{Circle().fill(Color.record).frame(width:9,height:9);Text(String(format:NSLocalizedString("%.1f s",comment:"Recording seconds"),capture.elapsed)).font(.title2.monospaced());Spacer();ProgressView(value:min(1,capture.level)).tint(.record).frame(width:100)}}
            if capture.state == .analyzing{ProgressView("Analyzing melody…",value:capture.progress).tint(.record)}
            if capture.isCapturing{Button{capture.stop()}label:{Label("Stop recording",systemImage:"stop.fill")}.buttonStyle(StudioActionStyle(color:.record))}
            else if capture.state != .analyzing && !applied{
                Toggle("One-bar count-in",isOn:$countIn).disabled(applying)
                Button{record()}label:{Label(LocalizedStringKey(capture.result==nil ? "Record melody":"Record again"),systemImage:"record.circle")}.buttonStyle(StudioActionStyle(color:.record)).disabled(applying)
            }
        }
    }
    func draft(_ result:VoiceCaptureResult)->some View {
        VStack(alignment:.leading,spacing:16){
            Canvas{context,size in for (i,amplitude) in result.analysis.waveform.enumerated(){let x=CGFloat(i)/CGFloat(max(1,result.analysis.waveform.count))*size.width,h=max(1,CGFloat(amplitude)*size.height);context.fill(Path(CGRect(x:x,y:(size.height-h)/2,width:2,height:h)),with:.color(.record.opacity(0.6)))}}.frame(height:64).background(Color.panel,in:RoundedRectangle(cornerRadius:Luz.Radius.cell,style:.continuous)).accessibilityLabel("Original voice waveform")
            HStack{Text("\(notes.count) notes").font(.headline).accessibilityIdentifier("voice.note-count");Spacer();Text("\(notes.filter{($0.confidence ?? 1)<0.9}.count) uncertain").font(.caption).foregroundStyle(Color.harmony)}
            if notes.isEmpty{Text("No stable notes were found. Listen to the original or try a clearer phrase.").font(.callout).foregroundStyle(Color.harmony)}
            HStack(spacing:10){
                Button{original()}label:{Label(LocalizedStringKey(capture.originalPlaying ? "Stop original":"Original voice"),systemImage:"waveform").frame(maxWidth:.infinity,minHeight:48).background(Color.raised,in:RoundedRectangle(cornerRadius:Luz.Radius.cell,style:.continuous))}.disabled(applying).accessibilityIdentifier("voice.original")
                Button{instrument()}label:{Label("Instrument",systemImage:"pianokeys").frame(maxWidth:.infinity,minHeight:48).background(Color.raised,in:RoundedRectangle(cornerRadius:Luz.Radius.cell,style:.continuous))}.disabled(notes.isEmpty || applied || applying).accessibilityIdentifier("voice.instrument")
            }.font(.subheadline)
            if session.harmonyPreview{Button("Stop preview"){session.endHarmonyPreview()}.frame(minHeight:44).accessibilityIdentifier("voice.stop-preview")}
            DisclosureGroup("Rhythm and scale"){
                VStack(spacing:12){StudioSegments(title:"Quantize",selection:$quantize,options:[(.off,"Original"),(.sixteenth,"1/16"),(.eighth,"1/8")]);Toggle("Snap to project scale",isOn:$snapScale);HStack{Text("Timing offset");Slider(value:$offset,in:-0.25...0.25,step:0.005);Text("\(Int(offset*1000)) ms").font(.caption.monospaced()).frame(width:56)};Button("Rebuild notes from source"){resetNotes()};Text("Rebuilding replaces manual note corrections. The original recording stays available.").font(.caption).foregroundStyle(Color.muted)}.padding(.top,12)
            }.disabled(draftLocked)
            if !notes.isEmpty{noteRoll.disabled(draftLocked);eventEditor}
            Picker("Destination",selection:$target){Text("New melody track").tag(nil as UUID?);ForEach(session.project.tracks.filter{$0.role == .melody}){t in Text(t.displayName).tag(Optional(t.id))}}.pickerStyle(.menu).disabled(draftLocked)
            if target != nil{Text("Melody notes in the selected section will be replaced. Other sections stay as written.").font(.caption).foregroundStyle(Color.harmony)}
            if stale && !applied {
                Text("The project changed. Review this melody against the current project before applying.").font(.callout).foregroundStyle(Color.harmony)
                Button("Review against current project"){rebase()}.frame(minHeight:48).disabled(applying || capture.isCapturing || capture.state == .analyzing).accessibilityIdentifier("voice.rebase")
            }
            #if DEBUG
            if synthetic && ProcessInfo.processInfo.arguments.contains("--voice-review-fixture") {
                Button{if !session.audio.playing{session.audio.play()};session.mixerEdit{$0.master=max(-60,$0.master-1)};session.mixerGesture=false}label:{Text(verbatim:"Change fixture mix")}.frame(minHeight:48).accessibilityIdentifier("voice.fixture-edit").disabled(draftLocked)
                Text(verbatim:session.audio.playing ? "PLAYING":"STOPPED").accessibilityIdentifier("voice.fixture-transport")
                Text(verbatim:session.harmonyPreview ? "PREVIEW":"ORIGINAL").accessibilityIdentifier("voice.fixture-preview")
                Text(verbatim:String(note?.pitch ?? -1)).accessibilityIdentifier("voice.fixture-pitch")
                Text(verbatim:result.record.sha256).font(.caption).accessibilityIdentifier("voice.fixture-source")
            }
            #endif
            if applied {
                Text("Notes applied. Save needs attention.").font(.callout).foregroundStyle(Color.harmony)
                Button("Retry save"){Task{await session.save();if session.saveError==nil{dismiss()}else{error=session.saveError}}}.frame(minHeight:48)
            }else{
                Button{apply()}label:{HStack{if applying{ProgressView()};Text("Apply melody")}}.buttonStyle(StudioActionStyle()).disabled(notes.isEmpty || stale || applying || capture.isCapturing || capture.state == .analyzing).accessibilityIdentifier("voice.apply")
                Text("One Undo restores the previous music. Source audio is kept in the project and portable exports.").font(.caption).foregroundStyle(Color.muted)
            }
        }
    }
    var noteRoll:some View {
        let minimum=max(0,(notes.map(\.pitch).min() ?? 60)-2),maximum=min(127,(notes.map(\.pitch).max() ?? 72)+2)
        return GeometryReader{geo in ZStack(alignment:.topLeading){
            Canvas{context,size in
                for row in minimum...maximum{let y=CGFloat(maximum-row)/CGFloat(maximum-minimum+1)*size.height;var line=Path();line.move(to:CGPoint(x:0,y:y));line.addLine(to:CGPoint(x:size.width,y:y));context.stroke(line,with:.color(.raised),lineWidth:1)}
                for beat in 0...sectionLength/ppq{let x=CGFloat(beat*ppq)/CGFloat(sectionLength)*size.width;var line=Path();line.move(to:CGPoint(x:x,y:0));line.addLine(to:CGPoint(x:x,y:size.height));context.stroke(line,with:.color(.raised),lineWidth:1)}
            }
            ForEach(notes){n in Button{selected=n.id}label:{RoundedRectangle(cornerRadius:3,style:.continuous).fill((n.confidence ?? 1)<0.9 ? Color.harmony:Color.mint).opacity(selected==n.id ? 1:0.7).frame(width:max(8,CGFloat(n.duration)/CGFloat(sectionLength)*geo.size.width),height:max(8,geo.size.height/CGFloat(maximum-minimum+1)-3))}.buttonStyle(StudioQuietButtonStyle()).offset(x:CGFloat(n.tick)/CGFloat(sectionLength)*geo.size.width,y:CGFloat(maximum-n.pitch)/CGFloat(maximum-minimum+1)*geo.size.height).accessibilityLabel(noteName(n.pitch))}
        }}.frame(height:150).background(Color.panel,in:RoundedRectangle(cornerRadius:Luz.Radius.cell,style:.continuous))
    }
    var eventEditor:some View {
        VStack(spacing:10){
            ScrollView(.horizontal){HStack{ForEach(notes){n in Button{selected=n.id}label:{Text(noteName(n.pitch)).font(.caption.monospaced()).padding(12).frame(minHeight:44).background(selected==n.id ? Color.record.opacity(0.2):Color.panel,in:RoundedRectangle(cornerRadius:8,style:.continuous))}.buttonStyle(StudioQuietButtonStyle())}}}
            if let note {
                Stepper("Pitch: \(noteName(note.pitch))",value:Binding(get:{note.pitch},set:{v in edit{$0.pitch=v}}),in:0...127).accessibilityLabel("Note pitch").accessibilityValue(Text(verbatim:noteName(note.pitch))).accessibilityIdentifier("voice.pitch")
                HStack{Button("Octave down"){edit{$0.pitch=max(0,$0.pitch-12)}};Spacer();Button("Octave up"){edit{$0.pitch=min(127,$0.pitch+12)}}}.frame(minHeight:44)
                Stepper("Start: \(note.tick) ticks",onIncrement:{move(note.tick+120)},onDecrement:{move(note.tick-120)})
                Stepper("Length: \(note.duration) ticks",onIncrement:{edit{$0.duration=min(sectionLength-$0.tick,$0.duration+120)}},onDecrement:{edit{$0.duration=max(1,$0.duration-120)}})
                Button("Delete note",role:.destructive){notes.removeAll{$0.id==note.id};selected=notes.first?.id}.frame(minHeight:44)
            }
        }.font(.subheadline).disabled(draftLocked)
    }
    func edit(_ action:(inout NoteEvent)->Void){guard !draftLocked else{return};if let i=notes.firstIndex(where:{$0.id==selected}){action(&notes[i])};session.endHarmonyPreview()}
    func move(_ tick:Int){edit{$0.tick=max(0,min(sectionLength-$0.duration,tick))}}
    private func makeContext(minimumLead:Double,playing:Bool?=nil)throws->VoiceReviewContext {
        session.audio.refreshClock()
        let project=session.project
        let plan=try VoiceCapturePlan.make(project:project,selectedSectionID:session.section.id,tick:session.audio.tick,playing:playing ?? session.audio.playing,loop:session.loop,range:session.loopRange,minimumLead:minimumLead)
        guard let section=project.sections.first(where:{$0.id==plan.sectionID})else{throw MusicError.invalidProject}
        return VoiceReviewContext(projectID:project.id,revision:project.revision,sectionID:section.id,sectionName:section.name,sectionStart:section.start,sectionLength:section.length,captureBPM:project.bpm,scaleRoot:project.keyRoot,minor:project.minor,plan:plan)
    }
    func record(){
        guard !draftLocked else{return}
        session.endHarmonyPreview();capture.stopOriginal();session.finishTake();error=nil;pendingContext=nil
        guard session.ensureAudio()else{error=session.audio.error;return}
        guard let lease=session.beginMicrophone(stop:{capture.stop();capture.stopOriginal()})else{return}
        microphoneLease=lease
        Task{
            guard session.ownsMicrophone(lease)else{return}
            let bpm=session.project.bpm
            let previousEngine=session.audio.captureEngine
            await capture.start(audio:session.audio,bpm:bpm,duration:30,countIn:countIn,schedule:{lead in
                do {
                    guard session.ownsMicrophone(lease),session.project.bpm==bpm else{throw AssistantError.stale}
                    let planned=try makeContext(minimumLead:lead)
                    pendingContext=planned
                    return planned.plan.delay
                }catch{self.error=error.localizedDescription;return nil}
            },scheduleDuration:{pendingContext?.plan.duration})
            if session.audio.captureEngine !== previousEngine,session.audio.isPrepared{session.sync()}
            if !capture.isCapturing{session.endMicrophone(lease);if microphoneLease==lease{microphoneLease=nil}}
        }
    }
    func restoreAudio(){if let lease=microphoneLease{microphoneLease=nil;session.endMicrophone(lease)}}
    func resetNotes(){
        guard !draftLocked else{return}
        guard let result=capture.result,let context else{return};session.endHarmonyPreview()
        let source=VoiceAnalyzer.notes(result.analysis,bpm:context.captureBPM,length:context.plan.captureTicks,quantize:quantize,scaleRoot:snapScale ? context.scaleRoot:nil,minor:context.minor,offset:offset)
        do{notes=try context.plan.place(source,sectionLength:context.sectionLength);selected=notes.first?.id}catch{self.error=error.localizedDescription}
    }
    func rebase(){
        guard !draftLocked else{return}
        guard var current=context,current.projectID==session.project.id,let section=session.project.sections.first(where:{$0.id==current.sectionID}),current.plan.offsetTicks+current.plan.captureTicks<=section.length else{error=NSLocalizedString("The recorded section is no longer compatible. Restore it or record a new melody.",comment:"");return}
        do {
            guard let result=capture.result else{return}
            _ = try Arrangement.voiceCandidate(session.project,sectionID:section.id,target:target,notes:notes,source:result.record)
            current.revision=session.project.revision;current.sectionName=section.name;current.sectionStart=section.start;current.sectionLength=section.length;current.scaleRoot=session.project.keyRoot;current.minor=session.project.minor
            context=current;error=nil;session.endHarmonyPreview()
        }catch{self.error=error.localizedDescription}
    }
    func placement()throws->VoicePlacement{guard !stale,let context,let result=capture.result else{throw AssistantError.stale};return try Arrangement.voiceCandidate(session.project,sectionID:context.sectionID,target:target,notes:notes,source:result.record)}
    func original(){guard !applying,!capture.isCapturing,capture.state != .analyzing else{return};session.endHarmonyPreview();session.audio.stop();do{try capture.toggleOriginal()}catch{self.error=error.localizedDescription}}
    func instrument(){guard !draftLocked else{return};capture.stopOriginal();do{let p=try placement();if let section=p.project.sections.first(where:{$0.id==context?.sectionID}){session.previewHarmony(p.project,section:section)}}catch{self.error=error.localizedDescription}}
    func apply(){
        guard !draftLocked else{return}
        guard let result=capture.result,let context else{return};capture.stopOriginal();session.endHarmonyPreview()
        do{let p=try placement();applying=true;Task{do{let saved=try await session.applyVoice(p,data:result.data,record:result.record,projectID:context.projectID,revision:context.revision);applied=true;applying=false;if saved{dismiss()}else{error=session.saveError}}catch{applying=false;self.error=error.localizedDescription}}}catch{self.error=error.localizedDescription}
    }
}
