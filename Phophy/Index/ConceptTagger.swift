import Accelerate
import Foundation

/// Gives every photo a few words ("waterfall 瀑布", "latte art 拉花") by
/// comparing its stored MobileCLIP embedding with a vocabulary of 4,585
/// everyday concepts in English and Chinese (the Recognize Anything tag
/// list, Apache-2.0).
///
/// This is the cheapest layer of the index: no image is loaded, no model
/// writes text, it's one matrix product per batch of photos, so the whole
/// library is tagged in seconds. It turns what the embedding sees into
/// words keyword search can find, and it doubles as a small Chinese-English
/// dictionary for queries.
actor ConceptTagger {
    static let shared = ConceptTagger()

    /// Bumped when the tagging rule changes, so photos are tagged again.
    /// 4: back to tagging every photo (dropping tags from text-heavy photos
    /// also dropped useful ones such as "receipt").
    nonisolated static let version = 4

    nonisolated struct Concept: Sendable {
        let english: String
        let chinese: [String]
    }

    /// Tagging rule, tuned on the Flickr test set (Eval/).
    nonisolated struct Rule: Sendable {
        /// At most this many tags per photo.
        var maximum = 6
        /// A tag must beat the concept's library-wide average by this much…
        var minimumLift: Float = 0.035
        /// …and be within this much of the photo's best tag.
        var margin: Float = 0.03
    }
    var rule = Rule()

    nonisolated let concepts: [Concept] = {
        guard let url = Bundle.main.url(forResource: "concepts", withExtension: "tsv"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return [] }
        return text.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            guard let english = parts.first, !english.isEmpty else { return nil }
            let chinese = parts.count > 1 ? parts[1].split(separator: " ").map(String.init) : []
            return Concept(english: english, chinese: chinese)
        }
    }()

    private var vectors: [Float] = []
    private var dimension = 0

    // MARK: Concept vectors

    /// Embeds every concept once ("a photo of a waterfall") and keeps the
    /// result in the index, about 9 MB. Takes about 20 seconds the first time.
    func prepare() async -> Bool {
        if !vectors.isEmpty { return true }
        guard CLIPEncoder.isAvailable, !concepts.isEmpty else { return false }
        let model = CLIPEncoder.modelName
        // Shipped with the app, computed once on a Mac (half precision, 4.7 MB).
        if let url = Bundle.main.url(forResource: "concepts-\(model)", withExtension: "f16"),
           let data = try? Data(contentsOf: url), data.count % (2 * concepts.count) == 0 {
            let halves = data.withUnsafeBytes { Array($0.bindMemory(to: Float16.self)) }
            vectors = halves.map(Float.init)
            dimension = halves.count / concepts.count
            return true
        }
        if let stored = try? IndexStore.shared.conceptVectors(model: model), stored.count == concepts.count {
            vectors = stored.data
            dimension = stored.dimension
            return true
        }
        var data: [Float] = []
        var dim = 0
        for concept in concepts {
            guard let vector = try? await CLIPEncoder.shared.embed(text: "a photo of \(concept.english)") else { return false }
            dim = vector.count
            data += vector
        }
        try? IndexStore.shared.saveConceptVectors(model: model, count: concepts.count, dimension: dim, data: data)
        vectors = data
        dimension = dim
        return true
    }

    // MARK: Tagging photos

    /// Tags every photo that has an embedding but no current tags.
    /// Returns how many photos were tagged.
    @discardableResult
    func tagPending() async -> Int {
        let store = IndexStore.shared
        let model = CLIPEncoder.modelName
        guard let pending = try? store.untaggedIDs(version: Self.version, model: model), !pending.isEmpty,
              await prepare(),
              let library = try? store.embeddings(model: model), library.dimension == dimension
        else { return 0 }

        let bias = conceptBias(library.matrix, count: library.ids.count)
        let row = Dictionary(uniqueKeysWithValues: library.ids.enumerated().map { ($1, $0) })
        let pendingRows = pending.compactMap { row[$0] }

        var tagged = 0
        for start in stride(from: 0, to: pendingRows.count, by: 256) {
            let rows = Array(pendingRows[start..<min(start + 256, pendingRows.count)])
            var chunk = [Float]()
            chunk.reserveCapacity(rows.count * dimension)
            for r in rows { chunk += library.matrix[(r * dimension)..<((r + 1) * dimension)] }
            let scores = similarities(chunk, rows: rows.count)

            var tags: [String: String] = [:]
            for (i, r) in rows.enumerated() {
                let photoScores = scores[(i * concepts.count)..<((i + 1) * concepts.count)]
                let picked = pick(Array(photoScores), bias: bias)
                tags[library.ids[r]] = picked.map { index in
                    let concept = concepts[index]
                    return ([concept.english] + concept.chinese).joined(separator: " / ")
                }.joined(separator: ", ")
            }
            try? store.saveTags(tags, version: Self.version)
            tagged += rows.count
            await Task.yield()
        }
        return tagged
    }

    /// Tags for one photo from its scores, best first.
    private func pick(_ scores: [Float], bias: [Float]) -> [Int] {
        var lifted = [Float](repeating: 0, count: scores.count)
        vDSP_vsub(bias, 1, scores, 1, &lifted, 1, vDSP_Length(scores.count))
        let order = lifted.indices.sorted { lifted[$0] > lifted[$1] }.prefix(rule.maximum * 2)
        guard let best = order.first.map({ lifted[$0] }) else { return [] }
        return Array(order
            .filter { lifted[$0] >= rule.minimumLift && lifted[$0] >= best - rule.margin }
            .prefix(rule.maximum))
    }

    /// Each concept's average similarity over (a sample of) the library.
    /// Some concepts score high against every photo; subtracting this
    /// stops them from tagging everything.
    private func conceptBias(_ matrix: [Float], count: Int) -> [Float] {
        let step = max(1, count / 2000)
        var sample: [Float] = []
        var n = 0
        for r in stride(from: 0, to: count, by: step) {
            sample += matrix[(r * dimension)..<((r + 1) * dimension)]
            n += 1
        }
        let scores = similarities(sample, rows: n)
        var mean = [Float](repeating: 0, count: concepts.count)
        for r in 0..<n {
            scores.withUnsafeBufferPointer { buffer in
                vDSP_vadd(buffer.baseAddress! + r * concepts.count, 1, mean, 1, &mean, 1, vDSP_Length(concepts.count))
            }
        }
        var divisor = Float(max(n, 1))
        vDSP_vsdiv(mean, 1, &divisor, &mean, 1, vDSP_Length(concepts.count))
        return mean
    }

    /// rows × concepts similarity matrix (row-major).
    private func similarities(_ embeddings: [Float], rows: Int) -> [Float] {
        var out = [Float](repeating: 0, count: rows * concepts.count)
        // out = embeddings (rows × d) · vectorsᵀ (d × concepts)
        cblas_sgemm(
            CblasRowMajor, CblasNoTrans, CblasTrans,
            Int32(rows), Int32(concepts.count), Int32(dimension),
            1, embeddings, Int32(dimension), vectors, Int32(dimension),
            0, &out, Int32(concepts.count)
        )
        return out
    }

    // MARK: Queries

    /// Concepts whose text is closest to a query's embedding, for widening a
    /// search ("coffee" → "latte", "espresso").
    func nearest(to query: [Float], count: Int, minimumScore: Float) async -> [(Concept, Float)] {
        guard await prepare(), query.count == dimension else { return [] }
        var scores = [Float](repeating: 0, count: concepts.count)
        vDSP_mmul(vectors, 1, query, 1, &scores, 1, vDSP_Length(concepts.count), 1, vDSP_Length(dimension))
        return scores.indices
            .sorted { scores[$0] > scores[$1] }
            .prefix(count)
            .filter { scores[$0] >= minimumScore }
            .map { (concepts[$0], scores[$0]) }
    }

    /// English names of the concepts mentioned in a Chinese query, for the
    /// visual search (the CLIP model only reads English).
    nonisolated func englishConcepts(in chinese: String, words: [String]) -> [String] {
        var found: [(position: String.Index, english: String)] = []
        var covered = Set<String>()
        for concept in concepts {
            for name in concept.chinese where !name.isEmpty {
                // Two characters or more can match inside the query; a single
                // character ("马") only when the tokenizer found it as a word,
                // so "马路" (road) isn't read as "horse".
                let hit = name.count >= 2 ? chinese.range(of: name) : (words.contains(name) ? chinese.range(of: name) : nil)
                if let hit, covered.insert(concept.english).inserted {
                    found.append((hit.lowerBound, concept.english))
                    break
                }
            }
        }
        // Prefer longer, more specific names, and keep the query's order.
        let specific = found.filter { candidate in
            !found.contains { other in other.english != candidate.english && other.english.contains(candidate.english) }
        }
        return specific.sorted { $0.position < $1.position }.map(\.english)
    }
}
