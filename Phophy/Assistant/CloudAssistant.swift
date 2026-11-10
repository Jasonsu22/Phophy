import Foundation

/// Anything that can answer the user, with the photo tools available.
protocol ChatBackend: AnyObject {
    func send(_ text: String) async throws -> String
}

extension OnDeviceAssistant: ChatBackend {}

/// Picks the cloud backend for the provider chosen in Settings.
enum CloudAssistant {
    static func make(config: CloudConfig, toolbox: PhotoToolbox) -> ChatBackend {
        switch config.provider {
        case .anthropic: AnthropicAssistant(config: config, toolbox: toolbox)
        case .openai, .custom: OpenAICompatibleAssistant(config: config, toolbox: toolbox)
        }
    }
}

// MARK: - Shared tool definitions

/// The photo tools in a provider-neutral form: a name, a description and a
/// JSON Schema for the arguments. Each backend wraps them in its own format.
nonisolated enum ToolSpecs {
    struct Spec {
        let name: String
        let description: String
        let schema: [String: Any]
    }

    static var all: [Spec] {
        [
            Spec(
                name: "search_photos",
                description: "Find photos by describing what they show (\"a dog on the beach\") or by words that appear in them (\"invoice\", \"gradient descent\"). Returns matching photos with refs, dates, categories, labels and recognized text, best match first.",
                schema: [
                    "type": "object",
                    "properties": [
                        "query": ["type": "string", "description": "A short English description or the words to look for."],
                        "limit": ["type": "integer", "description": "How many photos to return, 1 to 30. Default 12."],
                    ],
                    "required": ["query"],
                ]
            ),
            Spec(
                name: "photos_by_date",
                description: "List photos taken between two dates, newest first, optionally only one category.",
                schema: [
                    "type": "object",
                    "properties": [
                        "start": ["type": "string", "description": "First day, YYYY-MM-DD."],
                        "end": ["type": "string", "description": "Last day, YYYY-MM-DD, inclusive."],
                        "category": [
                            "type": "string",
                            "enum": PhotoCategory.allCases.map(\.rawValue) + ["screenshots"],
                            "description": "Only photos in this category.",
                        ],
                        "limit": ["type": "integer", "description": "How many photos to return, 1 to 30. Default 20."],
                    ],
                    "required": ["start", "end"],
                ]
            ),
            Spec(
                name: "list_collections",
                description: "Count the photos in the library and in each automatic category.",
                schema: ["type": "object", "properties": [String: Any]()]
            ),
            Spec(
                name: "show_photos",
                description: "Show photos to the user under your reply. Call this whenever your answer is about particular photos.",
                schema: [
                    "type": "object",
                    "properties": [
                        "refs": ["type": "array", "items": ["type": "string"], "description": "Photo refs such as p1, p2."],
                        "caption": ["type": "string", "description": "Optional short caption."],
                    ],
                    "required": ["refs"],
                ]
            ),
            Spec(
                name: "propose_album",
                description: "Offer to save photos as an album in Photos. The user confirms with a button; nothing is created until they tap it.",
                schema: [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string", "description": "Album name."],
                        "refs": ["type": "array", "items": ["type": "string"], "description": "Photo refs to include."],
                    ],
                    "required": ["title", "refs"],
                ]
            ),
        ]
    }
}

/// Sends a JSON request and maps HTTP failures to readable errors.
func postJSON(_ url: URL, body: [String: Any], headers: [String: String]) async throws -> [String: Any] {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 90
    request.setValue("application/json", forHTTPHeaderField: "content-type")
    for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, response) = try await URLSession.shared.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    guard status == 200 else {
        let error = json["error"] as? [String: Any]
        let message = error?["message"] as? String
        switch status {
        case 401, 403: throw AssistantError.badKey
        case 404: throw AssistantError.server(status, message ?? "Check the base URL and model name in Settings.")
        case 429, 529: throw AssistantError.busy
        default: throw AssistantError.server(status, message)
        }
    }
    return json
}

private let maxToolRounds = 8

// MARK: - Claude (Anthropic Messages API)

final class AnthropicAssistant: ChatBackend {
    private let config: CloudConfig
    private let toolbox: PhotoToolbox
    private let instructions = AssistantPrompt.instructions()
    /// The conversation exactly as the API returned it, so thinking blocks
    /// and tool calls go back unchanged on the next request.
    private var messages: [[String: Any]] = []

    init(config: CloudConfig, toolbox: PhotoToolbox) {
        self.config = config
        self.toolbox = toolbox
    }

