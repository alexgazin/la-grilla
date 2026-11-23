import AVFoundation
import MusicDomain
import SwiftUI
import UIKit

// MARK: - I35 Tuner

/// The newest microphone samples for the tuner, shared between the input drain and the UI.
final class TunerBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
    private(set) var rate: Double = 48_000
    private let capacity = 8_192

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        let count = Int(buffer.frameLength), channelCount = Int(buffer.format.channelCount)
        guard count > 0, channelCount > 0 else { return }
        var mono = [Float](repeating: 0, count: count)
        let stride = buffer.format.isInterleaved ? channelCount : 1
        for channel in 0..<(buffer.format.isInterleaved ? 1 : channelCount) {
            let data = channels[channel]
            for frame in 0..<count {
                if buffer.format.isInterleaved {
                    var sum: Float = 0
                    for c in 0..<channelCount { sum += data[frame * stride + c] }
                    mono[frame] += sum / Float(channelCount)
                } else {
                    mono[frame] += data[frame] / Float(channelCount)
                }
            }
        }
        lock.lock()
        rate = buffer.format.sampleRate
        samples.append(contentsOf: mono)
        if samples.count > capacity { samples.removeFirst(samples.count - capacity) }
        lock.unlock()
    }

    func snapshot() -> (samples: [Float], rate: Double) {
        lock.lock(); defer { lock.unlock() }
        return (samples, rate)
    }
}

/// Microphone, analysis loop and the latest reading for the tuner screen.
@MainActor @Observable final class TunerModel {
    var reading: Tuner.Reading?
    var smoothedCents = 0.0
    var problem: String?
    var denied = false
    var listening = false
    var reference = 440.0
    @ObservationIgnored private var microphone: LiveMicrophone?
    @ObservationIgnored private var owner: UUID?
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private let buffer = TunerBuffer()

    func start(_ session: Session) async {
        guard microphone == nil else { return }
        guard await AVAudioApplication.requestRecordPermission() else {
            denied = true
            problem = NSLocalizedString("The tuner needs the microphone. Allow it for La Grilla in Settings.", comment: "Tuner")
            return
        }
        guard session.ensureAudio() else { problem = session.audio.error ?? NSLocalizedString("Audio could not start.", comment: "Tuner"); return }
        let sink = buffer
        do {
            let mic = try LiveMicrophone(audio: session.audio, delay: 0, duration: 600,
                                         receiver: { _ in LiveInputReceiver(receive: { @Sendable buffer in sink.append(buffer) }, finish: { @Sendable in }) },
                                         onFailure: { [weak self] message in self?.problem = message; self?.listening = false })
            microphone = mic
            owner = session.beginMicrophone { try? mic.stop() }
            listening = true
            loop = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(90))
                    guard let self, self.listening else { return }
                    self.analyze()
                }
            }
        } catch {
            problem = error.localizedDescription
        }
    }

    private func analyze() {
        let snapshot = buffer.snapshot()
        guard let next = Tuner.detect(snapshot.samples, sampleRate: snapshot.rate, reference: reference) else {
            if microphone?.complete == true { listening = false }
            return
        }
        withAnimation(.easeOut(duration: 0.12)) {
            smoothedCents = reading?.note == next.note ? smoothedCents * 0.6 + next.cents * 0.4 : next.cents
            reading = next
        }
    }

    func stop(_ session: Session) {
        listening = false
        loop?.cancel(); loop = nil
        try? microphone?.stop()
        microphone = nil
        if let owner { session.endMicrophone(owner) }
        owner = nil
    }
}

struct TunerView: View {
    @Bindable var session: Session
    enum Instrument: String, CaseIterable { case chromatic, guitar, bass, ukulele }
    @State private var instrument: Instrument = .chromatic
    @AppStorage("tuner.reference") private var reference = 440.0
    @State private var model = TunerModel()
    @Environment(\.scenePhase) private var phase

