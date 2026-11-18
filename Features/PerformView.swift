import SwiftUI
import MusicDomain
import UIKit
import AVFAudio

struct PerformView:View {
    @Bindable var session:Session
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var showMore=false
    @State private var showTilt=false
    @State private var makingSong = false
    @State private var tilt=TiltFilterController()
    @State private var tiltOrientation=UIInterfaceOrientation.portrait
    @State private var tiltTarget=TiltTarget.filter
    @State private var tiltVolumeAnchor=TiltVolumeAnchor()
    private enum TiltTarget:Equatable,Sendable {case filter,volume}
    private var live:PerformanceController{session.performance}
    private var project:Project{session.displayProject}
    var body:some View {
        NavigationStack {
            ScrollViewReader {scroll in
            ScrollView {VStack(alignment:.leading,spacing:16){
                status
                LazyVGrid(columns:dynamicType.isAccessibilitySize ? [GridItem(.flexible())]:[GridItem(.flexible()),GridItem(.flexible())],spacing:8){ForEach(project.sections){section in sectionPad(section)}}
                if let error=live.error{Text(LocalizedStringKey(error)).foregroundStyle(Color.record).font(.caption).accessibilityIdentifier("perform.error")}
                if let notice=live.notice{Text(LocalizedStringKey(notice)).foregroundStyle(Color.muted).font(.caption)}
                effects.id("perform.effects")
                HStack(spacing:10){
                    Button{live.toggleRepeat()}label:{Label(LocalizedStringKey(live.repeating ? "Release repeat":"Repeat fragment"),systemImage:"repeat")}.buttonStyle(StudioActionStyle(color:live.repeating ? .drums:.mint,prominent:live.repeating)).accessibilityIdentifier("perform.repeat")
                    Picker("Repeat length",selection:Binding(get:{live.repeatSize},set:{live.setRepeatSize($0)})){Text("¼").tag(240);Text("½").tag(480);Text("1").tag(960);Text("2 beats").tag(1920)}.pickerStyle(.menu).labelsHidden().fixedSize(horizontal:true,vertical:false).frame(minWidth:60,minHeight:48)
                }.disabled(!live.playing || live.replaying)
                if let take=session.project.performanceTake{savedTake(take)}
                DisclosureGroup("Tilt control",isExpanded:$showTilt){tiltControl.padding(.top,10)}
                    .padding(14).modifier(StudioSurface()).accessibilityIdentifier("perform.tilt.options")
                DisclosureGroup("More controls",isExpanded:$showMore){VStack(alignment:.leading,spacing:16){
                    VStack(alignment:.leading,spacing:8){SmallHeading(text:"BEAT JUMP");HStack{ForEach([-4,-1,1,4],id:\.self){beats in Button(LocalizedStringKey(beats>0 ? "+\(beats)":"\(beats)")){live.jump(beats)}.frame(maxWidth:.infinity,minHeight:44).background(Color.raised,in:RoundedRectangle(cornerRadius:10))}}}.disabled(!live.playing || live.replaying)
                    Text("Release returns to the source position that kept moving underneath.").font(.caption).foregroundStyle(Color.muted)
                    VStack(alignment:.leading,spacing:8){SmallHeading(text:"LIVE MIX");ForEach(Array(project.tracks.enumerated()),id:\.element.id){index,track in Toggle(track.displayName,isOn:Binding(get:{!session.displayProject.tracks[index].mute},set:{on in session.mixerImmediate{$0.tracks[index].mute = !on}})).tint(.mint)};Button("Save mixer & FX snapshot"){session.commitPerformanceMix();live.notice="Mixer and effects saved to the project."}.frame(minHeight:44).disabled(live.recording)}.disabled(!live.contextActive || live.replaying)
                    Text("Record starts again at the selected section. Up to 64 bars; a new take replaces the previous one with Undo.").font(.caption).foregroundStyle(Color.muted)
                }.padding(.top,14)}.font(.subheadline).padding(14).modifier(StudioSurface())
            }.padding(18)}.background(Color.ink)
            .safeAreaInset(edge:.bottom){transport{
                scroll.scrollTo("perform.effects",anchor:.top)
            }}
            }
            .navigationTitle("Perform").navigationBarTitleDisplayMode(.inline)
            .toolbar{ToolbarItem(placement:.cancellationAction){Button("Done"){tilt.stop();session.sheet=nil}.accessibilityIdentifier("perform.done")};ToolbarItem(placement:.primaryAction){Button("Panic"){tilt.stop();live.panic();session.pollPerformance()}.foregroundStyle(Color.record).accessibilityIdentifier("perform.panic")}}
        }.disabled(makingSong).presentationDetents([.large])
        // A downward effect/scroll gesture must not close a running set.
        // Done and Return to editing remain explicit navigation controls.
        .interactiveDismissDisabled(makingSong || live.playing || live.starting || live.recording || live.replaying)
        .background(PerformOrientationReader{next in
            if next != tiltOrientation,tilt.active{tilt.stop(notice:"Screen rotated. Enable tilt again to set a new neutral position.")}
            tiltOrientation=next
        }.allowsHitTesting(false).accessibilityHidden(true))
        .onDisappear{tilt.stop()}
        .onChange(of:showTilt){_,expanded in if !expanded{tilt.stop()}}
        .onChange(of:scenePhase){_,phase in if phase != .active{tilt.stop()}}
        .onChange(of:canUseTilt){_,allowed in if !allowed{tilt.stop()}}
        .onReceive(NotificationCenter.default.publisher(for:UIApplication.willResignActiveNotification).receive(on:RunLoop.main)){_ in tilt.stop()}
        .onReceive(NotificationCenter.default.publisher(for:AVAudioSession.interruptionNotification).receive(on:RunLoop.main)){_ in tilt.stop()}
        .onReceive(NotificationCenter.default.publisher(for:AVAudioSession.mediaServicesWereResetNotification).receive(on:RunLoop.main)){_ in tilt.stop()}
    }
    private var status:some View {HStack(alignment:.top){VStack(alignment:.leading,spacing:6){
        Text(live.activeSectionID.flatMap{id in project.sections.first{$0.id==id}?.name} ?? session.section.name).font(.system(.title,weight:.semibold)).tracking(-0.6)
        Text(LocalizedStringKey(live.queuedSectionID == nil ? "Launches on the next bar":String(format:NSLocalizedString("Queued · %.1f beats",comment:"Section queue"),live.beatsToLaunch))).font(.caption).foregroundStyle(Color.muted)
    };Spacer();Text(String(format:"%02d:%02d",Int(live.seconds)/60,Int(live.seconds)%60)).font(.system(.title3,design:.monospaced,weight:.medium)).foregroundStyle(live.recording ? Color.record:Color.mint)}}
    private func transport(focusEffects:@escaping ()->Void)->some View {VStack(spacing:7){
        Text(LocalizedStringKey(live.recording ? "RECORDING":live.replaying ? "TAKE REPLAY":"YOUR SECTIONS. YOUR SET."))
            .font(.caption2.weight(.semibold)).tracking(1)
            .foregroundStyle(live.recording ? Color.record:Color.muted)
            .frame(maxWidth:.infinity,alignment:.leading)
            .accessibilityIdentifier("perform.mode")
        if verticalSizeClass == .compact {
            // Keep the workspace usable in landscape at large text sizes.
            // Labels remain available to VoiceOver on these icon controls.
            HStack(spacing:8){playButton(focusEffects:focusEffects);recordButton;replayButton(focusEffects:focusEffects);editButton}.labelStyle(.iconOnly)
        }else{
            HStack(spacing:8){playButton(focusEffects:focusEffects);recordButton}
            HStack(spacing:12){replayButton(focusEffects:focusEffects);editButton}
        }
    }.padding(.horizontal,18).padding(.top,10).background(Color.ink).overlay(alignment:.top){Rectangle().fill(Color.outline.opacity(0.6)).frame(height:0.5)}}
    private func playButton(focusEffects:@escaping ()->Void)->some View {
        Button{
            tilt.stop()
            if live.playing || live.starting{Task{await live.stop();session.pollPerformance()}}
            else{if dynamicType.isAccessibilitySize && !showTilt{focusEffects()};session.startPerformance(record:false)}
        }label:{Label(LocalizedStringKey(live.playing || live.starting ? "Stop":"Play live"),systemImage:live.playing || live.starting ? "stop.fill":"play.fill")}
            .buttonStyle(StudioActionStyle(prominent:!live.playing)).accessibilityIdentifier("perform.play").disabled(live.stopping)
    }
    private var recordButton:some View {
        Button{tilt.stop();if live.recording{live.stopRecording()}else{session.startPerformance(record:true)}}label:{Label(LocalizedStringKey(live.recording ? "Finish take":"Record take"),systemImage:live.recording ? "stop.circle":"record.circle")}
            .buttonStyle(StudioActionStyle(color:.record,prominent:live.recording)).accessibilityIdentifier("perform.record").disabled(live.starting || live.stopping)
    }
    @ViewBuilder private func replayButton(focusEffects:@escaping ()->Void)->some View {
        if let take=session.project.performanceTake {
            Button{tilt.stop();focusEffects();session.replayPerformance(take)}label:{Label("Replay take",systemImage:"play.circle").font(.caption.weight(.semibold)).frame(maxWidth:.infinity,minHeight:44)}
                .foregroundStyle(Color.mint).accessibilityIdentifier("perform.replay")
                .disabled(live.recording || live.starting || live.stopping)
        }
    }
    private var editButton:some View {
        Button{tilt.stop();Task{await session.leavePerformance();session.sheet=nil}}label:{Label("Return to editing",systemImage:"arrow.left").font(.caption).frame(maxWidth:.infinity,minHeight:44)}
            .foregroundStyle(Color.muted).accessibilityIdentifier("perform.edit")
    }
    private func sectionPad(_ section:MusicDomain.Section)->some View {
        let active=(live.contextActive ? live.activeSectionID:session.section.id)==section.id,queued=live.queuedSectionID==section.id
        return Button{if live.playing{live.queueSection(section.id)}else{session.selectedSection=section.id;session.startPerformance(record:false)}}label:{VStack(alignment:.leading,spacing:8){HStack{Text(section.name).font(.headline).lineLimit(dynamicType.isAccessibilitySize ? 3:1).fixedSize(horizontal:false,vertical:true);Spacer();Image(systemName:queued ? "clock":active ? "waveform":"play.fill")};Text(LocalizedStringKey(queued ? "QUEUED · TAP TO CANCEL":active ? (live.playing ? "ACTIVE":"SELECTED"):String(format:NSLocalizedString("%d BARS",comment:"Section length"),section.length/barTicks))).font(.system(.caption2,design:.monospaced,weight:.semibold))}.foregroundStyle(queued ? Color.drums:active ? Color.ink:Color.studioText).padding(14).frame(maxWidth:.infinity,minHeight:80,alignment:.leading).background(active && !queued ? Color.mint:Color.panel,in:RoundedRectangle(cornerRadius:16,style:.continuous)).overlay{RoundedRectangle(cornerRadius:16,style:.continuous).stroke(queued ? Color.drums:Color.outline.opacity(active ? 0:0.65),lineWidth:queued ? 2:0.6)}}.buttonStyle(StudioQuietButtonStyle()).disabled(live.replaying || live.starting || live.stopping).accessibilityIdentifier("perform.section.\(section.name)")
    }
    @ViewBuilder private var effects:some View {
        if dynamicType.isAccessibilitySize{VStack(spacing:10){filter;delay}}else{HStack(alignment:.top,spacing:10){filter;delay}.fixedSize(horizontal:false,vertical:true)}
    }
    private var filter:some View {VStack(alignment:.leading,spacing:4){
        Label("Master filter",systemImage:"line.3.horizontal.decrease").font(.caption.weight(.semibold)).lineLimit(2)
        FilterKnob(value:Binding(get:{live.fx.filter},set:{tilt.stop();live.setEffects(filter:$0)}))
            // The 112-point dial owns its touch surface, not the full card.
            // In a wide accessibility layout the remaining area scrolls.
            .frame(width:112,height:112)
            .frame(maxWidth:.infinity,alignment:dynamicType.isAccessibilitySize ? .leading:.center)
        HStack{Text("LOW PASS");Spacer();Text("HIGH PASS")}.font(.system(size:11,design:.monospaced)).foregroundStyle(Color.muted).frame(minHeight:28,alignment:.bottom)
        // Keep Reset with the dial when the heading scrolls under the bar.
        Button{tilt.stop();live.setEffects(filter:0)}label:{Label("Reset master filter",systemImage:"arrow.counterclockwise").font(.caption.weight(.medium)).frame(maxWidth:.infinity,minHeight:44)}
            .foregroundStyle(Color.mint).accessibilityIdentifier("perform.filter.reset")
    }.padding(12).frame(maxWidth:.infinity,minHeight:240,alignment:.top).modifier(StudioSurface()).disabled(!live.contextActive || live.replaying)}
    private var canUseTilt:Bool{
        scenePhase == .active && live.contextActive && live.playing && !live.replaying && !live.starting && !live.stopping && live.audio.playing && live.audio.isPrepared
    }
    private var tiltControl:some View {VStack(alignment:.leading,spacing:10){
        Toggle(isOn:Binding(get:{tilt.active},set:{enabled in if enabled{startTilt()}else{tilt.stop()}})){
            Label("Tilt control",systemImage:"move.3d").font(.subheadline.weight(.semibold))
        }.tint(.mint).frame(minHeight:44).disabled(!canUseTilt || !tilt.available).accessibilityIdentifier("perform.tilt.enabled")
        StudioSegments(title:"Tilt target",selection:Binding(get:{tiltTarget},set:{tilt.stop();tiltTarget=$0}),options:[(.filter,"Filter"),(.volume,"Volume")]).accessibilityIdentifier("perform.tilt.target")
        if tiltTarget == .volume {
            HStack{Text("Master volume").font(.caption).foregroundStyle(Color.muted);Spacer();Text(String(format:"%+.1f dB",live.runtimeProject?.master ?? project.master)).font(.caption.monospaced().weight(.semibold)).monospacedDigit()}.accessibilityElement(children:.combine).accessibilityIdentifier("perform.tilt.master-volume")
        }
        if tilt.active {
            GeometryReader{geometry in
                ZStack {
                    Capsule().fill(Color.raised).frame(height:6)
                    Rectangle().fill(Color.muted).frame(width:1,height:14)
                    Circle().fill(Color.mint).frame(width:16,height:16).offset(x:CGFloat(tilt.deflection)*max(0,geometry.size.width/2-8))
                }.frame(maxWidth:.infinity,maxHeight:.infinity)
            }.frame(height:22).accessibilityHidden(true)
            HStack {
                Text(LocalizedStringKey(tilt.calibrating ? "Finding neutral position…":tiltTarget == .filter ? "Tilt gently to shape the filter.":"Tilt gently to change the master volume.")).font(.caption).foregroundStyle(Color.muted)
                Spacer(minLength:8)
                Button("Set neutral"){calibrateTilt()}.font(.caption.weight(.semibold)).frame(minHeight:44).disabled(tilt.calibrating).accessibilityIdentifier("perform.tilt.calibrate")
            }
        } else {
            Text(LocalizedStringKey(!tilt.available ? "Tilt is unavailable on this device.":canUseTilt ? "Hold the phone comfortably, then enable tilt.":"Start live playback to use tilt.")).font(.caption).foregroundStyle(Color.muted)
        }
        if let notice=tilt.notice{Text(LocalizedStringKey(notice)).font(.caption).foregroundStyle(Color.muted).accessibilityIdentifier("perform.tilt.notice")}
    }}
    private func calibrateTilt(){
        if tiltTarget == .volume {
            guard let master=live.runtimeProject?.master,master.isFinite else{return}
            tiltVolumeAnchor.baseline=master;tiltVolumeAnchor.expected=master
            tilt.calibrate(filter:0)
        }else{tilt.calibrate(filter:live.fx.filter)}
    }
    private func startTilt(){
        guard canUseTilt else{return}
        let axis:TiltFilterController.Axis
        switch tiltOrientation {
        case .landscapeLeft:axis = .landscapeLeft
        case .landscapeRight:axis = .landscapeRight
        case .portraitUpsideDown:axis = .portraitInverted
        default:axis = .portrait
        }
        let performance=live,motion=tilt,target=tiltTarget,anchor=tiltVolumeAnchor
        if target == .volume {
            guard let master=performance.runtimeProject?.master,master.isFinite else{return}
            anchor.baseline=master;anchor.expected=master
        }
        tilt.start(filter:target == .filter ? live.fx.filter:0,axis:axis){[weak performance,weak motion] value in
            guard let performance,performance.contextActive,performance.playing,!performance.replaying,!performance.starting,!performance.stopping,performance.audio.playing,performance.audio.isPrepared else{motion?.stop();return}
            if target == .filter{performance.setEffects(filter:value)}else{
                // A manual/MIDI master change takes control until tilt is
                // explicitly enabled again. The anchor never owns this view.
                guard let current=performance.runtimeProject?.master,abs(current-anchor.expected)<0.0001 else{motion?.stop();return}
                let master=min(6,max(-61,anchor.baseline+value*12))
                guard abs(master-current)>=0.0001 else{return}
                do{try performance.editMix{$0.master=master};anchor.expected=master}
                catch{motion?.stop(notice:"Tilt stopped. You can enable it again.")}
            }
        }
    }
    private var delay:some View {VStack(alignment:.leading,spacing:4){
        Label("Delay wet",systemImage:"circle.dotted.circle").font(.caption.weight(.semibold)).lineLimit(2).frame(minHeight:44,alignment:.leading)
        Text(String(format:"%.0f%%",live.fx.delayWet*100)).font(.system(.title3,design:.monospaced,weight:.medium)).frame(maxWidth:.infinity,minHeight:44,alignment:.leading)
        Spacer(minLength:0)
        Slider(value:Binding(get:{live.fx.delayWet},set:{live.setEffects(delay:$0)}),in:0...0.5).tint(.mint).frame(minHeight:44).accessibilityLabel("Delay wet")
        Text("PING-PONG · ⅛").font(.system(size:11,design:.monospaced)).foregroundStyle(Color.muted).lineLimit(1).frame(minHeight:28,alignment:.bottom).accessibilityLabel("PING-PONG DELAY · ⅛ NOTE")
    }.padding(12).frame(maxWidth:.infinity,minHeight:240,alignment:.top).modifier(StudioSurface()).disabled(!live.contextActive || live.replaying)}
    private func savedTake(_ take:PerformanceTake)->some View {VStack(alignment:.leading,spacing:9){
        HStack{SmallHeading(text:"SAVED PERFORMANCE");Spacer();Text(String(format:"%.1f s",take.durationSeconds)).font(.caption.monospaced()).foregroundStyle(Color.muted)}
        Text(take.name).font(.subheadline.weight(.semibold)).lineLimit(1)
        Text("\(take.events.count) events · source revision \(take.sourceRevision)").font(.caption2).foregroundStyle(Color.muted).accessibilityIdentifier("perform.saved")
        HStack(spacing:8){
            Menu{Button("Export take WAV"){export(take,"wav")}.accessibilityIdentifier("perform.wav");Button("Export take MIDI"){export(take,"midi")}.accessibilityIdentifier("perform.midi")}label:{Label("Export",systemImage:"square.and.arrow.up").font(.subheadline.weight(.medium)).frame(minWidth:80,minHeight:48)}.disabled(live.recording).accessibilityIdentifier("perform.export")
        }
        Button {
            tilt.stop()
            makingSong = true
            Task {
                _ = await session.createFromPerformance(take)
                makingSong = false
            }
        } label: {
            if makingSong { ProgressView("Creating editable song…") }
            else { Label("Create editable song", systemImage: "rectangle.split.3x1") }
        }
        .buttonStyle(StudioActionStyle(prominent: false))
        .disabled(makingSong || live.playing || live.recording || live.replaying || live.starting || live.stopping)
        .accessibilityIdentifier("perform.create-song")
        Text("Creates a project from the played sections and parts. The exact live mix stays in the take.")
            .font(.caption).foregroundStyle(Color.muted)
    }.padding(14).modifier(StudioSurface())}
    private func export(_ take:PerformanceTake,_ format:String){tilt.stop();session.exportTake=take;session.exportPreset=format;session.sheet = .export}
}

