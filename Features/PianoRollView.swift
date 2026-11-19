import SwiftUI
import UIKit
import MusicDomain

struct PianoRollView: View {
    @Bindable var session:Session
    @AppStorage("studio.pitchSpelling") private var spellingValue=PitchSpelling.automatic.rawValue
    private var spelling:PitchSpelling{PitchSpelling(rawValue:spellingValue) ?? .automatic}
    private func noteName(_ pitch:Int)->String{MusicalNotation.noteName(pitch,keyRoot:session.project.keyRoot,minor:session.project.minor,spelling:spelling)}
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.dismiss) private var dismiss
    @State private var selected:UUID?
    @State private var clipboard:NoteEvent?
    @State private var snap=240
    @State private var barWidth:CGFloat=240
    @State private var rollViewport = CGRect.zero
    @State private var renderedWidth: CGFloat = 0
    private static let measureZoom = ProcessInfo.processInfo.arguments.contains("--measure-piano-zoom")
    @State private var lowPitch=60
    @State private var listMode=false
    @State private var renaming=false
    @State private var trackName=""
    @State private var original:AudioAssetRecord?
    @State private var showTrackActions=false
    @State private var pendingTrackRename=false
    @State private var pendingOriginal:AudioAssetRecord?
    @State private var noteDragging=false
    var track:Track?{session.project.tracks.first{$0.id==session.noteTrackID && $0.role == .melody} ?? session.project.tracks.first{$0.role == .melody}}
    var clip:Clip?{guard let track else{return nil};if let id=session.noteClipID,let selected=track.clips.first(where:{$0.id==id}){return selected};return track.clips.first{$0.start<=session.section.start && $0.start+$0.length>session.section.start}}
    var pattern:Pattern?{guard let clip else{return nil};return session.project.patterns.first{$0.id==clip.patternID}}
    var sourceRecord:AudioAssetRecord?{guard let id=clip?.sourceAssetID else{return nil};return session.project.audioAssets?.first{$0.id==id}}
    var sourcePlayhead:Double{guard let clip,let pattern else{return -1};let position=session.audio.tick-Double(clip.start);guard position>=0,position<Double(clip.length)else{return -1};return (position+Double(clip.offset)).truncatingRemainder(dividingBy:Double(pattern.length))}
    var note:NoteEvent?{pattern?.notes?.first{$0.id==selected}}
    var body:some View {
        NavigationStack {
            VStack(spacing:12){
                controls.padding(.horizontal,16)
                if let clip,let pattern,clip.offset != 0 || clip.length != pattern.length{Text("Editing the source pattern updates every loop of this clip.").font(.caption).foregroundStyle(Color.muted).padding(.horizontal,16)}
                if let pattern {
                    if listMode {eventList(pattern).frame(height:dynamicType.isAccessibilitySize ? 280:nil)} else {roll(pattern)}
                    if let note {NoteInspector(session:session,patternID:pattern.id,note:note,snap:snap,spelling:spelling)}
                    editBar(pattern).padding(.horizontal,16)
                } else {ContentUnavailableView("Add a melody track",systemImage:"pianokeys",description:Text("Write a melody above your harmony."))}
                HStack(spacing:4){IconButton(symbol:"arrow.uturn.backward",label:"Undo"){session.undo()}.disabled(!session.history.canUndo).accessibilityIdentifier("notes.undo");IconButton(symbol:"arrow.uturn.forward",label:"Redo"){session.redo()}.disabled(!session.history.canRedo).accessibilityIdentifier("notes.redo");Spacer();Text(LocalizedStringKey(session.audio.playing ? "PLAYING":"STOPPED")).font(.caption.monospaced()).foregroundStyle(Color.muted).accessibilityIdentifier("notes.status");IconButton(symbol:session.audio.playing ? "stop.fill":"play.fill",label:session.audio.playing ? "Stop":"Play",color:.mint){session.togglePlay()}.accessibilityIdentifier("notes.play")}.padding(.horizontal,12).overlay(alignment:.top){Rectangle().fill(Color.outline.opacity(0.5)).frame(height:0.5)}
            }.padding(.top,12).padding(.bottom,8).background(Color.ink).modifier(ScrollableForLargeType())
            .navigationTitle("Piano roll").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    InstrumentKeyboardButton(session: session, trackID: track?.id, clipID: clip?.id)
                }
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }.tint(.mint).alert("Rename track",isPresented:$renaming){TextField("Track name",text:$trackName);Button("Save"){if let id=track?.id{let name=String(trackName.trimmingCharacters(in:.whitespacesAndNewlines).prefix(40));if !name.isEmpty{session.edit{p in if let i=p.tracks.firstIndex(where:{$0.id==id}){p.tracks[i].name=name}}}}};Button("Cancel",role:.cancel){}}
        .onChange(of:dynamicType,initial:true){_,size in if size.isAccessibilitySize || UIAccessibility.isVoiceOverRunning{listMode=true}}
        .onChange(of:session.noteTrackID){_,_ in selected=nil}
        .onChange(of:session.noteClipID){_,_ in selected=nil}
        .sheet(item:$original){record in SourceRecordingView(session:session,record:record)}
        .sheet(isPresented:$showTrackActions,onDismiss:finishTrackAction){trackActions}
        .onChange(of:session.selectedSection){_,_ in selected=nil}
    }
    var controls:some View {
        VStack(spacing:10){
            if dynamicType.isAccessibilitySize {
                VStack(alignment:.leading,spacing:10){
                    trackControl.frame(maxWidth:.infinity,alignment:.leading)
                    sectionControl.frame(maxWidth:.infinity,alignment:.leading)
                }
            }else{
                HStack{trackControl;Spacer(minLength:6);sectionControl}
            }
            HStack(spacing:12){StudioSegments(title:"Snap",selection:$snap,options:[(240,"1/16"),(480,"1/8"),(960,"1/4")])
                Button{listMode.toggle()}label:{Image(systemName:listMode ? "pianokeys":"list.bullet").frame(width:44,height:44)}.accessibilityLabel(LocalizedStringKey(listMode ? "Show piano roll":"Show note list"))}
        }
    }
    private var trackControl:some View {
        Button{showTrackActions=true}label:{
            HStack(spacing:8){
                Image(systemName:"pianokeys").font(.system(size:17,weight:.medium)).foregroundStyle(Color.mint)
                Text(track?.displayName ?? NSLocalizedString("Add melody",comment:"Track menu"))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Color.studioText)
                    .lineLimit(dynamicType.isAccessibilitySize ? nil:1).fixedSize(horizontal:false,vertical:dynamicType.isAccessibilitySize)
                Image(systemName:"chevron.down").font(.system(size:11,weight:.semibold)).foregroundStyle(Color.muted)
            }.frame(minHeight:44)
        }.buttonStyle(StudioQuietButtonStyle()).accessibilityIdentifier("notes.tracks")
    }
    private var sectionControl:some View {
        Picker("Section",selection:Binding(get:{session.section.id},set:{id in if let s=session.project.sections.first(where:{$0.id==id}){session.noteClipID=nil;session.select(s)}})){ForEach(session.project.sections){s in Text(s.name).tag(s.id)}}.pickerStyle(.menu).accessibilityIdentifier("notes.section")
    }
    private var trackActions:some View {NavigationStack{List{
        ForEach(session.project.tracks.filter{$0.role == .melody}){track in
            Button{session.noteTrackID=track.id;session.noteClipID=nil;showTrackActions=false}label:{HStack{Text(track.displayName);Spacer();if track.id==session.noteTrackID{Image(systemName:"checkmark")}}}.accessibilityIdentifier("notes.track.select.\(track.id)")
        }
        Button("Add melody",systemImage:"plus"){session.addMelody();showTrackActions=false}.disabled(session.project.tracks.count>=8).accessibilityIdentifier("notes.track.add")
        if let sourceRecord{Button("Original voice",systemImage:"waveform"){pendingOriginal=sourceRecord;showTrackActions=false}.accessibilityIdentifier("notes.track.source")}
        if let track {
            if dynamicType.isAccessibilitySize {TrackSoundButton(session:session,trackID:track.id)}
            Button("Rename track",systemImage:"pencil"){pendingTrackRename=true;showTrackActions=false}.accessibilityIdentifier("notes.track.rename")
            Button("Duplicate track",systemImage:"plus.square.on.square"){session.duplicateMelody(track.id);showTrackActions=false}.disabled(session.project.tracks.count>=8).accessibilityIdentifier("notes.track.duplicate")
            Button("Delete track",systemImage:"trash",role:.destructive){session.deleteMelody(track.id);showTrackActions=false}.accessibilityIdentifier("notes.track.delete")
        }
    }.environment(\.defaultMinListRowHeight,52).navigationTitle("Track").navigationBarTitleDisplayMode(.inline)
        .toolbar{ToolbarItem(placement:.cancellationAction){Button("Cancel"){showTrackActions=false}}}}
        .presentationDetents([.large]).tint(.mint)
    }
    private func finishTrackAction(){
        if pendingTrackRename,let track{trackName=track.displayName;renaming=true}
        if let pendingOriginal{original=pendingOriginal}
        pendingTrackRename=false;pendingOriginal=nil
    }
    func roll(_ p:Pattern)->some View {
        VStack(spacing:0){
            HStack{Button{lowPitch=max(0,lowPitch-12)}label:{Label("Octave",systemImage:"minus").frame(minHeight:44)}.disabled(lowPitch==0);Spacer();Text("\(noteName(lowPitch)) – \(noteName(lowPitch+23))").font(.caption.monospaced()).foregroundStyle(Color.muted);Spacer();Button{lowPitch=min(104,lowPitch+12)}label:{Image(systemName:"plus").frame(width:44,height:44)}.disabled(lowPitch==104)}.padding(.horizontal,16)
            PianoRollViewport(bars: CGFloat(p.length)/CGFloat(barTicks), barWidth: $barWidth,
                              editing: noteDragging, measure: Self.measureZoom ? { width, visible in
                renderedWidth = width; rollViewport = visible
            } : nil) {
                HStack(spacing:0){
                    VStack(spacing:0){Color.raised.frame(height:24);ForEach((lowPitch...lowPitch+23).reversed(),id:\.self){pitch in Button{preview(pitch)}label:{
                        Text(noteName(pitch)).font(.system(size:11,weight:pitch%12==0 ? .bold:.medium,design:.monospaced))
                            .foregroundStyle(isBlack(pitch) ? Color.keyboardIvory:Color.keyboardGraphite)
                            .frame(width:48,height:24).background(isBlack(pitch) ? Color.keyboardGraphite:Color.keyboardIvory)
                            .overlay(alignment:.bottom){Rectangle().fill(Color.ink.opacity(0.2)).frame(height:0.5)}
                            .overlay(alignment:.trailing){Rectangle().fill(Color.outline).frame(width:0.5)}
                    }.buttonStyle(StudioQuietButtonStyle()).accessibilityLabel("Preview \(noteName(pitch))")}}
                    VStack(spacing:0){
                        HStack(spacing:0){ForEach(0..<p.length/barTicks,id:\.self){bar in
                            HStack(spacing:5){Rectangle().fill(Color.muted).frame(width:1,height:8);Text(String(format:"%02d",bar+1)).font(.system(.caption2,design:.monospaced,weight:.semibold));Spacer(minLength:0)}
                                .frame(width:barWidth,alignment:.leading)
                        }}.foregroundStyle(Color.muted).frame(height:24).background(Color.raised)
                            .overlay(alignment:.bottom){Rectangle().fill(Color.outline).frame(height:0.5)}
                        RollCanvas(pattern:p,projectID:session.project.id,revision:session.project.revision,clipID:clip?.id,sectionID:session.section.id,selected:selected,lowPitch:lowPitch,barWidth:barWidth,snap:snap,tick:sourcePlayhead,editingChanged:{noteDragging=$0},select:{id in selected=id},insert:{tick,pitch in add(p,tick:tick,pitch:pitch)},move:{id,tick,pitch in change(p.id){NoteEditing.move(id,in:&$0,tick:tick,pitch:pitch,step:snap)}},resize:{id,duration in change(p.id){NoteEditing.resize(id,in:&$0,duration:duration,step:snap)}})
                            .frame(width:CGFloat(p.length)/CGFloat(barTicks)*barWidth,height:576)
                    }
                }
            }
            .background(Color.panel)
            Text("Tap to add · hold and drag to move · drag selected note end to resize").font(.caption2).foregroundStyle(Color.muted).padding(.horizontal,16).padding(.top,7)
        }.frame(maxHeight:.infinity)
    }
    func eventList(_ p:Pattern)->some View {
        List {
            ForEach((p.notes ?? []).sorted{$0.tick<$1.tick}){n in
                Button{selected=n.id;preview(n.pitch)}label:{
                    if dynamicType.isAccessibilitySize {
                        VStack(alignment:.leading,spacing:8){
                            HStack(alignment:.firstTextBaseline){Text(noteName(n.pitch)).foregroundStyle(Color.mint);Spacer(minLength:8);if selected==n.id{Image(systemName:"checkmark")}}
                            noteDetails(n).fixedSize(horizontal:false,vertical:true)
                        }.frame(maxWidth:.infinity,alignment:.leading)
                    }else{
                        HStack{Text(noteName(n.pitch)).foregroundStyle(Color.mint);Spacer();noteDetails(n);if selected==n.id{Image(systemName:"checkmark")}}
                    }
                }.accessibilityIdentifier("notes.row.\(n.id)").listRowBackground(Color.panel)
            }
        }.scrollContentBackground(.hidden).accessibilityIdentifier("notes.list")
    }
    private func noteDetails(_ note:NoteEvent)->some View {
        Text("\(note.tick/ppq+1):\(note.tick%ppq) · \(note.duration) ticks · v\(note.velocity)").font(.caption.monospaced())
    }
    func editBar(_ p:Pattern)->some View {
        HStack(spacing:2){
            IconButton(symbol:"plus",label:"Add note",color:.mint){add(p,tick:(note.map{$0.tick+$0.duration} ?? 0),pitch:note?.pitch ?? 72)}.accessibilityIdentifier("notes.add")
            IconButton(symbol:"doc.on.doc",label:"Copy note"){clipboard=note}.disabled(note==nil)
            IconButton(symbol:"doc.on.clipboard",label:"Paste note"){if var n=clipboard{n.tick=note.map{$0.tick+$0.duration} ?? n.tick;change(p.id){try NoteEditing.insert(n,into:&$0,step:snap)}}}.disabled(clipboard==nil)
            IconButton(symbol:"plus.square.on.square",label:"Duplicate note"){if let id=selected{change(p.id){try NoteEditing.duplicate(id,in:&$0,step:snap)}}}.disabled(note==nil)
            IconButton(symbol:"trash",label:"Delete note",color:.record){if let id=selected{change(p.id){$0.notes?.removeAll{$0.id==id}};selected=nil}}.disabled(note==nil)
            Spacer(minLength:0)
            if !dynamicType.isAccessibilitySize,let track {TrackSoundButton(session:session,trackID:track.id,compact:true).frame(width:80)}
            let count = Text("\(p.notes?.count ?? 0)").font(.caption.monospaced())
                .foregroundStyle(Color.muted).accessibilityIdentifier("notes.count")
            if Self.measureZoom {
                count.accessibilityValue(Text(verbatim: "\(renderedWidth),\(rollViewport.minY)"))
            } else { count }
        }
    }
    func change(_ id:UUID,_ action:(inout Pattern)throws->Void){session.edit{p in if let i=p.patterns.firstIndex(where:{$0.id==id}){try action(&p.patterns[i])}}}
    func add(_ p:Pattern,tick:Int,pitch:Int){change(p.id){try NoteEditing.insert(NoteEvent(tick:tick,duration:snap*2,pitch:pitch),into:&$0,step:snap)};selected=session.project.patterns.first{$0.id==p.id}?.notes?.last?.id;preview(pitch)}
    func preview(_ pitch:Int){if session.ensureAudio(),let id=track?.id,let i=session.project.tracks.firstIndex(where:{$0.id==id}){session.audio.previewNote(pitch,track:i)}}
    func isBlack(_ pitch:Int)->Bool{[1,3,6,8,10].contains(pitch%12)}
}

