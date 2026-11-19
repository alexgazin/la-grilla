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
    @AppStorage("jam.haptics") private var padHaptics = false
    @AppStorage("jam.lesson") private var lessonID = ""
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
            jamHeading.padding(.top,12)
            if focusedClip != nil{clipFocus}
            HStack(spacing:10){soundControl;InstrumentKeyboardButton(session: session, compact: true);beatIndicator}
            recordingControls
            if session.recording || session.armed{recordingStatus}
            if steps {stepEditor.disabled(session.performance.contextActive)}else if dynamicType.isAccessibilitySize{accessiblePads}else{padGrid(height:(compact ? 264:312)-(compact && (session.recording || session.armed) ? 24:0)).disabled(session.performance.replaying).allowsHitTesting(!session.performance.replaying)}
            if !steps{Text("Touch to play · grid shapes the recording").font(.caption2).foregroundStyle(Color.muted).frame(maxWidth:.infinity,alignment:.leading)}
            if session.audio.wirelessOutput{Text("For tighter timing, use the speaker or wired headphones.").font(.caption2).foregroundStyle(Color.drums).frame(maxWidth:.infinity,alignment:.leading)}
            if let lesson=DrumLesson.library.first(where:{$0.id==lessonID}){DrumLessonPanel(lesson:lesson,played:drumPattern?.drums ?? [],bars:min(4,max(1,(drumPattern?.length ?? barTicks)/barTicks))){lessonID=""}}
            recordingGuide
            Spacer(minLength:0)
        }.padding(.horizontal,18).padding(.bottom,16)
    }
    @ViewBuilder private var jamHeading:some View {
        if dynamicType.isAccessibilitySize{
            VStack(alignment:.leading,spacing:12){Text("Pocket kit").font(.title2.weight(.semibold));editorMode}
        }else{
            HStack(spacing:12){Text("Pocket kit").font(.title2.weight(.semibold)).tracking(-0.5);Spacer(minLength:0);editorMode}
        }
    }
    @ViewBuilder private var recordingControls:some View {
        if dynamicType.isAccessibilitySize{
            VStack(spacing:8){HStack{loopControl;Spacer(minLength:8);recordingOptions};HStack{quantizeControl;Spacer(minLength:8);metronomeControl}}
        }else{
            HStack(spacing:6){loopControl;quantizeControl;Spacer(minLength:0);metronomeControl;recordingOptions}
        }
    }
    private var loopControl:some View{
        Menu{ForEach(session.loopLengthOptions,id:\.self){n in Button("\(n) bars"){session.setLoop(bars:n)}}}label:{HStack(spacing:6){Image(systemName:"repeat").foregroundStyle(Color.drums);Text("\(session.loopBars) bars").monospacedDigit();Image(systemName:"chevron.down").font(.system(size:11,weight:.semibold)).foregroundStyle(Color.muted)}.modifier(JamUtilitySurface())}.disabled(session.performance.contextActive)
    }
    private var quantizeControl:some View{
        Menu{ForEach(Quantize.allCases,id:\.rawValue){q in Button(LocalizedStringKey(q == .off ? "Off":q == .eighth ? "1/8":"1/16")){session.quantize=q}};QuantizeFeelMenu(session:session)}label:{HStack(spacing:6){Text("Q").foregroundStyle(Color.drums);Text(LocalizedStringKey(session.quantize == .off ? "Off":session.quantize == .eighth ? "1/8":"1/16")).monospacedDigit()}.modifier(JamUtilitySurface())}.disabled(session.performance.contextActive)
    }
    private var metronomeControl:some View{
        IconButton(symbol:"metronome",label:"Metronome",color:session.metronome ? .mint:.muted){session.metronome.toggle();session.audio.metronome(session.metronome)}
    }
    private var recordingOptions:some View{
        Menu{Toggle("Count-in",isOn:$session.countIn);Toggle("Overdub",isOn:$session.overdub);Toggle("Velocity from touch",isOn:$session.padVelocityFromTouch);Toggle("Haptics on hits",isOn:$padHaptics);Picker("Note repeat",selection:$session.noteRepeat){Text("Off").tag(NoteRepeat.Rate?.none);Text(verbatim:"1/8").tag(Optional(NoteRepeat.Rate.eighth));Text(verbatim:"1/16").tag(Optional(NoteRepeat.Rate.sixteenth));Text(verbatim:"1/32").tag(Optional(NoteRepeat.Rate.thirtySecond));Text(verbatim:"1/8T").tag(Optional(NoteRepeat.Rate.eighthTriplet));Text(verbatim:"1/16T").tag(Optional(NoteRepeat.Rate.sixteenthTriplet))};Picker("Lesson",selection:$lessonID){Text("No lesson").tag("");ForEach(DrumLesson.library){lesson in Text(LocalizedStringKey(lesson.title)).tag(lesson.id)}};Button("Keep the last 4 bars I played"){_ = session.keepRecentHits(bars:4)}.disabled(session.recording || session.armed)}label:{Image(systemName:"slider.horizontal.3").foregroundStyle(Color.muted).frame(width:44,height:44).background(Color.raised.opacity(0.45),in:RoundedRectangle(cornerRadius:12,style:.continuous))}.accessibilityLabel("Drum recording options").disabled(session.performance.contextActive)
    }
    private var editorMode:some View {HStack(spacing:2){
        Button{steps=false}label:{Text("Pads").frame(maxWidth:.infinity,minHeight:44).foregroundStyle(!steps ? Color.ink:Color.muted).background(!steps ? Color.mint:Color.clear,in:RoundedRectangle(cornerRadius:10,style:.continuous))}.accessibilityAddTraits(!steps ? .isSelected:[])
        Button{steps=true}label:{Text("Steps").frame(maxWidth:.infinity,minHeight:44).foregroundStyle(steps ? Color.ink:Color.muted).background(steps ? Color.mint:Color.clear,in:RoundedRectangle(cornerRadius:10,style:.continuous))}.accessibilityAddTraits(steps ? .isSelected:[])
    }.font(.caption.weight(.semibold)).buttonStyle(StudioQuietButtonStyle()).padding(3).frame(width:dynamicType.isAccessibilitySize ? 220:146).modifier(StudioSurface(color:.ink))}
    private var recordingStatus:some View{HStack(spacing:9){Image(systemName:session.armed ? "record.circle":"record.circle.fill").font(.caption);Text(LocalizedStringKey(session.armed ? "Count-in · get ready":"Recording drums · tap Record to finish")).font(.caption.weight(.medium));Spacer(minLength:0);if session.recording{Button{session.undoPass()}label:{Label("Undo pass",systemImage:"arrow.uturn.backward").font(.caption.weight(.semibold)).frame(minHeight:44)}.disabled(!session.canUndoPass).accessibilityIdentifier("jam.undo-pass")}}.foregroundStyle(Color.record).padding(10).background(Color.record.opacity(0.08),in:RoundedRectangle(cornerRadius:10,style:.continuous))}
    private var recordingGuide:some View {VStack(alignment:.leading,spacing:0){
        Button{showGuide.toggle()}label:{HStack(spacing:10){Image(systemName:session.overdub ? "square.stack.3d.up":"arrow.triangle.2.circlepath").font(.system(size:16,weight:.medium)).foregroundStyle(Color.drums).frame(width:28);SmallHeading(text:"RECORD MODE");Spacer(minLength:4);Text(LocalizedStringKey(session.overdub ? "Overdub":"Replace")).font(.caption.weight(.semibold)).foregroundStyle(Color.studioText);Image(systemName:showGuide ? "chevron.up":"chevron.down").font(.system(size:11,weight:.semibold)).foregroundStyle(Color.muted)}.frame(minHeight:52)}.buttonStyle(StudioQuietButtonStyle()).accessibilityLabel("Recording guide").accessibilityValue(LocalizedStringKey(showGuide ? "Expanded":"Collapsed")).accessibilityIdentifier("jam.recording-guide")
        if showGuide{VStack(alignment:.leading,spacing:8){
            Text("Play something only you would.")
            Text(LocalizedStringKey(session.overdub ? "Build your beat, layer by layer.":"A new take. Your last one is undoable."))
            Toggle("Count-in",isOn:$session.countIn).frame(minHeight:44).disabled(session.performance.contextActive)
            Toggle("Overdub",isOn:$session.overdub).frame(minHeight:44).disabled(session.performance.contextActive)
        }.font(.caption).foregroundStyle(Color.muted).padding(.bottom,12)}
    }.padding(.horizontal,12).modifier(StudioSurface()).overlay(alignment:.leading){RoundedRectangle(cornerRadius:2).fill(session.recording || session.armed ? Color.record:Color.drums.opacity(0.65)).frame(width:3).padding(.vertical,14).allowsHitTesting(false)}}
    private var compactJam:some View {VStack(spacing:8){
        if dynamicType.isAccessibilitySize{
            HStack{Text("Pocket kit").font(.headline);Spacer();compactOptions}
            HStack(spacing:10){soundControl;InstrumentKeyboardButton(session: session, compact: true);editorMode}
        }else{
            HStack(spacing:10){Text("Pocket kit").font(.headline);soundControl;InstrumentKeyboardButton(session: session, compact: true);Spacer(minLength:0);editorMode;compactOptions}
        }
        if focusedClip != nil{clipFocus}
        if steps{ScrollView{stepEditor.disabled(session.performance.contextActive)}}else if dynamicType.isAccessibilitySize{accessiblePads}else{padGrid(height:200).disabled(session.performance.replaying)}
    }.padding(.horizontal,12).padding(.bottom,8).modifier(ScrollableForLargeType())}
    private var compactOptions:some View{
        Menu{
                Picker("Quantize",selection:$session.quantize){ForEach(Quantize.allCases,id:\.rawValue){value in Text(LocalizedStringKey(value == .off ? "Off":value == .eighth ? "1/8":"1/16")).tag(value)}}
                Toggle("Count-in",isOn:$session.countIn);Toggle("Overdub",isOn:$session.overdub)
                Toggle("Metronome",isOn:Binding(get:{session.metronome},set:{session.metronome=$0;session.audio.metronome($0)}))
                Picker("Loop length",selection:Binding(get:{session.loopBars},set:{session.setLoop(bars:$0)})){ForEach(session.loopLengthOptions,id:\.self){bars in Text("\(bars) bars").tag(bars)}}.disabled(session.performance.contextActive)
        }label:{Image(systemName:"slider.horizontal.3").foregroundStyle(Color.muted).frame(width:44,height:44).background(Color.raised.opacity(0.45),in:RoundedRectangle(cornerRadius:12,style:.continuous))}.accessibilityLabel("Drum recording options")
    }
    @ViewBuilder private var soundControl:some View{
        if let drums=session.displayProject.tracks.first(where:{$0.role == .drums}){
            TrackSoundButton(session:session,trackID:drums.id,compact:verticalSize == .compact)
                .padding(4)
                .background(Color.panel,in:RoundedRectangle(cornerRadius:15,style:.continuous))
                .overlay{RoundedRectangle(cornerRadius:15,style:.continuous).strokeBorder(Color.drums.opacity(0.28),lineWidth:0.7).allowsHitTesting(false)}
        }
    }
    private var beatIndicator:some View{
        let beat=session.armed && session.audio.countRemaining>0 ? max(0,4-Int(ceil(Double(session.audio.countRemaining)/session.audio.sampleRate*session.project.bpm/60))):Int(session.audio.tick/Double(ppq))%4
        return VStack(alignment:.leading,spacing:9){Text("Beat").font(.caption2.weight(.medium)).foregroundStyle(Color.muted);HStack(spacing:5){ForEach(0..<4,id:\.self){index in RoundedRectangle(cornerRadius:2,style:.continuous).fill(session.audio.playing && index==beat ? (session.armed ? Color.record:Color.mint):Color.outline).frame(width:index==0 ? 17:11,height:4)}}}.padding(.horizontal,12).frame(minHeight:64).background(Color.panel,in:RoundedRectangle(cornerRadius:15,style:.continuous)).accessibilityElement(children:.ignore).accessibilityLabel("Beat").accessibilityValue(session.audio.playing ? String(beat+1):NSLocalizedString("Stopped",comment:"Transport"))
    }
    private var accessiblePads:some View {ScrollView{
        LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:10){ForEach(0..<16,id:\.self){pad in
            Button{session.hit(pad)}label:{HStack(spacing:10){Text(String(format:"%02d",pad+1)).font(.caption.monospaced()).foregroundStyle(Color.drums).accessibilityHidden(true);Text(LocalizedStringKey(Compiler.padNames[pad])).font(.headline);Spacer(minLength:0)}.frame(maxWidth:.infinity,minHeight:72).padding(12).background(Color.panel,in:RoundedRectangle(cornerRadius:14,style:.continuous)).overlay{RoundedRectangle(cornerRadius:14,style:.continuous).strokeBorder(Color.drums.opacity(0.3),lineWidth:0.8)}}.buttonStyle(StudioQuietButtonStyle()).foregroundStyle(Color.studioText)
        }}
    }.frame(minHeight:240).disabled(session.performance.replaying)}
    private func padGrid(height:CGFloat)->some View {
        GeometryReader{geo in
            let side=max(44,min((geo.size.width-24)/4,(geo.size.height-24)/4))
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:8),count:4),spacing:8){ForEach(0..<16,id:\.self){pad in
                JamPadFace(pad:pad,isDown:pressed.contains(pad),compact:height<280)
                    .equatable()
                    .frame(maxWidth:.infinity,alignment:.leading).frame(height:side).contentShape(Rectangle())
                    .accessibilityHidden(true)
            }}.frame(maxHeight:.infinity,alignment:.center)
                .overlay{PadTouchSurface(enabled:scenePhase == .active && !session.performance.replaying,trace:session.runtimeTraceEnabled,velocityFromTouch:session.padVelocityFromTouch,haptics:padHaptics,onHit:{pad,time,velocity in session.hit(pad,touchTime:time,velocity:velocity)},onHeld:{pressed=$0;session.padsHeld($0)})}
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
            HStack{Menu{ForEach(0..<16,id:\.self){i in Button(LocalizedStringKey(Compiler.padNames[i])){selectedPad=i}}}label:{Label(LocalizedStringKey(Compiler.padNames[selectedPad]),systemImage:"waveform").font(.subheadline.weight(.semibold)).foregroundStyle(Color.drums).frame(minHeight:44)};Spacer();Picker("Bar",selection:$stepBar){ForEach(0..<(drumPattern?.length ?? barTicks)/barTicks,id:\.self){i in Text("Bar \(i+1)").tag(i)}}.frame(width:dynamicType.isAccessibilitySize ? 150:110)}
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:6),count:4),spacing:10){ForEach(0..<16,id:\.self){step in
                let tick=stepBar*barTicks+step*240
                let exists=drumPattern?.drums.contains(where:{$0.pad==selectedPad && $0.tick==tick}) ?? false
                Button{toggleStep(tick)}label:{VStack(spacing:9){Text(String(step+1)).font(.system(size:11,weight:.medium,design:.monospaced));RoundedRectangle(cornerRadius:3).fill(exists ? Color.drums:Color.raised).frame(height:26)}.foregroundStyle(exists ? Color.drums:Color.muted).padding(8).frame(height:61).background(exists ? Color.drums.opacity(0.12):Color.ink.opacity(0.6),in:RoundedRectangle(cornerRadius:10,style:.continuous)).overlay{RoundedRectangle(cornerRadius:10,style:.continuous).strokeBorder(exists ? Color.drums.opacity(0.8):Color.outline.opacity(0.55),lineWidth:0.7)}}.buttonStyle(StudioQuietButtonStyle()).accessibilityLabel("Step \(step+1)").accessibilityValue(LocalizedStringKey(exists ? "On":"Off")).accessibilityIdentifier("jam.step.\(step)")
            }}
            VStack(alignment:.leading,spacing:8){HStack{SmallHeading(text:"VELOCITY");Spacer();Text(String(Int(velocity))).font(.system(size:12,design:.monospaced)).foregroundStyle(Color.drums).monospacedDigit()};Slider(value:$velocity,in:1...127,step:1).tint(.drums);Button("Apply velocity to this bar"){guard let id=drumPattern?.id else{return};session.edit{p in if let i=p.patterns.firstIndex(where:{$0.id==id}){for n in p.patterns[i].drums.indices where p.patterns[i].drums[n].pad==selectedPad && p.patterns[i].drums[n].tick/barTicks==stepBar{p.patterns[i].drums[n].velocity=Int(velocity)}}}}.font(.caption).frame(minHeight:44)}
        }.padding(14).modifier(StudioSurface())
    }
    func toggleStep(_ tick: Int){guard let pattern=drumPattern else{return};session.edit{p in guard let i=p.patterns.firstIndex(where:{$0.id==pattern.id})else{return};if p.patterns[i].drums.contains(where:{$0.pad==selectedPad && $0.tick==tick}){p.patterns[i].drums.removeAll(where:{$0.pad==selectedPad && $0.tick==tick})}else{p.patterns[i].drums.append(DrumEvent(tick:tick,pad:selectedPad,velocity:Int(velocity)))}}}
}

