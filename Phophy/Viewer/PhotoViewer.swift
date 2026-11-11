import AVKit
import Photos
import PhotosUI
import SwiftUI
import UIKit

/// The photos a viewer can page through: a fixed list, or a whole fetch
/// result (for example the entire library) read lazily.
enum PhotoSource {
    case assets([PHAsset])
    case fetch(PHFetchResult<PHAsset>)

    var count: Int {
        switch self {
        case let .assets(assets): assets.count
        case let .fetch(result): result.count
        }
    }

    func asset(at index: Int) -> PHAsset? {
        guard index >= 0, index < count else { return nil }
        switch self {
        case let .assets(assets): return assets[index]
        case let .fetch(result): return result.object(at: index)
        }
    }
}

/// Opens the full-screen photo viewer from anywhere in the app. It is shown
/// with Apple's zoom transition, so a photo grows out of its thumbnail and
/// shrinks back into it, as in Photos.
@Observable
final class PhotoViewerModel {
    struct Presentation: Identifiable {
        let id = UUID()
        let source: PhotoSource
        let start: Int
    }

    var presentation: Presentation?
    /// The photo on screen. Closing zooms back to this photo's thumbnail.
    var currentID = ""

    func open(_ source: PhotoSource, at index: Int) {
        guard source.count > 0 else { return }
        let start = min(max(index, 0), source.count - 1)
        currentID = source.asset(at: start)?.localIdentifier ?? ""
        presentation = Presentation(source: source, start: start)
    }

    func close() {
        presentation = nil
    }
}

private struct PhotoZoomNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    /// Shared by thumbnails and the viewer so the zoom transition can match them.
    var photoZoomNamespace: Namespace.ID? {
        get { self[PhotoZoomNamespaceKey.self] }
        set { self[PhotoZoomNamespaceKey.self] = newValue }
    }
}

extension View {
    /// Makes a thumbnail open the full-screen viewer, zooming out of it.
    func opensInViewer(_ source: @autoclosure @escaping () -> PhotoSource, at index: Int, id: String) -> some View {
        modifier(OpensInViewer(source: source, index: index, id: id))
    }
}

private struct OpensInViewer: ViewModifier {
    let source: () -> PhotoSource
    let index: Int
    let id: String

    @Environment(PhotoViewerModel.self) private var viewer
    @Environment(\.photoZoomNamespace) private var namespace

    func body(content: Content) -> some View {
        let button = Button {
            viewer.open(source(), at: index)
        } label: {
            content.contentShape(.rect)
        }
        .buttonStyle(.plain)
        if let namespace {
            button.matchedTransitionSource(id: id, in: namespace)
        } else {
            button
        }
    }
}

/// How viewer pages load: one target size and one set of options, so the
/// images preloaded for neighbouring pages are the ones the pages ask for.
enum PhotoLoading {
    static func targetSize(for size: CGSize, scale: CGFloat) -> CGSize {
        CGSize(width: max(size.width, 1) * scale, height: max(size.height, 1) * scale)
    }

    static func pageOptions() -> PHImageRequestOptions {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        return options
    }

    private static let instantCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 40
        return cache
    }()

    /// The small copy Photos keeps ready for thumbnails. It comes back
    /// immediately, so a page never starts empty. Kept in a small cache,
    /// because SwiftUI may build a page's view several times.
    static func instantImage(for asset: PHAsset) -> UIImage? {
        let key = asset.localIdentifier as NSString
        if let cached = instantCache.object(forKey: key) { return cached }
        let image = requestInstantImage(for: asset)
        if let image { instantCache.setObject(image, forKey: key) }
        return image
    }

    private static func requestInstantImage(for asset: PHAsset) -> UIImage? {
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        var result: UIImage?
        PHImageManager.default().requestImage(
            for: asset, targetSize: CGSize(width: 512, height: 512), contentMode: .aspectFit, options: options
        ) { image, _ in result = image }
        return result
    }
}

