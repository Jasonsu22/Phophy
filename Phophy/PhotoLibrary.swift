import Photos
import SwiftUI

/// The slices of the library we can offer from PhotoKit metadata alone.
/// AI categories (slides, receipts, ...) arrive with the index in Phase 2-3.
enum PhotoFilter: String, Hashable, CaseIterable, Identifiable {
    case all, favorites, screenshots, videos

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All Photos"
        case .favorites: "Favorites"
        case .screenshots: "Screenshots"
        case .videos: "Videos"
        }
    }

    nonisolated var predicate: NSPredicate? {
        switch self {
        case .all: nil
        case .favorites: NSPredicate(format: "isFavorite == YES")
        case .screenshots: NSPredicate(format: "(mediaSubtypes & %d) != 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
        case .videos: NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
        }
    }
}

enum Route: Hashable {
    case grid(PhotoFilter)
    case category(PhotoCategory)
    case similarPhotos
    case lecture(String)
    case flashcards(String)
    case slideNotes(String)
}

extension View {
    /// Where a `Route` leads. Apply once inside each NavigationStack.
    func photoDestinations() -> some View {
        modifier(AskBarSpace()).navigationDestination(for: Route.self) { route in
            switch route {
            case let .grid(filter): PhotoGridView(filter: filter).modifier(AskBarSpace())
            case let .category(category): CategoryGridView(category: category).modifier(AskBarSpace())
            case .similarPhotos: SimilarPhotosView().modifier(AskBarSpace())
            case let .lecture(id): LectureDetailView(sessionID: id).modifier(AskBarSpace())
            case let .flashcards(id): FlashcardsView(sessionID: id).modifier(AskBarSpace())
            case let .slideNotes(id): SlideNotesView(sessionID: id).modifier(AskBarSpace())
            }
        }
    }
}

/// Single entry point to the user's photo library (which includes iCloud Photos).
@Observable
final class PhotoLibrary: NSObject, PHPhotoLibraryChangeObserver {
    static let recentsLimit = 12

    private(set) var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    /// Bumped whenever the library changes, so views know to refetch.
    private(set) var revision = 0
    private(set) var counts: [PhotoFilter: Int] = [:]
    private(set) var recents: [PHAsset] = []

    @ObservationIgnored let imageManager = PHCachingImageManager()
    @ObservationIgnored private var isObserving = false
    /// Every asset, kept to tell real changes from background noise.
    @ObservationIgnored private var everything: PHFetchResult<PHAsset>?
    @ObservationIgnored private var favorites: PHFetchResult<PHAsset>?
    @ObservationIgnored private var reloadScheduled = false

    var hasAccess: Bool { status == .authorized || status == .limited }

    /// Call once at launch. Does nothing until the user has granted access.
    func start() {
        guard hasAccess else { return }
        if !isObserving {
            PHPhotoLibrary.shared().register(self)
            // Photos doesn't reliably report an edit as a change to the
            // picture, so the editor says so itself.
            NotificationCenter.default.addObserver(
                forName: .phophyPhotoEdited, object: nil, queue: .main
            ) { [weak self] note in
                guard let ids = note.userInfo?["localIDs"] as? [String] else { return }
                MainActor.assumeIsolated { self?.markEdited(ids) }
            }
            isObserving = true
        }
        reload()
    }

    func requestAccess() async {
        status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        start()
    }

    /// Newest first by default; `oldestFirst` gives the order Photos uses in
    /// its grids, where the newest photo is at the bottom.
    func fetch(_ filter: PhotoFilter, limit: Int = 0, oldestFirst: Bool = false) -> PHFetchResult<PHAsset> {
        Self.fetch(filter, limit: limit, oldestFirst: oldestFirst)
    }

