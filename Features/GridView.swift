import SwiftUI
import UIKit
import MusicDomain
import Observation

/// Read-only native QA inputs. Keep the latest raw framework anchor outside
/// the drag log ring; no target or musical result is supplied to the gesture.
@MainActor @Observable private final class GridZoomDiagnostics {
    static let shared=GridZoomDiagnostics()
    static let enabled=ProcessInfo.processInfo.arguments.contains("--uitesting")
    private(set) var report=""
    @ObservationIgnored private var sequence=0
    @ObservationIgnored private var beginLine=""
    @ObservationIgnored private var requestLine=""
    @ObservationIgnored private var awaitingAck=false
    @ObservationIgnored private var request:Request?
    private struct Request {
        let magnification:Double
        let position:TimelineZoom.Position
        let frozenAnchorX:Double
        let frozenAnchorBars:Double
    }
    func begin(unitAnchorX:Double,viewportWidth:Double,offset:Double,contentWidth:Double,barWidth:Double){
        guard Self.enabled else{return}
        sequence+=1;request=nil;requestLine="";awaitingAck=false
        beginLine="BEGIN id=\(sequence) unitAnchorX=\(unitAnchorX) viewportWidth=\(viewportWidth) offset=\(offset) contentWidth=\(contentWidth) barWidth=\(barWidth)"
        report=beginLine
    }
    func observeRequest(magnification:Double,position:TimelineZoom.Position,reference:TimelineZoom){
        guard Self.enabled else{return}
        // Fixed-size numeric storage only; no per-frame published log/string.
        request=Request(magnification:magnification,position:position,frozenAnchorX:reference.anchorX,frozenAnchorBars:reference.anchorBars)
    }
    func finish(viewportWidth:Double,offset:Double,contentWidth:Double,barCount:Int){
        guard Self.enabled,let request else{return}
        requestLine="REQUEST id=\(sequence) magnification=\(request.magnification) width=\(request.position.barWidth) offset=\(request.position.offset) frozenAnchorX=\(request.frozenAnchorX) frozenAnchorBars=\(request.frozenAnchorBars)"
        awaitingAck=true;report=beginLine+"\n"+requestLine
        acknowledge(viewportWidth:viewportWidth,offset:offset,contentWidth:contentWidth,barCount:barCount)
    }
    func acknowledge(viewportWidth:Double,offset:Double,contentWidth:Double,barCount:Int){
        guard Self.enabled,awaitingAck,let request,
              abs(contentWidth-Double(barCount)*request.position.barWidth)<1,
              abs(offset-request.position.offset)<=0.5 else{return}
        awaitingAck=false
        report=beginLine+"\n"+requestLine+"\nACK id=\(sequence) viewportWidth=\(viewportWidth) offset=\(offset) contentWidth=\(contentWidth)"
    }
}
private struct GridZoomDiagnosticValue:ViewModifier {
    @ViewBuilder func body(content:Content)->some View {
        if GridZoomDiagnostics.enabled {
            // A leaf StaticText keeps its own AX value; the timeline container
            // can lose that value when hosting native clip controls.
            content.accessibilityIdentifier("grid.zoom-diagnostics")
                .accessibilityValue(Text(verbatim:GridZoomDiagnostics.shared.report))
        }else{content}
    }
}