/// Full-screen viewer, laid out like Photos: swipe sideways between photos,
/// pinch or double-tap to zoom, swipe down to close, tap to hide the bars.
/// Live Photos play when you press and hold; videos play when they open.
struct PhotoViewer: View {
    let presentation: PhotoViewerModel.Presentation

    @Environment(PhotoViewerModel.self) private var viewer
    @Environment(PhotoLibrary.self) private var library
    @Environment(\.displayScale) private var displayScale
    @State private var position: Int
    @State private var chromeHidden = false
    @State private var showingInfo = false
    @State private var liveEnabled = true
    @State private var preheated: [PHAsset] = []
    private static let pageGap: CGFloat = 20

    init(presentation: PhotoViewerModel.Presentation) {
        self.presentation = presentation
        _position = State(initialValue: presentation.start)
    }

    private var current: PHAsset? {
        _ = library.revision
        return presentation.source.asset(at: position)
    }

    var body: some View {
        GeometryReader { proxy in
            let target = PhotoLoading.targetSize(for: proxy.size, scale: displayScale)
            // A collection view only builds the pages near the screen, so
            // opening a photo costs the same in a library of 20 or 20,000.
            PhotoPager(count: presentation.source.count, position: $position, revision: library.revision) { index, isCurrent in
                // Each page is a little wider than the screen, so a black
                // gap shows between photos while swiping, as in Photos.
                AnyView(page(at: index, isCurrent: isCurrent, target: target).padding(.horizontal, Self.pageGap / 2))
            }
            .padding(.horizontal, -Self.pageGap / 2)
            .onChange(of: position, initial: true) { preheat(around: position, target: target) }
        }
        .ignoresSafeArea()
        .background(Color.black.ignoresSafeArea())
        .overlay(alignment: .top) {
            if !chromeHidden {
                topBar.transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if !chromeHidden {
                bottomBar.transition(.opacity)
            }
        }
        .statusBarHidden(chromeHidden)
        .environment(\.colorScheme, .dark)
        .onChange(of: position) {
            viewer.currentID = presentation.source.asset(at: position)?.localIdentifier ?? ""
        }
        .onDisappear {
            library.imageManager.stopCachingImagesForAllAssets()
        }
        .sheet(isPresented: $showingInfo) {
            if let current { PhotoInfoSheet(asset: current) }
        }
    }

    @ViewBuilder
    private func page(at index: Int, isCurrent: Bool, target: CGSize) -> some View {
        Group {
            if let asset = presentation.source.asset(at: index) {
                if asset.mediaType == .video {
                    VideoPage(asset: asset, isCurrent: isCurrent, preload: index == presentation.start, targetSize: target)
                } else {
                    PhotoPage(
                        asset: asset,
                        isCurrent: isCurrent,
                        preload: index == presentation.start,
                        targetSize: target,
                        liveEnabled: liveEnabled,
                        onTap: {
                            withAnimation(.easeInOut(duration: 0.2)) { chromeHidden.toggle() }
                        }
                    )
                }
            } else {
                Color.black
            }
        }
        // A reused cell showing another photo starts from scratch.
        .id(presentation.source.asset(at: index)?.localIdentifier ?? "\(index)")
        .environment(library)
        .environment(\.colorScheme, .dark)
    }

    /// Asks Photos to get the photos either side of this one ready, so a
    /// swipe shows a sharp image straight away.
    private func preheat(around index: Int, target: CGSize) {
        let wanted = (index - 2...index + 2)
            .filter { $0 != index }
            .compactMap { presentation.source.asset(at: $0) }
            .filter { $0.mediaType == .image }
        let wantedIDs = Set(wanted.map(\.localIdentifier))
        let cachedIDs = Set(preheated.map(\.localIdentifier))
        let options = PhotoLoading.pageOptions()
        library.imageManager.stopCachingImages(
            for: preheated.filter { !wantedIDs.contains($0.localIdentifier) },
            targetSize: target, contentMode: .aspectFit, options: options
        )
        library.imageManager.startCachingImages(
            for: wanted.filter { !cachedIDs.contains($0.localIdentifier) },
            targetSize: target, contentMode: .aspectFit, options: options
        )
        preheated = wanted
    }

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                HStack {
                    Button {
                        viewer.close()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Close")
                    Spacer()
                }

                if let date = current?.creationDate {
                    VStack(spacing: 1) {
                        Text(date, format: .dateTime.day().month(.wide).year())
                            .font(.subheadline.weight(.semibold))
                        Text(date, format: .dateTime.hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 6)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.horizontal, 64)
                }
            }

            if let current, current.mediaSubtypes.contains(.photoLive) {
                Menu {
                    Button {
                        liveEnabled = true
                    } label: {
                        Label("Live", systemImage: liveEnabled ? "checkmark" : "livephoto")
                    }
                    Button {
                        liveEnabled = false
                    } label: {
                        Label("Live Off", systemImage: liveEnabled ? "livephoto.slash" : "checkmark")
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: liveEnabled ? "livephoto" : "livephoto.slash")
                        Text(liveEnabled ? "LIVE" : "LIVE OFF")
                            .font(.caption.weight(.semibold))
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.bold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .glassEffect(.regular, in: .capsule)
                }
                .accessibilityLabel(liveEnabled ? "Live Photo, on" : "Live Photo, off")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
    }

    private var bottomBar: some View {
        HStack {
            Color.clear.frame(width: 52, height: 52)
            Spacer()
            if let current {
                GlassEffectContainer(spacing: 0) {
                    HStack(spacing: 4) {
                        Button {
                            Task { await library.setFavorite(!current.isFavorite, for: current) }
                        } label: {
                            Image(systemName: current.isFavorite ? "heart.fill" : "heart")
                                .font(.title3)
                                .frame(width: 52, height: 44)
                        }
                        .accessibilityLabel(current.isFavorite ? "Remove from favorites" : "Add to favorites")

                        Button {
                            showingInfo = true
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.title3)
                                .frame(width: 52, height: 44)
                        }
                        .accessibilityLabel("What Phophy found in this photo")
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
            }
            Spacer()
            if let current {
                Button {
                    Task {
                        // iOS asks to confirm; the photo goes to Recently Deleted.
                        if await library.delete(localIDs: [current.localIdentifier]) {
                            viewer.close()
                        }
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.title3)
                        .frame(width: 52, height: 52)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Delete")
            }
        }
        .padding(.horizontal, 20)
    }
}

/// Pages sideways through photos, as Photos does: a paging collection view
/// that builds a SwiftUI page for the cells on screen and reuses them.
private struct PhotoPager: UIViewRepresentable {
    let count: Int
    @Binding var position: Int
    let revision: Int
    let page: (_ index: Int, _ isCurrent: Bool) -> AnyView

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> PagerCollectionView {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        let view = PagerCollectionView(frame: .zero, collectionViewLayout: layout)
        view.isPagingEnabled = true
        view.showsHorizontalScrollIndicator = false
        view.contentInsetAdjustmentBehavior = .never
        view.backgroundColor = .clear
        view.register(UICollectionViewCell.self, forCellWithReuseIdentifier: Coordinator.reuseID)
        view.dataSource = context.coordinator
        view.delegate = context.coordinator
        view.page = position
        return view
    }

    func updateUIView(_ view: PagerCollectionView, context: Context) {
        let coordinator = context.coordinator
        let previous = coordinator.parent
        coordinator.parent = self
        if previous.revision != revision || previous.count != count {
            view.reloadData()
        }
        if view.page != position {
            view.page = position
            view.showPage()
        }
        // Pass the new state (which page is current, Live on or off) to the
        // pages on screen without rebuilding them.
        let visible = view.indexPathsForVisibleItems
        if !visible.isEmpty { view.reconfigureItems(at: visible) }
    }

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
        static let reuseID = "page"
        var parent: PhotoPager

        init(parent: PhotoPager) { self.parent = parent }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            parent.count
        }

        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: Self.reuseID, for: indexPath)
            let index = indexPath.item
            let isCurrent = index == parent.position
            cell.contentConfiguration = UIHostingConfiguration { parent.page(index, isCurrent) }
                .margins(.all, 0)
            return cell
        }

