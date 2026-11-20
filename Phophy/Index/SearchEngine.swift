import Accelerate
import Foundation
import UIKit

nonisolated struct SearchResults: Sendable, Equatable {
    /// Best matches overall: words and looks merged, best first.
    var bestMatches: [String] = []
    /// Photos whose recognized text contains the query exactly.
    var textMatches: [String] = []
    /// The five most similar photos whatever their score, for when nothing
    /// passes the bar: weak guesses, labelled as such for the assistant.
    var closest: [String] = []

    var isEmpty: Bool { bestMatches.isEmpty && textMatches.isEmpty }
}

/// Which parts of search to use. Everything is on in the app; the
/// evaluation (`Debug/SearchEvaluation.swift`) turns parts off to measure
/// what each adds.
nonisolated struct SearchOptions: Sendable, Hashable {
    /// The ranking from before the keyword index existed: trigram text
    /// match plus confident visual matches.
    var legacy = false
    /// BM25 over descriptions, tags, labels and text in the photo.
    var keywords = true
    /// Misspelled words are matched to the closest word in the index.
    var typos = true
    /// Concepts close to the query widen it ("coffee" → "latte").
    var expansion = true
    /// Less confident visual matches still count, a little.
    var visualTail = true
    /// Weight of the visual ranking against the keyword ranking.
    var visualWeight = 1.0
    /// Weight of the keyword ranking for searches of four words or more.
    /// A long description is matched better by the visual model, and by
    /// descriptions where there are some; tags and labels alone are noisy there.
    var longQueryKeywordWeight = 0.5
    /// For searches of four words or more, the visual ranking also counts
    /// how far ahead a photo is, not just its place, so a clear visual
    /// winner isn't outvoted by keyword matches on common words. (Short
    /// searches do slightly better without it.)
    var visualScores = true

    static let standard = SearchOptions()
    static let previous = SearchOptions(legacy: true)
}

