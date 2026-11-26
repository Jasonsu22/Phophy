// Adds machine English to Eval/e3_queries.json for experiment E3, using the
// same Apple on-device models the iPhone has, run here on the Mac:
//
//   apple_translation  Apple's Translation framework, Chinese → English
//                      (condition c: translate on the device before encoding)
//   apple_rewrite      Apple's on-device language model, asked for the short
//                      English description the assistant gives find_photos
//                      (condition b: the assistant rewrites the query)
//
// Needs macOS 26 with Apple Intelligence on and the Chinese → English
// translation languages installed. Build and run from the project folder:
//   swiftc -parse-as-library Eval/e3_translate.swift -o /tmp/e3_translate && /tmp/e3_translate
import Foundation
import FoundationModels
import Translation

@main
struct E3Translate {
    static let path = "Eval/e3_queries.json"

    static func main() async throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var sets = root["sets"] as? [[String: Any]]
        else { fatalError("can't read \(path)") }

        let translator = TranslationSession(
            installedSource: Locale.Language(identifier: "zh-Hans"),
            target: Locale.Language(identifier: "en")
        )
        // Rewriting the user's own words is a content transformation: use the
        // guardrails Apple provides for that, as the app would.
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        // The same instruction the assistant gets for find_photos' description.
        let instructions = """
            You turn a photo search typed by the user into what a photo search tool needs: \
            a short English description of what the photo shows or the words in it. \
            Keep every detail the user gave and add nothing. Reply with the description only.
            """

        for s in sets.indices {
            var queries = sets[s]["queries"] as? [[String: Any]] ?? []
            for q in queries.indices {
                let zh = queries[q]["zh"] as? String ?? ""
                let translated = try await translator.translate(zh).targetText
                queries[q]["apple_translation"] = translated.trimmingCharacters(in: .whitespacesAndNewlines)
                // A fresh session per query, so earlier queries don't leak in.
                let session = LanguageModelSession(model: model, instructions: instructions)
                do {
                    let rewrite = try await session.respond(to: "The user searched: \(zh)").content
                    queries[q]["apple_rewrite"] = rewrite
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”."))
                } catch {
                    // Counted as a failed rewrite: the search gets the raw Chinese.
                    queries[q]["apple_rewrite_error"] = "\(error)"
                }
                print("\(zh) → \(translated) | \(queries[q]["apple_rewrite"] ?? "ERROR")")
                fflush(stdout)
            }
            sets[s]["queries"] = queries
        }
        root["sets"] = sets
        root["machine_english"] = "Apple Translation (zh-Hans → en) and Apple Foundation Models, macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
        let out = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try out.write(to: URL(fileURLWithPath: path))
    }
}
