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
    /// How many of the last results really match what was searched; the
    /// rest are only the nearest photos, given to the model to read.
    private var lastMatchCount = 0
    /// What the last search was for, as a name for an album of its results.
    private var lastSearchTitle: String?
    /// Whether any tool has been called since the last reply.
    var calledTools: Bool { !toolLog.isEmpty }
    /// Everything this turn's searches found, best first: the model reads
    /// only the top few (its context is small), the user can see them all.
    private var allMatchIDs: [String] = []
    private var proposals: [AlbumProposal] = []
    /// Tools called since the last `takeToolLog()` or reply, in order (E7).
    private var toolLog: [String] = []

    /// How many results a search keeps for "Show more" under the reply.
    private static let moreLimit = 60

    init(snippetLength: Int, categories: [String: PhotoCategory]) {
        self.snippetLength = snippetLength
        self.categories = categories
    }

    func setIndexedCount(_ count: Int) { indexedCount = count }

    /// The tools called this turn, for the assistant evaluation. Read it
    /// before `present(reply:)`, which starts the next turn.
    func takeToolLog() -> [String] {
        defer { toolLog = [] }
        return toolLog
    }

    /// Everything the user has typed in this conversation. Small models add
    /// filters nobody asked for ("in Hong Kong", "from 2024"), which hide
    /// the photo being looked for; a filter is only kept if the user's own
    /// words mention that place or a time.
    private var asked = ""
    private var latestQuestion = ""
    func setAsked(_ text: String, latest: String) {
        asked = PlaceNames.inEnglish(text).lowercased()
        latestQuestion = latest
    }

    private func askedAboutPlace(_ place: String) -> Bool {
        guard !asked.isEmpty else { return true }
        if asked.contains(place.lowercased()) { return true }
        let names = (try? IndexStore.shared.placeNames()) ?? []
        return QueryFilters.parse(asked, places: names).place != nil
    }

    private var askedAboutTime: Bool {
        guard !asked.isEmpty else { return true }
        if QueryFilters.parse(asked, places: []).from != nil { return true }
        if asked.contains(where: \.isNumber) { return true }
        let words = ["ago", "recent", "latest", "newest", "oldest", "earliest", "first", "last", "since", "before",
                     "after", "week", "month", "year", "day", "night", "morning", "weekend", "christmas", "birthday",
                     "holiday", "when", "年", "月", "周", "天", "最近", "之前", "以前", "以后", "时候"]
        return words.contains(where: asked.contains)
    }

    /// Photos and albums to show with the reply, collected during one turn.
    /// Small models sometimes name photos in their reply ("p1, p2") instead
    /// of calling show_photos; those photos are shown too, and the refs,
    /// which mean nothing to the user, are taken out of the text.
    func present(reply: String) -> (text: String, photoIDs: [String], moreIDs: [String], albums: [AlbumProposal], steps: [String]) {
        let steps = self.steps
        let allMatches = allMatchIDs
        defer {
            shownIDs = []
            proposals = []
            lastResultIDs = []
            allMatchIDs = []
            self.steps = []
            searchesThisTurn = 0
            toolLog = []
        }
        let pattern = /\bp(\d+)\b/
        let mentioned = reply.matches(of: pattern).compactMap { idByRef["p\($0.1)"] }
        var seen = Set<String>()
        var ids = (shownIDs + mentioned).filter { seen.insert($0).inserted }
        // Last resort: the model looked photos up but showed none of them.
        // Only the ones that match: the model also gets near misses to read,
        // and those mustn't be shown as results.
        if ids.isEmpty {
            // First choice: the photos the answer was read from, told by the
            // figures in the reply ("08:15", "HK$702") that are in their text.
            let sources = Self.sources(of: reply, among: lastResultIDs)
            ids = sources.isEmpty ? Array(lastResultIDs.prefix(min(12, max(lastMatchCount, 1)))) : sources
        }
        // The shown photos first, then the rest of what the searches found.
        let shown = Set(ids)
        let more = ids.isEmpty ? [] : ids + allMatches.filter { !shown.contains($0) }
        // Small models ask "shall I make an album?" instead of offering one,
        // which leaves the user with nothing to tap. Asked for an album and
        // photos were found: offer it.
        if proposals.isEmpty, ids.count >= 2, Self.asksForAlbum(latestQuestion) {
            let quoted = reply.firstMatch(of: /[“"「]([^”"」\n]{2,40})[”"」]/).map { String($0.1) }
            proposals.append(AlbumProposal(title: quoted ?? lastSearchTitle ?? "New album", localIDs: more.isEmpty ? ids : more))
        }
        return (Self.removingRefs(from: reply), ids, more.count > ids.count ? more : [], proposals, steps)
    }

    /// The photos whose text holds a figure the reply quotes: a time, a
    /// price, a code. Years are skipped; nearly every photo's date has one.
    private static func sources(of reply: String, among ids: [String]) -> [String] {
        func plain(_ text: String) -> String { text.lowercased().filter { !",，".contains($0) } }
        let figures = Set(plain(reply).matches(of: /[a-z$]*\d[\w:.\-]*/).map { String($0.0).trimmingCharacters(in: CharacterSet(charactersIn: ".:-")) })
            .filter { $0.count >= 3 && $0.wholeMatch(of: /(19|20)\d\d/) == nil }
        guard !figures.isEmpty, let documents = try? IndexStore.shared.documents(for: ids) else { return [] }
        return ids.filter { id in
            guard let text = documents[id].map({ plain($0.ocr) }), !text.isEmpty else { return false }
            return figures.contains(where: text.contains)
        }
    }

    private static func asksForAlbum(_ question: String) -> Bool {
        let text = question.lowercased()
        return ["album", "相册", "相簿", "影集"].contains(where: text.contains)
    }

    /// Drops ref tokens and the punctuation left around them, line by line.
    private static func removingRefs(from text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { raw -> String? in
                var line = String(raw)
                // Small models invent links to photos ("[Diagram](https://…/p1)"):
                // keep the words, drop the address.
                line = line.replacing(/\[([^\]]+)\]\([^)]*\)?/) { String($0.1) }
                let withoutRefs = line.replacing(/\(?\bp\d+\b\)?\s*(—|–|-|:)?\s*/, with: "")
                let hadRef = withoutRefs != line
                line = withoutRefs.replacing(/\s+([,.;:])/) { String($0.1) }.trimmingCharacters(in: .whitespaces)
                // A list line that held only a ref ("- p1") leaves just its bullet: drop it.
                if hadRef, line.allSatisfy({ "-•*·–—".contains($0) }) { return nil }
                return line
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
        toolLog.append("find_photos")
        searchesThisTurn += 1
        var description = description?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        var place = place.map(PlaceNames.inEnglish)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        var category = category?.nilIfEmpty
        var start = start, end = end
        var dropped: [String] = []
        if let name = place, !askedAboutPlace(name) { place = nil; dropped.append("place “\(name)”") }
        if start != nil || end != nil, !askedAboutTime { start = nil; end = nil; dropped.append("dates") }
        // A guessed category hides the photo too ("whiteboard" filed under
        // documents, when it's a plain photo). With a description to rank
        // by, a category is only kept if the user's words name it.
        if let name = category, description != nil, !asked.isEmpty {
            let stem = name.lowercased().hasSuffix("s") ? String(name.lowercased().dropLast()) : name.lowercased()
            if !asked.contains(stem) { category = nil; dropped.append("category \(name)") }
        }
        // Models often repeat the place as the description; it adds nothing.
        if let d = description, let place, d.lowercased() == place.lowercased() { description = nil }
        // Small models put shop names in the place field ("Muji"). A "place"
        // no photo was taken at is searched as words instead (receipts and
        // signs carry the name in their text).
        var placeAsWords: String?
        if let name = place, ((try? IndexStore.shared.places(matching: name, limit: 1)) ?? []).isEmpty {
            description = [description, name].compactMap { $0 }.joined(separator: " ")
            placeAsWords = name
            place = nil
        }
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
        // Small models get relative dates wrong ("last week" became a week
        // a month ago). When the user's latest message names a time the app
        // can work out itself, that is the range used.
        let named = QueryFilters.parse(latestQuestion, places: (try? IndexStore.shared.placeNames()) ?? [])
        if let exactFrom = named.from, let exactTo = named.to {
            from = exactFrom
            to = exactTo
        }
        if place == nil, let namedPlace = named.place { place = namedPlace }
        // The time or place repeated as the description adds nothing to rank by.
        if let d = description {
            let rest = QueryFilters.parse(d, places: (try? IndexStore.shared.placeNames()) ?? [])
            if !rest.isEmpty { description = rest.text.nilIfEmpty }
        }

        // Filters, covering the whole library whether indexed or not.
        let hasFilters = place != nil || from != nil || to != nil || category != nil || favoritesOnly || media != nil
        var candidates: [String]?
        // Filters the user never asked for are dropped quietly: nothing to tell.
        _ = dropped
        var relaxed: [String] = []
        if hasFilters {
            candidates = filtered(from: from, to: to, place: place, media: media, category: category, favoritesOnly: favoritesOnly)
            // Models guess details the user didn't give (a category) or
            // misjudge dates ("two years ago" read as "since two years
            // ago"). Before giving up, loosen the filters a step at a time
            // and say so in the result.
            if candidates?.isEmpty == true, let guessed = category {
                // A category that matched nothing stays dropped for the retries
                // below too: small models add one the user never asked for.
                category = nil
                relaxed.append("dropped the category \(guessed)")
                candidates = filtered(from: from, to: to, place: place, media: media, category: nil, favoritesOnly: favoritesOnly)
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
        if let from { summary.append("from \(Self.day.string(from: from))") }
        if let to { summary.append("to \(Self.day.string(from: to.addingTimeInterval(-1)))") }
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
        var matchCount: Int?
        if let description {
            var ranked = await SearchEngine.shared.rank(description, among: candidates, indexedCount: indexedCount, limit: max(limit, Self.moreLimit))
            // A weak result: look closer at the best guesses that have no
            // description yet, then rank again.
            if ranked.weak || ranked.ids.count < 3 {
                let fresh = await DescriptionService.shared.describeNow(ranked.ids, limit: DescriptionService.lookCloserCount)
                if fresh > 0 {
                    ranked = await SearchEngine.shared.rank(description, among: candidates, indexedCount: indexedCount, limit: max(limit, Self.moreLimit))
                    steps.append("Looked closer at \(fresh) photos")
                }
            }
            // "My flight to Tokyo": the place may be what the photo is about,
            // not where it was taken (a boarding pass is saved at home).
            // Nothing matching there: look for it anywhere, by its words.
            if let name = place, ranked.matches.isEmpty {
                let others = from != nil || to != nil || category != nil || favoritesOnly || media != nil
                let elsewhere = others
                    ? filtered(from: from, to: to, place: nil, media: media, category: category, favoritesOnly: favoritesOnly) : nil
                let wider = await SearchEngine.shared.rank(
                    "\(description) \(name)", among: elsewhere, indexedCount: indexedCount, limit: max(limit, Self.moreLimit))
                if !wider.matches.isEmpty {
                    ranked = wider
                    candidates = elsewhere
                    placeAsWords = name
                    place = nil
                }
            }
            // The matches first, then near misses up to the limit: the
            // answer may be in a photo the search wasn't sure about.
            let matched = Set(ranked.matches)
            let matches = ranked.matches.prefix(limit)
            ids = Array(matches) + ranked.ids.filter { !matched.contains($0) }.prefix(limit - matches.count)
            matchCount = matches.count
            weak = ranked.weak || matches.isEmpty
            // "Show all" gets the photos that match, not the whole ranking.
            addMatches(ranked.matches)
        } else {
            let all = candidates ?? []
            ids = Array(all.prefix(limit))
            addMatches(Array(all.prefix(Self.moreLimit)))
        }

        var header: [String] = []
        if let placeAsWords {
            header.append("Nothing matching was taken at a place called \(placeAsWords), so it was searched as words in the photos.")
        }
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
        lastMatchCount = matchCount ?? ids.count
        lastSearchTitle = (place ?? description).map { $0.prefix(1).uppercased() + $0.dropFirst() }
        let found = lastMatchCount > 0 ? "\(lastMatchCount) found" : "no close match"
        steps.append("Searched \(label) · \(found)" + (relaxed.isEmpty ? "" : " after loosening filters"))
        if weak {
            header.append("No close match for the description; these are only the nearest and may be unrelated. Use them only if their details fit. \(budgetNote())")
        } else {
            if let matchCount, matchCount < ids.count {
                header.append("Best match first. Only the first \(matchCount) match the description; the rest are near misses, to use only if their details fit:")
            } else {
                header.append(description != nil ? "Best match first:" : "Newest first:")
            }
        }
        return header.joined(separator: " ") + "\n" + describe(ids)
    }

    /// Where photos were taken, with counts and date spans.
    func listPlaces(matching query: String?) -> String {
        toolLog.append("list_places")
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
        toolLog.append("list_collections")
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
        toolLog.append("show_photos")
        let ids = refs.compactMap { idByRef[$0] }
        guard !ids.isEmpty else { return "Error: none of those refs are known. Use refs from a search first." }
        shownIDs += ids
        return "Showing \(ids.count) photos to the user."
    }

    func proposeAlbum(title: String, refs: [String]) -> String {
        toolLog.append("propose_album")
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

    private func addMatches(_ ids: [String]) {
        let known = Set(allMatchIDs)
        allMatchIDs += ids.filter { !known.contains($0) }
    }

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
        let documents = (try? IndexStore.shared.documents(for: ids)) ?? [:]

        return ids.enumerated().map { position, id in
            var parts = [ref(for: id)]
            // The best two matches carry much more of their text, so a total
            // at the bottom of a receipt or a seat on a ticket can be read.
            let textLength = position < 2 ? max(snippetLength * 5, 300) : snippetLength
            if let date = dates[id] { parts.append(Self.stamp.string(from: date)) }
            if let place = places[id] { parts.append(place) }
            if let category = categories[id] { parts.append(category.rawValue) }
            let document = documents[id]
            if let caption = document?.caption, !caption.isEmpty { parts.append("described: “\(caption)”") }
            if let info = try? IndexStore.shared.info(for: id) {
                if let tags = document?.tags, !tags.isEmpty, document?.caption.isEmpty ?? true {
                    // Concept tags are "english / 中文" pairs; the English is enough here.
                    let english = tags.components(separatedBy: ", ").prefix(4).compactMap { $0.components(separatedBy: " / ").first }
                    parts.append("looks like: " + english.joined(separator: ", "))
                }
                if !info.labels.isEmpty { parts.append("shows: " + info.labels.prefix(4).joined(separator: ", ")) }
                // A screenshot's text starts with the status bar clock, which
                // small models then give as the answer to "what time…?".
                let text = info.text.replacingOccurrences(of: "\n", with: " ")
                    .replacing(/^\s*\d{1,2}:\d{2}\s+/, with: "")
                if !text.isEmpty {
                    let snippet = text.count > textLength ? text.prefix(textLength) + "…" : Substring(text)
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

            The recognized text lets you answer questions about what is written in photos: prices \
            and totals on receipts, times and seats on tickets, dates in letters, messages in \
            screenshots. For such a question, find the photo, then read the answer from its text. \
            Never say you can't access something before you have searched for it.

            Use find_photos once with every detail the user gave: the place, a date range, a category, \
            and a short English description of what the photo shows or the words in it. Leave out \
            details the user didn't give: no category unless they named one, no description if they \
            only gave a place or time. Dates are a window around the moment meant: "two years ago" \
            means about six months either side of that day, "last summer" means June to August of \
            last year. If a place filter finds nothing, call list_places to see how places are named. \
            Never run more than three searches for one question; then answer with what you found.

            Whenever your answer is about particular photos, call show_photos with their refs so the \
            user sees them. Never write refs like p1 in your reply: the user can't see them. When the user asks for an album, call propose_album right away with \
            the photos you found, without asking first: the user confirms with a button, so never \
            claim an album was created.

            Answer in the user's language, in one to three short sentences. Today is \(date).
            """
    }
}

extension String {
    nonisolated var nilIfEmpty: String? { isEmpty ? nil : self }
}
