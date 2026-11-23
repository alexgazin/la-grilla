import SwiftUI
import MusicDomain

/// I63 · Stage visuals: full-screen spectrum, the beat flashing, the song and section in big
/// type — for a screen behind you (AirPlay mirroring works as is). Reads only the audio
/// meters at 20 Hz, never the render thread.
struct StageVJView: View {
    @Bindable var session: Session
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 24) {
                Text(verbatim: session.project.name).font(.system(size: 44, weight: .heavy)).foregroundStyle(.white).lineLimit(2).minimumScaleFactor(0.5)
                Text(verbatim: session.section.name.uppercased()).font(.system(size: 22, weight: .semibold, design: .monospaced)).foregroundStyle(Color.mint)
                StageBeatFlash(audio: session.audio).frame(height: 18)
                MasterSpectrum(audio: session.audio).frame(maxHeight: 280).padding(.horizontal, 12)
                HStack(spacing: 24) {
                    Button { session.togglePlay() } label: {
                        Image(systemName: session.audio.playing ? "stop.fill" : "play.fill").font(.system(size: 34, weight: .bold)).frame(width: 84, height: 84)
                    }.buttonStyle(StudioActionStyle(color: .mint, prominent: true)).accessibilityLabel(LocalizedStringKey(session.audio.playing ? "Stop" : "Play"))
                        .accessibilityIdentifier("vj.play")
                    Button { session.sheet = nil } label: { Image(systemName: "xmark").font(.title2).frame(width: 64, height: 64) }
                        .buttonStyle(StudioActionStyle(color: .mint, prominent: false)).accessibilityLabel("Close").accessibilityIdentifier("vj.close")
                }
            }.padding(24)
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }
}

private struct StageBeatFlash: View {
    let audio: AudioController
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !audio.playing)) { _ in
            let position = Int(audio.tick)
            let beat = (position % barTicks) / ppq, phase = Double(position % ppq) / Double(ppq)
            HStack(spacing: 10) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule().fill(index == beat ? (beat == 0 ? Color.mint : Color.harmony) : Color.white.opacity(0.12))
                        .opacity(index == beat ? max(0.35, 1 - phase) : 1)
                }
            }
        }.accessibilityHidden(true)
    }
}

/// I67 · Settings in one file: theme, notation, comfort, metronome look, quick bar, export
/// habits — to move to a new device or share with a bandmate. Never project data.
enum SettingsTransfer {
    static let prefixes = ["studio.", "commands.", "projects.order", "nextStep.", "export.", "notes.author", "jam."]
    static func export() throws -> URL {
        let all = UserDefaults.standard.dictionaryRepresentation()
        var picked: [String: Any] = [:]
        for (key, value) in all where prefixes.contains(where: { key.hasPrefix($0) }) && JSONSerialization.isValidJSONObject([key: value]) { picked[key] = value }
        let data = try JSONSerialization.data(withJSONObject: ["laGrillaSettings": 1, "values": picked], options: [.sortedKeys, .prettyPrinted])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("La Grilla settings.json")
        try data.write(to: url, options: .atomic)
        return url
    }
    @discardableResult static func importFile(_ url: URL) throws -> Int {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any], object["laGrillaSettings"] as? Int == 1,
              let values = object["values"] as? [String: Any] else { throw MusicError.invalidProject }
        var count = 0
        for (key, value) in values where prefixes.contains(where: { key.hasPrefix($0) }) { UserDefaults.standard.set(value, forKey: key); count += 1 }
        return count
    }
}
