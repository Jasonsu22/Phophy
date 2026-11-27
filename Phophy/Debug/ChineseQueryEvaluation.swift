#if DEBUG
import Foundation
import Photos

/// Experiment E3: how should Chinese searches reach a visual model that only
/// reads English? See `Eval/E3_CHINESE.md`.
///
/// Launch with `-PhophyE3` and put `e3_queries.json` (from
/// `Eval/e3_prepare.py` and `Eval/e3_translate.swift`) in the app's
/// Documents folder. Each Chinese query is searched once per condition, on
/// the same index and ranking as the app; the runner prints lines starting
/// with `E3` and writes `e3-results.json`.
enum ChineseQueryEvaluation {
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-PhophyE3") }

    struct TestSet: Decodable {
        struct Query: Decodable {
            var zh: String
            var humanEn: String
            var relevant: [String]
            var appleTranslation: String?
            var appleRewrite: String?
            var claudeRewrite: String?
        }
        struct QuerySet: Decodable { var name: String; var kind: String; var queries: [Query] }
        var library: String
        var sets: [QuerySet]
    }

    struct Condition {
        let label: String
        let options: SearchOptions
        /// The text searched; nil when this condition has no text for the
        /// query (then the Chinese is searched as typed, and it counts).
        let text: (TestSet.Query) -> String?
    }

    static let conditions: [Condition] = {
        var noDictionary = SearchOptions.standard
        noDictionary.chineseConcepts = false
        var dictionaryOnly = SearchOptions.standard
        dictionaryOnly.chineseTranslation = false
        return [
            Condition(label: "a. Chinese as typed (no handling)", options: noDictionary) { $0.zh },
            Condition(label: "a+. Chinese through the concept dictionary only", options: dictionaryOnly) { $0.zh },
            // The app's own search: translated on this device when the
            // languages are installed, with the dictionary alongside.
            Condition(label: "d. the app: translation + dictionary", options: .standard) { $0.zh },
            Condition(label: "b. rewritten in English by Apple's on-device model", options: .standard) { $0.appleRewrite },
            Condition(label: "b2. rewritten in English by Claude", options: .standard) { $0.claudeRewrite },
            Condition(label: "c. translated on the device (Apple Translation)", options: .standard) { $0.appleTranslation },
            Condition(label: "upper bound: human English", options: .standard) { $0.humanEn },
        ]
    }()

    struct SetResult: Encodable {
        var name: String
        var queries: Int
        /// Queries that had no text for this condition and fell back to the Chinese.
        var fellBack: Int
        var metrics: [String: Double]
        var misses: [String]
    }

    static func runWhenIndexed() async {
        let documents = URL.documentsDirectory
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let data = try? Data(contentsOf: documents.appending(path: "e3_queries.json")),
              let testSet = try? decoder.decode(TestSet.self, from: data)
        else { log("no readable e3_queries.json in \(documents.path)"); log("done"); return }

        let imageCount = PHAsset.fetchAssets(with: .image, options: nil).count
        let model = CLIPEncoder.isAvailable ? CLIPEncoder.modelName : nil
        while true {
            let indexed = (try? IndexStore.shared.indexedIDs(embeddingModel: model).count) ?? 0
            if indexed >= imageCount, await SearchEvaluation.extraWorkDone() { break }
            log("waiting for indexing: \(indexed) of \(imageCount)")
            try? await Task.sleep(for: .seconds(5))
        }
        let byName = fileNameIndex()
        log("results for \(testSet.library), \(imageCount) photos, CLIP \(model ?? "missing")")

        // Condition d needs the device's translation; where there is none
        // (the simulator), it uses the Mac's from e3_queries.json.
        if await QueryTranslator.shared.status() != .on {
            var given: [String: String] = [:]
            for query in testSet.sets.flatMap(\.queries) { given[query.zh] = query.appleTranslation }
            await QueryTranslator.shared.preload(given)
            log("translations for condition d come from e3_queries.json (\(given.count))")
        }

        var report: [String: [SetResult]] = [:]
        for condition in conditions {
            // Skip a machine condition nobody has produced text for yet.
            let available = testSet.sets.flatMap(\.queries).contains { condition.text($0) != nil }
            guard available else { log("== \(condition.label): no text in e3_queries.json, skipped"); continue }
            var results: [SetResult] = []
            for set in testSet.sets {
                results.append(await evaluate(set, condition: condition, byName: byName, indexedCount: imageCount))
            }
            report[condition.label] = results
            log("== \(condition.label)")
            for r in results {
                let cells = r.metrics.sorted { $0.key < $1.key }
                    .map { "\($0.key) \(String(format: "%.3f", $0.value))" }
                    .joined(separator: "  ")
                log("\(r.name) [\(r.queries)\(r.fellBack > 0 ? ", \(r.fellBack) fell back to Chinese" : "")]: \(cells)")
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try? encoder.encode(report).write(to: documents.appending(path: "e3-results.json"))
        log("done")
    }

    private static func evaluate(_ set: TestSet.QuerySet, condition: Condition, byName: [String: String], indexedCount: Int) async -> SetResult {
        var sums: [String: Double] = [:]
        var misses: [String] = []
        var fellBack = 0
        for query in set.queries {
            let relevant = Set(query.relevant.compactMap { byName[$0] })
            guard !relevant.isEmpty else { continue }
            let text: String
            if let given = condition.text(query)?.trimmingCharacters(in: .whitespacesAndNewlines), !given.isEmpty {
                text = given
            } else {
                text = query.zh
                fellBack += 1
            }
            let ranked = await SearchEngine.shared.rank(text, among: nil, indexedCount: indexedCount, limit: 100, options: condition.options).ids
            let firstHit = ranked.firstIndex(where: relevant.contains)
            sums["MRR", default: 0] += firstHit.map { 1 / Double($0 + 1) } ?? 0
            if set.kind == "single" {
                for k in [1, 5, 10] where (firstHit ?? .max) < k { sums["R@\(k)", default: 0] += 1 }
                if (firstHit ?? .max) >= 10 { misses.append(query.zh) }
            } else {
                let top10 = ranked.prefix(10).filter(relevant.contains).count
                let top50 = ranked.prefix(50).filter(relevant.contains).count
                sums["P@10", default: 0] += Double(top10) / 10
                sums["R@50", default: 0] += Double(top50) / Double(min(relevant.count, 50))
                if top10 == 0 { misses.append(query.zh) }
            }
        }
        let n = Double(max(set.queries.count, 1))
        return SetResult(name: set.name, queries: set.queries.count, fellBack: fellBack,
                         metrics: sums.mapValues { $0 / n }, misses: misses)
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

    static func log(_ message: String) {
        fputs("E3 \(message)\n", stderr)
    }
}
#endif
