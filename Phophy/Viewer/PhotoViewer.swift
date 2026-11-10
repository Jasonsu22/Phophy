import Photos
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

/// Full-screen viewer: swipe sideways for the next or previous photo, pinch
/// or double-tap to zoom, swipe down to close, tap to hide the controls.
struct PhotoViewer: View {
    let presentation: PhotoViewerModel.Presentation

    @Environment(PhotoViewerModel.self) private var viewer
    @Environment(PhotoLibrary.self) private var library
    @State private var position: Int
    @State private var chromeHidden = false
    @State private var showingInfo = false

    init(presentation: PhotoViewerModel.Presentation) {
        self.presentation = presentation
        _position = State(initialValue: presentation.start)
    }

    private var current: PHAsset? {
        _ = library.revision
        return presentation.source.asset(at: position)
    }

    var body: some View {
        TabView(selection: $position) {
            ForEach(0..<presentation.source.count, id: \.self) { index in
                Group {
                    if let asset = presentation.source.asset(at: index) {
                        ZoomablePhotoPage(
                            asset: asset,
                            preload: index == presentation.start,
                            onTap: {
                                withAnimation(.easeInOut(duration: 0.2)) { chromeHidden.toggle() }
                            }
                        )
                    } else {
                        Color.black
                    }
                }
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea()
        .background(Color.black.ignoresSafeArea())
        .overlay(alignment: .top) {
            if !chromeHidden {
                topBar.transition(.opacity)
            }
        }
        .statusBarHidden(chromeHidden)
        .environment(\.colorScheme, .dark)
        .onChange(of: position) {
            viewer.currentID = presentation.source.asset(at: position)?.localIdentifier ?? ""
        }
        .sheet(isPresented: $showingInfo) {
            if let current { PhotoInfoSheet(asset: current) }
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                viewer.close()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Close")

            Spacer()

            if let date = current?.creationDate {
                VStack(spacing: 1) {
                    Text(date, format: .dateTime.day().month(.abbreviated).year())
                        .font(.subheadline.weight(.semibold))
                    Text(presentation.source.count > 1
                        ? "\(date.formatted(date: .omitted, time: .shortened)) · \(position + 1) of \(presentation.source.count)"
                        : date.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .glassEffect(.regular, in: .capsule)
            }

            Spacer()

            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Button {
                        showingInfo = true
                    } label: {
                        Image(systemName: "info")
                            .font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("What Phophy found in this photo")

                    if let current {
                        Button {
                            Task { await library.setFavorite(!current.isFavorite, for: current) }
                        } label: {
                            Image(systemName: current.isFavorite ? "heart.fill" : "heart")
                                .font(.body.weight(.semibold))
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .accessibilityLabel(current.isFavorite ? "Remove from favorites" : "Add to favorites")
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }
}

/// One page of the viewer. The photo that was tapped is loaded before the
/// first frame, so the zoom transition animates the real photo instead of an
/// empty page; a sharper version replaces it when ready.
private struct ZoomablePhotoPage: View {
    let asset: PHAsset
    let onTap: () -> Void

    @Environment(PhotoLibrary.self) private var library
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var progress: Double?

    init(asset: PHAsset, preload: Bool, onTap: @escaping () -> Void) {
        self.asset = asset
        self.onTap = onTap
        _image = State(initialValue: preload ? Self.quickImage(for: asset) : nil)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ZoomableImage(image: image, onTap: onTap)
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
                load(size: proxy.size)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(asset.creationDate.map { "Photo, \($0.formatted(date: .long, time: .shortened))" } ?? "Photo")
        .accessibilityAddTraits(.isImage)
    }

    /// A screen-sized copy straight from the device, without waiting.
    private static func quickImage(for asset: PHAsset) -> UIImage? {
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        var result: UIImage?
        PHImageManager.default().requestImage(
            for: asset, targetSize: CGSize(width: 1400, height: 1400), contentMode: .aspectFit, options: options
        ) { image, _ in result = image }
        return result
    }

    private func load(size: CGSize) {
        let options = PHImageRequestOptions()
        options.deliveryMode = image == nil ? .opportunistic : .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.progressHandler = { value, _, _, _ in
            Task { @MainActor in progress = value }
        }
        // Sharper than the screen, so zooming in stays crisp.
        let target = CGSize(width: size.width * displayScale * 1.6, height: size.height * displayScale * 1.6)
        library.imageManager.requestImage(
            for: asset, targetSize: target, contentMode: .aspectFit, options: options
        ) { result, info in
            if let result { image = result }
            if (info?[PHImageResultIsDegradedKey] as? Bool) != true { progress = nil }
        }
    }
}

/// UIScrollView-based zooming, as in Photos: pinch, double-tap, and panning
/// around a zoomed photo. SwiftUI's own scroll view cannot zoom.
private struct ZoomableImage: UIViewRepresentable {
    let image: UIImage?
    let onTap: () -> Void

    func makeUIView(context: Context) -> ZoomScrollView {
        let view = ZoomScrollView()
        view.image = image
        return view
    }

    func updateUIView(_ view: ZoomScrollView, context: Context) {
        view.onSingleTap = onTap
        if view.image !== image { view.image = image }
    }
}

final class ZoomScrollView: UIScrollView, UIScrollViewDelegate {
    var onSingleTap: (() -> Void)?

    private let imageView = UIImageView()
    private var fittedForSize: CGSize = .zero

    var image: UIImage? {
        didSet {
            imageView.image = image
            // A sharper copy of the same photo keeps the zoom and position;
            // only a different shape needs a fresh fit.
            let oldRatio = oldValue.map { $0.size.width / max($0.size.height, 1) }
            let newRatio = image.map { $0.size.width / max($0.size.height, 1) }
            if oldRatio == nil || newRatio == nil || abs((oldRatio ?? 0) - (newRatio ?? 0)) > 0.01 {
                setZoomScale(1, animated: false)
                fittedForSize = .zero
                setNeedsLayout()
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
        addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        singleTap.require(toFail: doubleTap)
        addGestureRecognizer(singleTap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != fittedForSize, zoomScale <= minimumZoomScale + 0.001,
           let size = imageView.image?.size, size.width > 0, size.height > 0, bounds.width > 0 {
            let scale = min(bounds.width / size.width, bounds.height / size.height)
            let fitted = CGSize(width: size.width * scale, height: size.height * scale)
            imageView.frame = CGRect(origin: .zero, size: fitted)
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

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerContent() }

    @objc private func handleSingleTap() { onSingleTap?() }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale + 0.01 {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            let point = recognizer.location(in: imageView)
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