struct ChordSelection: Identifiable {let id: UUID;let patternID: UUID;let tick: Int;let chord: Chord;var duration: Int = barTicks}
struct GridView: View {
    @Bindable var session: Session
    @Environment(\.dynamicTypeSize) private var dynamicType
    @AppStorage("studio.pitchSpelling") private var pitchSpelling="automatic"
    @AppStorage("studio.showDegrees") private var showDegrees=false
    @State private var barWidth: CGFloat = 96
    /// U48: a double tap on a section chip renames it.
    @State private var renamingSection: UUID?
    /// The last chip tap: a second tap on the same section soon after is a double tap.
    @State private var lastChipTap: (id: UUID, time: Date)?
    /// U59: stronger contrast for the grid.
    @AppStorage("studio.gridContrast") private var gridContrast = false
    @State private var renameText = ""
    @State private var selection: ChordSelection?
    @State private var dragStart: Int?
    @State private var viewport=CGSize(width:440,height:630)
    @State private var zoomed=false
    @State private var timelinePosition=ScrollPosition(edge:.leading)
    @State private var timelineGeometry=TimelineGeometry()
    @State private var pinchReference:TimelineZoom?
    @State private var pendingZoom:TimelineZoom.Position?
    @GestureState private var pinchActive=false
    @State private var clipMode=ProcessInfo.processInfo.arguments.contains("--arrangement-clips")
    @State private var copyOnDrag=false
    @State private var clipSnap=barTicks
    @State private var clipSelection:ClipEditorSelection?
    @State private var pendingClipEditor:ClipEditorSelection?
    @State private var showClipList=false
    @State private var pendingClipInspector:ClipEditorSelection?
    @State private var targetTrack:UUID?
    @State private var resizeDraft:ClipResizeDraft?
    /// U31 · "Select": taps add clips (or a section's clips) to a batch for one action.
    @State private var selecting=false
    @State private var picked:Set<UUID>=[]
    private struct ClipResizeDraft {let payload:ArrangementDragPayload;let originalLength:Int;var length:Int;let start:Int}
    private struct TimelineGeometry:Equatable {
        var offset:CGFloat=0
        var viewportWidth:CGFloat=0
        var contentWidth:CGFloat=0
    }
    private let gutter:CGFloat=56
    @Environment(\.studioDensity) private var density
    /// U15: VoiceOver users get the song as a table above the grid.
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverOn
    /// U39: compact lanes are a little lower, large ones a little taller.
    private var laneScale:CGFloat{min(1.35,max(0.78,(viewport.height-155)/324))*(1+(CGFloat(density.spacing)-1)/2)}
    private var harmonyHeight:CGFloat{132*laneScale}
    private var drumHeight:CGFloat{100*laneScale}
    private var bassHeight:CGFloat{92*laneScale}
    private var melodyHeight:CGFloat{64*(1+(CGFloat(density.spacing)-1)/2)}
    private var showsRootBassLane: Bool {
        let tracks = session.displayProject.tracks
        return tracks.contains { $0.role == .bass } || !tracks.contains { $0.role == .melody }
    }
    private var musicHeight:CGFloat{harmonyHeight+drumHeight+(showsRootBassLane ? bassHeight : 0)+CGFloat(session.displayProject.tracks.filter{$0.role == .melody}.count)*melodyHeight}
    private var editingLocked:Bool{session.performance.contextActive || session.recording || session.armed || pinchReference != nil}
    private var hasMusicalEvents:Bool {
        session.displayProject.patterns.contains{!$0.chords.isEmpty || !$0.drums.isEmpty || !($0.notes ?? []).isEmpty}
    }
    private var timelineBars:Int {
        let base=session.displayProject.length/barTicks
        let resized=resizeDraft.map{($0.start+$0.length+barTicks-1)/barTicks} ?? 0
        return clipMode ? min(64,max(base+4,resized)):base
    }
    var body: some View {
        gridBody.contrast(gridContrast ? 1.35 : 1).saturation(gridContrast ? 1.15 : 1).renameAlert("Rename section",item:$renamingSection,text:$renameText,limit:120){id,name in
            session.edit{p in if let i=p.sections.firstIndex(where:{$0.id==id}){p.sections[i].name=name}}
        }
    }
    private var gridBody: some View {
        GeometryReader{geometry in
            VStack(spacing:0){
                ScrollView(.vertical,showsIndicators:false){
                    VStack(alignment:.leading,spacing:0){
                        arrangementHeader
                        sectionChips
                        if !hasMusicalEvents{emptyProjectGuide.padding(.horizontal,16).padding(.bottom,14)}
                        else{NextStepCard(session:session).padding(.horizontal,16).padding(.bottom,10)}
                        CoachTipBanner(tips:[.pinchGrid,.renameSection,.undoHistory]).padding(.horizontal,16).padding(.bottom,10)
                        if voiceOverOn || ProcessInfo.processInfo.arguments.contains("--voiceover-table"){GridAccessibleTable(session:session).padding(.horizontal,16).padding(.bottom,10)}
                        if clipMode{clipControls.padding(.horizontal,16).padding(.bottom,8)}
                        HStack(spacing:0){
                            VStack(spacing:0){Color.ink.frame(height:28);trackLabel(.harmony,height:harmonyHeight);trackLabel(.drums,height:drumHeight);if showsRootBassLane { trackLabel(.bass,height:bassHeight) };ForEach(session.displayProject.tracks.filter{$0.role == .melody}){track in melodyTrackLabel(track)}}.frame(width:gutter)
                            ScrollView(.horizontal,showsIndicators:true){ZStack(alignment:.topLeading){
                                timeline
                                GridPlayhead(audio:session.audio,barWidth:barWidth,height:musicHeight)
                            }.frame(width:CGFloat(timelineBars)*barWidth)}
                                .scrollPosition($timelinePosition)
                                .onScrollGeometryChange(for:TimelineGeometry.self){geometry in
                                    TimelineGeometry(offset:geometry.contentOffset.x+geometry.contentInsets.leading,viewportWidth:geometry.containerSize.width,contentWidth:geometry.contentSize.width)
                                }action:{_,geometry in observeTimeline(geometry)}
                                .onScrollPhaseChange{_,phase in
                                    if pinchReference==nil,phase == .interacting{pendingZoom=nil}
                                }
                                .simultaneousGesture(MagnifyGesture().updating($pinchActive){_,active,_ in active=true}.onChanged{value in
                                    zoomTimeline(magnification:value.magnification,anchor:value.startAnchor.x)
                                }.onEnded{_ in
                                    GridZoomDiagnostics.shared.finish(viewportWidth:Double(timelineGeometry.viewportWidth),offset:Double(timelineGeometry.offset),contentWidth:Double(timelineGeometry.contentWidth),barCount:timelineBars)
                                    pinchReference=nil
                                })
                                .onChange(of:pinchActive){_,active in if !active{pinchReference=nil}}
                                .accessibilityIdentifier("grid.timeline")
                        }
                    }
                }
                // Musician feedback: while two fingers zoom the timeline the page must not drift
                // vertically. Zoom positions the timeline programmatically, so user scrolling
                // can pause for the gesture.
                .scrollDisabled(pinchActive || pinchReference != nil)
                tools.padding(.horizontal,12).padding(.vertical,7)
            }.onAppear{configureViewport(geometry.size)}.onChange(of:geometry.size){_,size in cancelTimelineGesture();configureViewport(size)}.onChange(of:session.project.id){_,_ in
                cancelTimelineGesture();zoomed=false;timelinePosition.scrollTo(edge:.leading);configureViewport(geometry.size)
            }.onChange(of:session.displayProject.length){_,_ in cancelTimelineGesture();configureViewport(geometry.size)}.onChange(of:clipMode){_,mode in cancelTimelineGesture();if !mode{selecting=false;picked=[]}}
            .onChange(of:session.project.revision){_,_ in let existing=Set(session.project.tracks.flatMap(\.clips).map(\.id));picked.formIntersection(existing)}
        }.onChange(of:session.pendingTourChord){_,pending in if pending{openTourChord()}}
        .onAppear{if session.pendingTourChord{openTourChord()}}
        .sheet(item:$selection){selection in ChordEditor(session:session,selection:selection).presentationDetents([.large]).presentationDragIndicator(.visible).presentationBackground(Color.panel)}
            .sheet(item:$clipSelection,onDismiss:openPendingClipEditor){choice in ArrangementClipInspector(session:session,selection:choice){pendingClipEditor=choice;clipSelection=nil}.presentationDragIndicator(.visible).presentationBackground(Color.panel)}
            .sheet(isPresented:$showClipList,onDismiss:{if let choice=pendingClipInspector{pendingClipInspector=nil;clipSelection=choice}}){clipList}
    }
    private var emptyProjectGuide:some View {
        VStack(alignment:.leading,spacing:8){
            Text("No notes yet. Add a chord or play a beat to hear your idea.").font(.callout).foregroundStyle(Color.muted).accessibilityIdentifier("grid.empty-state")
            Button {
                session.openTrackBuilder()
            } label: {
                Label("New track from a description", systemImage: "music.note.list")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(StudioActionStyle()).accessibilityIdentifier("grid.new-from-description")
            HStack(spacing:10){
                Button{addFirstChord()}label:{Label("Add first chord",systemImage:"plus").frame(maxWidth:.infinity,minHeight:44)}.accessibilityIdentifier("grid.empty-chord")
                Button{session.tab=1}label:{Label("Play a beat",systemImage:"square.grid.2x2.fill").frame(maxWidth:.infinity,minHeight:44)}.accessibilityIdentifier("grid.empty-jam")
            }.buttonStyle(StudioQuietButtonStyle()).font(.subheadline.weight(.medium)).foregroundStyle(Color.mint)
            Button{session.presentEditor(.chordImport)}label:{Label("Chords from a song or photo",systemImage:"camera.viewfinder").frame(maxWidth:.infinity,minHeight:44)}
                .buttonStyle(StudioQuietButtonStyle()).font(.subheadline.weight(.medium)).foregroundStyle(Color.mint).accessibilityIdentifier("grid.empty-chord-import")
        }.padding(12).modifier(StudioSurface()).disabled(editingLocked)
    }
    /// U11 · The tour asked for a chord: open it once Grid has settled on screen.
    private func openTourChord(){
        session.pendingTourChord=false
        DispatchQueue.main.asyncAfter(deadline:.now()+0.35){openFirstChord()}
    }
    /// U11 · "Show me" on the chord step opens the first chord of this section.
    private func openFirstChord(){
        guard let track=session.project.tracks.first(where:{$0.role == .harmony}),
              let clip=track.clips.first(where:{$0.start<session.section.start+session.section.length && $0.start+$0.length>session.section.start}) ?? track.clips.first,
              let pattern=session.project.patterns.first(where:{$0.id==clip.patternID}) else{addFirstChord();return}
        guard let event=pattern.chords.sorted(by:{$0.tick<$1.tick}).first else{addFirstChord();return}
        selection=ChordSelection(id:event.id,patternID:pattern.id,tick:event.tick,chord:event.chord,duration:event.duration)
    }
    private func addFirstChord(){
        guard let track=session.project.tracks.first(where:{$0.role == .harmony}),
              let clip=track.clips.first(where:{$0.start<session.section.start+session.section.length && $0.start+$0.length>session.section.start}),
              let pattern=session.project.patterns.first(where:{$0.id==clip.patternID}) else{return}
        let local=(max(clip.start,session.section.start)-clip.start+clip.offset)%pattern.length
        selection=ChordSelection(id:UUID(),patternID:pattern.id,tick:local,
                                 chord:Chord(root:session.project.keyRoot,quality:session.project.minor ? .minor:.major),
                                 duration:min(barTicks,pattern.length-local))
    }
    private func configureViewport(_ size:CGSize){
        viewport=size
        if !zoomed,size.width>gutter{barWidth=CGFloat(TimelineZoom.clampedWidth(Double((size.width-gutter)/CGFloat(min(4,max(1,session.displayProject.length/barTicks))))))}
    }
    private func cancelTimelineGesture(){
        pinchReference=nil;pendingZoom=nil;resizeDraft=nil
    }
    private func zoomTimeline(magnification:CGFloat,anchor:CGFloat){
        guard timelineGeometry.viewportWidth>0 else{return}
        if pinchReference==nil {
            GridZoomDiagnostics.shared.begin(unitAnchorX:Double(anchor),viewportWidth:Double(timelineGeometry.viewportWidth),offset:Double(timelineGeometry.offset),contentWidth:Double(timelineGeometry.contentWidth),barWidth:Double(barWidth))
            resizeDraft=nil;zoomed=true
            pinchReference=TimelineZoom(barWidth:Double(barWidth),offset:Double(timelineGeometry.offset),viewportWidth:Double(timelineGeometry.viewportWidth),anchorX:Double(anchor*timelineGeometry.viewportWidth),barCount:timelineBars)
        }
        guard let reference=pinchReference,let next=reference.position(magnification:Double(magnification))else{return}
        GridZoomDiagnostics.shared.observeRequest(magnification:Double(magnification),position:next,reference:reference)
        pendingZoom=next
        var transaction=Transaction();transaction.animation=nil
        withTransaction(transaction){barWidth=CGFloat(next.barWidth);timelinePosition.scrollTo(x:CGFloat(next.offset))}
    }
    private func observeTimeline(_ geometry:TimelineGeometry){
        timelineGeometry=geometry
        GridZoomDiagnostics.shared.acknowledge(viewportWidth:Double(geometry.viewportWidth),offset:Double(geometry.offset),contentWidth:Double(geometry.contentWidth),barCount:timelineBars)
        guard let target=pendingZoom,
              abs(geometry.contentWidth-CGFloat(timelineBars)*CGFloat(target.barWidth))<1 else{return}
        // A point request can clamp against the previous, narrower content.
        // Reapply only once layout has acknowledged the target content width.
        if abs(geometry.offset-CGFloat(target.offset))>0.5 {
            timelinePosition.scrollTo(x:CGFloat(target.offset))
        }else{pendingZoom=nil}
    }
    private var arrangementHeader:some View {
        HStack {
            SmallHeading(text:"ARRANGEMENT").modifier(ArrangementDragTraceValue())
            Spacer()
            Text("\(session.displayProject.length/barTicks) bars")
                .font(.system(.caption2, design: .monospaced)).foregroundStyle(Color.muted)
                .modifier(GridZoomDiagnosticValue())
            IconButton(symbol:clipMode ? "pianokeys":"rectangle.3.group",label:clipMode ? "Edit chords":"Arrange clips",color:clipMode ? .mint:.muted){clipMode.toggle()}
                .background(clipMode ? Color.mint.opacity(0.12):Color.clear,in:RoundedRectangle(cornerRadius:StudioMetrics.controlRadius,style:.continuous))
                .accessibilityIdentifier("grid.mode.clips").accessibilityValue(LocalizedStringKey(clipMode ? "Clips":"Chords"))
            Button { session.presentEditor(.sections) } label: {
                ViewThatFits(in: .horizontal) {
                    Label("Song form", systemImage: "rectangle.split.3x1")
                        .font(.caption.weight(.semibold)).fixedSize(horizontal: true, vertical: false)
                    Image(systemName: "rectangle.split.3x1")
                }
                .foregroundStyle(Color.mint)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(StudioQuietButtonStyle())
            .accessibilityLabel("Edit song sections")
                .accessibilityIdentifier("sections.open")
        }.padding(.horizontal,16)
    }
    private var sectionChips:some View {
        ScrollView(.horizontal,showsIndicators:false) {
            HStack(spacing:6) {
                ForEach(session.displayProject.sections){section in sectionChip(section)}
                Button{session.presentEditor(.sections)}label:{Image(systemName:"plus").frame(width:44,height:44).foregroundStyle(Color.muted)}
                    .buttonStyle(StudioQuietButtonStyle())
                // U22: loop only the selected section while working on it.
                Button{session.toggleFocus()}label:{Image(systemName:session.focused ? "scope":"circle.dashed").frame(width:44,height:44).foregroundStyle(session.focused ? Color.mint:Color.muted)}
                    .buttonStyle(StudioQuietButtonStyle()).disabled(editingLocked)
                    .accessibilityLabel(LocalizedStringKey(session.focused ? "Leave focus" : "Focus on this section"))
                    .accessibilityIdentifier("grid.focus")
            }.padding(.horizontal,16)
        }.padding(.bottom,8)
    }
    /// One tap selects the section; a second tap on it within 0.4 s renames it (U48).
    private func chipTapped(_ section:MusicDomain.Section,selected:Bool) {
        if selecting{pickSection(section);return}
        let now=Date()
        if let last=lastChipTap,last.id==section.id,now.timeIntervalSince(last.time)<0.4,!editingLocked {
            lastChipTap=nil;renameText=section.name;renamingSection=section.id;return
        }
        lastChipTap=(section.id,now)
        if !selected{Luz.Haptics.selection()};withAnimation(Luz.Motion.snap){session.select(section)}
    }
    private func sectionChip(_ section:MusicDomain.Section)->some View {
        let selected=session.section.id==section.id
        let tint=SongFormStyle.color(for:section)
        return Button{chipTapped(section,selected:selected)}label:{
            HStack(spacing:8) {
                // Luz: each section keeps its own colour; selection lifts the chip and outlines it.
                RoundedRectangle(cornerRadius:1,style:.continuous).fill(tint.opacity(selected ? 1:0.5)).frame(width:3,height:14)
                    .accessibilityHidden(true)
                Text(section.name).font(.system(.caption, weight: .semibold)).lineLimit(1)
                Text("\(section.start/barTicks+1)–\((section.start+section.length)/barTicks)")
                    .font(.system(.caption2, design: .monospaced)).opacity(selected ? 0.75:0.65)
            }.padding(.horizontal,12).frame(minHeight:44)
                .foregroundStyle(Color.studioText)
                .background(selected ? Color.lifted:Color.panel,in:RoundedRectangle(cornerRadius:Luz.Radius.cell,style:.continuous))
                .overlay{RoundedRectangle(cornerRadius:Luz.Radius.cell,style:.continuous).strokeBorder(selected ? tint:Color.outline.opacity(0.65),lineWidth:selected ? 1.5:0.75)}
        }.buttonStyle(StudioQuietButtonStyle(radius:Luz.Radius.cell)).accessibilityIdentifier("grid.section.\(section.id)")
            .simultaneousGesture(TapGesture(count:2).onEnded{guard !editingLocked else{return};lastChipTap=nil;renameText=section.name;renamingSection=section.id})
            .accessibilityAction(named:Text("Rename")){guard !editingLocked else{return};renameText=section.name;renamingSection=section.id}
            .accessibilityAddTraits(selected ? .isSelected:[])
            .modifier(ArrangementDragSource(payload:editingLocked ? nil:ArrangementDragPayload(project:session.project,sectionID:section.id).encoded()))
            .dropDestination(for:String.self){items,_ in session.reorderSection(drop:items,onto:section.id)}
    }
    @ViewBuilder private var clipControls:some View {
        if selecting{selectionBar}else{clipOptions}
    }
    /// U31 · The action bar for the selected clips: every action is one edit (one Undo).
    private var selectionBar:some View {
        HStack(spacing:4) {
            Text(String(format:NSLocalizedString("%lld selected",comment:"Selected clips"),Int64(picked.count))).font(.system(.caption,weight:.semibold)).monospacedDigit()
                .foregroundStyle(Color.studioText).accessibilityIdentifier("grid.select.count")
            Spacer(minLength:2)
            IconButton(symbol:"plus.square.on.square",label:"Duplicate",color:.mint){batch(.duplicate)}.disabled(picked.isEmpty).accessibilityIdentifier("grid.batch.duplicate")
            Menu{
                Button("One bar earlier",systemImage:"arrow.left"){batch(.move(bars:-1))}.accessibilityIdentifier("grid.batch.move.earlier")
                Button("One bar later",systemImage:"arrow.right"){batch(.move(bars:1))}.accessibilityIdentifier("grid.batch.move.later")
            }label:{Image(systemName:"arrow.left.and.right").font(StudioTypography.icon).frame(width:44,height:44)}
                .disabled(picked.isEmpty).accessibilityLabel("Move").accessibilityIdentifier("grid.batch.move")
            Menu{
                Button("Track colour"){batch(.color(nil))}
                ForEach(0..<ClipEditing.clipColorCount,id:\.self){index in
                    Button{batch(.color(index))}label:{Label(String(format:NSLocalizedString("Colour %lld",comment:"Clip colour"),Int64(index+1)),systemImage:"circle.fill")}
                        .tint(Color.clipPalette[index]).accessibilityIdentifier("grid.batch.color.\(index)")
                }
            }label:{Image(systemName:"paintpalette").font(StudioTypography.icon).frame(width:44,height:44)}
                .disabled(picked.isEmpty).accessibilityLabel("Colour").accessibilityIdentifier("grid.batch.color")
            IconButton(symbol:allPickedMuted ? "speaker.wave.2":"speaker.slash",label:allPickedMuted ? "Unmute":"Mute",color:.mint){batch(.mute(!allPickedMuted))}
                .disabled(picked.isEmpty).accessibilityIdentifier("grid.batch.mute")
            IconButton(symbol:"trash",label:"Delete",color:.record){batch(.delete)}.disabled(picked.isEmpty).accessibilityIdentifier("grid.batch.delete")
            Button("Done"){withAnimation(Luz.Motion.snap){selecting=false;picked=[]}}.font(.system(.caption,weight:.semibold)).frame(minHeight:44)
                .accessibilityIdentifier("grid.select.done")
        }.foregroundStyle(Color.mint)
    }
    private var allPickedMuted:Bool{
        let clips=session.project.tracks.flatMap(\.clips).filter{picked.contains($0.id)}
        return !clips.isEmpty && clips.allSatisfy{$0.muted == true}
    }
    private func batch(_ action:ClipBatchAction){
        guard !editingLocked,!picked.isEmpty else{return}
        let revision=session.project.revision
        session.edit{try ClipEditing.batch(action,ids:picked,in:&$0)}
        guard session.project.revision>revision else{return}
        Luz.Haptics.selection()
        switch action{
        case .delete,.duplicate: picked=[]
        default: break
        }
    }
    /// In select mode a section chip adds the clips that play in that section.
    private func pickSection(_ section:MusicDomain.Section){
        let range=section.start..<(section.start+section.length)
        let ids=session.project.tracks.filter{$0.role != .bass}.flatMap(\.clips).filter{$0.start<range.upperBound && $0.start+$0.length>range.lowerBound}.map(\.id)
        if Set(ids).isSubset(of:picked){picked.subtract(ids)}else{picked.formUnion(ids)}
        Luz.Haptics.selection()
    }
    private var clipOptions:some View {
        HStack(spacing:10) {
            Menu {
                Picker("Clip snap",selection:$clipSnap){Text("1 bar").tag(barTicks);Text("1 beat").tag(ppq);Text("1/16").tag(240)}
                Toggle("Copy on drag",isOn:$copyOnDrag)
                Button("Play whole song"){session.setLoop(enabled:false)}
            } label: {Label(LocalizedStringKey(copyOnDrag ? "Copy clips":"Move clips"),systemImage:copyOnDrag ? "plus.rectangle.on.rectangle":"hand.draw").font(.system(.caption2, weight: .medium)).frame(minHeight:44)}.accessibilityIdentifier("grid.clip.options")
            Spacer(minLength:4)
            Text(LocalizedStringKey(clipSnap==barTicks ? "1 bar":clipSnap==ppq ? "1 beat":"1/16")).font(.system(.caption2, design: .monospaced)).foregroundStyle(Color.muted)
            IconButton(symbol:"list.bullet",label:"Clip list",color:.mint){showClipList=true}.accessibilityIdentifier("grid.clips.list")
            Button{withAnimation(Luz.Motion.snap){selecting=true;picked=[]}}label:{Label("Select",systemImage:"checkmark.circle").font(.system(.caption,weight:.semibold)).frame(minHeight:44)}
                .disabled(editingLocked).accessibilityIdentifier("grid.select")
        }.foregroundStyle(Color.mint)
    }
    private var clipTimeline:some View {
        let project=session.displayProject,notes=Compiler.notes(project)
        return VStack(spacing:0) {
            ruler
            if let track=project.tracks.first(where:{$0.role == .harmony}) {clipLane(track,height:harmonyHeight,notes:notes)}
            if let track=project.tracks.first(where:{$0.role == .drums}) {clipLane(track,height:drumHeight,notes:notes)}
            if showsRootBassLane {
            bassLane.overlay(alignment:.bottomLeading){Text("Root bass follows harmony").font(.system(.caption2)).foregroundStyle(Color.muted).padding(8)}
                .dropDestination(for:String.self){items,_ in
                    guard let track=project.tracks.first(where:{$0.role == .bass}) else{session.message=ClipEditingError.derivedBass.localizedDescription;return false}
                    return dropClip(items,on:track.id,at:.zero)
                }
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
                let tick=max(0,min(songTickLimit-clipSnap,Int(value.location.x/barWidth*CGFloat(barTicks))/clipSnap*clipSnap))
                session.edit{try ClipEditing.create(on:track.id,start:tick,length:barTicks,snap:clipSnap,in:&$0)}
            })
            if targetTrack==track.id {Rectangle().fill(Color.mint.opacity(0.09)).allowsHitTesting(false)}
            ForEach(track.clips){clip in clipBlock(track:track,clip:clip,height:height,notes:rendered)}
        }.frame(width:CGFloat(timelineBars)*barWidth,height:height)
            // The drop host contains distinct clip controls. It must not absorb
            // their accessibility frames into its lane-wide UIKit host view.
            .accessibilityElement(children:.contain)
            .dropDestination(for:String.self,action:{items,point in dropClip(items,on:track.id,at:point)},isTargeted:{targeted in
                ArrangementDragDiagnostics.record("drop targeted track=\(track.id) targeted=\(targeted)")
                if targeted{targetTrack=track.id}else if targetTrack==track.id{targetTrack=nil}
            })
    }
    private func clipBlock(track:Track,clip:Clip,height:CGFloat,notes:[CompiledNote])->some View {
        let draft=resizeDraft?.payload.objectID==clip.id ? resizeDraft:nil
        let visibleLength=draft?.length ?? clip.length
        let width=max(4,CGFloat(visibleLength)/CGFloat(barTicks)*barWidth-6)
        let clipHeight=max(44,height-12)
        let corner=ArrangementClipTouchLayout.resizeCorner(in:CGRect(x:0,y:0,width:width,height:clipHeight))
        return ZStack(alignment:.bottomTrailing) {
            ArrangementClipFace(notes:notes,track:track,clip:clip,width:width,height:clipHeight,resizing:draft != nil,selected:picked.contains(clip.id))
                .background(Color.panel,in:RoundedRectangle(cornerRadius:Luz.Radius.cell,style:.continuous))
                .overlay{if draft == nil{PlayingHighlight(audio:session.audio,range:clip.start..<(clip.start+clip.length),color:Color.track(track.role),fill:false)}}
                .allowsHitTesting(false).accessibilityHidden(true)
            if let corner {
                Image(systemName:"line.3.horizontal").font(.system(.caption2, weight: .semibold)).rotationEffect(.degrees(90)).foregroundStyle(Color.track(track.role))
                    .frame(width:corner.width,height:corner.height)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            ArrangementClipControl(label:track.displayName,value:String(format:NSLocalizedString("%.2f bars",comment:"Clip length"),Double(clip.length)/Double(barTicks)),hint:"\(NSLocalizedString("Clip position",comment:"Song timeline position")): \(MusicalPosition(tick:clip.start).arrangementAccessibilityDescription)",identifier:"grid.clip.\(clip.id)",enabled:!editingLocked,makePayload:{point in
                guard !selecting,!editingLocked,resizeDraft==nil,clipSelection==nil,selection==nil,!showClipList,session.sheet==nil else{
                    ArrangementDragDiagnostics.record("payload rejected locked=\(editingLocked) resizing=\(resizeDraft != nil) inspector=\(clipSelection != nil) chordEditor=\(selection != nil) list=\(showClipList) sheet=\(String(describing:session.sheet))")
                    return nil
                }
                guard let current=session.project.tracks.first(where:{$0.id==track.id})?.clips.first(where:{$0.id==clip.id})else{
                    ArrangementDragDiagnostics.record("payload rejected missing clip=\(clip.id)");return nil
                }
                let offset=max(0,min(current.length-1,Int(point.x/barWidth*CGFloat(barTicks))))
                ArrangementDragDiagnostics.record("payload clip=\(clip.id) revision=\(session.project.revision) anchor=\(point) grabOffset=\(offset) start=\(current.start) length=\(current.length) barWidth=\(barWidth)")
                return ArrangementDragPayload(project:session.project,trackID:track.id,clipID:clip.id,grabOffset:offset).encoded()
            },resize:{state,translation in
                guard !selecting else{return}
                resizeClip(trackID:track.id,clipID:clip.id,state:state,translation:translation)
            },activate:{
                if selecting{
                    if picked.contains(clip.id){picked.remove(clip.id)}else{picked.insert(clip.id)}
                    Luz.Haptics.selection()
                }else{clipSelection=ClipEditorSelection(trackID:track.id,clipID:clip.id)}
            }).frame(width:width,height:clipHeight)
        }.frame(width:width,height:clipHeight)
            .offset(x:CGFloat(clip.start)/CGFloat(barTicks)*barWidth+3,y:6)
            .allowsHitTesting(!editingLocked)
    }
    private func resizeClip(trackID:UUID,clipID:UUID,state:UIGestureRecognizer.State,translation:CGFloat){
        guard !editingLocked,let clip=session.project.tracks.first(where:{$0.id==trackID})?.clips.first(where:{$0.id==clipID})else{resizeDraft=nil;return}
        guard state == .began || state == .changed || state == .ended else{if state == .cancelled || state == .failed{resizeDraft=nil};return}
        if state == .began{resizeDraft=ClipResizeDraft(payload:.init(project:session.project,trackID:trackID,clipID:clipID),originalLength:clip.length,length:clip.length,start:clip.start)}
        // A pinch/rotation can invalidate an unfinished resize. Later changed
        // or ended callbacks from that old pan must not recreate its draft.
        guard var current=resizeDraft,current.payload.objectID==clipID else{return}
        let ticks=Double(current.originalLength)+Double(translation/barWidth)*Double(barTicks)
        let bounded=max(Double(clipSnap),min(Double(songTickLimit-current.start),ticks))
        current.length=(try? ClipEditing.snapped(Int(bounded),step:clipSnap)) ?? clip.length
        if state == .ended {
            resizeDraft=nil;guard current.length != current.originalLength else{return}
            let snap=clipSnap;session.edit{try ClipEditing.resize(current.payload,length:current.length,snap:snap,in:&$0)}
        }else{resizeDraft=current}
    }
    private func dropClip(_ items:[String],on trackID:UUID,at point:CGPoint)->Bool {
        ArrangementDragDiagnostics.record("drop received track=\(trackID) point=\(point) count=\(items.count) locked=\(editingLocked)")
        guard !editingLocked,items.count==1 else{return false}
        do {
            let payload=try ArrangementDragPayload.decode(items[0])
            guard payload.kind == .clip else{throw ClipEditingError.invalidDrag}
            let raw=Double((point.x-3)/barWidth)*Double(barTicks)-Double(payload.grabOffset)
            let tick=max(0,min(songTickLimit,Int(raw)))
            let copy=copyOnDrag,snap=clipSnap
            ArrangementDragDiagnostics.record("drop clip=\(payload.objectID) revision=\(payload.revision)/\(session.project.revision) point=\(point) grabOffset=\(payload.grabOffset) raw=\(raw) bounded=\(tick) snapped=\(String(describing:try? ClipEditing.snapped(tick,step:snap))) copy=\(copy)")
            if !copy,payload.sourceTrackID==trackID,let track=session.project.tracks.first(where:{$0.id==trackID}),let clip=track.clips.first(where:{$0.id==payload.objectID}),try ClipEditing.snapped(tick,step:snap)==clip.start{
                try payload.validate(in:session.project,kind:.clip);ArrangementDragDiagnostics.record("drop result valid-no-op clip=\(payload.objectID)");return true
            }
            var applied=false
            session.edit{project in if copy{try ClipEditing.copy(payload,to:trackID,start:tick,snap:snap,in:&project)}else{try ClipEditing.move(payload,to:trackID,start:tick,snap:snap,in:&project)};applied=true}
            ArrangementDragDiagnostics.record("drop result applied=\(applied) revision=\(session.project.revision) clip=\(payload.objectID)")
            return applied
        } catch {ArrangementDragDiagnostics.record("drop rejected error=\(error.localizedDescription)");session.message=error.localizedDescription;return false}
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
        let position=MusicalPosition(tick:clip.start)
        let length=String(format:NSLocalizedString("%.2f bars",comment:"Clip length"),Double(clip.length)/Double(barTicks))
        return Button {
            pendingClipInspector=ClipEditorSelection(trackID:trackID,clipID:clip.id)
            showClipList=false
        } label:{
            HStack{Text(position.description);Spacer();Text(length).foregroundStyle(Color.muted)}.frame(minHeight:44)
        }.accessibilityIdentifier("grid.clip.list.\(clip.id)")
            .accessibilityLabel(Text("Clip position"))
            .accessibilityValue("\(position.arrangementAccessibilityDescription), \(length)")
    }
    private func nextFreeClipStart(on track:Track)->Int? {
        var start=0
        for clip in track.clips.sorted(by:{$0.start<$1.start}) {
            if start+barTicks<=clip.start{return start}
            let end=clip.start+clip.length
            if end>start{start=((end+clipSnap-1)/clipSnap)*clipSnap}
        }
        return start+barTicks<=songTickLimit ? start:nil
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
                Button("New track from a description") { session.openTrackBuilder() }
                if !showsRootBassLane {
                    Button("+ Add root bass") { session.presentEditor(.bass) }.accessibilityIdentifier("bass.open")
                }
                Button("Harmony lab"){session.presentEditor(.harmony)};Button("Piano roll"){session.openNotes()};Button("Assistant"){session.presentEditor(.assistant)};Button("Voice to MIDI"){session.presentEditor(.voice)};Button("Perform"){session.sheet = .perform};Button("MIDI devices"){session.presentEditor(.midiDevices)}
                Divider()
                Button("Settings",systemImage:"gearshape"){session.presentEditor(.settings)}.accessibilityIdentifier("settings.open")
            }.font(.headline).frame(maxWidth:.infinity,minHeight:44).modifier(StudioSurface())
        }else{
            HStack(spacing:2){
                Button{session.presentEditor(.harmony)}label:{Label("Harmony",systemImage:"wand.and.stars").frame(maxWidth:.infinity,minHeight:44)}.accessibilityLabel("Harmony lab").accessibilityIdentifier("harmony.open")
                Button{session.openNotes()}label:{Label("Notes",systemImage:"pianokeys").frame(maxWidth:.infinity,minHeight:44)}.accessibilityLabel("Open piano roll").accessibilityIdentifier("notes.open")
                Button{session.presentEditor(.assistant)}label:{Label("Assistant",systemImage:"text.bubble").frame(maxWidth:.infinity,minHeight:44)}.accessibilityIdentifier("assistant.open")
                Menu{
                    Button("New track from a description", systemImage:"music.note.list") { session.openTrackBuilder() }
                    if !showsRootBassLane {
                        Button("+ Add root bass", systemImage:"waveform") { session.presentEditor(.bass) }.accessibilityIdentifier("bass.open")
                    }
                    Button("Voice",systemImage:"waveform.badge.mic"){session.presentEditor(.voice)}.accessibilityIdentifier("voice.open")
                    Button("Perform",systemImage:"waveform.path"){session.finishTake();session.sheet = .perform}.accessibilityIdentifier("perform.open")
                    Button("MIDI devices",systemImage:"pianokeys"){session.presentEditor(.midiDevices)}.accessibilityIdentifier("midi.open")
                    Divider()
                    Button("Settings",systemImage:"gearshape"){session.presentEditor(.settings)}.accessibilityIdentifier("settings.open")
                }label:{Image(systemName:"ellipsis.circle").frame(width:44,height:44)}.accessibilityLabel("More studio tools").accessibilityIdentifier("tools.more")
            }.buttonStyle(StudioQuietButtonStyle()).font(.system(.caption2, weight: .medium)).lineLimit(1).minimumScaleFactor(1).foregroundStyle(Color.mint).padding(.horizontal,4).modifier(StudioSurface())
        }
    }
    /// U37 · The kernel's level for the first track of a role (0 when silent).
    private func levelFor(_ role:TrackRole)->Float{
        guard let index=session.displayProject.tracks.firstIndex(where:{$0.role == role}),session.audio.meters.indices.contains(index)else{return 0}
        return session.audio.meters[index]
    }
    func trackLabel(_ role: TrackRole,height: CGFloat)->some View {
        Button{if role == .harmony{session.presentEditor(.harmony)}else if role == .bass {session.presentEditor(.bass)}else if role == .drums{session.tab=1}}
        label:{
            VStack(alignment:.leading,spacing:10){
                Image(systemName:role == .harmony ? "pianokeys":role == .drums ? "square.grid.2x2":"waveform")
                    .font(.system(.subheadline, weight: .medium)).foregroundStyle(Color.track(role))
                Text(LocalizedStringKey(role == .harmony ? "HARM":role == .drums ? "DRUM":"BASS"))
                    .font(.system(.caption2, weight: .semibold)).foregroundStyle(Color.studioText)
            }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.leading)
                .padding(.leading,12).frame(height:height)
                .background(Color.ink)
                .overlay(alignment:.trailing){TrackLevelBar(level:levelFor(role),color:Color.track(role)).padding(.vertical,12)}
                .overlay(alignment:.bottom){Rectangle().fill(Color.outline.opacity(0.4)).frame(height:0.5)}
        }.buttonStyle(StudioQuietButtonStyle()).accessibilityIdentifier(role == .bass ? "bass.open":"grid.track.\(role.rawValue)")
    }
    private func melodyTrackLabel(_ track:Track)->some View {
        Button{session.openNotes(track.id)}label:{
            Text(track.displayName).font(.system(.caption2, weight: .semibold)).lineLimit(2)
                .foregroundStyle(Color.mint).padding(8).frame(width:gutter,height:melodyHeight)
                .background(Color.ink)
                .overlay(alignment:.trailing){TrackLevelBar(level:{let i=session.displayProject.tracks.firstIndex(where:{$0.id==track.id}) ?? -1;return session.audio.meters.indices.contains(i) ? session.audio.meters[i]:0}(),color:Color.mint).padding(.vertical,12)}
                .overlay(alignment:.bottom){Rectangle().fill(Color.outline.opacity(0.4)).frame(height:0.5)}
        }.buttonStyle(StudioQuietButtonStyle())
    }
    @ViewBuilder var timeline: some View {
        if clipMode{clipTimeline}else{VStack(spacing:0) { ruler; harmonyLane; drumLane; if showsRootBassLane { bassLane };ForEach(session.displayProject.tracks.filter{$0.role == .melody}){t in melodyLane(t)} }}
    }
    var ruler: some View {
        HStack(spacing:0) {
            ForEach(0..<timelineBars,id:\.self) { bar in
                Text(String(format:"%02d",bar+1)).font(.system(.caption2, design: .monospaced, weight: .medium))
                    .foregroundStyle(bar<session.displayProject.length/barTicks ? Color.studioText:Color.muted.opacity(0.6)).frame(width:barWidth,alignment:.leading)
                    .overlay(alignment:.bottomLeading){Rectangle().fill(Color.outline).frame(width:1,height:5).offset(y:7)}
                    .accessibilityIdentifier("grid.bar.\(bar)")
            }
        }.frame(height:28).background(Color.ink).overlay(alignment:.bottom){Rectangle().fill(Color.outline.opacity(0.7)).frame(height:0.5)}.overlay(alignment:.topLeading) {
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
        } label: { ChordTile(chord:event?.chord,width:max(8,CGFloat(slice.duration)/CGFloat(barTicks)*barWidth-6),height:harmonyHeight-16,keyRoot:session.displayProject.keyRoot,minor:session.displayProject.minor,spelling:PitchSpelling(rawValue:pitchSpelling) ?? .automatic,showDegrees:showDegrees,audio:session.audio,playRange:slice.timelineTick..<(slice.timelineTick+slice.duration)) }
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
            Button("Change by voice",systemImage:"mic"){session.editByVoice(at:slice.timelineTick)}
            if let event {
                Button("Delete chord",role:.destructive) {
                    session.edit { p in
                        if let i=p.patterns.firstIndex(where:{$0.id==clip.patternID}) { p.patterns[i].chords.removeAll(where:{$0.id==event.id}) }
                    }
                }
            }
        } preview: {
            // U29: touch and hold a chord to hear it for as long as the menu is held open.
            HeldChordPreview(chord:event?.chord,keyRoot:session.displayProject.keyRoot,minor:session.displayProject.minor)
                .onAppear{if let chord=event?.chord{session.previewHold(chord:chord)}}
                .onDisappear{session.endHold()}
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
                Button("+ Add root bass"){session.presentEditor(.bass)}.font(.system(.caption)).foregroundStyle(Color.bass).padding(20)
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
    func gridBackground(height: CGFloat)->some View {
        Canvas{context,size in
            context.fill(Path(CGRect(origin:.zero,size:size)),with:.color(.panel))
            for bar in 0..<timelineBars where bar%2==1 {
                let rect=CGRect(x:CGFloat(bar)*barWidth,y:0,width:barWidth,height:height)
                context.fill(Path(rect),with:.color(.raised.opacity(0.22)))
            }
            for step in 0...timelineBars*4 {
                let x=CGFloat(step)*barWidth/4
                var line=Path();line.move(to:CGPoint(x:x,y:0));line.addLine(to:CGPoint(x:x,y:height))
                let major=step%4==0
                context.stroke(line,with:.color(Color.outline.opacity(major ? 0.65:0.2)),lineWidth:major ? 0.75:0.5)
            }
            var bottom=Path();bottom.move(to:CGPoint(x:0,y:height));bottom.addLine(to:CGPoint(x:size.width,y:height))
            context.stroke(bottom,with:.color(.outline.opacity(0.65)),lineWidth:0.75)
        }
    }
}

