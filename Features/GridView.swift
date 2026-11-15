import SwiftUI
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
    private let gutter:CGFloat=56
    private var laneScale:CGFloat{min(1.35,max(0.78,(viewport.height-155)/324))}
    private var harmonyHeight:CGFloat{132*laneScale}
    private var drumHeight:CGFloat{100*laneScale}
    private var bassHeight:CGFloat{92*laneScale}
    private var melodyHeight:CGFloat{64}
    private var musicHeight:CGFloat{harmonyHeight+drumHeight+bassHeight+CGFloat(session.displayProject.tracks.filter{$0.role == .melody}.count)*melodyHeight}
    var body: some View {
        GeometryReader{geometry in
            VStack(spacing:0){
                ScrollView(.vertical,showsIndicators:false){
                    VStack(alignment:.leading,spacing:0){
                        HStack{SmallHeading(text:"ARRANGEMENT");Spacer();Text("\(session.displayProject.length/barTicks) bars").font(.system(size:10,design:.monospaced)).foregroundStyle(Color.muted);IconButton(symbol:"ellipsis",label:"Edit song sections",color:.muted){session.presentEditor(.sections)}}.padding(.horizontal,16)
                        ScrollView(.horizontal,showsIndicators:false){HStack(spacing:6){ForEach(session.displayProject.sections){section in
                            Button{session.select(section)}label:{HStack(spacing:6){Text(section.name).font(.system(size:12,weight:.semibold));Text("\(section.start/barTicks+1)–\((section.start+section.length)/barTicks)").font(.system(size:9,design:.monospaced)).opacity(0.7)}.padding(.horizontal,14).frame(minHeight:44).foregroundStyle(session.section.id==section.id ? Color.ink:Color.studioText).background(session.section.id==section.id ? Color.mint:Color.panel,in:Capsule())}.buttonStyle(.plain)
                        };Button{session.presentEditor(.sections)}label:{Image(systemName:"plus").frame(width:44,height:44).foregroundStyle(Color.muted)}.buttonStyle(.plain)}.padding(.horizontal,16)}.padding(.bottom,8)
                        HStack(spacing:0){
                            VStack(spacing:0){Color.clear.frame(height:28);trackLabel(.harmony,height:harmonyHeight);trackLabel(.drums,height:drumHeight);trackLabel(.bass,height:bassHeight);ForEach(session.displayProject.tracks.filter{$0.role == .melody}){track in Button{session.openNotes(track.id)}label:{Text(track.displayName).font(.system(size:9,weight:.semibold)).lineLimit(2).foregroundStyle(Color.mint).padding(8).frame(width:gutter,height:melodyHeight)}.buttonStyle(.plain)}}.frame(width:gutter)
                            ScrollView(.horizontal,showsIndicators:true){ZStack(alignment:.topLeading){
                                timeline
                                Rectangle().fill(Color.mint).frame(width:2,height:musicHeight).offset(x:CGFloat(session.audio.tick)/CGFloat(barTicks)*barWidth,y:28).allowsHitTesting(false)
                                Image(systemName:"triangle.fill").font(.system(size:9)).rotationEffect(.degrees(180)).foregroundStyle(Color.mint).offset(x:CGFloat(session.audio.tick)/CGFloat(barTicks)*barWidth-4,y:18).allowsHitTesting(false)
                            }.frame(width:CGFloat(session.displayProject.length/barTicks)*barWidth).gesture(MagnifyGesture().onChanged{value in zoomed=true;barWidth=min(640,max(68,zoomBase*value.magnification))}.onEnded{_ in zoomBase=barWidth})}
                        }
                    }
                }
                tools.padding(.horizontal,12).padding(.vertical,7)
            }.onAppear{configureViewport(geometry.size)}.onChange(of:geometry.size){_,size in configureViewport(size)}
        }.sheet(item:$selection){selection in ChordEditor(session:session,selection:selection).presentationDetents([.large]).presentationDragIndicator(.visible).presentationBackground(Color.panel)}
    }
    private func configureViewport(_ size:CGSize){
        viewport=size
        if !zoomed,size.width>gutter{barWidth=max(68,(size.width-gutter)/CGFloat(min(4,max(1,session.displayProject.length/barTicks))));zoomBase=barWidth}
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
            }.buttonStyle(.plain).font(.system(size:11,weight:.medium)).lineLimit(1).minimumScaleFactor(0.8).foregroundStyle(Color.mint).padding(.horizontal,4).modifier(StudioSurface())
        }
    }
    func trackLabel(_ role: TrackRole,height: CGFloat)->some View {
        Button{if role == .harmony{session.presentEditor(.harmony)}else if role == .bass {session.presentEditor(.bass)}else if role == .drums{session.tab=1}}
        label:{VStack(alignment:.leading,spacing:9){RoundedRectangle(cornerRadius:2).fill(Color.track(role)).frame(width:18,height:3);Text(LocalizedStringKey(role == .harmony ? "HARM":role == .drums ? "DRUM":"BASS")).font(.system(size:9,weight:.semibold));Image(systemName:role == .harmony ? "pianokeys":role == .drums ? "square.grid.2x2":"waveform").font(.system(size:14)).foregroundStyle(Color.track(role))}.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.leading).padding(.leading,12).frame(height:height).background(Color.panel.opacity(0.6)).overlay(alignment:.bottom){Rectangle().fill(Color.raised).frame(height:1)}}.buttonStyle(.plain)
    }
    var timeline: some View {
        VStack(spacing:0) { ruler; harmonyLane; drumLane; bassLane;ForEach(session.displayProject.tracks.filter{$0.role == .melody}){t in melodyLane(t)} }
    }
    var ruler: some View {
        HStack(spacing:0) {
            ForEach(0..<session.displayProject.length/barTicks,id:\.self) { bar in
                Text(String(format:"%02d",bar+1)).font(.system(size:10,weight:.medium,design:.monospaced))
                    .foregroundStyle(Color.muted).frame(width:barWidth,alignment:.leading)
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
                        ForEach(0..<pattern.length/barTicks,id:\.self) { bar in
                            if !pattern.chords.contains(where:{$0.tick < (bar+1)*barTicks && $0.tick+$0.duration > bar*barTicks}) {
                                chordCell(clip:clip,pattern:pattern,event:nil,tick:bar*barTicks)
                            }
                        }
                        ForEach(pattern.chords) { event in
                            chordCell(clip:clip,pattern:pattern,event:event,tick:event.tick)
                        }
                    }
                }
            }
        }.frame(height:harmonyHeight)
    }
    func chordCell(clip:Clip,pattern:Pattern,event:ChordEvent?,tick:Int)->some View {
        return Button {
            selection=ChordSelection(id:event?.id ?? UUID(),patternID:pattern.id,
                tick:tick,
                chord:event?.chord ?? Chord(root:session.displayProject.keyRoot,quality:session.displayProject.minor ? .minor:.major),
                duration:event?.duration ?? barTicks)
        } label: { ChordTile(chord:event?.chord,width:max(44,CGFloat(event?.duration ?? barTicks)/CGFloat(barTicks)*barWidth-6),height:harmonyHeight-16) }
        .buttonStyle(.plain).disabled(session.performance.contextActive).offset(x:CGFloat(clip.start+tick)/CGFloat(barTicks)*barWidth+3,y:8)
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
    func gridBackground(height: CGFloat)->some View {Canvas{context,size in for step in 0...session.displayProject.length/ppq {let x=CGFloat(step)*barWidth/4;var p=Path();p.move(to:CGPoint(x:x,y:0));p.addLine(to:CGPoint(x:x,y:height));context.stroke(p,with:.color(Color.raised.opacity(step%4==0 ? 1:0.4)),lineWidth:1)};var line=Path();line.move(to:CGPoint(x:0,y:height));line.addLine(to:CGPoint(x:size.width,y:height));context.stroke(line,with:.color(.raised),lineWidth:1)}}
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
                Text(chord.quality.label).font(.system(size:9)).lineLimit(1).minimumScaleFactor(0.5).foregroundStyle(Color.harmony.opacity(0.9))
            }
        }.foregroundStyle(Color.harmony).padding(12).frame(width:width,height:height,alignment:.topLeading)
            .background(Color.harmony.opacity(chord == nil ? 0.04:0.12),in:RoundedRectangle(cornerRadius:10))
            .overlay { RoundedRectangle(cornerRadius:10).stroke(Color.harmony.opacity(0.22),lineWidth:1) }
    }
}
