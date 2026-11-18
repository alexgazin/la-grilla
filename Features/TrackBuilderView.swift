import SwiftUI
import MusicDomain
import Foundation

struct TrackBuilderView: View {
    @Bindable var session: Session
    @State private var brief = TrackBrief()
    @State private var idea = ""
    @State private var name = ""
    @State private var feedback: String?
    @State private var problem: String?
    @State private var preview: Project?
    @State private var ai = AIComposerController()
    @State private var interpreting: Task<Void,Never>?
    @State private var saving = false
    @Environment(\.scenePhase) private var phase
    @FocusState private var editing: Bool

    init(session:Session) {
        self.session=session
        _idea=State(initialValue:session.trackIdea)
        _name=State(initialValue:session.trackDraftName)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("A mellow late-night hip-hop beat",text:$idea,axis:.vertical)
                        .lineLimit(2...5).focused($editing).accessibilityIdentifier("builder.idea")
                        .onChange(of:idea) { _,text in
                            if text.count > 2000 { idea=String(text.prefix(2000)) }
                            feedback=nil; problem=nil
                        }
                    Button(action:interpret) {
                        Label("Suggest settings",systemImage:"wand.and.stars")
                    }.disabled(trimmedIdea.isEmpty || interpreting != nil)
                    if interpreting != nil { ProgressView("Suggesting settings…") }
                    if let feedback { Text(feedback).font(.footnote).foregroundStyle(Color.muted) }
                } header: { Text("Describe the track") }
                Section {
                    Picker("Groove preset",selection:presetBinding) {
                        Text("Choose a preset").tag(Optional<SketchStyle>.none)
                        ForEach(SketchStyle.allCases,id:\.self) { style in
                            Text(LocalizedStringKey(style.title)).tag(Optional(style))
                        }
                    }.pickerStyle(.menu)
                    Picker("Rhythm",selection:$brief.style) {
                        ForEach(SketchStyle.allCases,id:\.self) { style in Text(LocalizedStringKey(style.title)).tag(style) }
                    }.pickerStyle(.segmented)
                    HStack {
                        Text("Tempo")
                        Spacer()
                        TextField("BPM",value:$brief.tempo,format:.number.grouping(.never))
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                            .focused($editing).frame(width:56).accessibilityLabel("Tempo")
                        Text(verbatim:"BPM").font(.caption.monospaced()).foregroundStyle(Color.muted)
                        Stepper("Tempo",value:$brief.tempo,in:40...240).labelsHidden()
                    }
                    Picker("Loop length",selection:$brief.bars) {
                        ForEach([4,8,16],id:\.self) { bars in Text("\(bars) bars").tag(bars) }
                    }.pickerStyle(.segmented).accessibilityLabel("Loop length")
                } header: { Text("Rhythm and tempo") }
                Section {
                    Picker("Key",selection:$brief.root) {
                        ForEach(0..<12,id:\.self) { root in Text(verbatim:Chord.roots[root]).tag(root) }
                    }
                    Picker("Mode",selection:$brief.minor) {
                        Text("Major").tag(false); Text("Minor").tag(true)
                    }.pickerStyle(.segmented)
                    TextField("Automatic chord cycle",text:$brief.chordText)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($editing).accessibilityLabel("Chords").accessibilityIdentifier("builder.chords")
                    Button { brief.chordText=brief.suggestedChords } label: {
                        Label(brief.suggestedChords,systemImage:"music.note.list")
                    }.accessibilityHint("Use these chords")
                } header: { Text("Harmony and chords") } footer: {
                    Text("One chord per bar. The sequence repeats. Leave it empty to generate harmony in the selected key.")
                }
                Section {
                    TextField("Project name",text:$name).focused($editing)
                    Button { brief.seed &+= 1 } label: {
                        HStack { Label("New variation",systemImage:"dice"); Spacer(); Text(verbatim:"#\(brief.seed)").monospacedDigit() }
                    }
                    if let preview {
                        Text(verbatim:preview.patterns.flatMap(\.chords).map(\.chord.symbol).joined(separator:"  ·  "))
                            .font(.subheadline.monospaced()).foregroundStyle(Color.harmony)
                    }
                    Button(action:listen) {
                        Label(LocalizedStringKey(session.harmonyPreview ? "Stop preview" : "Listen to sketch"),
                              systemImage:session.harmonyPreview ? "stop.fill":"play.fill")
                    }.accessibilityIdentifier("builder.preview")
                    if let problem { Text(problem).font(.footnote).foregroundStyle(Color.record) }
                    Button(action:save) {
                        Label("Create editable track",systemImage:"square.grid.3x3.fill")
                    }.accessibilityIdentifier("builder.create")
                } footer: { Text("Creates a separate project with chords, drums, bass and melody.") }
            }
            .disabled(saving || interpreting != nil)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Build a track")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction) { Button("Cancel") { session.sheet=nil }.disabled(saving) }
                if interpreting != nil {
                    ToolbarItem(placement:.confirmationAction) { Button("Cancel generation") { cancelInterpretation() } }
                }
            }
            .overlay { if saving { ProgressView("Creating project…") } }
        }
        .interactiveDismissDisabled(saving)
        .onChange(of:brief) { _,_ in invalidatePreview() }
        .onChange(of:name) { _,_ in invalidatePreview() }
        .onChange(of:phase) { _,new in if new == .background { cancelInterpretation(); session.endHarmonyPreview() } }
        .onDisappear { cancelInterpretation(); session.endHarmonyPreview() }
    }

    private var presetBinding: Binding<SketchStyle?> {
        Binding(get:{
            var preset=brief; preset.usePreset(brief.style)
            return preset == brief ? brief.style : nil
        },set:{ if let style=$0 { brief.usePreset(style); feedback=nil } })
    }
    private var trimmedIdea:String { idea.trimmingCharacters(in:.whitespacesAndNewlines) }
    private func invalidatePreview() {
        session.endHarmonyPreview(); preview=nil; problem=nil
    }
    private func cancelInterpretation() {
        interpreting?.cancel(); interpreting=nil
    }
    private func interpret() {
        editing=false; problem=nil; feedback=nil
        let text=trimmedIdea
        let locale=text.range(of:#"[А-Яа-яЁё]"#,options:.regularExpression) == nil ? "en-US":"ru-RU"
        ai.refresh(localeIdentifier:locale)
        if !ai.available { suggestLocally(text); return }
        interpreting=Task { @MainActor in
            do {
                let next=try await ai.interpretBrief(text,current:brief,language:locale)
                try Task.checkCancellation()
                brief=next
                feedback=NSLocalizedString("Apple Intelligence suggested these settings. Adjust them before listening.",comment:"Track builder")
            } catch {
                guard !Task.isCancelled else { return }
                suggestLocally(text)
            }
            interpreting=nil
        }
    }
    private func suggestLocally(_ text:String) {
        do {
            brief=try brief.suggesting(text)
            feedback=NSLocalizedString("Local suggestions from rhythm, mood and musical terms. Review the settings below.",comment:"Track builder")
        } catch { feedback=error.localizedDescription }
    }
    private func draft() throws -> Project {
        if let preview { return preview }
        let title=name.trimmingCharacters(in:.whitespacesAndNewlines)
        let result=try brief.makeProject(name:title.isEmpty ? NSLocalizedString("New sketch",comment:"Project name") : title)
        preview=result
        return result
    }
    private func listen() {
        editing=false; problem=nil
        if session.harmonyPreview { session.endHarmonyPreview(); return }
        do { session.previewNewTrack(try draft()); problem=session.audio.error }
        catch { problem=error.localizedDescription }
    }
    private func save() {
        guard !saving else { return }
        editing=false; problem=nil
        do {
            let project=try draft()
            saving=true
            Task { @MainActor in
                let created=await session.saveNewProject(project)
                if created { session.adoptGeneratedSketchLoop(bars:brief.bars); session.tab=0 }
                else { problem=session.message ?? session.saveError }
                saving=false
            }
        } catch { problem=error.localizedDescription }
    }
}
