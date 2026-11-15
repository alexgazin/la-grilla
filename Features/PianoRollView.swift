import SwiftUI
import MusicDomain

struct PianoRollView: View {
    @Bindable var session:Session
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.dismiss) private var dismiss
    @State private var selected:UUID?
    @State private var clipboard:NoteEvent?
    @State private var snap=240
    @State private var barWidth:CGFloat=240
    @State private var zoomBase:CGFloat=240
    @State private var lowPitch=60
    @State private var listMode=false
    @State private var renaming=false
    @State private var trackName=""
    @State private var original:AudioAssetRecord?
    var track:Track?{session.project.tracks.first{$0.id==session.noteTrackID && $0.role == .melody} ?? session.project.tracks.first{$0.role == .melody}}
    var pattern:Pattern?{guard let t=track,let c=t.clips.first(where:{$0.start<=session.section.start && $0.start+$0.length>session.section.start})else{return nil};return session.project.patterns.first{$0.id==c.patternID}}
    var sourceRecord:AudioAssetRecord?{guard let clip=track?.clips.first(where:{$0.start<=session.section.start && $0.start+$0.length>session.section.start}),let id=clip.sourceAssetID else{return nil};return session.project.audioAssets?.first{$0.id==id}}
    var note:NoteEvent?{pattern?.notes?.first{$0.id==selected}}
    var body:some View {
        NavigationStack {
            VStack(spacing:12){
                controls.padding(.horizontal,16)
                if let pattern {
                    if listMode {eventList(pattern).frame(height:dynamicType.isAccessibilitySize ? 280:nil)} else {roll(pattern)}
                    if let note {NoteInspector(session:session,patternID:pattern.id,note:note,snap:snap)}
                    editBar(pattern).padding(.horizontal,16)
                } else {ContentUnavailableView("Add a melody track",systemImage:"pianokeys",description:Text("Write a melody above your harmony."))}
                HStack{IconButton(symbol:"arrow.uturn.backward",label:"Undo"){session.undo()}.disabled(!session.history.canUndo).accessibilityIdentifier("notes.undo");IconButton(symbol:"arrow.uturn.forward",label:"Redo"){session.redo()}.disabled(!session.history.canRedo).accessibilityIdentifier("notes.redo");Spacer();Text(LocalizedStringKey(session.audio.playing ? "PLAYING":"STOPPED")).font(.caption.monospaced()).foregroundStyle(Color.muted).accessibilityIdentifier("notes.status");IconButton(symbol:session.audio.playing ? "stop.fill":"play.fill",label:session.audio.playing ? "Stop":"Play",color:.mint){session.togglePlay()}.accessibilityIdentifier("notes.play")}.padding(.horizontal,12)
            }.padding(.top,12).padding(.bottom,8).background(Color.ink).modifier(ScrollableForLargeType())
            .navigationTitle("Piano roll").navigationBarTitleDisplayMode(.inline)
            .toolbar{ToolbarItem(placement:.topBarTrailing){Button("Done"){dismiss()}}}
        }.tint(.mint).alert("Rename track",isPresented:$renaming){TextField("Track name",text:$trackName);Button("Save"){if let id=track?.id{let name=String(trackName.trimmingCharacters(in:.whitespacesAndNewlines).prefix(40));if !name.isEmpty{session.edit{p in if let i=p.tracks.firstIndex(where:{$0.id==id}){p.tracks[i].name=name}}}}};Button("Cancel",role:.cancel){}}
        .onAppear{if dynamicType.isAccessibilitySize{listMode=true}}
        .onChange(of:session.noteTrackID){_,_ in selected=nil}
        .sheet(item:$original){record in SourceRecordingView(session:session,record:record)}
        .onChange(of:session.selectedSection){_,_ in selected=nil}
    }
    var controls:some View {
        VStack(spacing:10){
            HStack {
                Menu {
                    ForEach(session.project.tracks.filter{$0.role == .melody}){t in Button(t.displayName){session.noteTrackID=t.id}}
                    Button("Add melody",systemImage:"plus"){session.addMelody()}.disabled(session.project.tracks.count>=8)
                    if let sourceRecord{Button("Original voice",systemImage:"waveform"){original=sourceRecord}}
                    if let track {
                        Button("Rename track",systemImage:"pencil"){trackName=track.displayName;renaming=true}
                        Button("Duplicate track",systemImage:"plus.square.on.square"){session.duplicateMelody(track.id)}.disabled(session.project.tracks.count>=8)
                        Button("Delete track",systemImage:"trash",role:.destructive){session.deleteMelody(track.id)}
                    }
                }label:{Label(track?.displayName ?? "Add melody",systemImage:"pianokeys").lineLimit(1).frame(minHeight:44)}.accessibilityIdentifier("notes.tracks")
                Spacer(minLength:6)
                Picker("Section",selection:Binding(get:{session.section.id},set:{id in if let s=session.project.sections.first(where:{$0.id==id}){session.select(s)}})){ForEach(session.project.sections){s in Text(s.name).tag(s.id)}}.pickerStyle(.menu)
            }
            HStack(spacing:12){Picker("Snap",selection:$snap){Text("1/16").tag(240);Text("1/8").tag(480);Text("1/4").tag(960)}.pickerStyle(.segmented)
                Button{listMode.toggle()}label:{Image(systemName:listMode ? "pianokeys":"list.bullet").frame(width:44,height:44)}.accessibilityLabel(listMode ? "Show piano roll":"Show note list")}
        }
    }
    func roll(_ p:Pattern)->some View {
        VStack(spacing:0){
            HStack{Button{lowPitch=max(0,lowPitch-12)}label:{Label("Octave",systemImage:"minus").frame(minHeight:44)}.disabled(lowPitch==0);Spacer();Text("\(NoteEvent(tick:0,pitch:lowPitch).name) – \(NoteEvent(tick:0,pitch:lowPitch+23).name)").font(.caption.monospaced()).foregroundStyle(Color.muted);Spacer();Button{lowPitch=min(104,lowPitch+12)}label:{Image(systemName:"plus").frame(width:44,height:44)}.disabled(lowPitch==104)}.padding(.horizontal,16)
            ScrollView([.horizontal,.vertical]) {
                HStack(spacing:0){
                    VStack(spacing:0){Color.clear.frame(height:24);ForEach((lowPitch...lowPitch+23).reversed(),id:\.self){pitch in Button{preview(pitch)}label:{Text(NoteEvent(tick:0,pitch:pitch).name).font(.system(size:10,design:.monospaced)).foregroundStyle(isBlack(pitch) ? Color.white:Color.black).frame(width:48,height:24).background(isBlack(pitch) ? Color(white:0.14):Color.white)}.buttonStyle(.plain).accessibilityLabel("Preview \(NoteEvent(tick:0,pitch:pitch).name)")}}
                    VStack(spacing:0){
                        HStack(spacing:0){ForEach(0..<p.length/barTicks,id:\.self){bar in Text("\(bar+1)").font(.caption2.monospaced()).frame(width:barWidth,alignment:.leading)}}.foregroundStyle(Color.muted).frame(height:24)
                        RollCanvas(pattern:p,selected:selected,lowPitch:lowPitch,barWidth:barWidth,snap:snap,tick:session.audio.tick-Double(session.section.start),select:{id in selected=id},insert:{tick,pitch in add(p,tick:tick,pitch:pitch)},move:{id,tick,pitch in change(p.id){NoteEditing.move(id,in:&$0,tick:tick,pitch:pitch,step:snap)}},resize:{id,duration in change(p.id){NoteEditing.resize(id,in:&$0,duration:duration,step:snap)}})
                            .frame(width:CGFloat(p.length)/CGFloat(barTicks)*barWidth,height:576)
                    }
                }
            }.background(Color.panel).simultaneousGesture(MagnifyGesture().onChanged{v in barWidth=min(640,max(112,zoomBase*v.magnification))}.onEnded{_ in zoomBase=barWidth})
            Text("Tap to add · hold and drag to move · drag selected note end to resize").font(.caption2).foregroundStyle(Color.muted).padding(.horizontal,16).padding(.top,7)
        }.frame(maxHeight:.infinity)
    }
    func eventList(_ p:Pattern)->some View {
        List {
            ForEach((p.notes ?? []).sorted{$0.tick<$1.tick}){n in Button{selected=n.id;preview(n.pitch)}label:{HStack{Text(n.name).foregroundStyle(Color.mint);Spacer();Text("\(n.tick/ppq+1):\(n.tick%ppq) · \(n.duration) ticks · v\(n.velocity)").font(.caption.monospaced());if selected==n.id{Image(systemName:"checkmark")}}}.listRowBackground(Color.panel)}
        }.scrollContentBackground(.hidden).accessibilityIdentifier("notes.list")
    }
    func editBar(_ p:Pattern)->some View {
        HStack(spacing:4){
            IconButton(symbol:"plus",label:"Add note",color:.mint){add(p,tick:(note.map{$0.tick+$0.duration} ?? 0),pitch:note?.pitch ?? 72)}.accessibilityIdentifier("notes.add")
            IconButton(symbol:"doc.on.doc",label:"Copy note"){clipboard=note}.disabled(note==nil)
            IconButton(symbol:"doc.on.clipboard",label:"Paste note"){if var n=clipboard{n.tick=note.map{$0.tick+$0.duration} ?? n.tick;change(p.id){try NoteEditing.insert(n,into:&$0,step:snap)}}}.disabled(clipboard==nil)
            IconButton(symbol:"plus.square.on.square",label:"Duplicate note"){if let id=selected{change(p.id){try NoteEditing.duplicate(id,in:&$0,step:snap)}}}.disabled(note==nil)
            IconButton(symbol:"trash",label:"Delete note",color:.record){if let id=selected{change(p.id){$0.notes?.removeAll{$0.id==id}};selected=nil}}.disabled(note==nil)
            Spacer(minLength:0);Text("\(p.notes?.count ?? 0)").font(.caption.monospaced()).foregroundStyle(Color.muted).accessibilityIdentifier("notes.count")
        }
    }
    func change(_ id:UUID,_ action:(inout Pattern)throws->Void){session.edit{p in if let i=p.patterns.firstIndex(where:{$0.id==id}){try action(&p.patterns[i])}}}
    func add(_ p:Pattern,tick:Int,pitch:Int){change(p.id){try NoteEditing.insert(NoteEvent(tick:tick,duration:snap*2,pitch:pitch),into:&$0,step:snap)};selected=session.project.patterns.first{$0.id==p.id}?.notes?.last?.id;preview(pitch)}
    func preview(_ pitch:Int){if session.ensureAudio(),let id=track?.id,let i=session.project.tracks.firstIndex(where:{$0.id==id}){session.audio.previewNote(pitch,track:i)}}
    func isBlack(_ pitch:Int)->Bool{[1,3,6,8,10].contains(pitch%12)}
}

