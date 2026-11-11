import Foundation
import UIKit

/// Which AI image service does edits the on-device tools can't, such as
/// "remove the person behind me". Separate from the chat provider, because
/// Claude does not edit images.
nonisolated enum ImageProvider: String, CaseIterable, Identifiable, Sendable {
    case openai, gemini, custom

    var id: Self { self }

    var title: String {
        switch self {
        case .openai: "OpenAI"
        case .gemini: "Google Gemini"
        case .custom: "Custom"
        }
    }

    /// Prefilled, editable in Settings. Image model names change often:
    /// check the provider's model list if requests fail.
    var defaultModel: String {
        switch self {
        case .openai: "gpt-image-2"
        case .gemini: "gemini-3.1-flash-image-preview"
        case .custom: ""
        }
    }

    var fixedBaseURL: String? {
        switch self {
        case .openai: "https://api.openai.com/v1"
        case .gemini: "https://generativelanguage.googleapis.com/v1beta"
        case .custom: nil
        }
    }

    var keyAccount: String { "image.\(rawValue)" }

    var keyPlaceholder: String {
        switch self {
        case .openai: "sk-…"
        case .gemini: "AIza…"
        case .custom: "Key, if the service needs one"
        }
    }

    var help: String {
        switch self {
        case .openai:
            "Uses OpenAI's image editing API. Each edit is billed to your OpenAI account, typically a few cents. If you already saved an OpenAI key for the assistant, it is used here too."
        case .gemini:
            "Uses Google's Gemini image models. Create a key at aistudio.google.com. Each edit is billed to your Google account, typically a few cents."
        case .custom:
            "Any service that accepts OpenAI's image edit request (POST /images/edits). Enter its base URL, for example https://example.com/v1."
        }
    }

    /// The saved key; OpenAI falls back to the assistant's OpenAI key.
    var savedKey: String? {
        APIKeyStore.load(account: keyAccount)
            ?? (self == .openai ? APIKeyStore.load(for: .openai) : nil)
    }
}

nonisolated enum ImageEditError: LocalizedError {
    case notConfigured(String)
    case service(String)
    case noImage

    var errorDescription: String? {
        switch self {
        case let .notConfigured(message): message
        case let .service(message): message
        case .noImage: "The service answered without an image. Try rewording the request."
        }
    }
}

