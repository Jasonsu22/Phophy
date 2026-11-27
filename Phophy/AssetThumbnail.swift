import Photos
import SwiftUI

/// A square-cropped thumbnail for one asset. Loads a fast low-quality image
/// first, then the sharp one; fetches from iCloud if the phone doesn't have it.
struct AssetThumbnail: View {
    let asset: PHAsset

    @Environment(PhotoLibrary.self) private var library
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID?
    /// The tile size the current image was asked for.
    @State private var loadedSide: CGFloat = 0
    @State private var sharpen: Task<Void, Never>?

    private var isTall: Bool { asset.pixelHeight * 10 > asset.pixelWidth * 16 }

    var body: some View {
        GeometryReader { proxy in
            let side = max(proxy.size.width, proxy.size.height)
            ZStack {
                Rectangle().fill(.white.opacity(0.08))
                if let image = image ?? ThumbnailMemory.image(for: asset) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            // A screenshot or other tall page shows its top, where the title is.
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: isTall ? .top : .center)
            .clipped()
            .contentShape(.rect)
            .overlay(alignment: .bottomTrailing) { videoBadge }
            .onAppear { load(side: side) }
            // Grid zoomed in: once the tile stops growing, load a sharper
            // copy. The current image stays up meanwhile, so nothing flashes.
            .onChange(of: side) { _, side in
                sharpen?.cancel()
                guard side > loadedSide * 1.15 else { return }
                sharpen = Task {
                    try? await Task.sleep(for: .milliseconds(120))
                    guard !Task.isCancelled else { return }
                    load(side: side)
                }
            }
            .onDisappear { sharpen?.cancel(); cancel() }
            // Another photo in a reused cell, or this photo edited (an edit
            // keeps the ID, so the library's edit mark tells).
            .onChange(of: library.contentKey(asset)) {
                image = nil
                loadedSide = 0
                load(side: side)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isImage)
    }

    @ViewBuilder
    private var videoBadge: some View {
        if asset.mediaType == .video {
            Text(Duration.seconds(asset.duration), format: .time(pattern: .minuteSecond))
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.black.opacity(0.55), in: .capsule)
                .padding(4)
        }
    }

    private var accessibilityText: String {
        let kind = asset.mediaType == .video ? "Video" : "Photo"
        guard let date = asset.creationDate else { return kind }
        return "\(kind), \(date.formatted(date: .long, time: .omitted))"
    }

    /// Shared with the grid's prefetching, so prefetched images are the ones
    /// the thumbnails ask for.
    nonisolated static func requestOptions() -> PHImageRequestOptions {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        return options
    }

    private func load(side: CGFloat) {
        cancel()
        let options = Self.requestOptions()
        let pixels = side * displayScale
        let hadImage = image != nil || ThumbnailMemory.image(for: asset) != nil
        loadedSide = side
        requestID = library.imageManager.requestImage(
            for: asset,
            targetSize: CGSize(width: pixels, height: pixels),
            contentMode: .aspectFill,
            options: options
        ) { result, info in
            guard let result else { return }
            // Swapping a sharp tile for a blurry stand-in is the flash: when
            // there's already a picture, wait for the sharp one.
            let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            if degraded && hadImage { return }
            image = result
            if !degraded { ThumbnailMemory.remember(result, for: asset) }
        }
    }

    private func cancel() {
        if let requestID {
            library.imageManager.cancelImageRequest(requestID)
        }
        requestID = nil
    }
}
