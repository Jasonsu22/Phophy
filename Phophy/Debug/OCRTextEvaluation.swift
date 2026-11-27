#if DEBUG
import Foundation
import NaturalLanguage
import Photos

/// Experiment E4: do sentence vectors of the text in photos find slides and
/// documents when the search uses other words than the photo? See
/// `Eval/E4_OCR_EMBEDDINGS.md`.
///
/// Launch with `-PhophyE4` and put `e4_queries.json` in the app's Documents
/// folder. The text of every photo with at least 20 recognized characters
/// is embedded with Apple's contextual embedding (mean of the token vectors;
/// Latin-script and Chinese-script text each in their own model), here in
/// the runner, so the index is not changed. Prints `E4` lines and writes
/// `e4-results.json`.
enum OCRTextEvaluation {
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-PhophyE4") }

    struct TestSet: Decodable {
        struct Query: Decodable {
            var q: String
            var lang: String
            var relevant: [String]
            /// On-device translation of a Chinese query (Eval/e4_translate.swift).
            var qEn: String?
        }
        var queries: [Query]
    }

    /// A vector space: one Apple contextual embedding model and the photos
    /// whose text is in its script.
    final class Space {
        let model: NLContextualEmbedding
        var ids: [String] = []
        var vectors: [[Float]] = []

        init(model: NLContextualEmbedding) { self.model = model }

        /// Mean of the token vectors, normalised. Nil if the model can't read it.
        func embed(_ text: String) -> [Float]? {
            let text = String(text.prefix(1000))
            guard let result = try? model.embeddingResult(for: text, language: nil) else { return nil }
            var sum = [Double](repeating: 0, count: model.dimension)
            var count = 0.0
            result.enumerateTokenVectors(in: text.startIndex..<text.endIndex) { vector, _ in
                for i in vector.indices { sum[i] += vector[i] }
                count += 1
                return true
            }
            guard count > 0 else { return nil }
            let norm = sum.reduce(0) { $0 + $1 * $1 }.squareRoot()
            guard norm > 0 else { return nil }
            return sum.map { Float($0 / norm) }
        }

        func ranked(for text: String, limit: Int = 100) -> [String] {
            guard let q = embed(text) else { return [] }
            let scored = vectors.indices.map { i in (ids[i], zip(q, vectors[i]).reduce(Float(0)) { $0 + $1.0 * $1.1 }) }
            return scored.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
        }
    }

