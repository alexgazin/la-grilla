import SwiftUI
import MusicDomain
struct ChordSelection: Identifiable {let id: UUID;let patternID: UUID;let tick: Int;let chord: Chord;var duration: Int = barTicks}
struct GridView: View {
    @Bindable var session: Session
    @State private var barWidth: CGFloat = 112
    @State private var zoomBase: CGFloat = 112
    @State private var selection: ChordSelection?
    @State private var dragStart: Int?
    var body: some View {
        VStack(alignment:.leading,spacing:0){
            HStack{SmallHeading(text:"ARRANGEMENT");Spacer();Text("\(session.project.length/barTicks) bars").font(.system(size:11,design:.monospaced)).foregroundStyle(Color.muted);IconButton(symbol:"ellipsis",label:"Edit song sections",color:.muted){session.sheet = .sections}}.padding(.horizontal,18).padding(.top,8)
            ScrollView(.horizontal,showsIndicators:false){HStack(spacing:8){ForEach(session.project.sections){s in Button{session.select(s)}label:{HStack(spacing:8){RoundedRectangle(cornerRadius:1).fill(session.section.id==s.id ? Color.mint:Color.muted).frame(width:3,height:20);VStack(alignment:.leading,spacing:3){Text(s.name).font(.system(size:12,weight:.semibold));Text("\(s.start/barTicks+1)–\((s.start+s.length)/barTicks)").font(.system(size:9,design:.monospaced)).foregroundStyle(Color.muted)}}.padding(.horizontal,12).padding(.vertical,10).background(session.section.id==s.id ? Color.raised:Color.panel,in:RoundedRectangle(cornerRadius:8)).overlay{RoundedRectangle(cornerRadius:8).stroke(session.section.id==s.id ? Color.mint.opacity(0.4):Color.clear,lineWidth:1)}}.buttonStyle(.plain)}
                Button{session.sheet = .sections}label:{Image(systemName:"plus").frame(width:44,height:48).foregroundStyle(Color.muted)}
            }.padding(.horizontal,18)}.padding(.bottom,18)
            HStack(spacing:0){
                VStack(spacing:0){Color.clear.frame(height:34);trackLabel(.harmony,height:132);trackLabel(.drums,height:100);trackLabel(.bass,height:92)}.frame(width:68)
                ScrollView(.horizontal,showsIndicators:true){ZStack(alignment:.topLeading){
                    timeline
                    Rectangle().fill(Color.mint).frame(width:1.5,height:324).offset(x:CGFloat(session.audio.tick)/CGFloat(barTicks)*barWidth,y:34).allowsHitTesting(false)
                    Image(systemName:"triangle.fill").font(.system(size:9)).rotationEffect(.degrees(180)).foregroundStyle(Color.mint).offset(x:CGFloat(session.audio.tick)/CGFloat(barTicks)*barWidth-4,y:23).allowsHitTesting(false)
                }.frame(width:CGFloat(session.project.length/barTicks)*barWidth).gesture(MagnifyGesture().onChanged{value in barWidth=min(200,max(68,zoomBase*value.magnification))}.onEnded{_ in zoomBase=barWidth})}
            }
            HStack{Image(systemName:"hand.pinch");Text("Pinch to zoom");Spacer();Text("SNAP  1/16").fontDesign(.monospaced)}.font(.system(size:9)).foregroundStyle(Color.muted).padding(.horizontal,18).padding(.top,14)
            Spacer(minLength:14)
            HStack(alignment:.top,spacing:12){Image(systemName:"pianokeys").foregroundStyle(Color.harmony).font(.system(size:23));VStack(alignment:.leading,spacing:5){Text("Make room for an idea.").font(.system(size:15,weight:.medium));Text("Tap a chord to shape your harmony.\nThen find its rhythm in Jam.").font(.system(size:12)).foregroundStyle(Color.muted).lineSpacing(3)};Spacer()}.padding(18).background(Color.panel,in:RoundedRectangle(cornerRadius:12)).padding(.horizontal,18).padding(.bottom,18)
        }.sheet(item:$selection){s in ChordEditor(session:session,selection:s).presentationDetents([.medium,.large]).presentationDragIndicator(.visible).presentationBackground(Color.panel)}
    }
    func trackLabel(_ role: TrackRole,height: CGFloat)->some View {
        Button{if role == .bass {session.sheet = .bass}else if role == .drums{session.tab=1}}
        label:{VStack(alignment:.leading,spacing:9){RoundedRectangle(cornerRadius:2).fill(Color.track(role)).frame(width:18,height:3);Text(role == .harmony ? "HARM":role == .drums ? "DRUM":"BASS").font(.system(size:9,weight:.semibold));Image(systemName:role == .harmony ? "pianokeys":role == .drums ? "square.grid.2x2":"waveform").font(.system(size:14)).foregroundStyle(Color.track(role))}.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.leading).padding(.leading,16).frame(height:height).background(Color.panel.opacity(0.6)).overlay(alignment:.bottom){Rectangle().fill(Color.raised).frame(height:1)}}.buttonStyle(.plain)
    }
    var timeline: some View {
        VStack(spacing:0){
            HStack(spacing:0){ForEach(0..<session.project.length/barTicks,id:\.self){bar in Text(String(format:"%02d",bar+1)).font(.system(size:10,weight:.medium,design:.monospaced)).foregroundStyle(Color.muted).frame(width:barWidth,alignment:.leading)}}.frame(height:34).overlay(alignment:.topLeading){Rectangle().fill(Color.mint.opacity(0.6)).frame(width:CGFloat(session.loopRange.count)/CGFloat(barTicks)*barWidth,height:2).offset(x:CGFloat(session.loopRange.lowerBound)/CGFloat(barTicks)*barWidth)}
            ZStack(alignment:.topLeading){gridBackground(height:132)
                if let track=session.project.tracks.first(where:{$0.role == .harmony}) {ForEach(track.clips){clip in if let p=session.project.patterns.first(where:{$0.id==clip.patternID}){
                    ForEach(0..<p.length/barTicks,id:\.self){bar in let e=p.chords.first(where:{$0.tick<=bar*barTicks && $0.tick+$0.duration>bar*barTicks})
                        Button{selection=ChordSelection(id:e?.id ?? UUID(),patternID:p.id,tick:e?.tick ?? bar*barTicks,chord:e?.chord ?? Chord(root:session.project.keyRoot,quality:session.project.minor ? .minor:.major),duration:e?.duration ?? barTicks)}label:{VStack(alignment:.leading,spacing:13){HStack{Text(e?.chord.symbol ?? "+").font(.system(size:26,weight:.medium));Spacer()};if let e {HStack(spacing:3){ForEach(Array(e.chord.notes.enumerated()),id:\.offset){_,n in RoundedRectangle(cornerRadius:1).fill(Color.harmony.opacity(0.5)).frame(width:barWidth/6,height:3).offset(y:CGFloat(72-n)/4)}};Text(e.chord.quality.label).font(.system(size:9)).foregroundStyle(Color.harmony.opacity(0.65))}}.foregroundStyle(Color.harmony).padding(12).frame(width:barWidth-6,height:116,alignment:.topLeading).background(Color.harmony.opacity(e == nil ? 0.04:0.12),in:RoundedRectangle(cornerRadius:7)).overlay{RoundedRectangle(cornerRadius:7).stroke(Color.harmony.opacity(0.22),lineWidth:1)}}.buttonStyle(.plain).offset(x:CGFloat(clip.start/barTicks+bar)*barWidth+3,y:8)
                        .simultaneousGesture(LongPressGesture(minimumDuration:0.35).sequenced(before:DragGesture()).onEnded{value in
                            if case .second(true,let drag?)=value,let e {
                                let delta=Int((drag.translation.width/barWidth*16).rounded())*240
                                session.edit {p in guard let i=p.patterns.firstIndex(where:{$0.id==clip.patternID}),let n=p.patterns[i].chords.firstIndex(where:{$0.id==e.id})else{return};p.patterns[i].chords[n].tick=max(0,min(p.patterns[i].length-e.duration,e.tick+delta))}
                            }
                        })
                        .contextMenu{if let e{Button("Delete chord",role:.destructive){session.edit{p in if let i=p.patterns.firstIndex(where:{$0.id==clip.patternID}){p.patterns[i].chords.removeAll(where:{$0.id==e.id})}}}}}
                    }
                }}}
            }.frame(height:132)
            ZStack(alignment:.topLeading){gridBackground(height:100);Canvas{context,size in
                for n in Compiler.notes(session.project) where n.pad>=0 {let x=CGFloat(n.tick)/CGFloat(barTicks)*barWidth;let y=CGFloat(n.pad%4)*18+16;context.fill(Path(roundedRect:CGRect(x:x+2,y:y,width:max(3,barWidth/32),height:5),cornerRadius:1),with:.color(.drums.opacity(n.pad==2 ? 0.4:0.9)))}
            }.accessibilityLabel("Drum pattern. Edit in Jam.")}.frame(height:100).onTapGesture{session.tab=1}
            ZStack(alignment:.topLeading){gridBackground(height:92)
                if session.project.tracks.contains(where:{$0.role == .bass}) {Canvas{context,size in for n in Compiler.notes(session.project) where n.track==session.project.tracks.firstIndex(where:{$0.role == .bass}) {let x=CGFloat(n.tick)/CGFloat(barTicks)*barWidth;let width=CGFloat(n.duration)/CGFloat(barTicks)*barWidth;context.fill(Path(roundedRect:CGRect(x:x+4,y:28,width:max(3,width-8),height:24),cornerRadius:4),with:.color(.bass.opacity(0.18)));context.fill(Path(roundedRect:CGRect(x:x+12,y:38,width:max(3,width-24),height:3),cornerRadius:1),with:.color(.bass.opacity(0.7)))}}}
                else {Button("+ Add root bass"){session.sheet = .bass}.font(.system(size:12)).foregroundStyle(Color.bass).padding(20)}
            }.frame(height:92).onTapGesture{session.sheet = .bass}
        }
    }
    func gridBackground(height: CGFloat)->some View {Canvas{context,size in for step in 0...session.project.length/ppq {let x=CGFloat(step)*barWidth/4;var p=Path();p.move(to:CGPoint(x:x,y:0));p.addLine(to:CGPoint(x:x,y:height));context.stroke(p,with:.color(Color.raised.opacity(step%4==0 ? 1:0.4)),lineWidth:1)};var line=Path();line.move(to:CGPoint(x:0,y:height));line.addLine(to:CGPoint(x:size.width,y:height));context.stroke(line,with:.color(.raised),lineWidth:1)}}
}