/// Keep the drag source and receiver on the same native Transferable contract.
/// Locked clips retain tap/launch behavior without exporting an empty provider.
struct ArrangementDragSource:ViewModifier {
    let payload:String?
    @ViewBuilder func body(content:Content)->some View {
        if let payload{content.draggable(payload)}else{content}
    }
}

struct ChordTile: View {
    let chord: Chord?
    let width: CGFloat
    let height:CGFloat
    let keyRoot:Int
    let minor:Bool
    let spelling:PitchSpelling
    let showDegrees:Bool
    /// Luz: the chord under the playhead lights up in amber (read in a tiny view).
    var audio:AudioController?=nil
    var playRange:Range<Int>?=nil
    @Environment(\.colorSchemeContrast) private var contrast
    private var inset:CGFloat{width<64 ? 8:12}
    private var symbol:String{chord.map{MusicalNotation.chordSymbol($0,keyRoot:keyRoot,minor:minor,spelling:spelling)} ?? "+"}
    var body: some View {
        VStack(alignment:.leading,spacing:showDegrees ? 6:13) {
            HStack {
                Text(symbol).font(.system(size:25,weight:.semibold)).tracking(-0.6)
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .foregroundStyle(chord == nil ? Color.harmony:Color.studioText)
                Spacer(minLength:0)
            }
            if let chord {
                if showDegrees{Text(MusicalNotation.degreeSymbol(chord,keyRoot:keyRoot,minor:minor)).font(.caption.weight(.medium)).foregroundStyle(Color.harmony).lineLimit(1).accessibilityIdentifier("grid.chord-degree")}
                let notes: [Int] = chord.notes
                let spacing: CGFloat = width < 64 ? 1 : 3
                let gapCount: Int = max(0, notes.count - 1)
                let gapsWidth: CGFloat = CGFloat(gapCount) * spacing
                let availableWidth: CGFloat = width - inset*2 - gapsWidth
                let noteCount: CGFloat = CGFloat(max(1, notes.count))
                let noteWidth: CGFloat = max(2, availableWidth / noteCount)
                HStack(spacing: spacing) {
                    ForEach(Array(notes.enumerated()),id:\.offset) { _,note in
                        let noteOffset: CGFloat = CGFloat(72 - note) / 4
                        RoundedRectangle(cornerRadius:1,style:.continuous).fill(Color.harmony.opacity(0.75))
                            .frame(width: noteWidth, height: 3)
                            .offset(y: noteOffset)
                    }
                }
                if !showDegrees || height>=112{Text(chord.customIntervals == nil ? chord.quality.label:NSLocalizedString("Custom chord",comment:"Chord formula label"))
                    .font(.system(.caption2, weight: .medium)).lineLimit(1).foregroundStyle(Color.harmony)
                }
            }
        }.padding(inset).frame(width:width,height:height,alignment:.topLeading)
            .background{
                RoundedRectangle(cornerRadius:Luz.Radius.cell,style:.continuous).fill(Color.panel)
                    .overlay{
                        RoundedRectangle(cornerRadius:Luz.Radius.cell,style:.continuous).fill(
                            LinearGradient(colors:[Color.harmony.opacity(chord == nil ? 0.03:0.13),Color.harmony.opacity(chord == nil ? 0.01:0.04)],startPoint:.topLeading,endPoint:.bottomTrailing)
                        )
                    }
            }
            .overlay(alignment:.topLeading){
                RoundedRectangle(cornerRadius:1,style:.continuous).fill(Color.harmony.opacity(chord == nil ? 0.25:0.8))
                    .frame(width:max(0,min(24,width-inset*2)),height:2).padding(.leading,inset).padding(.top,0.5)
            }
            .overlay{RoundedRectangle(cornerRadius:Luz.Radius.cell,style:.continuous).strokeBorder(Color.harmony.opacity(chord == nil ? 0.2:0.4),lineWidth:0.75)}
            .overlay{if let audio,let playRange{PlayingHighlight(audio:audio,range:playRange,color:.harmony)}}
            .clipShape(RoundedRectangle(cornerRadius:Luz.Radius.cell,style:.continuous))
    }
}

