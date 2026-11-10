import Foundation

/// The automatic collections. Each is recognized on the device by comparing
/// a photo's MobileCLIP embedding with a few descriptions of the category.
nonisolated enum PhotoCategory: String, CaseIterable, Hashable, Identifiable, Sendable {
    case slides, documents, receipts, food, people, pets, scenery

    var id: Self { self }

    var title: String {
        switch self {
        case .slides: "Slides"
        case .documents: "Documents"
        case .receipts: "Receipts"
        case .food: "Food"
        case .people: "People"
        case .pets: "Pets"
        case .scenery: "Scenery"
        }
    }

    var symbol: String {
        switch self {
        case .slides: "rectangle.on.rectangle"
        case .documents: "doc.text"
        case .receipts: "receipt"
        case .food: "fork.knife"
        case .people: "person.2"
        case .pets: "pawprint"
        case .scenery: "mountain.2"
        }
    }

    /// Several phrasings per category; their embeddings are averaged.
    var prompts: [String] {
        switch self {
        case .slides: [
            "a photo of a presentation slide",
            "a photo of lecture slides projected on a screen",
            "a slide with a title and bullet points",
            "a photo of a whiteboard with writing",
        ]
        case .documents: [
            "a photo of a printed document",
            "a photo of handwritten notes",
            "a photo of a page of a book",
            "a scanned paper form",
        ]
        case .receipts: [
            "a photo of a shop receipt",
            "a printed receipt with prices and a total",
            "a photo of a restaurant bill",
        ]
        case .food: [
            "a photo of a meal",
            "a photo of food on a plate",
            "a photo of a drink in a cup or glass",
        ]
        case .people: [
            "a photo of a person",
            "a selfie",
            "a group photo of friends",
        ]
        case .pets: [
            "a photo of a dog",
            "a photo of a cat",
            "a photo of a pet animal",
        ]
        case .scenery: [
            "a landscape photo",
            "a photo of nature",
            "a photo of a waterfall",
            "a photo of flowers",
            "a photo of a city skyline",
            "a photo of the beach",
        ]
        }
    }

    /// Photos that compete with every category, so that an ordinary photo
    /// of an object is not forced into the closest category.
    static let otherPrompts = [
        "a photo of an object",
        "a photo of a room",
        "a blurry photo",
        "a photo of a car",
        "a screenshot of an app",
    ]

    /// Text categories also need readable text in the photo.
    var needsText: Bool {
        switch self {
        case .slides, .documents, .receipts: true
        default: false
        }
    }
}
