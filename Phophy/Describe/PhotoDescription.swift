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

    /// Everything but the caption, as one line of comma-separated words.
    var keywordLine: String {
        var seen = Set<String>()
        return ([scene, activity] + objects + keywords + keywordsChinese)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            .joined(separator: ", ")
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
