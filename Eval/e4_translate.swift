// Adds `q_en`, Apple's on-device translation, to every Chinese query in
// Eval/e4_queries.json (the E3 finding: translate Chinese before searching).
// Run on a Mac with the Chinese → English translation languages installed:
//   swiftc -parse-as-library Eval/e4_translate.swift -o /tmp/e4_translate && /tmp/e4_translate
import Foundation
import Translation

@main
struct E4Translate {
    static let path = "Eval/e4_queries.json"

    static func main() async throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var queries = root["queries"] as? [[String: Any]]
        else { fatalError("can't read \(path)") }
        let translator = TranslationSession(
            installedSource: Locale.Language(identifier: "zh-Hans"),
            target: Locale.Language(identifier: "en")
        )
        for i in queries.indices where queries[i]["lang"] as? String == "zh" {
            let zh = queries[i]["q"] as? String ?? ""
            let en = try await translator.translate(zh).targetText
            queries[i]["q_en"] = en
            print("\(zh) → \(en)")
        }
        root["queries"] = queries
        let out = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try out.write(to: URL(fileURLWithPath: path))
    }
}
