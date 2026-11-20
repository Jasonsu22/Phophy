#if DEBUG
import Foundation
import FoundationModels
import Photos

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
        ("2 keywords+tags", SearchOptions(typos: false, expansion: false, visualTail: false, visualScores: false)),
        ("3 +typos", SearchOptions(expansion: false, visualTail: false, visualScores: false)),
        ("4 +visual tail", SearchOptions(expansion: false, visualScores: false)),
        ("5 +expansion", SearchOptions(visualScores: false)),
        ("6 +visual scores for long searches (all)", .standard),
        ("7 visual scores, long-query keywords 1.0", SearchOptions(longQueryKeywordWeight: 1.0)),
        ("8 visual scores, long-query keywords 0.25", SearchOptions(longQueryKeywordWeight: 0.25)),
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
