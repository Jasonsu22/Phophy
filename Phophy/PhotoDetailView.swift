import Photos
import SwiftUI

/// One photo, full screen, with its date and a favorite toggle.
struct PhotoDetailView: View {
    let localIdentifier: String

    @Environment(PhotoLibrary.self) private var library
    @Environment(\.displayScale) private var displayScale
    @State private var asset: PHAsset?
    @State private var image: UIImage?
    @State private var downloadProgress: Double?
    @State private var isShowingInfo = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.ignoresSafeArea()
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .accessibilityLabel(title)
                } else if asset == nil {
                    ContentUnavailableView("Photo not available", systemImage: "photo")
                } else {
                    ProgressView()
                }
                if let downloadProgress, downloadProgress < 1 {
                    ProgressView("Downloading from iCloud", value: downloadProgress)
                        .padding()
                        .glassEffect(.regular, in: .rect(cornerRadius: 20))
                        .padding(40)
                }
            }
            .task(id: library.revision) {
                asset = library.asset(withLocalIdentifier: localIdentifier)
                if image == nil { loadImage(fitting: proxy.size) }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $isShowingInfo) { infoSheet }
        .toolbar {
            if let asset {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .accessibilityLabel("What Phophy found in this photo")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await library.setFavorite(!asset.isFavorite, for: asset) }
                    } label: {
                        Image(systemName: asset.isFavorite ? "heart.fill" : "heart")
                    }
                    .accessibilityLabel(asset.isFavorite ? "Remove from favorites" : "Add to favorites")
                }
            }
        }
    }

    private var infoSheet: some View {
        let info = try? IndexStore.shared.info(for: localIdentifier)
        return NavigationStack {
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
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private var title: String {
        asset?.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? "Photo"
    }

    private func loadImage(fitting size: CGSize) {
        guard let asset else { return }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        options.progressHandler = { progress, _, _, _ in
            Task { @MainActor in downloadProgress = progress }
        }
        let target = CGSize(width: size.width * displayScale, height: size.height * displayScale)
        library.imageManager.requestImage(
            for: asset,
            targetSize: target,
            contentMode: .aspectFit,
            options: options
        ) { result, info in
            if let result { image = result }
            let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            if !isDegraded { downloadProgress = nil }
        }
    }
}