/// U45 · One quiet suggestion for the next step; "Not now" hides it for this song.
struct NextStepCard: View {
    @Bindable var session: Session
    @AppStorage("nextStep.hidden") private var hiddenRaw = ""
    @AppStorage("nextStep.off") private var off = false
    var body: some View {
        let key = session.project.id.uuidString
        // UI tests check other screens; the hint shows there only when asked for.
        let allowed = !Luz.uiTesting || ProcessInfo.processInfo.arguments.contains("--next-step")
        if allowed, !off, !session.performance.contextActive, !session.recording, !hiddenRaw.contains(key), let step = NextStepAdvisor.suggest(session.project) {
            HStack(spacing: 10) {
                Image(systemName: "lightbulb").foregroundStyle(Color.mint).accessibilityHidden(true)
                Text(LocalizedStringKey(step.message)).font(.caption).foregroundStyle(Color.studioText).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button { session.run(step.command) } label: { Text("Go").font(.caption.weight(.semibold)).padding(.horizontal, 10).frame(minHeight: 44) }
                    .buttonStyle(StudioActionStyle(color: .mint, prominent: true)).fixedSize().accessibilityIdentifier("next-step.go")
                Menu {
                    Button("Not now") { hiddenRaw = String((hiddenRaw + "," + key).suffix(4000)) }
                    Button("Stop suggesting") { off = true }
                } label: { Image(systemName: "xmark").font(.caption).foregroundStyle(Color.muted).frame(width: 44, height: 44) }
                    .accessibilityLabel("Hide the suggestion")
            }
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(Color.panel, in: RoundedRectangle(cornerRadius: Luz.Radius.card, style: .continuous))
            .accessibilityElement(children: .contain).accessibilityIdentifier("next-step")
        }
    }
}

