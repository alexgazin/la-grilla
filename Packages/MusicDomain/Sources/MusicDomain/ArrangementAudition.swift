import Foundation

public enum ArrangementTake: String, Codable, CaseIterable, Sendable {
    case a = "A", b = "B"
}

public enum ArrangementAudition {
    public static func take(in brief: TrackBrief) -> ArrangementTake { brief.auditionTake ?? .a }

    /// Both seeds are stable at UInt32 boundaries. Their low bits select different rhythm/bass
    /// variants and adjacent modulo-three values select different wind phrases in the composer.
    public static func select(_ take: ArrangementTake, in brief: TrackBrief) -> TrackBrief {
        guard brief.songForm != nil, take != Self.take(in: brief) else { return brief }
        var chosen = brief
        chosen.seed ^= 1
        chosen.auditionTake = take == .a ? nil : .b
        return chosen
    }
}
