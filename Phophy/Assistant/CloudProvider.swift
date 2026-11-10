import Foundation

/// Which cloud service answers when the cloud backend is in use.
/// Claude uses Anthropic's Messages API; OpenAI and Custom use the
/// OpenAI-compatible Chat Completions API, which most other services
/// (DeepSeek, OpenRouter, Groq, Ollama, LM Studio, ...) also accept.
nonisolated enum CloudProvider: String, CaseIterable, Identifiable, Sendable {
    case anthropic, openai, custom

    var id: Self { self }

    var title: String {
        switch self {
        case .anthropic: "Claude"
        case .openai: "OpenAI"
        case .custom: "Custom"
        }
    }

    /// Prefilled model name; the user can change it in Settings.
    var defaultModel: String {
        switch self {
        case .anthropic: "claude-haiku-5-5"
        case .openai: "gpt-5-mini"
        case .custom: ""
        }
    }

    var modelPlaceholder: String {
        switch self {
        case .anthropic: "claude-haiku-5-5"
        case .openai: "gpt-5-mini"
        case .custom: "e.g. deepseek-chat"
        }
    }

    /// Fixed for Claude and OpenAI; entered by the user for Custom.
    var fixedBaseURL: String? {
        switch self {
        case .anthropic: "https://api.anthropic.com/v1"
        case .openai: "https://api.openai.com/v1"
        case .custom: nil
        }
    }

    /// A local server such as Ollama may not need a key.
    var requiresKey: Bool { self != .custom }

    var keyPlaceholder: String {
        switch self {
        case .anthropic: "sk-ant-…"
        case .openai: "sk-…"
        case .custom: "Key, if the service needs one"
        }
    }

    var help: String {
        switch self {
        case .anthropic:
            "Create a key at console.anthropic.com. Requests are billed to your Anthropic account."
        case .openai:
            "Create a key at platform.openai.com. Requests are billed to your OpenAI account."
        case .custom:
            "Any service that speaks the OpenAI Chat Completions API, such as DeepSeek, OpenRouter or Ollama. Enter its base URL, for example https://api.deepseek.com/v1. The model must support tool calling."
        }
    }
}

/// Everything needed to call the chosen cloud service, read from Settings.
nonisolated struct CloudConfig: Sendable {
    let provider: CloudProvider
    let model: String
    let baseURL: URL
    let apiKey: String?

    static func current() throws -> CloudConfig {
        let provider = AppSettings.cloudProvider
        let model = AppSettings.cloudModel(for: provider)
        guard !model.isEmpty else { throw AssistantError.notConfigured("Enter a model name in Settings.") }

        let base = provider.fixedBaseURL ?? AppSettings.customBaseURL
        guard let url = URL(string: base.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme, ["https", "http"].contains(scheme), url.host != nil
        else { throw AssistantError.notConfigured("Enter the service's base URL in Settings.") }

        let key = APIKeyStore.load(for: provider)
        if provider.requiresKey && key == nil { throw AssistantError.noKey(provider) }
        return CloudConfig(provider: provider, model: model, baseURL: url, apiKey: key)
    }
}
