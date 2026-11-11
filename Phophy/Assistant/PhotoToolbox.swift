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

    func search(query: String, limit: Int) async -> String {
        searchesThisTurn += 1
        let results = await SearchEngine.shared.search(query, indexedCount: indexedCount)
        let ids = Array((results.textMatches + results.lookAlikes).prefix(clamped(limit)))
        if !ids.isEmpty {
            lastResultIDs = ids
            steps.append("Searched “\(query)” · \(ids.count) found")
            return "\(ids.count) photos, best match first:\n" + describe(ids)
        }
        steps.append("Searched “\(query)” · no close match")
        let budget = searchesThisTurn >= 3
            ? "You have searched \(searchesThisTurn) times for this question. Stop searching and answer with what you have."
            : "Try at most one clearly different wording; do not repeat near-identical searches."
        guard !results.closest.isEmpty else {
            return "No photos match “\(query)”, and nothing in the index is close. \(budget)"
        }
        return """
            No close match for “\(query)”. The nearest photos, which may be unrelated:
            \(describe(results.closest))
            Use them only if their labels or text fit the question. \(budget)
            """
    }

    func photosByDate(start: String, end: String, category: String?, limit: Int) -> String {
        guard let from = Self.day.date(from: start), let toDay = Self.day.date(from: end) else {
            return "Error: dates must look like 2026-11-10."
        }
        let to = Calendar.current.date(byAdding: .day, value: 1, to: toDay) ?? toDay

        let options = PHFetchOptions()
        var predicates = [NSPredicate(format: "creationDate >= %@ AND creationDate < %@", from as NSDate, to as NSDate)]
        if category == "screenshots" {
            predicates.append(NSPredicate(format: "(mediaSubtypes & %d) != 0", PHAssetMediaSubtype.photoScreenshot.rawValue))
        }
        options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let fetched = PHAsset.fetchAssets(with: .image, options: options)

        var ids: [String] = []
        fetched.enumerateObjects { asset, _, stop in
            let id = asset.localIdentifier
            if let category, category != "screenshots", self.categories[id]?.rawValue != category { return }
            ids.append(id)
            if ids.count >= self.clamped(limit) { stop.pointee = true }
        }
        lastResultIDs = ids
        steps.append("Looked at \(start) to \(end) · \(ids.count) found")
        guard !ids.isEmpty else { return "No photos between \(start) and \(end)." }
        let total = category == nil ? " (of \(fetched.count) in that period)" : ""
        return "\(ids.count) photos, newest first\(total):\n" + describe(ids)
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
            case "search_photos":
                let args = try decoder.decode(SearchArgs.self, from: input)
                return (await search(query: args.query, limit: args.limit ?? 12), false)
            case "photos_by_date":
                let args = try decoder.decode(DateArgs.self, from: input)
                return (photosByDate(start: args.start, end: args.end, category: args.category, limit: args.limit ?? 20), false)
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

    private struct SearchArgs: Decodable { let query: String; let limit: Int? }
    private struct DateArgs: Decodable { let start: String; let end: String; let category: String?; let limit: Int? }
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

        return ids.map { id in
            var parts = [ref(for: id)]
            if let date = dates[id] { parts.append(Self.stamp.string(from: date)) }
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

            You cannot see images. For each photo you get its date, its category, what it shows and \
            the text recognized in it. Use the tools to look things up instead of guessing, and say so \
            when nothing matches.

            Search efficiently: usually one search is enough. If it finds nothing, try at most one \
            clearly different wording or a date range, then answer with what you found. Never run \
            more than three searches for one question.

            Whenever your answer is about particular photos, call show_photos with their refs so the \
            user sees them. Never write refs like p1 in your reply: the user can't see them. To group photos, call propose_album; the user confirms with a button, so \
            never claim an album was created.

            Answer in the user's language, in one to three short sentences. Today is \(date).
            """
    }
}
