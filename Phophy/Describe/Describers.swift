import CoreGraphics
import Foundation
import FoundationModels
import HuggingFace
import ImageIO
import MLXFoundationModels
import MLXHuggingFace
import MLXLMCommon
import MLXVLM
import Tokenizers
import UniformTypeIdentifiers

/// Writes a `PhotoDescription` for one image.
nonisolated protocol PhotoDescriber: Sendable {
    /// Stored with each description, so a better describer can redo the work of a worse one.
    var id: String { get }
    /// Long side of the image to send, in pixels. Smaller is faster and, in the cloud, cheaper.
    var imageSize: Int { get }
    func describe(_ image: CGImage, context: DescribeContext) async throws -> PhotoDescription
}

/// Which describer writes descriptions. Stored in settings.
nonisolated enum DescriberChoice: String, CaseIterable, Identifiable, Sendable {
    /// Apple's model if the iPhone has it, else the downloaded model if
    /// there is one. Never the cloud.
    case automatic
    /// Only Apple's built-in model (Apple Intelligence, iOS 27).
    case apple
    /// A small open model downloaded to the iPhone.
    case downloaded
    /// Google Gemini, with the user's key. Photos are uploaded.
    case gemini
    /// OpenAI, with the user's key. Photos are uploaded.
    case openai
    /// Descriptions are off.
    case off

    var id: Self { self }

    var title: String {
        switch self {
        case .automatic: "Automatic (on this iPhone)"
        case .apple: "Apple Intelligence"
        case .downloaded: "Downloaded model"
        case .gemini: "Google Gemini (cloud)"
        case .openai: "OpenAI (cloud)"
        case .off: "Off"
        }
    }

    var isCloud: Bool { self == .gemini || self == .openai }
}

/// Errors any describer can throw.
nonisolated enum DescriberError: LocalizedError {
    case unavailable(String)
    case badReply(String)
    case service(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let why): why
        case .badReply(let text): "The describer's reply couldn't be read: \(text.prefix(200))"
        case .service(let message): message
        }
    }
}

// MARK: - On the iPhone

/// The small open vision models the app can download for iPhones without
/// Apple Intelligence. They run with MLX on the GPU.
nonisolated enum DownloadableModel: String, CaseIterable, Identifiable, Sendable {
    /// SmolVLM2 500M (Hugging Face, Apache-2.0). About 1 GB. The default:
    /// good captions in tests, about 0.8 s a photo on an M5 Mac.
    case smolVLM
    /// FastVLM 0.5B (Apple, research licence). About 1.2 GB.
    case fastVLM

    var id: Self { self }

    var title: String {
        switch self {
        case .smolVLM: "SmolVLM2 500M"
        case .fastVLM: "FastVLM 0.5B"
        }
    }

    var configuration: ModelConfiguration {
        switch self {
        case .smolVLM: VLMRegistry.smolvlm
        case .fastVLM: VLMRegistry.fastvlm
        }
    }

    var sizeNote: String {
        switch self {
        case .smolVLM: "about 1 GB, Apache-2.0"
        case .fastVLM: "about 1.2 GB, Apple research licence"
        }
    }
}

