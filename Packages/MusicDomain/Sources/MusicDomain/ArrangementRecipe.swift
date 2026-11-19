import Foundation

/// The reviewed starting point of a generated score. Later note edits belong to
/// the project. Opening this recipe in the builder creates a separate arrangement.
public struct ArrangementRecipe: Codable, Equatable, Sendable {
    public let brief: TrackBrief
    public let prompt: String

    public init(brief: TrackBrief, prompt: String) throws {
        guard prompt.count <= 2000, brief.chordText.count <= 2000,
              (40...240).contains(brief.tempo), (0..<12).contains(brief.root),
              (1...64).contains(brief.bars), (0..<brief.bars).contains(brief.introBars),
              let form = brief.songForm, form.parts.count <= 8,
              form.parts.allSatisfy({ $0.chordText.count <= 2000 })
        else { throw MusicError.invalidProject }
        try form.validate()
        self.brief = brief
        self.prompt = prompt
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(brief: values.decode(TrackBrief.self, forKey: .brief),
                      prompt: values.decode(String.self, forKey: .prompt))
    }
}
