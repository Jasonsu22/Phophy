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

    var predicate: NSPredicate? {
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
    case photo(localIdentifier: String)
    case category(PhotoCategory)
    case similarPhotos
}

extension View {
    /// Where a `Route` leads. Apply once inside each NavigationStack.
    func photoDestinations() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case let .grid(filter): PhotoGridView(filter: filter)
            case let .photo(localIdentifier): PhotoDetailView(localIdentifier: localIdentifier)
            case let .category(category): CategoryGridView(category: category)
            case .similarPhotos: SimilarPhotosView()
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

    var hasAccess: Bool { status == .authorized || status == .limited }

    /// Call once at launch. Does nothing until the user has granted access.
    func start() {
        guard hasAccess else { return }
        if !isObserving {
            PHPhotoLibrary.shared().register(self)
            isObserving = true
        }
        reload()
    }

    func requestAccess() async {
        status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        start()
    }

    func fetch(_ filter: PhotoFilter, limit: Int = 0) -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.predicate = filter.predicate
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
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
        for filter in PhotoFilter.allCases {
            counts[filter] = fetch(filter).count
        }
        let latest = fetch(.all, limit: Self.recentsLimit)
        recents = (0..<latest.count).map { latest.object(at: $0) }
        revision += 1
    }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            self.reload()
        }
    }
}
