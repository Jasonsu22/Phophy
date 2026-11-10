import Photos
import SwiftUI
import Vision

/// Indexing progress, for the UI.
@Observable
final class IndexStatus {
    private(set) var indexed = 0
    private(set) var total = 0
    private(set) var isRunning = false
    let semanticSearchAvailable = CLIPEncoder.isAvailable

    func update(indexed: Int, total: Int, isRunning: Bool) {
        self.indexed = indexed
        self.total = total
        self.isRunning = isRunning
    }
}

/// Walks the photo library once and records, for each photo not yet indexed:
/// the text in it, what Vision thinks it shows, and its MobileCLIP embedding.
/// Everything runs on the device. Videos are skipped for now.
actor PhotoIndexer {
    static let shared = PhotoIndexer()

    private var isRunning = false
    private var runAgain = false

    func run(status: IndexStatus) async {
        if isRunning {
            runAgain = true
            return
        }
        isRunning = true
        defer { isRunning = false }

        repeat {
            runAgain = false
            await indexPending(status: status)
        } while runAgain
    }

    private func indexPending(status: IndexStatus) async {
        let store = IndexStore.shared
        let model = CLIPEncoder.isAvailable ? CLIPEncoder.modelName : nil

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let assets = PHAsset.fetchAssets(with: .image, options: options)
        let total = assets.count

        var libraryIDs = Set<String>()
        libraryIDs.reserveCapacity(total)
        assets.enumerateObjects { asset, _, _ in libraryIDs.insert(asset.localIdentifier) }

        // Forget photos that were deleted from the library.
        if let stored = try? store.allIDs() {
            try? store.remove(localIDs: Array(stored.subtracting(libraryIDs)))
        }

        let done = ((try? store.indexedIDs(embeddingModel: model)) ?? []).intersection(libraryIDs)
        var indexed = done.count
        await status.update(indexed: indexed, total: total, isRunning: indexed < total)

        for position in 0..<total {
            let asset = assets.object(at: position)
            guard !done.contains(asset.localIdentifier) else { continue }
            guard let image = await loadIndexImage(for: asset) else { continue }

            let text = await recognizeText(in: image)
            let labels = await classify(image)
            let embedding = try? await CLIPEncoder.shared.embed(image: image)

            try? store.save(
                localID: asset.localIdentifier,
                modified: asset.modificationDate,
                text: text,
                labels: labels,
                embedding: embedding,
                embeddingModel: embedding == nil ? nil : model
            )
            indexed += 1
            await status.update(indexed: indexed, total: total, isRunning: true)
        }
        await status.update(indexed: indexed, total: total, isRunning: false)
    }

    private func recognizeText(in image: CGImage) async -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = true
        guard let observations = try? await request.perform(on: image) else { return "" }
        return observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }

    /// Vision's built-in scene labels ("waterfall", "document", ...). This can
    /// fail in the simulator; an empty list is fine.
    private func classify(_ image: CGImage) async -> [String] {
        guard let observations = try? await ClassifyImageRequest().perform(on: image) else { return [] }
        return observations
            .filter { $0.confidence >= 0.3 }
            .sorted { $0.confidence > $1.confidence }
            .prefix(10)
            .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
    }
}

/// A copy of the photo about 1280 px on its long side: enough for text
/// recognition, far smaller than the original. Downloads from iCloud if needed.
nonisolated func loadIndexImage(for asset: PHAsset) async -> CGImage? {
    await withCheckedContinuation { continuation in
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = AppSettings.indexICloudPhotos
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 1280, height: 1280),
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            continuation.resume(returning: image?.cgImage)
        }
    }
}
