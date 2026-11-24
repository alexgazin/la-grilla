import Foundation

/// U19 · Who built a proposal.
public enum AssistantEngineKind: Equatable, Sendable {
    /// The local parser and composers; nothing leaves the device.
    case offline
    /// Apple Intelligence read the words; the notes are still composed locally.
    case appleIntelligence

    public var badge: String { self == .offline ? "Offline builder" : "Apple Intelligence" }
}

/// U19 · "Why this": two or three reasons taken from the proposal's own parameters (style, key,
/// tempo, sections, constraints) — never free text from a model.
public struct AssistantRationale: Equatable, Sendable {
    public var reasons: [String]
    public var engine: AssistantEngineKind

    public static func explain(_ proposal: AssistantProposal, project: Project, engine: AssistantEngineKind) -> AssistantRationale {
        func key(_ root: Int, _ minor: Bool) -> String {
            let name = MusicalNotation.pitchClassName(root, keyRoot: root, minor: minor)
            return String(format: NSLocalizedString(minor ? "%@ minor" : "%@ major", comment: "Key name"), name)
        }
        func section(_ id: UUID?) -> String { project.sections.first { $0.id == id }?.name ?? NSLocalizedString("this section", comment: "Rationale") }
        var reasons: [String] = []
        var changesKey = false
        for operation in proposal.operations {
            switch operation.type {
            case .setTempo:
                reasons.append(String(format: NSLocalizedString("Tempo %lld BPM, as you asked.", comment: "Rationale"), Int64((operation.bpm ?? project.bpm).rounded())))
            case .setKey:
                changesKey = true
                reasons.append(String(format: NSLocalizedString("Key %@, from your words.", comment: "Rationale"), key(operation.root ?? project.keyRoot, operation.minor ?? project.minor)))
            case .renameSection:
                reasons.append(String(format: NSLocalizedString("The section is renamed “%@”.", comment: "Rationale"), operation.name ?? ""))
            case .resizeSection:
                reasons.append(String(format: NSLocalizedString("%@ becomes %lld bars long.", comment: "Rationale"), section(operation.sectionID), Int64(operation.bars ?? 0)))
            case .setProgression:
                let chords = (operation.chords ?? []).prefix(6).map(\.symbol).joined(separator: " ")
                let bars = (operation.durations ?? []).reduce(0, +)
                reasons.append(String(format: NSLocalizedString("%@ gets %@ over %lld bars; the bass and voicing follow each chord.", comment: "Rationale"), section(operation.sectionID), chords, Int64(bars)))
            case .arrangeSong:
                let form = (operation.sections ?? []).map { "\($0.name) \($0.bars)" }.joined(separator: " · ")
                reasons.append(String(format: NSLocalizedString("Song form %@, as written; rhythm and melody repeat from the matching sections.", comment: "Rationale"), form))
            case .styleHarmony, .styleSong:
                let style = HarmonyStyle(rawValue: operation.style ?? "")?.title ?? (operation.style ?? "")
                let target = operation.type == .styleSong ? NSLocalizedString("every section with chords", comment: "Rationale") : section(operation.sectionID)
                reasons.append(String(format: NSLocalizedString("%@ harmony for %@: the same roots, richer chord colours.", comment: "Rationale"), NSLocalizedString(style, comment: "Harmony style"), target))
            case .generateSketch:
                if let plan = operation.sketch {
                    changesKey = changesKey || plan.root != project.keyRoot || plan.minor != project.minor
                    reasons.append(String(format: NSLocalizedString("%@ at %lld BPM in %@, %lld bars, from the style in your words.", comment: "Rationale"),
                                          NSLocalizedString(plan.style.title, comment: "Sketch style"), Int64(plan.bpm.rounded()), key(plan.root, plan.minor), Int64(plan.bars)))
                }
            }
        }
        reasons = Array(reasons.prefix(2))
        if !changesKey, proposal.operations.contains(where: { [.setProgression, .styleHarmony, .styleSong, .arrangeSong, .generateSketch].contains($0.type) }) {
            reasons.append(String(format: NSLocalizedString("It stays in %@, the song's key.", comment: "Rationale"), key(project.keyRoot, project.minor)))
        } else if project.tracks.contains(where: { $0.locked == true }) {
            reasons.append(NSLocalizedString("Locked parts stay exactly as they are.", comment: "Rationale"))
        }
        if reasons.count < 2 {
            reasons.append(NSLocalizedString(engine == .offline ? "Built offline from your words; nothing leaves this iPhone." : "Apple Intelligence read your words; the notes are composed on this iPhone.", comment: "Rationale"))
        }
        return AssistantRationale(reasons: Array(reasons.prefix(3)), engine: engine)
    }
}

/// U19 · "Another way": a new variant of the same request, as careful or as bold as asked.
public enum AssistantVariation {
    /// Harmony styles from the gentlest to the boldest.
    static let styles: [HarmonyStyle] = [.gentle, .voiceLeading, .expressive, .reharmonize]

    /// True when the request has more than one good answer (composed or styled music).
    public static func canVary(_ proposal: AssistantProposal) -> Bool {
        proposal.operations.contains { [.generateSketch, .styleHarmony, .styleSong].contains($0.type) }
    }

    /// `boldness` 0 (careful) … 1 (bold); `attempt` 1, 2, … gives a different answer each time.
    public static func vary(_ proposal: AssistantProposal, project: Project, boldness: Double, attempt: Int) throws -> AssistantProposal {
        guard canVary(proposal), attempt > 0 else { throw AssistantError.unsupported }
        var next = proposal
        next.id = UUID()
        let bold = min(1, max(0, boldness))
        for index in next.operations.indices {
            switch next.operations[index].type {
            case .generateSketch:
                guard var plan = next.operations[index].sketch else { continue }
                plan.seed = plan.seed &+ UInt32(truncatingIfNeeded: attempt) &* 7919
                if bold > 0.66 {
                    // Bold: also nudge the tempo a little either way.
                    plan.bpm = min(240, max(40, (plan.bpm + (attempt % 2 == 0 ? 6 : -6)).rounded()))
                }
                next.operations[index].sketch = plan
            case .styleHarmony, .styleSong:
                let window = bold < 0.34 ? Array(styles[0...1]) : bold > 0.66 ? Array(styles[2...3]) : Array(styles[1...2])
                let current = HarmonyStyle(rawValue: next.operations[index].style ?? "")
                let choices = window.filter { $0 != current }
                next.operations[index].style = choices[(attempt - 1) % choices.count].rawValue
            default:
                continue
            }
        }
        _ = try next.candidate(for: project)
        return next
    }
}
