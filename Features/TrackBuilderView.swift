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
    @AppStorage("studio.builder.interpretWithApple") private var interpretWithApple = false
    @State private var interpreting: Task<Void,Never>?
    @State private var saving = false
    @State private var rejectedIdea = false
    @Environment(\.scenePhase) private var phase
    @FocusState private var editing: Bool

    init(session:Session) {
        self.session=session
        if let suggestion = session.suggestedTrackBrief {
            _brief = State(initialValue: suggestion)
            _feedback = State(initialValue: NSLocalizedString("Prepared with the offline generator. Listen before creating a new project.", comment: "Assistant handoff"))
        }
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
                    if trimmedIdea.isEmpty {
                        Button("Try a boom-bap arrangement") {
                            idea = NSLocalizedString("8 bars of boom bap at 88 BPM in D minor. First 4 bars only bass and drums. Half-bar break before the loop.", comment: "Instrumental prompt")
                        }
                        Button("Try a workout arrangement") {
                            idea = NSLocalizedString("Workout in D minor. Four on the floor, offbeat hats. Part A 8 bars chords A, Bb, C, D. Part B 16 bars chords D, E, F, G quieter. Return to part A.", comment: "Song form example")
                        }
                    }
                    Toggle("Use Apple Intelligence to interpret the description", isOn: $interpretWithApple)
                    Button(action:interpret) {
                        Label("Suggest settings",systemImage:"wand.and.stars")
                    }.disabled(trimmedIdea.isEmpty || interpreting != nil)
                    if interpreting != nil { ProgressView("Suggesting settings…") }
                    if let feedback { Text(feedback).font(.footnote).foregroundStyle(Color.muted) }
                } header: { Text("Describe the track") }
                Section {
                    Menu {
                        ForEach(SketchStyle.allCases,id:\.self) { style in
                            Menu(LocalizedStringKey(style.title)) {
                                ForEach(GroovePreset.library.filter{$0.recipe.style==style}) { preset in
                                    Button {
                                        brief=preset.recipe; feedback=nil; rejectedIdea=false
                                    } label: {
                                        Text(LocalizedStringKey(preset.name)) + Text(verbatim:" · \(preset.recipe.tempo) BPM")
                                    }
                                }
                            }
                        }
                    } label: {
                        LabeledContent("Groove preset") {
                            Text(LocalizedStringKey(GroovePreset.library.first{$0.recipe==brief}?.name ?? "Choose a preset"))
                        }
                    }.accessibilityIdentifier("builder.presets")
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
                    if brief.songForm == nil {
                        Picker("Loop length",selection: Binding(get: { brief.bars }, set: { bars in
                            brief.bars = bars
                            brief.introBars = min(brief.introBars, bars - 1)
                        })) {
                            ForEach([4,8,16],id:\.self) { bars in Text("\(bars) bars").tag(bars) }
                        }.pickerStyle(.segmented).accessibilityLabel("Loop length")
                    }
                } header: { Text("Rhythm and tempo") }
                Section {
                    Picker("Key",selection:$brief.root) {
                        ForEach(0..<12,id:\.self) { root in Text(verbatim:Chord.roots[root]).tag(root) }
                    }
                    Picker("Mode",selection:$brief.minor) {
                        Text("Major").tag(false); Text("Minor").tag(true)
                    }.pickerStyle(.segmented)
                    if brief.songForm == nil {
                        TextField("Automatic chord cycle",text:$brief.chordText)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .focused($editing).accessibilityLabel("Chords").accessibilityIdentifier("builder.chords")
                        Button { brief.chordText=brief.suggestedChords } label: {
                            Label(brief.suggestedChords,systemImage:"music.note.list")
                        }.accessibilityHint("Use these chords")
                    }
                } header: { Text("Harmony and chords") } footer: {
                    if brief.songForm == nil {
                        Text("One chord per bar. The sequence repeats. Leave it empty to generate harmony in the selected key.")
                    }
                }
                if let form = Binding($brief.songForm) {
                    SongFormEditor(form: form)
                }
                Section {
                    if brief.style == .hipHop {
                        Picker("Hip-hop feel", selection: $brief.hipHopFeel) {
                            ForEach(HipHopFeel.allCases, id: \.self) { feel in Text(LocalizedStringKey(feel.rawValue)).tag(feel) }
                        }.pickerStyle(.segmented)
                    }
                    Toggle("Lay the keys behind the beat", isOn: $brief.laidBackKeys)
                    if brief.songForm == nil {
                        Stepper(value: $brief.introBars, in: 0...(brief.bars-1)) {
                            LabeledContent("Bass and drums intro", value: "\(brief.introBars) / \(brief.bars)")
                        }
                        Toggle("Half-bar break at the end", isOn: $brief.endBreak)
                    }
                    Button { brief.drumVariation &+= 1 } label: {
                        LabeledContent("Vary drums only", value: "#\(brief.drumVariation &+ 1)")
                    }
                    Button { brief.bassVariation &+= 1 } label: {
                        LabeledContent("Vary bass only", value: "#\(brief.bassVariation &+ 1)")
                    }
                } header: { Text("Arrangement") }
                Section {
                    TextField("Project name",text:$name).focused($editing)
                    Button { brief.seed &+= 1 } label: {
                        HStack { Label("New variation",systemImage:"dice"); Spacer(); Text(verbatim:"#\(brief.seed)").monospacedDigit() }
                    }
                    if let preview, brief.songForm == nil {
                        Text(verbatim:preview.patterns.flatMap(\.chords).map(\.chord.symbol).joined(separator:"  ·  "))
                            .font(.subheadline.monospaced()).foregroundStyle(Color.harmony)
                    }
                    Button(action:listen) {
                        Label(LocalizedStringKey(session.harmonyPreview ? "Stop preview" : "Listen to sketch"),
                              systemImage:session.harmonyPreview ? "stop.fill":"play.fill")
                    }.disabled(rejectedIdea).accessibilityIdentifier("builder.preview")
                    if let problem { Text(problem).font(.footnote).foregroundStyle(Color.record) }
                    Button(action:save) {
                        Label("Create editable track",systemImage:"square.grid.3x3.fill")
                    }.disabled(rejectedIdea).accessibilityIdentifier("builder.create")
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
        .onChange(of:brief) { _,_ in rejectedIdea=false; invalidatePreview() }
        .onChange(of:name) { _,_ in invalidatePreview() }
        .onChange(of:phase) { _,new in if new == .background { cancelInterpretation(); session.endHarmonyPreview() } }
        .onDisappear { cancelInterpretation(); session.endHarmonyPreview() }
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
        rejectedIdea=false
        guard interpretWithApple && !SongFormBrief.recognizes(text) else { suggestLocally(text); return }
        if let local = try? brief.suggesting(text),
           local.bassVariation != brief.bassVariation || local.drumVariation != brief.drumVariation {
            suggestLocally(text)
            return
        }
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
        } catch {
            invalidatePreview()
            rejectedIdea=true
            feedback=error.localizedDescription
        }
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
                if created { session.adoptGeneratedSketchLoop(bars:project.length/barTicks); session.tab=0 }
                else { problem=session.message ?? session.saveError }
                saving=false
            }
        } catch { problem=error.localizedDescription }
    }
}

