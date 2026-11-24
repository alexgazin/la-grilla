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
    @State private var preview: PreparedTrackDraft?
    @State private var preparation: Task<Void,Never>?
    @State private var previewPart: Int?
    @State private var preparingScope: PlaybackScope?
    @State private var takeChange: TakeChange?
    @State private var cachedTakes: [ArrangementTake: PreparedTrackDraft] = [:]
    @State private var acceptedIdea: String?
    @State private var history: [TrackBrief] = []
    @State private var programmaticChange: TrackBrief?
    /// Bumped when "Build by parts in a table" opens the table, to scroll to it.
    @State private var tableOpened = 0
    @State private var ai = AIComposerController()
    @AppStorage("studio.builder.interpretWithApple") private var interpretWithApple = false
    @State private var interpreting: Task<Void,Never>?
    @State private var saving = false
    /// The plan a running preparation was started from; a later onChange for the same plan keeps it.
    @State private var preparingBrief: TrackBrief?
    /// Listen or Create pressed while the description still had to be read: continue after it.
    @State private var afterReview: AfterReview?
    private enum AfterReview { case listen(Int?), save }
    @Environment(\.scenePhase) private var phase
    @FocusState private var editing: Bool

    init(session:Session) {
        self.session=session
        if let suggestion = session.suggestedTrackBrief {
            _brief = State(initialValue: suggestion)
            _acceptedIdea = State(initialValue: session.trackIdea.trimmingCharacters(in: .whitespacesAndNewlines))
            if !session.editingArrangementCopy {
                let key = session.trackSuggestionUsesApple ? "Apple Intelligence suggested these settings. Adjust them before listening." : "Prepared with the offline generator. Listen before creating a new project."
                _feedback = State(initialValue: NSLocalizedString(key,comment:"Assistant handoff"))
            }
        }
        _idea=State(initialValue:session.trackIdea)
        _name=State(initialValue:session.trackDraftName)
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroller in
            Form {
                if brief.songForm != nil {
                    Section {
                        ArrangementScorePreview(brief: brief, session: session,
                                                playingPart: session.harmonyPreview ? previewPart : nil,
                                                canPreview: preparation == nil,
                                                play: { listen(part: $0) })
                            .listRowInsets(EdgeInsets()).listRowBackground(Color.panel)
                        ArrangementTakePicker(selection: takeBinding)
                            .disabled(preparation != nil && preparingScope == nil)
                    }
                }
                Section {
                    TextField("A mellow late-night hip-hop beat",text:$idea,axis:.vertical)
                        .lineLimit(2...5).focused($editing).accessibilityIdentifier("builder.idea")
                        .onChange(of:idea) { _,text in
                            if text.count > 2000 { idea=String(text.prefix(2000)) }
                            feedback=nil; history.removeAll(); invalidatePreview()
                        }
                    if session.editingArrangementCopy {
                        Text("This copy starts from the saved arrangement plan. Later edits to individual notes and mixer settings stay in the original project.")
                            .font(.footnote).foregroundStyle(Color.muted)
                    } else if trimmedIdea.isEmpty, session.project.arrangementRecipe != nil {
                        Button("Edit saved arrangement as a copy") {
                            Self.openSavedArrangement(in: session)
                            if let restored = session.suggestedTrackBrief {
                                install(restored)
                                idea=session.trackIdea
                                acceptedIdea=trimmedIdea
                                name=session.trackDraftName
                            }
                        }.accessibilityIdentifier("builder.edit-saved-arrangement")
                    }
                    if trimmedIdea.isEmpty {
                        Button("Try a boom-bap arrangement") {
                            idea = NSLocalizedString("8 bars of boom bap at 88 BPM in D minor. First 4 bars only bass and drums. Half-bar break before the loop.", comment: "Instrumental prompt")
                        }
                        ForEach(ArrangementExample.allCases) { example in
                            Button(LocalizedStringKey(example.title)) { idea = example.prompt() }
                                .accessibilityIdentifier("builder.example." + example.rawValue)
                        }
                    }
                    Toggle("Use Apple Intelligence to interpret the description", isOn: $interpretWithApple)
                    Button(action:interpret) {
                        Label("Suggest settings",systemImage:"wand.and.stars")
                    }.disabled(trimmedIdea.isEmpty || interpreting != nil).accessibilityIdentifier("builder.suggest")
                    if interpreting != nil { LoadingSkeleton(rows: 2, caption: "Suggesting settings…") }
                    if let feedback {
                        Text(feedback).font(.footnote).foregroundStyle(Color.muted)
                    } else if unreviewedIdea {
                        Text("Review the description to update the arrangement.")
                            .font(.footnote).foregroundStyle(Color.muted).accessibilityIdentifier("builder.unreviewed")
                    }
                } header: { Text("Describe the track") }
                if let form = Binding($brief.songForm) {
                    SongFormEditor(form: form, keyRoot: brief.root, minor: brief.minor,
                                   previewing: session.harmonyPreview ? previewPart : nil,
                                   canPreview: preparation == nil,
                                   play: { position in listen(part: position) },
                                   close: { acceptedIdea = trimmedIdea; brief.songForm = nil })
                } else {
                    // Musician feedback: a table instead of guessing the wording.
                    Section {
                        Button { startTable() } label: { Label("Build by parts in a table", systemImage: "tablecells") }
                            .accessibilityIdentifier("builder.table")
                    } footer: { Text("No need to guess a format: set each part's bars and chords, then the order.") }
                }
                Section {
                    Menu {
                        ForEach(SketchStyle.allCases,id:\.self) { style in
                            Menu(LocalizedStringKey(style.title)) {
                                ForEach(GroovePreset.library.filter{$0.recipe.style==style}) { preset in
                                    Button {
                                        idea=""; acceptedIdea=nil; install(preset.recipe); feedback=nil
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
                    if flexibleRhythm {
                        Picker("Rhythm",selection:$brief.style) {
                            ForEach(SketchStyle.allCases,id:\.self) { style in Text(LocalizedStringKey(style.title)).tag(style) }
                        }.pickerStyle(.segmented)
                    }
                    HStack {
                        Text("Tempo")
                        Spacer()
                        TextField("BPM",value:tempoBinding,format:.number.grouping(.never))
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                            .focused($editing).frame(width:56).accessibilityLabel("Tempo")
                        Text(verbatim:"BPM").font(.caption.monospaced()).foregroundStyle(Color.muted)
                        Stepper("Tempo",value:tempoBinding,in:40...240).labelsHidden()
                    }
                    if brief.songForm?.proposedTempo == true {
                        Text("Suggested tempo").font(.footnote).foregroundStyle(Color.muted)
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
                    Picker("Key",selection:keyBinding(\.root)) {
                        ForEach(0..<12,id:\.self) { root in Text(verbatim:Chord.roots[root]).tag(root) }
                    }
                    Picker("Mode",selection:keyBinding(\.minor)) {
                        Text("Major").tag(false); Text("Minor").tag(true)
                    }.pickerStyle(.segmented)
                    if brief.songForm?.proposedKey == true {
                        Text("Suggested key").font(.footnote).foregroundStyle(Color.muted)
                    }
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
                if !ambient {
                    Section {
                        if flexibleRhythm && brief.style == .hipHop {
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
                }
                Section {
                    TextField("Project name",text:$name).focused($editing)
                    if brief.songForm == nil {
                        Button { brief.seed &+= 1 } label: {
                            HStack { Label("New variation",systemImage:"dice"); Spacer(); Text(verbatim:"#\(brief.seed)").monospacedDigit() }
                        }
                    }
                    if let preview, brief.songForm == nil {
                        Text(verbatim:preview.project.patterns.flatMap(\.chords).map(\.chord.symbol).joined(separator:"  ·  "))
                            .font(.subheadline.monospaced()).foregroundStyle(Color.harmony)
                    }
                    // Musician feedback: the button always answers — it reads a changed description,
                    // shows the preparation, then playback with the bar that is playing.
                    Button { listen() } label: {
                        HStack {
                            if preparation != nil && preparingScope?.part == nil && !saving { ProgressView().padding(.trailing, 4) }
                            else { Image(systemName: session.harmonyPreview && previewPart == nil ? "stop.fill" : "play.fill") }
                            Text(LocalizedStringKey(preparation != nil && preparingScope?.part == nil && !saving ? "Preparing instruments…"
                                                    : session.harmonyPreview && previewPart == nil ? "Stop sketch" : "Listen to sketch"))
                        }
                    }.disabled(preparation != nil || interpreting != nil).accessibilityIdentifier("builder.preview")
                    if session.harmonyPreview && previewPart == nil, let preview {
                        SketchPlayhead(session: session, length: preview.project.length)
                    }
                    // U5: the same promise as every listening block.
                    Text("Nothing is created until you tap Create.").font(.footnote).foregroundStyle(Color.muted)
                    if unreviewedIdea && preparation == nil {
                        Text("The description changed: Listen and Create read it first.").font(.footnote).foregroundStyle(Color.muted)
                    }
                    if let problem { Text(problem).font(.footnote).foregroundStyle(Color.record).accessibilityIdentifier("builder.problem") }
                    Button(action:save) {
                        Label(LocalizedStringKey(session.editingArrangementCopy ? "Create arrangement copy" : "Create editable track"),systemImage:"square.grid.3x3.fill")
                    }.disabled(preparation != nil || interpreting != nil).accessibilityIdentifier("builder.create")
                } footer: { Text("Creates a separate editable project.") }
            }
            // The score appears above when the table opens; keep the table itself in view.
            .onChange(of: tableOpened) { _, _ in
                Task { @MainActor in withAnimation(Luz.Motion.snap) { scroller.scrollTo("builder.songform", anchor: .top) } }
            }
            }
            .disabled(saving || interpreting != nil)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Build a track")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction) { Button("Cancel") { session.sheet=nil }.disabled(saving) }
                if !history.isEmpty && !unreviewedIdea && !saving && interpreting == nil {
                    ToolbarItem(placement:.topBarTrailing) {
                        Button { undoPlanEdit() } label: { Label("Undo plan edit", systemImage:"arrow.uturn.backward") }
                            .accessibilityIdentifier("builder.undo")
                    }
                }
                if interpreting != nil {
                    ToolbarItem(placement:.confirmationAction) { Button("Cancel generation") { cancelInterpretation() } }
                }
            }
            .overlay { if saving { ProgressView("Creating project…") } }
        }
        .interactiveDismissDisabled(saving)
        .onChange(of:brief) { old, new in
            if programmaticChange != new && !unreviewedIdea {
                history.append(old)
                if history.count > 32 { history.removeFirst() }
            }
            let change = takeChange
            takeChange=nil
            programmaticChange=nil
            if let change, change.brief == new {
                preparation?.cancel(); preparation=nil; preparingScope=nil
                preview = cachedTakes[ArrangementAudition.take(in: new)]
                if let scope = change.resume {
                    // Keep the audible take running until the new instruments are ready.
                    listen(part: scope.part, restart: true)
                }
            } else if preparation == nil || preparingBrief != new {
                invalidatePreview()
            }
        }
        .onChange(of:name) { _,_ in invalidatePreview() }
        .onChange(of:phase) { _,new in if new == .background { cancelInterpretation(); invalidatePreview() } }
        .onDisappear { cancelInterpretation(); invalidatePreview() }
    }

    static func openSavedArrangement(in session: Session) {
        guard let recipe = session.project.arrangementRecipe else { return }
        let format = NSLocalizedString("%@ · arrangement copy", comment: "Generated project name")
        let name = String(format: format, String(session.project.name.prefix(90)))
        session.openTrackBuilder(idea: recipe.prompt, name: name, suggestion: recipe.brief, asCopy: true)
    }

    private struct PlaybackScope {
        /// A nil index selects the entire draft.
        let part: Int?
    }
    private struct TakeChange {
        let brief: TrackBrief
        let resume: PlaybackScope?
    }
    private var takeBinding: Binding<ArrangementTake> {
        Binding(get: { ArrangementAudition.take(in: brief) }, set: { chosen in
            let next = ArrangementAudition.select(chosen, in: brief)
            guard next != brief else { return }
            if let preview, takeChange == nil {
                cachedTakes[ArrangementAudition.take(in: brief)] = preview
            }
            let resume = preparingScope ?? (session.harmonyPreview ? PlaybackScope(part: previewPart) : nil) ?? takeChange?.resume
            takeChange = TakeChange(brief: next, resume: resume)
            programmaticChange=next
            brief=next
        })
    }

    private var trimmedIdea:String { idea.trimmingCharacters(in:.whitespacesAndNewlines) }
    private var ambient: Bool { brief.songForm?.arrangement == .ambient }
    private var flexibleRhythm: Bool { brief.songForm == nil || brief.songForm?.arrangement == .groove }
    private var unreviewedIdea: Bool { !trimmedIdea.isEmpty && acceptedIdea != trimmedIdea }
    private func keyBinding<Value>(_ path: WritableKeyPath<TrackBrief,Value>) -> Binding<Value> {
        Binding(get: { brief[keyPath:path] }, set: { value in
            brief[keyPath:path]=value
            brief.songForm?.proposedKey=false
        })
    }
    private var tempoBinding: Binding<Int> {
        Binding(get: { brief.tempo }, set: { value in
            brief.tempo = value
            brief.songForm?.proposedTempo = false
        })
    }
    private func startTable() {
        acceptedIdea = trimmedIdea; feedback = nil
        brief.songForm = SongFormBrief.starter(keyRoot: brief.root, minor: brief.minor)
        tableOpened += 1
    }
    private func install(_ next:TrackBrief) {
        history.removeAll()
        if next != brief { programmaticChange=next; brief=next }
    }
    private func undoPlanEdit() {
        guard let last = history.popLast() else { return }
        programmaticChange=last
        brief=last
    }
    private func invalidatePreview() {
        if !saving { preparation?.cancel(); preparation=nil }
        cachedTakes.removeAll(); takeChange=nil
        preparingScope=nil; previewPart=nil
        session.endHarmonyPreview(); preview=nil; problem=nil
    }
    private func cancelInterpretation() {
        interpreting?.cancel(); interpreting=nil
    }
    private func interpret() {
        editing=false; problem=nil; feedback=nil
        let text=trimmedIdea
        acceptedIdea=nil; invalidatePreview()
        guard interpretWithApple else { suggestLocally(text); return }
        let local = Result { try brief.suggesting(text) }
        if case .success(let supported) = local,
           SongFormBrief.recognizes(text) || supported.bassVariation != brief.bassVariation || supported.drumVariation != brief.drumVariation {
            applyLocal(supported, text: text)
            return
        }
        let locale=text.range(of:#"[А-Яа-яЁё]"#,options:.regularExpression) == nil ? "en-US":"ru-RU"
        ai.refresh(localeIdentifier:locale)
        if !ai.available { suggestLocally(text); return }
        interpreting=Task { @MainActor in
            do {
                let next=try await ai.interpretBrief(text,current:brief,language:locale)
                try Task.checkCancellation()
                install(next); acceptedIdea=text
                feedback=NSLocalizedString("Apple Intelligence suggested these settings. Adjust them before listening.",comment:"Track builder")
            } catch {
                guard !Task.isCancelled else { return }
                if case .success(let supported) = local {
                    applyLocal(supported, text: text)
                } else {
                    feedback=error.localizedDescription
                }
            }
            interpreting=nil
            resumeAfterReview()
        }
    }
    /// True when the plan matches the description; otherwise reads it first. Local reading is
    /// immediate; Apple Intelligence continues with `next` when it answers.
    private func reviewThen(_ next: AfterReview) -> Bool {
        guard unreviewedIdea else { return true }
        guard interpreting == nil else { afterReview = next; return false }
        interpret()
        if interpreting != nil { afterReview = next; return false }
        if unreviewedIdea {
            problem = feedback ?? NSLocalizedString("Check the description above, then try again.", comment: "Track builder")
            return false
        }
        return true
    }
    private func resumeAfterReview() {
        guard let next = afterReview else { return }
        afterReview = nil
        guard !unreviewedIdea else { problem = feedback; return }
        switch next {
        case .listen(let part): listen(part: part)
        case .save: save()
        }
    }
    private func suggestLocally(_ text:String) {
        do {
            applyLocal(try brief.suggesting(text), text: text)
        } catch {
            invalidatePreview()
            acceptedIdea=nil
            feedback=error.localizedDescription
        }
    }
    private func applyLocal(_ result: TrackBrief, text: String) {
        install(result)
        acceptedIdea=text
        feedback=NSLocalizedString("Local suggestions from rhythm, mood and musical terms. Review the settings below.",comment:"Track builder")
    }
    private func prepare(_ action: @escaping @MainActor (PreparedTrackDraft) async -> Void) {
        guard !unreviewedIdea, preparation == nil, !saving else { return }
        let snapshot = brief
        let sourcePrompt = trimmedIdea
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let projectName = title.isEmpty ? NSLocalizedString("New sketch",comment:"Project name") : title
        preparingBrief = snapshot
        preparation = Task { @MainActor in
            do {
                let ready: PreparedTrackDraft
                if let preview { ready = preview } else {
                    ready = try await SoundBankLibrary.shared.prepareTrackDraft(brief: snapshot, name: projectName, sourcePrompt: sourcePrompt)
                }
                try Task.checkCancellation()
                preview = ready
                await action(ready)
            } catch {
                if !Task.isCancelled {
                    if preparingScope != nil { session.endHarmonyPreview(); previewPart=nil }
                    problem = error.localizedDescription
                }
            }
            if !Task.isCancelled { preparation=nil; preparingScope=nil; preparingBrief=nil }
        }
    }
    private func listen(part: Int? = nil, restart: Bool = false) {
        guard !saving else { return }
        editing=false
        guard reviewThen(.listen(part)), preparation == nil else { return }
        problem=nil
        if !restart && session.harmonyPreview && previewPart == part {
            session.endHarmonyPreview(); previewPart=nil; return
        }
        preparingScope=PlaybackScope(part: part)
        prepare { ready in
            let range = part.map { index in
                let section = ready.project.sections[index]
                return section.start..<(section.start + section.length)
            }
            if session.previewNewTrack(ready, range: range) {
                previewPart = part
                Luz.Haptics.transportStart()
            } else {
                previewPart = nil
                problem = session.audio.error ?? session.message
                    ?? NSLocalizedString("The sketch could not start. Stop other playback and try again.", comment: "Track builder")
                session.message = nil
            }
        }
    }
    private func save() {
        editing=false
        guard reviewThen(.save) else { return }
        problem=nil
        prepare { ready in
            saving=true
            let created = await session.saveGeneratedTrack(ready)
            if created { session.tab=0 } else { problem=session.message ?? session.saveError }
            saving=false
        }
    }
}

enum ArrangementExample: String, CaseIterable, Identifiable {
    case workout, chillhop, ambient
    var id: Self { self }

    var title: String {
        switch self {
        case .workout: "Try a workout arrangement"
        case .chillhop: "Chillhop with flute and piano"
        case .ambient: "Ambient meditation with bansuri"
        }
    }

    func prompt(language: String? = nil) -> String {
        let languageBundle = language.flatMap { code in
            Bundle.main.path(forResource: String(code.prefix(2)), ofType: "lproj").flatMap(Bundle.init(path:))
        }
        return (languageBundle ?? .main).localizedString(forKey: "arrangement.example." + rawValue + ".prompt",
                                                        value: nil, table: nil)
    }
}

private struct SongFormEditor: View {
    @Binding var form: SongFormBrief
    let keyRoot: Int
    let minor: Bool
    var previewing: Int?
    var canPreview: Bool
    let play: (Int) -> Void
    let close: () -> Void

    private func orderText(_ order: [Int]) -> String { order.map { form.title($0) }.joined(separator: " · ") }

    var body: some View {
        Section {
            if form.arrangement == .groove {
                Menu {
                    ForEach(SongFormBrief.orderChoices(parts: form.parts.count), id: \.self) { choice in
                        Button { form.setOrder(choice) } label: {
                            if choice == form.order { Label(orderText(choice), systemImage: "checkmark") } else { Text(verbatim: orderText(choice)) }
                        }
                    }
                } label: {
                    LabeledContent("Order") { Text(verbatim: orderText(form.order)).monospaced() }
                }.accessibilityIdentifier("builder.order").id("builder.songform")
            }
            ForEach(form.order.indices, id: \.self) { position in
                let source = form.order[position]
                let start = 1 + form.order.prefix(position).reduce(0) { $0 + form.parts[$1].bars }
                SongFormPartEditor(form: $form, keyRoot: keyRoot, minor: minor, position: position, source: source, start: start,
                                   previewing: previewing == position, canPreview: canPreview, play: play)
            }
            if form.arrangement == .groove {
                HStack(spacing: 12) {
                    Button { form.addPart() } label: { Label("Add a part", systemImage: "plus.circle") }
                        .disabled(form.parts.count >= SongFormBrief.maximumParts || form.order.count >= 8)
                        .accessibilityIdentifier("builder.add-part")
                    Spacer()
                    if form.parts.count > 1 {
                        Menu {
                            ForEach(form.parts.indices, id: \.self) { index in
                                Button(role: .destructive) { form.removePart(index) } label: { Text(verbatim: form.title(index)) }
                            }
                        } label: { Label("Remove a part", systemImage: "minus.circle") }
                            .accessibilityIdentifier("builder.remove-part")
                    }
                }.buttonStyle(.borderless)
            }
            if let skipped = form.skipped, !skipped.isEmpty {
                let names = skipped.map { NSLocalizedString($0, comment: "Skipped wish") }.joined(separator: ", ")
                Label(String(format: NSLocalizedString("Not played offline yet, so left out: %@. The rest of the description is used.", comment: "Song form"), names),
                      systemImage: "info.circle")
                    .font(.footnote).foregroundStyle(Color.muted).accessibilityIdentifier("builder.skipped")
            }
            if form.arrangement == .ambient {
                Toggle("Long delay", isOn: $form.longDelay).accessibilityIdentifier("builder.delay")
            }
            Button(role: .destructive, action: close) { Label("Back to one loop", systemImage: "arrow.uturn.backward") }
                .accessibilityIdentifier("builder.close-table")
        } header: {
            HStack { Text("Song form"); Spacer(); Text("\(form.totalBars) bars") }
        } footer: {
            if form.totalBars > 64 { Text("The whole song can be up to 64 bars. Shorten a part or play it fewer times.").foregroundStyle(Color.record) }
        }
    }
}

private struct SongFormPartEditor: View {
    @Binding var form: SongFormBrief
    let keyRoot: Int
    let minor: Bool
    let position: Int
    let source: Int
    let start: Int
    let previewing: Bool
    let canPreview: Bool
    let play: (Int) -> Void

    private var part: SongFormBrief.Part { form.parts[source] }
    private var repeated: Bool { form.order.prefix(position).contains(source) }
    private var identifier: String { "builder.part.\(position)." }

    private func title(at index: Int) -> String {
        let key: String
        switch form.parts[index].role {
        case .groove: return form.title(index)
        case .fluteIntro: key = "Flute intro"
        case .developingBeat: key = "Main groove"
        case .arpeggio: key = "Arpeggio"
        case .gong: key = "Gong"
        case .ambientIntro: key = "Ambient intro"
        case .bansuriSolo: key = "Bansuri solo"
        case .keysOutro: key = "Closing keys"
        }
        return NSLocalizedString(key,comment:"Song section")
    }

    private var chordsBinding: Binding<String> {
        Binding(get: { form.parts[source].chordText }, set: { text in
            form.parts[source].chordText = text
            form.parts[source].proposedChords = nil
        })
    }

    private var nameBinding: Binding<String> {
        Binding(get: { form.parts[source].name ?? "" }, set: { text in
            let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
            form.parts[source].name = trimmed.isEmpty ? nil : String(text.prefix(40))
        })
    }

    private var barsBinding: Binding<Int> {
        Binding(get: { part.bars }, set: { bars in
            form.parts[source].bars=bars
            form.parts[source].proposedBars=false
            if part.role == .keysOutro { form.fadeBars=min(form.fadeBars,bars) }
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(verbatim:title(at: source)).font(.headline).accessibilityIdentifier(identifier+"title")
                Spacer()
                Text(verbatim:"\(start)–\(start + part.bars - 1)").font(.subheadline.monospacedDigit())
                    .accessibilityIdentifier(identifier+"range")
                Button { play(position) } label: {
                    Image(systemName: previewing ? "stop.fill":"play.fill")
                        .frame(minWidth:44,minHeight:44)
                }.buttonStyle(.borderless).disabled(!canPreview)
                    .accessibilityLabel(LocalizedStringKey(previewing ? "Stop preview" : "Listen to section"))
                    .accessibilityValue(Text(verbatim:title(at:source)))
                    .accessibilityIdentifier(identifier+"preview")
            }.foregroundStyle(Color.harmony)
            if repeated {
                Text("Repeats the source part, including edits.").font(.footnote)
                Text(verbatim:form.resolvedChordText(for: source))
            } else {
                let copies = form.order.filter { $0 == source }.count
                let maximum = part.bars + (64 - form.totalBars) / copies
                Stepper(value: barsBinding, in: 1...maximum) {
                    VStack(alignment:.leading) {
                        Text("\(part.bars) bars")
                        if part.proposedBars { Text("Suggested length").font(.footnote).foregroundStyle(Color.muted) }
                    }
                }.accessibilityIdentifier(identifier+"bars")
                if let from = part.chordSource {
                    let label = String(format:NSLocalizedString("Chords from %@",comment:"Inherited progression"),title(at:from))
                    VStack(alignment:.leading,spacing:3) {
                        Text(verbatim:label).font(.footnote).foregroundStyle(Color.muted)
                            .accessibilityIdentifier(identifier+"inheritance")
                        Text(verbatim:form.resolvedChordText(for:source))
                            .accessibilityIdentifier(identifier+"chords")
                    }
                } else if part.role != .fluteIntro && part.role != .gong {
                    TextField("Chords",text:chordsBinding)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityLabel("Chords").accessibilityIdentifier(identifier+"chords")
                    ChordPicker(text: chordsBinding, keyRoot: keyRoot, minor: minor, identifier: identifier)
                    if part.proposedChords == true { Text("Suggested chords").font(.footnote).foregroundStyle(Color.muted) }
                }
                if part.role == .groove {
                    TextField("Part name, for example Verse", text: nameBinding)
                        .accessibilityIdentifier(identifier+"name")
                    Toggle("Quieter part",isOn:$form.parts[source].relaxed)
                }
                if part.role == .keysOutro {
                    Stepper(value: Binding(get: { form.fadeBars }, set: {
                        form.fadeBars=$0
                        form.proposedFadeBars=false
                    }), in: 0...part.bars) {
                        VStack(alignment:.leading) {
                            Text("Fade over \(form.fadeBars) bars")
                            if form.proposedFadeBars { Text("Suggested fade").font(.footnote).foregroundStyle(Color.muted) }
                        }
                    }.accessibilityIdentifier("builder.fade")
                }
            }
        }.padding(.vertical,4)
    }
}

/// Tap-to-pick chords of the key next to the typed list: no format to guess.
private struct ChordPicker: View {
    @Binding var text: String
    let keyRoot: Int
    let minor: Bool
    let identifier: String

    private var chords: [String] { text.split { $0 == "," || $0.isWhitespace }.map(String.init) }
    private var palette: [String] { SongFormBrief.diatonic(keyRoot: keyRoot, minor: minor).map { MusicalNotation.chordSymbol($0, keyRoot: keyRoot, minor: minor) } }

    private func write(_ list: [String]) { text = list.joined(separator: ", ") }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(chords.enumerated()), id: \.offset) { index, chord in
                    Menu {
                        ForEach(palette, id: \.self) { symbol in
                            Button(symbol) { var list = chords; list[index] = symbol; write(list) }
                        }
                        Button("Remove", systemImage: "trash", role: .destructive) { var list = chords; list.remove(at: index); write(list) }
                    } label: {
                        Text(verbatim: chord).font(.subheadline.weight(.semibold)).padding(.horizontal, 10).frame(minHeight: 36)
                            .background(Color.harmony.opacity(0.18), in: Capsule()).foregroundStyle(Color.harmony)
                    }
                    .accessibilityLabel(Text(verbatim: chord)).accessibilityHint("Change or remove this chord")
                    .accessibilityIdentifier(identifier + "chord.\(index)")
                }
                Menu {
                    ForEach(palette, id: \.self) { symbol in Button(symbol) { write(chords + [symbol]) } }
                } label: {
                    Image(systemName: "plus").font(.subheadline.weight(.bold)).frame(width: 44, height: 36)
                        .background(Color.raised, in: Capsule()).foregroundStyle(Color.studioText)
                }
                .disabled(chords.count >= 64)
                .accessibilityLabel("Add a chord").accessibilityIdentifier(identifier + "chord.add")
            }
        }
    }
}

/// The bar the sketch preview is playing, so a silent route still shows that it plays.
private struct SketchPlayhead: View {
    let session: Session
    let length: Int
    var body: some View {
        let bars = max(1, length / barTicks)
        let bar = min(bars, max(1, Int(session.audio.tick) / barTicks + 1))
        VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: Double(bar), total: Double(bars)).tint(Color.mint)
            Text("Playing · bar \(bar) of \(bars)").font(.footnote.monospacedDigit()).foregroundStyle(Color.muted)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("builder.playhead")
    }
}