private struct RollCanvas:View {
    let pattern:Pattern;let selected:UUID?;let lowPitch:Int;let barWidth:CGFloat;let snap:Int;let tick:Double
    let select:(UUID?)->Void;let insert:(Int,Int)->Void;let move:(UUID,Int,Int)->Void;let resize:(UUID,Int)->Void
    func rect(_ n:NoteEvent)->CGRect{CGRect(x:CGFloat(n.tick)/CGFloat(barTicks)*barWidth,y:CGFloat(lowPitch+23-n.pitch)*24+2,width:max(4,CGFloat(n.duration)/CGFloat(barTicks)*barWidth-2),height:20)}
    func hit(_ point:CGPoint)->NoteEvent?{(pattern.notes ?? []).filter{(lowPitch...lowPitch+23).contains($0.pitch)}.sorted{($0.id==selected ? 0:1)<($1.id==selected ? 0:1)}.first{rect($0).insetBy(dx:-8,dy:-2).contains(point)}}
    var body:some View {
        Canvas{context,size in
            for row in 0..<24 {let pitch=lowPitch+23-row;context.fill(Path(CGRect(x:0,y:CGFloat(row)*24,width:size.width,height:24)),with:.color([1,3,6,8,10].contains(pitch%12) ? .ink:.panel));var line=Path();line.move(to:CGPoint(x:0,y:CGFloat(row)*24));line.addLine(to:CGPoint(x:size.width,y:CGFloat(row)*24));context.stroke(line,with:.color(.raised),lineWidth:0.5)}
            for step in 0...pattern.length/snap{let x=CGFloat(step*snap)/CGFloat(barTicks)*barWidth;var line=Path();line.move(to:CGPoint(x:x,y:0));line.addLine(to:CGPoint(x:x,y:size.height));context.stroke(line,with:.color(step*snap%barTicks==0 ? .muted.opacity(0.5):.raised),lineWidth:1)}
            for n in pattern.notes ?? [] where (lowPitch...lowPitch+23).contains(n.pitch) {let r=rect(n);context.fill(Path(roundedRect:r,cornerRadius:4),with:.color(.mint.opacity(n.id==selected ? 1:0.35+Double(n.velocity)/254)));if n.id==selected {context.fill(Path(CGRect(x:r.maxX-3,y:r.minY+3,width:2,height:14)),with:.color(.ink))}}
            if tick>=0 && tick<Double(pattern.length){let x=CGFloat(tick)/CGFloat(barTicks)*barWidth;var line=Path();line.move(to:CGPoint(x:x,y:0));line.addLine(to:CGPoint(x:x,y:size.height));context.stroke(line,with:.color(.record),lineWidth:1.5)}
        }.contentShape(Rectangle()).accessibilityLabel("Piano roll. Use the note list to edit with VoiceOver.")
        .gesture(SpatialTapGesture().onEnded{v in if let n=hit(v.location){select(n.id)}else{insert(Int(v.location.x/barWidth*CGFloat(barTicks)),min(127,max(0,lowPitch+23-Int(v.location.y/24))))}})
        .simultaneousGesture(LongPressGesture(minimumDuration:0.35).sequenced(before:DragGesture()).onEnded{v in
            if case .second(true,let drag?)=v,let n=hit(drag.startLocation){
                select(n.id);let delta=Int(drag.translation.width/barWidth*CGFloat(barTicks))
                if n.id==selected && abs(drag.startLocation.x-rect(n).maxX)<16 {resize(n.id,n.duration+delta)}
                else{move(n.id,n.tick+delta,n.pitch-Int((drag.translation.height/24).rounded()))}
            }
        })
    }
}

