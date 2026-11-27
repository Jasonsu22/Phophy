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

    func makeUIView(context: Context) -> ZoomContainer {
        let coordinator = context.coordinator
        if let zoomKey, axis == .vertical {
            let saved = UserDefaults.standard.integer(forKey: zoomKey)
            if Coordinator.zoomSteps.contains(saved) { coordinator.columns = saved }
        }
        let layout = coordinator.makeLayout(columns: coordinator.columns)

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
        if zoomKey != nil, axis == .vertical {
            let pinch = UIPinchGestureRecognizer(target: coordinator, action: #selector(Coordinator.pinched(_:)))
            pinch.delegate = coordinator
            view.addGestureRecognizer(pinch)
        }
        return ZoomContainer(view)
    }

    func updateUIView(_ container: ZoomContainer, context: Context) {
        let view = container.collection
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
        
        init(parent: CollectionRepresentable) { self.parent = parent }

        /// A layout showing `columns` across in its grids (nil: each grid's own).
        func makeLayout(columns: Int?) -> ZoomableLayout {
            let configuration = UICollectionViewCompositionalLayoutConfiguration()
            configuration.scrollDirection = parent.axis == .horizontal ? .horizontal : .vertical
            return ZoomableLayout(sectionProvider: { [weak self] index, environment in
                self?.layoutSection(index, environment: environment, columns: columns)
            }, configuration: configuration)
        }

        // MARK: Pinch to zoom
        //
        // As in Photos, the grid is never reshuffled under the fingers. The
        // grid as it was is kept as a picture; the real grid switches to the
        // next size straight away, underneath. While the fingers move, both
        // are scaled as whole sheets so the pinched photo is the same size
        // and in the same place in each, and one fades into the other. The
        // pinched photo grows or shrinks with the fingers; everything around
        // it dissolves from the old arrangement to the new one. Letting go
        // settles on the nearer size. A long pinch carries on to the next size.

        private struct Zoom {
            let from: Int, to: Int
            let old: UIView                 // picture of the grid before
            let oldLayout: UICollectionViewLayout
            let oldOffset: CGPoint
            let frame0: CGRect              // pinched photo, before (in the container)
            let frame1: CGRect              // pinched photo, after
            var progress: CGFloat = 0
            /// Where the fingers' midpoint was when the step began, and how
            /// far it has moved since: the grid moves with the hand.
            var startTouch: CGPoint = .zero
            var drift: CGPoint = .zero
        }
        /// At the smallest or largest size the grid gives a little and springs back.
        private var stretching = false
        private var zoom: Zoom?
        private var settling = false

        @objc func pinched(_ gesture: UIPinchGestureRecognizer) {
            guard let view = gesture.view as? UICollectionView else { return }
            // A finger lifted at the end of a pinch must not open the photo under it.
            GridPinch.lastActivity = .now
            switch gesture.state {
            case .changed:
                guard !settling, gesture.numberOfTouches >= 2, let container = view.superview else { return }
                let touch = gesture.location(in: container)
                if zoom == nil { begin(gesture, in: view) }
                guard var zoom else {
                    stretch(view, scale: gesture.scale, around: touch)
                    return
                }
                // Turned round and went back past the start: step the other way.
                let zoomingIn = zoom.to < zoom.from
                if zoomingIn ? gesture.scale < 0.98 : gesture.scale > 1.02,
                   nextStep(from: zoom.from, zoomingIn: !zoomingIn) != nil {
                    finish(view, committed: false)
                    gesture.scale = 1
                    return
                }
                zoom.progress = progress(for: gesture.scale, zoom)
                zoom.drift = CGPoint(x: touch.x - zoom.startTouch.x, y: touch.y - zoom.startTouch.y)
                self.zoom = zoom
                apply(zoom, to: view)
                // Past the next size and still pinching: carry on from there.
                if zoom.progress >= 1, nextStep(from: zoom.to, zoomingIn: zoom.to < zoom.from) != nil {
                    finish(view, committed: true, keeping: zoom.drift)
                    gesture.scale = 1
                }
            case .ended, .cancelled, .failed:
                if stretching { relax(view) }
                guard let zoom, !settling else { return }
                // Fingers still moving apart (zoom in) or together (zoom out) count too.
                let towards = zoom.to < zoom.from ? gesture.velocity : -gesture.velocity
                let commit = zoom.progress > 0.35 || (zoom.progress > 0.08 && towards > 0.5)
                settle(view, commit: commit, velocity: abs(gesture.velocity))
            default:
                break
            }
        }

        private func nextStep(from current: Int, zoomingIn: Bool) -> Int? {
            let steps = Self.zoomSteps
            let index = steps.firstIndex { $0 >= current } ?? steps.count - 1
            let next = zoomingIn
                ? steps[max(index - 1, 0)]
                : steps[min(steps[index] == current ? index + 1 : index, steps.count - 1)]
            return next == current ? nil : next
        }

        private func begin(_ gesture: UIPinchGestureRecognizer, in view: UICollectionView) {
            guard abs(gesture.scale - 1) > 0.02, let container = view.superview else { return }
            let current = columns ?? defaultColumns ?? 4
            guard let next = nextStep(from: current, zoomingIn: gesture.scale > 1) else { return }
            let touch = gesture.location(in: view)
            guard let anchor = view.indexPathForItem(at: touch)
                    ?? view.indexPathsForVisibleItems.sorted()[safe: view.indexPathsForVisibleItems.count / 2],
                  let before = view.layoutAttributesForItem(at: anchor),
                  let old = view.snapshotView(afterScreenUpdates: false) else { return }
            let oldLayout = view.collectionViewLayout
            let oldOffset = view.contentOffset
            let frame0 = before.frame.offsetBy(dx: -oldOffset.x, dy: -oldOffset.y)

            if next > current { warmThumbnails(around: anchor, in: view, factor: CGFloat(next) / CGFloat(current)) }

            // The real grid takes its new size now, with the pinched photo
            // as close as it can be to where it was.
            UIView.performWithoutAnimation {
                view.setCollectionViewLayout(makeLayout(columns: next), animated: false)
                view.layoutIfNeeded()
                if let after = view.layoutAttributesForItem(at: anchor) {
                    let inset = view.adjustedContentInset
                    let maxY = max(view.contentSize.height + inset.bottom - view.bounds.height, -inset.top)
                    let y = min(max(after.center.y - frame0.midY, -inset.top), maxY)
                    view.contentOffset = CGPoint(x: oldOffset.x, y: y)
                    view.layoutIfNeeded()
                }
            }
            let after = view.layoutAttributesForItem(at: anchor)?.frame ?? before.frame
            let frame1 = after.offsetBy(dx: -view.contentOffset.x, dy: -view.contentOffset.y)

            old.frame = view.frame
            old.isUserInteractionEnabled = false
            container.addSubview(old)
            var zoom = Zoom(from: current, to: next, old: old, oldLayout: oldLayout, oldOffset: oldOffset,
                            frame0: frame0, frame1: frame1)
            zoom.startTouch = gesture.location(in: container)
            self.zoom = zoom
            apply(zoom, to: view)
        }

        /// How far along the step a pinch of `scale` is: the pinched photo
        /// has grown (or shrunk) by the same factor as the fingers.
        private func progress(for scale: CGFloat, _ zoom: Zoom) -> CGFloat {
            let side0 = zoom.frame0.width, side1 = zoom.frame1.width
            guard abs(side1 - side0) > 0.5 else { return 0 }
            return min(max((side0 * scale - side0) / (side1 - side0), 0), 1)
        }

        /// Places both sheets for the step's current progress.
        private func apply(_ zoom: Zoom, to view: UICollectionView) {
            let p = zoom.progress
            // Where the pinched photo is right now: between its two places.
            let side = zoom.frame0.width + (zoom.frame1.width - zoom.frame0.width) * p
            let center = CGPoint(x: zoom.frame0.midX + (zoom.frame1.midX - zoom.frame0.midX) * p + zoom.drift.x,
                                 y: zoom.frame0.midY + (zoom.frame1.midY - zoom.frame0.midY) * p + zoom.drift.y)
            zoom.old.transform = Self.transform(moving: zoom.frame0, toSide: side, center: center, in: view.bounds.size)
            view.transform = Self.transform(moving: zoom.frame1, toSide: side, center: center, in: view.bounds.size)
            // One arrangement dissolves into the other over the whole pinch.
            zoom.old.alpha = 1 - p * p * (3 - 2 * p)
        }

        /// The transform that scales a sheet so `frame` (in the sheet's own
        /// coordinates) becomes `side` wide, centred on `center`.
        private static func transform(moving frame: CGRect, toSide side: CGFloat, center: CGPoint, in size: CGSize) -> CGAffineTransform {
            let scale = side / max(frame.width, 1)
            // Transforms act around the sheet's centre.
            let mid = CGPoint(x: size.width / 2, y: size.height / 2)
            let dx = center.x - (mid.x + (frame.midX - mid.x) * scale)
            let dy = center.y - (mid.y + (frame.midY - mid.y) * scale)
            return CGAffineTransform(translationX: dx, y: dy).scaledBy(x: scale, y: scale)
        }

        /// After the fingers lift: glide to the chosen size.
        private func settle(_ view: UICollectionView, commit: Bool, velocity: CGFloat) {
            guard var zoom else { return }
            settling = true
            let remaining = commit ? 1 - zoom.progress : zoom.progress
            zoom.progress = commit ? 1 : 0
            zoom.drift = .zero
            self.zoom = zoom
            let spring = UISpringTimingParameters(dampingRatio: 0.86, initialVelocity: CGVector(dx: min(velocity, 4), dy: 0))
            let animator = UIViewPropertyAnimator(duration: 0.3 + 0.2 * Double(remaining), timingParameters: spring)
            animator.addAnimations { self.apply(zoom, to: view) }
            animator.addCompletion { _ in
                self.finish(view, committed: commit)
                self.settling = false
                GridPinch.lastActivity = .now
            }
            animator.startAnimation()
        }

        /// Ends the step: the real grid stays at the new size, or goes back.
        /// `keeping`: how far the hand has carried the grid, when the pinch goes on.
        private func finish(_ view: UICollectionView, committed: Bool, keeping drift: CGPoint = .zero) {
            guard let zoom else { return }
            self.zoom = nil
            UIView.performWithoutAnimation {
                view.transform = .identity
                if committed {
                    columns = zoom.to
                    if let key = parent.zoomKey { UserDefaults.standard.set(zoom.to, forKey: key) }
                    if drift.y != 0 {
                        let inset = view.adjustedContentInset
                        let maxY = max(view.contentSize.height + inset.bottom - view.bounds.height, -inset.top)
                        view.contentOffset.y = min(max(view.contentOffset.y - drift.y, -inset.top), maxY)
                        view.layoutIfNeeded()
                    }
                } else {
                    view.setCollectionViewLayout(zoom.oldLayout, animated: false)
                    view.layoutIfNeeded()
                    view.contentOffset = zoom.oldOffset
                }
                zoom.old.removeFromSuperview()
            }
        }

        /// No bigger or smaller size left: the grid stretches a little with
        /// the fingers, so the pinch is felt, and springs back on release.
        private func stretch(_ view: UICollectionView, scale: CGFloat, around touch: CGPoint) {
            let current = columns ?? defaultColumns ?? 4
            guard nextStep(from: current, zoomingIn: scale > 1) == nil else { return }
            stretching = true
            let give = 1 + (scale > 1 ? min(scale - 1, 1.5) * 0.12 : -min(1 - scale, 0.6) * 0.2)
            let mid = CGPoint(x: view.bounds.width / 2, y: view.bounds.height / 2)
            view.transform = CGAffineTransform(translationX: (touch.x - mid.x) * (1 - give), y: (touch.y - mid.y) * (1 - give))
                .scaledBy(x: give, y: give)
        }

        private func relax(_ view: UICollectionView) {
            stretching = false
            UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0,
                           options: [.allowUserInteraction, .beginFromCurrentState]) { view.transform = .identity }
        }

        /// Zooming out brings in photos that weren't on screen. Small copies
        /// are fetched for them now, so they show up as the tiles appear
        /// instead of as empty squares.
        private func warmThumbnails(around anchor: IndexPath, in view: UICollectionView, factor: CGFloat) {
            guard let imageManager = parent.imageManager,
                  let source = parent.sections[safe: anchor.section]?.asset else { return }
            let count = parent.sections[anchor.section].count
            let reach = Int(CGFloat(view.indexPathsForVisibleItems.count) * factor * factor)
            let range = max(anchor.item - reach, 0)..<min(anchor.item + reach, count)
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = false
            let side = 160.0
            for item in range {
                guard let asset = source(item), ThumbnailMemory.image(for: asset) == nil else { continue }
                imageManager.requestImage(for: asset, targetSize: CGSize(width: side, height: side),
                                          contentMode: .aspectFill, options: options) { image, _ in
                    if let image { ThumbnailMemory.remember(image, for: asset) }
                }
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

        func layoutSection(_ index: Int, environment: NSCollectionLayoutEnvironment, columns: Int?) -> NSCollectionLayoutSection? {
            guard index < parent.sections.count else { return nil }
            let section = parent.sections[index]
            let result: NSCollectionLayoutSection
            switch section.layout {
            case let .grid(sectionColumns, spacing):
                let columnsOverride = columns
                let columns = sectionColumns
                let width = environment.container.effectiveContentSize.width
                    - section.insets.leading - section.insets.trailing
                let count = max(columnsOverride ?? columns, 1)
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

/// Holds the grid, and during a pinch the picture of the grid as it was.
/// Clips both, since they are scaled past their edges while zooming.
final class ZoomContainer: UIView {
    let collection: ReusableCollectionView

    init(_ collection: ReusableCollectionView) {
        self.collection = collection
        super.init(frame: .zero)
        clipsToBounds = true
        addSubview(collection)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        // A scaled view's frame isn't its real size; leave it alone mid-pinch.
        if collection.transform.isIdentity, collection.frame != bounds { collection.frame = bounds }
    }
}

/// A compositional layout that, after a pinch, keeps the scroll position the
/// pinch ended at instead of jumping.
final class ZoomableLayout: UICollectionViewCompositionalLayout {
    var pinnedOffset: CGPoint?

    override func targetContentOffset(forProposedContentOffset proposed: CGPoint) -> CGPoint {
        pinnedOffset ?? super.targetContentOffset(forProposedContentOffset: proposed)
    }
}

/// The last thumbnail shown for each photo, so a cell that appears (or is
/// reused) shows a picture straight away while a sharper one loads.
@MainActor enum ThumbnailMemory {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 3000
        cache.totalCostLimit = 120 << 20  // bytes of decoded pixels
        return cache
    }()

    static func image(for asset: PHAsset) -> UIImage? { cache.object(forKey: asset.localIdentifier as NSString) }

    static func remember(_ image: UIImage, for asset: PHAsset) {
        let key = asset.localIdentifier as NSString
        // Keep the sharper of the two.
        if let old = cache.object(forKey: key), old.size.width * old.scale > image.size.width * image.scale { return }
        let pixels = image.size.width * image.scale * image.size.height * image.scale
        cache.setObject(image, forKey: key, cost: Int(pixels) * 4)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
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
