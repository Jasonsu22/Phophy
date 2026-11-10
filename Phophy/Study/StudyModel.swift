import Foundation
import Photos

/// Lecture sessions found among the slide photos, and their saved digests.
@Observable
final class StudyModel {
    private(set) var sessions: [LectureSession] = []
    private(set) var digests: [String: LectureDigest] = [:]
    private(set) var working: Set<String> = []
    private(set) var errors: [String: String] = [:]

    /// Up to three cover photos per session, fetched in one batch per refresh
    /// so list rows never query the photo library themselves.
    private(set) var covers: [String: [PHAsset]] = [:]

    /// Per-session caches, filled the first time a lecture is opened.
    @ObservationIgnored private var assetCache: [String: [PHAsset]] = [:]
    @ObservationIgnored private var slideCache: [String: [DigestWriter.Slide]] = [:]

    /// Regroups the slide photos into sessions and loads saved digests.
    func refresh(slideIDs: [String]) {
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: slideIDs, options: nil)
        var photos: [(id: String, date: Date)] = []
        fetched.enumerateObjects { asset, _, _ in
            photos.append((asset.localIdentifier, asset.creationDate ?? .distantPast))
        }
        sessions = LectureSession.group(photos)
        assetCache = [:]
        slideCache = [:]

        var assetByID: [String: PHAsset] = [:]
        fetched.enumerateObjects { asset, _, _ in assetByID[asset.localIdentifier] = asset }
        covers = Dictionary(uniqueKeysWithValues: sessions.map { session in
            (session.id, session.localIDs.prefix(3).compactMap { assetByID[$0] })
        })

        let decoder = JSONDecoder()
        let saved = (try? IndexStore.shared.allDigests()) ?? [:]
        digests = saved.compactMapValues { try? decoder.decode(LectureDigest.self, from: $0) }
    }

    func session(id: String) -> LectureSession? {
        sessions.first { $0.id == id }
    }

    /// A session's photos in slide order, fetched once.
    func assets(of session: LectureSession) -> [PHAsset] {
        if let cached = assetCache[session.id] { return cached }
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: session.localIDs, options: nil)
        var byID: [String: PHAsset] = [:]
        fetched.enumerateObjects { asset, _, _ in byID[asset.localIdentifier] = asset }
        let assets = session.localIDs.compactMap { byID[$0] }
        assetCache[session.id] = assets
        return assets
    }

    /// The text recognized on each slide of a session, in order, read once.
    func slides(of session: LectureSession) -> [DigestWriter.Slide] {
        if let cached = slideCache[session.id] { return cached }
        var dates: [String: Date] = [:]
        for asset in assets(of: session) { dates[asset.localIdentifier] = asset.creationDate }
        let slides = session.localIDs.enumerated().map { index, id in
            DigestWriter.Slide(
                number: index + 1,
                time: dates[id] ?? session.start,
                text: (try? IndexStore.shared.info(for: id))?.text ?? ""
            )
        }
        slideCache[session.id] = slides
        return slides
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
