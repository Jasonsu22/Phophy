import Accelerate
import Foundation
import Photos

nonisolated struct CategoryResult: Sendable, Identifiable, Equatable {
    let category: PhotoCategory
    /// Newest first.
    let localIDs: [String]
    var id: PhotoCategory { category }
}

nonisolated struct SimilarGroup: Sendable, Identifiable, Equatable {
    /// Oldest first.
    let localIDs: [String]
    /// The one to keep by default: a favorite, else the largest image.
    let suggestedKeep: String
    var id: String { localIDs[0] }
}

nonisolated struct CollectionsSnapshot: Sendable, Equatable {
    var categories: [CategoryResult] = []
    var similarGroups: [SimilarGroup] = []
}

/// Sorts indexed photos into categories and finds near-duplicates, using
/// only the embeddings already in the index. Nothing leaves the device.
actor CollectionsEngine {
    static let shared = CollectionsEngine()

    /// CLIP's similarity scale; turns cosine scores into class probabilities.
    private let logitScale: Float = 100
    /// A photo joins a category only when that category wins this clearly.
    private let minimumProbability: Float = 0.5
    /// Characters of recognized text a slide, document or receipt must have.
    private let minimumText = 20
    /// Two photos this close are treated as the same shot. Tuned on MobileCLIP S0.
    private let similarThreshold: Float = 0.92
    /// Near-duplicates are usually taken together, so each photo is compared
    /// only with the photos taken just after it.
    private let neighborWindow = 24

    private var classVectors: [[Float]]?

    func compute() async -> CollectionsSnapshot {
        guard CLIPEncoder.isAvailable,
              let data = try? IndexStore.shared.embeddings(model: CLIPEncoder.modelName),
              !data.ids.isEmpty,
              let classes = await loadClassVectors(),
              classes.allSatisfy({ $0.count == data.dimension })
        else { return CollectionsSnapshot() }

        let textLengths = (try? IndexStore.shared.textLengths()) ?? [:]

        // Assets newest first; `order` maps that ordering onto embedding rows.
        let rowByID = Dictionary(uniqueKeysWithValues: data.ids.enumerated().map { ($1, $0) })
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: data.ids, options: options)
        var assets: [PHAsset] = []
        fetched.enumerateObjects { asset, _, _ in assets.append(asset) }
        let order = assets.compactMap { rowByID[$0.localIdentifier] }

        let categories = classify(data: data, classes: classes, order: order, textLengths: textLengths)
        let texts = (try? IndexStore.shared.allTexts()) ?? [:]
        let groups = findSimilar(data: data, order: order, assets: assets, texts: texts)
        return CollectionsSnapshot(categories: categories, similarGroups: groups)
    }

    // MARK: Categories

    private func classify(
        data: (ids: [String], matrix: [Float], dimension: Int),
        classes: [[Float]],
        order: [Int],
        textLengths: [String: Int]
    ) -> [CategoryResult] {
        let rows = data.ids.count, k = classes.count, d = data.dimension

        // Class vectors as a d x k matrix, so one product scores every photo
        // against every class.
        var classMatrix = [Float](repeating: 0, count: d * k)
        for (column, vector) in classes.enumerated() {
            for i in 0..<d { classMatrix[i * k + column] = vector[i] }
        }
        var scores = [Float](repeating: 0, count: rows * k)
        vDSP_mmul(data.matrix, 1, classMatrix, 1, &scores, 1, vDSP_Length(rows), vDSP_Length(k), vDSP_Length(d))

        let categories = PhotoCategory.allCases
        var members: [PhotoCategory: [String]] = [:]
        for row in order {
            let logits = (0..<k).map { scores[row * k + $0] * logitScale }
            let top = logits.max() ?? 0
            let weights = logits.map { exp($0 - top) }
            let total = weights.reduce(0, +)
            guard let best = weights.indices.max(by: { weights[$0] < weights[$1] }) else { continue }
            let probability = weights[best] / total
            let id = data.ids[row]

            #if DEBUG
            let label = best < categories.count ? categories[best].rawValue : "other"
            fputs(String(format: "category %@ p=%.2f text=%d\n", label, probability, textLengths[id] ?? 0), stderr)
            #endif

            // The last class is "other": no category.
            guard best < categories.count, probability >= minimumProbability else { continue }
            let category = categories[best]
            if category.needsText && (textLengths[id] ?? 0) < minimumText { continue }
            members[category, default: []].append(id)
        }
        return categories.compactMap { category in
            guard let ids = members[category], !ids.isEmpty else { return nil }
            return CategoryResult(category: category, localIDs: ids)
        }
    }

    /// One averaged, normalized text embedding per category, then one for "other".
    private func loadClassVectors() async -> [[Float]]? {
        if let classVectors { return classVectors }
        var vectors: [[Float]] = []
        for prompts in PhotoCategory.allCases.map(\.prompts) + [PhotoCategory.otherPrompts] {
            var sum: [Float]?
            for prompt in prompts {
                guard let vector = try? await CLIPEncoder.shared.embed(text: prompt) else { return nil }
                sum = sum.map { zip($0, vector).map(+) } ?? vector
            }
            guard var vector = sum else { return nil }
            var length: Float = 0
            vDSP_svesq(vector, 1, &length, vDSP_Length(vector.count))
            length = length.squareRoot()
            vDSP_vsdiv(vector, 1, &length, &vector, 1, vDSP_Length(vector.count))
            vectors.append(vector)
        }
        classVectors = vectors
        return vectors
    }

    // MARK: Similar photos

    /// Slides from one deck, or pages of one document, look alike to CLIP
    /// because they share a layout. They only count as the same shot when the
    /// text on them also matches: at least 85% of their words in common, as
    /// two shots of the same slide read almost identically, and the same
    /// numbers, since a different number usually means a different lecture,
    /// page or price. Missing a real duplicate is harmless; offering to delete
    /// a slide that only looks similar is not.
    static func sameText(_ a: String?, _ b: String?) -> Bool {
        func words(_ text: String?) -> Set<String> {
            Set((text ?? "").lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        }
        let wa = words(a), wb = words(b)
        if wa.count < 4 && wb.count < 4 { return true }
        let numbers = { (words: Set<String>) in words.filter { $0.allSatisfy(\.isNumber) } }
        if numbers(wa) != numbers(wb) { return false }
        let shared = wa.intersection(wb).count
        return Double(shared) / Double(max(wa.union(wb).count, 1)) >= 0.85
    }

    private func findSimilar(
        data: (ids: [String], matrix: [Float], dimension: Int),
        order: [Int],
        assets: [PHAsset],
        texts: [String: String]
    ) -> [SimilarGroup] {
        let n = order.count, d = data.dimension
        var parent = Array(0..<n)
        func root(_ i: Int) -> Int {
            var i = i
            while parent[i] != i {
                parent[i] = parent[parent[i]]
                i = parent[i]
            }
            return i
        }

        data.matrix.withUnsafeBufferPointer { matrix in
            guard let base = matrix.baseAddress else { return }
            for a in 0..<n {
                for b in (a + 1)..<min(a + neighborWindow, n) {
                    var similarity: Float = 0
                    vDSP_dotpr(base + order[a] * d, 1, base + order[b] * d, 1, &similarity, vDSP_Length(d))
                    let idA = data.ids[order[a]], idB = data.ids[order[b]]
                    if similarity >= similarThreshold, Self.sameText(texts[idA], texts[idB]) {
                        parent[root(a)] = root(b)
                    }
                }
            }
        }

        var groups: [Int: [Int]] = [:]
        for i in 0..<n { groups[root(i), default: []].append(i) }

        return groups.values
            .filter { $0.count > 1 }
            .map { positions in
                // `positions` index the newest-first list; show oldest first.
                let members = positions.sorted(by: >).map { assets[$0] }
                let keep = members.max { lhs, rhs in
                    if lhs.isFavorite != rhs.isFavorite { return !lhs.isFavorite }
                    return lhs.pixelWidth * lhs.pixelHeight < rhs.pixelWidth * rhs.pixelHeight
                }
                return SimilarGroup(
                    localIDs: members.map(\.localIdentifier),
                    suggestedKeep: keep?.localIdentifier ?? members[0].localIdentifier
                )
            }
            .sorted { $0.localIDs.count > $1.localIDs.count }
    }
}