        func collectionView(_ collectionView: UICollectionView, layout: UICollectionViewLayout,
                            sizeForItemAt indexPath: IndexPath) -> CGSize {
            collectionView.bounds.size
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { settle(scrollView) }

        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) { settle(scrollView) }

        /// Once a swipe comes to rest, that page becomes the current one.
        private func settle(_ scrollView: UIScrollView) {
            guard let pager = scrollView as? PagerCollectionView, pager.bounds.width > 0 else { return }
            let index = Int((pager.contentOffset.x / pager.bounds.width).rounded())
            guard index >= 0, index < parent.count, index != pager.page else { return }
            pager.page = index
            parent.position = index
        }
    }
}

final class PagerCollectionView: UICollectionView {
    var page = 0
    private var laidOutSize: CGSize = .zero

    override func layoutSubviews() {
        if bounds.size != laidOutSize, bounds.width > 0 {
            // New size (first layout or rotation): resize pages and stay on
            // the same photo.
            laidOutSize = bounds.size
            collectionViewLayout.invalidateLayout()
            showPage()
        }
        super.layoutSubviews()
    }

    func showPage() {
        guard bounds.width > 0 else { return }
        setContentOffset(CGPoint(x: CGFloat(page) * bounds.width, y: 0), animated: false)
    }
}

