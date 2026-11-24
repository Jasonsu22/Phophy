import Photos
import SwiftUI
import UIKit

/// One part of a `ReusableCollection`: how its items are laid out, how many
/// there are, and the SwiftUI view for each.
struct ReusableSection {
    enum Layout {
        /// Square tiles, `columns` across (vertical collections).
        case grid(columns: Int, spacing: CGFloat)
        /// Full-width rows that size themselves to their content.
        case rows(spacing: CGFloat, estimatedHeight: CGFloat)
        /// Fixed-size items in a line (horizontal collections).
        case strip(itemSize: CGSize, spacing: CGFloat)
    }

    var layout: Layout
    var count: Int
    var insets = NSDirectionalEdgeInsets()
    /// The view for item `index`.
    var cell: (Int) -> AnyView
    /// The photo item `index` shows, if any, so its thumbnail can be
    /// prepared just before it scrolls in.
    var asset: ((Int) -> PHAsset?)?
}

extension ReusableSection {
    /// Photo tiles that open the viewer.
    static func photos(
        _ source: PhotoSource,
        layout: Layout,
        insets: NSDirectionalEdgeInsets = NSDirectionalEdgeInsets(),
        cornerRadius: CGFloat = 0
    ) -> ReusableSection {
        ReusableSection(layout: layout, count: source.count, insets: insets, cell: { index in
            guard let asset = source.asset(at: index) else { return AnyView(Color.clear) }
            return AnyView(
                AssetThumbnail(asset: asset)
                    .clipShape(.rect(cornerRadius: cornerRadius))
                    .opensInViewer(source, at: index, id: asset.localIdentifier)
            )
        }, asset: { source.asset(at: $0) })
    }

    /// A single full-width view, such as a heading.
    static func header<Content: View>(insets: NSDirectionalEdgeInsets = NSDirectionalEdgeInsets(),
                                       @ViewBuilder _ content: @escaping () -> Content) -> ReusableSection {
        ReusableSection(layout: .rows(spacing: 0, estimatedHeight: 44), count: 1, insets: insets) { _ in
            AnyView(content())
        }
    }
}

/// A scrolling list or grid built on UICollectionView, as Photos is: only
/// the cells on screen exist, and a cell that scrolls out of view is reused
/// for the item scrolling in. Scrolling costs the same for 10 items or
/// 20,000. Each cell holds a SwiftUI view.
struct ReusableCollection: View {
    let sections: [ReusableSection]
    var axis: Axis = .vertical
    /// Change it when the items change; anything else only refreshes the
    /// cells on screen.
    var contentID: AnyHashable = 0
    /// Open scrolled to the end (the newest photo, as in Photos).
    var startsAtEnd = false
    var bottomInset: CGFloat = 0
    /// Pinch to show more or fewer photos across, as in Photos. The choice
    /// is remembered under this key; nil turns pinching off.
    var zoomKey: String? = nil

    // Cells are hosted outside this view's SwiftUI tree, so what they read
    // from the environment is passed to them.
    @Environment(PhotoLibrary.self) private var library: PhotoLibrary?
    @Environment(PhotoViewerModel.self) private var viewer: PhotoViewerModel?
    @Environment(IndexStatus.self) private var indexStatus: IndexStatus?
    @Environment(CollectionsModel.self) private var collections: CollectionsModel?
    @Environment(AssistantModel.self) private var assistant: AssistantModel?
    @Environment(StudyModel.self) private var study: StudyModel?
    @Environment(\.photoZoomNamespace) private var namespace

    var body: some View {
        CollectionRepresentable(
            sections: sections, axis: axis, contentID: contentID, startsAtEnd: startsAtEnd,
            bottomInset: bottomInset, zoomKey: zoomKey, imageManager: library?.imageManager, decorate: decorate
        )
    }

    private func decorate(_ view: AnyView) -> AnyView {
        var view = AnyView(view.environment(\.photoZoomNamespace, namespace))
        if let library { view = AnyView(view.environment(library)) }
        if let viewer { view = AnyView(view.environment(viewer)) }
        if let indexStatus { view = AnyView(view.environment(indexStatus)) }
        if let collections { view = AnyView(view.environment(collections)) }
        if let assistant { view = AnyView(view.environment(assistant)) }
        if let study { view = AnyView(view.environment(study)) }
        return view
    }
}