    static func runWhenIndexed() async {
        let documents = URL.documentsDirectory
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let data = try? Data(contentsOf: documents.appending(path: "e4_queries.json")),
              let testSet = try? decoder.decode(TestSet.self, from: data)
        else { log("no readable e4_queries.json in \(documents.path)"); log("done"); return }

        let imageCount = PHAsset.fetchAssets(with: .image, options: nil).count
        let model = CLIPEncoder.isAvailable ? CLIPEncoder.modelName : nil
        while true {
            let indexed = (try? IndexStore.shared.indexedIDs(embeddingModel: model).count) ?? 0
            if indexed >= imageCount, await SearchEvaluation.extraWorkDone() { break }
            log("waiting for indexing: \(indexed) of \(imageCount)")
            try? await Task.sleep(for: .seconds(5))
        }

        let byName = fileNameIndex()
        // Per query: photos ranked by text vectors, English space (query in
        // English) and Chinese space (Chinese queries only), as local IDs.
        var vectorRanks: [String: (en: [String], zh: [String])] = [:]
        if let precomputed = try? Data(contentsOf: documents.appending(path: "e4_vectors.json")),
           let file = try? JSONDecoder().decode(VectorFile.self, from: precomputed) {
            // Computed on a Mac by Eval/e4_embed.swift from this index's text.
            for (q, ranks) in file.queries {
                vectorRanks[q] = (ranks.en.compactMap { byName[$0] }, ranks.zh.compactMap { byName[$0] })
            }
            log("text vectors from e4_vectors.json (\(file.source))")
        } else if let spaces = await embedHere() {
            for query in testSet.queries {
                let english = query.lang == "zh" ? (query.qEn ?? query.q) : query.q
                vectorRanks[query.q] = (spaces.english.ranked(for: english),
                                        query.lang == "zh" ? spaces.han.ranked(for: query.q) : [])
            }
        } else {
            exportText(byName: byName, to: documents.appending(path: "e4-ocr.json"))
            log("text vectors can't be computed here; exported e4-ocr.json. Run Eval/e4_embed.swift on a Mac, put e4_vectors.json in Documents and run again")
            log("done")
            return
        }

        let conditions = ["1. app search today", "2. app + query translation", "3. text vectors only",
                          "4. app + text vectors", "5. app + translation + text vectors",
                          "6. app + text vectors (translation for vectors only)",
                          "7. same as 6, vectors weighted 2", "8. same as 6, vectors weighted 3"]
        var sums: [String: [String: Double]] = [:]
        var counts: [String: Int] = [:]
        var misses: [String: [String]] = [:]

        for query in testSet.queries {
            let relevant = Set(query.relevant.compactMap { byName[$0] })
            guard !relevant.isEmpty else { log("no photo for \(query.relevant)"); continue }
            let english_q = query.lang == "zh" ? (query.qEn ?? query.q) : query.q
            let app = await SearchEngine.shared.rank(query.q, among: nil, indexedCount: imageCount, limit: 100).ids
            let appTranslated = query.lang == "zh"
                ? await SearchEngine.shared.rank(english_q, among: nil, indexedCount: imageCount, limit: 100).ids
                : app
            // Vectors: English text in the Latin model; Chinese text in the
            // Chinese model (only a Chinese query can be compared there).
            let ranks = vectorRanks[query.q] ?? ([], [])
            var vectorLists = [ranks.en]
            if query.lang == "zh" { vectorLists.append(ranks.zh) }
            let vectorsOnly = fuse(vectorLists.map { ($0, 1.0) })
            let vectorsNoTranslation = query.lang == "zh" ? ranks.zh : ranks.en

            let lists: [String: [String]] = [
                conditions[0]: app,
                conditions[1]: appTranslated,
                conditions[2]: vectorsOnly,
                conditions[3]: fuse([(app, 1), (vectorsNoTranslation, 1)]),
                conditions[4]: fuse([(appTranslated, 1)] + vectorLists.map { ($0, 1.0) }),
                // The app keeps the words as typed (Chinese keywords still match
                // Chinese slides); the translation only feeds the English vectors.
                conditions[5]: fuse([(app, 1)] + vectorLists.map { ($0, 1.0) }),
                conditions[6]: fuse([(app, 1)] + vectorLists.map { ($0, 2.0) }),
                conditions[7]: fuse([(app, 1)] + vectorLists.map { ($0, 3.0) }),
            ]
            for (label, ranked) in lists {
                let firstHit = ranked.firstIndex(where: relevant.contains)
                for group in ["all", query.lang] {
                    let key = "\(label)|\(group)"
                    sums[key, default: [:]]["MRR", default: 0] += firstHit.map { 1 / Double($0 + 1) } ?? 0
                    for k in [1, 5, 10] where (firstHit ?? .max) < k { sums[key, default: [:]]["R@\(k)", default: 0] += 1 }
                    counts[key, default: 0] += 1
                }
                if (firstHit ?? .max) >= 10 { misses[label, default: []].append(query.q) }
            }
        }

        var report: [String: [String: Double]] = [:]
        for label in conditions {
            log("== \(label)")
            for group in ["all", "en", "zh"] {
                let key = "\(label)|\(group)"
                guard let n = counts[key], n > 0 else { continue }
                var metrics = (sums[key] ?? [:]).mapValues { $0 / Double(n) }
                for k in ["R@1", "R@5", "R@10"] where metrics[k] == nil { metrics[k] = 0 }
                report[key] = metrics
                let cells = metrics.sorted { $0.key < $1.key }.map { "\($0.key) \(String(format: "%.3f", $0.value))" }.joined(separator: "  ")
                log("\(group) [\(n)]: \(cells)")
            }
        }
        let output: [String: Any] = ["metrics": report, "misses": misses]
        if let json = try? JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
            try? json.write(to: documents.appending(path: "e4-results.json"))
        }
        log("done")
    }

    /// Rankings computed on a Mac (Eval/e4_embed.swift), by file name.
    struct VectorFile: Decodable {
        struct Ranks: Decodable { var en: [String]; var zh: [String] }
        var source: String
        var queries: [String: Ranks]
    }

    /// Embeds every photo's text here, if this device can load Apple's
    /// contextual embeddings. (The iOS simulator can't: "Embedding model
    /// requires compilation".)
    private static func embedHere() async -> (english: Space, han: Space)? {
        guard let latin = NLContextualEmbedding(language: .english),
              let chinese = NLContextualEmbedding(language: .simplifiedChinese)
        else { return nil }
        for embedding in [latin, chinese] where !embedding.hasAvailableAssets {
            _ = try? await embedding.requestAssets()
        }
        do { try latin.load(); try chinese.load() } catch { log("can't load embeddings here: \(error)"); return nil }
        let english = Space(model: latin), han = Space(model: chinese)
        let ids = Array((try? IndexStore.shared.allIDs()) ?? [])
        for (id, doc) in (try? IndexStore.shared.documents(for: ids)) ?? [:] {
            guard let text = embeddableText(doc.ocr) else { continue }
            let space = isMostlyChinese(text) ? han : english
            if let vector = space.embed(text) {
                space.ids.append(id)
                space.vectors.append(vector)
            }
        }
        log("embedded the text of \(english.ids.count) Latin-script and \(han.ids.count) Chinese photos")
        return (english, han)
    }

    /// Text worth embedding: at least 20 characters, on one line.
    static func embeddableText(_ ocr: String) -> String? {
        let text = ocr.replacingOccurrences(of: "\n", with: " ")
        return text.count >= 20 ? text : nil
    }

    static func isMostlyChinese(_ text: String) -> Bool {
        Double(text.unicodeScalars.filter(TextNormalizer.isCJK).count) / Double(max(text.count, 1)) > 0.2
    }

    /// Writes [{file, text}] for every photo with embeddable text.
    private static func exportText(byName: [String: String], to url: URL) {
        let nameByID = Dictionary(byName.map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        let docs = (try? IndexStore.shared.documents(for: Array(nameByID.keys))) ?? [:]
        let rows: [[String: String]] = docs.compactMap { id, doc in
            guard let file = nameByID[id], let text = embeddableText(doc.ocr) else { return nil }
            return ["file": file, "text": text]
        }
        if let data = try? JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url)
        }
        log("exported the text of \(rows.count) photos")
    }

    /// Weighted reciprocal rank fusion, with the search engine's k = 60.
    private static func fuse(_ lists: [([String], Double)]) -> [String] {
        var scores: [String: Double] = [:]
        for (ids, weight) in lists {
            for (rank, id) in ids.enumerated() { scores[id, default: 0] += weight / Double(60 + rank) }
        }
        // Ties broken by ID, so every run ranks the same way.
        return scores.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(100).map(\.key)
    }

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
        fputs("E4 \(message)\n", stderr)
    }
}
#endif