/// Pan belongs to the scroll view, while a pinch changes only musical time. The
/// UIKit viewport owns its offset, so changing the hosted SwiftUI ruler width
/// cannot reset the pitch rows or feed a second scroll-position transaction back.
private struct PianoRollViewport<Content: View>: UIViewControllerRepresentable {
    let bars: CGFloat
    @Binding var barWidth: CGFloat
    let editing: Bool
    let measure: ((CGFloat, CGRect) -> Void)?
    @ViewBuilder let content: () -> Content

    func makeUIViewController(context: Context) -> Controller {
        Controller(content: content())
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.update(content: content(), bars: bars, width: barWidth, editing: editing,
                          setWidth: { barWidth = $0 }, measure: measure)
    }

    final class Controller: UIViewController, UIScrollViewDelegate {
        private let scroll = UIScrollView()
        private let host: UIHostingController<Content>
        private var width: CGFloat = 240
        private var bars: CGFloat = 1
        private var setWidth: ((CGFloat) -> Void)?
        private var measure: ((CGFloat, CGRect) -> Void)?
        private var lastMeasurement = CGRect.null
        private var lastContentWidth: CGFloat = 0
        private var anchor: (width: CGFloat, viewX: CGFloat, contentX: CGFloat, y: CGFloat)?

        init(content: Content) {
            host = UIHostingController(rootView: content)
            super.init(nibName: nil, bundle: nil)
        }
        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func loadView() {
            view = scroll
            scroll.accessibilityIdentifier = "notes.viewport"
            scroll.contentInsetAdjustmentBehavior = .never
            scroll.panGestureRecognizer.maximumNumberOfTouches = 1
            scroll.delegate = self
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(magnify(_:)))
            scroll.addGestureRecognizer(pinch)
            addChild(host)
            host.view.backgroundColor = .clear
            scroll.addSubview(host.view)
            host.didMove(toParent: self)
        }

