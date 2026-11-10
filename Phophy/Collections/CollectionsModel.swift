import Foundation

/// The latest categories and similar-photo groups, for the UI.
@Observable
final class CollectionsModel {
    private(set) var snapshot = CollectionsSnapshot()
    private(set) var isLoading = false
    private(set) var hasLoaded = false

    func refresh() async {
        isLoading = true
        let result = await CollectionsEngine.shared.compute()
        snapshot = result
        isLoading = false
        hasLoaded = true
    }

    func ids(for category: PhotoCategory) -> [String] {
        snapshot.categories.first { $0.category == category }?.localIDs ?? []
    }

    /// Photos the similar-photo groups suggest removing.
    var removableCount: Int {
        snapshot.similarGroups.reduce(0) { $0 + $1.localIDs.count - 1 }
    }
}
