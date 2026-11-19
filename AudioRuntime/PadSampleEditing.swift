import Foundation
import MusicDomain

extension DrumSamplePreparation {
    func openEditor(asset: SampleAsset, store: ProjectStore, projectID: UUID) async throws -> OneShotSource {
        let bytes = try await store.sampleData(asset, projectID: projectID)
        try Task.checkCancellation()
        return try OneShotSource(asset: asset, data: bytes)
    }

    func editorPreview(source: OneShotSource, edit: OneShotEdit) throws -> Data {
        try Task.checkCancellation()
        return try source.previewWAV(edit)
    }

    func editedSample(source: OneShotSource, edit: OneShotEdit) throws -> PreparedSound {
        try Task.checkCancellation()
        let pcm = try source.render(edit)
        return try PreparedSound(name: source.asset.name, kind: .oneShot, pcm: pcm)
    }
}
