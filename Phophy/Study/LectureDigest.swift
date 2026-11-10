import Foundation

/// Slide photos taken close together: one lecture.
nonisolated struct LectureSession: Identifiable, Hashable, Sendable {
    /// Oldest first.
    let localIDs: [String]
    let start: Date
    let end: Date

    /// Stable while the same photos make up the session.
    var id: String { "\(localIDs.first ?? "")|\(localIDs.last ?? "")|\(localIDs.count)" }

    /// Slide photos at most this far apart belong to the same lecture.
    static let maximumGap: TimeInterval = 30 * 60

    /// Groups photos (with their dates) into sessions, newest session first.
    static func group(_ photos: [(id: String, date: Date)]) -> [LectureSession] {
        let sorted = photos.sorted { $0.date < $1.date }
        var sessions: [LectureSession] = []
        var current: [(id: String, date: Date)] = []
        func close() {
            guard let first = current.first, let last = current.last else { return }
            sessions.append(LectureSession(localIDs: current.map(\.id), start: first.date, end: last.date))
            current = []
        }
        for photo in sorted {
            if let last = current.last, photo.date.timeIntervalSince(last.date) > maximumGap { close() }
            current.append(photo)
        }
        close()
        return sessions.reversed()
    }
}

/// Study notes made from one lecture's slides.
nonisolated struct LectureDigest: Codable, Sendable, Equatable {
    struct KeyPoint: Codable, Sendable, Equatable, Hashable {
        let point: String
        /// 1-based slide numbers the point comes from.
        let slides: [Int]

        /// The point without a trailing "(Slide 2)" or "(Slides 3, 4)"; the
        /// slide numbers are shown separately.
        var displayText: String {
            point.replacing(/\s*\((?:see )?slides?\s*[\d,\s&and–-]+\)\s*(?=[.!?]?$)/.ignoresCase(), with: "")
        }
    }

    struct Flashcard: Codable, Sendable, Equatable, Hashable {
        let question: String
        let answer: String
    }

    let title: String
    let summary: String
    let keyPoints: [KeyPoint]
    let flashcards: [Flashcard]
    /// Which model wrote it, e.g. "Apple Intelligence" or "Claude".
    var madeWith: String = ""
    var createdAt: Date = .now
}