/// Pure presentation: the shared native surface owns note onset and held contacts.
/// Equatable faces keep unchanged pads out of the contact-driven view work.
private struct JamPadFace:View,Equatable {
    let pad:Int
    let isDown:Bool
    let compact:Bool
    var body:some View {
        VStack(alignment:.leading,spacing:0){
            HStack(alignment:.top){
                Text(String(format:"%02d",pad+1)).font(StudioTypography.index).foregroundStyle(isDown ? Color.ink.opacity(0.72):Color.muted)
                Spacer(minLength:0)
                // Rest-state accent: the pad's colour at 35 %, full when played.
                Capsule().fill(isDown ? Color.ink.opacity(0.65):Color.drums.opacity(0.35)).frame(width:compact ? 12:18,height:3).padding(.top,3)
            }
            Spacer(minLength:4)
            Text(LocalizedStringKey(Compiler.padNames[pad])).font(StudioTypography.pad).lineLimit(1).minimumScaleFactor(0.85).foregroundStyle(isDown ? Color.ink:Color.studioText)
        }
        .padding(compact ? 8:10)
        .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.leading)
        // Luz instrument: opaque, raised; lit from inside in the drum colour on contact.
        .litInstrument(.drums,isDown:isDown,radius:compact ? Luz.Radius.cell:Luz.Radius.pad)
    }
}