        func update(content: Content, bars: CGFloat, width: CGFloat, editing: Bool,
                    setWidth: @escaping (CGFloat) -> Void, measure: ((CGFloat, CGRect) -> Void)?) {
            loadViewIfNeeded()
            self.measure = measure
            self.setWidth = setWidth
            self.bars = bars
            self.width = width
            host.rootView = content
            scroll.panGestureRecognizer.isEnabled = !editing
            layoutCanvas()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            layoutCanvas()
        }
        private func layoutCanvas() {
            let size = CGSize(width: 48+bars*width, height: 24+24*24)
            if host.view.frame.size != size { host.view.frame = CGRect(origin: .zero, size: size) }
            if scroll.contentSize != size { scroll.contentSize = size }
            reportGeometry()
        }
        func scrollViewDidScroll(_ scrollView: UIScrollView) { reportGeometry() }
        private func reportGeometry() {
            guard let measure else { return }
            let visible = scroll.bounds, contentWidth = scroll.contentSize.width
            guard visible != lastMeasurement || contentWidth != lastContentWidth else { return }
            lastMeasurement = visible; lastContentWidth = contentWidth
            // Measurements are exposed to the on-device geometry regression only.
            DispatchQueue.main.async { measure(contentWidth, visible) }
        }
        @objc private func magnify(_ gesture: UIPinchGestureRecognizer) {
            if gesture.state == .began {
                let contentX = gesture.location(in: scroll).x
                anchor = (width, contentX-scroll.contentOffset.x, contentX, scroll.contentOffset.y)
                if scroll.isDecelerating { scroll.setContentOffset(scroll.contentOffset, animated: false) }
            }
            if gesture.state == .began || gesture.state == .changed || gesture.state == .ended, let anchor {
                let next = min(640, max(112, anchor.width*gesture.scale))
                width = next
                layoutCanvas()
                let x = anchor.contentX <= 48 ? anchor.contentX : 48+(anchor.contentX-48)*next/anchor.width
                let maxX = max(0, scroll.contentSize.width-scroll.bounds.width)
                let maxY = max(0, scroll.contentSize.height-scroll.bounds.height)
                scroll.setContentOffset(CGPoint(x: min(maxX, max(0, x-anchor.viewX)), y: min(maxY,max(0,anchor.y))), animated: false)
                setWidth?(next)
            }
            if [.ended, .cancelled, .failed].contains(gesture.state) { anchor = nil }
        }
    }
}

