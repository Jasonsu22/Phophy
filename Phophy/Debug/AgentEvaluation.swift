#if DEBUG
import Foundation
import Photos

/// Experiment E7 and E11: can the assistant finish real tasks, with how many
/// tool calls, how fast, and at what cost? See `Eval/AGENT_EVAL.md`.
///
/// Launch with `-PhophyAgentEval` and put `agent_tasks.json` in the app's
/// Documents folder. The runner waits for indexing, asks every task in a
/// fresh conversation on the backend chosen in Settings (pick it at launch
/// with `-useAppleIntelligence NO -cloudProvider openai`), prints lines
/// starting with `AGENT` and writes `agent-results-<backend>.json`.
enum AgentEvaluation {
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-PhophyAgentEval") }

    struct TaskSpec: Decodable {
        var id: String
        var ask: String
        var lang: String
        var kind: String
        /// The reply must contain one of these (case and commas ignored).
        var answerAny: [String]?
        /// The shown photos must include one of these file names;
        /// "slide_*" matches by prefix.
        var showsAny: [String]?
        /// The assistant must offer to save an album.
        var album: Bool?
        /// At least this many photos must be shown.
        var minShown: Int?
    }

    struct TaskResult: Encodable {
        var id: String
        var lang: String
        var kind: String
        var ok: Bool
        var failed: [String]
        var reply: String
        var shown: [String]
        var albums: Int
        var tools: [String]
        var seconds: Double
        var usage: TokenUsage
        var costUSD: Double?
        var error: String?
    }

    struct Report: Encodable {
        var backend: String
        var date: Date
        var photos: Int
        var tasks: Int
        var succeeded: Int
        var successRate: Double
        var meanToolCalls: Double
        var meanSeconds: Double
        var totalCostUSD: Double?
        var costPerTaskUSD: Double?
        var results: [TaskResult]
    }

    static func runWhenIndexed() async {
        let documents = URL.documentsDirectory
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let data = try? Data(contentsOf: documents.appending(path: "agent_tasks.json")),
              let tasks = try? decoder.decode([TaskSpec].self, from: data)
        else { log("no readable agent_tasks.json in \(documents.path)"); return }

        let photoCount = PHAsset.fetchAssets(with: .image, options: nil).count
        while true {
            let indexed = (try? IndexStore.shared.allIDs().count) ?? 0
            if indexed >= photoCount, await SearchEvaluation.extraWorkDone() { break }
            log("waiting for indexing: \(indexed) of \(photoCount)")
            try? await Task.sleep(for: .seconds(5))
        }
        var categories: [String: PhotoCategory] = [:]
        for result in await CollectionsEngine.shared.compute().categories {
            for id in result.localIDs { categories[id] = result.category }
        }

        let backend = AIBackend.resolve()
        let label = backendLabel(backend)
        guard backend != .off else { log("the assistant is off: turn on Apple Intelligence or cloud AI"); log("done"); return }
        log("\(tasks.count) tasks on \(label), \(photoCount) photos")

        var results: [TaskResult] = []
        for task in tasks {
            let result = await run(task, backend: backend, indexedCount: photoCount, categories: categories)
            results.append(result)
            let cost = result.costUSD.map { String(format: "$%.5f", $0) } ?? "no price"
            log("\(result.ok ? "PASS" : "FAIL") \(task.id) [\(task.lang)/\(task.kind)] \(String(format: "%.1f", result.seconds)) s, \(result.tools.count) tools, \(cost)\(result.failed.isEmpty ? "" : " · " + result.failed.joined(separator: "; "))")
        }

        let n = Double(max(results.count, 1))
        let succeeded = results.filter(\.ok).count
        let costs = results.compactMap(\.costUSD)
        let total: Double? = costs.count == results.count && backend == .cloud ? costs.reduce(0, +) : nil
        let report = Report(
            backend: label, date: .now, photos: photoCount, tasks: results.count, succeeded: succeeded,
            successRate: Double(succeeded) / n,
            meanToolCalls: Double(results.map(\.tools.count).reduce(0, +)) / n,
            meanSeconds: results.map(\.seconds).reduce(0, +) / n,
            totalCostUSD: total, costPerTaskUSD: total.map { $0 / n },
            results: results
        )
        log(String(format: "summary %@: %d/%d succeeded (%.0f%%), %.1f tool calls, %.1f s per task%@",
                   label, succeeded, results.count, report.successRate * 100, report.meanToolCalls, report.meanSeconds,
                   total.map { String(format: ", $%.5f per task", $0 / n) } ?? ""))

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        let file = "agent-results-\(label.replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: "/", with: "-")).json"
        try? encoder.encode(report).write(to: documents.appending(path: file))
        log("wrote \(file)")
        log("done")
    }

