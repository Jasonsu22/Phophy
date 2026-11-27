#if DEBUG
import Foundation
import FoundationModels
import Photos
import UIKit

/// Scores search against a labelled test set (see `Eval/README.md`).
///
/// Launch with `-PhophyEval` and put `eval.json` in the app's Documents
/// folder. The runner waits for indexing to finish, runs every query
/// through the same ranking the assistant uses, prints a table prefixed
/// `EVAL` and writes `eval-results.json` next to the input.
nonisolated enum SearchEvaluation {
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-PhophyEval") }

    struct TestSet: Decodable {
        struct Query: Decodable { var q: String; var relevant: [String] }
        struct QuerySet: Decodable { var name: String; var kind: String; var queries: [Query] }
        var library: String
        var sets: [QuerySet]
    }

    struct SetResult: Encodable {
        var name: String
        var queries: Int
        var metrics: [String: Double]
        var misses: [String]
    }

    static func runWhenIndexed() async {
        let documents = URL.documentsDirectory
        guard let data = try? Data(contentsOf: documents.appending(path: "eval.json")),
              let testSet = try? JSONDecoder().decode(TestSet.self, from: data)
        else { log("no eval.json in \(documents.path)"); return }

        let imageCount = PHAsset.fetchAssets(with: .image, options: nil).count
        let model = CLIPEncoder.isAvailable ? CLIPEncoder.modelName : nil
        while true {
            let indexed = (try? IndexStore.shared.indexedIDs(embeddingModel: model).count) ?? 0
            if indexed >= imageCount, await extraWorkDone() { break }
            log("waiting for indexing: \(indexed) of \(imageCount)")
            try? await Task.sleep(for: .seconds(5))
        }

        let byName = fileNameIndex()
        let described = (try? IndexStore.shared.describedCount()) ?? 0
        var report: [String: [SetResult]] = [:]
        log("results for \(testSet.library), \(imageCount) photos, \(described) described")
        for (label, options) in configurations {
            var results: [SetResult] = []
            for set in testSet.sets {
                results.append(await evaluate(set, byName: byName, indexedCount: imageCount, options: options))
            }
            report[label] = results
            log("== \(label)")
            for r in results {
                let cells = r.metrics.sorted { $0.key < $1.key }
                    .map { "\($0.key) \(String(format: "%.3f", $0.value))" }
                    .joined(separator: "  ")
                log("\(r.name) [\(r.queries)]: \(cells)")
            }
        }
        let output = try? JSONEncoder.pretty.encode(report)
        try? output?.write(to: documents.appending(path: "eval-results.json"))
        log("done")
    }

    /// Each layer added in turn, so the table shows what each one adds.
    static let configurations: [(String, SearchOptions)] = [
        ("1 before", .previous),
        ("2 keywords+tags", SearchOptions(typos: false, expansion: false, visualTail: false, visualScores: false, rareWordWeight: 0, keywordScores: false)),
        ("3 +typos", SearchOptions(expansion: false, visualTail: false, visualScores: false, rareWordWeight: 0, keywordScores: false)),
        ("4 +visual tail", SearchOptions(expansion: false, visualScores: false, rareWordWeight: 0, keywordScores: false)),
        ("5 +expansion", SearchOptions(visualScores: false, rareWordWeight: 0, keywordScores: false)),
        ("6 +visual scores for long searches", SearchOptions(rareWordWeight: 0, keywordScores: false)),
        ("7 +rare words for short searches (all)", .standard),
        ("8 with keyword scores", SearchOptions(keywordScores: true)),
    ]

    /// Hook for later index stages (tags, descriptions) to report they're finished.
    static func extraWorkDone() async -> Bool {
        let model = CLIPEncoder.modelName
        let untagged = (try? IndexStore.shared.untaggedIDs(version: ConceptTagger.version, model: model).count) ?? 1
        let pending = (try? IndexStore.shared.pendingDocumentCount()) ?? 1
        return untagged == 0 && pending == 0
    }

    private static func evaluate(_ set: TestSet.QuerySet, byName: [String: String], indexedCount: Int, options: SearchOptions) async -> SetResult {
        var sums: [String: Double] = [:]
        var misses: [String] = []
        var latency = Duration.zero
        for query in set.queries {
            let relevant = Set(query.relevant.compactMap { byName[$0] })
            guard !relevant.isEmpty else { continue }
            let start = ContinuousClock.now
            let ranked = await SearchEngine.shared.rank(query.q, among: nil, indexedCount: indexedCount, limit: 100, options: options).ids
            latency += ContinuousClock.now - start

            let firstHit = ranked.firstIndex(where: relevant.contains)
            sums["MRR", default: 0] += firstHit.map { 1 / Double($0 + 1) } ?? 0
            if set.kind == "single" {
                for k in [1, 5, 10] where (firstHit ?? .max) < k { sums["R@\(k)", default: 0] += 1 }
                if (firstHit ?? .max) >= 10 { misses.append(query.q) }
            } else {
                let top10 = ranked.prefix(10).filter(relevant.contains).count
                let top50 = ranked.prefix(50).filter(relevant.contains).count
                sums["P@10", default: 0] += Double(top10) / 10
                sums["R@50", default: 0] += Double(top50) / Double(min(relevant.count, 50))
                if top10 == 0 { misses.append(query.q) }
            }
        }
        let n = Double(set.queries.count)
        var metrics = sums.mapValues { $0 / n }
        metrics["ms/query"] = Double(latency.components.seconds) * 1000 / n
            + Double(latency.components.attoseconds) / 1e15 / n
        return SetResult(name: set.name, queries: set.queries.count, metrics: metrics, misses: misses)
    }

    /// Original file name → local identifier, for every photo.
    private static func fileNameIndex() -> [String: String] {
        var map: [String: String] = [:]
        PHAsset.fetchAssets(with: .image, options: nil).enumerateObjects { asset, _, _ in
            if let name = PHAssetResource.assetResources(for: asset).first?.originalFilename {
                map[name] = asset.localIdentifier
            }
        }
        return map
    }

    /// `-PhophyDescribeProbe`: says whether Apple's model can describe
    /// images here, and times it on five photos.
    static func probeDescribers() async {
        guard ProcessInfo.processInfo.arguments.contains("-PhophyDescribeProbe") else { return }
        if #available(iOS 27.0, *) {
            let model = SystemLanguageModel.default
            log("probe: apple availability \(model.availability), vision \(model.capabilities.contains(.vision))")
        }
        let (describer, reason) = await Describers.current()
        guard let describer else { log("probe: no describer: \(reason)"); return }
        let ids = Array((try? IndexStore.shared.allIDs()) ?? []).prefix(5)
        let started = ContinuousClock.now
        let count = await DescriptionService.shared.describeNow(Array(ids), limit: 5)
        log("probe: \(describer.id) described \(count) in \(ContinuousClock.now - started)")
        for id in ids {
            if let d = try? IndexStore.shared.document(for: id) { log("probe: \(d.caption) | \(d.keywords)") }
        }
    }

    /// Testing aid: `-PhophyPhoneBench -describer downloaded` times search and
    /// describing on a real iPhone, on the library that's there.
    static func benchPhone() async {
        guard ProcessInfo.processInfo.arguments.contains("-PhophyPhoneBench") else { return }
        let store = IndexStore.shared
        let ids = Array((try? store.allIDs()) ?? [])
        let photoCount = PHAsset.fetchAssets(with: .image, options: nil).count
        log("bench: \(ids.count) indexed of \(photoCount) photos, \(((try? store.describedCount()) ?? 0)) described, memory \(memoryMB()) MB, \(conditions())")

        // Search: warm up once, then the median of five runs.
        for query in ["dog", "food", "beach", "screenshot", "狗", "生日蛋糕", "bicyle", "a person standing next to a car at night"] {
            _ = await SearchEngine.shared.rank(query, among: nil, indexedCount: ids.count, limit: 100)
            var times: [Double] = []
            var found = 0
            for _ in 0..<5 {
                let started = ContinuousClock.now
                found = await SearchEngine.shared.rank(query, among: nil, indexedCount: ids.count, limit: 100).ids.count
                times.append(milliseconds(since: started))
            }
            log("bench: search \"\(query)\" \(String(format: "%.0f", times.sorted()[2])) ms, \(found) results")
        }

        guard #available(iOS 27.0, *) else { log("bench: describing needs iOS 27"); return }
        let model = AppSettings.downloadableModel
        if !(await OnDeviceDescriber.isDownloaded(model)) {
            log("bench: downloading \(model.rawValue)…")
            let started = ContinuousClock.now
            do { try await OnDeviceDescriber.download(model) } catch { log("bench: download failed: \(error)"); return }
            log("bench: downloaded and loaded in \(String(format: "%.0f", milliseconds(since: started) / 1000)) s, memory \(memoryMB()) MB")
        }
        // Start clean: earlier test runs are the only descriptions on this phone.
        try? store.clearDescriptions(by: model.rawValue)
        // Mostly screenshots and text-heavy photos (the hard case), some scenes.
        let lengths = (try? store.textLengths()) ?? [:]
        var screens = Set<String>()
        PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).enumerateObjects { asset, _, _ in
            if asset.mediaSubtypes.contains(.photoScreenshot) { screens.insert(asset.localIdentifier) }
        }
        for (id, n) in lengths where n >= DescriptionService.textHeavy { screens.insert(id) }
        let shuffled = ids.shuffled()
        let todo = Array(shuffled.filter(screens.contains).prefix(9)) + Array(shuffled.filter { !screens.contains($0) }.prefix(3))
        log("bench: \(screens.count) of \(ids.count) indexed photos are screens or text")
        let battery = await batteryLevel()
        let started = ContinuousClock.now
        for (n, id) in todo.enumerated() {
            let one = ContinuousClock.now
            let ok = await DescriptionService.shared.describeNow([id], limit: 1)
            log("bench: photo \(n + 1) \(ok == 1 ? "described" : "failed") in \(String(format: "%.0f", milliseconds(since: one))) ms, memory \(memoryMB()) MB, \(conditions())")
        }
        let total = milliseconds(since: started) / 1000
        log("bench: \(todo.count) photos in \(String(format: "%.0f", total)) s, battery \(battery)% → \(await batteryLevel())%")
        log("bench done")
    }

    private static func milliseconds(since start: ContinuousClock.Instant) -> Double {
        let d = ContinuousClock.now - start
        return Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
    }

    private static func conditions() -> String {
        let info = ProcessInfo.processInfo
        let heat = ["nominal", "fair", "serious", "critical"][info.thermalState.rawValue]
        return "heat \(heat)\(info.isLowPowerModeEnabled ? ", Low Power Mode" : "")"
    }

    @MainActor private static func batteryLevel() -> Int {
        UIDevice.current.isBatteryMonitoringEnabled = true
        return Int((UIDevice.current.batteryLevel * 100).rounded())
    }

    private static func memoryMB() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.phys_footprint / 1_048_576) : -1
    }

    /// Testing aid: `-PhophySearchProbe` runs each line of Documents/queries.txt
    /// through search once indexing is done and logs the top results by file name.
    static func probeSearch() async {
        guard ProcessInfo.processInfo.arguments.contains("-PhophySearchProbe") else { return }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        guard let text = try? String(contentsOf: documents.appendingPathComponent("queries.txt"), encoding: .utf8) else { return }
        while !(await extraWorkDone()) { try? await Task.sleep(for: .seconds(2)) }
        let ids = Array((try? IndexStore.shared.allIDs()) ?? [])
        var names: [String: String] = [:]
        PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).enumerateObjects { asset, _, _ in
            names[asset.localIdentifier] = PHAssetResource.assetResources(for: asset).first?.originalFilename ?? "?"
        }
        for query in text.split(separator: "\n").map(String.init) where !query.isEmpty {
            let started = ContinuousClock.now
            let results = await SearchEngine.shared.search(query, indexedCount: ids.count)
            let ms = milliseconds(since: started)
            let top = (results.bestMatches.isEmpty ? results.closest : results.bestMatches).prefix(6).map { names[$0] ?? "?" }
            for list in await SearchEngine.shared.lastLists {
                log("probe   list w\(list.weight): \(list.ids.prefix(4).map { names[$0] ?? "?" }.joined(separator: " ")) (\(list.ids.count))")
            }
            log("probe \"\(query)\" \(String(format: "%.0f", ms)) ms\(results.bestMatches.isEmpty ? " WEAK" : "") best \(results.bestMatches.count) text \(results.textMatches.count): \(top.joined(separator: " "))")
        }
        log("probe done")
    }

    static func log(_ message: String) {
        fputs("EVAL \(message)\n", stderr)
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
#endif