/// One photo page. It starts with the thumbnail Photos already has, swaps
/// in a screen-sized image (usually preloaded), and asks for a larger one
/// only when you zoom in. A Live Photo's motion loads once its page is on
/// screen.
private struct PhotoPage: View {
    let asset: PHAsset
    let isCurrent: Bool
    let targetSize: CGSize
    let liveEnabled: Bool
    let onTap: () -> Void

    @Environment(PhotoLibrary.self) private var library
    @State private var image: UIImage?
    @State private var livePhoto: PHLivePhoto?
    @State private var progress: Double?
    @State private var wantsFullSize = false

    init(asset: PHAsset, isCurrent: Bool, preload: Bool, targetSize: CGSize, liveEnabled: Bool, onTap: @escaping () -> Void) {
        self.asset = asset
        self.isCurrent = isCurrent
        self.targetSize = targetSize
        self.liveEnabled = liveEnabled
        self.onTap = onTap
        _image = State(initialValue: preload ? PhotoLoading.instantImage(for: asset) : nil)
    }

    private struct LiveKey: Equatable {
        let id: String
        let isCurrent: Bool
    }

    var body: some View {
        ZStack {
            ZoomableImage(
                image: image,
                livePhoto: liveEnabled ? livePhoto : nil,
                isCurrent: isCurrent,
                onTap: onTap,
                onZoomIn: { wantsFullSize = true }
            )
            if image == nil {
                ProgressView()
            }
            if let progress, progress < 1 {
                ProgressView("Downloading from iCloud", value: progress)
                    .padding()
                    .glassEffect(.regular, in: .rect(cornerRadius: 20))
                    .padding(40)
            }
        }
        .task(id: asset.localIdentifier) {
            if image == nil { image = PhotoLoading.instantImage(for: asset) }
            load(targetSize)
        }
        .task(id: LiveKey(id: asset.localIdentifier, isCurrent: isCurrent)) {
            if isCurrent, livePhoto == nil, asset.mediaSubtypes.contains(.photoLive) { loadLivePhoto() }
        }
        .onChange(of: wantsFullSize) {
            if wantsFullSize { load(CGSize(width: targetSize.width * 2.5, height: targetSize.height * 2.5)) }
        }
        .accessibilityElement()
        .accessibilityLabel(asset.creationDate.map { "Photo, \($0.formatted(date: .long, time: .shortened))" } ?? "Photo")
        .accessibilityAddTraits(.isImage)
    }

