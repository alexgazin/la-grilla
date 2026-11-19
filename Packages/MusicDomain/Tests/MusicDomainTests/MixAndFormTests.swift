import Foundation
import Testing
@testable import MusicDomain

struct MixAndFormTests {
    @Test func mixPresetsChangeOnlyMasterEQAndLeadBalance() throws {
        let p = try SongEditDemo.project()
        for preset in MixPreset.allCases {
            let mixed = try preset.applied(to: p)
            #expect(Compiler.notes(mixed) == Compiler.notes(p))
            #expect(mixed.masterEQ != nil && mixed.master == p.master)
            #expect(mixed.tracks.map(\.presetVersion) == p.tracks.map(\.presetVersion))
            let lead = p.tracks.firstIndex { $0.name == "Flute" }!
            if preset == .club { #expect(mixed.tracks[lead].gain == p.tracks[lead].gain) } else { #expect(mixed.tracks[lead].gain != p.tracks[lead].gain) }
        }
    }

    @Test func formTemplatesFitTheLimitsAndReuseTheSongsParts() throws {
        let p = try SongEditDemo.project()
        for template in SongFormTemplate.allCases {
            let proposal = try template.proposal(for: p)
            let candidate = try proposal.candidate(for: p)
            try candidate.validate()
            #expect(candidate.length <= 64 * barTicks && candidate.sections.count <= 8)
            #expect(candidate.sections.count >= 4)
            #expect(Set(candidate.tracks.map(\.id)) == Set(p.tracks.map(\.id)))
            #expect(!Compiler.notes(candidate).isEmpty)
        }
    }
}
