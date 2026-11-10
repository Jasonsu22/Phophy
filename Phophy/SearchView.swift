import Photos
import SwiftUI

/// Find photos by describing them or by a word that appears in them.
struct SearchView: View {
    @Environment(IndexStatus.self) private var status

    @State private var query = ""
    @State private var results = SearchResults()
    @State private var hasSearched = false

    private struct SearchKey: Equatable {
        let query: String
        let indexed: Int
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    IndexProgressLine()
                    content
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background { AmbientBackground() }
            .navigationTitle("Search")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Describe a photo")
            .autocorrectionDisabled()
            .photoDestinations()
            .task(id: SearchKey(query: query, indexed: status.indexed)) {
                // Wait for a pause in typing before searching.
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                let found = await SearchEngine.shared.search(query, indexedCount: status.indexed)
                guard !Task.isCancelled else { return }
                results = found
                hasSearched = !query.trimmingCharacters(in: .whitespaces).isEmpty
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !hasSearched {
            ContentUnavailableView(
                "Describe a photo",
                systemImage: "magnifyingglass",
                description: Text("Try “waterfall”, “pink flowers”, or a word that appears in a photo.")
            )
            .padding(.top, 60)
        } else if results.isEmpty {
            ContentUnavailableView.search(text: query)
                .padding(.top, 60)
        } else {
            if !results.textMatches.isEmpty {
                ResultSection(title: "Text and labels", localIDs: results.textMatches)
            }
            if !results.lookAlikes.isEmpty {
                ResultSection(title: "Looks like “\(query)”", localIDs: results.lookAlikes)
            }
        }
    }
}

private struct ResultSection: View {
    let title: String
    let localIDs: [String]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.bold())
            LazyVGrid(columns: columns, spacing: 4) {
                let assets = assets
                ForEach(Array(assets.enumerated()), id: \.element.localIdentifier) { index, asset in
                    AssetThumbnail(asset: asset)
                        .aspectRatio(1, contentMode: .fit)
                        .opensInViewer(.assets(assets), at: index, id: asset.localIdentifier)
                }
            }
            .clipShape(.rect(cornerRadius: 22))
        }
    }

    /// The matching assets, in ranked order.
    private var assets: [PHAsset] {
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: localIDs, options: nil)
        var byID: [String: PHAsset] = [:]
        fetched.enumerateObjects { asset, _, _ in byID[asset.localIdentifier] = asset }
        return localIDs.compactMap { byID[$0] }
    }
}

/// One line saying how much of the library is searchable yet.
struct IndexProgressLine: View {
    @Environment(IndexStatus.self) private var status

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if status.isRunning {
                ProgressView(value: Double(status.indexed), total: Double(max(status.total, 1))) {
                    Text("Indexing \(status.indexed) of \(status.total) photos")
                }
            } else if status.total > 0 {
                Text("\(status.indexed) of \(status.total) photos indexed on this device")
            }
            if !status.semanticSearchAvailable {
                Text("Search by description is off because the MobileCLIP models are not installed. Text and label search still works.")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}
