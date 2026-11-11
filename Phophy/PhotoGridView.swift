import Photos
import SwiftUI

/// Every asset matching a filter, laid out like Photos: oldest at the top,
/// newest at the bottom, opening scrolled to the newest. Cells are reused
/// as you scroll, so a library of 20,000 scrolls like one of 20.
struct PhotoGridView: View {
    let filter: PhotoFilter

    @Environment(PhotoLibrary.self) private var library
    @State private var result: PHFetchResult<PHAsset>

    init(filter: PhotoFilter) {
        self.filter = filter
        _result = State(initialValue: PhotoLibrary.fetch(filter, oldestFirst: true))
    }

    var body: some View {
        Group {
            if result.count > 0 {
                PhotoGrid(source: .fetch(result), contentID: ObjectIdentifier(result))
            } else {
                ContentUnavailableView(
                    "Nothing here yet",
                    systemImage: "photo.on.rectangle",
                    description: Text("No items in \(filter.title).")
                )
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

/// Square photo tiles, four across, opening at the newest (bottom) photo,
/// with room at the bottom for the floating ask bar.
struct PhotoGrid: View {
    let source: PhotoSource
    let contentID: AnyHashable

    @Environment(AssistantModel.self) private var assistant

    var body: some View {
        ReusableCollection(
            sections: [.photos(source, layout: .grid(columns: 4, spacing: 2))],
            contentID: contentID,
            startsAtEnd: true,
            bottomInset: assistant.isPresented ? 0 : 58
        )
        .ignoresSafeArea(.container, edges: .vertical)
    }
}
