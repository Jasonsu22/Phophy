import Photos
import SwiftUI
import UIKit

/// Every asset matching a filter, laid out like Photos: oldest at the top,
/// newest at the bottom, opening scrolled to the newest.
///
/// A UIKit collection view, as in Photos: only the cells on screen exist,
/// and a cell that scrolls out of view is reused for the next photo coming
/// in. Opening at the bottom costs the same for 20 photos or 20,000.
struct PhotoGridView: View {
    let filter: PhotoFilter

    @Environment(PhotoLibrary.self) private var library
    @Environment(PhotoViewerModel.self) private var viewer
    @Environment(\.photoZoomNamespace) private var namespace
    @Environment(AssistantModel.self) private var assistant
    @State private var result: PHFetchResult<PHAsset>

    init(filter: PhotoFilter) {
        self.filter = filter
        _result = State(initialValue: PhotoLibrary.fetch(filter, oldestFirst: true))
    }

    var body: some View {
        Group {
            if result.count > 0 {
                AssetGrid(
                    result: result, library: library, viewer: viewer, namespace: namespace,
                    // Room for the floating ask bar above the tab bar.
                    bottomInset: assistant.isPresented ? 0 : 58
                )
                    .ignoresSafeArea(.container, edges: .vertical)
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

private struct AssetGrid: UIViewRepresentable {
    let result: PHFetchResult<PHAsset>
    let library: PhotoLibrary
    let viewer: PhotoViewerModel
    let namespace: Namespace.ID?
    let bottomInset: CGFloat

    static let columns: CGFloat = 4
    static let spacing: CGFloat = 2

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> GridCollectionView {
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = Self.spacing
        layout.minimumInteritemSpacing = Self.spacing
        let view = GridCollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .clear
        view.alwaysBounceVertical = true
        view.contentInsetAdjustmentBehavior = .always
        view.register(UICollectionViewCell.self, forCellWithReuseIdentifier: Coordinator.reuseID)
        view.dataSource = context.coordinator
        view.delegate = context.coordinator
        view.prefetchDataSource = context.coordinator
        view.contentInset.bottom = bottomInset
        view.verticalScrollIndicatorInsets.bottom = bottomInset
        return view
    }

    func updateUIView(_ view: GridCollectionView, context: Context) {
        let coordinator = context.coordinator
        let changed = coordinator.parent.result !== result
        coordinator.parent = self
        if changed { view.reloadData() }
        if view.contentInset.bottom != bottomInset {
            view.contentInset.bottom = bottomInset
            view.verticalScrollIndicatorInsets.bottom = bottomInset
        }
    }

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout,
                             UICollectionViewDataSourcePrefetching {
        static let reuseID = "thumbnail"
        var parent: AssetGrid
        private var cellSide: CGFloat = 0
        private var cachingSize: CGSize = .zero

        init(parent: AssetGrid) { self.parent = parent }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            parent.result.count
        }

        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: Self.reuseID, for: indexPath)
            let index = indexPath.item
            let asset = parent.result.object(at: index)
            let result = parent.result
            // The thumbnail is SwiftUI, so it can be the source of the zoom
            // transition into the viewer; the cell around it is reused.
            cell.contentConfiguration = UIHostingConfiguration {
                AssetThumbnail(asset: asset)
                    .opensInViewer(.fetch(result), at: index, id: asset.localIdentifier)
                    .environment(parent.library)
                    .environment(parent.viewer)
                    .environment(\.photoZoomNamespace, parent.namespace)
            }
            .margins(.all, 0)
            return cell
        }

        func collectionView(_ collectionView: UICollectionView, layout: UICollectionViewLayout,
                            sizeForItemAt indexPath: IndexPath) -> CGSize {
            let width = collectionView.bounds.width
            let side = ((width - AssetGrid.spacing * (AssetGrid.columns - 1)) / AssetGrid.columns).rounded(.down)
            cellSide = side
            return CGSize(width: side, height: side)
        }

        // Photos gets thumbnails ready just before their cells scroll in.
        func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
            parent.library.imageManager.startCachingImages(
                for: assets(at: indexPaths), targetSize: targetSize(collectionView),
                contentMode: .aspectFill, options: AssetThumbnail.requestOptions()
            )
        }

        func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
            parent.library.imageManager.stopCachingImages(
                for: assets(at: indexPaths), targetSize: targetSize(collectionView),
                contentMode: .aspectFill, options: AssetThumbnail.requestOptions()
            )
        }

        private func assets(at indexPaths: [IndexPath]) -> [PHAsset] {
            indexPaths.compactMap { $0.item < parent.result.count ? parent.result.object(at: $0.item) : nil }
        }

        private func targetSize(_ collectionView: UICollectionView) -> CGSize {
            let pixels = cellSide * collectionView.traitCollection.displayScale
            return CGSize(width: pixels, height: pixels)
        }
    }
}

final class GridCollectionView: UICollectionView {
    private var openedAtBottom = false
    private var laidOutWidth: CGFloat = 0

    override func layoutSubviews() {
        if bounds.width != laidOutWidth, bounds.width > 0 {
            laidOutWidth = bounds.width
            collectionViewLayout.invalidateLayout()
        }
        super.layoutSubviews()
        // Like Photos: open on the newest photo, at the bottom.
        if !openedAtBottom, bounds.height > 0, contentSize.height > 0 {
            openedAtBottom = true
            let bottom = contentSize.height + adjustedContentInset.bottom - bounds.height
            setContentOffset(CGPoint(x: 0, y: max(bottom, -adjustedContentInset.top)), animated: false)
        }
    }
}
