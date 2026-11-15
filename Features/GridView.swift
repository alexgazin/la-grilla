import SwiftUI
import UIKit
import MusicDomain
struct ChordSelection: Identifiable {let id: UUID;let patternID: UUID;let tick: Int;let chord: Chord;var duration: Int = barTicks}
struct GridView: View {
    @Bindable var session: Session
    @Environment(\.dynamicTypeSize) private var dynamicType
    @State private var barWidth: CGFloat = 96
    @State private var zoomBase: CGFloat = 96
    @State private var selection: ChordSelection?
    @State private var dragStart: Int?
    @State private var viewport=CGSize(width:440,height:630)
    @State private var zoomed=false
    @State private var clipMode=ProcessInfo.processInfo.arguments.contains("--arrangement-clips")
    @State private var copyOnDrag=false
    @State private var clipSnap=barTicks
    @State private var clipSelection:ClipEditorSelection?
    @State private var pendingClipEditor:ClipEditorSelection?
    @State private var showClipList=false
    @State private var pendingClipInspector:ClipEditorSelection?
    @State private var targetTrack:UUID?
    @State private var grabbedClip:UUID?
    @State private var grabbedOffset=0
    @State private var resizeDraft:ClipResizeDraft?
    private struct ClipResizeDraft {let payload:ArrangementDragPayload;let originalLength:Int;var length:Int;let start:Int}
    private let gutter:CGFloat=56
    private var laneScale:CGFloat{min(1.35,max(0.78,(viewport.height-155)/324))}
    private var harmonyHeight:CGFloat{132*laneScale}
    private var drumHeight:CGFloat{100*laneScale}
    private var bassHeight:CGFloat{92*laneScale}
    private var melodyHeight:CGFloat{64}
    private var musicHeight:CGFloat{harmonyHeight+drumHeight+bassHeight+CGFloat(session.displayProject.tracks.filter{$0.role == .melody}.count)*melodyHeight}
    private var editingLocked:Bool{session.performance.contextActive || session.recording || session.armed}
    private var timelineBars:Int {
        let base=session.displayProject.length/barTicks
        let resized=resizeDraft.map{($0.start+$0.length+barTicks-1)/barTicks} ?? 0
        return clipMode ? min(64,max(base+4,resized)):base
    }
    var body: some View {
        GeometryReader{geometry in
            VStack(spacing:0){
                ScrollView(.vertical,showsIndicators:false){
                    VStack(alignment:.leading,spacing:0){
                        arrangementHeader
                        sectionChips
                        if clipMode{clipControls.padding(.horizontal,16).padding(.bottom,8)}
                        HStack(spacing:0){
                            VStack(spacing:0){Color.clear.frame(height:28);trackLabel(.harmony,height:harmonyHeight);trackLabel(.drums,height:drumHeight);trackLabel(.bass,height:bassHeight);ForEach(session.displayProject.tracks.filter{$0.role == .melody}){track in Button{session.openNotes(track.id)}label:{Text(track.displayName).font(.system(size:11,weight:.semibold)).lineLimit(2).foregroundStyle(Color.mint).padding(8).frame(width:gutter,height:melodyHeight)}.buttonStyle(StudioQuietButtonStyle())}}.frame(width:gutter)
                            ScrollView(.horizontal,showsIndicators:true){ZStack(alignment:.topLeading){
                                timeline
                                Rectangle().fill(Color.mint).frame(width:2,height:musicHeight).offset(x:CGFloat(session.audio.tick)/CGFloat(barTicks)*barWidth,y:28).allowsHitTesting(false)
                                Image(systemName:"triangle.fill").font(.system(size:11)).rotationEffect(.degrees(180)).foregroundStyle(Color.mint).offset(x:CGFloat(session.audio.tick)/CGFloat(barTicks)*barWidth-4,y:18).allowsHitTesting(false)
                            }.frame(width:CGFloat(timelineBars)*barWidth).gesture(MagnifyGesture().onChanged{value in zoomed=true;barWidth=min(640,max(68,zoomBase*value.magnification))}.onEnded{_ in zoomBase=barWidth})}
                        }
                    }
                }
                tools.padding(.horizontal,12).padding(.vertical,7)
            }.onAppear{configureViewport(geometry.size)}.onChange(of:geometry.size){_,size in configureViewport(size)}.onChange(of:session.project.id){_,_ in zoomed=false;configureViewport(geometry.size)}.onChange(of:session.displayProject.length){_,_ in configureViewport(geometry.size)}
        }.sheet(item:$selection){selection in ChordEditor(session:session,selection:selection).presentationDetents([.large]).presentationDragIndicator(.visible).presentationBackground(Color.panel)}
            .sheet(item:$clipSelection,onDismiss:openPendingClipEditor){choice in ArrangementClipInspector(session:session,selection:choice){pendingClipEditor=choice;clipSelection=nil}.presentationDragIndicator(.visible).presentationBackground(Color.panel)}
            .sheet(isPresented:$showClipList,onDismiss:{if let choice=pendingClipInspector{pendingClipInspector=nil;clipSelection=choice}}){clipList}
    }
    private func configureViewport(_ size:CGSize){
        viewport=size
        if !zoomed,size.width>gutter{barWidth=max(68,(size.width-gutter)/CGFloat(min(4,max(1,session.displayProject.length/barTicks))));zoomBase=barWidth}
    }
    private var arrangementHeader:some View {
        HStack {
            SmallHeading(text:"ARRANGEMENT")
            Spacer()
            Text("\(session.displayProject.length/barTicks) bars")
                .font(.system(size:11,design:.monospaced)).foregroundStyle(Color.muted)
            IconButton(symbol:clipMode ? "pianokeys":"rectangle.3.group",label:clipMode ? "Edit chords":"Arrange clips",color:clipMode ? .mint:.muted){clipMode.toggle()}
                .accessibilityIdentifier("grid.mode.clips").accessibilityValue(LocalizedStringKey(clipMode ? "Clips":"Chords"))
            IconButton(symbol:"ellipsis",label:"Edit song sections",color:.muted){session.presentEditor(.sections)}
                .accessibilityIdentifier("sections.open")
        }.padding(.horizontal,16)
    }
    private var sectionChips:some View {
        ScrollView(.horizontal,showsIndicators:false) {
            HStack(spacing:6) {
                ForEach(session.displayProject.sections){section in sectionChip(section)}
                Button{session.presentEditor(.sections)}label:{Image(systemName:"plus").frame(width:44,height:44).foregroundStyle(Color.muted)}
                    .buttonStyle(StudioQuietButtonStyle())
            }.padding(.horizontal,16)
        }.padding(.bottom,8)
    }
    private func sectionChip(_ section:MusicDomain.Section)->some View {
        let selected=session.section.id==section.id
        return Button{session.select(section)}label:{
            HStack(spacing:6) {
                Text(section.name).font(.system(size:12,weight:.semibold))
                Text("\(section.start/barTicks+1)–\((section.start+section.length)/barTicks)")
                    .font(.system(size:11,design:.monospaced)).opacity(0.7)
            }.padding(.horizontal,14).frame(minHeight:44)
                .foregroundStyle(selected ? Color.ink:Color.studioText)
                .background(selected ? Color.mint:Color.panel,in:Capsule())
        }.buttonStyle(StudioQuietButtonStyle()).accessibilityIdentifier("grid.section.\(section.id)")
            .modifier(ArrangementDragSource(payload:editingLocked ? nil:ArrangementDragPayload(project:session.project,sectionID:section.id).encoded()))
            .dropDestination(for:String.self){items,_ in dropSection(items,on:section.id)}
    }
    private var clipControls:some View {
        HStack(spacing:10) {
            Menu {
                Picker("Clip snap",selection:$clipSnap){Text("1 bar").tag(barTicks);Text("1 beat").tag(ppq);Text("1/16").tag(240)}
                Toggle("Copy on drag",isOn:$copyOnDrag)
                Button("Play whole song"){session.setLoop(enabled:false)}
            } label: {Label(LocalizedStringKey(copyOnDrag ? "Copy clips":"Move clips"),systemImage:copyOnDrag ? "plus.rectangle.on.rectangle":"hand.draw").font(.system(size:11,weight:.medium)).frame(minHeight:44)}.accessibilityIdentifier("grid.clip.options")
            Spacer(minLength:4)
            Text(LocalizedStringKey(clipSnap==barTicks ? "1 bar":clipSnap==ppq ? "1 beat":"1/16")).font(.system(size:11,design:.monospaced)).foregroundStyle(Color.muted)
            IconButton(symbol:"list.bullet",label:"Clip list",color:.mint){showClipList=true}.accessibilityIdentifier("grid.clips.list")
        }.foregroundStyle(Color.mint)
    }
    private var clipTimeline:some View {
        let project=session.displayProject,notes=Compiler.notes(project)
        return VStack(spacing:0) {
            ruler
            if let track=project.tracks.first(where:{$0.role == .harmony}) {clipLane(track,height:harmonyHeight,notes:notes)}
            if let track=project.tracks.first(where:{$0.role == .drums}) {clipLane(track,height:drumHeight,notes:notes)}
            bassLane.overlay(alignment:.bottomLeading){Text("Root bass follows harmony").font(.system(size:11)).foregroundStyle(Color.muted).padding(8)}
                .dropDestination(for:String.self){items,_ in
                    guard let track=project.tracks.first(where:{$0.role == .bass}) else{session.message=ClipEditingError.derivedBass.localizedDescription;return false}
                    return dropClip(items,on:track.id,at:.zero)
                }
            ForEach(project.tracks.filter{$0.role == .melody}){track in clipLane(track,height:melodyHeight,notes:notes)}
        }
    }
    private func clipLane(_ track:Track,height:CGFloat,notes:[CompiledNote])->some View {
        let index=session.displayProject.tracks.firstIndex(where:{$0.id==track.id}) ?? -1
        let rendered=notes.filter{$0.track==index}
        return ZStack(alignment:.topLeading) {
            gridBackground(height:height).contentShape(Rectangle()).gesture(SpatialTapGesture().onEnded{value in
                guard !editingLocked else{return}
                let tick=max(0,min(64*barTicks-clipSnap,Int(value.location.x/barWidth*CGFloat(barTicks))/clipSnap*clipSnap))
                session.edit{try ClipEditing.create(on:track.id,start:tick,length:barTicks,snap:clipSnap,in:&$0)}
            })
            if targetTrack==track.id {Rectangle().fill(Color.mint.opacity(0.09)).allowsHitTesting(false)}
            ForEach(track.clips){clip in clipBlock(track:track,clip:clip,height:height,notes:rendered)}
        }.frame(width:CGFloat(timelineBars)*barWidth,height:height)
            // The drop host contains distinct clip controls. It must not absorb
            // their accessibility frames into its lane-wide UIKit host view.
            .accessibilityElement(children:.contain)
            .dropDestination(for:String.self,action:{items,point in dropClip(items,on:track.id,at:point)},isTargeted:{targeted in if targeted{targetTrack=track.id}else if targetTrack==track.id{targetTrack=nil}})
    }
    private func clipBlock(track:Track,clip:Clip,height:CGFloat,notes:[CompiledNote])->some View {
        let draft=resizeDraft?.payload.objectID==clip.id ? resizeDraft:nil
        let visibleLength=draft?.length ?? clip.length
        let width=max(4,CGFloat(visibleLength)/CGFloat(barTicks)*barWidth-6)
        let control=Button {
            guard !editingLocked else{return}
            clipSelection=ClipEditorSelection(trackID:track.id,clipID:clip.id)
        } label: {
            ArrangementClipFace(notes:notes,track:track,clip:clip,width:width,height:max(44,height-12),resizing:draft != nil)
            .overlay(alignment:.trailing){
                Image(systemName:"line.3.horizontal").font(.system(size:11,weight:.semibold)).rotationEffect(.degrees(90)).foregroundStyle(Color.track(track.role))
                    .frame(width:min(18,max(6,width*0.2)),height:44).frame(width:44,height:44).contentShape(Rectangle())
                    .highPriorityGesture(DragGesture(minimumDistance:1).onChanged{value in
                        guard !editingLocked else{return}
                        if resizeDraft?.payload.objectID != clip.id {resizeDraft=ClipResizeDraft(payload:.init(project:session.project,trackID:track.id,clipID:clip.id),originalLength:clip.length,length:clip.length,start:clip.start)}
                        guard var current=resizeDraft else{return}
                        let ticks=Double(current.originalLength)+Double(value.translation.width/barWidth)*Double(barTicks)
                        let bounded=max(Double(clipSnap),min(Double(64*barTicks-current.start),ticks))
                        current.length=(try? ClipEditing.snapped(Int(bounded),step:clipSnap)) ?? clip.length;resizeDraft=current
                    }.onEnded{_ in
                        guard let current=resizeDraft,current.payload.objectID==clip.id else{return};resizeDraft=nil
                        guard current.length != current.originalLength else{return}
                        let snap=clipSnap
                        session.edit{try ClipEditing.resize(current.payload,length:current.length,snap:snap,in:&$0)}
                    })
                    .accessibilityLabel("Resize clip").accessibilityHidden(true)
            }
        }.buttonStyle(.plain).frame(width:width,height:max(44,height-12)).contentShape(Rectangle())
            .simultaneousGesture(DragGesture(minimumDistance:0).onChanged{value in
                if grabbedClip != clip.id{grabbedClip=clip.id;grabbedOffset=max(0,min(clip.length-1,Int(value.startLocation.x/barWidth*CGFloat(barTicks))))}
            }.onEnded{_ in grabbedClip=nil})
            .modifier(ArrangementDragSource(payload:editingLocked || resizeDraft != nil ? nil:ArrangementDragPayload(project:session.project,trackID:track.id,clipID:clip.id,grabOffset:grabbedClip==clip.id ? grabbedOffset:0).encoded()))
            .contextMenu{
                Button("Edit clip contents"){pendingClipEditor=ClipEditorSelection(trackID:track.id,clipID:clip.id);openPendingClipEditor()}
                Button("Clip settings"){clipSelection=ClipEditorSelection(trackID:track.id,clipID:clip.id)}
                Button("Duplicate clip"){
                    let token=ArrangementDragPayload(project:session.project,trackID:track.id,clipID:clip.id)
                    session.edit{try ClipEditing.copy(token,to:track.id,start:clip.start+clip.length,snap:240,in:&$0)}
                }
                Button("Delete clip",role:.destructive){let token=ArrangementDragPayload(project:session.project,trackID:track.id,clipID:clip.id);session.edit{try ClipEditing.delete(token,in:&$0)}}
            }
            .accessibilityHidden(true)
        return ZStack {
            control
            ArrangementClipAccessibility(label:track.displayName,value:String(format:NSLocalizedString("%.2f bars",comment:"Clip length"),Double(clip.length)/Double(barTicks)),identifier:"grid.clip.\(clip.id)",enabled:!editingLocked){
                clipSelection=ClipEditorSelection(trackID:track.id,clipID:clip.id)
            }.frame(width:width,height:max(44,height-12))
        }.frame(width:width,height:max(44,height-12))
            .offset(x:CGFloat(clip.start)/CGFloat(barTicks)*barWidth+3,y:6)
            .allowsHitTesting(!editingLocked)
    }
    private func dropClip(_ items:[String],on trackID:UUID,at point:CGPoint)->Bool {
        guard !editingLocked,items.count==1 else{return false}
        do {
            let payload=try ArrangementDragPayload.decode(items[0])
            guard payload.kind == .clip else{throw ClipEditingError.invalidDrag}
            let raw=Double(point.x/barWidth)*Double(barTicks)-Double(payload.grabOffset)
            let tick=max(0,min(64*barTicks,Int(raw)))
            let copy=copyOnDrag,snap=clipSnap
            if !copy,payload.sourceTrackID==trackID,let track=session.project.tracks.first(where:{$0.id==trackID}),let clip=track.clips.first(where:{$0.id==payload.objectID}),try ClipEditing.snapped(tick,step:snap)==clip.start{
                try payload.validate(in:session.project,kind:.clip);return true
            }
            var applied=false
            session.edit{project in if copy{try ClipEditing.copy(payload,to:trackID,start:tick,snap:snap,in:&project)}else{try ClipEditing.move(payload,to:trackID,start:tick,snap:snap,in:&project)};applied=true}
            return applied
        } catch {session.message=error.localizedDescription;return false}
    }
    private func dropSection(_ items:[String],on sectionID:UUID)->Bool {
        guard !editingLocked,items.count==1 else{return false}
        do {
            let token=try ArrangementDragPayload.decode(items[0]);try token.validate(in:session.project,kind:.section)
            if token.objectID==sectionID{return true}
            var applied=false;session.edit{try ClipEditing.reorderSection(token,to:sectionID,in:&$0);applied=true};return applied
        } catch {session.message=error.localizedDescription;return false}
    }
    private func openPendingClipEditor() {
        guard let choice=pendingClipEditor else{return};pendingClipEditor=nil
        guard let track=session.project.tracks.first(where:{$0.id==choice.trackID}),let clip=track.clips.first(where:{$0.id==choice.clipID}),let pattern=session.project.patterns.first(where:{$0.id==clip.patternID})else{session.message=ClipEditingError.missing.localizedDescription;return}
        if track.role == .melody {session.openNotes(track.id,clipID:clip.id)}
        else if track.role == .drums {session.openDrumClip(clip.id)}
        else if track.role == .harmony {
            clipMode=false
            let event=pattern.chords.sorted{$0.tick<$1.tick}.first
            selection=ChordSelection(id:event?.id ?? UUID(),patternID:pattern.id,tick:event?.tick ?? 0,chord:event?.chord ?? Chord(root:session.project.keyRoot,quality:session.project.minor ? .minor:.major),duration:event?.duration ?? barTicks)
        }
    }
    private var clipList:some View {
        NavigationStack {
            clipListContents.navigationTitle("Clip list")
                .toolbar{ToolbarItem(placement:.confirmationAction){Button("Done"){showClipList=false}}}
        }.tint(.mint)
    }
    private var clipListContents:some View {
        let tracks=session.project.tracks
        return List{ForEach(tracks){track in clipListSection(track)}}
    }
    private func clipListSection(_ track:Track)->some View {
        let clips=track.clips.sorted{$0.start<$1.start}
        return SwiftUI.Section {
            if track.role != .bass{ForEach(clips){clip in clipListRow(trackID:track.id,clip:clip)}}
            addClipButton(track)
            if track.role == .bass{Text("Root bass follows harmony and cannot hold independent clips.").font(.caption).foregroundStyle(Color.muted)}
        } header:{Text(track.displayName)}
    }
    private func addClipButton(_ track:Track)->some View {
        let label=String(format:NSLocalizedString("Add clip to %@",comment:"Create a clip on a track"),track.displayName)
        return Button{addClip(on:track)}label:{
            Label("Add clip",systemImage:"plus").frame(maxWidth:.infinity,minHeight:44,alignment:.leading).contentShape(Rectangle())
        }.accessibilityLabel(label).accessibilityIdentifier("grid.clip.add.\(track.role.rawValue).\(track.id)")
            .disabled(track.role == .bass || editingLocked)
    }
    private func clipListRow(trackID:UUID,clip:Clip)->some View {
        let position="\(clip.start/barTicks+1):\(clip.start%barTicks/240+1)"
        let length=String(format:NSLocalizedString("%.2f bars",comment:"Clip length"),Double(clip.length)/Double(barTicks))
        return Button {
            pendingClipInspector=ClipEditorSelection(trackID:trackID,clipID:clip.id)
            showClipList=false
        } label:{
            HStack{Text(position);Spacer();Text(length).foregroundStyle(Color.muted)}.frame(minHeight:44)
        }.accessibilityIdentifier("grid.clip.list.\(clip.id)")
    }
    private func nextFreeClipStart(on track:Track)->Int? {
        var start=0
        for clip in track.clips.sorted(by:{$0.start<$1.start}) {
            if start+barTicks<=clip.start{return start}
            let end=clip.start+clip.length
            if end>start{start=((end+clipSnap-1)/clipSnap)*clipSnap}
        }
        return start+barTicks<=64*barTicks ? start:nil
    }
    private func addClip(on track:Track){
        guard !editingLocked,track.role != .bass else{return}
        guard let start=nextFreeClipStart(on:track)else{
            session.message=NSLocalizedString("There is no room for another clip. Shorten or move an existing clip first.",comment:"Arrangement clip creation")
            return
        }
        let existing=Set(track.clips.map(\.id)),revision=session.project.revision
        session.edit{try ClipEditing.create(on:track.id,start:start,length:barTicks,snap:clipSnap,in:&$0)}
        guard session.project.revision>revision,
              let created=session.project.tracks.first(where:{$0.id==track.id})?.clips.first(where:{!existing.contains($0.id)})else{return}
        pendingClipInspector=ClipEditorSelection(trackID:track.id,clipID:created.id)
        showClipList=false
    }
    @ViewBuilder private var tools:some View {
        if dynamicType.isAccessibilitySize {
            Menu("Studio tools"){
                Button("Harmony lab"){session.presentEditor(.harmony)};Button("Piano roll"){session.openNotes()};Button("Assistant"){session.presentEditor(.assistant)};Button("Voice to MIDI"){session.presentEditor(.voice)};Button("Perform"){session.sheet = .perform};Button("MIDI devices"){session.presentEditor(.midiDevices)}
            }.font(.headline).frame(maxWidth:.infinity,minHeight:44).modifier(StudioSurface())
        }else{
            HStack(spacing:2){
                Button{session.presentEditor(.harmony)}label:{Label("Harmony",systemImage:"wand.and.stars").frame(maxWidth:.infinity,minHeight:44)}.accessibilityLabel("Harmony lab").accessibilityIdentifier("harmony.open")
                Button{session.openNotes()}label:{Label("Notes",systemImage:"pianokeys").frame(maxWidth:.infinity,minHeight:44)}.accessibilityLabel("Open piano roll").accessibilityIdentifier("notes.open")
                Button{session.presentEditor(.assistant)}label:{Label("Assistant",systemImage:"text.bubble").frame(maxWidth:.infinity,minHeight:44)}.accessibilityIdentifier("assistant.open")
                Menu{
                    Button("Voice",systemImage:"waveform.badge.mic"){session.presentEditor(.voice)}.accessibilityIdentifier("voice.open")
                    Button("Perform",systemImage:"waveform.path"){session.finishTake();session.sheet = .perform}.accessibilityIdentifier("perform.open")
                    Button("MIDI devices",systemImage:"pianokeys"){session.presentEditor(.midiDevices)}.accessibilityIdentifier("midi.open")
                }label:{Image(systemName:"ellipsis.circle").frame(width:44,height:44)}.accessibilityLabel("More studio tools").accessibilityIdentifier("tools.more")
            }.buttonStyle(StudioQuietButtonStyle()).font(.system(size:11,weight:.medium)).lineLimit(1).minimumScaleFactor(1).foregroundStyle(Color.mint).padding(.horizontal,4).modifier(StudioSurface())
        }
    }
    func trackLabel(_ role: TrackRole,height: CGFloat)->some View {
        Button{if role == .harmony{session.presentEditor(.harmony)}else if role == .bass {session.presentEditor(.bass)}else if role == .drums{session.tab=1}}
        label:{VStack(alignment:.leading,spacing:9){RoundedRectangle(cornerRadius:2).fill(Color.track(role)).frame(width:18,height:3);Text(LocalizedStringKey(role == .harmony ? "HARM":role == .drums ? "DRUM":"BASS")).font(.system(size:11,weight:.semibold));Image(systemName:role == .harmony ? "pianokeys":role == .drums ? "square.grid.2x2":"waveform").font(.system(size:14)).foregroundStyle(Color.track(role))}.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.leading).padding(.leading,12).frame(height:height).background(Color.panel.opacity(0.6)).overlay(alignment:.bottom){Rectangle().fill(Color.raised).frame(height:1)}}.buttonStyle(StudioQuietButtonStyle()).accessibilityIdentifier(role == .bass ? "bass.open":"grid.track.\(role.rawValue)")
    }
    @ViewBuilder var timeline: some View {
        if clipMode{clipTimeline}else{VStack(spacing:0) { ruler; harmonyLane; drumLane; bassLane;ForEach(session.displayProject.tracks.filter{$0.role == .melody}){t in melodyLane(t)} }}
    }
    var ruler: some View {
        HStack(spacing:0) {
            ForEach(0..<timelineBars,id:\.self) { bar in
                Text(String(format:"%02d",bar+1)).font(.system(size:11,weight:.medium,design:.monospaced))
                    .foregroundStyle(bar<session.displayProject.length/barTicks ? Color.muted:Color.muted.opacity(0.5)).frame(width:barWidth,alignment:.leading)
            }
        }.frame(height:28).overlay(alignment:.topLeading) {
            Rectangle().fill(Color.mint.opacity(0.6))
                .frame(width:CGFloat(session.loopRange.count)/CGFloat(barTicks)*barWidth,height:2)
                .offset(x:CGFloat(session.loopRange.lowerBound)/CGFloat(barTicks)*barWidth)
        }
    }
    var harmonyLane: some View {
        ZStack(alignment:.topLeading) {
            gridBackground(height:harmonyHeight)
            if let track=session.displayProject.tracks.first(where:{$0.role == .harmony}) {
                ForEach(track.clips) { clip in
                    if let pattern=session.displayProject.patterns.first(where:{$0.id==clip.patternID}) {
                        ForEach(ClipEditing.chordSlices(clip:clip,pattern:pattern)) { slice in
                            chordCell(clip:clip,pattern:pattern,slice:slice)
                        }
                    }
                }
            }
        }.frame(height:harmonyHeight)
    }
    func chordCell(clip:Clip,pattern:Pattern,slice:ArrangementChordSlice)->some View {
        let event=slice.event,tick=slice.sourceTick
        return Button {
            selection=ChordSelection(id:event?.id ?? UUID(),patternID:pattern.id,
                tick:tick,
                chord:event?.chord ?? Chord(root:session.displayProject.keyRoot,quality:session.displayProject.minor ? .minor:.major),
                duration:event?.duration ?? slice.duration)
        } label: { ChordTile(chord:event?.chord,width:max(8,CGFloat(slice.duration)/CGFloat(barTicks)*barWidth-6),height:harmonyHeight-16) }
        .buttonStyle(StudioQuietButtonStyle()).disabled(editingLocked).accessibilityIdentifier("grid.chord.\(slice.id)").offset(x:CGFloat(slice.timelineTick)/CGFloat(barTicks)*barWidth+3,y:8)
        .simultaneousGesture(LongPressGesture(minimumDuration:0.35).sequenced(before:DragGesture()).onEnded { value in
            if case .second(true,let drag?)=value,let event {
                let delta=Int((drag.translation.width/barWidth*16).rounded())*240
                session.edit { p in
                    guard let i=p.patterns.firstIndex(where:{$0.id==clip.patternID}),let n=p.patterns[i].chords.firstIndex(where:{$0.id==event.id})else{return}
                    p.patterns[i].chords[n].tick=max(0,min(p.patterns[i].length-event.duration,event.tick+delta))
                }
            }
        })
        .contextMenu {
            if let event {
                Button("Delete chord",role:.destructive) {
                    session.edit { p in
                        if let i=p.patterns.firstIndex(where:{$0.id==clip.patternID}) { p.patterns[i].chords.removeAll(where:{$0.id==event.id}) }
                    }
                }
            }
        }
    }
    var drumLane: some View {
        ZStack(alignment:.topLeading) {
            gridBackground(height:drumHeight)
            Canvas { context,_ in
                for note in Compiler.notes(session.displayProject) where note.pad>=0 {
                    let x=CGFloat(note.tick)/CGFloat(barTicks)*barWidth
                    let y=CGFloat(note.pad%4)*18+16
                    context.fill(Path(roundedRect:CGRect(x:x+2,y:y,width:max(3,barWidth/32),height:5),cornerRadius:1),with:.color(.drums.opacity(note.pad==2 ? 0.4:0.9)))
                }
            }.accessibilityLabel("Drum pattern. Edit in Jam.")
        }.frame(height:drumHeight).onTapGesture{session.tab=1}
    }
    var bassLane: some View {
        ZStack(alignment:.topLeading) {
            gridBackground(height:bassHeight)
            if let index=session.displayProject.tracks.firstIndex(where:{$0.role == .bass}) {
                Canvas { context,_ in
                    for note in Compiler.notes(session.displayProject) where note.track==index {
                        let x=CGFloat(note.tick)/CGFloat(barTicks)*barWidth
                        let width=CGFloat(note.duration)/CGFloat(barTicks)*barWidth
                        context.fill(Path(roundedRect:CGRect(x:x+4,y:28,width:max(3,width-8),height:24),cornerRadius:4),with:.color(.bass.opacity(0.18)))
                        context.fill(Path(roundedRect:CGRect(x:x+12,y:38,width:max(3,width-24),height:3),cornerRadius:1),with:.color(.bass.opacity(0.7)))
                    }
                }
            } else {
                Button("+ Add root bass"){session.presentEditor(.bass)}.font(.system(size:12)).foregroundStyle(Color.bass).padding(20)
            }
        }.frame(height:bassHeight).onTapGesture{session.presentEditor(.bass)}
    }
    func melodyLane(_ track:Track)->some View {
        ZStack(alignment:.topLeading){gridBackground(height:melodyHeight)
            Canvas{context,_ in
                if let index=session.displayProject.tracks.firstIndex(where:{$0.id==track.id}){
                    for n in Compiler.notes(session.displayProject) where n.track==index{let x=CGFloat(n.tick)/CGFloat(barTicks)*barWidth;let y=CGFloat(84-min(84,max(48,n.pitch)))/36*48+10;context.fill(Path(roundedRect:CGRect(x:x+2,y:y,width:max(3,CGFloat(n.duration)/CGFloat(barTicks)*barWidth-2),height:5),cornerRadius:2),with:.color(.mint.opacity(0.7)))}
                }
            }
        }.frame(height:melodyHeight).contentShape(Rectangle()).onTapGesture{session.openNotes(track.id)}.accessibilityLabel("Edit \(track.displayName)")
    }
    func gridBackground(height: CGFloat)->some View {Canvas{context,size in for step in 0...timelineBars*4 {let x=CGFloat(step)*barWidth/4;var p=Path();p.move(to:CGPoint(x:x,y:0));p.addLine(to:CGPoint(x:x,y:height));context.stroke(p,with:.color(Color.raised.opacity(step%4==0 ? 1:0.4)),lineWidth:1)};var line=Path();line.move(to:CGPoint(x:0,y:height));line.addLine(to:CGPoint(x:size.width,y:height));context.stroke(line,with:.color(.raised),lineWidth:1)}}
}

