import Foundation
import FoundationModels

/// Turns the text recognized on a lecture's slides into a `LectureDigest`,
/// using whichever backend Settings selects. Only text is sent, never images.
enum DigestWriter {
    struct Slide: Sendable {
        let number: Int
        let time: Date
        let text: String
    }

    static func write(slides: [Slide], backend: AIBackend) async throws -> LectureDigest {
        let readable = slides.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !readable.isEmpty else { throw DigestError.noText }

        switch backend {
        case .appleIntelligence:
            // The on-device model has a small context window.
            var digest = try await onDevice(prompt(for: readable, characterBudget: 6_000))
            digest.madeWith = "Apple Intelligence"
            return digest
        case .cloud:
            let config = try CloudConfig.current()
            let text = try await cloud(prompt(for: readable, characterBudget: 60_000), config: config)
            var digest = try parse(text)
            digest.madeWith = config.provider.title
            return digest
        case .off:
            throw DigestError.aiOff
        }
    }

    // MARK: Prompt

    private static let instructions = """
        You turn photos of lecture slides into study notes for a student who took the photos \
        and has not looked at them since. You get the text recognized on each slide; it can \
        contain recognition errors, so fix obvious ones silently and never invent content that \
        is not supported by the slides. Write in the language of the slides.

        Produce: a title of at most 8 words naming the topic; a summary of 2 to 4 sentences; \
        3 to 7 key points, each one sentence, each citing the slide numbers it comes from; and \
        4 to 10 flashcards whose questions test the key ideas and whose answers are short.
        """

    private static let jsonShape = """
        Reply with only a JSON object, no other text, in exactly this shape:
        {"title": "...", "summary": "...", "keyPoints": [{"point": "...", "slides": [1, 2]}], \
        "flashcards": [{"question": "...", "answer": "..."}]}
        """

    private static func prompt(for slides: [Slide], characterBudget: Int) -> String {
        let perSlide = max(200, min(1_500, characterBudget / max(slides.count, 1)))
        let time = Date.FormatStyle(date: .omitted, time: .shortened)
        let body = slides.map { slide in
            let text = slide.text.count > perSlide ? String(slide.text.prefix(perSlide)) + "…" : slide.text
            return "Slide \(slide.number) (\(slide.time.formatted(time))):\n\(text)"
        }
        return "Here are the slides, in the order they were photographed.\n\n" + body.joined(separator: "\n\n")
    }

    // MARK: Cloud

    private static func cloud(_ prompt: String, config: CloudConfig) async throws -> String {
        switch config.provider {
        case .anthropic:
            let response = try await postJSON(
                config.baseURL.appending(path: "messages"),
                body: [
                    "model": config.model,
                    "max_tokens": 8192,
                    "system": instructions + "\n\n" + jsonShape,
                    "output_config": ["effort": "medium"],
                    "messages": [["role": "user", "content": prompt]],
                ],
                headers: ["x-api-key": config.apiKey ?? "", "anthropic-version": "2026-10-21"]
            )
            if response["stop_reason"] as? String == "refusal" { throw AssistantError.declined }
            let blocks = response["content"] as? [[String: Any]] ?? []
            return blocks
                .filter { $0["type"] as? String == "text" }
                .compactMap { $0["text"] as? String }
                .joined()
        case .openai, .custom:
            var headers: [String: String] = [:]
            if let key = config.apiKey { headers["authorization"] = "Bearer \(key)" }
            let response = try await postJSON(
                config.baseURL.appending(path: "chat/completions"),
                body: [
                    "model": config.model,
                    "messages": [
                        ["role": "system", "content": instructions + "\n\n" + jsonShape],
                        ["role": "user", "content": prompt],
                    ],
                ],
                headers: headers
            )
            let choice = (response["choices"] as? [[String: Any]])?.first
            return (choice?["message"] as? [String: Any])?["content"] as? String ?? ""
        }
    }

    /// Reads the JSON object out of a reply, tolerating code fences or a
    /// sentence around it.
    static func parse(_ text: String) throws -> LectureDigest {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else {
            throw DigestError.unreadable
        }
        let data = Data(text[start...end].utf8)
        guard let digest = try? JSONDecoder().decode(CloudDigest.self, from: data) else {
            throw DigestError.unreadable
        }
        return LectureDigest(
            title: digest.title,
            summary: digest.summary,
            keyPoints: digest.keyPoints.map { .init(point: $0.point, slides: $0.slides ?? []) },
            flashcards: digest.flashcards.map { .init(question: $0.question, answer: $0.answer) }
        )
    }

    /// What the cloud model returns; slide numbers are optional to be lenient.
    private struct CloudDigest: Decodable {
        struct Point: Decodable { let point: String; let slides: [Int]? }
        struct Card: Decodable { let question: String; let answer: String }
        let title: String
        let summary: String
        let keyPoints: [Point]
        let flashcards: [Card]
    }

    // MARK: On device

    private static func onDevice(_ prompt: String) async throws -> LectureDigest {
        let session = LanguageModelSession(instructions: instructions)
        let generated = try await session.respond(to: prompt, generating: GeneratedDigest.self).content
        return LectureDigest(
            title: generated.title,
            summary: generated.summary,
            keyPoints: generated.keyPoints.map { .init(point: $0.point, slides: $0.slides) },
            flashcards: generated.flashcards.map { .init(question: $0.question, answer: $0.answer) }
        )
    }
}

@Generable
nonisolated struct GeneratedDigest {
    @Guide(description: "The lecture topic, at most 8 words")
    var title: String
    @Guide(description: "2 to 4 sentences summarizing the lecture")
    var summary: String
    @Guide(description: "3 to 7 key points")
    var keyPoints: [GeneratedPoint]
    @Guide(description: "4 to 10 flashcards testing the key ideas")
    var flashcards: [GeneratedCard]
}

@Generable
nonisolated struct GeneratedPoint {
    @Guide(description: "One sentence")
    var point: String
    @Guide(description: "Slide numbers this point comes from")
    var slides: [Int]
}

@Generable
nonisolated struct GeneratedCard {
    var question: String
    @Guide(description: "A short answer")
    var answer: String
}

enum DigestError: LocalizedError {
    case noText
    case aiOff
    case unreadable

    var errorDescription: String? {
        switch self {
        case .noText: "No readable text was found on these slides yet. Wait for indexing to finish, then try again."
        case .aiOff: "Notes need Apple Intelligence or cloud AI. Turn one on in Settings."
        case .unreadable: "The model's answer couldn't be read. Try again, or choose another model in Settings."
        }
    }
}
