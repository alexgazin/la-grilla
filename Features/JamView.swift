import SwiftUI
import MusicDomain
struct JamView: View {
    @Bindable var session: Session
    @State private var steps = false
    @State private var selectedPad = 0
    @State private var stepBar = 0
    @State private var velocity = 100.0
    @State private var pressed: Set<Int> = []
    var body: some View {
        VStack(spacing:14){
            HStack{VStack(alignment:.leading,spacing:5){SmallHeading(text:"DRUM MACHINE");Text("Pocket kit").font(.system(size:22,weight:.medium))};Spacer();Picker("Editor",selection:$steps){Text("Pads").tag(false);Text("Steps").tag(true)}.pickerStyle(.segmented).frame(width:145)}.padding(.top,18)
            HStack(spacing:6){Menu{ForEach([1,2,4,8],id:\.self){n in Button("\(n) bars"){session.setLoop(bars:n)}}}label:{HStack(spacing:5){Image(systemName:"repeat");Text("\(session.loopBars) bars");Image(systemName:"chevron.down").font(.system(size:8))}.font(.system(size:11,weight:.medium)).frame(minHeight:40).padding(.horizontal,10).background(Color.raised,in:RoundedRectangle(cornerRadius:8))}
                Menu{ForEach(Quantize.allCases,id:\.rawValue){q in Button(q == .off ? "Off":q == .eighth ? "1/8":"1/16"){session.quantize=q}}}label:{HStack(spacing:5){Text("Q").foregroundStyle(Color.muted);Text(session.quantize == .off ? "Off":session.quantize == .eighth ? "1/8":"1/16")}.font(.system(size:11,weight:.medium)).frame(minHeight:40).padding(.horizontal,10).background(Color.raised,in:RoundedRectangle(cornerRadius:8))}
                Spacer(minLength:0)
                IconButton(symbol:"metronome",label:"Metronome",color:session.metronome ? .mint:.muted){session.metronome.toggle();session.audio.metronome(session.metronome)}
                Menu{Toggle("Count-in",isOn:$session.countIn);Toggle("Overdub",isOn:$session.overdub)}label:{Image(systemName:"slider.horizontal.3").foregroundStyle(Color.muted).frame(width:44,height:44)}
            }
            if steps {stepEditor}else{padGrid}
            HStack(spacing:8){Circle().fill(session.recording || session.armed ? Color.record:Color.drums).frame(width:5,height:5);Text(session.armed ? "Count-in · get ready" : session.recording ? "Recording drums · tap Record to finish":"Play something only you would.").font(.system(size:11)).foregroundStyle(Color.muted);Spacer()}
            HStack{VStack(alignment:.leading,spacing:5){SmallHeading(text:"RECORD MODE");Text(session.overdub ? "Overdub":"Replace").font(.system(size:14,weight:.medium))};Spacer();Text(session.overdub ? "Build your beat, layer by layer.":"A new take. Your last one is undoable.").font(.system(size:10)).foregroundStyle(Color.muted).multilineTextAlignment(.trailing).frame(maxWidth:190)}.padding(14).background(Color.panel,in:RoundedRectangle(cornerRadius:10))
            Spacer(minLength:0)
        }.padding(.horizontal,18).padding(.bottom,16)
    }
    var padGrid: some View {
        GeometryReader{geo in
            let side=max(48,min((geo.size.width-24)/4,(geo.size.height-24)/4))
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:8),count:4),spacing:8){ForEach(0..<16,id:\.self){pad in
                let isDown=pressed.contains(pad)
                VStack(alignment:.leading,spacing:0){HStack{Text(String(format:"%02d",pad+1)).font(.system(size:9,design:.monospaced)).foregroundStyle(Color.drums.opacity(0.6));Spacer();Circle().fill(isDown ? Color.mint:Color.drums.opacity(0.25)).frame(width:4,height:4)};Spacer(minLength:4);Image(systemName:pad==0 ? "circle.fill":pad==1 ? "circle.lefthalf.filled":pad==2 || pad==3 ? "line.3.horizontal":"waveform").font(.system(size:17,weight:.light)).foregroundStyle(isDown ? Color.ink:Color.drums.opacity(0.8));Spacer(minLength:4);Text(LocalizedStringKey(Compiler.padNames[pad])).font(.system(size:10,weight:.medium)).lineLimit(1).minimumScaleFactor(0.7)}.padding(10).frame(maxWidth:.infinity).frame(height:side).background(isDown ? Color.drums:Color.drums.opacity(pad<4 ? 0.17:0.08),in:RoundedRectangle(cornerRadius:10)).overlay{RoundedRectangle(cornerRadius:10).stroke(Color.drums.opacity(isDown ? 0.8:0.22),lineWidth:1)}.contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance:0).onChanged{_ in if !pressed.contains(pad){pressed.insert(pad);session.hit(pad)}}.onEnded{_ in pressed.remove(pad)})
                    .accessibilityElement(children:.ignore).accessibilityLabel(LocalizedStringKey(Compiler.padNames[pad])).accessibilityAddTraits(.isButton).accessibilityAction{session.hit(pad)}
            }}.frame(maxHeight:.infinity,alignment:.center)
        }.frame(minHeight:240,maxHeight:380)
    }
    var drumPattern: Pattern? {
        guard let t=session.project.tracks.first(where:{$0.role == .drums}),let c=t.clips.first(where:{$0.start==session.section.start})else{return nil}
        return session.project.patterns.first(where:{$0.id==c.patternID})
    }
    var stepEditor: some View {
        VStack(spacing:16){
            HStack{Menu{ForEach(0..<16,id:\.self){i in Button(LocalizedStringKey(Compiler.padNames[i])){selectedPad=i}}}label:{Label(LocalizedStringKey(Compiler.padNames[selectedPad]),systemImage:"waveform").font(.system(size:15,weight:.medium)).foregroundStyle(Color.drums)};Spacer();Picker("Bar",selection:$stepBar){ForEach(0..<(drumPattern?.length ?? barTicks)/barTicks,id:\.self){i in Text("Bar \(i+1)").tag(i)}}.frame(width:110)}
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:6),count:4),spacing:10){ForEach(0..<16,id:\.self){step in
                let tick=stepBar*barTicks+step*240
                let exists=drumPattern?.drums.contains(where:{$0.pad==selectedPad && $0.tick==tick}) ?? false
                Button{toggleStep(tick)}label:{VStack(spacing:9){Text(String(step+1)).font(.system(size:10,design:.monospaced));RoundedRectangle(cornerRadius:2).fill(exists ? Color.drums:Color.raised).frame(height:26)}.foregroundStyle(exists ? Color.drums:Color.muted).padding(8).frame(height:61).background(exists ? Color.drums.opacity(0.14):Color.panel,in:RoundedRectangle(cornerRadius:7))}.buttonStyle(.plain).accessibilityLabel("Step \(step+1), \(exists ? "on":"off")")
            }}
            VStack(alignment:.leading,spacing:8){HStack{SmallHeading(text:"VELOCITY");Spacer();Text(String(Int(velocity))).font(.system(size:12,design:.monospaced))};Slider(value:$velocity,in:1...127,step:1).tint(.drums);Button("Apply velocity to this bar"){guard let id=drumPattern?.id else{return};session.edit{p in if let i=p.patterns.firstIndex(where:{$0.id==id}){for n in p.patterns[i].drums.indices where p.patterns[i].drums[n].pad==selectedPad && p.patterns[i].drums[n].tick/barTicks==stepBar{p.patterns[i].drums[n].velocity=Int(velocity)}}}}.font(.caption)}
        }.padding(14).background(Color.panel,in:RoundedRectangle(cornerRadius:12))
    }
    func toggleStep(_ tick: Int){guard let pattern=drumPattern else{return};session.edit{p in guard let i=p.patterns.firstIndex(where:{$0.id==pattern.id})else{return};if p.patterns[i].drums.contains(where:{$0.pad==selectedPad && $0.tick==tick}){p.patterns[i].drums.removeAll(where:{$0.pad==selectedPad && $0.tick==tick})}else{p.patterns[i].drums.append(DrumEvent(tick:tick,pad:selectedPad,velocity:Int(velocity)))}}}
}
