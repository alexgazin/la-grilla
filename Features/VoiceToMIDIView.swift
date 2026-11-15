import SwiftUI
import MusicDomain
import AVFoundation

struct VoiceToMIDIView:View {
    @Bindable var session:Session
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
    @State private var sourceProjectID:UUID?
    @State private var sourceRevision=0
    @State private var sourceSectionID:UUID?
    var note:NoteEvent?{notes.first{$0.id==selected}}
    var synthetic:Bool{let args=ProcessInfo.processInfo.arguments;return args.contains("--uitesting") && args.contains("voice-draft")}
    var limit:Double{min(30,Double(session.section.length)/Double(ppq)*60/session.project.bpm)}
    var body:some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:18){
                    HStack{Image(systemName:"waveform.badge.mic").font(.system(size:32)).foregroundStyle(Color.record);Spacer();CapsuleLabel(text:"BETA · MONO",color:.record)}
                    Text("Hum it. Shape it.").font(.system(size:27,weight:.medium))
                    Text("Record one melody in a quiet room. Use headphones. Microphone monitoring is off. Review uncertain notes before applying.").font(.subheadline).foregroundStyle(Color.muted)
                    HStack{Text(session.section.name).fontWeight(.medium);Spacer();Text("\(Int(limit)) s · \(Int(session.project.bpm)) BPM").font(.caption.monospaced()).foregroundStyle(Color.muted)}
                    if synthetic{Text("QA FIXTURE · SYNTHETIC SOURCE").font(.caption.monospaced()).foregroundStyle(Color.harmony)}
                    recordingControls
                    if let result=capture.result{draft(result)}
                    if let error=capture.error{Text(error).font(.callout).foregroundStyle(Color.record)}
                    if let error{Text(error).font(.callout).foregroundStyle(Color.record)}
                }.padding(20)
            }.background(Color.ink).navigationTitle("Voice to MIDI").navigationBarTitleDisplayMode(.inline)
                .toolbar{ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}.disabled(applying)}}
        }.tint(.record).interactiveDismissDisabled(applying)
        .onChange(of:capture.result?.record.id){_,id in if id != nil{resetNotes()}}
        .onChange(of:capture.state){_,state in if state == .analyzing || state == .idle || state == .ready{_ = session.ensureAudio()}}
        .onReceive(Timer.publish(every:0.1,on:.main,in:.common).autoconnect()){_ in capture.pollOriginal()}
        .onReceive(NotificationCenter.default.publisher(for:AVAudioSession.interruptionNotification).receive(on:RunLoop.main)){_ in capture.stop();capture.stopOriginal()}
        .onChange(of:phase){_,value in if value == .background{capture.stop();capture.stopOriginal();session.endHarmonyPreview()}}
        .onDisappear{capture.discard();session.endHarmonyPreview();_ = session.ensureAudio()}
        .task{rememberContext();if synthetic{await capture.loadFixture()}}
    }
    var recordingControls:some View {
        VStack(spacing:12){
            if capture.state == .countIn{Text("\(capture.remaining)").font(.system(size:64,weight:.medium,design:.monospaced)).foregroundStyle(Color.record)}
            if capture.state == .recording{HStack{Circle().fill(Color.record).frame(width:9,height:9);Text(String(format:"%.1f s",capture.elapsed)).font(.title2.monospaced());Spacer();ProgressView(value:min(1,capture.level)).tint(.record).frame(width:100)}}
            if capture.state == .analyzing{ProgressView("Analyzing melody…",value:capture.progress).tint(.record)}
            if capture.isCapturing{Button{capture.stop()}label:{Label("Stop recording",systemImage:"stop.fill").frame(maxWidth:.infinity,minHeight:52).background(Color.record,in:RoundedRectangle(cornerRadius:12)).foregroundStyle(Color.ink)}}
            else if capture.state != .analyzing && !applied{
                Toggle("One-bar count-in",isOn:$countIn)
                Button{record()}label:{Label(capture.result==nil ? "Record melody":"Record again",systemImage:"record.circle").frame(maxWidth:.infinity,minHeight:52).background(Color.record,in:RoundedRectangle(cornerRadius:12)).foregroundStyle(Color.ink).fontWeight(.semibold)}.disabled(applying)
            }
        }
    }
    func draft(_ result:VoiceCaptureResult)->some View {
        VStack(alignment:.leading,spacing:16){
            Canvas{context,size in for (i,amplitude) in result.analysis.waveform.enumerated(){let x=CGFloat(i)/CGFloat(max(1,result.analysis.waveform.count))*size.width,h=max(1,CGFloat(amplitude)*size.height);context.fill(Path(CGRect(x:x,y:(size.height-h)/2,width:2,height:h)),with:.color(.record.opacity(0.6)))}}.frame(height:64).background(Color.panel,in:RoundedRectangle(cornerRadius:10)).accessibilityLabel("Original voice waveform")
            HStack{Text("\(notes.count) notes").font(.headline).accessibilityIdentifier("voice.note-count");Spacer();Text("\(notes.filter{($0.confidence ?? 1)<0.9}.count) uncertain").font(.caption).foregroundStyle(Color.harmony)}
            if notes.isEmpty{Text("No stable notes were found. Listen to the original or try a clearer phrase.").font(.callout).foregroundStyle(Color.harmony)}
            HStack(spacing:10){
                Button{original()}label:{Label(capture.originalPlaying ? "Stop original":"Original voice",systemImage:"waveform").frame(maxWidth:.infinity,minHeight:48).background(Color.raised,in:RoundedRectangle(cornerRadius:10))}.accessibilityIdentifier("voice.original")
                Button{instrument()}label:{Label("Instrument",systemImage:"pianokeys").frame(maxWidth:.infinity,minHeight:48).background(Color.raised,in:RoundedRectangle(cornerRadius:10))}.disabled(notes.isEmpty).accessibilityIdentifier("voice.instrument")
            }.font(.subheadline)
            if session.harmonyPreview{Button("Stop preview"){session.endHarmonyPreview()}.frame(minHeight:44)}
            DisclosureGroup("Rhythm and scale"){
                VStack(spacing:12){Picker("Quantize",selection:$quantize){Text("Original").tag(Quantize.off);Text("1/16").tag(Quantize.sixteenth);Text("1/8").tag(Quantize.eighth)}.pickerStyle(.segmented);Toggle("Snap to project scale",isOn:$snapScale);HStack{Text("Timing offset");Slider(value:$offset,in:-0.25...0.25,step:0.005);Text("\(Int(offset*1000)) ms").font(.caption.monospaced()).frame(width:56)};Button("Rebuild notes from source"){resetNotes()};Text("Rebuilding replaces manual note corrections. The original recording stays available.").font(.caption).foregroundStyle(Color.muted)}.padding(.top,12)
            }
            if !notes.isEmpty{noteRoll;eventEditor}
            Picker("Destination",selection:$target){Text("New melody track").tag(nil as UUID?);ForEach(session.project.tracks.filter{$0.role == .melody}){t in Text(t.displayName).tag(Optional(t.id))}}.pickerStyle(.menu).disabled(applied)
            if target != nil{Text("Melody notes in the selected section will be replaced. Other sections stay as written.").font(.caption).foregroundStyle(Color.harmony)}
            if applied {
                Text("Notes applied. Save needs attention.").font(.callout).foregroundStyle(Color.harmony)
                Button("Retry save"){Task{await session.save();if session.saveError==nil{dismiss()}else{error=session.saveError}}}.frame(minHeight:48)
            }else{
                Button{apply()}label:{HStack{if applying{ProgressView()};Text("Apply melody")}.fontWeight(.semibold).frame(maxWidth:.infinity,minHeight:52).foregroundStyle(Color.ink).background(Color.record,in:RoundedRectangle(cornerRadius:12))}.disabled(notes.isEmpty || applying || capture.isCapturing || capture.state == .analyzing).accessibilityIdentifier("voice.apply")
                Text("One Undo restores the previous music. Source audio is kept in the project and portable exports.").font(.caption).foregroundStyle(Color.muted)
            }
        }
    }
    var noteRoll:some View {
        let minimum=max(0,(notes.map(\.pitch).min() ?? 60)-2),maximum=min(127,(notes.map(\.pitch).max() ?? 72)+2)
        return GeometryReader{geo in ZStack(alignment:.topLeading){
            Canvas{context,size in
                for row in minimum...maximum{let y=CGFloat(maximum-row)/CGFloat(maximum-minimum+1)*size.height;var line=Path();line.move(to:CGPoint(x:0,y:y));line.addLine(to:CGPoint(x:size.width,y:y));context.stroke(line,with:.color(.raised),lineWidth:1)}
                for beat in 0...session.section.length/ppq{let x=CGFloat(beat*ppq)/CGFloat(session.section.length)*size.width;var line=Path();line.move(to:CGPoint(x:x,y:0));line.addLine(to:CGPoint(x:x,y:size.height));context.stroke(line,with:.color(.raised),lineWidth:1)}
            }
            ForEach(notes){n in Button{selected=n.id}label:{RoundedRectangle(cornerRadius:3).fill((n.confidence ?? 1)<0.9 ? Color.harmony:Color.mint).opacity(selected==n.id ? 1:0.7).frame(width:max(8,CGFloat(n.duration)/CGFloat(session.section.length)*geo.size.width),height:max(8,geo.size.height/CGFloat(maximum-minimum+1)-3))}.buttonStyle(.plain).offset(x:CGFloat(n.tick)/CGFloat(session.section.length)*geo.size.width,y:CGFloat(maximum-n.pitch)/CGFloat(maximum-minimum+1)*geo.size.height).accessibilityLabel(n.name)}
        }}.frame(height:150).background(Color.panel,in:RoundedRectangle(cornerRadius:10))
    }
    var eventEditor:some View {
        VStack(spacing:10){
            ScrollView(.horizontal){HStack{ForEach(notes){n in Button{selected=n.id}label:{Text(n.name).font(.caption.monospaced()).padding(12).frame(minHeight:44).background(selected==n.id ? Color.record.opacity(0.2):Color.panel,in:RoundedRectangle(cornerRadius:8))}.buttonStyle(.plain)}}}
            if let note {
                Stepper("Pitch: \(note.name)",value:Binding(get:{note.pitch},set:{v in edit{$0.pitch=v}}),in:0...127)
                HStack{Button("Octave down"){edit{$0.pitch=max(0,$0.pitch-12)}};Spacer();Button("Octave up"){edit{$0.pitch=min(127,$0.pitch+12)}}}.frame(minHeight:44)
                Stepper("Start: \(note.tick) ticks",onIncrement:{move(note.tick+120)},onDecrement:{move(note.tick-120)})
                Stepper("Length: \(note.duration) ticks",onIncrement:{edit{$0.duration=min(session.section.length-$0.tick,$0.duration+120)}},onDecrement:{edit{$0.duration=max(1,$0.duration-120)}})
                Button("Delete note",role:.destructive){notes.removeAll{$0.id==note.id};selected=notes.first?.id}.frame(minHeight:44)
            }
        }.font(.subheadline).disabled(applied || applying)
    }
    func edit(_ action:(inout NoteEvent)->Void){if let i=notes.firstIndex(where:{$0.id==selected}){action(&notes[i])};session.endHarmonyPreview()}
    func move(_ tick:Int){edit{$0.tick=max(0,min(session.section.length-$0.duration,tick))}}
    func rememberContext(){sourceProjectID=session.project.id;sourceRevision=session.project.revision;sourceSectionID=session.section.id}
    func record(){session.endHarmonyPreview();capture.stopOriginal();session.finishTake();rememberContext();session.audio.reset();Task{await capture.start(bpm:session.project.bpm,duration:limit,countIn:countIn);if !capture.isCapturing{_ = session.ensureAudio()}}}
    func resetNotes(){guard let result=capture.result else{return};session.endHarmonyPreview();notes=VoiceAnalyzer.notes(result.analysis,bpm:session.project.bpm,length:session.section.length,quantize:quantize,scaleRoot:snapScale ? session.project.keyRoot:nil,minor:session.project.minor,offset:offset);selected=notes.first?.id}
    func placement()throws->VoicePlacement{guard sourceProjectID==session.project.id,sourceRevision==session.project.revision,let sourceSectionID,let result=capture.result else{throw AssistantError.stale};return try Arrangement.voiceCandidate(session.project,sectionID:sourceSectionID,target:target,notes:notes,source:result.record)}
    func original(){session.endHarmonyPreview();session.audio.stop();do{try capture.toggleOriginal()}catch{self.error=error.localizedDescription}}
    func instrument(){capture.stopOriginal();do{let p=try placement();if let section=p.project.sections.first(where:{$0.id==sourceSectionID}){session.previewHarmony(p.project,section:section)}}catch{self.error=error.localizedDescription}}
    func apply(){
        guard let result=capture.result,let sourceProjectID else{return};capture.stopOriginal();session.endHarmonyPreview();session.audio.stop()
        do{let p=try placement();applying=true;Task{do{let saved=try await session.applyVoice(p,data:result.data,record:result.record,projectID:sourceProjectID,revision:sourceRevision);applied=true;applying=false;if saved{dismiss()}else{error=session.saveError}}catch{applying=false;self.error=error.localizedDescription}}}catch{self.error=error.localizedDescription}
    }
}
