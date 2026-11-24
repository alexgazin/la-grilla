import Foundation

/// 54 · Export to DAWproject 1.0, the open project format read by Bitwig Studio, Studio One,
/// Cubase 14, and on iPhone and iPad by Cubasis 3.7 and n-Track Studio. Every part goes over as
/// an instrument track with its notes (choose an instrument in the DAW) and as an aligned audio
/// track with the sound you hear in La Grilla; tempo, time signature, mix levels and section
/// markers come along. The XML is checked against the official schema in the tests.
public enum DAWProject {
    public static let fileExtension = "dawproject"

    /// One rendered stem in the package: the file name inside the zip and the track it belongs to.
    public struct Stem: Sendable {
        public let trackIndex: Int
        public let file: String
        public init(trackIndex: Int, file: String) { self.trackIndex = trackIndex; self.file = file }
    }

    /// The stems StemExporter writes for `project` (one per track, "01-harmony.wav" …).
    public static func stems(_ project: Project) -> [Stem] {
        project.tracks.enumerated().map { Stem(trackIndex: $0.offset, file: String(format: "%02d", $0.offset + 1) + "-" + $0.element.role.rawValue + ".wav") }
    }

    /// project.xml and metadata.xml for the package, added next to the stems.
    public static func entries(_ project: Project, range: Range<Int>? = nil, settings: WAVSettings, version: String) -> [ProjectArchive.Entry] {
        [.init("project.xml", Data(projectXML(project, range: range, stems: stems(project), settings: settings, version: version).utf8)),
         .init("metadata.xml", Data(metadataXML(project).utf8))]
    }

    public static func metadataXML(_ project: Project) -> String {
        var lines = ["<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>", "<MetaData>", "  <Title>\(escape(project.name))</Title>"]
        if let credit = project.remixOf {
            lines.append("  <OriginalArtist>\(escape(credit.author ?? credit.title))</OriginalArtist>")
        }
        lines.append("  <Comment>\(escape("\(Int(project.bpm.rounded())) BPM · \(project.keyName) · La Grilla"))</Comment>")
        lines.append("</MetaData>")
        return lines.joined(separator: "\n") + "\n"
    }