/// Only a hold beginning on a note may claim the move recognizer. In
/// particular, the full-size drawing has no drag recognizer on empty canvas.
private struct PianoCanvasInput: UIViewRepresentable {
    let hitNote: (CGPoint) -> NoteEvent?
    let tap: (CGPoint) -> Void
    let drag: (NoteEvent, CGSize) -> Void
    let end: (CGSize) -> Void
    let cancel: () -> Void

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var input: PianoCanvasInput
        var note: NoteEvent?
        var start: CGPoint = .zero
        init(_ input: PianoCanvasInput) { self.input = input }
        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard recognizer is UILongPressGestureRecognizer else { return true }
            start = touch.location(in: recognizer.view)
            note = input.hitNote(start)
            return note != nil
        }
        @objc func tapped(_ recognizer: UITapGestureRecognizer) { input.tap(recognizer.location(in: recognizer.view)) }
        @objc func held(_ recognizer: UILongPressGestureRecognizer) {
            let location = recognizer.location(in: recognizer.view)
            let delta = CGSize(width: location.x-start.x, height: location.y-start.y)
            switch recognizer.state {
            case .began, .changed:
                if let note { input.drag(note, delta) }
            case .ended: input.end(delta); note = nil
            case .cancelled, .failed: input.cancel(); note = nil
            default: break
            }
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let delegate = context.coordinator
        let hold = UILongPressGestureRecognizer(target: delegate, action: #selector(Coordinator.held(_:)))
        hold.minimumPressDuration = 0.35; hold.delegate = delegate
        let tap = UITapGestureRecognizer(target: delegate, action: #selector(Coordinator.tapped(_:)))
        tap.require(toFail: hold)
        view.addGestureRecognizer(hold)
        view.addGestureRecognizer(tap)
        return view
    }
    func updateUIView(_ view: UIView, context: Context) { context.coordinator.input = self }
}

private struct RollCanvas:View {
    let pattern:Pattern;let projectID:UUID;let revision:Int;let clipID:UUID?;let sectionID:UUID
    let selected:UUID?;let lowPitch:Int;let barWidth:CGFloat;let snap:Int;let tick:Double
    let editingChanged:(Bool)->Void
    let select:(UUID?)->Void;let insert:(Int,Int)->Void;let move:(UUID,Int,Int)->Void;let resize:(UUID,Int)->Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var interaction:Interaction?
    @State private var gestureAnchor:Anchor?
    @State private var invalidated=false
    @GestureState private var resizing=false
    @Namespace private var canvasSpace

    private enum Operation:Equatable {case move,resize}
    private struct Context:Equatable {
        let projectID:UUID;let revision:Int;let clipID:UUID?;let sectionID:UUID;let patternID:UUID
        let length:Int;let selected:UUID?;let lowPitch:Int;let barWidth:CGFloat;let snap:Int
    }
    private struct Anchor {
        let context:Context;let operation:Operation;let original:NoteEvent
    }
    private struct Interaction {
        let anchor:Anchor
        var preview:NoteEvent
        var original:NoteEvent {anchor.original}
    }
    private var context:Context {Context(projectID:projectID,revision:revision,clipID:clipID,sectionID:sectionID,patternID:pattern.id,length:pattern.length,selected:selected,lowPitch:lowPitch,barWidth:barWidth,snap:snap)}
    private var selectedNote:NoteEvent? {pattern.notes?.first{$0.id==selected}}
    private var displayedSelection:NoteEvent? {interaction?.preview ?? selectedNote}
    private var contentWidth:CGFloat {CGFloat(pattern.length)/CGFloat(barTicks)*barWidth}
    private var touching:Bool {gestureAnchor != nil || resizing}
    private func rect(_ n:NoteEvent)->CGRect {CGRect(x:CGFloat(n.tick)/CGFloat(barTicks)*barWidth,y:CGFloat(lowPitch+23-n.pitch)*24+2,width:max(4,CGFloat(n.duration)/CGFloat(barTicks)*barWidth-2),height:20)}
    private func hit(_ point:CGPoint)->NoteEvent? {(pattern.notes ?? []).filter{(lowPitch...lowPitch+23).contains($0.pitch)}.sorted{($0.id==selected ? 0:1)<($1.id==selected ? 0:1)}.first{rect($0).insetBy(dx:-8,dy:-2).contains(point)}}
    private func endpoint(_ note:NoteEvent)->CGFloat {CGFloat(note.tick+note.duration)/CGFloat(barTicks)*barWidth}
    private func gripCenter(_ note:NoteEvent)->CGPoint {CGPoint(x:min(max(22,endpoint(note)+14),max(22,contentWidth-22)),y:min(554,max(22,rect(note).midY)))}
    private func position(_ tick:Int)->String {MusicalPosition(tick:tick).description}

    var body:some View {
        ZStack(alignment:.topLeading){
            drawing.allowsHitTesting(false)
            PianoCanvasInput(hitNote: hit, tap: { point in
                if let note = hit(point) { select(note.id) }
                else { insert(Int(point.x/barWidth*CGFloat(barTicks)), min(127,max(0,lowPitch+23-Int(point.y/24)))) }
            }, drag: { note, translation in
                update(.move, translation: translation, note: note)
            }, end: { translation in
                finish(.move, translation: translation)
            }, cancel: cancel)
            .accessibilityLabel("Piano roll. Use the note list to edit with VoiceOver.")
            .accessibilityIdentifier("notes.canvas")
            if let note=displayedSelection,(lowPitch...lowPitch+23).contains(note.pitch) {
                resizeGrip(note).position(gripCenter(note))
            }
            if let draft=interaction?.preview {
                endpointGuide(draft)
                readout(draft).allowsHitTesting(false)
            }
        }
        .coordinateSpace(name:canvasSpace)
        .onChange(of:context){_,_ in
            if touching || gestureAnchor != nil{interaction=nil;gestureAnchor=nil;invalidated=touching;editingChanged(false)}
        }
        .onChange(of:resizing){_,active in
            // Resetting GestureState can precede onEnded. Remove the visible
            // draft and release scrolling, but keep the immutable start anchor
            // for completion. A system cancellation never invokes onEnded.
            // update() takes ownership only when the touch actually found a note.
            // Holding blank canvas must still allow a one-finger pan.
            if !active { interaction=nil; invalidated=false; editingChanged(false) }
        }
        .onChange(of:scenePhase){_,phase in if phase != .active{interaction=nil;gestureAnchor=nil;invalidated=touching;editingChanged(false)}}
        .onDisappear{cancel()}
    }
    private var drawing:some View {
        Canvas{context,size in
            for row in 0..<24 {
                let pitch=lowPitch+23-row,y=CGFloat(row)*24
                let black=[1,3,6,8,10].contains(pitch%12)
                context.fill(Path(CGRect(x:0,y:y,width:size.width,height:24)),with:.color(black ? .ink:.panel))
                var line=Path();line.move(to:CGPoint(x:0,y:y));line.addLine(to:CGPoint(x:size.width,y:y))
                context.stroke(line,with:.color(pitch%12==11 ? .outline:.raised),lineWidth:0.5)
            }
            for step in 0...pattern.length/snap {
                let position=step*snap,x=CGFloat(position)/CGFloat(barTicks)*barWidth
                let bar=position%barTicks==0,beat=position%ppq==0
                var line=Path();line.move(to:CGPoint(x:x,y:0));line.addLine(to:CGPoint(x:x,y:size.height))
                let color:Color=bar ? .muted.opacity(0.5):beat ? .outline:.raised
                context.stroke(line,with:.color(color),lineWidth:bar ? 1:0.5)
            }
            let drag=interaction
            for original in pattern.notes ?? [] {
                var note=original
                if let drag,drag.original.id==original.id{note=drag.preview}
                guard (lowPitch...lowPitch+23).contains(note.pitch) else{continue}
                let r=rect(note),active=note.id==selected || note.id==drag?.original.id
                let shape=Path(roundedRect:r,cornerRadius:4)
                context.fill(shape,with:.color(.mint.opacity(active ? 1:0.35+Double(note.velocity)/254)))
                context.stroke(shape,with:.color(active ? .studioText.opacity(0.8):.mint.opacity(0.45)),lineWidth:active ? 1:0.5)
                // The cap and endpoint belong to the note's actual rectangle;
                // neither introduces a second animated geometry while held.
                if r.width>6 {
                    let top=CGRect(x:r.minX+3,y:r.minY+2,width:r.width-6,height:1)
                    context.fill(Path(top),with:.color(active ? .studioText.opacity(0.6):.mint.opacity(0.4)))
                    if active{context.fill(Path(CGRect(x:r.maxX-3,y:r.minY+4,width:2,height:12)),with:.color(.ink))}
                }
                if note.id==drag?.original.id {
                    context.stroke(Path(roundedRect:rect(original),cornerRadius:4),with:.color(.mint.opacity(0.35)),style:StrokeStyle(lineWidth:1,dash:[3,3]))
                }
            }
            if tick>=0 && tick<Double(pattern.length){let x=CGFloat(tick)/CGFloat(barTicks)*barWidth;var line=Path();line.move(to:CGPoint(x:x,y:0));line.addLine(to:CGPoint(x:x,y:size.height));context.stroke(line,with:.color(.record),lineWidth:1.5)}
        }
    }
    private func resizeGrip(_ note:NoteEvent)->some View {
        Image(systemName:"arrow.left.and.right").font(.system(size:12,weight:.bold)).foregroundStyle(Color.ink)
            .frame(width:28,height:28).background(Color.mint,in:Circle())
            .overlay{Circle().stroke(Color.studioText.opacity(0.7),lineWidth:1).frame(width:28,height:28)}
            .frame(width:44,height:44).contentShape(Rectangle())
            .accessibilityLabel("Resize note").accessibilityValue("\(note.duration) ticks")
            .accessibilityAddTraits(.isButton).accessibilityIdentifier("notes.resize-handle")
            .accessibilityAdjustableAction{direction in
                guard interaction==nil else{return}
                switch direction{case .increment:resize(note.id,note.duration+snap);case .decrement:resize(note.id,note.duration-snap);@unknown default:break}
            }
            .highPriorityGesture(DragGesture(minimumDistance:0,coordinateSpace:.named(canvasSpace))
                .updating($resizing){_,active,_ in active=true}
                .onChanged{drag in update(.resize,translation:drag.translation,note:selectedNote)}
                .onEnded{drag in finish(.resize,translation:drag.translation)})
    }
    private func endpointGuide(_ note:NoteEvent)->some View {
        Path{path in path.move(to:CGPoint(x:endpoint(note),y:max(0,rect(note).minY-58)));path.addLine(to:CGPoint(x:endpoint(note),y:min(576,rect(note).maxY+10)))}
            .stroke(Color.mint,style:StrokeStyle(lineWidth:1,dash:[3,3])).allowsHitTesting(false)
    }
    private func readout(_ note:NoteEvent)->some View {
        VStack(spacing:3){
            Text("End \(position(note.tick+note.duration))").font(.system(.caption,design:.monospaced,weight:.semibold))
            Text("\(Double(note.duration)/Double(ppq),specifier:"%.2f") beats").font(.caption2.monospacedDigit()).foregroundStyle(Color.muted)
        }.foregroundStyle(Color.studioText).padding(.horizontal,12).padding(.vertical,8)
            .background(Color.raised,in:RoundedRectangle(cornerRadius:10,style:.continuous))
            .overlay{RoundedRectangle(cornerRadius:10,style:.continuous).stroke(Color.mint,lineWidth:1)}
            .fixedSize().position(x:min(max(64,endpoint(note)),max(64,contentWidth-64)),y:rect(note).minY>=70 ? rect(note).midY-60:rect(note).midY+64)
            .accessibilityIdentifier("notes.drag-preview")
    }
    private func update(_ operation:Operation,translation:CGSize,note:NoteEvent?){
        guard !invalidated,let note else{return}
        if interaction==nil {
            let anchor=Anchor(context:context,operation:operation,original:note)
            gestureAnchor=anchor;interaction=Interaction(anchor:anchor,preview:note)
            editingChanged(true)
        }
        guard let current=gestureAnchor,current.context==context,current.operation==operation,
              pattern.notes?.first(where:{$0.id==current.original.id})==current.original else{interaction=nil;gestureAnchor=nil;invalidated=true;editingChanged(false);return}
        interaction?.preview=preview(current,translation:translation)
    }
    private func preview(_ interaction:Anchor,translation:CGSize)->NoteEvent {
        guard barWidth.isFinite,barWidth>0,translation.width.isFinite,translation.height.isFinite else{return interaction.original}
        let step=max(1,snap)
        let rawSteps=Double(translation.width/barWidth)*Double(barTicks)/Double(step)
        let steps=Int(min(Double(pattern.length/step+1),max(-Double(pattern.length/step+1),rawSteps)).rounded())
        let pitchDelta=Int(min(127,max(-127,Double(translation.height/24))).rounded())
        if steps==0 && (interaction.operation == .resize || pitchDelta==0){return interaction.original}
        var temporary=Pattern(length:pattern.length,notes:[interaction.original])
        switch interaction.operation {
        case .resize:NoteEditing.resize(interaction.original.id,in:&temporary,duration:interaction.original.duration+steps*step,step:step)
        case .move:NoteEditing.move(interaction.original.id,in:&temporary,tick:interaction.original.tick+steps*step,pitch:min(lowPitch+23,max(lowPitch,interaction.original.pitch-pitchDelta)),step:step)
        }
        return temporary.notes?.first ?? interaction.original
    }
    private func finish(_ operation:Operation,translation:CGSize){
        defer{cancel()}
        guard !invalidated,let current=gestureAnchor,current.operation==operation,current.context==context,
              pattern.notes?.first(where:{$0.id==current.original.id})==current.original else{return}
        let final=preview(current,translation:translation)
        guard final != current.original else{return}
        select(final.id)
        switch operation{case .move:move(final.id,final.tick,final.pitch);case .resize:resize(final.id,final.duration)}
    }
    private func cancel(){interaction=nil;gestureAnchor=nil;invalidated=false;editingChanged(false)}
}

private struct NoteInspector:View {
    @Environment(\.dynamicTypeSize) private var dynamicType
    private var layout:AnyLayout{dynamicType.isAccessibilitySize ? AnyLayout(VStackLayout(spacing:8)):AnyLayout(HStackLayout(spacing:16))}
    @Bindable var session:Session;let patternID:UUID;let note:NoteEvent;let snap:Int;let spelling:PitchSpelling
    private var noteName:String{MusicalNotation.noteName(note.pitch,keyRoot:session.project.keyRoot,minor:session.project.minor,spelling:spelling)}
    func edit(_ action:(inout NoteEvent)->Void){session.edit{p in if let i=p.patterns.firstIndex(where:{$0.id==patternID}),let j=p.patterns[i].notes?.firstIndex(where:{$0.id==note.id}){action(&p.patterns[i].notes![j])}}}
    var body:some View {
        VStack(spacing:6){
            layout{Stepper(noteName,value:Binding(get:{note.pitch},set:{v in edit{$0.pitch=v}}),in:0...127).accessibilityLabel("Note pitch").accessibilityValue(Text(verbatim:noteName)).accessibilityIdentifier("notes.selection.pitch");Text("\(note.duration) ticks").monospacedDigit().accessibilityIdentifier("notes.selection.duration")}
            layout{Stepper("Start",onIncrement:{move(note.tick+snap)},onDecrement:{move(note.tick-snap)}).accessibilityLabel("Note start").accessibilityValue(MusicalPosition(tick:note.tick).description).accessibilityIdentifier("notes.selection.start");Stepper("Length",onIncrement:{resize(note.duration+snap)},onDecrement:{resize(note.duration-snap)}).accessibilityLabel("Note duration")}
            HStack{Text("Velocity").font(.caption);Slider(value:Binding(get:{Double(note.velocity)},set:{v in session.coalescedMusicEdit{p in if let i=p.patterns.firstIndex(where:{$0.id==patternID}),let j=p.patterns[i].notes?.firstIndex(where:{$0.id==note.id}){p.patterns[i].notes?[j].velocity=Int(v)}}}),in:1...127,step:1,onEditingChanged:{_ in session.mixerGesture=false}).accessibilityLabel("Note velocity");Text("\(note.velocity)").font(.caption.monospaced()).frame(width:28)}
        }.padding(.horizontal,16).font(.caption).background(Color.panel)
            .overlay(alignment:.top){Rectangle().fill(Color.outline.opacity(0.6)).frame(height:0.5)}
            .overlay(alignment:.bottom){Rectangle().fill(Color.outline.opacity(0.6)).frame(height:0.5)}
    }
    func move(_ tick:Int){session.edit{p in if let i=p.patterns.firstIndex(where:{$0.id==patternID}){NoteEditing.move(note.id,in:&p.patterns[i],tick:tick,pitch:note.pitch,step:snap)}}}
    func resize(_ duration:Int){session.edit{p in if let i=p.patterns.firstIndex(where:{$0.id==patternID}){NoteEditing.resize(note.id,in:&p.patterns[i],duration:duration,step:snap)}}}
}
