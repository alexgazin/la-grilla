import SwiftUI
import MusicDomain
struct ChordSelection: Identifiable {let id: UUID;let patternID: UUID;let tick: Int;let chord: Chord;var duration: Int = barTicks}
struct GridView: View {
    @Bindable var session: Session
    @Environment(\.dynamicTypeSize) private var dynamicType
    @State private var barWidth: CGFloat = 112
    @State private var zoomBase: CGFloat = 112
    @State private var selection: ChordSelection?
    @State private var dragStart: Int?
    var body: some View {
        ScrollView(.vertical,showsIndicators:false) {
        VStack(alignment:.leading,spacing:0){
            HStack{SmallHeading(text:"ARRANGEMENT");Spacer();Text("\(session.displayProject.length/barTicks) bars").font(.system(size:11,design:.monospaced)).foregroundStyle(Color.muted);IconButton(symbol:"ellipsis",label:"Edit song sections",color:.muted){session.presentEditor(.sections)}}.padding(.horizontal,18).padding(.top,8)
            if dynamicType.isAccessibilitySize {
                Menu("Studio tools"){
                    Button("Harmony lab"){session.presentEditor(.harmony)};Button("Piano roll"){session.openNotes()};Button("Assistant"){session.presentEditor(.assistant)};Button("Voice to MIDI"){session.presentEditor(.voice)};Button("Perform"){session.sheet = .perform};Button("MIDI devices"){session.presentEditor(.midiDevices)}
                }.font(.headline).frame(minHeight:44).padding(.horizontal,18)
            }else{ScrollView(.horizontal,showsIndicators:false){HStack(spacing:8){
                Button{session.presentEditor(.midiDevices)}label:{Label("MIDI",systemImage:"pianokeys.inverse").frame(minWidth:76,minHeight:44)}.accessibilityIdentifier("midi.open")
                Button{session.finishTake();session.sheet = .perform}label:{Label("Perform",systemImage:"waveform.path").frame(minWidth:90,minHeight:44)}.accessibilityIdentifier("perform.open")
                Button{session.presentEditor(.harmony)}label:{Label("Harmony",systemImage:"wand.and.stars").frame(minWidth:92,minHeight:44)}.accessibilityLabel("Harmony lab").accessibilityIdentifier("harmony.open")
                Button{session.openNotes()}label:{Label("Notes",systemImage:"pianokeys").frame(minWidth:80,minHeight:44)}.accessibilityLabel("Open piano roll").accessibilityIdentifier("notes.open")
                Button{session.presentEditor(.assistant)}label:{Label("Assistant",systemImage:"text.bubble").frame(minWidth:96,minHeight:44)}.accessibilityIdentifier("assistant.open")
                Button{session.presentEditor(.voice)}label:{Label("Voice",systemImage:"waveform.badge.mic").frame(minWidth:76,minHeight:44)}.accessibilityIdentifier("voice.open")
            }}.font(.system(size:12,weight:.medium)).foregroundStyle(Color.mint).padding(.horizontal,18).padding(.bottom,10)}
            ScrollView(.horizontal,showsIndicators:false){HStack(spacing:8){ForEach(session.displayProject.sections){s in Button{session.select(s)}label:{HStack(spacing:8){RoundedRectangle(cornerRadius:1).fill(session.section.id==s.id ? Color.mint:Color.muted).frame(width:3,height:20);VStack(alignment:.leading,spacing:3){Text(s.name).font(.system(size:12,weight:.semibold));Text("\(s.start/barTicks+1)–\((s.start+s.length)/barTicks)").font(.system(size:9,design:.monospaced)).foregroundStyle(Color.muted)}}.padding(.horizontal,12).padding(.vertical,10).background(session.section.id==s.id ? Color.raised:Color.panel,in:RoundedRectangle(cornerRadius:8)).overlay{RoundedRectangle(cornerRadius:8).stroke(session.section.id==s.id ? Color.mint.opacity(0.4):Color.clear,lineWidth:1)}}.buttonStyle(.plain)}
                Button{session.presentEditor(.sections)}label:{Image(systemName:"plus").frame(width:44,height:48).foregroundStyle(Color.muted)}
            }.padding(.horizontal,18)}.padding(.bottom,18)
            HStack(spacing:0){
                VStack(spacing:0){Color.clear.frame(height:34);trackLabel(.harmony,height:132);trackLabel(.drums,height:100);trackLabel(.bass,height:92);ForEach(session.displayProject.tracks.filter{$0.role == .melody}){t in Button{session.openNotes(t.id)}label:{Text(t.displayName).font(.system(size:9,weight:.semibold)).lineLimit(2).foregroundStyle(Color.mint).padding(8).frame(width:68,height:76).background(Color.panel)}.buttonStyle(.plain)}}.frame(width:68)
                ScrollView(.horizontal,showsIndicators:true){ZStack(alignment:.topLeading){
                    timeline
                    Rectangle().fill(Color.mint).frame(width:1.5,height:CGFloat(324+session.displayProject.tracks.filter{$0.role == .melody}.count*76)).offset(x:CGFloat(session.audio.tick)/CGFloat(barTicks)*barWidth,y:34).allowsHitTesting(false)
                    Image(systemName:"triangle.fill").font(.system(size:9)).rotationEffect(.degrees(180)).foregroundStyle(Color.mint).offset(x:CGFloat(session.audio.tick)/CGFloat(barTicks)*barWidth-4,y:23).allowsHitTesting(false)
                }.frame(width:CGFloat(session.displayProject.length/barTicks)*barWidth).gesture(MagnifyGesture().onChanged{value in barWidth=min(640,max(68,zoomBase*value.magnification))}.onEnded{_ in zoomBase=barWidth})}
            }
            HStack{Image(systemName:"hand.pinch");Text("Pinch to zoom");Spacer();Text("SNAP  1/16").fontDesign(.monospaced)}.font(.system(size:9)).foregroundStyle(Color.muted).padding(.horizontal,18).padding(.top,14)
            Spacer(minLength:14)
            HStack(alignment:.top,spacing:12){Image(systemName:"pianokeys").foregroundStyle(Color.harmony).font(.system(size:23));VStack(alignment:.leading,spacing:5){Text("Make room for an idea.").font(.system(size:15,weight:.medium));Text("Tap a chord to shape your harmony.\nThen find its rhythm in Jam.").font(.system(size:12)).foregroundStyle(Color.muted).lineSpacing(3)};Spacer()}.padding(18).background(Color.panel,in:RoundedRectangle(cornerRadius:12)).padding(.horizontal,18).padding(.bottom,18)
        }
        }.sheet(item:$selection){s in ChordEditor(session:session,selection:s).presentationDetents([.large]).presentationDragIndicator(.visible).presentationBackground(Color.panel)}
    }
    func trackLabel(_ role: TrackRole,height: CGFloat)->some View {
        Button{if role == .harmony{session.presentEditor(.harmony)}else if role == .bass {session.presentEditor(.bass)}else if role == .drums{session.tab=1}}
        label:{VStack(alignment:.leading,spacing:9){RoundedRectangle(cornerRadius:2).fill(Color.track(role)).frame(width:18,height:3);Text(LocalizedStringKey(role == .harmony ? "HARM":role == .drums ? "DRUM":"BASS")).font(.system(size:9,weight:.semibold));Image(systemName:role == .harmony ? "pianokeys":role == .drums ? "square.grid.2x2":"waveform").font(.system(size:14)).foregroundStyle(Color.track(role))}.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.leading).padding(.leading,16).frame(height:height).background(Color.panel.opacity(0.6)).overlay(alignment:.bottom){Rectangle().fill(Color.raised).frame(height:1)}}.buttonStyle(.plain)
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
        }.frame(height:34).overlay(alignment:.topLeading) {
            Rectangle().fill(Color.mint.opacity(0.6))
                .frame(width:CGFloat(session.loopRange.count)/CGFloat(barTicks)*barWidth,height:2)
                .offset(x:CGFloat(session.loopRange.lowerBound)/CGFloat(barTicks)*barWidth)
        }
    }
    var harmonyLane: some View {
        ZStack(alignment:.topLeading) {
            gridBackground(height:132)
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
        }.frame(height:132)
    }
    func chordCell(clip:Clip,pattern:Pattern,event:ChordEvent?,tick:Int)->some View {
        return Button {
            selection=ChordSelection(id:event?.id ?? UUID(),patternID:pattern.id,
                tick:tick,
                chord:event?.chord ?? Chord(root:session.displayProject.keyRoot,quality:session.displayProject.minor ? .minor:.major),
                duration:event?.duration ?? barTicks)
        } label: { ChordTile(chord:event?.chord,width:max(44,CGFloat(event?.duration ?? barTicks)/CGFloat(barTicks)*barWidth-6)) }
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
            gridBackground(height:100)
            Canvas { context,_ in
                for note in Compiler.notes(session.displayProject) where note.pad>=0 {
                    let x=CGFloat(note.tick)/CGFloat(barTicks)*barWidth
                    let y=CGFloat(note.pad%4)*18+16
                    context.fill(Path(roundedRect:CGRect(x:x+2,y:y,width:max(3,barWidth/32),height:5),cornerRadius:1),with:.color(.drums.opacity(note.pad==2 ? 0.4:0.9)))
                }
            }.accessibilityLabel("Drum pattern. Edit in Jam.")
        }.frame(height:100).onTapGesture{session.tab=1}
    }
    var bassLane: some View {
        ZStack(alignment:.topLeading) {
            gridBackground(height:92)
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
        }.frame(height:92).onTapGesture{session.presentEditor(.bass)}
    }
    func melodyLane(_ track:Track)->some View {
        ZStack(alignment:.topLeading){gridBackground(height:76)
            Canvas{context,_ in
                if let index=session.displayProject.tracks.firstIndex(where:{$0.id==track.id}){
                    for n in Compiler.notes(session.displayProject) where n.track==index{let x=CGFloat(n.tick)/CGFloat(barTicks)*barWidth;let y=CGFloat(84-min(84,max(48,n.pitch)))/36*48+10;context.fill(Path(roundedRect:CGRect(x:x+2,y:y,width:max(3,CGFloat(n.duration)/CGFloat(barTicks)*barWidth-2),height:5),cornerRadius:2),with:.color(.mint.opacity(0.7)))}
                }
            }
        }.frame(height:76).contentShape(Rectangle()).onTapGesture{session.openNotes(track.id)}.accessibilityLabel("Edit \(track.displayName)")
    }
    func gridBackground(height: CGFloat)->some View {Canvas{context,size in for step in 0...session.displayProject.length/ppq {let x=CGFloat(step)*barWidth/4;var p=Path();p.move(to:CGPoint(x:x,y:0));p.addLine(to:CGPoint(x:x,y:height));context.stroke(p,with:.color(Color.raised.opacity(step%4==0 ? 1:0.4)),lineWidth:1)};var line=Path();line.move(to:CGPoint(x:0,y:height));line.addLine(to:CGPoint(x:size.width,y:height));context.stroke(line,with:.color(.raised),lineWidth:1)}}
}

struct ChordTile: View {
    let chord: Chord?
    let width: CGFloat
    var body: some View {
        VStack(alignment:.leading,spacing:13) {
            HStack { Text(chord?.symbol ?? "+").font(.system(size:26,weight:.medium)).lineLimit(1).minimumScaleFactor(0.5); Spacer() }
            if let chord {
                HStack(spacing:3) {
                    ForEach(Array(chord.notes.enumerated()),id:\.offset) { _,note in
                        RoundedRectangle(cornerRadius:1).fill(Color.harmony.opacity(0.5))
                            .frame(width:width/6,height:3).offset(y:CGFloat(72-note)/4)
                    }
                }
                Text(chord.quality.label).font(.system(size:9)).lineLimit(1).minimumScaleFactor(0.5).foregroundStyle(Color.harmony.opacity(0.9))
            }
        }.foregroundStyle(Color.harmony).padding(12).frame(width:width,height:116,alignment:.topLeading)
            .background(Color.harmony.opacity(chord == nil ? 0.04:0.12),in:RoundedRectangle(cornerRadius:7))
            .overlay { RoundedRectangle(cornerRadius:7).stroke(Color.harmony.opacity(0.22),lineWidth:1) }
    }
}
