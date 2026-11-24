import SwiftUI
import MusicDomain

/// I57 · Check the song: places worth a second look, each one tap away.
struct ArrangementDoctorView: View {
    @Bindable var session: Session
    var body: some View {
        let findings = ArrangementDoctor.check(session.project)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Suggestions, not rules: trust your ears.").font(.caption).foregroundStyle(Color.muted)
                    // I60: what it sounds like, with the closest starter groove.
                    let style = StyleGuess.guess(session.project)
                    HStack {
                        Text("\(Text("Sounds like")) \(Text(LocalizedStringKey(StarterGrooves.all.first { $0.id == style.grooveID }?.title ?? ""))) — \(Text(LocalizedStringKey(style.reason)))").font(.callout)
                        Spacer(minLength: 4)
                        Button("Grooves") { session.sheet = .grooves }.font(.callout.weight(.semibold)).frame(minHeight: 44)
                    }.padding(12).background(Color.panel, in: RoundedRectangle(cornerRadius: Luz.Radius.card, style: .continuous)).accessibilityIdentifier("doctor.style")
                    if findings.isEmpty {
                        Label("Nothing stands out. Nice.", systemImage: "checkmark.seal").font(.callout).foregroundStyle(Color.mint).padding(.vertical, 20)
                            .accessibilityIdentifier("doctor.clean")
                    }
                    ForEach(Array(findings.enumerated()), id: \.offset) { index, finding in
                        Button { go(to: finding.bar) } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: symbol(finding.kind)).foregroundStyle(Color.drums).frame(width: 24).accessibilityHidden(true)
                                Text(String(format: NSLocalizedString(finding.message, comment: "Song check"), finding.bar)).font(.callout).multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.muted).accessibilityHidden(true)
                            }
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.panel, in: RoundedRectangle(cornerRadius: Luz.Radius.card, style: .continuous))
                        }
                        .buttonStyle(StudioQuietButtonStyle())
                        .accessibilityIdentifier("doctor.finding.\(index)")
                    }
                }.padding(18)
            }
            .background(Color.ink)
            .navigationTitle("Check the song").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { session.sheet = nil } } }
        }.tint(.mint)
    }
    private func symbol(_ kind: ArrangementDoctor.Finding.Kind) -> String {
        switch kind {
        case .clashWithChord: "waveform.path.ecg"; case .longWithoutChange: "repeat"; case .emptySection: "speaker.slash"
        case .tooDense: "square.stack.3d.up.fill"; case .melodyOutOfRange: "arrow.up.and.down"
        }
    }
    private func go(to bar: Int) {
        let tick = (bar - 1) * barTicks
        if let section = session.project.sections.first(where: { $0.start <= tick && tick < $0.start + $0.length }) { session.select(section) }
        session.sheet = nil; session.tab = 0
    }
}

/// I41 · Which chord is this? Questions from the song's own chords.
struct EarTrainingView: View {
    @Bindable var session: Session
    @State private var questions: [EarTraining.Question] = []
    @State private var index = 0
    @State private var score = 0
    @State private var answered: String?
    @State private var seed: UInt64 = UInt64(Date().timeIntervalSince1970)

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                if questions.isEmpty {
                    Text("Add some chords first: the questions come from your song.").foregroundStyle(Color.muted)
                } else if index < questions.count {
                    let question = questions[index]
                    Text("Question \(index + 1) of \(questions.count) · \(score) right").font(.caption.monospacedDigit()).foregroundStyle(Color.muted)
                    Button { session.audio.preview(question.chord) } label: {
                        Label("Play the chord", systemImage: "play.circle.fill").font(.title3.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 64)
                    }.buttonStyle(StudioActionStyle()).accessibilityIdentifier("ear.play")
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(Array(question.choices.enumerated()), id: \.offset) { choiceIndex, choice in
                            let symbol = MusicalNotation.chordSymbol(choice, keyRoot: session.project.keyRoot, minor: session.project.minor)
                            Button { answer(choice, question: question) } label: {
                                Text(verbatim: symbol).font(.title2.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 64)
                                    .background(color(choice, question: question), in: RoundedRectangle(cornerRadius: Luz.Radius.card, style: .continuous))
                            }
                            .buttonStyle(StudioQuietButtonStyle()).disabled(answered != nil)
                            .accessibilityIdentifier("ear.choice.\(choiceIndex)")
                        }
                    }
                    if answered != nil {
                        Button { answered = nil; index += 1 } label: { Text("Next").frame(maxWidth: .infinity, minHeight: 48) }
                            .buttonStyle(StudioActionStyle(color: .mint, prominent: false)).accessibilityIdentifier("ear.next")
                    }
                } else {
                    Text("\(score) of \(questions.count) right").font(.largeTitle.weight(.semibold)).accessibilityIdentifier("ear.score")
                    Button { start() } label: { Text("Again").frame(maxWidth: .infinity, minHeight: 48) }.buttonStyle(StudioActionStyle())
                }
                Spacer()
            }
            .padding(18).background(Color.ink)
            .navigationTitle("Ear training").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { session.sheet = nil } } }
        }
        .tint(.mint)
        .onAppear { if questions.isEmpty { start() } }
    }
    private func start() { seed &+= 1; questions = EarTraining.questions(session.project, count: 8, seed: seed); index = 0; score = 0; answered = nil }
    private func answer(_ choice: Chord, question: EarTraining.Question) {
        answered = choice.symbol
        if choice.symbol == question.chord.symbol { score += 1; Luz.Haptics.success() } else { Luz.Haptics.warning() }
    }
    private func color(_ choice: Chord, question: EarTraining.Question) -> Color {
        guard let answered else { return Color.panel }
        if choice.symbol == question.chord.symbol { return Color.mint.opacity(0.35) }
        return choice.symbol == answered ? Color.record.opacity(0.3) : Color.panel
    }
}

/// I69 · I66 · The idea of the day and what you have made, at the top of Projects.
struct DailyIdeaCard: View {
    @Bindable var session: Session
    var body: some View {
        let idea = DailyPrompt.idea(for: Date())
        let stats = CreativeStats.summarize(session.entries.compactMap(\.summary))
        VStack(alignment: .leading, spacing: 8) {
            HStack { Image(systemName: "sparkles").foregroundStyle(Color.mint); Text("IDEA OF THE DAY").font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(Color.muted) }
            Text(LocalizedStringKey(idea.task)).font(.callout.weight(.medium)).fixedSize(horizontal: false, vertical: true)
            Text(verbatim: "\(idea.bpm) BPM · " + Chord.roots[idea.keyRoot] + " " + NSLocalizedString(idea.minor ? "minor" : "major", comment: "Key mode"))
                .font(.caption.monospacedDigit()).foregroundStyle(Color.muted)
            Button {
                Task { await session.create(name: "", bpm: Double(idea.bpm), root: idea.keyRoot, minor: idea.minor, bars: 8); session.sheet = nil }
            } label: { Text("Start this idea").frame(maxWidth: .infinity, minHeight: 44) }
                .buttonStyle(StudioActionStyle(color: .mint, prominent: false)).accessibilityIdentifier("daily.start")
            if stats.projects > 0 {
                Text("\(stats.projects) songs · \(String(format: "%.1f", stats.minutesOfMusic)) min of music · \(stats.editedThisWeek) this week")
                    .font(.caption).foregroundStyle(Color.muted).accessibilityIdentifier("daily.stats")
            }
        }
        .padding(14).background(Color.panel, in: RoundedRectangle(cornerRadius: Luz.Radius.card, style: .continuous))
        .accessibilityElement(children: .contain).accessibilityIdentifier("daily")
    }
}
