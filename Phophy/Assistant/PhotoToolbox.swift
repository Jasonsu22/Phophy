import Foundation
import Photos

/// Something the assistant decided to put in front of the user.
nonisolated struct AlbumProposal: Identifiable, Sendable, Equatable, Codable {
    var id = UUID()
    let title: String
    let localIDs: [String]
}

/// What the assistant can do with the library. Both backends (cloud and
/// Apple Intelligence) call these same functions. Results are short text:
/// the model never receives the images themselves, only each photo's date,
/// category, labels and recognized text.
///
/// Photos are referred to by short refs ("p1", "p2", ...) that stay stable
/// for one conversation, which keeps tool results small.
actor PhotoToolbox {
    /// How much recognized text to include per photo. The on-device model has
    /// a small context window, so it gets less.
    private let snippetLength: Int
    private let categories: [String: PhotoCategory]
    private var indexedCount = 0

    private var refByID: [String: String] = [:]
    private var idByRef: [String: String] = [:]

    private var shownIDs: [String] = []
    /// What the assistant did this turn, shown under its reply.
    private var steps: [String] = []
    private var searchesThisTurn = 0
    /// What the last search or date lookup this turn returned.
    private var lastResultIDs: [String] = []
    private var proposals: [AlbumProposal] = []

    init(snippetLength: Int, categories: [String: PhotoCategory]) {
        self.snippetLength = snippetLength
        self.categories = categories
    }

    func setIndexedCount(_ count: Int) { indexedCount = count }

    /// Photos and albums to show with the reply, collected during one turn.
    /// Small models sometimes name photos in their reply ("p1, p2") instead
    /// of calling show_photos; those photos are shown too, and the refs,
    /// which mean nothing to the user, are taken out of the text.
    func present(reply: String) -> (text: String, photoIDs: [String], albums: [AlbumProposal], steps: [String]) {
        let steps = self.steps
        defer {
            shownIDs = []
            proposals = []
            lastResultIDs = []
            self.steps = []
            searchesThisTurn = 0
        }
        let pattern = /\bp(\d+)\b/
        let mentioned = reply.matches(of: pattern).compactMap { idByRef["p\($0.1)"] }
        var seen = Set<String>()
        var ids = (shownIDs + mentioned).filter { seen.insert($0).inserted }
        // Last resort: the model looked photos up but showed none of them.
        if ids.isEmpty { ids = Array(lastResultIDs.prefix(12)) }
        return (Self.removingRefs(from: reply), ids, proposals, steps)
    }

    /// Drops ref tokens and the punctuation left around them, line by line.
    private static func removingRefs(from text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                var line = String(line)
                line = line.replacing(/\(?\bp\d+\b\)?\s*(—|–|-|:)?\s*/, with: "")
                line = line.replacing(/\s+([,.;:])/) { String($0.1) }
                return line.trimmingCharacters(in: .whitespaces)
            }
            .joined(separator: "\n")
            .replacing(/\n{3,}/, with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Tools

    /// The one search: optional filters (place, dates, category, favourites,
    /// type) narrow the library, then an optional description ranks what's
    /// left by the words in the photos and by how they look.
    func find(
        description: String?, place: String?, start: String?, end: String?,
        category: String?, favoritesOnly: Bool, media: String?, limit: Int
    ) async -> String {
        searchesThisTurn += 1
        var description = description?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let place = place?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        var category = category?.nilIfEmpty
        // Models often repeat the place as the description; it adds nothing.
        if let d = description, let place, d.lowercased() == place.lowercased() { description = nil }
        let media = media?.nilIfEmpty
        let limit = clamped(limit)

        var from: Date?, to: Date?
        if let start {
            guard let day = Self.day.date(from: start) else { return "Error: start must look like 2024-03-01." }
            from = day
        }
        if let end {
            guard let day = Self.day.date(from: end) else { return "Error: end must look like 2024-03-31." }
            to = Calendar.current.date(byAdding: .day, value: 1, to: day)
        }

        // Filters, covering the whole library whether indexed or not.
        let hasFilters = place != nil || from != nil || to != nil || category != nil || favoritesOnly || media != nil
        var candidates: [String]?
        var relaxed: [String] = []
        if hasFilters {
            candidates = filtered(from: from, to: to, place: place, media: media, category: category, favoritesOnly: favoritesOnly)
            // Models guess details the user didn't give (a category) or
            // misjudge dates ("two years ago" read as "since two years
            // ago"). Before giving up, loosen the filters a step at a time
            // and say so in the result.
            if candidates?.isEmpty == true, category != nil {
                let retry = filtered(from: from, to: to, place: place, media: media, category: nil, favoritesOnly: favoritesOnly)
                if !retry.isEmpty { candidates = retry; relaxed.append("dropped the category \(category!)"); category = nil }
            }
            if candidates?.isEmpty == true, from != nil || to != nil {
                let widen: TimeInterval = 183 * 86_400
                let wideFrom = from.map { $0.addingTimeInterval(-widen) }, wideTo = to.map { $0.addingTimeInterval(widen) }
                let retry = filtered(from: wideFrom, to: wideTo, place: place, media: media, category: category, favoritesOnly: favoritesOnly)
                if !retry.isEmpty {
                    candidates = retry
                    relaxed.append("widened the dates by six months each side")
                } else if place != nil {
                    let anyTime = filtered(from: nil, to: nil, place: place, media: media, category: category, favoritesOnly: favoritesOnly)
                    if !anyTime.isEmpty { candidates = anyTime; relaxed.append("ignored the dates; nothing from that place in or near that period") }
                }
            }
        }

        var summary: [String] = []
        if let description { summary.append("“\(description)”") }
        if let place { summary.append("in \(place)") }
        if let start { summary.append("from \(start)") }
        if let end { summary.append("to \(end)") }
        if let category { summary.append(category) }
        if favoritesOnly { summary.append("favorites") }
        if let media { summary.append(media) }
        let label = summary.joined(separator: " ")

        // Filters matched nothing: explain why, so the model doesn't guess.
        if let candidates, candidates.isEmpty {
            steps.append("Searched \(label) · none")
            var reasons = ["No photos match these filters."]
            if place != nil {
                let coverage = try? IndexStore.shared.coverage()
                let known = (try? IndexStore.shared.places(matching: nil, limit: 8)) ?? []
                if let coverage {
                    reasons.append("Place names are known for \(coverage.placesNamed) of \(coverage.photos) photos (\(coverage.withLocation) have a location; \(coverage.placesPending) areas still being looked up).")
                }
                if !known.isEmpty {
                    reasons.append("Most common places: " + known.map { "\($0.label) (\($0.count))" }.joined(separator: "; ") + ".")
                }
                reasons.append("Call list_places to check how the place is named, or drop the place filter.")
            }
            return reasons.joined(separator: " ") + " " + budgetNote()
        }

        var ids: [String]
        var weak = false
        if let description {
            let ranked = await SearchEngine.shared.rank(description, among: candidates, indexedCount: indexedCount, limit: limit)
            ids = ranked.ids
            weak = ranked.weak
        } else {
            ids = Array((candidates ?? []).prefix(limit))
        }

        var header: [String] = []
        if !relaxed.isEmpty {
            header.append("Nothing matched exactly, so the search " + relaxed.joined(separator: " and ") + ". Tell the user this.")
        }
        if let candidates {
            header.append("\(candidates.count) photos match the filters.")
            if description != nil {
                let indexedSet = (try? IndexStore.shared.indexedIDs(embeddingModel: CLIPEncoder.isAvailable ? CLIPEncoder.modelName : nil)) ?? []
                let unindexed = candidates.filter { !indexedSet.contains($0) }.count
                if unindexed > 0 {
                    header.append("\(unindexed) of them are not indexed yet, so the description can't rank them; they are still found by the filters alone.")
                }
            }
        }

        guard !ids.isEmpty else {
            steps.append("Searched \(label) · none")
            return (header + ["Nothing found. \(budgetNote())"]).joined(separator: " ")
        }
        lastResultIDs = ids
        steps.append("Searched \(label) · \(ids.count) found" + (relaxed.isEmpty ? "" : " after loosening filters"))
        if weak {
            header.append("No close match for the description; these are only the nearest and may be unrelated. Use them only if their details fit. \(budgetNote())")
        } else {
            header.append(description != nil ? "Best match first:" : "Newest first:")
        }
        return header.joined(separator: " ") + "\n" + describe(ids)
    }

    /// Where photos were taken, with counts and date spans.
    func listPlaces(matching query: String?) -> String {
        let places = (try? IndexStore.shared.places(matching: query?.nilIfEmpty, limit: 25)) ?? []
        let coverage = try? IndexStore.shared.coverage()
        steps.append(query.map { "Looked up places like “\($0)”" } ?? "Looked up places")
        var lines: [String] = []
        if let coverage {
            lines.append("\(coverage.withLocation) of \(coverage.photos) photos have a location; \(coverage.placesNamed) have a place name so far.")
        }
        if places.isEmpty {
            lines.append(query == nil ? "No place names yet." : "No place matches “\(query!)”.")
        }
        for place in places {
            let span = [place.first, place.last].compactMap { $0.map { Self.day.string(from: $0) } }
            lines.append("\(place.label): \(place.count) photos" + (span.count == 2 ? ", \(span[0]) to \(span[1])" : ""))
        }
        return lines.joined(separator: "\n")
    }

    private func filtered(
        from: Date?, to: Date?, place: String?, media: String?, category: String?, favoritesOnly: Bool
    ) -> [String] {
        var ids = (try? IndexStore.shared.filteredIDs(from: from, to: to, place: place, media: media)) ?? []
        if let category {
            if category == "screenshots" {
                let shots = Self.ids(matching: Self.screenshotOptions)
                ids = ids.filter { shots.contains($0) }
            } else {
                ids = ids.filter { categories[$0]?.rawValue == category }
            }
        }
        if favoritesOnly {
            let options = PHFetchOptions()
            options.predicate = NSPredicate(format: "isFavorite == YES")
            let favorites = Self.ids(matching: options)
            ids = ids.filter { favorites.contains($0) }
        }
        return ids
    }

    private func budgetNote() -> String {
        searchesThisTurn >= 3
            ? "You have searched \(searchesThisTurn) times for this question. Stop searching and answer with what you have."
            : "Change the filters or wording at most once more; do not repeat near-identical searches."
    }

    private static func ids(matching options: PHFetchOptions) -> Set<String> {
        var ids = Set<String>()
        PHAsset.fetchAssets(with: options).enumerateObjects { asset, _, _ in ids.insert(asset.localIdentifier) }
        return ids
    }

    func listCollections() -> String {
        var counts: [PhotoCategory: Int] = [:]
        for category in categories.values { counts[category, default: 0] += 1 }
        let screenshots = PHAsset.fetchAssets(with: Self.screenshotOptions).count
        let total = PHAsset.fetchAssets(with: .image, options: nil).count
        // One labelled line each: small models misread long one-line lists.
        var lines = [
            "Total photos in the library: \(total) (\(indexedCount) indexed)",
            "Screenshots: \(screenshots)",
        ]
        lines += PhotoCategory.allCases.map { "\($0.title): \(counts[$0] ?? 0)" }
        return lines.joined(separator: "\n")
    }

    func show(refs: [String], caption: String?) -> String {
        let ids = refs.compactMap { idByRef[$0] }
        guard !ids.isEmpty else { return "Error: none of those refs are known. Use refs from a search first." }
        shownIDs += ids
        return "Showing \(ids.count) photos to the user."
    }

    func proposeAlbum(title: String, refs: [String]) -> String {
        let ids = refs.compactMap { idByRef[$0] }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ids.isEmpty, !name.isEmpty else { return "Error: an album needs a title and known refs." }
        proposals.append(AlbumProposal(title: name, localIDs: ids))
        return "Offered the user a button to save \(ids.count) photos as “\(name)”. Nothing is saved until they tap it."
    }

    // MARK: Cloud dispatch

    /// Runs a tool call from the cloud model. Returns the result text and
    /// whether it was an error.
    func run(name: String, input: Data) async -> (String, Bool) {
        let decoder = JSONDecoder()
        do {
            switch name {
            case "find_photos":
                let args = try decoder.decode(FindArgs.self, from: input)
                return (await find(
                    description: args.description, place: args.place, start: args.start, end: args.end,
                    category: args.category, favoritesOnly: args.favorites_only ?? false,
                    media: args.media, limit: args.limit ?? 12
                ), false)
            case "list_places":
                let args = try decoder.decode(PlacesArgs.self, from: input)
                return (listPlaces(matching: args.query), false)
            case "list_collections":
                return (listCollections(), false)
            case "show_photos":
                let args = try decoder.decode(ShowArgs.self, from: input)
                return (show(refs: args.refs, caption: args.caption), false)
            case "propose_album":
                let args = try decoder.decode(AlbumArgs.self, from: input)
                return (proposeAlbum(title: args.title, refs: args.refs), false)
            default:
                return ("Unknown tool \(name).", true)
            }
        } catch {
            return ("Invalid arguments for \(name): \(error.localizedDescription)", true)
        }
    }

    private struct FindArgs: Decodable {
        let description: String?
        let place: String?
        let start: String?
        let end: String?
        let category: String?
        let favorites_only: Bool?
        let media: String?
        let limit: Int?
    }
    private struct PlacesArgs: Decodable { let query: String? }
    private struct ShowArgs: Decodable { let refs: [String]; let caption: String? }
    private struct AlbumArgs: Decodable { let title: String; let refs: [String] }

    // MARK: Helpers

    private func clamped(_ limit: Int) -> Int { min(max(limit, 1), 30) }

    private func ref(for id: String) -> String {
        if let ref = refByID[id] { return ref }
        let ref = "p\(refByID.count + 1)"
        refByID[id] = ref
        idByRef[ref] = id
        return ref
    }

    /// One compact line per photo.
    private func describe(_ ids: [String]) -> String {
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var dates: [String: Date] = [:]
        fetched.enumerateObjects { asset, _, _ in dates[asset.localIdentifier] = asset.creationDate }
        let places = (try? IndexStore.shared.placeLabels(for: ids)) ?? [:]

        return ids.map { id in
            var parts = [ref(for: id)]
            if let date = dates[id] { parts.append(Self.stamp.string(from: date)) }
            if let place = places[id] { parts.append(place) }
            if let category = categories[id] { parts.append(category.rawValue) }
            if let info = try? IndexStore.shared.info(for: id) {
                if !info.labels.isEmpty { parts.append("shows: " + info.labels.prefix(4).joined(separator: ", ")) }
                let text = info.text.replacingOccurrences(of: "\n", with: " ")
                if !text.isEmpty {
                    let snippet = text.count > snippetLength ? text.prefix(snippetLength) + "…" : Substring(text)
                    parts.append("text: “\(snippet)”")
                }
            }
            return parts.joined(separator: " · ")
        }
        .joined(separator: "\n")
    }

    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    private static var screenshotOptions: PHFetchOptions {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "(mediaSubtypes & %d) != 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
        return options
    }
}

/// Instructions shared by both backends.
nonisolated enum AssistantPrompt {
    static func instructions(today: Date = .now) -> String {
        let date = today.formatted(.iso8601.year().month().day())
        return """
            You are Phophy, the assistant inside a photo app on the user's iPhone. You help them find, \
            understand and organize their own photos.

            You cannot see images. For each photo you get its date, where it was taken, its category, \
            what it shows and the text recognized in it. Use the tools to look things up instead of \
            guessing, and say so when nothing matches.

            Use find_photos once with every detail the user gave: the place, a date range, a category, \
            and a short English description of what the photo shows or the words in it. Leave out \
            details the user didn't give: no category unless they named one, no description if they \
            only gave a place or time. Dates are a window around the moment meant: "two years ago" \
            means about six months either side of that day, "last summer" means June to August of \
            last year. If a place filter finds nothing, call list_places to see how places are named. \
            Never run more than three searches for one question; then answer with what you found.

            Whenever your answer is about particular photos, call show_photos with their refs so the \
            user sees them. Never write refs like p1 in your reply: the user can't see them. To group photos, call propose_album; the user confirms with a button, so \
            never claim an album was created.

            Answer in the user's language, in one to three short sentences. Today is \(date).
            """
    }
}

extension String {
    nonisolated var nilIfEmpty: String? { isEmpty ? nil : self }
}