    private var reading: Tuner.Reading? { model.reading }
    private var smoothedCents: Double { model.smoothedCents }
    private var listening: Bool { model.listening }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    StudioSegments(title: "Instrument", selection: $instrument,
                                   options: [(.chromatic, "Chromatic"), (.guitar, "Guitar"), (.bass, "Bass"), (.ukulele, "Ukulele")], identifier: "tuner.instrument")
                    gauge
                    if instrument != .chromatic { strings }
                    Stepper(value: $reference, in: 430...450, step: 1) {
                        LabeledContent("Reference A4", value: "\(Int(reference)) Hz")
                    }.accessibilityIdentifier("tuner.reference")
                    if let problem = model.problem {
                        VStack(spacing: 8) {
                            Text(problem).font(.callout).foregroundStyle(Color.record).multilineTextAlignment(.center)
                            if model.denied {
                                Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                                    .buttonStyle(StudioActionStyle(prominent: false)).accessibilityIdentifier("tuner.settings")
                            }
                        }
                    }
                    Text("Play one string or note at a time. The tuner listens only while this screen is open.")
                        .font(.caption).foregroundStyle(Color.muted).multilineTextAlignment(.center)
                }.padding(18)
            }
            .background(Color.ink)
            .navigationTitle("Tuner").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { session.sheet = nil } } }
        }
        .tint(.mint)
        .task { model.reference = reference; await model.start(session) }
        .onChange(of: reference) { _, value in model.reference = value }
        .onChange(of: phase) { _, value in if value != .active { model.stop(session) } }
        .onDisappear { model.stop(session) }
    }

    private var gauge: some View {
        let tuned = reading.map { abs(smoothedCents) <= 5 } ?? false
        return VStack(spacing: 6) {
            ZStack {
                Canvas { context, size in
                    let center = CGPoint(x: size.width / 2, y: size.height * 0.92)
                    let radius = min(size.width / 2, size.height) * 0.86
                    for mark in stride(from: -50, through: 50, by: 5) {
                        let angle = Angle.degrees(Double(mark) * 1.6 - 90).radians
                        let long = mark % 25 == 0
                        let inner = radius * (long ? 0.82 : 0.9)
                        var path = Path()
                        path.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
                        path.addLine(to: CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius))
                        context.stroke(path, with: .color(abs(mark) <= 5 ? Color.mint : Color.muted.opacity(long ? 0.9 : 0.45)), lineWidth: long ? 2.5 : 1.5)
                    }
                    if reading != nil {
                        let angle = Angle.degrees(max(-50, min(50, smoothedCents)) * 1.6 - 90).radians
                        var needle = Path()
                        needle.move(to: center)
                        needle.addLine(to: CGPoint(x: center.x + cos(angle) * radius * 0.95, y: center.y + sin(angle) * radius * 0.95))
                        context.stroke(needle, with: .color(tuned ? Color.mint : Color.harmony), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        context.fill(Path(ellipseIn: CGRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14)), with: .color(tuned ? Color.mint : Color.harmony))
                    }
                }
                .frame(height: 170)
                .accessibilityHidden(true)
            }
            Text(verbatim: reading.map { noteName($0) } ?? "–")
                .font(.system(size: 64, weight: .bold, design: .rounded)).foregroundStyle(tuned ? Color.mint : Color.studioText)
                .contentTransition(.numericText()).accessibilityIdentifier("tuner.note")
            Text(verbatim: reading.map { String(format: "%+.0f ¢ · %.1f Hz", smoothedCents, $0.frequency) } ?? NSLocalizedString(listening ? "Listening…" : "Starting the microphone…", comment: "Tuner"))
                .font(.subheadline.monospacedDigit()).foregroundStyle(Color.muted).accessibilityIdentifier("tuner.cents")
            if reading != nil {
                Text(LocalizedStringKey(tuned ? "In tune" : smoothedCents < 0 ? "Flat: tune up" : "Sharp: tune down"))
                    .font(.headline).foregroundStyle(tuned ? Color.mint : Color.harmony)
            }
        }
        .padding(16).frame(maxWidth: .infinity)
        .background(Color.panel, in: RoundedRectangle(cornerRadius: Luz.Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var strings: some View {
        let targets: [Int] = switch instrument { case .guitar: Tuner.guitar; case .bass: Tuner.bass; case .ukulele: Tuner.ukulele; case .chromatic: [] }
        let nearest = reading.flatMap { value in targets.min { abs($0 - value.note) < abs($1 - value.note) } }
        return HStack(spacing: 8) {
            ForEach(targets, id: \.self) { note in
                Text(verbatim: Chord.roots[note % 12] + String(note / 12 - 1))
                    .font(.headline.monospaced()).frame(maxWidth: .infinity, minHeight: 44)
                    .background(note == nearest ? Color.mint.opacity(0.25) : Color.panel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .foregroundStyle(note == nearest ? Color.mint : Color.studioText)
            }
        }.accessibilityIdentifier("tuner.strings")
    }

    private func noteName(_ value: Tuner.Reading) -> String {
        MusicalNotation.pitchClassName(((value.note % 12) + 12) % 12, keyRoot: session.project.keyRoot, minor: session.project.minor) + String(value.note / 12 - 1)
    }

}

// MARK: - I39 Markers

struct MarkersView: View {
    @Bindable var session: Session
    @State private var text = ""
    @FocusState private var typing: Bool

    private var markers: [Marker] { session.project.markers ?? [] }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Add vocals here", text: $text).focused($typing).submitLabel(.done).onSubmit(add)
                            .accessibilityIdentifier("markers.text")
                        Button("Add", action: add).disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                            .accessibilityIdentifier("markers.add")
                    }
                } footer: {
                    Text(String(format: NSLocalizedString("The marker goes at the playhead, bar %@.", comment: "Markers"), MarkerEditing.position(Int(session.audio.tick))))
                }
                Section {
                    if markers.isEmpty {
                        Text("No markers yet. Pin a note to a place in the song: what to change, where the vocals start.")
                            .font(.callout).foregroundStyle(Color.muted)
                    }
                    ForEach(Array(markers.enumerated()), id: \.element.id) { index, marker in
                        Button { jump(marker) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "flag.fill").foregroundStyle(Color.harmony)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: marker.text).foregroundStyle(Color.studioText)
                                    Text(verbatim: sectionName(marker) + " · " + MarkerEditing.position(marker.tick)).font(.caption.monospacedDigit()).foregroundStyle(Color.muted)
                                }
                                Spacer()
                                Image(systemName: "arrow.right.circle").foregroundStyle(Color.muted)
                            }
                        }
                        .accessibilityHint("Moves the playhead here")
                        .accessibilityIdentifier("markers.row.\(index)")
                        .swipeActions {
                            Button("Delete", role: .destructive) { session.edit { MarkerEditing.remove(marker.id, in: &$0) } }
                        }
                    }
                } header: { Text("In this song") }
            }
            .navigationTitle("Markers").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { session.sheet = nil } } }
        }
        .tint(.mint)
    }

    private func sectionName(_ marker: Marker) -> String {
        session.project.sections.first { $0.start <= marker.tick && marker.tick < $0.start + $0.length }?.name ?? ""
    }

    private func add() {
        let note = text, tick = Int(session.audio.tick)
        guard !note.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        session.edit { try MarkerEditing.add(note, at: tick, in: &$0) }
        text = ""
        Luz.Haptics.success()
    }

    private func jump(_ marker: Marker) {
        if let section = session.project.sections.first(where: { $0.start <= marker.tick && marker.tick < $0.start + $0.length }) {
            session.select(section)
        }
        if !session.audio.playing { session.audio.seek(marker.tick) } else { session.audio.restartAt(marker.tick) }
        Luz.Haptics.selection()
    }
}

