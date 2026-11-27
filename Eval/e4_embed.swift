// Computes the text-vector rankings for experiment E4 on a Mac, for when the
// device running the evaluation can't load Apple's contextual embeddings
// (the iOS simulator: "Embedding model requires compilation").
//
// Same method as `embedHere()` in Phophy/Debug/OCRTextEvaluation.swift:
// NLContextualEmbedding, mean of the token vectors, normalised;
// Latin-script text in the English model, mostly-Chinese text in the
// Chinese model. Reads the photos' text exported by the app (e4-ocr.json)
// and Eval/e4_queries.json; writes e4_vectors.json for the app to read back.
//
//   swiftc -parse-as-library Eval/e4_embed.swift -o /tmp/e4_embed
//   /tmp/e4_embed path/to/e4-ocr.json path/to/e4_vectors.json
import Foundation
import NaturalLanguage

func isCJK(_ s: Unicode.Scalar) -> Bool {
    switch s.value {
    case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0xAC00...0xD7AF: true
    default: false
    }
}

func isMostlyChinese(_ text: String) -> Bool {
    Double(text.unicodeScalars.filter(isCJK).count) / Double(max(text.count, 1)) > 0.2
}

final class Space {
    let model: NLContextualEmbedding
    var files: [String] = []
    var vectors: [[Float]] = []
    init(_ model: NLContextualEmbedding) { self.model = model }

    func embed(_ raw: String) -> [Float]? {
        let text = String(raw.prefix(1000))
        guard let result = try? model.embeddingResult(for: text, language: nil) else { return nil }
        var sum = [Double](repeating: 0, count: model.dimension)
        var count = 0.0
        result.enumerateTokenVectors(in: text.startIndex..<text.endIndex) { v, _ in
            for i in v.indices { sum[i] += v[i] }
            count += 1
            return true
        }
        let norm = sum.reduce(0) { $0 + $1 * $1 }.squareRoot()
        guard count > 0, norm > 0 else { return nil }
        return sum.map { Float($0 / norm) }
    }

    func ranked(_ query: String, limit: Int = 100) -> [String] {
        guard let q = embed(query) else { return [] }
        return vectors.indices
            .map { (files[$0], zip(q, vectors[$0]).reduce(Float(0)) { $0 + $1.0 * $1.1 }) }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }
}

@main
struct E4Embed {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count == 3 else { print("usage: e4_embed e4-ocr.json e4_vectors.json"); return }
        let rows = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[1]))) as? [[String: String]] ?? []
        let queryFile = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: "Eval/e4_queries.json"))) as? [String: Any] ?? [:]
        let queries = queryFile["queries"] as? [[String: Any]] ?? []

        guard let latin = NLContextualEmbedding(language: .english),
              let chinese = NLContextualEmbedding(language: .simplifiedChinese)
        else { fatalError("no contextual embeddings") }
        for e in [latin, chinese] where !e.hasAvailableAssets { _ = try await e.requestAssets() }
        try latin.load()
        try chinese.load()
        let english = Space(latin), han = Space(chinese)
        for row in rows {
            guard let file = row["file"], let text = row["text"] else { continue }
            let space = isMostlyChinese(text) ? han : english
            if let v = space.embed(text) { space.files.append(file); space.vectors.append(v) }
        }
        print("embedded \(english.files.count) Latin-script and \(han.files.count) Chinese texts")

        var out: [String: [String: [String]]] = [:]
        for q in queries {
            guard let text = q["q"] as? String, let lang = q["lang"] as? String else { continue }
            let englishQuery = lang == "zh" ? (q["q_en"] as? String ?? text) : text
            out[text] = ["en": english.ranked(englishQuery), "zh": lang == "zh" ? han.ranked(text) : []]
        }
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let result: [String: Any] = [
            "source": "NLContextualEmbedding \(latin.modelIdentifier) / \(chinese.modelIdentifier), mean pooled, on macOS \(os)",
            "queries": out,
        ]
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            .write(to: URL(fileURLWithPath: args[2]))
        print("wrote \(out.count) queries to \(args[2])")
    }
}
