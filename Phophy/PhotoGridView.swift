import Photos
import SwiftUI

/// Every asset matching a filter, laid out like Photos: oldest at the top,
/// newest at the bottom, opening scrolled to the newest.
struct PhotoGridView: View {
    let filter: PhotoFilter

    @Environment(PhotoLibrary.self) private var library
    @State private var result: PHFetchResult<PHAsset>?

    init(filter: PhotoFilter) {
        self.filter = filter
        // Fetched before the first frame, so the grid can open at the bottom.
        _result = State(initialValue: PhotoLibrary.fetch(filter, oldestFirst: true))
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 4)

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            if let result, result.count > 0 {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(0..<result.count, id: \.self) { index in
                        let asset = result.object(at: index)
                        AssetThumbnail(asset: asset)
                            .aspectRatio(1, contentMode: .fit)
                            .opensInViewer(.fetch(result), at: index, id: asset.localIdentifier)
                            .id(index)
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
        // Like Photos: open on the newest photo, at the bottom.
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .task {
            await Task.yield()
            if let result, result.count > 0 { proxy.scrollTo(result.count - 1, anchor: .bottom) }
        }
        }
        .background { AmbientBackground() }
        .navigationTitle(filter.title)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: library.revision) {
            result = library.fetch(filter, oldestFirst: true)
        }
    }
}