@MainActor private final class TiltVolumeAnchor {
    var baseline=0.0
    var expected=0.0
}

/// Reads this presentation's actual interface orientation, including when the
/// phone is flat and UIDevice reports faceUp instead of a screen orientation.
private struct PerformOrientationReader:UIViewRepresentable {
    let changed:@MainActor (UIInterfaceOrientation)->Void
    func makeUIView(context:Context)->OrientationView{let view=OrientationView();view.backgroundColor = .clear;view.isOpaque=false;view.changed=changed;return view}
    func updateUIView(_ view:OrientationView,context:Context){view.changed=changed}
    static func dismantleUIView(_ view:OrientationView,coordinator:Void){view.changed=nil}
    final class OrientationView:UIView {
        var changed:(@MainActor (UIInterfaceOrientation)->Void)?
        private var reported:UIInterfaceOrientation?
        override func didMoveToWindow(){super.didMoveToWindow();report()}
        override func layoutSubviews(){super.layoutSubviews();report()}
        private func report(){
            guard let orientation=window?.windowScene?.interfaceOrientation,orientation != .unknown,orientation != reported else{return}
            reported=orientation
            DispatchQueue.main.async{[weak self] in
                guard let self,self.reported==orientation else{return}
                self.changed?(orientation)
            }
        }
    }
}
