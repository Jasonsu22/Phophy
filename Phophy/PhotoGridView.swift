import Photos
import SwiftUI

/// Scrollable grid of every asset matching a filter, newest first.
struct PhotoGridView: View {
    let filter: PhotoFilter

    @Environment(PhotoLibrary.self) private var library
    @State private var result: PHFetchResult<PHAsset>?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 4)

    var body: some View {
        ScrollView {
            if let result, result.count > 0 {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(0..<result.count, id: \.self) { index in
                        let asset = result.object(at: index)
                        NavigationLink(value: Route.photo(localIdentifier: asset.localIdentifier)) {
                            AssetThumbnail(asset: asset)
                                .aspectRatio(1, contentMode: .fit)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if result != nil {
                ContentUnavailableView(
                    "Nothing here yet",
                    systemImage: "photo.on.rectangle",
                    description: Text("No items in \(filter.title).")
                )
                .padding(.top, 120)
            }
        }
        .background { AmbientBackground() }
        .navigationTitle(filter.title)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: library.revision, initial: true) {
            result = library.fetch(filter)
        }
    }
}