private struct JamUtilitySurface:ViewModifier {
    func body(content:Content)->some View {
        content.font(.caption.weight(.semibold)).foregroundStyle(Color.studioText)
            .frame(minHeight:44).padding(.horizontal,12)
            .background(Color.raised.opacity(0.45),in:RoundedRectangle(cornerRadius:12,style:.continuous))
            .overlay{RoundedRectangle(cornerRadius:12,style:.continuous).strokeBorder(Color.outline.opacity(0.6),lineWidth:0.6)}
    }
}

/// I06/I07: quantize strength and swing for recorded hits; the live sound is never delayed.
private struct QuantizeFeelMenu: View {
    @Bindable var session: Session
    var body: some View {
        Picker("Strength", selection: $session.quantizeStrength) {
            Text(verbatim: "100%").tag(1.0)
            Text(verbatim: "75%").tag(0.75)
            Text(verbatim: "50%").tag(0.5)
        }
        Picker("Swing", selection: $session.swing) {
            Text("Straight").tag(0.5)
            Text(verbatim: "54%").tag(0.54)
            Text(verbatim: "58%").tag(0.58)
            Text(verbatim: "62%").tag(0.62)
            Text("Triplet").tag(2.0 / 3.0)
        }
    }
}

/// I12: the lesson's grid and the score of the current drum clip against it.
private struct DrumLessonPanel: View {
    let lesson: DrumLesson
    let played: [DrumEvent]
    let bars: Int
    let close: () -> Void
    var body: some View {
        let score = lesson.score(played, bars: bars)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SmallHeading(text: "LESSON")
                Text(LocalizedStringKey(lesson.title)).font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                Button("Close lesson", action: close).font(.caption).frame(minHeight: 44)
            }
            ForEach(lesson.notation, id: \.self) { Text(verbatim: $0).font(.system(size: 12, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.7) }
            Text(String(format: NSLocalizedString("Record %d bars: %d%% · %d hit · %d missed · %d extra", comment: "Drum lesson score"), bars, score.accuracy, score.hit, score.missed, score.extra))
                .font(.caption.monospacedDigit()).foregroundStyle(score.accuracy >= 90 ? Color.mint : Color.muted)
                .accessibilityIdentifier("jam.lesson.score")
        }.padding(12).modifier(StudioSurface())
    }
}
