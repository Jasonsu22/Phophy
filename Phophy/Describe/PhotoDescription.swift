import Foundation
import FoundationModels

/// What a describer writes about one photo. Short fields, not prose: the
/// time a model takes is mostly the words it writes, and search needs
/// words to match, not sentences to read.
@Generable(description: "Facts about a photo, written so it can be found by searching")
nonisolated struct PhotoDescription: Sendable, Codable, Equatable {
    @Guide(description: "One plain sentence of at most 20 words saying what the photo shows")
    var caption: String

    @Guide(description: "Main things visible, as short nouns, most important first", .maximumCount(10))
    var objects: [String]

    @Guide(description: "Where it was taken, in two or three words, such as 'city street' or 'kitchen'")
    var scene: String

    @Guide(description: "What people or animals are doing, in a few words, or empty if nothing")
    var activity: String

    @Guide(description: "Search words a person might type to find this photo, in English", .maximumCount(10))
    var keywords: [String]

    @Guide(description: "The same search words in Simplified Chinese", .maximumCount(10))
    var keywordsChinese: [String]

    init(caption: String, objects: [String], scene: String, activity: String, keywords: [String], keywordsChinese: [String]) {
        self.caption = caption
        self.objects = objects
        self.scene = scene
        self.activity = activity
        self.keywords = keywords
        self.keywordsChinese = keywordsChinese
    }

    /// False for a reply that is mostly repeats or numbers (small models
    /// sometimes loop on a status bar). Such a reply isn't worth indexing.
    var isUsable: Bool {
        // A run of one character ("Q1000000000…") is a loop too.
        var run = 0, previous: Character?
        for c in caption { run = c == previous ? run + 1 : 1; previous = c; if run >= 10 { return false } }
        let words = caption.lowercased().split { !$0.isLetter && !$0.isNumber }
        guard words.count >= 3 else { return !caption.isEmpty }
        let distinct = Set(words).count
        let numeric = words.filter { $0.allSatisfy(\.isNumber) }.count
        return Double(distinct) / Double(words.count) >= 0.4 && Double(numeric) / Double(words.count) < 0.5
    }

    /// Everything but the caption, as one line of comma-separated words.
    var keywordLine: String {
        var seen = Set<String>()
        return ([scene, activity] + objects + keywords + keywordsChinese)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            .joined(separator: ", ")
    }

    /// For screenshots and photos of screens or documents: say what it *is*
    /// (a booking confirmation, a chat about dinner), using the text already read from it,
    /// instead of describing pixels. Small models otherwise invent "a person
    /// holding a smartphone" for every screenshot. (No examples in the
    /// request itself: SmolVLM2 copied them as answers.)
    static func screenNote(_ context: DescribeContext) -> String {
        var note = "This image is a screenshot or a picture of a screen, document or sign, not a scene. " +
            "Say what app, website or kind of document it is, and what it is about, in plain words. " +
            "Don't list numbers or copy long text. " +
            "Don't mention hands, phones or people unless they are clearly part of the picture."
        let text = context.textExcerpt
        if !text.isEmpty { note += " Text read from it: \"\(text)\"" }
        return note
    }

    /// The instructions every describer gets, on-device or in the cloud.
    static let instructions = """
        You describe photos for a photo search index. Be literal and specific: name \
        objects, colours, clothing, animals, food, signs, landmarks and activities you \
        can actually see. Never guess names of people. Keep every field short.
        """

    /// The same request as JSON, for cloud services and models without guided output.
    static let jsonPrompt = """
        Describe this photo for a search index. Reply with JSON only, no other text, \
        in exactly this shape: {"caption": "one sentence, at most 20 words", \
        "objects": ["up to 10 short nouns"], "scene": "2-3 words", \
        "activity": "a few words or empty", "keywords": ["up to 10 English search words"], \
        "keywordsChinese": ["the same search words in Simplified Chinese"]}
        """

    /// Reads the JSON reply of a describer that can't do guided output,
    /// tolerating code fences and missing fields.
    static func parse(_ text: String) -> PhotoDescription? {
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = body.firstIndex(of: "{"), let end = body.lastIndex(of: "}") {
            body = String(body[start...end])
        }
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        func string(_ key: String) -> String { (object[key] as? String) ?? "" }
        func list(_ key: String) -> [String] {
            if let array = object[key] as? [String] { return array }
            if let line = object[key] as? String { return line.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
            return []
        }
        let description = PhotoDescription(
            caption: string("caption"), objects: list("objects"), scene: string("scene"),
            activity: string("activity"), keywords: list("keywords"), keywordsChinese: list("keywordsChinese")
        )
        return description.caption.isEmpty && description.objects.isEmpty ? nil : description
    }
}

/// What's already known about a photo before it's described.
nonisolated struct DescribeContext: Sendable {
    /// A screenshot, or a photo that is mostly text (slides, receipts, documents).
    var isScreen = false
    /// Text recognized in the photo, if any.
    var text = ""

    static let none = DescribeContext()

    /// The start of the recognized text, short enough to keep the request
    /// small, without times, signal bars and bare numbers: small models
    /// copied a status bar ("14:37 5G 804") over and over instead of answering.
    var textExcerpt: String {
        let words = text.split(whereSeparator: \.isWhitespace).filter { word in
            let letters = word.filter(\.isLetter)
            return letters.count >= 2 || letters.unicodeScalars.contains(where: TextNormalizer.isCJK)
        }
        let flat = words.joined(separator: " ")
        return flat.count > 400 ? String(flat.prefix(400)) + "…" : flat
    }
}