private struct SongFormEditor: View {
    @Binding var form: SongFormBrief

    var body: some View {
        Section {
            ForEach(form.order.indices, id: \.self) { position in
                let source = form.order[position]
                let part = form.parts[source]
                let first = 1 + form.order.prefix(position).reduce(0) { $0 + form.parts[$1].bars }
                let repeated = form.order.prefix(position).contains(source)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: repeated ? "repeat" : "music.note.list")
                        Text(verbatim: ["A","B","C"][source]).bold()
                        Spacer()
                        Text(verbatim: "\(first)–\(first + part.bars - 1)").monospacedDigit()
                    }.foregroundStyle(Color.harmony)
                    if repeated {
                        Text("Repeats the source part, including edits.").font(.footnote)
                        Text(verbatim: part.chordText)
                    } else {
                        let copies = form.order.filter { $0 == source }.count
                        let maximum = part.bars + (64 - form.totalBars) / copies
                        Stepper(value: $form.parts[source].bars, in: 1...maximum) {
                            Text("\(part.bars) bars")
                        }
                        TextField("Chords", text: $form.parts[source].chordText)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityLabel("Chords")
                        Toggle("Quieter part", isOn: $form.parts[source].relaxed)
                    }
                }.padding(.vertical, 4)
            }
        } header: {
            HStack { Text("Song form"); Spacer(); Text("\(form.totalBars) bars") }
        } footer: {
            if form.proposedTempo { Text("Tempo is a suggestion. Adjust it above.") }
        }
    }
}
