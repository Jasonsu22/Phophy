import Photos
import SwiftUI

/// Find photos by describing them or by a word that appears in them.
/// Results are reusable cells, so a common word matching thousands of
/// photos scrolls smoothly.
struct SearchView: View {
    @Environment(IndexStatus.self) private var status
    @Environment(AssistantModel.self) private var assistant

    @State private var query = ""
    @State private var results = SearchResults()
    @State private var textAssets: [PHAsset] = []
    @State private var lookAlikeAssets: [PHAsset] = []
    @State private var hasSearched = false
    @State private var shownQuery = ""

    private struct SearchKey: Equatable {
        let query: String
        let indexed: Int
    }

    private struct ContentKey: Hashable {
        let query: String
        let text: [String]
        let lookAlikes: [String]
        let hasSearched: Bool
    }

    private static let edges = NSDirectionalEdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20)

    var body: some View {
        NavigationStack {
            ReusableCollection(
                sections: sections,
                contentID: ContentKey(
                    query: shownQuery, text: results.textMatches,
                    lookAlikes: results.lookAlikes, hasSearched: hasSearched
                ),
                bottomInset: assistant.isPresented ? 0 : 58
            )
            .ignoresSafeArea(.container, edges: .vertical)
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
                textAssets = Self.assets(found.textMatches)
                lookAlikeAssets = Self.assets(found.lookAlikes)
                shownQuery = query
                hasSearched = !query.trimmingCharacters(in: .whitespaces).isEmpty
            }
        }
    }

    private var sections: [ReusableSection] {
        var sections: [ReusableSection] = [
            .header(insets: NSDirectionalEdgeInsets(top: 8, leading: 20, bottom: 20, trailing: 20)) {
                IndexProgressLine().frame(maxWidth: .infinity, alignment: .leading)
            },
        ]
        let query = shownQuery
        if !hasSearched {
            sections.append(.header(insets: Self.edges) {
                ContentUnavailableView(
                    "Describe a photo",
                    systemImage: "magnifyingglass",
                    description: Text("Try “waterfall”, “pink flowers”, or a word that appears in a photo.")
                )
                .padding(.top, 60)
            })
        } else if results.isEmpty {
            sections.append(.header(insets: Self.edges) {
                ContentUnavailableView.search(text: query).padding(.top, 60)
            })
        } else {
            if !textAssets.isEmpty {
                sections += resultSections(title: "Text and labels", assets: textAssets)
            }
            if !lookAlikeAssets.isEmpty {
                sections += resultSections(title: "Looks like “\(query)”", assets: lookAlikeAssets)
            }
        }
        return sections
    }

    private func resultSections(title: String, assets: [PHAsset]) -> [ReusableSection] {
        [
            .header(insets: NSDirectionalEdgeInsets(top: 0, leading: 20, bottom: 10, trailing: 20)) {
                Text(title).font(.title3.bold()).frame(maxWidth: .infinity, alignment: .leading)
            },
            .photos(
                .assets(assets),
                layout: .grid(columns: 3, spacing: 4),
                insets: NSDirectionalEdgeInsets(top: 0, leading: 20, bottom: 24, trailing: 20),
                cornerRadius: 6
            ),
        ]
    }

    /// The matching assets, in ranked order.
    private static func assets(_ localIDs: [String]) -> [PHAsset] {
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
