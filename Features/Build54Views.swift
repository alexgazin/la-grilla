import SwiftUI
import MusicDomain

/// 54 · Share the song as a link others open with "Make your version". The music rides inside the
/// link; recorded and imported sounds stay in the project file.
struct RemixShareSection: View {
    @Bindable var session: Session
    @AppStorage("remix.author") private var author = ""
    private var allowed: Bool { RemixLink.allowsRemix(session.project.license) }
    private var link: Result<URL, Error> { Result { try session.remixLink(author: author) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SmallHeading(text: "REMIX LINK")
            if let credit = session.project.remixOf {
                Text(credit.author.map { String(format: NSLocalizedString("Your version of “%@” by %@", comment: "Remix credit"), credit.title, $0) }
                     ?? String(format: NSLocalizedString("Your version of “%@”", comment: "Remix credit"), credit.title))
                    .font(.caption).foregroundStyle(Color.muted).accessibilityIdentifier("remix.credit")
            }
            if !allowed {
                Text("Choose how others may use the song. A link lets them open it and make their version, with your name on it.")
                    .font(.caption).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    licenceButton(.attribution, title: "Remix with credit", identifier: "remix.allow")
                    licenceButton(.nonCommercial, title: "Not for sale", identifier: "remix.allow-nc")
                }
            } else {
                TextField("Your name on the remix (optional)", text: $author).textInputAutocapitalization(.words)
                    .accessibilityIdentifier("remix.author")
                switch link {
                case .success(let url):
                    ShareLink(item: url, subject: Text(session.project.name), message: Text("Make your version in La Grilla. If the link does not open, copy it and tap Paste in La Grilla › Projects.")) {
                        Label("Share remix link", systemImage: "link").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(StudioActionStyle()).accessibilityIdentifier("remix.share")
                    Text("Notes, chords, beat and mix go in the link; it opens La Grilla directly, nothing is uploaded. Recorded and imported sounds travel only in the project file.")
                        .font(.caption).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
                case .failure(let error):
                    Text(error.localizedDescription).font(.caption).foregroundStyle(Color.record).accessibilityIdentifier("remix.error")
                }
            }
        }
        .padding(14)
        .background(Color.panel, in: RoundedRectangle(cornerRadius: Luz.Radius.card, style: .continuous))
    }

    private func licenceButton(_ licence: SongLicense, title: LocalizedStringKey, identifier: String) -> some View {
        Button { session.edit { $0.license = licence.rawValue } } label: {
            Text(title).frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(StudioQuietButtonStyle()).accessibilityIdentifier(identifier)
    }
}

/// 54 · This week's challenge with its rules ticked against the open song, and a clip to post.
struct WeeklyChallengeCard: View {
    @Bindable var session: Session
    private var challenge: WeeklyChallenge { WeeklyChallenge.current() }