    /// One task in a fresh conversation, as a user would ask it.
    private static func run(_ task: TaskSpec, backend: AIBackend, indexedCount: Int, categories: [String: PhotoCategory]) async -> TaskResult {
        let toolbox = PhotoToolbox(snippetLength: backend == .appleIntelligence ? 60 : 160, categories: categories)
        await toolbox.setIndexedCount(indexedCount)
        let tally = UsageTally(label: "agent-eval:\(task.id)")
        let started = ContinuousClock.now
        var reply = ""
        var errorText: String?
        do {
            let chat: ChatBackend
            if backend == .appleIntelligence {
                chat = OnDeviceAssistant(toolbox: toolbox)
            } else {
                chat = CloudAssistant.make(config: try .current(), toolbox: toolbox)
            }
            reply = try await UsageMeter.$current.withValue(tally) {
                try await chat.send(task.ask)
            }
        } catch {
            errorText = error.localizedDescription
        }
        let elapsed = ContinuousClock.now - started
        let tools = await toolbox.takeToolLog()
        let shown = await toolbox.present(reply: reply)
        let names = fileNames(for: shown.photoIDs)

        var failed: [String] = []
        if let errorText { failed.append("error: \(errorText)") }
        if let expected = task.answerAny {
            let text = normalized(shown.text)
            if !expected.contains(where: { text.contains(normalized($0)) }) {
                failed.append("answer lacks \(expected.joined(separator: " / "))")
            }
        }
        if let expected = task.showsAny {
            let hit = names.contains { name in
                expected.contains { pattern in
                    let pattern = pattern.lowercased()
                    return pattern.hasSuffix("*") ? name.hasPrefix(String(pattern.dropLast())) : name == pattern
                }
            }
            if !hit { failed.append("didn't show \(expected.joined(separator: " / "))") }
        }
        if task.album == true, shown.albums.isEmpty { failed.append("no album offered") }
        if let minimum = task.minShown, names.count < minimum { failed.append("showed \(names.count) < \(minimum) photos") }

        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        let usage = await tally.usage
        // On the phone it's free; in the cloud, nil means the model has no price.
        var cost: Double? = 0
        if backend == .cloud { cost = await tally.cost }
        return TaskResult(
            id: task.id, lang: task.lang, kind: task.kind, ok: failed.isEmpty, failed: failed,
            reply: String(shown.text.prefix(400)), shown: names, albums: shown.albums.count, tools: tools,
            seconds: seconds, usage: usage, costUSD: cost, error: errorText
        )
    }

    private static func backendLabel(_ backend: AIBackend) -> String {
        switch backend {
        case .appleIntelligence: "apple-intelligence"
        case .cloud:
            "\(AppSettings.cloudProvider.rawValue):\(AppSettings.cloudModel(for: AppSettings.cloudProvider))"
        case .off: "off"
        }
    }

    /// Lowercased, without commas, spaces or currency signs, so "HK$702.00"
    /// contains "702" and "14,500" matches "14500".
    private static func normalized(_ text: String) -> String {
        text.lowercased().filter { !",， $".contains($0) }
    }

    /// Original file names (lowercased) of shown photos, in order.
    private static func fileNames(for ids: [String]) -> [String] {
        var byID: [String: String] = [:]
        PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).enumerateObjects { asset, _, _ in
            byID[asset.localIdentifier] = PHAssetResource.assetResources(for: asset).first?.originalFilename.lowercased()
        }
        return ids.compactMap { byID[$0] }
    }

    static func log(_ message: String) {
        fputs("AGENT \(message)\n", stderr)
    }
}
#endif
