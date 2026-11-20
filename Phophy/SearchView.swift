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
    @State private var bestAssets: [PHAsset] = []
    @State private var hasSearched = false
    @State private var shownQuery = ""
    @State private var lookingCloser = false

    private struct SearchKey: Equatable {
        let query: String
        let indexed: Int
    }

    private struct ContentKey: Hashable {
        let query: String
        let text: [String]
        let best: [String]
        let hasSearched: Bool
        let lookingCloser: Bool
    }

    private static let edges = NSDirectionalEdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20)

    var body: some View {
        NavigationStack {
            ReusableCollection(
                sections: sections,
                contentID: ContentKey(
                    query: shownQuery, text: results.textMatches,
                    best: results.bestMatches, hasSearched: hasSearched, lookingCloser: lookingCloser
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
                bestAssets = Self.assets(found.bestMatches)
                shownQuery = query
                hasSearched = !query.trimmingCharacters(in: .whitespaces).isEmpty
                lookingCloser = false

                // Look closer: when the match is weak or the search asks for
                // details, describe the best guesses that have no description
                // yet, then search again. Waits a moment so typing isn't slowed.
                let words = query.split(separator: " ").count
                let guesses = found.bestMatches.isEmpty ? found.closest : found.bestMatches
                guard hasSearched, found.bestMatches.isEmpty || words >= 3, !guesses.isEmpty else { return }
                try? await Task.sleep(for: .milliseconds(700))
                guard !Task.isCancelled else { return }
                lookingCloser = true
                let fresh = await DescriptionService.shared.describeNow(guesses, limit: DescriptionService.lookCloserCount)
                guard !Task.isCancelled else { return }
                lookingCloser = false
                guard fresh > 0 else { return }
                let refined = await SearchEngine.shared.search(query, indexedCount: status.indexed)
                guard !Task.isCancelled else { return }
                results = refined
                textAssets = Self.assets(refined.textMatches)
                bestAssets = Self.assets(refined.bestMatches)
            }
        }
    }

    private var sections: [ReusableSection] {
        var sections: [ReusableSection] = [
            .header(insets: NSDirectionalEdgeInsets(top: 8, leading: 20, bottom: 20, trailing: 20)) {
                IndexProgressLine().frame(maxWidth: .infinity, alignment: .leading)
            },
        ]
        if lookingCloser {
            sections.append(.header(insets: NSDirectionalEdgeInsets(top: 0, leading: 20, bottom: 12, trailing: 20)) {
                Label("Looking closer at the best guesses…", systemImage: "eye")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            })
        }
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
            if !bestAssets.isEmpty {
                sections += resultSections(title: "Best matches", assets: bestAssets)
            }
            if !textAssets.isEmpty {
                sections += resultSections(title: "Text in photos", assets: textAssets)
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
                if let pause = status.pause {
                    Text(pause.message)
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