    nonisolated static func fetch(_ filter: PhotoFilter, limit: Int = 0, oldestFirst: Bool = false) -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.predicate = filter.predicate
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: oldestFirst)]
        options.fetchLimit = limit
        return PHAsset.fetchAssets(with: options)
    }

    func asset(withLocalIdentifier identifier: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject
    }

    func setFavorite(_ isFavorite: Bool, for asset: PHAsset) async {
        try? await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest(for: asset).isFavorite = isFavorite
        }
    }

    /// Moves photos to Recently Deleted. iOS asks the user to confirm first.
    /// Returns false if the user declined or the change failed.
    func delete(localIDs: [String]) async -> Bool {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: localIDs, options: nil)
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets)
            }
            return true
        } catch {
            return false
        }
    }

    /// Adds photos to the album with this title, creating it if needed.
    func addToAlbum(named title: String, localIDs: [String]) async throws {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: localIDs, options: nil)
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title == %@", title)
        let existing = PHAssetCollection
            .fetchAssetCollections(with: .album, subtype: .albumRegular, options: options)
            .firstObject
        try await PHPhotoLibrary.shared().performChanges {
            let request = existing.flatMap { PHAssetCollectionChangeRequest(for: $0) }
                ?? PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
            request.addAssets(assets)
        }
    }

    private func reload() {
        everything = PHAsset.fetchAssets(with: nil)
        favorites = fetch(.favorites)
        for filter in PhotoFilter.allCases {
            counts[filter] = fetch(filter).count
        }
        let latest = fetch(.all, limit: Self.recentsLimit)
        recents = (0..<latest.count).map { latest.object(at: $0) }
        revision += 1
    }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            self.handle(changeInstance)
        }
    }

    /// Photos reports a change whenever iCloud syncs or downloads anything,
    /// often several times a second while photos are being indexed.
    /// Only photos added, removed, edited or (un)favourited matter to the
    /// app, and a burst of changes is handled once, a second later.
    private func handle(_ change: PHChange) {
        guard let everything else {
            scheduleReload()
            return
        }
        guard let details = change.changeDetails(for: everything) else { return }
        self.everything = details.fetchResultAfterChanges
        let added = !(details.insertedIndexes?.isEmpty ?? true)
        let removed = !(details.removedIndexes?.isEmpty ?? true)
        // A photo becoming (or no longer being) a favourite enters or leaves
        // the favourites fetch.
        var favoriteChanged = false
        if let favorites, let favoriteDetails = change.changeDetails(for: favorites) {
            self.favorites = favoriteDetails.fetchResultAfterChanges
            favoriteChanged = !favoriteDetails.hasIncrementalChanges
                || !(favoriteDetails.insertedIndexes?.isEmpty ?? true)
                || !(favoriteDetails.removedIndexes?.isEmpty ?? true)
        }
        // An edit (here or in Photos) changes the picture itself.
        // Photos says so per photo, which tells an edit apart from iCloud's
        // background noise; it has to be asked about the photo as it was
        // before the change. (When photos were also added or removed, the
        // reload happens anyway.)
        var edited: [String] = []
        if !added, !removed, let changed = details.changedIndexes, changed.count <= 500 {
            let before = details.fetchResultBeforeChanges
            for index in changed where index < before.count {
                let old = before.object(at: index)
                if change.changeDetails(for: old)?.assetContentChanged == true {
                    edited.append(old.localIdentifier)
                }
            }
        }
        if !edited.isEmpty { markEdited(edited) }
        if !details.hasIncrementalChanges || added || removed || favoriteChanged || !edited.isEmpty {
            scheduleReload()
        }
    }

    /// Bumped for a photo each time its picture is edited. An edit keeps the
    /// photo's ID (and, it turns out, its modification date), so thumbnails
    /// and previews use this to know they must load the picture again.
    private(set) var editMarks: [String: Int] = [:]

    /// The key for a photo's current picture.
    func contentKey(_ asset: PHAsset) -> String {
        "\(asset.localIdentifier)#\(editMarks[asset.localIdentifier] ?? 0)"
    }

    /// A photo's picture changed: show the new one everywhere and index it
    /// again (the old text and embedding are forgotten; the indexer picks the
    /// photo up on the reload).
    func markEdited(_ localIDs: [String]) {
        for id in localIDs {
            editMarks[id, default: 0] += 1
            PhotoLoading.forget(id)
        }
        imageManager.stopCachingImagesForAllAssets()
        try? IndexStore.shared.remove(localIDs: localIDs)
        scheduleReload()
    }

    private func scheduleReload() {
        guard !reloadScheduled else { return }
        reloadScheduled = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            reloadScheduled = false
            reload()
        }
    }
}

/// Room at the bottom of every screen for the floating ask bar, so the last
/// content can scroll clear of it. None while the chat is open.
struct AskBarSpace: ViewModifier {
    @Environment(AssistantModel.self) private var assistant

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: assistant.isPresented ? 0 : 58)
        }
    }
}

extension Notification.Name {
    /// Posted with `userInfo["localIDs"]` after photos are edited or reverted.
    static let phophyPhotoEdited = Notification.Name("phophyPhotoEdited")
}
