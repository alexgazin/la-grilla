import Foundation
import Testing
@testable import MusicDomain

struct MIDIFileImportTests {
    @Test func appOwnMIDIRoundTripsNotesTempoKeyAndMarkers() throws {
        let source = try SongEditDemo.project()
        let data = try MIDIExporter.data(source)
        let imported = try MIDIFileImport.read(data, name: "Round trip").project
        #expect(imported.bpm == source.bpm && imported.keyRoot == source.keyRoot && imported.minor == source.minor)
        #expect(imported.length == source.length)
        #expect(imported.sections.map(\.start) == source.sections.map(\.start))
        #expect(imported.sections.map(\.name) == source.sections.map(\.name))
        // Drums: the same pad hits at the same ticks.
        func drums(_ p: Project) -> [String] { Compiler.notes(p).filter { $0.pad >= 0 }.map { "\($0.tick)-\($0.pad)-\($0.velocity)" }.sorted() }
        #expect(drums(imported) == drums(source))
        // Melodic notes: chords, bass and flute all arrive as notes with exact timing.
        func pitched(_ p: Project) -> [String] { Compiler.notes(p).filter { $0.pad < 0 }.map { "\($0.tick)-\($0.duration)-\($0.pitch)" }.sorted() }
        #expect(pitched(imported) == pitched(source))
        #expect(imported.tracks.filter { $0.role == .melody }.map(\.name) == ["Harmony", "Bass", "Flute"])
    }

    @Test func formatZeroRunningStatusAndOtherDivisions() throws {
        // Format 0, division 480, running status note-ons with velocity-0 note-offs on channel 1 and 10.
        var track: [UInt8] = [0x00, 0xff, 0x51, 0x03, 0x07, 0xa1, 0x20]   // 120 BPM
        track += [0x00, 0x90, 60, 100, 0x83, 0x60, 60, 0]                    // C4 for 480 (quarter at 480 ppq)
        track += [0x00, 0x99, 36, 110, 0x60, 36, 0]                          // kick
        track += [0x00, 0xff, 0x2f, 0x00]
        var file: [UInt8] = Array("MThd".utf8) + [0, 0, 0, 6, 0, 0, 0, 1, 0x01, 0xe0]
        file += Array("MTrk".utf8) + [0, 0, 0, UInt8(track.count)] + track
        let result = try MIDIFileImport.read(Data(file))
        let notes = Compiler.notes(result.project)
        #expect(result.project.bpm == 120)
        #expect(notes.contains { $0.pad < 0 && $0.pitch == 60 && $0.tick == 0 && $0.duration == ppq })
        #expect(notes.contains { $0.pad == 0 && $0.tick == ppq })
    }

    @Test func damagedAndForeignFilesFailSafely() {
        #expect(throws: MIDIFileImport.Failure.notMIDI) { try MIDIFileImport.read(Data("hello".utf8)) }
        var truncated: [UInt8] = Array("MThd".utf8) + [0, 0, 0, 6, 0, 1, 0, 1, 0x03, 0xc0] + Array("MTrk".utf8) + [0, 0, 0, 20, 0x00, 0x90]
        #expect(throws: MIDIFileImport.Failure.self) { try MIDIFileImport.read(Data(truncated)) }
        truncated = Array("MThd".utf8) + [0, 0, 0, 6, 0, 2, 0, 1, 0x03, 0xc0]
        #expect(throws: MIDIFileImport.Failure.unsupportedFormat) { try MIDIFileImport.read(Data(truncated)) }
        let empty: [UInt8] = Array("MThd".utf8) + [0, 0, 0, 6, 0, 0, 0, 1, 0x03, 0xc0] + Array("MTrk".utf8) + [0, 0, 0, 4, 0x00, 0xff, 0x2f, 0x00]
        #expect(throws: MIDIFileImport.Failure.noNotes) { try MIDIFileImport.read(Data(empty)) }
    }
}