// MARK: - I38 Song dynamics

struct DynamicsView: View {
    @Bindable var session: Session
    enum Source: Hashable { case current, shaped }
    @State private var roles: [UUID: ArrangementDynamics.Role] = [:]
    @State private var source: Source = .shaped
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("The same parts, thinned and filled so the song breathes: a sparse intro, a lighter verse, a full chorus with a crash, a contrasting bridge.")
                        .font(.caption).foregroundStyle(Color.muted)
                    let before = ArrangementDynamics.density(session.project)
                    let shaped = candidate()
                    let after = shaped.map(ArrangementDynamics.density) ?? before
                    let peak = max(1, (before.values + after.values).max() ?? 1)
                    ForEach(Array(session.project.sections.enumerated()), id: \.element.id) { index, section in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: section.name).font(.headline)
                                Menu {
                                    ForEach(ArrangementDynamics.Role.allCases, id: \.self) { role in
                                        Button(LocalizedStringKey(role.title)) { roles[section.id] = role }
                                    }
                                } label: {
                                    Label(LocalizedStringKey((roles[section.id] ?? .keep).title), systemImage: "slider.horizontal.3").font(.subheadline)
                                }.accessibilityIdentifier("dynamics.role.\(index)")
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                bar(before[section.id] ?? 0, peak: peak, color: Color.muted)
                                bar(after[section.id] ?? 0, peak: peak, color: Color.drums)
                            }.frame(width: 120).accessibilityHidden(true)
                        }
                        .padding(12)
                        .background(Color.panel, in: RoundedRectangle(cornerRadius: Luz.Radius.card, style: .continuous))
                    }
                    HStack(spacing: 14) {
                        Label("As it is", systemImage: "circle.fill").foregroundStyle(Color.muted)
                        Label("With dynamics", systemImage: "circle.fill").foregroundStyle(Color.drums)
                    }.font(.caption)
                    AuditionBar(screen: "dynamics", source: $source, sources: [(.current, "As it is"), (.shaped, "With dynamics")],
                                playing: session.harmonyPreview, enabled: shaped != nil,
                                caption: "Chords and locked tracks stay. Nothing changes until you apply.", play: play, stop: { session.endHarmonyPreview() })
                    if let error { Text(error).font(.caption).foregroundStyle(Color.record) }
                    Button { apply() } label: { Text("Apply dynamics").frame(maxWidth: .infinity, minHeight: 48) }
                        .buttonStyle(StudioActionStyle()).disabled(shaped == nil || session.recording || session.armed)
                        .accessibilityIdentifier("dynamics.apply")
                }.padding(18)
            }
            .background(Color.ink)
            .navigationTitle("Song dynamics").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { session.endHarmonyPreview(); session.sheet = nil } } }
        }
        .tint(.mint)
        .onAppear { if roles.isEmpty { roles = ArrangementDynamics.plan(session.project) } }
        .onDisappear { session.endHarmonyPreview() }
    }

    private func bar(_ value: Double, peak: Double, color: Color) -> some View {
        GeometryReader { proxy in
            Capsule().fill(color).frame(width: max(4, proxy.size.width * value / peak))
        }.frame(height: 6)
    }

    private func candidate() -> Project? { try? ArrangementDynamics.apply(session.project, roles: roles) }

    private func play() {
        if source == .current { session.previewSnapshot(session.project) } else if let project = candidate() { session.previewSnapshot(project) }
    }

    private func apply() {
        let plan = roles
        session.endHarmonyPreview()
        session.edit { $0 = try ArrangementDynamics.apply($0, roles: plan) }
        session.sheet = nil
        Luz.Haptics.success()
    }
}
