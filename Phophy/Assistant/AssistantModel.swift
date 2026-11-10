import Foundation

/// One conversation with the assistant, and which backend answers it.
@Observable
final class AssistantModel {
    enum Role { case user, assistant }

    struct Message: Identifiable {
        let id = UUID()
        let role: Role
        var text: String
        var photoIDs: [String] = []
        var albums: [AlbumProposal] = []
        var isError = false
    }

    var isPresented = false
    private(set) var messages: [Message] = []
    private(set) var isWorking = false
    private(set) var backend: AIBackend = .resolve()

    @ObservationIgnored private var toolbox: PhotoToolbox?
    @ObservationIgnored private var chat: ChatBackend?

    /// Starts a fresh conversation, picking the backend from current settings.
    func reset() {
        messages = []
        toolbox = nil
        chat = nil
        backend = .resolve()
    }

    func send(_ rawText: String, indexedCount: Int, categories: [String: PhotoCategory]) async {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isWorking else { return }
        messages.append(Message(role: .user, text: text))
        isWorking = true
        defer { isWorking = false }

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
            let reply = try await chat.send(text)
            let shown = await toolbox.present(reply: reply)
            let text = shown.text.isEmpty ? "Here they are." : shown.text
            messages.append(Message(role: .assistant, text: text, photoIDs: shown.photoIDs, albums: shown.albums))
        } catch {
            _ = await toolbox.present(reply: "")
            messages.append(Message(role: .assistant, text: error.localizedDescription, isError: true))
        }
    }
}