/// Keep the drag source and receiver on the same native Transferable contract.
/// Locked clips retain tap/launch behavior without exporting an empty provider.
private struct ArrangementDragSource:ViewModifier {
    let payload:String?
    @ViewBuilder func body(content:Content)->some View {
        if let payload{content.draggable(payload)}else{content}
    }
}

/// UIKit's lane drop host can report its full bounds for custom SwiftUI
/// controls. Use the rendered clip geometry for VoiceOver focus and native hit
/// coordinates, including after a resize, move, zoom or horizontal scroll.
private struct ArrangementClipAccessibility:UIViewRepresentable {
    let label:String
    let value:String
    let identifier:String
    let enabled:Bool
    let activate:()->Void
    func makeUIView(context:Context)->ArrangementClipAccessibilityView {
        let view=ArrangementClipAccessibilityView()
        view.backgroundColor = .clear;view.isOpaque=false
        view.isUserInteractionEnabled=false;view.isAccessibilityElement=true
        return view
    }
    func updateUIView(_ view:ArrangementClipAccessibilityView,context:Context){
        view.accessibilityLabel=label;view.accessibilityValue=value;view.accessibilityIdentifier=identifier
        view.accessibilityTraits=enabled ? .button:[.button,.notEnabled]
        view.acceptsActivation=enabled;view.activate=activate
    }
}
private final class ArrangementClipAccessibilityView:UIView {
    var acceptsActivation=true
    var activate:(()->Void)?
    override var accessibilityFrame:CGRect {
        get{UIAccessibility.convertToScreenCoordinates(bounds,in:self)}
        set{super.accessibilityFrame=newValue}
    }
    override func accessibilityActivate()->Bool {
        guard acceptsActivation,let activate else{return false}
        activate();return true
    }
}