/// Answers a search from the local index. Nothing leaves the device.
///
/// A query is turned into words (English reduced to dictionary forms,
/// Chinese split into words, misspellings corrected) and into a MobileCLIP
/// vector (Chinese is read through the concept dictionary first, since the
/// model only reads English). Keyword matches are ranked by BM25 over each
/// photo's description, tags, labels and text; visual matches by cosine
/// similarity. The rankings are merged with weighted reciprocal rank fusion.
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

    private var vocabulary: [String: Int] = [:]
    private var vocabularyLoaded = ContinuousClock.now - .seconds(3600)

    // MARK: Search tab

    /// `indexedCount` tells the engine when its cached embeddings are stale.
    func search(_ rawQuery: String, indexedCount: Int) async -> SearchResults {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return SearchResults() }
        let ranked = await rank(query, among: nil, indexedCount: indexedCount, limit: 300)
        var results = SearchResults()
        results.closest = ranked.weak ? ranked.ids : []
        results.bestMatches = ranked.weak ? [] : ranked.ids
        let exact = (try? IndexStore.shared.textMatches(query)) ?? []
        // Exact text hits that the ranking didn't already show near the top.
        let shown = Set(results.bestMatches.prefix(60))
        results.textMatches = exact.filter { !shown.contains($0) }
        return results
    }

    // MARK: Ranked search within filters

    nonisolated struct Ranked: Sendable {
        var ids: [String]
        /// True when nothing scored well and these are only the nearest photos.
        var weak: Bool
    }

    /// Ranks photos for a description: filters first (the `candidates`, if
    /// any), then keyword and visual rankings merged, so a photo good on
    /// both counts comes first.
    func rank(
        _ description: String, among candidates: [String]?, indexedCount: Int, limit: Int,
        options: SearchOptions = .standard
    ) async -> Ranked {
        let query = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return Ranked(ids: [], weak: true) }
        let allowed = candidates.map(Set.init)
        func keep(_ id: String) -> Bool { allowed?.contains(id) ?? true }

        var lists: [(ids: [String], weight: Double)] = []

        // Words.
        let plan = await plan(for: query, options: options)
        var keywordHits: [String] = []
        var longQuery = false
        if options.legacy || !options.keywords {
            keywordHits = ((try? IndexStore.shared.textMatches(query, limit: 500)) ?? []).filter(keep)
            lists.append((keywordHits, 1))
        } else {
            keywordHits = ((try? IndexStore.shared.keywordMatches(plan.terms, limit: 500)) ?? []).map(\.id).filter(keep)
            lists.append((keywordHits, plan.terms.count >= 4 ? options.longQueryKeywordWeight : 1))
            longQuery = plan.terms.count >= 4
            if !plan.expansion.isEmpty {
                let widened = ((try? IndexStore.shared.keywordMatches(plan.expansion, limit: 300)) ?? []).map(\.id).filter(keep)
                lists.append((widened, 0.4))
            }
            // Exact substrings (text in slides, short Chinese words).
            let exact = ((try? IndexStore.shared.textMatches(query, limit: 200)) ?? []).filter(keep)
            lists.append((exact, 0.5))
        }

        // Looks.
        var visual: [(String, Float)] = []
        if let visualQuery = plan.visualQuery, let vector = await queryVector(visualQuery) {
            visual = similarities(to: vector, indexedCount: indexedCount).filter { keep($0.0) }
        }
        let best = visual.first?.1 ?? 0
        if allowed == nil {
            // Without filters, only confident visual matches count fully.
            let strong = visual.prefix { $0.1 >= minimumScore && $0.1 >= best - margin }.map(\.0)
            lists.append((strong, options.visualWeight))
            if options.visualTail && !options.legacy {
                lists.append((visual.prefix(200).map(\.0), 0.5 * options.visualWeight))
            }
        } else {
            // With filters the photos are already narrowed down, so ranking alone decides.
            lists.append((visual.prefix(200).map(\.0), options.visualWeight))
        }

        var fused: [String: Double] = [:]
        for list in lists {
            for (rank, id) in list.ids.enumerated() { fused[id, default: 0] += list.weight / Double(60 + rank) }
        }
        if options.visualScores, longQuery, allowed == nil, visual.count > 1 {
            // A bonus of up to one first place, by how close the photo comes
            // to the best visual score (cubed, so only clear leaders gain much).
            let floor = visual[min(199, visual.count - 1)].1
            let span = max(best - floor, 0.0001)
            for (id, score) in visual.prefix(200) {
                let closeness = Double(max(score - floor, 0) / span)
                fused[id, default: 0] += options.visualWeight * closeness * closeness * closeness / 60
            }
        }
        let ranked = fused.sorted { $0.value > $1.value }.map(\.key)

        if ranked.isEmpty {
            return Ranked(ids: Array(visual.prefix(min(limit, 5)).map(\.0)), weak: true)
        }
        let weak = keywordHits.isEmpty && best < minimumScore
        #if DEBUG
        if !SearchEvaluation.isRequested {
            fputs("search \"\(query)\": terms \(plan.terms) expansion \(plan.expansion.flatMap { $0 }) visual \"\(plan.visualQuery ?? "-")\" best \(String(format: "%.3f", best)) keyword hits \(keywordHits.count)\n", stderr)
        }
        #endif
        return Ranked(ids: Array(ranked.prefix(limit)), weak: weak)
    }

    // MARK: Understanding the query

    private struct QueryPlan {
        /// Groups of alternatives, any of which may match.
        var terms: [[String]]
        /// Related concepts, searched separately with less weight.
        var expansion: [[String]]
        /// English text for the visual model, if there is any.
        var visualQuery: String?
    }

    private func plan(for query: String, options: SearchOptions) async -> QueryPlan {
        let words = TextNormalizer.queryTerms(query)
        let chinese = TextNormalizer.containsCJK(query)
        if options.legacy {
            return QueryPlan(terms: words.map { [$0] }, expansion: [], visualQuery: query)
        }

        var terms = words.map { [$0] }
        var visualQuery: String? = query
        var expansion: [[String]] = []

        if chinese {
            // The visual model reads English only: read the query through the
            // concept dictionary, and search the English names as words too.
            let english = ConceptTagger.shared.englishConcepts(in: query, words: words)
            visualQuery = english.isEmpty ? nil : english.joined(separator: ", ")
            for name in english { terms.append(TextNormalizer.queryTerms(name)) }
        }

        if options.typos, options.keywords {
            await loadVocabularyIfStale()
            var fixes: [String: String] = [:]
            for index in terms.indices {
                for word in terms[index] where vocabulary[word] == nil {
                    // Only words that aren't real words: "orange" may simply
                    // not be in the index yet, and mustn't become "range".
                    guard await Self.isMisspelled(word) else { continue }
                    if let fixed = correction(for: word) {
                        terms[index].append(fixed)
                        fixes[word] = fixed
                    }
                }
            }
            // The visual model should see the corrected words too.
            if !chinese, !fixes.isEmpty {
                visualQuery = query.split(separator: " ").map { piece in
                    fixes[piece.lowercased()] ?? String(piece)
                }.joined(separator: " ")
            }
        }

        if options.expansion, let visualQuery, let vector = await queryVector(visualQuery) {
            let known = Set(terms.flatMap { $0 })
            let near = await ConceptTagger.shared.nearest(to: vector, count: 4, minimumScore: 0.86)
            for (concept, _) in near {
                let group = TextNormalizer.queryTerms(concept.english)
                if !group.isEmpty, !group.allSatisfy(known.contains) { expansion.append(group) }
            }
        }
        return QueryPlan(terms: terms, expansion: expansion, visualQuery: visualQuery)
    }

    private var vectorCache: [String: [Float]] = [:]

    private func queryVector(_ text: String) async -> [Float]? {
        if let cached = vectorCache[text] { return cached }
        guard CLIPEncoder.isAvailable, let vector = try? await CLIPEncoder.shared.embed(text: "a photo of \(text)") else { return nil }
        if vectorCache.count > 200 { vectorCache.removeAll() }
        vectorCache[text] = vector
        return vector
    }

    private func similarities(to vector: [Float], indexedCount: Int) -> [(String, Float)] {
        if cache == nil || cachedForCount != indexedCount {
            cache = try? IndexStore.shared.embeddings(model: CLIPEncoder.modelName)
            cachedForCount = indexedCount
        }
        guard let cache, !cache.ids.isEmpty, cache.dimension == vector.count else { return [] }
        // One matrix-vector product gives the similarity of every photo to the query.
        var scores = [Float](repeating: 0, count: cache.ids.count)
        vDSP_mmul(cache.matrix, 1, vector, 1, &scores, 1,
                  vDSP_Length(cache.ids.count), 1, vDSP_Length(cache.dimension))
        return zip(cache.ids, scores).sorted { $0.1 > $1.1 }
    }

    // MARK: Typos

    @MainActor private static let checker = UITextChecker()

    @MainActor private static func isMisspelled(_ word: String) -> Bool {
        let range = checker.rangeOfMisspelledWord(
            in: word, range: NSRange(location: 0, length: (word as NSString).length),
            startingAt: 0, wrap: false, language: "en_US"
        )
        return range.location != NSNotFound
    }

    private func loadVocabularyIfStale() async {
        guard ContinuousClock.now - vocabularyLoaded > .seconds(60) else { return }
        vocabulary = (try? IndexStore.shared.vocabulary()) ?? [:]
        vocabularyLoaded = .now
    }

    /// The most common index word within one edit (two for long words) of
    /// `word`, if `word` itself isn't in the index.
    private func correction(for word: String) -> String? {
        let length = word.count
        guard length >= 3, !word.unicodeScalars.contains(where: TextNormalizer.isCJK),
              !word.contains(where: \.isNumber) else { return nil }
        let allowed = length >= 7 ? 2 : 1
        let letters = Array(word)
        var best: (String, Int)?
        for (candidate, frequency) in vocabulary where abs(candidate.count - length) <= allowed {
            guard frequency > (best?.1 ?? 0) else { continue }
            if Self.editDistance(letters, Array(candidate), limit: allowed) <= allowed {
                best = (candidate, frequency)
            }
        }
        return best?.0
    }

    /// Damerau–Levenshtein distance (adjacent swaps count as one edit),
    /// giving up early once it's over `limit`.
    static func editDistance(_ a: [Character], _ b: [Character], limit: Int) -> Int {
        if abs(a.count - b.count) > limit { return limit + 1 }
        if a.isEmpty || b.isEmpty { return max(a.count, b.count) }
        var previous2 = [Int](repeating: 0, count: b.count + 1)
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            var rowMinimum = current[0]
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                var value = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    value = min(value, previous2[j - 2] + 1)
                }
                current[j] = value
                rowMinimum = min(rowMinimum, value)
            }
            if rowMinimum > limit { return limit + 1 }
            (previous2, previous, current) = (previous, current, previous2)
        }
        return previous[b.count]
    }
}