private struct CollectionRepresentable: UIViewRepresentable {
    let sections: [ReusableSection]
    let axis: Axis
    let contentID: AnyHashable
    let startsAtEnd: Bool
    let bottomInset: CGFloat
    let zoomKey: String?
    let imageManager: PHCachingImageManager?
    let decorate: (AnyView) -> AnyView

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> ReusableCollectionView {
        let coordinator = context.coordinator
        let configuration = UICollectionViewCompositionalLayoutConfiguration()
        configuration.scrollDirection = axis == .horizontal ? .horizontal : .vertical
        let layout = UICollectionViewCompositionalLayout(sectionProvider: { [weak coordinator] index, environment in
            coordinator?.layoutSection(index, environment: environment)
        }, configuration: configuration)

        let view = ReusableCollectionView(frame: .zero, collectionViewLayout: layout)
        view.axis = axis
        view.startsAtEnd = startsAtEnd
        view.backgroundColor = .clear
        view.clipsToBounds = true
        view.showsHorizontalScrollIndicator = false
        view.alwaysBounceVertical = axis == .vertical
        view.alwaysBounceHorizontal = axis == .horizontal
        view.contentInsetAdjustmentBehavior = axis == .vertical ? .always : .never
        view.keyboardDismissMode = .onDrag
        view.register(UICollectionViewCell.self, forCellWithReuseIdentifier: Coordinator.reuseID)
        view.dataSource = coordinator
        view.prefetchDataSource = coordinator
        view.contentInset.bottom = bottomInset
        view.verticalScrollIndicatorInsets.bottom = bottomInset
        coordinator.shownContentID = contentID
        if let zoomKey, axis == .vertical {
            let saved = UserDefaults.standard.integer(forKey: zoomKey)
            if Coordinator.zoomSteps.contains(saved) { coordinator.columns = saved }
            let pinch = UIPinchGestureRecognizer(target: coordinator, action: #selector(Coordinator.pinched(_:)))
            pinch.delegate = coordinator
            view.addGestureRecognizer(pinch)
        }
        return view
    }

    func updateUIView(_ view: ReusableCollectionView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        if view.contentInset.bottom != bottomInset {
            view.contentInset.bottom = bottomInset
            view.verticalScrollIndicatorInsets.bottom = bottomInset
        }
        if coordinator.shownContentID != contentID {
            coordinator.shownContentID = contentID
            view.reloadData()
        } else {
            // Same items: hand the cells on screen their updated views
            // (for example a new selection) without rebuilding them.
            let visible = view.indexPathsForVisibleItems
            if !visible.isEmpty { view.reconfigureItems(at: visible) }
        }
    }

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDataSourcePrefetching, UIGestureRecognizerDelegate {
        static let reuseID = "cell"
        var parent: CollectionRepresentable
        var shownContentID: AnyHashable?
        /// Columns chosen by pinching; nil keeps the section's own.
        var columns: Int?
        static let zoomSteps = [1, 3, 5, 7, 11]
        private var pinchHandled = false

        init(parent: CollectionRepresentable) { self.parent = parent }

        /// One step per pinch, like Photos: pinch out for bigger photos,
        /// pinch in for more. The photo under the fingers stays in view.
        @objc func pinched(_ gesture: UIPinchGestureRecognizer) {
            guard let view = gesture.view as? UICollectionView else { return }
            // A finger lifted at the end of a pinch must not open the photo under it.
            GridPinch.lastActivity = .now
            switch gesture.state {
            case .began:
                pinchHandled = false
            case .changed:
                guard !pinchHandled, gesture.scale > 1.25 || gesture.scale < 0.8 else { return }
                let current = columns ?? defaultColumns ?? 4
                let steps = Self.zoomSteps
                let index = steps.firstIndex { $0 >= current } ?? steps.count - 1
                let next = gesture.scale > 1
                    ? steps[max(index - 1, 0)]
                    : steps[min((steps[index] == current ? index + 1 : index), steps.count - 1)]
                guard next != current else { return }
                pinchHandled = true
                let anchor = view.indexPathForItem(at: gesture.location(in: view))
                columns = next
                if let key = parent.zoomKey { UserDefaults.standard.set(next, forKey: key) }
                UIView.animate(withDuration: 0.32, delay: 0, usingSpringWithDamping: 0.88, initialSpringVelocity: 0) {
                    view.collectionViewLayout.invalidateLayout()
                    view.layoutIfNeeded()
                    if let anchor { view.scrollToItem(at: anchor, at: .centeredVertically, animated: false) }
                    // Never leave empty space past the first or last row.
                    let inset = view.adjustedContentInset
                    let maxY = max(view.contentSize.height + inset.bottom - view.bounds.height, -inset.top)
                    view.contentOffset.y = min(max(view.contentOffset.y, -inset.top), maxY)
                }
                // Bigger tiles need sharper thumbnails.
                view.reconfigureItems(at: view.indexPathsForVisibleItems)
            default:
                break
            }
        }

        // The photos' tap buttons keep their touches; the pinch runs alongside.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        private var defaultColumns: Int? {
            for section in parent.sections {
                if case let .grid(columns, _) = section.layout { return columns }
            }
            return nil
        }

        func layoutSection(_ index: Int, environment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection? {
            guard index < parent.sections.count else { return nil }
            let section = parent.sections[index]
            let result: NSCollectionLayoutSection
            switch section.layout {
            case let .grid(columns, spacing):
                let width = environment.container.effectiveContentSize.width
                    - section.insets.leading - section.insets.trailing
                let count = max(self.columns ?? columns, 1)
                let side = ((width - spacing * CGFloat(count - 1)) / CGFloat(count)).rounded(.down)
                let item = NSCollectionLayoutItem(layoutSize: .init(
                    widthDimension: .absolute(side), heightDimension: .absolute(side)))
                let group = NSCollectionLayoutGroup.horizontal(
                    layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(side)),
                    repeatingSubitem: item, count: count)
                group.interItemSpacing = .flexible(spacing)
                result = NSCollectionLayoutSection(group: group)
                result.interGroupSpacing = spacing
            case let .rows(spacing, estimatedHeight):
                let size = NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1), heightDimension: .estimated(estimatedHeight))
                let group = NSCollectionLayoutGroup.vertical(
                    layoutSize: size, subitems: [NSCollectionLayoutItem(layoutSize: size)])
                result = NSCollectionLayoutSection(group: group)
                result.interGroupSpacing = spacing
            case let .strip(itemSize, spacing):
                let size = NSCollectionLayoutSize(
                    widthDimension: .absolute(itemSize.width), heightDimension: .absolute(itemSize.height))
                let group = NSCollectionLayoutGroup.horizontal(
                    layoutSize: size, subitems: [NSCollectionLayoutItem(layoutSize: size)])
                result = NSCollectionLayoutSection(group: group)
                result.interGroupSpacing = spacing
            }
            result.contentInsets = section.insets
            return result
        }

        func numberOfSections(in collectionView: UICollectionView) -> Int { parent.sections.count }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            section < parent.sections.count ? parent.sections[section].count : 0
        }

        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: Self.reuseID, for: indexPath)
            let content = parent.decorate(parent.sections[indexPath.section].cell(indexPath.item))
            cell.contentConfiguration = UIHostingConfiguration { content }.margins(.all, 0)
            return cell
        }

        // Thumbnails are requested just before their cells scroll in.
        func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
            cache(indexPaths, in: collectionView, start: true)
        }

        func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
            cache(indexPaths, in: collectionView, start: false)
        }

        private func cache(_ indexPaths: [IndexPath], in collectionView: UICollectionView, start: Bool) {
            guard let imageManager = parent.imageManager else { return }
            var bySide: [CGFloat: [PHAsset]] = [:]
            for path in indexPaths {
                guard path.section < parent.sections.count,
                      let asset = parent.sections[path.section].asset?(path.item),
                      let size = collectionView.layoutAttributesForItem(at: path)?.size else { continue }
                // The size AssetThumbnail asks for: its longer side, square.
                let side = max(size.width, size.height) * collectionView.traitCollection.displayScale
                bySide[side, default: []].append(asset)
            }
            for (side, assets) in bySide {
                let size = CGSize(width: side, height: side)
                if start {
                    imageManager.startCachingImages(
                        for: assets, targetSize: size, contentMode: .aspectFill, options: AssetThumbnail.requestOptions())
                } else {
                    imageManager.stopCachingImages(
                        for: assets, targetSize: size, contentMode: .aspectFill, options: AssetThumbnail.requestOptions())
                }
            }
        }
    }
}