    var body: some View {
        let checks = challenge.check(session.project)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Challenge of the week", systemImage: "flag.checkered").font(.caption.weight(.semibold)).foregroundStyle(Color.mint)
                Spacer()
                Text(verbatim: challenge.tag).font(.caption.monospaced()).foregroundStyle(Color.muted).textSelection(.enabled)
            }
            Text(LocalizedStringKey(challenge.title)).font(.headline)
            Text(LocalizedStringKey(challenge.idea)).font(.caption).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
            ForEach(Array(checks.enumerated()), id: \.offset) { index, check in
                Label(check.rule.title, systemImage: check.met ? "checkmark.circle.fill" : "circle")
                    .font(.callout).foregroundStyle(check.met ? Color.mint : Color.studioText)
                    .accessibilityValue(Text(check.met ? "Done" : "Not yet"))
                    .accessibilityIdentifier("challenge.rule.\(index)")
            }
            if checks.allSatisfy(\.met) {
                Button {
                    session.exportPreset = Session.ExportFormat.video.rawValue
                    session.exportClip = .medium
                    session.sheet = .export
                } label: { Label("Post my entry", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity, minHeight: 44) }
                    .buttonStyle(StudioActionStyle()).accessibilityIdentifier("challenge.post")
            } else {
                Text(String(format: NSLocalizedString("Checked against “%@”.", comment: "Challenge"), session.project.name))
                    .font(.caption2).foregroundStyle(Color.muted)
            }
        }
        .padding(14)
        .background(Color.panel, in: RoundedRectangle(cornerRadius: Luz.Radius.card, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("challenge.card")
    }
}

// MARK: - 54 · Harmony course

/// Lessons with an example to hear and an exercise checked on your song; a teacher section that
/// sends assignments as project files and lists the results of songs sent back.
struct HarmonyCourseView: View {
    @Bindable var session: Session
    @AppStorage("course.done") private var done = ""
    @AppStorage("teacher.name") private var teacher = ""
    @Environment(\.dismiss) private var dismiss
    private var doneIDs: Set<String> { Set(done.split(separator: ",").map(String.init)) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(HarmonyCourse.lessons.enumerated()), id: \.element.id) { index, lesson in
                        NavigationLink(value: lesson.id) {
                            HStack(spacing: 12) {
                                Text("\(index + 1)").font(.callout.monospacedDigit().weight(.semibold)).foregroundStyle(Color.muted).frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(LocalizedStringKey(lesson.title)).font(.body.weight(.medium))
                                    Text(verbatim: lesson.example.map(\.roman).joined(separator: " – ")).font(.caption.monospaced()).foregroundStyle(Color.muted)
                                }
                                Spacer()
                                if doneIDs.contains(lesson.id) {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.mint).accessibilityLabel("Done")
                                }
                            }.frame(minHeight: 44)
                        }
                        .accessibilityIdentifier("course.lesson.\(lesson.id)")
                    }
                } header: { Text("Lessons") } footer: {
                    Text(String(format: NSLocalizedString("%d of %d done. Each exercise is checked on your own song.", comment: "Course"), doneIDs.intersection(HarmonyCourse.lessons.map(\.id)).count, HarmonyCourse.lessons.count))
                }
                Section {
                    TextField("Your name for students", text: $teacher).textInputAutocapitalization(.words).accessibilityIdentifier("course.teacher-name")
                    Button {
                        guard let assignment = HarmonyAssignment.progression(of: session.project, title: session.project.name, teacher: teacher.isEmpty ? nil : teacher) else { return }
                        Task { await session.shareAssignment(assignment, bars: max(4, min(16, HarmonyCourse.chords(session.project).count))) }
                    } label: { Label("Make an assignment from my chords", systemImage: "square.and.arrow.up") }
                        .disabled(HarmonyCourse.chords(session.project).count < 2)
                        .accessibilityIdentifier("course.assign-mine")
                } header: { Text("For teachers") } footer: {
                    Text("Students open the file, write the chords and send their song back. Opening it here adds their result below.")
                }
                Section {
                    if session.assignmentResults.isEmpty {
                        Text("No songs from students yet.").foregroundStyle(Color.muted)
                    }
                    ForEach(session.assignmentResults) { result in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: result.student).font(.body.weight(.medium))
                                Text(verbatim: result.title).font(.caption).foregroundStyle(Color.muted)
                            }
                            Spacer()
                            Text(verbatim: "\(result.met)/\(result.total)").font(.callout.monospacedDigit().weight(.semibold))
                                .foregroundStyle(result.met == result.total ? Color.mint : Color.studioText)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("course.result.\(result.student)")
                    }
                    if !session.assignmentResults.isEmpty {
                        Button("Clear results", role: .destructive) { session.clearAssignmentResults() }
                    }
                } header: { Text("Results from students") }
            }
            .navigationTitle("Harmony course").navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { id in
                if let lesson = HarmonyCourse.lesson(id) { LessonView(session: session, lesson: lesson, teacher: teacher) }
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("course.done") } }
        }
        .onDisappear { session.endHarmonyPreview() }
    }
}

