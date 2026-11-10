import Photos
import SwiftUI

/// The Collections tab: photos sorted into categories on the device, and
/// near-duplicates that could be cleaned up.
struct CollectionsView: View {
    @Environment(PhotoLibrary.self) private var library
    @Environment(IndexStatus.self) private var indexStatus
    @Environment(CollectionsModel.self) private var collections

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    content
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background { AmbientBackground() }
            .toolbar(.hidden, for: .navigationBar)
            .photoDestinations()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Sorted on your iPhone")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Collections")
                .font(.largeTitle.bold())
        }
    }

    @ViewBuilder
    private var content: some View {
        if !library.hasAccess {
            ContentUnavailableView(
                "No photo access",
                systemImage: "photo.on.rectangle",
                description: Text("Allow photo access on the Library tab to sort your photos.")
            )
        } else if !indexStatus.semanticSearchAvailable {
            ContentUnavailableView(
                "Sorting is off",
                systemImage: "square.stack",
                description: Text("Automatic collections need the MobileCLIP models, which are not installed.")
            )
        } else if !collections.hasLoaded || (indexStatus.isRunning && collections.snapshot.categories.isEmpty) {
            SortingCard(indexed: indexStatus.indexed, total: indexStatus.total)
        } else {
            if !collections.snapshot.similarGroups.isEmpty {
                NavigationLink(value: Route.similarPhotos) {
                    CleanUpCard(
                        groups: collections.snapshot.similarGroups.count,
                        removable: collections.removableCount
                    )
                }
                .buttonStyle(.plain)
            }
            if cards.isEmpty {
                ContentUnavailableView(
                    "Nothing to sort yet",
                    systemImage: "square.stack",
                    description: Text("Collections appear as Phophy recognizes slides, receipts, food, people and more.")
                )
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(cards) { card in
                        NavigationLink(value: card.route) {
                            CategoryCard(card: card)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if indexStatus.isRunning {
                IndexProgressLine()
            }
        }
    }

    private var cards: [CategoryCardModel] {
        var cards = collections.snapshot.categories.map { result in
            CategoryCardModel(
                id: result.category.rawValue,
                title: result.category.title,
                symbol: result.category.symbol,
                count: result.localIDs.count,
                coverID: result.localIDs.first,
                route: .category(result.category)
            )
        }
        // Screenshots come straight from iOS, not from the index.
        let screenshots = library.counts[.screenshots] ?? 0
        if screenshots > 0 {
            cards.append(CategoryCardModel(
                id: "screenshots",
                title: "Screenshots",
                symbol: "camera.viewfinder",
                count: screenshots,
                coverID: library.fetch(.screenshots, limit: 1).firstObject?.localIdentifier,
                route: .grid(.screenshots)
            ))
        }
        return cards
    }
}

private struct CategoryCardModel: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let count: Int
    let coverID: String?
    let route: Route
}

private struct CategoryCard: View {
    let card: CategoryCardModel
    @Environment(PhotoLibrary.self) private var library

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let coverID = card.coverID, let asset = library.asset(withLocalIdentifier: coverID) {
                    AssetThumbnail(asset: asset)
                } else {
                    Rectangle().fill(.white.opacity(0.08))
                }
            }
            .frame(height: 176)
            .clipShape(.rect(cornerRadius: 26))

            HStack(spacing: 6) {
                Image(systemName: card.symbol)
                    .font(.footnote.weight(.semibold))
                Text(card.title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(card.count, format: .number)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .glassEffect(.regular, in: .capsule)
            .padding(8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(card.title), \(card.count) photos")
    }
}

private struct CleanUpCard: View {
    let groups: Int
    let removable: Int

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "square.on.square")
                .font(.system(size: 22, weight: .medium))
                .frame(width: 52, height: 52)
                .glassEffect(.regular, in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("CLEAN UP")
                    .font(.caption.weight(.bold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                Text("Similar photos")
                    .font(.headline)
                Text("\(groups) \(groups == 1 ? "set" : "sets") · \(removable) you could remove")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .accessibilityElement(children: .combine)
    }
}

private struct SortingCard: View {
    let indexed: Int
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ProgressView()
                Text("Sorting your photos").font(.headline)
            }
            Text("Phophy is looking at each photo on your iPhone. Collections appear as it goes.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if total > 0 {
                ProgressView(value: Double(indexed), total: Double(total))
                Text("\(indexed) of \(total) photos")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }
}

// MARK: - Category grid

/// All photos in one category, with a way to keep them as a real album.
struct CategoryGridView: View {
    let category: PhotoCategory

    @Environment(PhotoLibrary.self) private var library
    @Environment(CollectionsModel.self) private var collections
    @State private var saveMessage: String?

    var body: some View {
        let ids = collections.ids(for: category)
        AssetIDGrid(localIDs: ids)
            .navigationTitle(category.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await saveAlbum(ids) }
                    } label: {
                        Label("Save as album", systemImage: "rectangle.stack.badge.plus")
                    }
                    .disabled(ids.isEmpty)
                }
            }
            .alert(saveMessage ?? "", isPresented: Binding(
                get: { saveMessage != nil },
                set: { if !$0 { saveMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            }
    }

    private func saveAlbum(_ ids: [String]) async {
        do {
            try await library.addToAlbum(named: category.title, localIDs: ids)
            let photos = ids.count == 1 ? "1 photo" : "\(ids.count) photos"
            saveMessage = "Saved \(photos) to the “\(category.title)” album in Photos."
        } catch {
            saveMessage = "Couldn't save the album. \(error.localizedDescription)"
        }
    }
}

/// A grid of specific photos, in the given order.
struct AssetIDGrid: View {
    let localIDs: [String]

    @Environment(PhotoLibrary.self) private var library
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 4)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(assets, id: \.localIdentifier) { asset in
                    NavigationLink(value: Route.photo(localIdentifier: asset.localIdentifier)) {
                        AssetThumbnail(asset: asset)
                            .aspectRatio(1, contentMode: .fit)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background { AmbientBackground() }
    }

    private var assets: [PHAsset] {
        _ = library.revision
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: localIDs, options: nil)
        var byID: [String: PHAsset] = [:]
        fetched.enumerateObjects { asset, _, _ in byID[asset.localIdentifier] = asset }
        return localIDs.compactMap { byID[$0] }
    }
}
