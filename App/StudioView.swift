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
                HStack(spacing:0){tab("square.grid.3x3","Grid",0);tab("square.grid.2x2.fill","Jam",1);tab("slider.vertical.3","Mixer",2)}.padding(.top,5).background(Color.panel)
            }
        }.background(Color.ink).foregroundStyle(.primary)
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
        Button{session.presentEditor(.settings)}label:{VStack(alignment:.leading,spacing:4){Text(session.displayProject.name).font(.headline).lineLimit(1);Text("\(Int(session.displayProject.bpm)) BPM · \(session.displayProject.keyName)").font(.caption).foregroundStyle(Color.muted)}}.buttonStyle(.plain).frame(maxWidth:.infinity,alignment:.leading)
        IconButton(symbol:"arrow.uturn.backward",label:"Undo"){session.undo()}.disabled(!session.history.canUndo || session.recording || session.armed)
        IconButton(symbol:"arrow.uturn.forward",label:"Redo"){session.redo()}.disabled(!session.history.canRedo || session.recording || session.armed)
        IconButton(symbol:"square.and.arrow.up",label:"Export"){session.finishTake();session.exportTake=nil;session.sheet = .export}.accessibilityIdentifier("export.open")
    }.padding(.horizontal,8).frame(minHeight:58).background(Color.panel)}
    private var compactSidebar:some View {VStack(spacing:4){
        Button{session.togglePlay()}label:{Image(systemName:session.audio.playing ? "stop.fill":"play.fill").font(.title2).foregroundStyle(Color.ink).frame(width:72,height:48).background(Color.mint,in:RoundedRectangle(cornerRadius:12))}.accessibilityLabel(session.audio.playing ? "Stop":"Play")
        HStack(spacing:0){IconButton(symbol:"backward.end.fill",label:"Return to start"){session.rewind()};IconButton(symbol:session.recording ? "stop.circle.fill":"record.circle",label:session.recording ? "Finish drum take":"Record drums",color:.record){session.record()}.disabled(session.performance.contextActive)}
        HStack(spacing:0){IconButton(symbol:"repeat",label:"Toggle loop",color:session.loop ? .mint:.muted){session.setLoop(enabled:!session.loop)}.disabled(session.performance.contextActive);Button{if session.performance.contextActive{session.sheet = .perform}}label:{Text(String(format:"%02d:%d",Int(session.audio.tick)/barTicks+1,Int(session.audio.tick)%barTicks/ppq+1)).font(.caption.monospaced()).frame(minWidth:44,minHeight:44)}.accessibilityIdentifier("perform.transport")}
        tab("square.grid.3x3","Grid",0);tab("square.grid.2x2.fill","Jam",1);tab("slider.vertical.3","Mixer",2)
        Spacer(minLength:0)
    }.padding(.top,6).frame(width:104).background(Color.panel)}
    var header: some View {
        VStack(spacing:8){
            HStack(spacing:6){
                IconButton(symbol:"square.stack.3d.up",label:"Projects",color:.mint){session.sheet = .projects}
                VStack(alignment:.leading,spacing:3){Text(session.displayProject.name).font(.system(size:19,weight:.semibold)).lineLimit(1);HStack(spacing:5){Circle().fill(session.saveError == nil ? Color.mint : .record).frame(width:4,height:4);Text(LocalizedStringKey(session.saveError != nil ? "Save failed" : session.saving ? "Saving…" : session.savedRevision==session.project.revision ? "Saved on this iPhone" : "Unsaved changes")).font(.system(size:10)).foregroundStyle(Color.muted)}.onTapGesture{Task{await session.save()}}}
                Spacer(minLength:0)
                IconButton(symbol:"arrow.uturn.backward",label:"Undo"){session.undo()}.disabled(!session.history.canUndo || session.recording || session.armed).opacity(session.history.canUndo ? 1:0.3)
                IconButton(symbol:"arrow.uturn.forward",label:"Redo"){session.redo()}.disabled(!session.history.canRedo || session.recording || session.armed).opacity(session.history.canRedo ? 1:0.3)
                IconButton(symbol:"square.and.arrow.up",label:"Export"){session.finishTake();session.exportTake=nil;session.sheet = .export}.accessibilityIdentifier("export.open")
            }
            HStack{Button{session.presentEditor(.settings)}label:{HStack(spacing:7){Text(String(format:"%.0f",session.displayProject.bpm)).font(.system(size:14,weight:.semibold,design:.monospaced));Text("BPM").font(.system(size:9,weight:.semibold)).foregroundStyle(Color.muted);Image(systemName:"chevron.down").font(.system(size:8))}.frame(minHeight:34)}.buttonStyle(.plain)
                Rectangle().fill(Color.raised).frame(width:1,height:16).padding(.horizontal,8)
                Button{session.presentEditor(.settings)}label:{Text(session.displayProject.keyName).font(.system(size:12,weight:.medium)).frame(minHeight:34)}.buttonStyle(.plain)
                Spacer();Text("4/4").font(.system(size:12,design:.monospaced)).foregroundStyle(Color.muted)
                CapsuleLabel(text:"LOCAL",color:.mint)
            }.padding(.horizontal,15)
        }.padding(.horizontal,8).padding(.bottom,9).background(Color.panel).overlay(alignment:.bottom){Rectangle().fill(Color.raised).frame(height:1)}
    }
    var transport: some View {
        VStack(spacing:0){Rectangle().fill(Color.raised).frame(height:1)
            HStack(spacing:7){
                IconButton(symbol:"backward.end.fill",label:"Return to start",color:.muted){session.rewind()}
                Button{session.togglePlay()}label:{Image(systemName:session.audio.playing ? "stop.fill":"play.fill").font(.system(size:22,weight:.semibold)).foregroundStyle(Color.ink).frame(width:54,height:48).background(Color.mint,in:RoundedRectangle(cornerRadius:14))}.accessibilityLabel(session.audio.playing ? "Stop":"Play")
                IconButton(symbol:session.recording ? "stop.circle.fill":"record.circle",label:session.recording ? "Finish drum take":"Record drums",color:.record){session.tab=1;session.record()}.background(session.recording || session.armed ? Color.record.opacity(0.15):Color.clear,in:RoundedRectangle(cornerRadius:12)).disabled(session.performance.contextActive)
                Button{if session.performance.contextActive{session.sheet = .perform}}label:{VStack(alignment:.leading,spacing:4){Text(String(format:"%02d : %d",Int(session.audio.tick)/barTicks+1,Int(session.audio.tick)%barTicks/ppq+1)).font(.system(size:20,weight:.medium,design:.monospaced)).monospacedDigit();Text(LocalizedStringKey(session.performance.contextActive ? (session.performance.recording ? "REC · PERFORM":session.performance.replaying ? "TAKE REPLAY":"PERFORM") : session.armed ? "COUNT IN" : session.recording ? "REC · DRUMS" : session.pending ? "PENDING · NEXT BAR" : session.audio.playing ? "PLAYING":"STOPPED")).font(.system(size:8,weight:.semibold,design:.monospaced)).foregroundStyle(session.recording || session.armed ? Color.record:Color.muted)}.frame(maxWidth:.infinity,alignment:.leading)}.buttonStyle(.plain).accessibilityIdentifier("perform.transport")
                IconButton(symbol:"repeat",label:"Toggle loop",color:session.loop ? .mint:.muted){session.setLoop(enabled:!session.loop)}.background(session.loop ? Color.mint.opacity(0.08):Color.clear,in:RoundedRectangle(cornerRadius:12)).disabled(session.performance.contextActive)
            }.padding(.horizontal,10).padding(.vertical,12)
        }.background(Color.panel)
    }
    func tab(_ symbol: String,_ label: LocalizedStringKey,_ index: Int)->some View {Button{session.tab=index}label:{VStack(spacing:5){Image(systemName:symbol).font(.system(size:18));Text(label).font(.system(size:10,weight:.semibold))}.foregroundStyle(session.tab==index ? Color.mint:Color.muted).frame(maxWidth:.infinity,minHeight:49)}.buttonStyle(.plain)}
}