private struct LessonView: View {
    @Bindable var session: Session
    let lesson: Lesson
    let teacher: String
    @State private var root = 0
    @State private var playing = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(LocalizedStringKey(lesson.title)).font(StudioTypography.title)
                ForEach(lesson.text, id: \.self) { paragraph in
                    Text(LocalizedStringKey(paragraph)).fixedSize(horizontal: false, vertical: true)
                }
                Picker("Key", selection: $root) {
                    ForEach(0..<12, id: \.self) { index in
                        Text(verbatim: MusicalNotation.pitchClassName(index, keyRoot: index, minor: lesson.minor) + " " + NSLocalizedString(lesson.minor ? "minor" : "major", comment: "Key mode")).tag(index)
                    }
                }.pickerStyle(.menu).accessibilityIdentifier("lesson.key")
                HStack(spacing: 6) {
                    ForEach(Array(lesson.example.enumerated()), id: \.offset) { _, degree in
                        VStack(spacing: 2) {
                            Text(verbatim: degree.roman).font(.caption.weight(.semibold)).foregroundStyle(Color.muted)
                            Text(verbatim: MusicalNotation.chordSymbol(degree.chord(keyRoot: root), keyRoot: root, minor: lesson.minor)).font(.headline)
                        }
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(Color.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("lesson.example")
                Button {
                    if playing { session.endHarmonyPreview(); playing = false; return }
                    guard let example = try? HarmonyCourse.example(lesson, root: root) else { return }
                    playing = session.holdPreview(example, range: 0..<example.length)
                } label: { Label(playing ? "Stop" : "Hear the example", systemImage: playing ? "stop.fill" : "play.fill").frame(maxWidth: .infinity, minHeight: 44) }
                    .buttonStyle(StudioQuietButtonStyle()).accessibilityIdentifier("lesson.play")
                SmallHeading(text: "EXERCISE")
                ForEach(Array(lesson.rules.enumerated()), id: \.offset) { _, rule in
                    Label(rule.title, systemImage: "music.note.list").font(.callout)
                }
                Text(LocalizedStringKey(lesson.hint)).font(.caption).foregroundStyle(Color.muted)
                Button {
                    session.endHarmonyPreview()
                    Task { if await session.startLesson(lesson, root: root) { session.sheet = nil } }
                } label: { Label("Try it in a new song", systemImage: "pencil.and.outline").frame(maxWidth: .infinity, minHeight: 48) }
                    .buttonStyle(StudioActionStyle()).accessibilityIdentifier("lesson.try")
                Button {
                    session.endHarmonyPreview()
                    Task { await session.shareAssignment(HarmonyAssignment(lesson: lesson, keyRoot: root, teacher: teacher.isEmpty ? nil : teacher), bars: max(4, lesson.example.count)) }
                } label: { Label("Send to students as an assignment", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity, minHeight: 44) }
                    .buttonStyle(StudioQuietButtonStyle()).accessibilityIdentifier("lesson.assign")
            }
            .padding(18)
        }
        .background(Color.ink)
        .navigationTitle(LocalizedStringKey(lesson.title)).navigationBarTitleDisplayMode(.inline)
        .onAppear { root = session.project.minor == lesson.minor ? session.project.keyRoot : 0 }
        .onDisappear { if playing { session.endHarmonyPreview() } }
    }
}

/// 54 · On a song with a lesson's exercise or a teacher's assignment: what is done, and a way to
/// send it back.
struct AssignmentCheckCard: View {
    @Bindable var session: Session
    @AppStorage("course.done") private var done = ""
    @AppStorage("student.name") private var student = ""

    var body: some View {
        if let assignment = session.project.harmonyAssignment {
            let checks = assignment.check(session.project)
            let complete = checks.allSatisfy(\.met)
            VStack(alignment: .leading, spacing: 8) {
                Label(assignment.teacher.map { String(format: NSLocalizedString("Assignment from %@", comment: "Assignment"), $0) } ?? NSLocalizedString("Exercise", comment: "Assignment"),
                      systemImage: "graduationcap").font(.caption.weight(.semibold)).foregroundStyle(Color.mint)
                Text(LocalizedStringKey(assignment.title)).font(.headline)
                ForEach(Array(checks.enumerated()), id: \.offset) { index, check in
                    Label(check.rule.title, systemImage: check.met ? "checkmark.circle.fill" : "circle")
                        .font(.callout).foregroundStyle(check.met ? Color.mint : Color.studioText)
                        .accessibilityValue(Text(check.met ? "Done" : "Not yet"))
                        .accessibilityIdentifier("assignment.rule.\(index)")
                }
                if !complete, let hint = assignment.hint { Text(LocalizedStringKey(hint)).font(.caption).foregroundStyle(Color.muted) }
                if let name = assignment.student, let date = assignment.submittedAt {
                    Text(String(format: NSLocalizedString("Sent by %@, %@", comment: "Assignment"), name, date.formatted(date: .abbreviated, time: .shortened)))
                        .font(.caption).foregroundStyle(Color.muted).accessibilityIdentifier("assignment.sent")
                } else if complete && assignment.teacher != nil {
                    TextField("Your name", text: $student).textInputAutocapitalization(.words).accessibilityIdentifier("assignment.student")
                    Button { session.submitAssignment(student: student) } label: {
                        Label("Send to the teacher", systemImage: "paperplane").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(StudioActionStyle()).disabled(student.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("assignment.send")
                } else if complete {
                    Text("Done! The next lesson is waiting in the course.").font(.caption).foregroundStyle(Color.mint).accessibilityIdentifier("assignment.done")
                }
            }
            .padding(14)
            .background(Color.panel, in: RoundedRectangle(cornerRadius: Luz.Radius.card, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("assignment.card")
            .onChange(of: complete, initial: true) { _, now in
                guard now, let lesson = assignment.lessonID else { return }
                var ids = Set(done.split(separator: ",").map(String.init))
                if ids.insert(lesson).inserted { done = ids.sorted().joined(separator: ","); session.showToast("Lesson done") }
            }
        }
    }
}