    func send(_ text: String) async throws -> String {
        messages.append(["role": "user", "content": text])
        let tools = ToolSpecs.all.map { ["name": $0.name, "description": $0.description, "input_schema": $0.schema] }

        for _ in 0..<maxToolRounds {
            let response = try await postJSON(
                config.baseURL.appending(path: "messages"),
                body: [
                    "model": config.model,
                    "max_tokens": 4096,
                    "system": instructions,
                    "output_config": ["effort": "low"],
                    "tools": tools,
                    "messages": messages,
                ],
                headers: ["x-api-key": config.apiKey ?? "", "anthropic-version": "2026-10-21"]
            )
            let content = response["content"] as? [[String: Any]] ?? []
            messages.append(["role": "assistant", "content": content])

            switch response["stop_reason"] as? String {
            case "tool_use":
                var results: [[String: Any]] = []
                for block in content where block["type"] as? String == "tool_use" {
                    guard let id = block["id"] as? String, let name = block["name"] as? String else { continue }
                    let input = (try? JSONSerialization.data(withJSONObject: block["input"] ?? [:])) ?? Data("{}".utf8)
                    let (output, isError) = await toolbox.run(name: name, input: input)
                    var result: [String: Any] = ["type": "tool_result", "tool_use_id": id, "content": output]
                    if isError { result["is_error"] = true }
                    results.append(result)
                }
                // All results for one turn go back in a single user message.
                messages.append(["role": "user", "content": results])
            case "refusal":
                throw AssistantError.declined
            default:
                let reply = content
                    .filter { $0["type"] as? String == "text" }
                    .compactMap { $0["text"] as? String }
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return reply.isEmpty ? "Done." : reply
            }
        }
        throw AssistantError.tooManySteps
    }
}

// MARK: - OpenAI and compatible services (Chat Completions API)

final class OpenAICompatibleAssistant: ChatBackend {
    private let config: CloudConfig
    private let toolbox: PhotoToolbox
    private var messages: [[String: Any]]

    init(config: CloudConfig, toolbox: PhotoToolbox) {
        self.config = config
        self.toolbox = toolbox
        self.messages = [["role": "system", "content": AssistantPrompt.instructions()]]
    }

    func send(_ text: String) async throws -> String {
        messages.append(["role": "user", "content": text])
        let tools = ToolSpecs.all.map {
            ["type": "function", "function": ["name": $0.name, "description": $0.description, "parameters": $0.schema]]
        }
        var headers: [String: String] = [:]
        if let key = config.apiKey { headers["authorization"] = "Bearer \(key)" }

        for _ in 0..<maxToolRounds {
            let response = try await postJSON(
                config.baseURL.appending(path: "chat/completions"),
                body: ["model": config.model, "messages": messages, "tools": tools],
                headers: headers
            )
            guard let choice = (response["choices"] as? [[String: Any]])?.first,
                  let message = choice["message"] as? [String: Any]
            else { throw AssistantError.server(200, "The service sent an answer Phophy couldn't read.") }

            // Keep only the fields every compatible service accepts back.
            var assistantMessage: [String: Any] = ["role": "assistant", "content": message["content"] as? String ?? ""]
            let toolCalls = message["tool_calls"] as? [[String: Any]] ?? []
            if !toolCalls.isEmpty { assistantMessage["tool_calls"] = toolCalls }
            messages.append(assistantMessage)

            if toolCalls.isEmpty {
                if choice["finish_reason"] as? String == "content_filter" { throw AssistantError.declined }
                let reply = (message["content"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return reply.isEmpty ? "Done." : reply
            }

            for call in toolCalls {
                guard let id = call["id"] as? String,
                      let function = call["function"] as? [String: Any],
                      let name = function["name"] as? String
                else { continue }
                let arguments = function["arguments"] as? String ?? "{}"
                let (output, _) = await toolbox.run(name: name, input: Data(arguments.utf8))
                messages.append(["role": "tool", "tool_call_id": id, "content": output])
            }
        }
        throw AssistantError.tooManySteps
    }
}

// MARK: - Errors

enum AssistantError: LocalizedError {
    case noKey(CloudProvider)
    case notConfigured(String)
    case badKey
    case busy
    case declined
    case tooManySteps
    case server(Int, String?)

    var errorDescription: String? {
        switch self {
        case let .noKey(provider): "Add your \(provider.title) API key in Settings to use the cloud model."
        case let .notConfigured(message): message
        case .badKey: "The API key was rejected. Check it in Settings."
        case .busy: "The cloud service is busy right now. Try again in a moment."
        case .declined: "The model declined to answer that."
        case .tooManySteps: "That took too many steps. Try asking more specifically."
        case let .server(status, message): "The cloud service returned an error (\(status)). \(message ?? "")"
        }
    }
}
