import Foundation
import FoundationModels

/// The Apple Intelligence backend: Apple's on-device model with the same
/// photo tools. Free, private and offline, but with a small context window,
/// so long conversations are restarted automatically.
final class OnDeviceAssistant {
    private let toolbox: PhotoToolbox
    private var session: LanguageModelSession

    init(toolbox: PhotoToolbox) {
        self.toolbox = toolbox
        self.session = Self.makeSession(toolbox: toolbox)
    }

    func send(_ text: String) async throws -> String {
        do {
            return try await session.respond(to: text).content
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            // Start over with a fresh session and try once more.
            session = Self.makeSession(toolbox: toolbox)
            return try await session.respond(to: text).content
        }
    }

    private static func makeSession(toolbox: PhotoToolbox) -> LanguageModelSession {
        LanguageModelSession(
            tools: [
                FindPhotosTool(toolbox: toolbox),
                ListPlacesTool(toolbox: toolbox),
                ListCollectionsTool(toolbox: toolbox),
                ShowPhotosTool(toolbox: toolbox),
                ProposeAlbumTool(toolbox: toolbox),
            ],
            instructions: AssistantPrompt.instructions()
        )
    }
}

nonisolated struct FindPhotosTool: Tool {
    let toolbox: PhotoToolbox
    let name = "find_photos"
    let description = "Find photos by place, dates, category and a description of what they show, all in one call."

    @Generable
    struct Arguments {
        @Guide(description: "Short English description of what the photo shows or words in it; empty if none given")
        var description: String?
        @Guide(description: "Place, city or country where it was taken, e.g. Hong Kong")
        var place: String?
        @Guide(description: "First day, YYYY-MM-DD")
        var start: String?
        @Guide(description: "Last day, YYYY-MM-DD, inclusive")
        var end: String?
        @Guide(description: "Optional category: slides, documents, receipts, food, people, pets, scenery or screenshots")
        var category: String?
    }

    func call(arguments: Arguments) async throws -> String {
        await toolbox.find(
            description: arguments.description, place: arguments.place, start: arguments.start,
            end: arguments.end, category: arguments.category, favoritesOnly: false, media: nil, limit: 8
        )
    }
}

nonisolated struct ListPlacesTool: Tool {
    let toolbox: PhotoToolbox
    let name = "list_places"
    let description = "List places where photos were taken, with counts."

    @Generable
    struct Arguments {
        @Guide(description: "Optional part of a place name")
        var query: String?
    }

    func call(arguments: Arguments) async throws -> String {
        await toolbox.listPlaces(matching: arguments.query)
    }
}

nonisolated struct ListCollectionsTool: Tool {
    let toolbox: PhotoToolbox
    let name = "list_collections"
    let description = "Count the photos in the library and in each automatic category."

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        await toolbox.listCollections()
    }
}

nonisolated struct ShowPhotosTool: Tool {
    let toolbox: PhotoToolbox
    let name = "show_photos"
    let description = "Show photos to the user under your reply. Use it whenever your answer is about particular photos."

    @Generable
    struct Arguments {
        @Guide(description: "Photo refs such as p1, p2")
        var refs: [String]
    }

    func call(arguments: Arguments) async throws -> String {
        await toolbox.show(refs: arguments.refs, caption: nil)
    }
}

nonisolated struct ProposeAlbumTool: Tool {
    let toolbox: PhotoToolbox
    let name = "propose_album"
    let description = "Offer to save photos as an album. The user confirms with a button."

    @Generable
    struct Arguments {
        @Guide(description: "Album name")
        var title: String
        @Guide(description: "Photo refs to include")
        var refs: [String]
    }

    func call(arguments: Arguments) async throws -> String {
        await toolbox.proposeAlbum(title: arguments.title, refs: arguments.refs)
    }
}