    public static func projectXML(_ project: Project, range: Range<Int>? = nil, stems: [Stem], settings: WAVSettings, version: String) -> String {
        let range = range ?? 0..<project.length
        var nextID = 0
        func id() -> String { defer { nextID += 1 }; return "id\(nextID)" }
        func beats(_ ticks: Int) -> String { number(Double(ticks) / Double(ppq)) }
        let songBeats = beats(range.count)
        let seconds = Double(range.count) / Double(ppq) * 60 / project.bpm
        let audioSeconds = seconds + max(0, settings.tailSeconds)
        let anySolo = project.tracks.contains(where: \.solo)
        let notes = Compiler.notes(project, range: range)

        var structure: [String] = []
        var lanes: [String] = []
        // The master is allocated first so every track can send to its channel.
        let master = id(), masterID = id()
        func channel(_ track: Track?, role: String, destination: String?, channelID fixed: String? = nil) -> [String] {
            let channelID = fixed ?? id()
            let gain = track.map { pow(10, $0.gain / 20) } ?? pow(10, project.master / 20)
            let pan = track.map { ($0.pan + 1) / 2 } ?? 0.5
            let muted = track.map { $0.mute || (anySolo && !$0.solo) } ?? false
            var attributes = "audioChannels=\"2\" role=\"\(role)\" solo=\"false\" id=\"\(channelID)\""
            if let destination { attributes = "audioChannels=\"2\" destination=\"\(destination)\" role=\"\(role)\" solo=\"false\" id=\"\(channelID)\"" }
            return ["      <Channel \(attributes)>",
                    "        <Mute value=\"\(muted)\" id=\"\(id())\" name=\"Mute\"/>",
                    "        <Pan max=\"1.000000\" min=\"0.000000\" unit=\"normalized\" value=\"\(number(min(1, max(0, pan))))\" id=\"\(id())\" name=\"Pan\"/>",
                    "        <Volume max=\"2.000000\" min=\"0.000000\" unit=\"linear\" value=\"\(number(min(2, max(0, gain))))\" id=\"\(id())\" name=\"Volume\"/>",
                    "      </Channel>"]
        }

        for (index, track) in project.tracks.enumerated() {
            let colour = colourHex(track)
            // Instrument track with the notes.
            let noteTrack = id()
            structure.append("    <Track contentType=\"notes\" loaded=\"true\" id=\"\(noteTrack)\" name=\"\(escape(track.displayName))\" color=\"\(colour)\">")
            structure += channel(track, role: "regular", destination: masterID)
            structure.append("    </Track>")
            let own = notes.filter { $0.track == index }
            var lane = ["      <Lanes track=\"\(noteTrack)\" id=\"\(id())\">", "        <Clips id=\"\(id())\">"]
            if !own.isEmpty {
                lane.append("          <Clip time=\"0.0\" duration=\"\(songBeats)\" playStart=\"0.0\" name=\"\(escape(track.displayName))\">")
                lane.append("            <Notes id=\"\(id())\">")
                for note in own.sorted(by: { ($0.tick, $0.pitch) < ($1.tick, $1.pitch) }) {
                    let key = note.pad >= 0 ? Compiler.drumMap[note.pad % Compiler.drumMap.count] : note.pitch
                    let velocity = number(Double(max(1, min(127, note.velocity))) / 127)
                    lane.append("              <Note time=\"\(beats(note.tick))\" duration=\"\(beats(max(1, note.duration)))\" channel=\"\(note.pad >= 0 ? 9 : 0)\" key=\"\(max(0, min(127, key)))\" vel=\"\(velocity)\" rel=\"\(velocity)\"/>")
                }
                lane.append("            </Notes>")
                lane.append("          </Clip>")
            }
            lane += ["        </Clips>", "      </Lanes>"]
            lanes += lane
            // Audio track with the rendered stem.
            guard let stem = stems.first(where: { $0.trackIndex == index }) else { continue }
            let audioTrack = id()
            structure.append("    <Track contentType=\"audio\" loaded=\"true\" id=\"\(audioTrack)\" name=\"\(escape(track.displayName + " (audio)"))\" color=\"\(colour)\">")
            structure += channel(track, role: "regular", destination: masterID)
            structure.append("    </Track>")
            lanes += ["      <Lanes track=\"\(audioTrack)\" id=\"\(id())\">",
                      "        <Clips id=\"\(id())\">",
                      "          <Clip time=\"0.0\" duration=\"\(songBeats)\" playStart=\"0.0\" name=\"\(escape(stem.file))\">",
                      "            <Warps contentTimeUnit=\"seconds\" timeUnit=\"beats\" id=\"\(id())\">",
                      "              <Audio algorithm=\"stretch\" channels=\"2\" duration=\"\(number(audioSeconds))\" sampleRate=\"\(Int(settings.sampleRate))\" id=\"\(id())\">",
                      "                <File path=\"\(escape(stem.file))\"/>",
                      "              </Audio>",
                      "              <Warp time=\"0.0\" contentTime=\"0.0\"/>",
                      "              <Warp time=\"\(songBeats)\" contentTime=\"\(number(seconds))\"/>",
                      "            </Warps>",
                      "          </Clip>",
                      "        </Clips>",
                      "      </Lanes>"]
        }
        structure.append("    <Track contentType=\"audio notes\" loaded=\"true\" id=\"\(master)\" name=\"Master\">")
        structure += channel(nil, role: "master", destination: nil, channelID: masterID)
        structure.append("    </Track>")

        let markers = project.sections.filter { $0.start >= range.lowerBound && $0.start < range.upperBound }
            .map { "      <Marker time=\"\(beats($0.start - range.lowerBound))\" name=\"\(escape($0.name))\"/>" }
            + (project.markers ?? []).filter { range.contains($0.tick) }.map { "      <Marker time=\"\(beats($0.tick - range.lowerBound))\" name=\"\(escape($0.text))\"/>" }

        var xml = ["<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>",
                   "<Project version=\"1.0\">",
                   "  <Application name=\"La Grilla\" version=\"\(escape(version))\"/>",
                   "  <Transport>",
                   "    <Tempo max=\"240.000000\" min=\"40.000000\" unit=\"bpm\" value=\"\(number(project.bpm))\" id=\"\(id())\" name=\"Tempo\"/>",
                   "    <TimeSignature denominator=\"4\" numerator=\"4\" id=\"\(id())\"/>",
                   "  </Transport>",
                   "  <Structure>"]
        xml += structure
        xml += ["  </Structure>", "  <Arrangement id=\"\(id())\">", "    <Lanes timeUnit=\"beats\" id=\"\(id())\">"]
        xml += lanes
        xml += ["      <Lanes track=\"\(master)\" id=\"\(id())\">", "        <Clips id=\"\(id())\"/>", "      </Lanes>", "    </Lanes>"]
        if !markers.isEmpty {
            xml.append("    <Markers id=\"\(id())\">")
            xml += markers
            xml.append("    </Markers>")
        }
        xml += ["  </Arrangement>", "  <Scenes/>", "</Project>"]
        return xml.joined(separator: "\n") + "\n"
    }

    static func number(_ value: Double) -> String { String(format: "%.6f", value.isFinite ? value : 0) }

    static func escape(_ text: String) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&apos;"
            default:
                // XML 1.0 has no place for most control characters.
                if scalar.value < 0x20 && scalar != "\t" && scalar != "\n" && scalar != "\r" { continue }
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    static func colourHex(_ track: Track) -> String {
        let palette = ["#E5BE69", "#B7BCEF", "#85D6C3", "#D8F780", "#FF858D"]
        let index = track.color ?? (track.role == .harmony ? 0 : track.role == .drums ? 1 : track.role == .bass ? 2 : 3)
        return palette[max(0, min(palette.count - 1, index))]
    }
}
