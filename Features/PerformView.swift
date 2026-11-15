import SwiftUI
import MusicDomain

struct PerformView:View {
    @Bindable var session:Session
    private var live:PerformanceController{session.performance}
    private var project:Project{session.displayProject}
    var body:some View {
        NavigationStack {
            ScrollView {VStack(alignment:.leading,spacing:22){
                status
                HStack(spacing:12){
                    Button{if live.playing || live.starting{Task{await live.stop();session.pollPerformance()}}else{session.startPerformance(record:false)}}label:{Label(live.playing ? "Stop":"Play live",systemImage:live.playing ? "stop.fill":"play.fill").frame(maxWidth:.infinity,minHeight:48)}.tint(.mint).accessibilityIdentifier("perform.play")
                    Button{if live.recording{live.stopRecording()}else{session.startPerformance(record:true)}}label:{Label(live.recording ? "Finish take":"Record take",systemImage:live.recording ? "stop.circle":"record.circle").frame(maxWidth:.infinity,minHeight:48)}.tint(.record).accessibilityIdentifier("perform.record").disabled(live.starting)
                }.buttonStyle(.bordered)
                Text("Record starts again at the selected section. Up to 64 bars; a new take replaces the previous one with Undo.").font(.caption).foregroundStyle(Color.muted)
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:10){ForEach(project.sections){section in sectionPad(section)}}
                if let error=live.error{Text(error).foregroundStyle(Color.record).font(.caption).accessibilityIdentifier("perform.error")}
                if let notice=live.notice{Text(notice).foregroundStyle(Color.muted).font(.caption)}
                effects
                HStack{SmallHeading(text:"BEAT JUMP");Spacer();ForEach([-4,-1,1,4],id:\.self){beats in Button(beats>0 ? "+\(beats)":"\(beats)"){live.jump(beats)}.frame(minWidth:44,minHeight:44).background(Color.raised,in:RoundedRectangle(cornerRadius:8))}}.disabled(!live.playing || live.replaying)
                VStack(alignment:.leading,spacing:10){
                    SmallHeading(text:"BEAT REPEAT")
                    Picker("Repeat length",selection:Binding(get:{live.repeatSize},set:{live.setRepeatSize($0)})){Text("¼").tag(240);Text("½").tag(480);Text("1").tag(960);Text("2 beats").tag(1920)}.pickerStyle(.segmented)
                    Button{live.toggleRepeat()}label:{Label(live.repeating ? "Release repeat":"Repeat fragment",systemImage:"repeat").frame(maxWidth:.infinity,minHeight:46)}.buttonStyle(.bordered).tint(live.repeating ? .drums:.mint).accessibilityIdentifier("perform.repeat")
                    Text("Release returns to the source position that kept moving underneath.").font(.caption).foregroundStyle(Color.muted)
                }.disabled(!live.playing || live.replaying)
                VStack(alignment:.leading,spacing:8){SmallHeading(text:"LIVE MIX");ForEach(Array(project.tracks.enumerated()),id:\.element.id){i,track in Toggle(track.displayName,isOn:Binding(get:{!session.displayProject.tracks[i].mute},set:{on in session.mixerImmediate{$0.tracks[i].mute = !on}})).tint(.mint)};Button("Save mixer & FX snapshot"){session.commitPerformanceMix();live.notice="Mixer and effects saved to the project."}.frame(minHeight:44).disabled(live.recording)}.disabled(!live.contextActive || live.replaying)
                if let take=session.project.performanceTake{savedTake(take)}
                Button("Return to editing"){Task{await session.leavePerformance();session.sheet=nil}}.frame(maxWidth:.infinity,minHeight:44).accessibilityIdentifier("perform.edit")
            }.padding(22)}.background(Color.panel)
            .navigationTitle("Perform").navigationBarTitleDisplayMode(.inline)
            .toolbar{ToolbarItem(placement:.cancellationAction){Button("Done"){session.sheet=nil}.accessibilityIdentifier("perform.done")};ToolbarItem(placement:.primaryAction){Button("Panic"){live.panic();session.pollPerformance()}.foregroundStyle(Color.record).accessibilityIdentifier("perform.panic")}}
        }.presentationDetents([.large])
    }
    private var status:some View {HStack(alignment:.top){VStack(alignment:.leading,spacing:6){SmallHeading(text:live.recording ? "RECORDING":live.replaying ? "TAKE REPLAY":"YOUR SECTIONS. YOUR SET.");Text(live.activeSectionID.flatMap{id in project.sections.first{$0.id==id}?.name} ?? session.section.name).font(.system(size:28,weight:.medium));Text(live.queuedSectionID == nil ? "Launches on the next bar" : String(format:"Queued · %.1f beats",live.beatsToLaunch)).font(.caption).foregroundStyle(Color.muted)};Spacer();Text(String(format:"%02d:%02d",Int(live.seconds)/60,Int(live.seconds)%60)).font(.system(.title3,design:.monospaced)).foregroundStyle(live.recording ? Color.record:Color.mint)}.accessibilityIdentifier("perform.status")}
    private func sectionPad(_ section:MusicDomain.Section)->some View {
        let active=(live.contextActive ? live.activeSectionID:session.section.id)==section.id,queued=live.queuedSectionID==section.id
        return Button{if live.playing{live.queueSection(section.id)}else{session.selectedSection=section.id;session.startPerformance(record:false)}}label:{VStack(alignment:.leading,spacing:9){HStack{Text(section.name).font(.headline).lineLimit(1);Spacer();Image(systemName:queued ? "clock":active ? "waveform":"play.fill")};Text(queued ? "QUEUED · TAP TO CANCEL":active ? "ACTIVE":"\(section.length/barTicks) BARS").font(.system(size:9,weight:.semibold,design:.monospaced))}.foregroundStyle(queued ? Color.drums:active ? Color.ink:Color.white).padding(16).frame(maxWidth:.infinity,minHeight:92,alignment:.leading).background(active && !queued ? Color.mint:Color.raised,in:RoundedRectangle(cornerRadius:14)).overlay{RoundedRectangle(cornerRadius:14).stroke(queued ? Color.drums:Color.clear,lineWidth:2)}}.buttonStyle(.plain).disabled(live.replaying || live.starting).accessibilityIdentifier("perform.section.\(section.name)")
    }
    private var effects:some View {VStack(alignment:.leading,spacing:16){
        HStack{SmallHeading(text:"MASTER FILTER");Spacer();Button("Reset"){live.setEffects(filter:0)}.frame(minHeight:44)}
        HStack{Text("LOW PASS");Spacer();Text(abs(live.fx.filter)<0.001 ? "BYPASS":String(format:"%+.0f%%",live.fx.filter*100));Spacer();Text("HIGH PASS")}.font(.system(size:9,design:.monospaced)).foregroundStyle(Color.muted)
        Slider(value:Binding(get:{live.fx.filter},set:{live.setEffects(filter:$0)}),in:-1...1).tint(.mint).accessibilityLabel("Master filter").accessibilityIdentifier("perform.filter")
        HStack{SmallHeading(text:"PING-PONG DELAY · ⅛ NOTE");Spacer();Text(String(format:"%.0f%%",live.fx.delayWet*100)).font(.caption.monospaced())}
        Slider(value:Binding(get:{live.fx.delayWet},set:{live.setEffects(delay:$0)}),in:0...0.5).tint(.mint).accessibilityLabel("Delay wet")
    }.padding(16).background(Color.raised,in:RoundedRectangle(cornerRadius:14)).disabled(!live.contextActive || live.replaying)}
    private func savedTake(_ take:PerformanceTake)->some View {VStack(alignment:.leading,spacing:12){
        SmallHeading(text:"SAVED PERFORMANCE")
        HStack{Text(take.name).font(.headline);Spacer();Text(String(format:"%.1f s",take.durationSeconds)).font(.caption.monospaced())}
        Text("\(take.events.count) events · source revision \(take.sourceRevision)").font(.caption).foregroundStyle(Color.muted).accessibilityIdentifier("perform.saved")
        Button{session.replayPerformance(take)}label:{Label("Replay take",systemImage:"play.circle").frame(minHeight:44)}.accessibilityIdentifier("perform.replay").disabled(live.recording || live.starting)
        HStack{Button("Export take WAV"){export(take,"wav")}.accessibilityIdentifier("perform.wav");Spacer();Button("Export take MIDI"){export(take,"midi")}.accessibilityIdentifier("perform.midi")}.frame(minHeight:44).disabled(live.recording)
    }.padding(16).background(Color.raised,in:RoundedRectangle(cornerRadius:14))}
    private func export(_ take:PerformanceTake,_ format:String){session.exportTake=take;session.exportPreset=format;session.sheet = .export}
}
