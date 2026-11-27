import Accelerate
import Photos
import SwiftUI
import UIKit

/// Description progress, for Settings and Search.
@Observable
final class DescribeStatus {
    private(set) var described = 0
    private(set) var toDescribe = 0
    private(set) var isRunning = false
    /// Why describing is stopped or waiting, if it is.
    private(set) var message: String?
    private(set) var describer: String?

    func update(described: Int, toDescribe: Int, isRunning: Bool, message: String?, describer: String?) {
        self.described = described
        self.toDescribe = toDescribe
        self.isRunning = isRunning
        self.message = message
        self.describer = describer
    }
}

/// Writes descriptions for photos, cheapest first and only where they
/// help: the costly layer of the index.
///
/// - Screenshots and photos that are mostly text (slides, documents,
///   receipts) get a different request: what it is and what it's about,
///   with the text already read from it, so "train ticket" finds a ticket
///   whose text only says "G1234 08:15".
/// - Near-duplicates (bursts, series: very similar look, taken within two
///   minutes) are described once and the description is copied.
/// - Favourites go first, then the newest photos.
/// - It waits while the screen moves, the iPhone is hot or in Low Power
///   Mode, like indexing, and with "Only while charging" on it waits for
///   the charger.
actor DescriptionService {
    static let shared = DescriptionService()

    /// Recognized text longer than this means the photo is mostly text, and
    /// is described as a screen or document.
    nonisolated static let textHeavy = 100
    /// Similarity above which two photos taken close together count as the same shot.
    nonisolated static let duplicateSimilarity: Float = 0.93

    private var isRunning = false
    private var runAgain = false

    /// How many photos a search may describe on the spot: a few seconds of
    /// work on the iPhone, a moment in the cloud.
    nonisolated static var lookCloserCount: Int { AppSettings.describer.isCloud ? 24 : 6 }

    /// One unit of work: a photo to describe and its near-duplicates.
    private struct Job {
        let id: String
        var copies: [String]
    }

    func run(status: DescribeStatus) async {
        if isRunning { runAgain = true; return }
        isRunning = true
        defer { isRunning = false }
        repeat {
            runAgain = false
            await describePending(status: status)
            // Photos indexed meanwhile are new work: go round again.
            if !runAgain, await PhotoIndexer.shared.isIndexing(), !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                runAgain = true
            }
        } while runAgain
    }

    private var indexBatchesAtLastTurn = 0
    private var lastTurn = Date.distantPast

    /// Describes up to `limit` of `ids` that have no description yet, right
    /// away (for a search that came back weak). Returns how many were described.
    func describeNow(_ ids: [String], limit: Int) async -> Int {
        let (describer, _) = await Describers.current()
        guard let describer else { return 0 }
        let done = (try? IndexStore.shared.describedIDs()) ?? [:]
        let todo = Array(ids.filter { done[$0] == nil }.prefix(limit))
        guard !todo.isEmpty else { return 0 }
        let assets = Self.assets(todo)
        let width = describer is CloudDescriber ? 6 : 1
        var count = 0
        await withTaskGroup(of: Bool.self) { group in
            var next = 0
            func add() {
                guard next < todo.count else { return }
                let id = todo[next]; next += 1
                group.addTask { await Self.describe(Job(id: id, copies: []), asset: assets[id], with: describer) }
            }
            for _ in 0..<width { add() }
            for await ok in group {
                if ok { count += 1 }
                add()
            }
        }
        if count > 0 { await PhotoIndexer.shared.refreshKeywordIndex() }
        return count
    }

    // MARK: The queue

    private func describePending(status: DescribeStatus) async {
        let (found, reason) = await Describers.current()
        let store = IndexStore.shared
        guard let describer = found else {
            let described = (try? store.describedCount()) ?? 0
            await status.update(described: described, toDescribe: 0, isRunning: false, message: reason, describer: nil)
            return
        }
        let jobs = plan()
        var described = (try? store.describedCount()) ?? 0
        let total = described + jobs.reduce(0) { $0 + 1 + $1.copies.count }
        let name = describer.id
        await status.update(described: described, toDescribe: total, isRunning: !jobs.isEmpty, message: nil, describer: name)
        guard !jobs.isEmpty else { return }

        let assets = Self.assets(jobs.map(\.id))
        let width = describer is CloudDescriber ? 4 : 1
        var failures = 0
        var stopReason: String?
        var index = 0
        while index < jobs.count, !Task.isCancelled {
            if let wait = await waitForTurn(status: status, described: described, total: total, name: name) {
                stopReason = wait
                break
            }
            let batch = Array(jobs[index..<min(index + width, jobs.count)])
            index += batch.count
            let results = await withTaskGroup(of: (Job, Bool).self) { group in
                for job in batch {
                    group.addTask { (job, await Self.describe(job, asset: assets[job.id], with: describer)) }
                }
                var results: [(Job, Bool)] = []
                for await result in group { results.append(result) }
                return results
            }
            for (job, ok) in results {
                if ok { described += 1 + job.copies.count; failures = 0 } else { failures += 1 }
            }
            if failures >= 5 {
                stopReason = Self.lastError ?? "Describing failed several times in a row."
                break
            }
            _ = try? store.refreshDocuments(limit: 50)
            await status.update(described: described, toDescribe: total, isRunning: true, message: nil, describer: name)
        }
        await PhotoIndexer.shared.refreshKeywordIndex()
        await status.update(described: described, toDescribe: total, isRunning: false, message: stopReason, describer: name)
    }

    /// Returns nil when it's fine to go on, or the reason to stop.
    private func waitForTurn(status: DescribeStatus, described: Int, total: Int, name: String) async -> String? {
        let throttle = IndexThrottle.shared
        while !Task.isCancelled {
            if let pause = throttle.pause {
                await status.update(described: described, toDescribe: total, isRunning: true, message: pause.message, describer: name)
                try? await Task.sleep(for: .seconds(10))
                continue
            }
            // Indexing a big library can take days (photos wait on iCloud),
            // so describing doesn't wait for it to finish: the two take
            // turns. Indexing gets a few batches between descriptions, and
            // if it's stuck waiting on a download, describing goes ahead.
            if await PhotoIndexer.shared.isIndexing() {
                let batches = await PhotoIndexer.shared.batchCount()
                if batches - indexBatchesAtLastTurn < 4, Date.now.timeIntervalSince(lastTurn) < 12 {
                    try? await Task.sleep(for: .milliseconds(400))
                    continue
                }
                indexBatchesAtLastTurn = batches
            }
            if AppSettings.describeOnlyWhenCharging, !(await Self.isCharging()) {
                return "Waiting for the charger"
            }
            if throttle.screenIsBusy {
                try? await Task.sleep(for: .milliseconds(250))
                continue
            }
            lastTurn = .now
            return nil
        }
        return "Stopped"
    }

    @MainActor private static func isCharging() -> Bool {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let state = UIDevice.current.batteryState
        return state == .charging || state == .full || state == .unknown
    }

    /// What to describe, in order, with near-duplicates folded in.
    private func plan() -> [Job] {
        let store = IndexStore.shared
        guard let library = try? store.embeddings(model: CLIPEncoder.modelName), !library.ids.isEmpty else { return [] }
        let done = (try? store.describedIDs()) ?? [:]

        // Newest first, by date taken.
        var taken: [String: Date] = [:]
        var favorites = Set<String>()
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: library.ids, options: nil)
        fetch.enumerateObjects { asset, _, _ in
            taken[asset.localIdentifier] = asset.creationDate
            if asset.isFavorite { favorites.insert(asset.localIdentifier) }
        }
        let row = Dictionary(uniqueKeysWithValues: library.ids.enumerated().map { ($1, $0) })
        let candidates = library.ids
            .filter { done[$0] == nil }
            .sorted { (taken[$0] ?? .distantPast) > (taken[$1] ?? .distantPast) }

        // Fold near-duplicates into the newest of each run.
        let dimension = library.dimension
        func similarity(_ a: String, _ b: String) -> Float {
            guard let ra = row[a], let rb = row[b] else { return 0 }
            var dot: Float = 0
            library.matrix.withUnsafeBufferPointer { m in
                vDSP_dotpr(m.baseAddress! + ra * dimension, 1, m.baseAddress! + rb * dimension, 1, &dot, vDSP_Length(dimension))
            }
            return dot
        }
        var jobs: [Job] = []
        for id in candidates {
            if let last = jobs.indices.last,
               let a = taken[jobs[last].id], let b = taken[id], abs(a.timeIntervalSince(b)) < 120,
               similarity(jobs[last].id, id) >= Self.duplicateSimilarity {
                jobs[last].copies.append(id)
            } else {
                jobs.append(Job(id: id, copies: []))
            }
        }
        // Favourites first; otherwise keep newest first.
        return jobs.filter { favorites.contains($0.id) } + jobs.filter { !favorites.contains($0.id) }
    }

    // MARK: One photo

    nonisolated(unsafe) private static var lastError: String?

    private static func describe(_ job: Job, asset: PHAsset?, with describer: PhotoDescriber) async -> Bool {
        guard let asset, let image = await loadImage(asset, size: describer.imageSize) else { return false }
        let text = (try? IndexStore.shared.info(for: job.id))?.text ?? ""
        let context = DescribeContext(
            isScreen: asset.mediaSubtypes.contains(.photoScreenshot) || TextNormalizer.textAmount(text) >= Self.textHeavy,
            text: text
        )
        do {
            let started = ContinuousClock.now
            let description = try await describer.describe(Describers.scaled(image, to: describer.imageSize), context: context)
            #if DEBUG
            let ms = (ContinuousClock.now - started).components.attoseconds / 1_000_000_000_000_000
                + (ContinuousClock.now - started).components.seconds * 1000
            fputs("describe \(describer.id)\(context.isScreen ? " screen" : "") \(ms) ms\(description.isUsable ? "" : " (dropped)"): \(description.caption) | \(description.keywordLine)\n", stderr)
            #endif
            // A garbled reply is dropped but the photo still counts as done, so
            // it isn't tried again and again; it stays findable by its text.
            let usable = description.isUsable
            for id in [job.id] + job.copies {
                try IndexStore.shared.saveDescription(
                    localID: id, caption: usable ? description.caption : "",
                    keywords: usable ? description.keywordLine : "", describedBy: describer.id
                )
            }
            return true
        } catch {
            lastError = error.localizedDescription
            #if DEBUG
            fputs("describe failed: \(error)\n", stderr)
            #endif
            return false
        }
    }

    private static func assets(_ ids: [String]) -> [String: PHAsset] {
        var map: [String: PHAsset] = [:]
        PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).enumerateObjects { asset, _, _ in
            map[asset.localIdentifier] = asset
        }
        return map
    }

    /// A small copy of the photo, just big enough for the describer.
    private static func loadImage(_ asset: PHAsset, size: Int) async -> CGImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = AppSettings.indexICloudPhotos
            PHImageManager.default().requestImage(
                for: asset, targetSize: CGSize(width: size, height: size),
                contentMode: .aspectFit, options: options
            ) { image, _ in
                continuation.resume(returning: image?.cgImage)
            }
        }
    }
}
