import Foundation

/// The conversation with the assistant, which backend answers it, and the
/// history of earlier conversations (kept on this iPhone only).
@Observable
final class AssistantModel {
    enum Role: String, Codable { case user, assistant }

    struct Message: Identifiable, Codable {
        var id = UUID()
        let role: Role
        var text: String
        var photoIDs: [String] = []
        var albums: [AlbumProposal] = []
        var isError = false
        /// What the assistant did to answer, e.g. "Searched “waterfall” · 3 found".
        var steps: [String]? = nil
    }

    struct Conversation: Identifiable, Codable {
        var id = UUID()
        var title: String
        var updated: Date
        var messages: [Message]
    }

    /// Earlier conversations, most recent first.
    private(set) var history: [Conversation] = AssistantModel.loadHistory()
    /// Which conversation is on screen; nil until its first question.
    private(set) var conversationID: UUID?
    /// When an old conversation is continued, the model starts without its
    /// context, so a short transcript goes along with the next question.
    @ObservationIgnored private var carryOver: String?

    /// Whether the chat layer is showing over the app.
    private(set) var isPresented = false
    /// What's typed in the ask bar; it's the same field open or closed.
    var draft = ""
    private(set) var messages: [Message] = []
    private(set) var isWorking = false
    private(set) var backend: AIBackend = .resolve()

    @ObservationIgnored private var toolbox: PhotoToolbox?
    @ObservationIgnored private var chat: ChatBackend?

    func open() {
        if messages.isEmpty { backend = .resolve() }
        isPresented = true
    }

    func close() {
        isPresented = false
    }

    /// Starts a fresh conversation, picking the backend from current settings.
    func reset() {
        messages = []
        conversationID = nil
        carryOver = nil
        toolbox = nil
        chat = nil
        backend = .resolve()
    }

    /// Reopens an earlier conversation so it can be read or continued.
    func resume(_ conversation: Conversation) {
        reset()
        conversationID = conversation.id
        messages = conversation.messages
        let recent = conversation.messages.filter { !$0.isError }.suffix(6)
        if !recent.isEmpty {
            carryOver = recent
                .map { "\($0.role == .user ? "User" : "Assistant"): \($0.text.prefix(400))" }
                .joined(separator: "\n")
        }
    }

    func delete(_ conversation: Conversation) {
        history.removeAll { $0.id == conversation.id }
        if conversationID == conversation.id { reset() }
        saveHistory()
    }

    /// Stores the current conversation at the top of the history.
    private func record() {
        guard let first = messages.first(where: { $0.role == .user }) else { return }
        let id = conversationID ?? UUID()
        conversationID = id
        history.removeAll { $0.id == id }
        history.insert(Conversation(id: id, title: String(first.text.prefix(80)), updated: .now, messages: messages), at: 0)
        if history.count > 100 { history.removeLast(history.count - 100) }
        saveHistory()
    }

    private static var historyURL: URL? {
        try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("conversations.json")
    }

    private static func loadHistory() -> [Conversation] {
        guard let url = historyURL, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Conversation].self, from: data)) ?? []
    }

    private func saveHistory() {
        guard let url = Self.historyURL, let data = try? JSONEncoder().encode(history) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    func send(_ rawText: String, indexedCount: Int, categories: [String: PhotoCategory]) async {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isWorking else { return }
        messages.append(Message(role: .user, text: text))
        isWorking = true
        defer {
            isWorking = false
            record()
        }

        if messages.count == 1 { backend = .resolve() }
        let toolbox = toolbox ?? PhotoToolbox(
            snippetLength: backend == .appleIntelligence ? 60 : 160,
            categories: categories
        )
        self.toolbox = toolbox
        await toolbox.setIndexedCount(indexedCount)

        do {
            let chat: ChatBackend
            switch backend {
            case .appleIntelligence:
                chat = self.chat ?? OnDeviceAssistant(toolbox: toolbox)
            case .cloud:
                chat = try self.chat ?? CloudAssistant.make(config: .current(), toolbox: toolbox)
            case .off:
                messages.append(Message(
                    role: .assistant,
                    text: "The assistant is off. Turn on Apple Intelligence or cloud AI in Settings.",
                    isError: true
                ))
                return
            }
            self.chat = chat
            var prompt = text
            if let context = carryOver {
                prompt = "Earlier in this conversation:\n\(context)\n\nNew question: \(text)"
                carryOver = nil
            }
            let reply = try await chat.send(prompt)
            let shown = await toolbox.present(reply: reply)
            let text = shown.text.isEmpty ? "Here they are." : shown.text
            messages.append(Message(role: .assistant, text: text, photoIDs: shown.photoIDs, albums: shown.albums, steps: shown.steps))
        } catch {
            _ = await toolbox.present(reply: "")
            messages.append(Message(role: .assistant, text: error.localizedDescription, isError: true))
        }
    }
}