/// U29 · The lifted chord while it sounds: its symbol and notes.
private struct HeldChordPreview: View {
    let chord: Chord?
    let keyRoot: Int
    let minor: Bool
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "speaker.wave.2.fill").foregroundStyle(Color.harmony).accessibilityHidden(true)
            if let chord {
                Text(verbatim: MusicalNotation.chordSymbol(chord, keyRoot: keyRoot, minor: minor)).font(.title.weight(.semibold))
                Text(verbatim: MusicalNotation.chordNoteNames(chord, keyRoot: keyRoot, minor: minor).joined(separator: " · ")).font(.caption.monospaced()).foregroundStyle(Color.muted)
            } else {
                Text("Empty bar").font(.headline)
            }
        }
        .padding(20).frame(minWidth: 160).background(Color.panel)
    }
}

/// U37 · A thin level meter at the edge of a track header: the track colour fills from the bottom
/// with the kernel's level; at rest it is the faint track line.
struct TrackLevelBar: View {
    let level: Float
    let color: Color
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                Rectangle().fill(color.opacity(0.35))
                Rectangle().fill(color).frame(height: geometry.size.height * CGFloat(min(1, max(0, level.squareRoot()))))
            }
        }
        .frame(width: 3)
        .accessibilityElement()
        .accessibilityLabel(Text("Level"))
        .accessibilityValue(Text(level > 0.01 ? "Playing" : "Silent"))
        .accessibilityIdentifier("grid.level")
    }
}