/// Describes photos with a model on the iPhone, through Apple's
/// FoundationModels API: either Apple's built-in model, or a downloaded
/// MLX model wrapped as a `LanguageModel`. The same guided output
/// (`PhotoDescription`) comes back either way.
@available(iOS 27.0, *)
nonisolated struct OnDeviceDescriber: PhotoDescriber {
    let id: String
    let imageSize = 448
    /// Small models can't fill in a structured form well (in tests they
    /// copied the field descriptions and repeated words), so they get a plain
    /// request and their sentences become the caption. The words are what
    /// search needs; concept tags supply the Chinese.
    let plain: Bool
    private let makeSession: @Sendable () -> LanguageModelSession

    /// Apple's built-in model, if this iPhone has it and it can see images.
    static func apple() -> OnDeviceDescriber? {
        let model = SystemLanguageModel.default
        guard model.isAvailable, model.capabilities.contains(.vision) else { return nil }
        return OnDeviceDescriber(id: "apple", plain: false) {
            LanguageModelSession(model: model, instructions: PhotoDescription.instructions)
        }
    }

    /// A downloaded model. Downloads it on first use (see `download`).
    static func downloaded(_ choice: DownloadableModel) -> OnDeviceDescriber {
        let model = languageModel(choice)
        return OnDeviceDescriber(id: choice.rawValue, plain: true) {
            LanguageModelSession(model: model)
        }
    }

    static func languageModel(_ choice: DownloadableModel) -> MLXLanguageModel {
        #huggingFaceLanguageModel(configuration: choice.configuration, capabilities: [.vision])
    }

    /// The request small models get.
    static let plainRequest = "Describe this photo in two short sentences. Name the main objects, their colours, the place, and what any people or animals are doing."

    static func plainScreenRequest(_ context: DescribeContext) -> String {
        PhotoDescription.screenNote(context) + " Answer in two short sentences."
    }

    static func isDownloaded(_ choice: DownloadableModel) async -> Bool {
        await languageModel(choice).isAvailable
    }

    /// Downloads and loads the model. Progress shows in `MLXDownloadProgress.shared`.
    static func download(_ choice: DownloadableModel) async throws {
        try await languageModel(choice).preload()
    }

    func describe(_ image: CGImage, context: DescribeContext) async throws -> PhotoDescription {
        // A fresh session per photo, so earlier photos don't fill the context.
        let session = makeSession()
        if plain {
            let request = context.isScreen ? Self.plainScreenRequest(context) : Self.plainRequest
            let response = try await session.respond(
                options: GenerationOptions(sampling: .greedy, maximumResponseTokens: 80)
            ) {
                request
                Attachment(image)
            }
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw DescriberError.badReply(text) }
            return PhotoDescription(caption: text, objects: [], scene: "", activity: "", keywords: [], keywordsChinese: [])
        }
        let response = try await session.respond(
            generating: PhotoDescription.self,
            options: GenerationOptions(sampling: .greedy, maximumResponseTokens: 220)
        ) {
            context.isScreen ? "Describe this image. " + PhotoDescription.screenNote(context) : "Describe this photo."
            Attachment(image)
        }
        return response.content
    }
}

// MARK: - In the cloud

