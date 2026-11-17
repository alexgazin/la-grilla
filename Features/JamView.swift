import SwiftUI
import MusicDomain
struct JamView: View {
    @Bindable var session: Session
    @Environment(\.verticalSizeClass) private var verticalSize
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.scenePhase) private var scenePhase
    @State private var steps = false
    @State private var showGuide=false
    @State private var selectedPad = 0
    @State private var stepBar = 0
    @State private var velocity = 100.0
    @State private var pressed: Set<Int> = []
    var body:some View{
        Group{if verticalSize == .compact{compactJam}else{GeometryReader{geometry in ScrollView(.vertical){regularJam(compact:geometry.size.height<500)}}}}
            .onChange(of:drumPattern?.id){_,_ in stepBar=0}
            .onChange(of:drumPattern?.length){_,length in stepBar=min(stepBar,max(0,(length ?? barTicks)/barTicks-1))}
            .onChange(of:scenePhase){_,phase in if phase != .active{pressed=[]}}
            .onChange(of:session.performance.replaying){_,replaying in if replaying{pressed=[]}}
            .onDisappear{pressed=[]}
            .onAppear{_ = session.ensureAudio()}
    }
    private func regularJam(compact:Bool)->some View {
        VStack(spacing:14){
            HStack(spacing:10){Text("Pocket kit").font(.system(size:26,weight:.semibold)).tracking(-0.6).lineLimit(1).minimumScaleFactor(0.75);Spacer(minLength:0);editorMode}.padding(.top,12)
            if focusedClip != nil{clipFocus}
            HStack(spacing:12){soundControl;Spacer(minLength:0);beatIndicator}
            HStack(spacing:6){Menu{ForEach(session.loopLengthOptions,id:\.self){n in Button("\(n) bars"){session.setLoop(bars:n)}}}label:{HStack(spacing:5){Image(systemName:"repeat");Text("\(session.loopBars) bars");Image(systemName:"chevron.down").font(.system(size:11))}.font(.system(size:11,weight:.medium)).frame(minHeight:44).padding(.horizontal,12).background(Color.panel,in:RoundedRectangle(cornerRadius:12,style:.continuous))}.disabled(session.performance.contextActive)
                Menu{ForEach(Quantize.allCases,id:\.rawValue){q in Button(LocalizedStringKey(q == .off ? "Off":q == .eighth ? "1/8":"1/16")){session.quantize=q}}}label:{HStack(spacing:5){Text("Q").foregroundStyle(Color.muted);Text(LocalizedStringKey(session.quantize == .off ? "Off":session.quantize == .eighth ? "1/8":"1/16"))}.font(.system(size:11,weight:.medium)).frame(minHeight:44).padding(.horizontal,12).background(Color.panel,in:RoundedRectangle(cornerRadius:12,style:.continuous))}.disabled(session.performance.contextActive)
                Spacer(minLength:0)
                IconButton(symbol:"metronome",label:"Metronome",color:session.metronome ? .mint:.muted){session.metronome.toggle();session.audio.metronome(session.metronome)}
                Menu{Toggle("Count-in",isOn:$session.countIn);Toggle("Overdub",isOn:$session.overdub)}label:{Image(systemName:"slider.horizontal.3").foregroundStyle(Color.muted).frame(width:44,height:44)}.accessibilityLabel("Drum recording options").disabled(session.performance.contextActive)
            }
            if session.recording || session.armed{HStack(spacing:8){Circle().fill(Color.record).frame(width:5,height:5);Text(LocalizedStringKey(session.armed ? "Count-in · get ready":"Recording drums · tap Record to finish")).font(.caption).foregroundStyle(Color.record);Spacer()}}
            if steps {stepEditor.disabled(session.performance.contextActive)}else if dynamicType.isAccessibilitySize{accessiblePads}else{padGrid(height:(compact ? 264:312)-(compact && (session.recording || session.armed) ? 24:0)).disabled(session.performance.replaying).allowsHitTesting(!session.performance.replaying)}
            if !steps{Text("Touch to play · grid shapes the recording").font(.caption2).foregroundStyle(Color.muted).frame(maxWidth:.infinity,alignment:.leading)}
            if session.audio.wirelessOutput{Text("For tighter timing, use the speaker or wired headphones.").font(.caption2).foregroundStyle(Color.drums).frame(maxWidth:.infinity,alignment:.leading)}
            recordingGuide
            Spacer(minLength:0)
        }.padding(.horizontal,18).padding(.bottom,16)
    }
    private var editorMode:some View {HStack(spacing:2){
        Button{steps=false}label:{Text("Pads").frame(maxWidth:.infinity,minHeight:44).foregroundStyle(!steps ? Color.ink:Color.muted).background(!steps ? Color.mint:Color.clear,in:RoundedRectangle(cornerRadius:10))}
        Button{steps=true}label:{Text("Steps").frame(maxWidth:.infinity,minHeight:44).foregroundStyle(steps ? Color.ink:Color.muted).background(steps ? Color.mint:Color.clear,in:RoundedRectangle(cornerRadius:10))}
    }.font(.system(size:12,weight:.semibold)).buttonStyle(StudioQuietButtonStyle()).padding(3).frame(width:140).modifier(StudioSurface())}
    private var recordingGuide:some View {VStack(alignment:.leading,spacing:0){
        Button{showGuide.toggle()}label:{HStack{SmallHeading(text:"RECORD MODE");Spacer();Text(LocalizedStringKey(session.overdub ? "Overdub":"Replace")).font(.caption.weight(.medium));Image(systemName:showGuide ? "chevron.up":"chevron.down").font(.system(size:11,weight:.semibold))}.foregroundStyle(Color.muted).frame(minHeight:44)}.buttonStyle(StudioQuietButtonStyle()).accessibilityLabel("Recording guide").accessibilityValue(LocalizedStringKey(showGuide ? "Expanded":"Collapsed")).accessibilityIdentifier("jam.recording-guide")
        if showGuide{VStack(alignment:.leading,spacing:8){
            Text("Play something only you would.")
            Text(LocalizedStringKey(session.overdub ? "Build your beat, layer by layer.":"A new take. Your last one is undoable."))
            Toggle("Count-in",isOn:$session.countIn).frame(minHeight:44).disabled(session.performance.contextActive)
            Toggle("Overdub",isOn:$session.overdub).frame(minHeight:44).disabled(session.performance.contextActive)
        }.font(.caption).foregroundStyle(Color.muted).padding(.bottom,12)}
    }.padding(.horizontal,12).modifier(StudioSurface())}
    private var compactJam:some View {VStack(spacing:4){
        HStack{Text("Pocket kit").font(.headline);soundControl;Spacer();editorMode
            Menu{
                Picker("Quantize",selection:$session.quantize){ForEach(Quantize.allCases,id:\.rawValue){value in Text(LocalizedStringKey(value == .off ? "Off":value == .eighth ? "1/8":"1/16")).tag(value)}}
                Toggle("Count-in",isOn:$session.countIn);Toggle("Overdub",isOn:$session.overdub)
                Toggle("Metronome",isOn:Binding(get:{session.metronome},set:{session.metronome=$0;session.audio.metronome($0)}))
                Picker("Loop length",selection:Binding(get:{session.loopBars},set:{session.setLoop(bars:$0)})){ForEach(session.loopLengthOptions,id:\.self){bars in Text("\(bars) bars").tag(bars)}}.disabled(session.performance.contextActive)
            }label:{Image(systemName:"slider.horizontal.3").frame(width:44,height:44)}.accessibilityLabel("Drum recording options")
        }
        if focusedClip != nil{clipFocus}
        if steps{ScrollView{stepEditor.disabled(session.performance.contextActive)}}else if dynamicType.isAccessibilitySize{accessiblePads}else{padGrid(height:200).disabled(session.performance.replaying)}
    }.padding(.horizontal,12).padding(.bottom,8)}
    @ViewBuilder private var soundControl:some View{
        if let drums=session.displayProject.tracks.first(where:{$0.role == .drums}){TrackSoundButton(session:session,trackID:drums.id,compact:verticalSize == .compact)}
    }
    private var beatIndicator:some View{
        let beat=session.armed && session.audio.countRemaining>0 ? max(0,4-Int(ceil(Double(session.audio.countRemaining)/session.audio.sampleRate*session.project.bpm/60))):Int(session.audio.tick/Double(ppq))%4
        return HStack(spacing:7){ForEach(0..<4,id:\.self){index in Circle().fill(session.audio.playing && index==beat ? (session.armed ? Color.record:Color.mint):Color.outline).frame(width:index==0 ? 10:7,height:index==0 ? 10:7)}}.frame(minHeight:44).accessibilityElement(children:.ignore).accessibilityLabel("Beat").accessibilityValue(session.audio.playing ? String(beat+1):NSLocalizedString("Stopped",comment:"Transport"))
    }
    private var accessiblePads:some View {ScrollView{
        LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:10){ForEach(0..<16,id:\.self){pad in
            Button{session.hit(pad)}label:{Text(LocalizedStringKey(Compiler.padNames[pad])).font(.headline).frame(maxWidth:.infinity,minHeight:72).padding(8).background(Color.drums.opacity(0.15),in:RoundedRectangle(cornerRadius:10))}.buttonStyle(StudioQuietButtonStyle()).foregroundStyle(Color.drums)
        }}
    }.frame(minHeight:240).disabled(session.performance.replaying)}
    private func padGrid(height:CGFloat)->some View {
        GeometryReader{geo in
            let side=max(44,min((geo.size.width-24)/4,(geo.size.height-24)/4))
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:8),count:4),spacing:8){ForEach(0..<16,id:\.self){pad in
                let isDown=pressed.contains(pad)
                VStack(alignment:.leading,spacing:0){
                    Text(String(format:"%02d",pad+1)).font(.system(size:11,weight:.medium,design:.monospaced)).foregroundStyle(isDown ? Color.ink.opacity(0.7):Color.drums)
                    Spacer(minLength:4)
                    Text(LocalizedStringKey(Compiler.padNames[pad])).font(.system(size:11,weight:.medium)).lineLimit(1).foregroundStyle(isDown ? Color.ink:Color.studioText)
                }.padding(height<280 ? 8:10).frame(maxWidth:.infinity,alignment:.leading).frame(height:side).background(isDown ? Color.mint:Color.panel,in:RoundedRectangle(cornerRadius:14,style:.continuous)).overlay{RoundedRectangle(cornerRadius:14,style:.continuous).stroke(isDown ? Color.mint:Color.outline.opacity(0.75),lineWidth:isDown ? 1.5:0.6)}.contentShape(Rectangle())
                    .accessibilityHidden(true)
            }}.frame(maxHeight:.infinity,alignment:.center)
                .overlay{PadTouchSurface(enabled:scenePhase == .active && !session.performance.replaying,trace:session.runtimeTraceEnabled,onHit:{pad,time in session.hit(pad,touchTime:time)},onHeld:{pressed=$0})}
        }.frame(height:height)
    }
    private var focusedClip:Clip?{guard let id=session.drumClipID else{return nil};return session.displayProject.tracks.first{$0.role == .drums}?.clips.first{$0.id==id}}
    private var clipFocus:some View{HStack(spacing:8){Text("Editing this drum clip's source pattern. Repeats share these steps.").font(.caption).foregroundStyle(Color.muted);Spacer(minLength:0);Button("Whole section"){session.drumClipID=nil;session.sync()}.font(.caption).frame(minHeight:44)}.accessibilityIdentifier("jam.clip-focus")}
    var drumPattern: Pattern? {
        guard let t=session.displayProject.tracks.first(where:{$0.role == .drums}),let c=focusedClip ?? t.clips.first(where:{$0.start<=session.section.start && $0.start+$0.length>session.section.start})else{return nil}
        return session.displayProject.patterns.first(where:{$0.id==c.patternID})
    }
    var stepEditor: some View {
        VStack(spacing:16){
            HStack{Menu{ForEach(0..<16,id:\.self){i in Button(LocalizedStringKey(Compiler.padNames[i])){selectedPad=i}}}label:{Label(LocalizedStringKey(Compiler.padNames[selectedPad]),systemImage:"waveform").font(.system(size:15,weight:.medium)).foregroundStyle(Color.drums)};Spacer();Picker("Bar",selection:$stepBar){ForEach(0..<(drumPattern?.length ?? barTicks)/barTicks,id:\.self){i in Text("Bar \(i+1)").tag(i)}}.frame(width:110)}
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:6),count:4),spacing:10){ForEach(0..<16,id:\.self){step in
                let tick=stepBar*barTicks+step*240
                let exists=drumPattern?.drums.contains(where:{$0.pad==selectedPad && $0.tick==tick}) ?? false
                Button{toggleStep(tick)}label:{VStack(spacing:9){Text(String(step+1)).font(.system(size:11,design:.monospaced));RoundedRectangle(cornerRadius:2).fill(exists ? Color.drums:Color.raised).frame(height:26)}.foregroundStyle(exists ? Color.drums:Color.muted).padding(8).frame(height:61).background(exists ? Color.drums.opacity(0.14):Color.panel,in:RoundedRectangle(cornerRadius:7))}.buttonStyle(StudioQuietButtonStyle()).accessibilityLabel("Step \(step+1)").accessibilityValue(LocalizedStringKey(exists ? "On":"Off")).accessibilityIdentifier("jam.step.\(step)")
            }}
            VStack(alignment:.leading,spacing:8){HStack{SmallHeading(text:"VELOCITY");Spacer();Text(String(Int(velocity))).font(.system(size:12,design:.monospaced))};Slider(value:$velocity,in:1...127,step:1).tint(.drums);Button("Apply velocity to this bar"){guard let id=drumPattern?.id else{return};session.edit{p in if let i=p.patterns.firstIndex(where:{$0.id==id}){for n in p.patterns[i].drums.indices where p.patterns[i].drums[n].pad==selectedPad && p.patterns[i].drums[n].tick/barTicks==stepBar{p.patterns[i].drums[n].velocity=Int(velocity)}}}}.font(.caption)}
        }.padding(14).background(Color.panel,in:RoundedRectangle(cornerRadius:12,style:.continuous))
    }
    func toggleStep(_ tick: Int){guard let pattern=drumPattern else{return};session.edit{p in guard let i=p.patterns.firstIndex(where:{$0.id==pattern.id})else{return};if p.patterns[i].drums.contains(where:{$0.pad==selectedPad && $0.tick==tick}){p.patterns[i].drums.removeAll(where:{$0.pad==selectedPad && $0.tick==tick})}else{p.patterns[i].drums.append(DrumEvent(tick:tick,pad:selectedPad,velocity:Int(velocity)))}}}
}