/// Sends one photo and an instruction to the chosen AI image service and
/// returns the edited photo. Only called after the user taps to confirm,
/// because each call costs money.
nonisolated struct ImageEditService: Sendable {
    let provider: ImageProvider
    let model: String
    let baseURL: URL
    let apiKey: String?

    static func current() throws -> ImageEditService {
        let provider = AppSettings.imageProvider
        let model = AppSettings.imageModel(for: provider)
        guard !model.isEmpty else {
            throw ImageEditError.notConfigured("Enter an image model name in Settings › AI photo edits.")
        }
        let base = provider.fixedBaseURL ?? AppSettings.imageBaseURL
        guard let url = URL(string: base.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme, ["https", "http"].contains(scheme), url.host != nil
        else { throw ImageEditError.notConfigured("Enter the image service's base URL in Settings › AI photo edits.") }
        let key = provider.savedKey
        if provider != .custom && key == nil {
            throw ImageEditError.notConfigured("Add a \(provider.title) key in Settings › AI photo edits.")
        }
        return ImageEditService(provider: provider, model: model, baseURL: url, apiKey: key)
    }

    func edit(_ image: UIImage, instruction: String) async throws -> UIImage {
        let prompt = """
            Edit this photo: \(instruction). Change only what is asked. Keep the people, \
            framing and everything else as they are, and keep the result photorealistic.
            """
        // About 1.5 megapixels: what these services work at, and a smaller upload.
        let upload = image.scaledToFit(longSide: 1536)
        switch provider {
        case .openai, .custom: return try await openAIEdit(upload, prompt: prompt)
        case .gemini: return try await geminiEdit(upload, prompt: prompt)
        }
    }

    // MARK: OpenAI-style: multipart POST /images/edits

    private func openAIEdit(_ image: UIImage, prompt: String) async throws -> UIImage {
        guard let png = image.pngData() else { throw ImageEditError.noImage }
        var request = URLRequest(url: baseURL.appendingPathComponent("images/edits"))
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        if let apiKey { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }

        var form = MultipartForm()
        form.addField("model", model)
        form.addField("prompt", prompt)
        form.addField("n", "1")
        if provider == .openai { form.addField("quality", "medium") }
        form.addFile("image", filename: "photo.png", mimeType: "image/png", data: png)
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = form.finish()

        let json = try await send(request)
        guard let first = (json["data"] as? [[String: Any]])?.first else { throw ImageEditError.noImage }
        if let b64 = first["b64_json"] as? String, let data = Data(base64Encoded: b64), let result = UIImage(data: data) {
            return result
        }
        if let link = first["url"] as? String, let url = URL(string: link) {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let result = UIImage(data: data) { return result }
        }
        throw ImageEditError.noImage
    }

    // MARK: Gemini: POST /models/{model}:generateContent

    private func geminiEdit(_ image: UIImage, prompt: String) async throws -> UIImage {
        guard let jpeg = image.jpegData(compressionQuality: 0.9) else { throw ImageEditError.noImage }
        var request = URLRequest(url: baseURL.appendingPathComponent("models/\(model):generateContent"))
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey { request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key") }
        let body: [String: Any] = [
            "contents": [[
                "parts": [
                    ["text": prompt],
                    ["inline_data": ["mime_type": "image/jpeg", "data": jpeg.base64EncodedString()]],
                ],
            ]],
            "generationConfig": ["responseModalities": ["TEXT", "IMAGE"]],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let json = try await send(request)
        let candidates = json["candidates"] as? [[String: Any]] ?? []
        for candidate in candidates {
            let parts = (candidate["content"] as? [String: Any])?["parts"] as? [[String: Any]] ?? []
            for part in parts {
                let inline = (part["inlineData"] ?? part["inline_data"]) as? [String: Any]
                if let b64 = inline?["data"] as? String, let data = Data(base64Encoded: b64),
                   let result = UIImage(data: data) {
                    return result
                }
            }
        }
        if let text = candidates.first.flatMap({ ($0["content"] as? [String: Any])?["parts"] as? [[String: Any]] })?
            .compactMap({ $0["text"] as? String }).joined(separator: " "), !text.isEmpty {
            throw ImageEditError.service("The service replied without an image: \(text.prefix(200))")
        }
        throw ImageEditError.noImage
    }

    // MARK: Shared

    private func send(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(status) else {
            let message = (json["error"] as? [String: Any])?["message"] as? String
                ?? String(data: data.prefix(300), encoding: .utf8) ?? ""
            switch status {
            case 401, 403: throw ImageEditError.service("\(provider.title) rejected the key (\(status)). Check it in Settings.")
            case 404: throw ImageEditError.service("\(provider.title) doesn't know the model \"\(model)\". Check the name in Settings. \(message)")
            case 429: throw ImageEditError.service("\(provider.title) is rate limiting or out of credit (429). \(message)")
            default: throw ImageEditError.service("\(provider.title) error \(status): \(message)")
            }
        }
        return json
    }
}

private nonisolated struct MultipartForm {
    private let boundary = "phophy-\(UUID().uuidString)"
    private var body = Data()

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func addField(_ name: String, _ value: String) {
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
    }

    mutating func addFile(_ name: String, filename: String, mimeType: String, data: Data) {
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\nContent-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n".utf8))
    }

    mutating func finish() -> Data {
        body.append(Data("--\(boundary)--\r\n".utf8))
        return body
    }
}

extension UIImage {
    /// A copy no larger than `longSide` pixels on its long side, upright.
    nonisolated func scaledToFit(longSide: CGFloat) -> UIImage {
        let pixels = CGSize(width: size.width * scale, height: size.height * scale)
        let factor = min(1, longSide / max(pixels.width, pixels.height))
        let target = CGSize(width: (pixels.width * factor).rounded(), height: (pixels.height * factor).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
