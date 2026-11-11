import Photos
import SwiftUI

/// Sets of near-identical photos. Phophy suggests one to keep in each set;
/// tap another photo to keep that one instead. Deleting always goes through
/// iOS's own confirmation, and photos go to Recently Deleted.
///
/// Groups are rows of a reusable collection, and the photos in a group are
/// a reusable sideways strip, so hundreds of groups scroll smoothly.
struct SimilarPhotosView: View {
    @Environment(CollectionsModel.self) private var collections
    @Environment(PhotoLibrary.self) private var library
    @Environment(AssistantModel.self) private var assistant
    /// The photo chosen to keep in each group, when not the suggested one.
    @State private var keep: [String: String] = [:]

    var body: some View {
        let groups = collections.snapshot.similarGroups
        let edges = NSDirectionalEdgeInsets(top: 8, leading: 20, bottom: 16, trailing: 20)
        ReusableCollection(
            sections: [
                .header(insets: edges) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Tap the photo you want to keep. The others go to Recently Deleted, where you can recover them for 30 days.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if groups.isEmpty {
                            ContentUnavailableView(
                                "All clean",
                                systemImage: "checkmark.circle",
                                description: Text("No similar photos left.")
                            )
                            .padding(.top, 40)
                        }
                    }
                },
                ReusableSection(
                    layout: .rows(spacing: 16, estimatedHeight: 230),
                    count: groups.count,
                    insets: NSDirectionalEdgeInsets(top: 0, leading: 20, bottom: 24, trailing: 20)
                ) { index in
                    let group = groups[index]
                    return AnyView(
                        SimilarGroupCard(group: group, keep: Binding(
                            get: { keep[group.id] ?? group.suggestedKeep },
                            set: { keep[group.id] = $0 }
                        ))
                        // A reused row showing another group starts fresh.
                        .id(group.id)
                    )
                },
            ],
            contentID: ContentKey(groups: groups.map(\.id), revision: library.revision),
            bottomInset: assistant.isPresented ? 0 : 58
        )
        .ignoresSafeArea(.container, edges: .vertical)
        .background { AmbientBackground() }
        .navigationTitle("Similar photos")
        .navigationBarTitleDisplayMode(.inline)
    }

    private struct ContentKey: Hashable {
        let groups: [String]
        let revision: Int
    }
}

private struct SimilarGroupCard: View {
    let group: SimilarGroup
    @Binding var keep: String

    @Environment(PhotoLibrary.self) private var library
    @State private var assets: [PHAsset] = []
    @State private var isDeleting = false

    private var others: [String] { group.localIDs.filter { $0 != keep } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(group.localIDs.count) similar photos")
                    .font(.headline)
                Spacer()
                if let date = assets.first?.creationDate {
                    Text(date, format: .dateTime.day().month().year())
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            ReusableCollection(
                sections: [ReusableSection(
                    layout: .strip(itemSize: CGSize(width: 104, height: 104), spacing: 8),
                    count: assets.count,
                    // Runs to the card's edges and is clipped there.
                    insets: NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16),
                    cell: { index in AnyView(tile(assets[index])) },
                    asset: { assets.indices.contains($0) ? assets[$0] : nil }
                )],
                axis: .horizontal,
                contentID: assets.map(\.localIdentifier)
            )
            .frame(height: 104)
            .padding(.horizontal, -16)

            Button {
                Task {
                    isDeleting = true
                    _ = await library.delete(localIDs: others)
                    isDeleting = false
                }
            } label: {
                Text(others.count == 1 ? "Delete 1 other" : "Delete \(others.count) others")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .disabled(isDeleting || others.isEmpty)
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .task(id: library.revision) { assets = fetchAssets() }
    }

    private func tile(_ asset: PHAsset) -> some View {
        let isKept = asset.localIdentifier == keep
        return Button {
            keep = asset.localIdentifier
        } label: {
            AssetThumbnail(asset: asset)
                .clipShape(.rect(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(isKept ? Color.white : .clear, lineWidth: 3)
                }
                .overlay(alignment: .bottomLeading) {
                    if isKept {
                        Label("Keep", systemImage: "checkmark")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .glassEffect(.regular, in: .capsule)
                            .padding(6)
                    }
                }
                .opacity(isKept ? 1 : 0.7)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isKept ? "Kept photo" : "Keep this photo instead")
    }

    /// Fetched once per library change, not on every redraw.
    private func fetchAssets() -> [PHAsset] {
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: group.localIDs, options: nil)
        var byID: [String: PHAsset] = [:]
        fetched.enumerateObjects { asset, _, _ in byID[asset.localIdentifier] = asset }
        return group.localIDs.compactMap { byID[$0] }
    }
}
