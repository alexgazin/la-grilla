import SwiftUI
import MusicDomain

struct PerformView:View {
    @Bindable var session:Session
    @Environment(\.dynamicTypeSize) private var dynamicType
    @State private var showMore=false
    private var live:PerformanceController{session.performance}
    private var project:Project{session.displayProject}
    var body:some View {
        NavigationStack {
            ScrollView {VStack(alignment:.leading,spacing:16){
                status
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:8){ForEach(project.sections){section in sectionPad(section)}}
                if let error=live.error{Text(LocalizedStringKey(error)).foregroundStyle(Color.record).font(.caption).accessibilityIdentifier("perform.error")}
                if let notice=live.notice{Text(LocalizedStringKey(notice)).foregroundStyle(Color.muted).font(.caption)}
                effects
                HStack(spacing:10){
                    Button{live.toggleRepeat()}label:{Label(LocalizedStringKey(live.repeating ? "Release repeat":"Repeat fragment"),systemImage:"repeat")}.buttonStyle(StudioActionStyle(color:live.repeating ? .drums:.mint,prominent:live.repeating)).accessibilityIdentifier("perform.repeat")
                    Picker("Repeat length",selection:Binding(get:{live.repeatSize},set:{live.setRepeatSize($0)})){Text("¼").tag(240);Text("½").tag(480);Text("1").tag(960);Text("2 beats").tag(1920)}.pickerStyle(.menu).labelsHidden().fixedSize(horizontal:true,vertical:false).frame(minWidth:60,minHeight:48)
                }.disabled(!live.playing || live.replaying)
                if let take=session.project.performanceTake{savedTake(take)}
                DisclosureGroup("More controls",isExpanded:$showMore){VStack(alignment:.leading,spacing:16){
                    VStack(alignment:.leading,spacing:8){SmallHeading(text:"BEAT JUMP");HStack{ForEach([-4,-1,1,4],id:\.self){beats in Button(LocalizedStringKey(beats>0 ? "+\(beats)":"\(beats)")){live.jump(beats)}.frame(maxWidth:.infinity,minHeight:44).background(Color.raised,in:RoundedRectangle(cornerRadius:10))}}}.disabled(!live.playing || live.replaying)
                    Text("Release returns to the source position that kept moving underneath.").font(.caption).foregroundStyle(Color.muted)
                    VStack(alignment:.leading,spacing:8){SmallHeading(text:"LIVE MIX");ForEach(Array(project.tracks.enumerated()),id:\.element.id){index,track in Toggle(track.displayName,isOn:Binding(get:{!session.displayProject.tracks[index].mute},set:{on in session.mixerImmediate{$0.tracks[index].mute = !on}})).tint(.mint)};Button("Save mixer & FX snapshot"){session.commitPerformanceMix();live.notice="Mixer and effects saved to the project."}.frame(minHeight:44).disabled(live.recording)}.disabled(!live.contextActive || live.replaying)
                    Text("Record starts again at the selected section. Up to 64 bars; a new take replaces the previous one with Undo.").font(.caption).foregroundStyle(Color.muted)
                }.padding(.top,14)}.font(.subheadline).padding(14).modifier(StudioSurface())
            }.padding(18)}.background(Color.ink)
            .safeAreaInset(edge:.bottom){transport}
            .navigationTitle("Perform").navigationBarTitleDisplayMode(.inline)
            .toolbar{ToolbarItem(placement:.cancellationAction){Button("Done"){session.sheet=nil}.accessibilityIdentifier("perform.done")};ToolbarItem(placement:.primaryAction){Button("Panic"){live.panic();session.pollPerformance()}.foregroundStyle(Color.record).accessibilityIdentifier("perform.panic")}}
        }.presentationDetents([.large])
    }
    private var status:some View {HStack(alignment:.top){VStack(alignment:.leading,spacing:6){
        Text(LocalizedStringKey(live.recording ? "RECORDING":live.replaying ? "TAKE REPLAY":"YOUR SECTIONS. YOUR SET.")).font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(live.recording ? Color.record:Color.muted).accessibilityIdentifier("perform.mode")
        Text(live.activeSectionID.flatMap{id in project.sections.first{$0.id==id}?.name} ?? session.section.name).font(.system(.title,weight:.semibold)).tracking(-0.6)
        Text(LocalizedStringKey(live.queuedSectionID == nil ? "Launches on the next bar":String(format:NSLocalizedString("Queued · %.1f beats",comment:"Section queue"),live.beatsToLaunch))).font(.caption).foregroundStyle(Color.muted)
    };Spacer();Text(String(format:"%02d:%02d",Int(live.seconds)/60,Int(live.seconds)%60)).font(.system(.title3,design:.monospaced,weight:.medium)).foregroundStyle(live.recording ? Color.record:Color.mint)}}
    private var transport:some View {VStack(spacing:7){
        HStack(spacing:8){
            Button{if live.playing || live.starting{Task{await live.stop();session.pollPerformance()}}else{session.startPerformance(record:false)}}label:{Label(LocalizedStringKey(live.playing || live.starting ? "Stop":"Play live"),systemImage:live.playing || live.starting ? "stop.fill":"play.fill")}.buttonStyle(StudioActionStyle(prominent:!live.playing)).accessibilityIdentifier("perform.play").disabled(live.stopping)
            Button{if live.recording{live.stopRecording()}else{session.startPerformance(record:true)}}label:{Label(LocalizedStringKey(live.recording ? "Finish take":"Record take"),systemImage:live.recording ? "stop.circle":"record.circle")}.buttonStyle(StudioActionStyle(color:.record,prominent:live.recording)).accessibilityIdentifier("perform.record").disabled(live.starting || live.stopping)
        }
        Button("Return to editing"){Task{await session.leavePerformance();session.sheet=nil}}.font(.caption).foregroundStyle(Color.muted).frame(maxWidth:.infinity,minHeight:44).accessibilityIdentifier("perform.edit")
    }.padding(.horizontal,18).padding(.top,10).background(Color.ink).overlay(alignment:.top){Rectangle().fill(Color.outline.opacity(0.6)).frame(height:0.5)}}
    private func sectionPad(_ section:MusicDomain.Section)->some View {
        let active=(live.contextActive ? live.activeSectionID:session.section.id)==section.id,queued=live.queuedSectionID==section.id
        return Button{if live.playing{live.queueSection(section.id)}else{session.selectedSection=section.id;session.startPerformance(record:false)}}label:{VStack(alignment:.leading,spacing:8){HStack{Text(section.name).font(.headline).lineLimit(1);Spacer();Image(systemName:queued ? "clock":active ? "waveform":"play.fill")};Text(LocalizedStringKey(queued ? "QUEUED · TAP TO CANCEL":active ? (live.playing ? "ACTIVE":"SELECTED"):String(format:NSLocalizedString("%d BARS",comment:"Section length"),section.length/barTicks))).font(.system(.caption2,design:.monospaced,weight:.semibold))}.foregroundStyle(queued ? Color.drums:active ? Color.ink:Color.studioText).padding(14).frame(maxWidth:.infinity,minHeight:80,alignment:.leading).background(active && !queued ? Color.mint:Color.panel,in:RoundedRectangle(cornerRadius:16,style:.continuous)).overlay{RoundedRectangle(cornerRadius:16,style:.continuous).stroke(queued ? Color.drums:Color.outline.opacity(active ? 0:0.65),lineWidth:queued ? 2:0.6)}}.buttonStyle(StudioQuietButtonStyle()).disabled(live.replaying || live.starting || live.stopping).accessibilityIdentifier("perform.section.\(section.name)")
    }
    @ViewBuilder private var effects:some View {
        if dynamicType.isAccessibilitySize{VStack(spacing:10){filter;delay}}else{HStack(alignment:.top,spacing:10){filter;delay}.fixedSize(horizontal:false,vertical:true)}
    }
    private var filter:some View {VStack(alignment:.leading,spacing:4){
        HStack(spacing:0){Label("Master filter",systemImage:"line.3.horizontal.decrease").font(.caption.weight(.semibold)).lineLimit(2);Spacer(minLength:0);IconButton(symbol:"arrow.counterclockwise",label:"Reset master filter",color:.mint){live.setEffects(filter:0)}.accessibilityIdentifier("perform.filter.reset")}.frame(minHeight:44)
        FilterKnob(value:Binding(get:{live.fx.filter},set:{live.setEffects(filter:$0)}))
        HStack{Text("LOW PASS");Spacer();Text("HIGH PASS")}.font(.system(size:11,design:.monospaced)).foregroundStyle(Color.muted).frame(minHeight:28,alignment:.bottom)
    }.padding(12).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.top).modifier(StudioSurface()).disabled(!live.contextActive || live.replaying)}
    private var delay:some View {VStack(alignment:.leading,spacing:4){
        Label("Delay wet",systemImage:"circle.dotted.circle").font(.caption.weight(.semibold)).lineLimit(2).frame(minHeight:44,alignment:.leading)
        Text(String(format:"%.0f%%",live.fx.delayWet*100)).font(.system(.title3,design:.monospaced,weight:.medium)).frame(maxWidth:.infinity,minHeight:44,alignment:.leading)
        Spacer(minLength:0)
        Slider(value:Binding(get:{live.fx.delayWet},set:{live.setEffects(delay:$0)}),in:0...0.5).tint(.mint).frame(minHeight:44).accessibilityLabel("Delay wet")
        Text("PING-PONG · ⅛").font(.system(size:11,design:.monospaced)).foregroundStyle(Color.muted).lineLimit(1).frame(minHeight:28,alignment:.bottom).accessibilityLabel("PING-PONG DELAY · ⅛ NOTE")
    }.padding(12).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.top).modifier(StudioSurface()).disabled(!live.contextActive || live.replaying)}
    private func savedTake(_ take:PerformanceTake)->some View {VStack(alignment:.leading,spacing:9){
        HStack{SmallHeading(text:"SAVED PERFORMANCE");Spacer();Text(String(format:"%.1f s",take.durationSeconds)).font(.caption.monospaced()).foregroundStyle(Color.muted)}
        Text(take.name).font(.subheadline.weight(.semibold)).lineLimit(1)
        Text("\(take.events.count) events · source revision \(take.sourceRevision)").font(.caption2).foregroundStyle(Color.muted).accessibilityIdentifier("perform.saved")
        HStack(spacing:8){
            Button{session.replayPerformance(take)}label:{Label("Replay take",systemImage:"play.circle")}.buttonStyle(StudioActionStyle(prominent:false)).accessibilityIdentifier("perform.replay").disabled(live.recording || live.starting || live.stopping)
            Menu{Button("Export take WAV"){export(take,"wav")}.accessibilityIdentifier("perform.wav");Button("Export take MIDI"){export(take,"midi")}.accessibilityIdentifier("perform.midi")}label:{Label("Export",systemImage:"square.and.arrow.up").font(.subheadline.weight(.medium)).frame(minWidth:80,minHeight:48)}.disabled(live.recording).accessibilityIdentifier("perform.export")
        }
    }.padding(14).modifier(StudioSurface())}
    private func export(_ take:PerformanceTake,_ format:String){session.exportTake=take;session.exportPreset=format;session.sheet = .export}
}
