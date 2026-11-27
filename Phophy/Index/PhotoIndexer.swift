import Photos
import SwiftUI
import Vision

/// Indexing progress, for the UI.
@Observable
final class IndexStatus {
    private(set) var indexed = 0
    private(set) var total = 0
    private(set) var isRunning = false
    /// Set while indexing waits for the iPhone to cool down or leave Low
    /// Power Mode (not while it waits for scrolling to stop).
    private(set) var pause: IndexThrottle.Pause?
    let semanticSearchAvailable = CLIPEncoder.isAvailable

    func setPause(_ pause: IndexThrottle.Pause?) {
        if self.pause != pause { self.pause = pause }
    }

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

    /// Whether indexing is under way. Describing takes turns with it.
    func isIndexing() -> Bool { isRunning }

    /// How many batches have been indexed since launch, so describing can
    /// tell that indexing is getting its share.
    private(set) var batchesIndexed = 0
    func batchCount() -> Int { batchesIndexed }

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

        // 1. Date, location and type for every photo and video. This is read
        //    from Photos without downloading anything, so date and place
        //    search cover the whole library straight away.
        let everything = PHAsset.fetchAssets(with: nil)
        var metadata: [IndexStore.PhotoMeta] = []
        metadata.reserveCapacity(everything.count)
        everything.enumerateObjects { asset, _, _ in
            let coordinate = asset.location?.coordinate
            let media = asset.mediaType == .video ? "video"
                : asset.mediaSubtypes.contains(.photoLive) ? "live" : "photo"
            metadata.append(.init(
                localID: asset.localIdentifier, taken: asset.creationDate,
                latitude: coordinate?.latitude, longitude: coordinate?.longitude, media: media
            ))
        }
        try? store.replaceMetadata(metadata)

        // 2. Place names, looked up alongside the slower work below.
        Task.detached(priority: .utility) { await PlaceResolver.shared.run() }

        // 3. Text, labels and embeddings for each photo, newest first.
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

        var pending: [PHAsset] = []
        assets.enumerateObjects { asset, _, _ in
            if !done.contains(asset.localIdentifier) { pending.append(asset) }
        }

        // Tag and keyword-index what's already indexed before starting on the
        // rest: it takes seconds, and the rest can take hours on a big
        // library (photos waiting on iCloud).
        await updateKeywordIndex(status: status)

        // Images are fetched two at a time, so waiting on iCloud for one
        // photo doesn't hold up the other, without holding many large
        // images in memory. Before each step, indexing waits until the
        // screen is still, so it never slows scrolling or the viewer.
        let batchSize = 2
        for start in stride(from: 0, to: pending.count, by: batchSize) {
            await waitForTurn(status: status)
            let batch = Array(pending[start..<min(start + batchSize, pending.count)])
            let images = await withTaskGroup(of: (Int, CGImage?).self) { group in
                for (offset, asset) in batch.enumerated() {
                    group.addTask { (offset, await loadIndexImage(for: asset)) }
                }
                var images = [CGImage?](repeating: nil, count: batch.count)
                for await (offset, image) in group { images[offset] = image }
                return images
            }
            for (asset, image) in zip(batch, images) {
                guard let image else { continue }
                await waitForTurn(status: status)
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
            }
            batchesIndexed += 1
            await status.update(indexed: indexed, total: total, isRunning: true)
            // Every few hundred photos, make the new ones findable by keyword.
            if (start / batchSize) % 100 == 99 { await updateKeywordIndex(status: status) }
        }
        await updateKeywordIndex(status: status)
        await status.update(indexed: indexed, total: total, isRunning: false)
        await PlaceResolver.shared.run()
        // Place names just looked up go into the keyword entries.
        await refreshKeywordIndex()
    }

    /// Tags new photos with concepts and rebuilds their keyword entries.
    /// Both are cheap (no image is loaded) but still wait their turn.
    private func updateKeywordIndex(status: IndexStatus) async {
        await waitForTurn(status: status)
        await ConceptTagger.shared.tagPending()
        while !Task.isCancelled {
            await waitForTurn(status: status)
            let done = (try? IndexStore.shared.refreshDocuments(limit: 200)) ?? 0
            if done == 0 { break }
        }
    }

    /// Rebuilds keyword entries changed outside indexing (a new description).
    func refreshKeywordIndex() async {
        while !Task.isCancelled, ((try? IndexStore.shared.refreshDocuments(limit: 200)) ?? 0) > 0 {
            await Task.yield()
        }
    }

    /// Returns once the screen has been still for a moment and the iPhone
    /// is neither hot nor in Low Power Mode.
    private func waitForTurn(status: IndexStatus) async {
        let throttle = IndexThrottle.shared
        while !Task.isCancelled {
            let pause = throttle.pause
            await status.setPause(pause)
            if pause == nil, !throttle.screenIsBusy { return }
            try? await Task.sleep(for: pause == nil ? .milliseconds(250) : .seconds(10))
        }
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

/// A copy of the photo 2,048 px on its long side: sharp enough to read
/// small text, far smaller than a 12-megapixel original. Downloads from
/// iCloud if the phone doesn't hold the photo; if that fails the photo is
/// skipped and retried next time, never indexed from a blurry thumbnail.
nonisolated func loadIndexImage(for asset: PHAsset) async -> CGImage? {
    await withCheckedContinuation { continuation in
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = AppSettings.indexICloudPhotos
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 2048, height: 2048),
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            continuation.resume(returning: image?.cgImage)
        }
    }
}
