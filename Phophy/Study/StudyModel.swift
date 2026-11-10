import Foundation
import Photos

/// Lecture sessions found among the slide photos, and their saved digests.
@Observable
final class StudyModel {
    private(set) var sessions: [LectureSession] = []
    private(set) var digests: [String: LectureDigest] = [:]
    private(set) var working: Set<String> = []
    private(set) var errors: [String: String] = [:]

    /// Regroups the slide photos into sessions and loads saved digests.
    func refresh(slideIDs: [String]) {
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: slideIDs, options: nil)
        var photos: [(id: String, date: Date)] = []
        fetched.enumerateObjects { asset, _, _ in
            photos.append((asset.localIdentifier, asset.creationDate ?? .distantPast))
        }
        sessions = LectureSession.group(photos)

        let decoder = JSONDecoder()
        let saved = (try? IndexStore.shared.allDigests()) ?? [:]
        digests = saved.compactMapValues { try? decoder.decode(LectureDigest.self, from: $0) }
    }

    func session(id: String) -> LectureSession? {
        sessions.first { $0.id == id }
    }

    /// The text recognized on each slide of a session, in order.
    func slides(of session: LectureSession) -> [DigestWriter.Slide] {
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: session.localIDs, options: nil)
        var dates: [String: Date] = [:]
        fetched.enumerateObjects { asset, _, _ in dates[asset.localIdentifier] = asset.creationDate }
        return session.localIDs.enumerated().map { index, id in
            DigestWriter.Slide(
                number: index + 1,
                time: dates[id] ?? session.start,
                text: (try? IndexStore.shared.info(for: id))?.text ?? ""
            )
        }
    }

    func makeDigest(for session: LectureSession) async {
        guard !working.contains(session.id) else { return }
        working.insert(session.id)
        errors[session.id] = nil
        defer { working.remove(session.id) }

        do {
            let digest = try await DigestWriter.write(slides: slides(of: session), backend: .resolve())
            if let data = try? JSONEncoder().encode(digest) {
                try? IndexStore.shared.saveDigest(data, for: session.id)
            }
            digests[session.id] = digest
        } catch {
            errors[session.id] = error.localizedDescription
        }
    }
}
