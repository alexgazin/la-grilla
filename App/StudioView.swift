import SwiftUI
import UIKit
import MusicDomain
struct StudioView: View {
    @Bindable var session: Session
    @AppStorage("studio.visualMetronome") private var visualMetronome=false
    @AppStorage("studio.recordLock") private var recordLock=false
    @AppStorage("studio.pitchSpelling") private var spellingValue=PitchSpelling.automatic.rawValue
    @Namespace private var tabPuck
    /// Sheets grow out of the control that opened them (Luz zoom transitions).
    @Namespace private var sheetZoom
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    private var displayedKeyName:String{
        let project=session.displayProject
        let root=MusicalNotation.pitchClassName(project.keyRoot,keyRoot:project.keyRoot,minor:project.minor,spelling:PitchSpelling(rawValue:spellingValue) ?? .automatic)
        return root+" "+NSLocalizedString(project.minor ? "minor":"major",comment:"Key mode")
    }
    @Environment(\.verticalSizeClass) private var verticalSize
    var body: some View {
        VStack(spacing:0){
            if let error=session.audio.error {LuzNotice(kind:.danger,symbol:"speaker.slash",text:LocalizedStringKey(error),actions:[("Retry",{_ = session.ensureAudio()})]).padding(.horizontal,8).padding(.top,6).transition(Luz.Transition.drop(reduceMotion))}
            if let error=session.saveError {LuzNotice(kind:.danger,text:LocalizedStringKey(error),actions:[("Retry",{Task{await session.save()}}),("Save copy",{Task{await session.saveCopy()}})]).padding(.horizontal,8).padding(.top,6).transition(Luz.Transition.drop(reduceMotion))}
            if verticalSize == .compact {
                HStack(spacing:0){VStack(spacing:0){compactHeader;workspaceStage};compactSidebar}
            }else{
                // U42: with the recording lock on, only the instrument and Stop respond while recording.
                header.disabled(recordLock && session.recording).opacity(recordLock && session.recording ? 0.45:1)
                workspaceStage
                QuickBar(session:session).disabled(recordLock && session.recording)
                console
            }
        }.animation(reduceMotion ? nil:Luz.Motion.morph,value:session.saveError).animation(reduceMotion ? nil:Luz.Motion.morph,value:session.audio.error)
        .background(Color.ink).foregroundStyle(Color.studioText)
        .overlay{if AudioRuntimeQA.enabled{AudioRuntimeQAView(session:session)}}
        .background{UndoGestureInstaller(undo:{session.gestureUndo(false)},redo:{session.gestureUndo(true)}).frame(width:0,height:0).accessibilityHidden(true)}
        .background{StudioKeyCommands(session:session)}
        .overlay(alignment:.top){if visualMetronome && session.audio.playing{VisualMetronome(session:session).allowsHitTesting(false)}}
        .background{BarAnnouncer(audio:session.audio)}
        .overlay(alignment:.bottom){ComfortCompanions(session:session)}
        .overlay(alignment:.top){if let toast=session.toast{Label(LocalizedStringKey(toast),systemImage:toast=="Undo" ? "arrow.uturn.backward":toast=="Redo" ? "arrow.uturn.forward":"checkmark.circle").font(.subheadline.weight(.semibold)).padding(.horizontal,16).padding(.vertical,10).modifier(StudioNavigationSurface()).padding(.top,8).transition(Luz.Transition.drop(reduceMotion)).accessibilityAddTraits(.updatesFrequently).allowsHitTesting(false)}}
        .animation(reduceMotion ? .easeOut(duration:0.15):Luz.Motion.morph,value:session.toast)
        .sheet(item:$session.sheet,onDismiss:{if let url=session.exportedURL{session.shareURL=url;session.exportedURL=nil}}){sheet in VStack(spacing:0){Group{switch sheet {
        case .projects: ProjectsView(session:session)
        case .trackBuilder: TrackBuilderView(session:session)
        case .newProject: NewProjectView(session:session)
        case .export: ExportView(session:session)
        case .settings: SettingsView(session:session)
        case .gettingStarted: GettingStartedView{session.sheet=nil}
        case .bass: BassView(session:session)
        case .sections: SectionsView(session:session)
        case .notes: PianoRollView(session:session)
        case .harmony: HarmonyLabView(session:session)
        case .assistant: AssistantView(session:session)
        case .voice: VoiceToMIDIView(session:session)
        case .perform: PerformView(session:session)
        case .midiDevices: MIDIDevicesView(session:session)
        case .palettes: PaletteView(session:session)
        case .history: HistoryView(session:session)
        case .versions: VersionsView(session:session)
        case .trash: TrashView(session:session)
        case .commands: CommandPaletteView(session:session)
        case .variations: VariationsView(session:session)
        case .comp: CompView(session:session)
        case .chordImport: ChordImportView(session:session)
        case .melodyIdeas: MelodyIdeasView(session:session)
        case .lyrics: LyricsView(session:session)
        case .master: MasterAssistView(session:session)
        case .mood: MoodProgressionsView(session:session)
        case .doctor: ArrangementDoctorView(session:session)
        case .earTraining: EarTrainingView(session:session)
        case .whatsNew: WhatsNewView(session:session)
        case .coNotes: CoAuthorNotesView(session:session)
        case .vj: StageVJView(session:session)
        case .help: HelpView(session:session)
        case .grooves: StarterGroovesView(session:session)
        case .beatMachine: BeatMachineView(session:session)
        case .tuner: TunerView(session:session)
        case .markers: MarkersView(session:session)
        case .automation: AutomationEditorView(session:session)
        case .dynamics: DynamicsView(session:session)
        case .practicePlayer: PracticePlayerView(session:session)
        }}.frame(maxHeight:.infinity);if [.bass,.palettes,.lyrics,.harmony].contains(sheet){SheetMiniTransport(session:session)}}
        .modifier(SheetZoom(sheet:sheet,namespace:sheetZoom)).modifier(StudioQATypeSize()).scrollContentBackground(.hidden).tint(.mint).presentationDragIndicator(.visible).presentationBackground(Color.panel).presentationCornerRadius(Luz.Radius.sheet)}
        .sheet(isPresented:Binding(get:{session.shareURL != nil},set:{if !$0 {session.shareURL=nil}}),onDismiss:{session.finishSharing()}){if let url=session.shareURL{ShareView(url:url)}}
        .alert("La Grilla",isPresented:Binding(get:{session.message != nil},set:{if !$0{session.message=nil}})){
            // U46: a message with a fix offers it as a button.
            if let action=MessageAction.suggested(for:session.message ?? ""){Button(action.title){action.perform(in:session)}.accessibilityIdentifier("message.action")}
            Button("OK"){session.message=nil}
        }message:{Text(LocalizedStringKey(session.message ?? ""))}
        // U16: a late route (Bluetooth, AirPlay, a measured delay over 60 ms) is named before recording.
        .alert("Record over this route?",isPresented:$session.routeWarningPending){
            Button("Record anyway"){session.recordAnyway()}.accessibilityIdentifier("route.record-anyway")
            Button("Calibrate"){session.routeWarningPending=false;session.presentEditor(.settings)}
            Button("Cancel",role:.cancel){session.routeWarningPending=false}
        }message:{Text("\(Text(LocalizedStringKey(session.routeKind.title))) adds about \(session.routeLatencyDisplay.milliseconds) ms, so recorded hits may land late. Wired headphones or the speaker are better for recording.")}

    }
    /// Grid, Jam and Mixer replace each other with a short cross-fade and settle (no blur:
    /// these are full screens and the transition must stay cheap).
    private var workspaceStage: some View {
        ZStack{
            workspace.id(session.tab)
                .transition(Luz.uiTesting ? .identity:reduceMotion ? .opacity:.opacity.combined(with:.scale(scale:0.985)))
        }.frame(maxWidth:.infinity,maxHeight:.infinity).clipped()
    }
    @ViewBuilder var workspace: some View {
        switch session.tab {
        case 1: JamView(session:session)
        case 2: MixerView(session:session)
        default: GridView(session:session)
        }
    }
    private var compactHeader:some View {HStack(spacing:4){
        IconButton(symbol:"square.stack.3d.up",label:"Projects",color:.mint){session.sheet = .projects}.luzZoomSource(Session.Sheet.projects,in:sheetZoom)
        Button{session.presentEditor(.settings)}label:{VStack(alignment:.leading,spacing:4){Text(session.displayProject.name).font(.headline).lineLimit(1);Text("\(Int(session.displayProject.bpm)) BPM · \(displayedKeyName)").font(.caption).foregroundStyle(Color.muted)}}.buttonStyle(StudioQuietButtonStyle()).frame(maxWidth:.infinity,alignment:.leading)
        HStack(spacing:0){
            IconButton(symbol:"arrow.uturn.backward",label:"Undo"){session.undo()}.disabled(!session.history.canUndo || session.recording || session.armed)
            IconButton(symbol:"arrow.uturn.forward",label:"Redo"){session.redo()}.disabled(!session.history.canRedo || session.recording || session.armed)
        }.contextMenu{historyMenu}
        IconButton(symbol:"magnifyingglass",label:"Search actions"){session.sheet = .commands}.keyboardShortcut("k",modifiers:.command).accessibilityIdentifier("commands.open")
        IconButton(symbol:"square.and.arrow.up",label:"Export"){session.finishTake();session.exportTake=nil;session.sheet = .export}.luzZoomSource(Session.Sheet.export,in:sheetZoom).accessibilityIdentifier("export.open")
    }.padding(.horizontal,8).frame(minHeight:58).background(Color.panel)}
    private var compactSidebar:some View {VStack(spacing:4){
        Button{session.togglePlay()}label:{Image(systemName:session.audio.playing ? "stop.fill":"play.fill").font(.title2.weight(.semibold)).contentTransition(.symbolEffect(.replace))}.buttonStyle(TransportKeyStyle(isOn:session.audio.playing,diameter:52)).accessibilityLabel(session.audio.playing ? "Stop":"Play")
        HStack(spacing:0){IconButton(symbol:"backward.end.fill",label:"Return to start"){session.rewind()};IconButton(symbol:session.recording ? "stop.circle.fill":"record.circle",label:session.recording ? "Finish drum take":"Record drums",color:.record){session.record()}.disabled(session.performance.contextActive).opacity(session.performance.contextActive ? 0.35:1)}
        HStack(spacing:0){IconButton(symbol:"repeat",label:"Toggle loop",color:session.loop ? .mint:.muted){session.setLoop(enabled:!session.loop)}.disabled(session.performance.contextActive).opacity(session.performance.contextActive ? 0.35:1);Button{if session.performance.contextActive{session.sheet = .perform}}label:{CompactPosition(audio:session.audio,bpm:session.project.bpm).frame(minWidth:44,minHeight:44)}.accessibilityIdentifier("perform.transport").accessibilityValue(Text(verbatim:session.runtimeTraceReport))}
        tab("square.grid.3x3","Grid",0);tab("square.grid.2x2","Jam",1);tab("slider.vertical.3","Mixer",2)
        Spacer(minLength:0)
    }.padding(.top,6).frame(width:104).background(Color.panel)}
    @ViewBuilder private var historyMenu:some View {
        Button("Edit history",systemImage:"clock.arrow.circlepath"){session.sheet = .history}
        Button("Song versions",systemImage:"bookmark"){session.sheet = .versions}
        Button("Recently deleted",systemImage:"trash"){session.sheet = .trash}
    }
    private var saveColor: Color {
        if session.saveError != nil { return .record }
        return session.saving || session.savedRevision != session.project.revision ? .muted : .mint
    }
    var header: some View {
        HStack(spacing:8){
            Button{session.sheet = .projects}label:{
                StudioMark().frame(width:44,height:44)
                    .background(Color.panel,in:RoundedRectangle(cornerRadius:Luz.Radius.card,style:.continuous))
                    .overlay{RoundedRectangle(cornerRadius:Luz.Radius.card,style:.continuous).strokeBorder(Color.outline.opacity(0.7),lineWidth:0.75)}
            }.buttonStyle(StudioQuietButtonStyle()).luzZoomSource(Session.Sheet.projects,in:sheetZoom).accessibilityLabel("Projects")
            VStack(alignment:.leading,spacing:0){
                HStack(spacing:6){
                    Text(session.displayProject.name).font(StudioTypography.title).tracking(-0.5).lineLimit(1)
                    // Luz: a status symbol, not colour alone.
                    Image(systemName:session.saveError != nil ? "exclamationmark.triangle.fill":session.saving || session.savedRevision != session.project.revision ? "circle.dotted":"checkmark.circle.fill")
                        .font(StudioTypography.index).foregroundStyle(saveColor)
                        .contentTransition(.symbolEffect(.replace))
                        .luzConfirm(session.savedRevision)
                        .accessibilityLabel(LocalizedStringKey(session.saveError != nil ? "Save failed":session.saving ? "Saving…":session.savedRevision==session.project.revision ? "Saved on this iPhone":"Unsaved changes"))
                }
                Button{session.presentEditor(.settings)}label:{
                    HStack(spacing:5){
                        Text("\(Int(session.displayProject.bpm)) BPM").monospacedDigit().luzNumeric(session.displayProject.bpm).animation(Luz.Motion.snap,value:Int(session.displayProject.bpm)).accessibilityIdentifier("studio.tempo")
                        Text("·").accessibilityHidden(true)
                        Text(displayedKeyName)
                        Image(systemName:"chevron.down").font(.system(.caption2, weight: .semibold)).accessibilityHidden(true)
                    }.font(StudioTypography.detail).foregroundStyle(Color.muted).lineLimit(1)
                        .frame(minHeight:44,alignment:.leading).contentShape(Rectangle())
                }.buttonStyle(StudioQuietButtonStyle()).luzZoomSource(Session.Sheet.settings,in:sheetZoom)
            }.frame(maxWidth:.infinity,alignment:.leading)
            HStack(spacing:0){
                IconButton(symbol:"arrow.uturn.backward",label:"Undo"){session.undo()}
                    .disabled(!session.history.canUndo || session.recording || session.armed).opacity(session.history.canUndo ? 1:0.3)
                IconButton(symbol:"arrow.uturn.forward",label:"Redo"){session.redo()}
                    .disabled(!session.history.canRedo || session.recording || session.armed).opacity(session.history.canRedo ? 1:0.3)
            }.background(Color.panel,in:RoundedRectangle(cornerRadius:Luz.Radius.card,style:.continuous))
                // U6 · U7: a long press on Undo/Redo opens the history and the song versions.
                .contextMenu{historyMenu}
            IconButton(symbol:"magnifyingglass",label:"Search actions"){session.sheet = .commands}
                .keyboardShortcut("k",modifiers:.command).accessibilityIdentifier("commands.open")
            IconButton(symbol:"square.and.arrow.up",label:"Export"){session.finishTake();session.exportTake=nil;session.sheet = .export}
                .background(Color.raised,in:RoundedRectangle(cornerRadius:Luz.Radius.card,style:.continuous)).luzZoomSource(Session.Sheet.export,in:sheetZoom).accessibilityIdentifier("export.open")
        }.padding(.horizontal,12).padding(.top,8).padding(.bottom,6)
    }
    var transport: some View {
        HStack(spacing:4){
            Button{if session.performance.contextActive{session.sheet = .perform}}label:{TransportReadout(session:session)}
                .buttonStyle(StudioQuietButtonStyle()).luzZoomSource(Session.Sheet.perform,in:sheetZoom).accessibilityIdentifier("perform.transport")
                .accessibilityValue(Text(verbatim:session.runtimeTraceReport))
            IconButton(symbol:"backward.end.fill",label:"Return to start",color:.muted){session.rewind()}
            Button{session.togglePlay()}label:{
                // Luz transport key: morphing symbol, press sink, gradient glow while playing.
                Image(systemName:session.audio.playing ? "stop.fill":"play.fill")
                    .font(.title2.weight(.semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .offset(x:session.audio.playing ? 0:2)
            }.buttonStyle(TransportKeyStyle(isOn:session.audio.playing)).accessibilityLabel(LocalizedStringKey(session.audio.playing ? "Stop":"Play"))
            IconButton(symbol:session.recording ? "stop.circle.fill":"record.circle",label:session.recording ? "Finish drum take":"Record drums",color:.record){session.tab=1;session.record()}.luzBreathe(session.armed)
                .background(session.recording || session.armed ? Color.record.opacity(0.16):Color.clear,in:Circle())
                .disabled(session.performance.contextActive).opacity(session.performance.contextActive ? 0.35:1)
            IconButton(symbol:"repeat",label:"Toggle loop",color:.muted,isOn:session.loop){session.setLoop(enabled:!session.loop)}
                .disabled(session.performance.contextActive).opacity(session.performance.contextActive ? 0.35:1)
        }.padding(.horizontal,12).padding(.top,10).padding(.bottom,8)
    }
    private var console: some View {
        VStack(spacing:0){
            transport
            Rectangle().fill(Color.outline.opacity(0.65)).frame(height:0.5).padding(.horizontal,12).accessibilityHidden(true)
            HStack(spacing:4){tab("square.grid.3x3","Grid",0);tab("square.grid.2x2","Jam",1);tab("slider.vertical.3","Mixer",2)}
                .padding(6)
        }.modifier(StudioNavigationSurface(solid:session.tab == 1)).padding(.horizontal,8).padding(.top,6).padding(.bottom,4)
    }
    func tab(_ symbol:String,_ label:LocalizedStringKey,_ index:Int)->some View {
        let selected=session.tab == index
        return Button{
            guard session.tab != index else{return}
            withAnimation(reduceMotion ? nil:Luz.Motion.snap){session.tab=index}
            Luz.Haptics.selection()
        }label:{
            HStack(spacing:7){
                Image(systemName:symbol).font(StudioTypography.icon).accessibilityHidden(true)
                    .symbolVariant(selected ? .fill:.none)
                    .contentTransition(.symbolEffect(.replace))
                Text(label).font(StudioTypography.label)
            }.foregroundStyle(selected ? Color.studioText:Color.muted)
                .frame(maxWidth:.infinity,minHeight:44)
                .background{
                    // Luz: one puck slides to the selected tab.
                    if selected{
                        Capsule(style:.continuous).fill(Color.raised)
                            .overlay(alignment:.bottom){Capsule().fill(Color.mint).frame(width:16,height:2).padding(.bottom,3)}
                            .matchedGeometryEffect(id:"tab",in:tabPuck)
                    }
                }
        }.buttonStyle(StudioQuietButtonStyle()).accessibilityAddTraits(selected ? .isSelected:[])
    }
}

/// Only this view reads the 30 Hz transport tick, so the studio shell does not re-render with it.
private struct TransportReadout: View {
    @Bindable var session: Session
    private var transportStatus: LocalizedStringKey {
        if session.performance.contextActive {
            return session.performance.recording ? "REC · PERFORM":session.performance.replaying ? "TAKE REPLAY":"PERFORM"
        }
        return session.armed ? "COUNT IN":session.recording ? "REC · DRUMS":session.pending ? "PENDING · NEXT BAR":session.audio.playing ? "PLAYING":"STOPPED"
    }
    var body: some View {
        VStack(alignment:.leading,spacing:4){
            HStack(alignment:.center,spacing:8){
                Text(String(format:"%02d : %d",Int(session.audio.tick)/barTicks+1,Int(session.audio.tick)%barTicks/ppq+1))
                    .font(StudioTypography.readout).tracking(-1).monospacedDigit()
                HStack(spacing:2){
                    ForEach(0..<4,id:\.self){beat in
                        Capsule().fill(session.audio.playing && Int(session.audio.tick)%barTicks/ppq == beat ? (session.armed || session.recording ? Color.record:Color.mint):Color.lifted)
                            .frame(width:4,height:beat == 0 ? 14:10)
                    }
                }.accessibilityHidden(true)
            }
            Text(transportStatus).font(StudioTypography.detail)
                .foregroundStyle(session.recording || session.armed ? Color.record:Color.muted).lineLimit(1)
        }.frame(maxWidth:.infinity,minHeight:52,alignment:.leading)
    }
}

/// Bar:beat for the landscape sidebar, isolated from the shell body.
/// U21 · U23 · Play, stop and undo without closing an editor sheet.
struct SheetMiniTransport: View {
    @Bindable var session: Session
    var body: some View {
        HStack(spacing: 4) {
            IconButton(symbol: "arrow.uturn.backward", label: "Undo") { session.undo() }
                .disabled(!session.history.canUndo || session.recording || session.armed).accessibilityIdentifier("sheet.undo")
            IconButton(symbol: "arrow.uturn.forward", label: "Redo") { session.redo() }
                .disabled(!session.history.canRedo || session.recording || session.armed).accessibilityIdentifier("sheet.redo")
            Spacer(minLength: 4)
            CompactPosition(audio: session.audio, bpm: session.project.bpm).foregroundStyle(Color.muted)
            Button { session.togglePlay() } label: {
                Image(systemName: session.audio.playing ? "stop.fill" : "play.fill").font(.headline).contentTransition(.symbolEffect(.replace))
                    .frame(width: 52, height: 44)
            }
            .buttonStyle(StudioActionStyle(color: .mint, prominent: !session.audio.playing))
            .disabled(session.harmonyPreview)
            .accessibilityLabel(LocalizedStringKey(session.audio.playing ? "Stop" : "Play"))
            .accessibilityIdentifier("sheet.play")
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.bar)
    }
}
struct CompactPosition: View {
    let audio: AudioController
    var bpm: Double = 120
    /// U68: minutes and seconds instead of bar and beat.
    @AppStorage("studio.showSeconds") private var showSeconds=false
    var body: some View {
        if showSeconds, audio.sampleRate > 0 {
            let seconds = Int(Double(audio.tick) / Double(ppq) * 60 / max(1, bpm))
            Text(String(format:"%d:%02d", seconds / 60, seconds % 60)).font(StudioTypography.index).monospacedDigit()
        } else { barBeat }
    }
    private var barBeat: some View {
        Text(String(format:"%02d:%d",Int(audio.tick)/barTicks+1,Int(audio.tick)%barTicks/ppq+1)).font(StudioTypography.index).monospacedDigit()
    }
}

/// Only sheets opened from a visible control zoom out of it; the rest keep the
/// standard sheet motion (a zoom without a source would have nowhere to return).
private struct SheetZoom: ViewModifier {
    let sheet: Session.Sheet
    let namespace: Namespace.ID
    func body(content: Content) -> some View {
        switch sheet {
        case .projects, .export, .settings, .perform: content.luzZoomDestination(sheet, in: namespace)
        default: content
        }
    }
}

/// U28 · A hardware keyboard on iPhone: space plays, R records, L loops, 1–3 switch tabs,
/// ⌘Z / ⇧⌘Z undo and redo, F focuses the section. Hold ⌘ to see them.
private struct StudioKeyCommands: View {
    @Bindable var session: Session
    var body: some View {
        // Labels differ from the visible buttons so UI tests and Full Keyboard Access
        // never see two "Undo" or "Record drums" buttons.
        Group {
            Button("Play or stop") { session.togglePlay() }.keyboardShortcut(.space, modifiers: [])
            Button("Start a drum take") { session.tab = 1; session.record() }.keyboardShortcut("r", modifiers: [])
            Button("Loop on or off") { session.setLoop(enabled: !session.loop) }.keyboardShortcut("l", modifiers: [])
            Button("Focus or leave the section") { session.toggleFocus() }.keyboardShortcut("f", modifiers: [])
            Button("Undo the last change") { session.undo() }.keyboardShortcut("z", modifiers: .command)
            Button("Redo the last change") { session.redo() }.keyboardShortcut("z", modifiers: [.command, .shift])
            Button("Repeat the last action") { session.run(.repeatLast) }.keyboardShortcut("y", modifiers: .command)
            // I53: page-turner pedals send Page Down / Page Up.
            Button("Start a drum take (pedal)") { session.tab = 1; session.record() }.keyboardShortcut(.pageDown, modifiers: [])
            Button("Undo the last change (pedal)") { session.undo() }.keyboardShortcut(.pageUp, modifiers: [])
            Button("Open Grid") { session.tab = 0 }.keyboardShortcut("1", modifiers: .command)
            Button("Open Jam") { session.tab = 1 }.keyboardShortcut("2", modifiers: .command)
            Button("Open Mixer") { session.tab = 2 }.keyboardShortcut("3", modifiers: .command)
        }
        .frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
        .disabled(session.sheet != nil)
    }
}

/// U56 · A beat you can see: a bar at the top lights on every beat, brighter on the first.
private struct VisualMetronome: View {
    let session: Session
    var body: some View {
        let position = Int(session.audio.tick)
        let beat = (position % barTicks) / ppq
        let phase = Double(position % ppq) / Double(ppq)
        Rectangle()
            .fill(beat == 0 ? Color.mint : Color.harmony)
            .opacity(max(0, 1 - phase * 2.5))
            .frame(height: beat == 0 ? 8 : 5)
            .ignoresSafeArea(edges: .top)
            .transaction { $0.animation = nil }
            .accessibilityHidden(true)
    }
}

/// U58 · With VoiceOver on, each new bar is announced while playing (at most once per bar).
private struct BarAnnouncer: View {
    let audio: AudioController
    @State private var announced = -1
    var body: some View {
        let bar = audio.playing ? Int(audio.tick) / barTicks + 1 : -1
        Color.clear.frame(width: 0, height: 0).accessibilityHidden(true)
            .onChange(of: bar) { _, value in
                guard value > 0, value != announced, UIAccessibility.isVoiceOverRunning else { return }
                announced = value
                UIAccessibility.post(notification: .announcement, argument: String(format: NSLocalizedString("Bar %lld", comment: "VoiceOver position"), value))
            }
    }
}
