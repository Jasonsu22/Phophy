import Accelerate
import Foundation

nonisolated struct SearchResults: Sendable, Equatable {
    /// Photos whose recognized text or labels contain the query words.
    var textMatches: [String] = []
    /// Photos that look like the description, best first.
    var lookAlikes: [String] = []
    /// The five most similar photos whatever their score, for when nothing
    /// passes the bar: weak guesses, labelled as such for the assistant.
    var closest: [String] = []

    var isEmpty: Bool { textMatches.isEmpty && lookAlikes.isEmpty }
}

/// Answers a search from the local index. Nothing leaves the device.
actor SearchEngine {
    static let shared = SearchEngine()

    /// A look-alike must score at least this, and be within `margin` of the best hit.
    /// Tuned on MobileCLIP S0, where real matches scored 0.25 and up and
    /// unrelated photos stayed under 0.18. Re-check after changing the model.
    private let minimumScore: Float = 0.20
    private let margin: Float = 0.05
    private let maximumLookAlikes = 60

    private var cache: (ids: [String], matrix: [Float], dimension: Int)?
    private var cachedForCount = -1

    /// `indexedCount` tells the engine when its cached embeddings are stale.
    func search(_ rawQuery: String, indexedCount: Int) async -> SearchResults {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return SearchResults() }

        var results = SearchResults()
        results.textMatches = (try? IndexStore.shared.textMatches(query)) ?? []

        guard CLIPEncoder.isAvailable,
              let vector = try? await CLIPEncoder.shared.embed(text: "a photo of \(query)")
        else { return results }

        if cache == nil || cachedForCount != indexedCount {
            cache = try? IndexStore.shared.embeddings(model: CLIPEncoder.modelName)
            cachedForCount = indexedCount
        }
        guard let cache, !cache.ids.isEmpty, cache.dimension == vector.count else { return results }

        // One matrix-vector product gives the similarity of every photo to the query.
        var scores = [Float](repeating: 0, count: cache.ids.count)
        vDSP_mmul(
            cache.matrix, 1, vector, 1, &scores, 1,
            vDSP_Length(cache.ids.count), 1, vDSP_Length(cache.dimension)
        )
        let ranked = zip(cache.ids, scores).sorted { $0.1 > $1.1 }
        guard let best = ranked.first?.1 else { return results }

        results.closest = ranked.prefix(5).map(\.0)
        let alreadyShown = Set(results.textMatches)
        results.lookAlikes = ranked
            .prefix { $0.1 >= minimumScore && $0.1 >= best - margin }
            .prefix(maximumLookAlikes)
            .map(\.0)
            .filter { !alreadyShown.contains($0) }
        #if DEBUG
        let line = "search \"\(query)\": " + ranked.prefix(8).map { String(format: "%.3f", $0.1) }.joined(separator: " ")
        fputs(line + "\n", stderr)
        #endif
        return results
    }

    // MARK: Ranked search within filters

    nonisolated struct Ranked: Sendable {
        var ids: [String]
        /// True when nothing scored well and these are only the nearest photos.
        var weak: Bool
    }

    /// Ranks photos for a description, the way Immich's smart search works:
    /// filters first (the `candidates`, if any), then words found in the
    /// photos and visual similarity are merged into one ranking (reciprocal
    /// rank fusion), so a photo good on both counts comes first.
    func rank(_ description: String, among candidates: [String]?, indexedCount: Int, limit: Int) async -> Ranked {
        let query = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = candidates.map(Set.init)

        var textHits = (try? IndexStore.shared.textMatches(query, limit: 500)) ?? []
        if let allowed { textHits = textHits.filter { allowed.contains($0) } }

        var visual: [(String, Float)] = []
        if CLIPEncoder.isAvailable, let vector = try? await CLIPEncoder.shared.embed(text: "a photo of \(query)") {
            if cache == nil || cachedForCount != indexedCount {
                cache = try? IndexStore.shared.embeddings(model: CLIPEncoder.modelName)
                cachedForCount = indexedCount
            }
            if let cache, !cache.ids.isEmpty, cache.dimension == vector.count {
                var scores = [Float](repeating: 0, count: cache.ids.count)
                vDSP_mmul(cache.matrix, 1, vector, 1, &scores, 1,
                          vDSP_Length(cache.ids.count), 1, vDSP_Length(cache.dimension))
                visual = zip(cache.ids, scores)
                    .filter { allowed?.contains($0.0) ?? true }
                    .sorted { $0.1 > $1.1 }
            }
        }

        let best = visual.first?.1 ?? 0
        // Without filters, only confident visual matches count. With filters
        // the photos are already narrowed down, so ranking alone decides.
        let strongVisual = allowed == nil
            ? visual.prefix { $0.1 >= minimumScore && $0.1 >= best - margin }.map(\.0)
            : Array(visual.prefix(200).map(\.0))

        var fused: [String: Double] = [:]
        for (rank, id) in textHits.enumerated() { fused[id, default: 0] += 1 / Double(60 + rank) }
        for (rank, id) in strongVisual.enumerated() { fused[id, default: 0] += 1 / Double(60 + rank) }
        let ranked = fused.sorted { $0.value > $1.value }.map(\.key)

        if ranked.isEmpty {
            return Ranked(ids: Array(visual.prefix(min(limit, 5)).map(\.0)), weak: true)
        }
        let weak = textHits.isEmpty && best < minimumScore
        return Ranked(ids: Array(ranked.prefix(limit)), weak: weak)
    }
}
