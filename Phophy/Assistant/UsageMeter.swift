import Foundation

/// What cloud requests used, read from each response's `usage` block, and
/// what that cost (experiment E11). Only token counts are kept: never the
/// question, the answer or anything about the photos.
nonisolated struct TokenUsage: Codable, Sendable, Equatable {
    /// Input tokens billed at the normal rate (cached ones are counted apart).
    var input = 0
    var output = 0
    var cacheRead = 0
    var cacheWrite = 0
    var requests = 0

    init() {}

    /// Reads an Anthropic Messages or OpenAI Chat Completions response.
    /// Nil when the service sent no usage.
    init?(response: [String: Any]) {
        guard let usage = response["usage"] as? [String: Any] else { return nil }
        func count(_ value: Any?) -> Int { (value as? Int) ?? 0 }
        if usage["input_tokens"] != nil {
            // Anthropic: input_tokens excludes the cached part.
            input = count(usage["input_tokens"])
            output = count(usage["output_tokens"])
            cacheRead = count(usage["cache_read_input_tokens"])
            cacheWrite = count(usage["cache_creation_input_tokens"])
        } else {
            // OpenAI and compatible: prompt_tokens includes the cached part.
            let prompt = count(usage["prompt_tokens"])
            let cached = count((usage["prompt_tokens_details"] as? [String: Any])?["cached_tokens"])
            input = max(prompt - cached, 0)
            cacheRead = cached
            output = count(usage["completion_tokens"])
        }
        requests = 1
    }

    static func + (a: TokenUsage, b: TokenUsage) -> TokenUsage {
        var sum = a
        sum.input += b.input
        sum.output += b.output
        sum.cacheRead += b.cacheRead
        sum.cacheWrite += b.cacheWrite
        sum.requests += b.requests
        return sum
    }
}

/// US dollars per million tokens. List prices from the providers' pricing
/// pages, checked 27 Nov 2026; models not listed show tokens but no cost.
nonisolated struct ModelPrice: Sendable {
    let input: Double
    let output: Double
    let cacheRead: Double
    let cacheWrite: Double

    /// Matched by prefix, longest first, so "gpt-5-mini" isn't priced as "gpt-5".
    static let table: [String: ModelPrice] = [
        // Claude Haiku 5.5: prompts up to 100K tokens (ours are far smaller).
        "claude-haiku-5-5": ModelPrice(input: 0.10, output: 0.50, cacheRead: 0.01, cacheWrite: 0.125),
        "claude-sonnet-5-5": ModelPrice(input: 2.00, output: 10.00, cacheRead: 0.10, cacheWrite: 2.50),
        "claude-opus-5-5": ModelPrice(input: 4.00, output: 20.00, cacheRead: 0.20, cacheWrite: 5.00),
        "gpt-5-mini": ModelPrice(input: 0.25, output: 2.00, cacheRead: 0.025, cacheWrite: 0.25),
        "gpt-5-nano": ModelPrice(input: 0.05, output: 0.40, cacheRead: 0.005, cacheWrite: 0.05),
    ]

    static func forModel(_ model: String) -> ModelPrice? {
        let name = model.lowercased()
        return table
            .filter { name.hasPrefix($0.key) }
            .max { $0.key.count < $1.key.count }?
            .value
    }

    func cost(of usage: TokenUsage) -> Double {
        (Double(usage.input) * input
            + Double(usage.output) * output
            + Double(usage.cacheRead) * cacheRead
            + Double(usage.cacheWrite) * cacheWrite) / 1_000_000
    }
}

/// Adds up the usage of every cloud request made while it is current, for
/// example all the rounds of one assistant answer.
actor UsageTally {
    let label: String
    let id = UUID()
    private var byModel: [String: TokenUsage] = [:]

    init(label: String) {
        self.label = label
    }

    func add(_ usage: TokenUsage, model: String) {
        byModel[model] = byModel[model, default: TokenUsage()] + usage
    }

    var usage: TokenUsage {
        byModel.values.reduce(TokenUsage(), +)
    }

    /// Nil when a model used has no known price.
    var cost: Double? {
        var total = 0.0
        for (model, usage) in byModel {
            guard let price = ModelPrice.forModel(model) else { return nil }
            total += price.cost(of: usage)
        }
        return total
    }

    /// One line for the steps under an answer, e.g.
    /// "Cloud: 3,120 tokens in, 85 out · about $0.0004". Nil when nothing was sent.
    func summaryLine() -> String? {
        let usage = usage
        guard usage.requests > 0 else { return nil }
        var line = "Cloud: \((usage.input + usage.cacheRead + usage.cacheWrite).formatted()) tokens in, \(usage.output.formatted()) out"
        if let cost { line += String(format: " · about $%.4f", cost) }
        return line
    }
}

nonisolated enum UsageMeter {
    /// The tally that cloud requests in this task add to, if any.
    @TaskLocal static var current: UsageTally?

    /// Called by `postJSON` for every successful cloud response.
    static func record(_ usage: TokenUsage, model: String) async {
        let tally = current
        await tally?.add(usage, model: model)
        #if DEBUG
        appendToLog(usage, model: model, label: tally?.label ?? "other", tallyID: tally?.id)
        #endif
    }

    #if DEBUG
    /// Debug builds keep one line per request in Documents/usage-log.jsonl,
    /// which `Eval/agent_report.py` summarises. Token counts only.
    static var logURL: URL { URL.documentsDirectory.appending(path: "usage-log.jsonl") }

    private static func appendToLog(_ usage: TokenUsage, model: String, label: String, tallyID: UUID?) {
        var entry: [String: Any] = [
            "time": ISO8601DateFormatter().string(from: .now),
            "label": label,
            "model": model,
            "input": usage.input,
            "output": usage.output,
            "cache_read": usage.cacheRead,
            "cache_write": usage.cacheWrite,
        ]
        if let tallyID { entry["tally"] = tallyID.uuidString }
        if let price = ModelPrice.forModel(model) { entry["cost_usd"] = price.cost(of: usage) }
        guard var line = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]) else { return }
        line.append(0x0A)
        let url = logURL
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: url)
        }
    }
    #endif
}
