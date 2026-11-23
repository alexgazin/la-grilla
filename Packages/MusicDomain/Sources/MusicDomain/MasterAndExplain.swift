import Foundation

/// I15 · Getting a mix ready for release: where it should sit in loudness and what to
/// change on the master to get there.
public enum MasterTarget: String, CaseIterable, Sendable {
    case streaming, appleMusic, club
    public var lufs: Double { switch self { case .streaming: -14; case .appleMusic: -16; case .club: -9 } }
    public var title: String { switch self { case .streaming: "Spotify and YouTube (−14 LUFS)"; case .appleMusic: "Apple Music (−16 LUFS)"; case .club: "Club and DJ sets (−9 LUFS)" } }
}

public struct MasterSuggestion: Equatable, Sendable {
    /// The new master gain (dB) and whether the limiter should be on.
    public let master: Double
    public let limiter: Bool
    /// Loudness after the change, as predicted from the measurement.
    public let predictedLUFS: Double
    /// Gain the limiter would have to take off the loudest peaks (dB, ≥ 0).
    public let limiterReduction: Double
    /// Localizable advice: "ready", "louder", "quieter", "tooLoud".
    public let advice: String
}

public enum MasterAssistant {
    /// Peaks are kept below −1 dBFS; above 6 dB of limiting the mix gets squashed, so the
    /// suggestion stops there and says so.
    public static func suggest(measured: LoudnessMeter.Measurement, currentMaster: Double, target: MasterTarget) -> MasterSuggestion {
        guard measured.integratedLUFS.isFinite, measured.integratedLUFS > -70 else {
            return MasterSuggestion(master: currentMaster, limiter: false, predictedLUFS: measured.integratedLUFS, limiterReduction: 0, advice: "silent")
        }
        let wanted = target.lufs - measured.integratedLUFS
        var change = min(6 - currentMaster, max(-61 - currentMaster, wanted))
        var reduction = max(0, measured.samplePeakDBFS + change - -1)
        var advice = abs(wanted) < 0.5 ? "ready" : wanted > 0 ? "louder" : "quieter"
        if reduction > 6 { change -= reduction - 6; reduction = 6; advice = "tooLoud" }
        let master = ((currentMaster + change) * 10).rounded() / 10
        return MasterSuggestion(master: master, limiter: reduction > 0, predictedLUFS: ((measured.integratedLUFS + change) * 10).rounded() / 10,
                                limiterReduction: (reduction * 10).rounded() / 10, advice: advice)
    }
}

/// I16 · "Why does this sound like that?" — short explanations from the song itself.
public enum HarmonyExplainer {
    public struct Explanation: Equatable, Sendable {
        /// Roman numeral in the key ("vi", "IV", "♭VII").
        public let degree: String
        /// Tonic, subdominant, dominant or borrowed colour.
        public let function: String
        /// Localizable sentences (English keys), shown one after another.
        public let sentences: [String]
        public var text: String { sentences.joined(separator: " ") }
    }

    private static let majorDegrees = [0: "I", 2: "ii", 4: "iii", 5: "IV", 7: "V", 9: "vi", 11: "vii°"]
    private static let minorDegrees = [0: "i", 2: "ii°", 3: "III", 5: "iv", 7: "v", 8: "VI", 10: "VII"]

    public static func degree(of chord: Chord, keyRoot: Int, minor: Bool) -> String {
        let interval = ((chord.root - keyRoot) % 12 + 12) % 12
        if let name = (minor ? minorDegrees : majorDegrees)[interval] {
            // A major chord on a minor degree (or the reverse) is a borrowed or secondary colour.
            let isMinorChord = chord.quality.rawValue.hasPrefix("m") && !chord.quality.rawValue.hasPrefix("maj")
            let lower = name.lowercased() == name
            if minor && interval == 7 && !isMinorChord { return "V" }   // harmonic-minor dominant
            if isMinorChord && !lower { return name.lowercased() }
            if !isMinorChord && lower && !name.contains("°") { return name.uppercased() }
            return name
        }
        let flats = [1: "♭II", 3: "♭III", 6: "♯IV", 8: "♭VI", 10: "♭VII"]
        return flats[interval] ?? "?"
    }

    public static func function(degree: String) -> String {
        switch degree.trimmingCharacters(in: CharacterSet(charactersIn: "°")).lowercased() {
        case "i", "vi", "iii": "tonic"
        case "iv", "ii": "subdominant"
        case "v", "vii": "dominant"
        default: "borrowed"
        }
    }

    public static func explain(_ chord: Chord, previous: Chord?, keyRoot: Int, minor: Bool) -> Explanation {
        let degree = degree(of: chord, keyRoot: keyRoot, minor: minor)
        let function = function(degree: degree)
        let base: String
        switch function {
        case "tonic": base = degree.lowercased() == "i" ? "Home: the song rests here." : "A softer home: it shares two notes with the tonic."
        case "subdominant": base = "Moving away from home: it opens the phrase up."
        case "dominant": base = "Tension that wants to go home."
        default: base = "A borrowed colour from outside the key: it surprises the ear."
        }
        var sentences = [base]
        if let previous {
            let motion = ((chord.root - previous.root) % 12 + 12) % 12
            if motion == 5 { sentences.append("The root moves up a fourth — the strongest pull in harmony.") }
            else if motion == 7 { sentences.append("The root moves down a fourth: the move feels open, not final.") }
            else if motion == 1 || motion == 11 { sentences.append("The root slides by a semitone: smooth and dramatic.") }
            else if motion == 2 || motion == 10 { sentences.append("The root steps by a tone: it walks rather than jumps.") }
        }
        return Explanation(degree: degree, function: function, sentences: sentences)
    }
}