    private func load(_ size: CGSize) {
        let options = PhotoLoading.pageOptions()
        options.progressHandler = { value, _, _, _ in
            Task { @MainActor in progress = value }
        }
        library.imageManager.requestImage(
            for: asset, targetSize: size, contentMode: .aspectFit, options: options
        ) { result, info in
            // Never swap a sharper image for a blurrier one.
            if let result, result.size.width >= (image?.size.width ?? 0) * 0.95 { image = result }
            if (info?[PHImageResultIsDegradedKey] as? Bool) != true { progress = nil }
        }
    }

    private func loadLivePhoto() {
        let options = PHLivePhotoRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        library.imageManager.requestLivePhoto(
            for: asset, targetSize: targetSize, contentMode: .aspectFit, options: options
        ) { live, _ in
            if let live { livePhoto = live }
        }
    }
}

/// A video page: the poster frame at once, then a player that starts when
/// the page is on screen and pauses when you swipe away.
private struct VideoPage: View {
    let asset: PHAsset
    let isCurrent: Bool
    let targetSize: CGSize

    @State private var poster: UIImage?
    @State private var player: AVPlayer?
    @State private var failed = false
    @State private var ready = false

    init(asset: PHAsset, isCurrent: Bool, preload: Bool, targetSize: CGSize) {
        self.asset = asset
        self.isCurrent = isCurrent
        self.targetSize = targetSize
        _poster = State(initialValue: preload ? PhotoLoading.instantImage(for: asset) : nil)
    }

    var body: some View {
        ZStack {
            Color.black
            if let player {
                // Kept clear of the viewer's own top and bottom bars, so the
                // player's controls and timeline are never covered.
                VideoPlayer(player: player)
                    .padding(.top, 120)
                    .padding(.bottom, 110)
            }
            if let poster, !ready {
                Image(uiImage: poster)
                    .resizable()
                    .scaledToFit()
                    .allowsHitTesting(false)
            }
            if player == nil && !failed {
                ProgressView()
            }
            if failed {
                ContentUnavailableView("Video not available", systemImage: "video.slash")
            }
        }
        .task(id: asset.localIdentifier) {
            if poster == nil { poster = PhotoLoading.instantImage(for: asset) }
            guard player == nil else { return }
            guard let item = await requestPlayerItem(for: asset) else {
                failed = true
                return
            }
            let player = AVPlayer(playerItem: item)
            self.player = player
            if isCurrent { player.play() }
            // Hide the poster once the first frame is on screen.
            try? await Task.sleep(for: .milliseconds(250))
            ready = true
        }
        .onChange(of: isCurrent) {
            if isCurrent { player?.play() } else { player?.pause() }
        }
        .onDisappear { player?.pause() }
        .accessibilityLabel("Video")
    }
}

/// Fetches a playable item for a video, downloading from iCloud if needed.
nonisolated func requestPlayerItem(for asset: PHAsset) async -> AVPlayerItem? {
    let options = PHVideoRequestOptions()
    options.isNetworkAccessAllowed = true
    options.deliveryMode = .automatic
    return await withCheckedContinuation { continuation in
        PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
            continuation.resume(returning: item)
        }
    }
}

/// UIScrollView-based zooming, as in Photos: pinch, double-tap, and panning
/// around a zoomed photo. A Live Photo view sits over the still image and
/// zooms with it; press and hold to play it.
private struct ZoomableImage: UIViewRepresentable {
    let image: UIImage?
    let livePhoto: PHLivePhoto?
    let isCurrent: Bool
    let onTap: () -> Void
    let onZoomIn: () -> Void

    func makeUIView(context: Context) -> ZoomScrollView {
        let view = ZoomScrollView()
        view.image = image
        return view
    }

    func updateUIView(_ view: ZoomScrollView, context: Context) {
        view.onSingleTap = onTap
        view.onZoomIn = onZoomIn
        if view.image !== image { view.image = image }
        if view.livePhoto !== livePhoto { view.livePhoto = livePhoto }
        if view.isCurrent != isCurrent { view.isCurrent = isCurrent }
    }
}

final class ZoomScrollView: UIScrollView, UIScrollViewDelegate {
    var onSingleTap: (() -> Void)?
    var onZoomIn: (() -> Void)?

