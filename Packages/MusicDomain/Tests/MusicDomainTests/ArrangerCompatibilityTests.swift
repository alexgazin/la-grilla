import Foundation
import Testing
@testable import MusicDomain

struct ArrangerCompatibilityTests {
    @Test func existingSongsKeepTheirDefaultChordVelocityAfterMigration() throws {
        var legacy = Project.demo()
        legacy.schemaVersion = 13
        let original = Compiler.notes(legacy)
        let reopened = try ProjectDocument.decode(JSONEncoder().encode(legacy))
        #expect(reopened.schemaVersion == Project.currentSchemaVersion)
        #expect(reopened.hasComposedEnding == nil)
        #expect(Compiler.notes(reopened) == original)
    }

    @Test func rearrangingQuietChordsPreservesDynamics() throws {
        var song = Project.demo()
        song.patterns[0].chords[0].velocity = 36
        song.hasComposedEnding = true
        let section = song.sections[0]
        #expect(Arrangement.harmony(song, section: section).first?.velocity == 36)
        let resized = try Arrangement.resized(song, sectionID: section.id, bars: 3)
        let reopened = try PortableProject.decode(PortableProject.data(resized))
        #expect(reopened.hasComposedEnding == true)
        #expect(Compiler.notes(reopened).first { $0.track == 0 }?.velocity == 36)
    }
}
