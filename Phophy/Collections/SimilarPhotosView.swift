import Photos
import SwiftUI

/// Sets of near-identical photos. Phophy suggests one to keep in each set;
/// tap another photo to keep that one instead. Deleting always goes through
/// iOS's own confirmation, and photos go to Recently Deleted.
struct SimilarPhotosView: View {
    @Environment(CollectionsModel.self) private var collections

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Tap the photo you want to keep. The others go to Recently Deleted, where you can recover them for 30 days.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if collections.snapshot.similarGroups.isEmpty {
                    ContentUnavailableView(
                        "All clean",
                        systemImage: "checkmark.circle",
                        description: Text("No similar photos left.")
                    )
                    .padding(.top, 40)
                }
                ForEach(collections.snapshot.similarGroups) { group in
                    SimilarGroupCard(group: group)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background { AmbientBackground() }
        .navigationTitle("Similar photos")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SimilarGroupCard: View {
    let group: SimilarGroup

    @Environment(PhotoLibrary.self) private var library
    @State private var keep: String?
    @State private var isDeleting = false

    private var keptID: String { keep ?? group.suggestedKeep }
    private var others: [String] { group.localIDs.filter { $0 != keptID } }

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

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(assets, id: \.localIdentifier) { asset in
                        let isKept = asset.localIdentifier == keptID
                        Button {
                            keep = asset.localIdentifier
                        } label: {
                            AssetThumbnail(asset: asset)
                                .frame(width: 104, height: 104)
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
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()

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
    }

    private var assets: [PHAsset] {
        _ = library.revision
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: group.localIDs, options: nil)
        var byID: [String: PHAsset] = [:]
        fetched.enumerateObjects { asset, _, _ in byID[asset.localIdentifier] = asset }
        return group.localIDs.compactMap { byID[$0] }
    }
}