/// U15 · The song as a table for VoiceOver: a row per bar, read as "Bar 3, Verse. Harmony: Am.
/// Drums: 12 hits." A "Bars" rotor jumps between rows; activating a row selects its section and
/// moves the playhead to the bar. Shown while VoiceOver runs (and in UI tests on request).
struct GridAccessibleTable: View {
    @Bindable var session: Session
    @Namespace private var rotor
    var body: some View {
        let rows = AccessibleGridTable.rows(session.displayProject) { MusicalNotation.chordSymbol($0, keyRoot: session.displayProject.keyRoot, minor: session.displayProject.minor) }
        VStack(alignment: .leading, spacing: 2) {
            Text("SONG TABLE").font(.caption.weight(.semibold)).tracking(1.1).foregroundStyle(Color.muted).accessibilityAddTraits(.isHeader)
            ForEach(rows) { row in
                Button {
                    let tick = (row.bar - 1) * barTicks
                    if let section = session.project.sections.first(where: { $0.start <= tick && tick < $0.start + $0.length }) { session.select(section) }
                    session.audio.seek(tick)
                } label: {
                    Text(verbatim: row.label).font(.caption).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(StudioQuietButtonStyle(plate: false))
                .accessibilityRotorEntry(id: row.bar, in: rotor)
                .accessibilityIdentifier("grid.table.row.\(row.bar)")
            }
        }
        .padding(10)
        .background(Color.panel, in: RoundedRectangle(cornerRadius: Luz.Radius.card, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityRotor("Bars") {
            ForEach(rows) { row in AccessibilityRotorEntry(Text(verbatim: row.label), id: row.bar, in: rotor) }
        }
        .accessibilityIdentifier("grid.table")
    }
}