/// Describes photos with a cloud service, using the user's own key.
/// The photo (a small copy) is uploaded to that service.
nonisolated struct CloudDescriber: PhotoDescriber {
    enum Service: String, Sendable { case gemini, openai }

    let service: Service
    let model: String
    let key: String
    let imageSize = 384

    var id: String { "\(service.rawValue):\(model)" }

    static let defaultGeminiModel = "gemini-2.5-flash-lite"
    static let defaultOpenAIModel = "gpt-5-nano"

    /// The configured cloud describer, if a key is saved.
    static func configured(_ service: Service) -> CloudDescriber? {
        switch service {
        case .gemini:
            guard let key = APIKeyStore.load(account: ImageProvider.gemini.keyAccount) else { return nil }
            return CloudDescriber(service: .gemini, model: defaultGeminiModel, key: key)
        case .openai:
            guard let key = APIKeyStore.load(account: ImageProvider.openai.keyAccount)
                ?? APIKeyStore.load(for: .openai) else { return nil }
            return CloudDescriber(service: .openai, model: defaultOpenAIModel, key: key)
        }
    }

    /// Rough cost of describing `count` photos, in US dollars, from the
    /// services' list prices (November 2026). Shown before anything is sent.
    static func estimatedCost(photos count: Int, service: Service) -> Double {
        switch service {
        // 384 px image ≈ 258 tokens + ~250 prompt tokens in, ~120 out; $0.10 / $0.40 per million.
        case .gemini: Double(count) * (508 * 0.10 + 120 * 0.40) / 1_000_000
        // ~1,250 image tokens + ~250 prompt in, ~150 out; $0.05 / $0.40 per million.
        case .openai: Double(count) * (1_500 * 0.05 + 150 * 0.40) / 1_000_000
        }
    }

    func describe(_ image: CGImage, context: DescribeContext) async throws -> PhotoDescription {
        guard let jpeg = Self.jpeg(image) else { throw DescriberError.badReply("couldn't encode the photo") }
        let prompt = context.isScreen ? PhotoDescription.screenNote(context) + " " + PhotoDescription.jsonPrompt : PhotoDescription.jsonPrompt
        let text = switch service {
        case .gemini: try await gemini(jpeg, prompt: prompt)
        case .openai: try await openAI(jpeg, prompt: prompt)
        }
        guard let description = PhotoDescription.parse(text) else { throw DescriberError.badReply(text) }
        return description
    }

    private func gemini(_ jpeg: Data, prompt: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": PhotoDescription.instructions]]],
            "contents": [["parts": [
                ["inline_data": ["mime_type": "image/jpeg", "data": jpeg.base64EncodedString()]],
                ["text": prompt],
            ]]],
            "generationConfig": [
                "responseMimeType": "application/json",
                "maxOutputTokens": 400,
                "temperature": 0,
                "thinkingConfig": ["thinkingBudget": 0],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let json = try await Self.send(request)
        let candidates = json["candidates"] as? [[String: Any]]
        let parts = (candidates?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]]
        return parts?.compactMap { $0["text"] as? String }.joined() ?? ""
    }

    private func openAI(_ jpeg: Data, prompt: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": PhotoDescription.instructions],
                ["role": "user", "content": [
                    ["type": "text", "text": prompt],
                    ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64," + jpeg.base64EncodedString(), "detail": "low"]],
                ]],
            ],
            "response_format": ["type": "json_object"],
            "reasoning_effort": "minimal",
            "max_completion_tokens": 600,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let json = try await Self.send(request)
        let choices = json["choices"] as? [[String: Any]]
        return (choices?.first?["message"] as? [String: Any])?["content"] as? String ?? ""
    }

    private static func send(_ request: URLRequest) async throws -> [String: Any] {
        var request = request
        request.timeoutInterval = 60
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = ((json["error"] as? [String: Any])?["message"] as? String)
                ?? String(data: data.prefix(300), encoding: .utf8) ?? "HTTP error"
            throw DescriberError.service(message)
        }
        return json
    }

    static func jpeg(_ image: CGImage, quality: Double = 0.8) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}

// MARK: - Choosing

nonisolated enum Describers {
    /// The describer to use right now, following the user's choice, or nil
    /// with a reason when none can run.
    static func current() async -> (PhotoDescriber?, String) {
        let choice = AppSettings.describer
        switch choice {
        case .off:
            return (nil, "Descriptions are off.")
        case .gemini, .openai:
            let service: CloudDescriber.Service = choice == .gemini ? .gemini : .openai
            guard AppSettings.cloudDescriptionsConsented else { return (nil, "Cloud descriptions need your OK in Settings.") }
            guard let describer = CloudDescriber.configured(service) else { return (nil, "Add a \(service == .gemini ? "Gemini" : "OpenAI") key in Settings.") }
            return (describer, "")
        case .apple, .downloaded, .automatic:
            guard #available(iOS 27.0, *) else { return (nil, "Describing photos on the iPhone needs iOS 27.") }
            if choice != .downloaded, let apple = OnDeviceDescriber.apple() { return (apple, "") }
            if choice == .apple { return (nil, "Apple Intelligence isn't available on this iPhone.") }
            let model = AppSettings.downloadableModel
            if await OnDeviceDescriber.isDownloaded(model) { return (OnDeviceDescriber.downloaded(model), "") }
            return (nil, "Download a model in Settings to describe photos on this iPhone.")
        }
    }

    /// Down-scales `image` so its long side is at most `size` pixels.
    static func scaled(_ image: CGImage, to size: Int) -> CGImage {
        let longSide = max(image.width, image.height)
        guard longSide > size else { return image }
        let scale = Double(size) / Double(longSide)
        let width = max(1, Int(Double(image.width) * scale)), height = max(1, Int(Double(image.height) * scale))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }
}
