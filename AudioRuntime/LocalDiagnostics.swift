import Foundation
import MetricKit

/// I95 · Crash and hang reports from MetricKit, kept only on this iPhone
/// (at most 20 files). Nothing is sent anywhere; the musician can share the
/// latest report from Settings. Payloads contain stack frames and system
/// metrics, never project content or recordings.
final class LocalDiagnostics: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = LocalDiagnostics()
    private let queue = DispatchQueue(label: "la-grilla.diagnostics")
    private var folder: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("Diagnostics", isDirectory: true)
    }

    func start() { MXMetricManager.shared.add(self) }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let reports = payloads.map { $0.jsonRepresentation() }
        queue.async { [weak self] in self?.store(reports) }
    }

    private func store(_ reports: [Data]) {
        guard let folder else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for data in reports {
            let name = "diagnostic-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(6)).json"
            try? data.write(to: folder.appendingPathComponent(name), options: .atomic)
        }
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?.sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
        for old in files.dropLast(20) { try? FileManager.default.removeItem(at: old) }
    }

    /// The newest stored report, if any.
    var latestReport: URL? {
        guard let folder else { return nil }
        return (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }.last
    }
}