    private let content = UIView()
    private let imageView = UIImageView()
    private let livePhotoView = PHLivePhotoView()
    private var fittedForSize: CGSize = .zero
    private var askedForFullSize = false

    var image: UIImage? {
        didSet {
            imageView.image = image
            // A sharper copy of the same photo keeps the zoom and position;
            // only a different shape needs a fresh fit.
            if abs(Self.ratio(oldValue?.size) - Self.ratio(image?.size)) > 0.01 {
                refit()
            }
        }
    }

    var livePhoto: PHLivePhoto? {
        didSet {
            livePhotoView.livePhoto = livePhoto
            livePhotoView.isHidden = livePhoto == nil
            if image == nil, livePhoto != nil { refit() }
            // A short hint of the motion, as Photos does when a Live Photo appears.
            if livePhoto != nil, oldValue == nil, isCurrent { livePhotoView.startPlayback(with: .hint) }
        }
    }

    var isCurrent = false {
        didSet {
            if isCurrent, livePhoto != nil {
                livePhotoView.startPlayback(with: .hint)
            } else if !isCurrent {
                livePhotoView.stopPlayback()
                if zoomScale > minimumZoomScale { setZoomScale(minimumZoomScale, animated: false) }
            }
        }
    }

    init() {
        super.init(frame: .zero)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 5
        bouncesZoom = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        decelerationRate = .fast
        backgroundColor = .clear
        imageView.contentMode = .scaleAspectFit
        imageView.layer.minificationFilter = .trilinear
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        livePhotoView.contentMode = .scaleAspectFit
        livePhotoView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        livePhotoView.isHidden = true
        content.addSubview(imageView)
        content.addSubview(livePhotoView)
        addSubview(content)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        singleTap.require(toFail: doubleTap)
        addGestureRecognizer(singleTap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private static func ratio(_ size: CGSize?) -> CGFloat {
        guard let size, size.height > 0 else { return 0 }
        return size.width / size.height
    }

    private var contentAspectSize: CGSize? {
        if let size = image?.size, size.width > 0 { return size }
        if let size = livePhoto?.size, size.width > 0 { return size }
        return nil
    }

    private func refit() {
        setZoomScale(1, animated: false)
        fittedForSize = .zero
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != fittedForSize, zoomScale <= minimumZoomScale + 0.001,
           let size = contentAspectSize, bounds.width > 0 {
            let scale = min(bounds.width / size.width, bounds.height / size.height)
            let fitted = CGSize(width: size.width * scale, height: size.height * scale)
            content.frame = CGRect(origin: .zero, size: fitted)
            imageView.frame = content.bounds
            livePhotoView.frame = content.bounds
            contentSize = fitted
            fittedForSize = bounds.size
        }
        centerContent()
    }

    private func centerContent() {
        let horizontal = max(0, (bounds.width - contentSize.width) / 2)
        let vertical = max(0, (bounds.height - contentSize.height) / 2)
        let insets = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
        if contentInset != insets { contentInset = insets }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { content }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerContent()
        if zoomScale > 1.3, !askedForFullSize {
            askedForFullSize = true
            onZoomIn?()
        }
    }

    @objc private func handleSingleTap() { onSingleTap?() }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale + 0.01 {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            let point = recognizer.location(in: content)
            let scale: CGFloat = 2.5
            let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
            zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                            width: size.width, height: size.height), animated: true)
        }
    }
}

/// What the index found in a photo.
struct PhotoInfoSheet: View {
    let asset: PHAsset

    var body: some View {
        let info = try? IndexStore.shared.info(for: asset.localIdentifier)
        NavigationStack {
            List {
                if let info {
                    Section("Shows") {
                        Text(info.labels.isEmpty ? "No labels" : info.labels.joined(separator: " · "))
                    }
                    Section("Text in photo") {
                        Text(info.text.isEmpty ? "No text found" : info.text)
                            .textSelection(.enabled)
                    }
                } else {
                    Text("This photo has not been indexed yet.")
                }
            }
            .navigationTitle(asset.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? "Photo")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}