private struct NoteInspector:View {
    @Environment(\.dynamicTypeSize) private var dynamicType
    private var layout:AnyLayout{dynamicType.isAccessibilitySize ? AnyLayout(VStackLayout(spacing:8)):AnyLayout(HStackLayout(spacing:16))}
    @Bindable var session:Session;let patternID:UUID;let note:NoteEvent;let snap:Int
    func edit(_ action:(inout NoteEvent)->Void){session.edit{p in if let i=p.patterns.firstIndex(where:{$0.id==patternID}),let j=p.patterns[i].notes?.firstIndex(where:{$0.id==note.id}){action(&p.patterns[i].notes![j])}}}
    var body:some View {
        VStack(spacing:6){
            layout{Stepper(note.name,value:Binding(get:{note.pitch},set:{v in edit{$0.pitch=v}}),in:0...127).accessibilityLabel("Note pitch");Text("\(note.duration) ticks").monospacedDigit()}
            layout{Stepper("Start",onIncrement:{move(note.tick+snap)},onDecrement:{move(note.tick-snap)}).accessibilityLabel("Note start");Stepper("Length",onIncrement:{resize(note.duration+snap)},onDecrement:{resize(note.duration-snap)}).accessibilityLabel("Note duration")}
            HStack{Text("Velocity").font(.caption);Slider(value:Binding(get:{Double(note.velocity)},set:{v in session.mixerEdit{p in if let i=p.patterns.firstIndex(where:{$0.id==patternID}),let j=p.patterns[i].notes?.firstIndex(where:{$0.id==note.id}){p.patterns[i].notes?[j].velocity=Int(v)}}}),in:1...127,step:1,onEditingChanged:{_ in session.mixerGesture=false}).accessibilityLabel("Note velocity");Text("\(note.velocity)").font(.caption.monospaced()).frame(width:28)}
        }.padding(.horizontal,16).font(.caption)
    }
    func move(_ tick:Int){session.edit{p in if let i=p.patterns.firstIndex(where:{$0.id==patternID}){NoteEditing.move(note.id,in:&p.patterns[i],tick:tick,pitch:note.pitch,step:snap)}}}
    func resize(_ duration:Int){session.edit{p in if let i=p.patterns.firstIndex(where:{$0.id==patternID}){NoteEditing.resize(note.id,in:&p.patterns[i],duration:duration,step:snap)}}}
}