struct ChordTile: View {
    let chord: Chord?
    let width: CGFloat
    let height:CGFloat
    var body: some View {
        VStack(alignment:.leading,spacing:13) {
            HStack { Text(chord?.symbol ?? "+").font(.system(size:26,weight:.semibold)).lineLimit(1).minimumScaleFactor(0.5); Spacer() }
            if let chord {
                HStack(spacing:width<64 ? 1:3) {
                    ForEach(Array(chord.notes.enumerated()),id:\.offset) { _,note in
                        RoundedRectangle(cornerRadius:1).fill(Color.harmony.opacity(0.5))
                            .frame(width:max(2,(width-24-CGFloat(max(0,chord.notes.count-1))*(width<64 ? 1:3))/CGFloat(max(1,chord.notes.count))),height:3).offset(y:CGFloat(72-note)/4)
                    }
                }
                Text(chord.customIntervals == nil ? chord.quality.label:NSLocalizedString("Custom chord",comment:"Chord formula label"))
                    .font(.system(size:11)).lineLimit(1).foregroundStyle(Color.harmony.opacity(0.9))
            }
        }.foregroundStyle(Color.harmony).padding(12).frame(width:width,height:height,alignment:.topLeading)
            .background(Color.harmony.opacity(chord == nil ? 0.04:0.12),in:RoundedRectangle(cornerRadius:10))
            .overlay { RoundedRectangle(cornerRadius:10).stroke(Color.harmony.opacity(0.22),lineWidth:1) }
    }
}
