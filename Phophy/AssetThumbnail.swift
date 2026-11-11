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
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .contentShape(.rect)
            .overlay(alignment: .bottomTrailing) { videoBadge }
            .onAppear { load(side: side) }
            .onDisappear { cancel() }
            .onChange(of: asset.localIdentifier) {
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
