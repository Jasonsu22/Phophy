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

    private var isTall: Bool { asset.pixelHeight * 10 > asset.pixelWidth * 16 }

    var body: some View {
        GeometryReader { proxy in
            let side = max(proxy.size.width, proxy.size.height)
            ZStack {
                Rectangle().fill(.white.opacity(0.08))
                if let image {
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
            // Grid zoomed in: load a sharper copy for the bigger tile.
            .onChange(of: side) { load(side: side) }
            .onDisappear { cancel() }
            // Another photo in a reused cell, or this photo edited (an edit
            // keeps the ID, so the library's edit mark tells).
            .onChange(of: library.contentKey(asset)) {
                image = nil
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
        requestID = library.imageManager.requestImage(
            for: asset,
            targetSize: CGSize(width: pixels, height: pixels),
            contentMode: .aspectFill,
            options: options
        ) { result, _ in
            if let result { image = result }
        }
    }

    private func cancel() {
        if let requestID {
            library.imageManager.cancelImageRequest(requestID)
        }
        requestID = nil
    }
}
