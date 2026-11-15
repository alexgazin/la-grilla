import SwiftUI
import MusicDomain
struct StudioView: View {
    @Bindable var session: Session
    @Environment(\.verticalSizeClass) private var verticalSize
    var body: some View {
        VStack(spacing:0){
            if let error=session.audio.error {HStack{Image(systemName:"speaker.slash");Text(LocalizedStringKey(error)).font(.caption);Button("Retry"){_ = session.ensureAudio()}}.padding(12).background(Color.record.opacity(0.15))}
            if let error=session.saveError {HStack{Text(LocalizedStringKey(error)).font(.caption);Button("Retry"){Task{await session.save()}};Button("Save copy"){Task{await session.saveCopy()}}}.padding(12).background(Color.record.opacity(0.15))}
            if verticalSize == .compact {
                HStack(spacing:0){VStack(spacing:0){compactHeader;workspace.frame(maxWidth:.infinity,maxHeight:.infinity)};compactSidebar}
            }else{
                header;workspace.frame(maxWidth:.infinity,maxHeight:.infinity);transport
                HStack(spacing:4){tab("square.grid.3x3","Grid",0);tab("square.grid.2x2.fill","Jam",1);tab("slider.vertical.3","Mixer",2)} .padding(6).modifier(StudioNavigationSurface()).padding(.horizontal,12).padding(.bottom,4).background(Color.ink)
            }
        }.background(Color.ink).foregroundStyle(Color.studioText)
        .sheet(item:$session.sheet,onDismiss:{if let url=session.exportedURL{session.shareURL=url;session.exportedURL=nil}}){sheet in Group{switch sheet {
        case .projects: ProjectsView(session:session)
        case .newProject: NewProjectView(session:session)
        case .export: ExportView(session:session)
        case .settings: SettingsView(session:session)
        case .bass: BassView(session:session)
        case .sections: SectionsView(session:session)
        case .notes: PianoRollView(session:session)
        case .harmony: HarmonyLabView(session:session)
        case .assistant: AssistantView(session:session)
        case .voice: VoiceToMIDIView(session:session)
        case .perform: PerformView(session:session)
        case .midiDevices: MIDIDevicesView(session:session)
        }}.modifier(StudioQATypeSize()).presentationDragIndicator(.visible).presentationBackground(Color.panel)}
        .sheet(isPresented:Binding(get:{session.shareURL != nil},set:{if !$0 {session.shareURL=nil}}),onDismiss:{session.finishSharing()}){if let url=session.shareURL{ShareView(url:url)}}
        .alert("La Grilla",isPresented:Binding(get:{session.message != nil},set:{if !$0{session.message=nil}})){Button("OK"){session.message=nil}}message:{Text(LocalizedStringKey(session.message ?? ""))}

    }
    @ViewBuilder var workspace: some View {
        switch session.tab {
        case 1: JamView(session:session)
        case 2: MixerView(session:session)
        default: GridView(session:session)
        }
    }
    private var compactHeader:some View {HStack(spacing:4){
        IconButton(symbol:"square.stack.3d.up",label:"Projects",color:.mint){session.sheet = .projects}
        Button{session.presentEditor(.settings)}label:{VStack(alignment:.leading,spacing:4){Text(session.displayProject.name).font(.headline).lineLimit(1);Text("\(Int(session.displayProject.bpm)) BPM · \(session.displayProject.keyName)").font(.caption).foregroundStyle(Color.muted)}}.buttonStyle(StudioQuietButtonStyle()).frame(maxWidth:.infinity,alignment:.leading)
        IconButton(symbol:"arrow.uturn.backward",label:"Undo"){session.undo()}.disabled(!session.history.canUndo || session.recording || session.armed)
        IconButton(symbol:"arrow.uturn.forward",label:"Redo"){session.redo()}.disabled(!session.history.canRedo || session.recording || session.armed)
        IconButton(symbol:"square.and.arrow.up",label:"Export"){session.finishTake();session.exportTake=nil;session.sheet = .export}.accessibilityIdentifier("export.open")
    }.padding(.horizontal,8).frame(minHeight:58).background(Color.panel)}
    private var compactSidebar:some View {VStack(spacing:4){
        Button{session.togglePlay()}label:{Image(systemName:session.audio.playing ? "stop.fill":"play.fill").font(.title2).foregroundStyle(Color.ink).frame(width:72,height:48).background(Color.mint,in:RoundedRectangle(cornerRadius:12))}.accessibilityLabel(session.audio.playing ? "Stop":"Play")
        HStack(spacing:0){IconButton(symbol:"backward.end.fill",label:"Return to start"){session.rewind()};IconButton(symbol:session.recording ? "stop.circle.fill":"record.circle",label:session.recording ? "Finish drum take":"Record drums",color:.record){session.record()}.disabled(session.performance.contextActive).opacity(session.performance.contextActive ? 0.35:1)}
        HStack(spacing:0){IconButton(symbol:"repeat",label:"Toggle loop",color:session.loop ? .mint:.muted){session.setLoop(enabled:!session.loop)}.disabled(session.performance.contextActive).opacity(session.performance.contextActive ? 0.35:1);Button{if session.performance.contextActive{session.sheet = .perform}}label:{Text(String(format:"%02d:%d",Int(session.audio.tick)/barTicks+1,Int(session.audio.tick)%barTicks/ppq+1)).font(.caption.monospaced()).frame(minWidth:44,minHeight:44)}.accessibilityIdentifier("perform.transport")}
        tab("square.grid.3x3","Grid",0);tab("square.grid.2x2.fill","Jam",1);tab("slider.vertical.3","Mixer",2)
        Spacer(minLength:0)
    }.padding(.top,6).frame(width:104).background(Color.panel)}
    var header: some View {
        HStack(spacing:4){
            Button{session.sheet = .projects}label:{StudioMark().frame(width:44,height:44)}.buttonStyle(StudioQuietButtonStyle()).accessibilityLabel("Projects")
            VStack(alignment:.leading,spacing:0){
                HStack(spacing:6){Text(session.displayProject.name).font(.system(size:20,weight:.semibold)).tracking(-0.5).lineLimit(1);Circle().fill(session.saveError == nil ? Color.mint:Color.record).frame(width:5,height:5).accessibilityLabel(LocalizedStringKey(session.saveError != nil ? "Save failed":session.saving ? "Saving…":session.savedRevision==session.project.revision ? "Saved on this iPhone":"Unsaved changes"))}
                Button{session.presentEditor(.settings)}label:{HStack(spacing:6){Text("\(Int(session.displayProject.bpm)) BPM");Text("·");Text(session.displayProject.keyName);Image(systemName:"chevron.down").font(.system(size:11))}.font(.system(size:11,weight:.medium,design:.monospaced)).foregroundStyle(Color.muted).lineLimit(1).minimumScaleFactor(1).frame(minHeight:44,alignment:.leading)}.buttonStyle(StudioQuietButtonStyle())
            }.frame(maxWidth:.infinity,alignment:.leading)
            IconButton(symbol:"arrow.uturn.backward",label:"Undo"){session.undo()}.disabled(!session.history.canUndo || session.recording || session.armed).opacity(session.history.canUndo ? 1:0.3)
            IconButton(symbol:"arrow.uturn.forward",label:"Redo"){session.redo()}.disabled(!session.history.canRedo || session.recording || session.armed).opacity(session.history.canRedo ? 1:0.3)
            IconButton(symbol:"square.and.arrow.up",label:"Export"){session.finishTake();session.exportTake=nil;session.sheet = .export}.accessibilityIdentifier("export.open")
        }.padding(.horizontal,8).padding(.top,7).padding(.bottom,2)
    }
    var transport: some View {
        HStack(spacing:4){
            Button{if session.performance.contextActive{session.sheet = .perform}}label:{VStack(alignment:.leading,spacing:3){Text(String(format:"%02d : %d",Int(session.audio.tick)/barTicks+1,Int(session.audio.tick)%barTicks/ppq+1)).font(.system(size:23,weight:.semibold,design:.monospaced)).monospacedDigit();Text(LocalizedStringKey(session.performance.contextActive ? (session.performance.recording ? "REC · PERFORM":session.performance.replaying ? "TAKE REPLAY":"PERFORM") : session.armed ? "COUNT IN" : session.recording ? "REC · DRUMS" : session.pending ? "PENDING · NEXT BAR" : session.audio.playing ? "PLAYING":"STOPPED")).font(.system(size:11,weight:.medium,design:.monospaced)).foregroundStyle(session.recording || session.armed ? Color.record:Color.muted)}.frame(maxWidth:.infinity,minHeight:52,alignment:.leading)}.buttonStyle(StudioQuietButtonStyle()).accessibilityIdentifier("perform.transport")
            IconButton(symbol:"backward.end.fill",label:"Return to start",color:.muted){session.rewind()}
            Button{session.togglePlay()}label:{Image(systemName:session.audio.playing ? "stop.fill":"play.fill").font(.system(size:22,weight:.semibold)).foregroundStyle(Color.ink).frame(width:58,height:58).background(Color.mint,in:Circle())}.buttonStyle(StudioQuietButtonStyle()).accessibilityLabel(LocalizedStringKey(session.audio.playing ? "Stop":"Play"))
            IconButton(symbol:session.recording ? "stop.circle.fill":"record.circle",label:session.recording ? "Finish drum take":"Record drums",color:.record){session.tab=1;session.record()}.background(session.recording || session.armed ? Color.record.opacity(0.12):Color.clear,in:Circle()).disabled(session.performance.contextActive).opacity(session.performance.contextActive ? 0.35:1)
            IconButton(symbol:"repeat",label:"Toggle loop",color:session.loop ? .mint:.muted){session.setLoop(enabled:!session.loop)}.disabled(session.performance.contextActive).opacity(session.performance.contextActive ? 0.35:1)
        }.padding(.horizontal,18).padding(.vertical,10).background(Color.ink)
    }
    func tab(_ symbol: String,_ label: LocalizedStringKey,_ index: Int)->some View {Button{session.tab=index}label:{HStack(spacing:7){Image(systemName:symbol).font(.system(size:17,weight:.medium)).accessibilityHidden(true);Text(label).font(.system(size:11,weight:.semibold))}.foregroundStyle(session.tab==index ? Color.mint:Color.muted).frame(maxWidth:.infinity,minHeight:44).background(session.tab==index ? Color.mint.opacity(0.1):Color.clear,in:RoundedRectangle(cornerRadius:11))}.buttonStyle(StudioQuietButtonStyle()).accessibilityAddTraits(session.tab==index ? .isSelected:[]).overlay(alignment:.bottom){Capsule().fill(Color.mint).frame(width:16,height:2).opacity(session.tab==index ? 1:0).padding(.bottom,2)}}
}