/// When a grid was last pinched, so a photo tap that ends a pinch is ignored.
@MainActor enum GridPinch {
    static var lastActivity = Date.distantPast
    static var isRecent: Bool { Date.now.timeIntervalSince(lastActivity) < 0.4 }
}

final class ReusableCollectionView: UICollectionView {
    var axis: Axis = .vertical
    var startsAtEnd = false
    private var scrolledToEnd = false
    private var laidOutSize: CGSize = .zero

    // Indexing waits while any list or grid is moving.
    override var contentOffset: CGPoint {
        didSet { if contentOffset != oldValue { IndexThrottle.shared.noteActivity() } }
    }

    override func layoutSubviews() {
        if bounds.size != laidOutSize, bounds.width > 0 {
            laidOutSize = bounds.size
            collectionViewLayout.invalidateLayout()
        }
        super.layoutSubviews()
        guard startsAtEnd, !scrolledToEnd, bounds.width > 0, bounds.height > 0 else { return }
        let size = collectionViewLayout.collectionViewContentSize
        guard size.width > 0, size.height > 0 else { return }
        scrolledToEnd = true
        if axis == .vertical {
            let bottom = size.height + adjustedContentInset.bottom - bounds.height
            setContentOffset(CGPoint(x: 0, y: max(bottom, -adjustedContentInset.top)), animated: false)
        } else {
            let end = size.width + adjustedContentInset.right - bounds.width
            setContentOffset(CGPoint(x: max(end, -adjustedContentInset.left), y: 0), animated: false)
        }
    }
}
