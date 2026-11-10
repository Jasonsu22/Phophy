import Photos
import SwiftUI

/// Home screen: the newest photos, quick filters, and the way into everything else.
struct LibraryView: View {
    @Environment(PhotoLibrary.self) private var library
    @Environment(\.openURL) private var openURL

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 4)
    private let chipFilters: [PhotoFilter] = [.favorites, .screenshots, .videos]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    content
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background { AmbientBackground() }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case let .grid(filter): PhotoGridView(filter: filter)
                case let .photo(localIdentifier): PhotoDetailView(localIdentifier: localIdentifier)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch library.status {
        case .authorized, .limited:
            chips
            if library.recents.isEmpty {
                ContentUnavailableView(
                    "No photos yet",
                    systemImage: "photo.on.rectangle",
                    description: Text("Photos you take will appear here.")
                )
            } else {
                recents
            }
            if library.status == .limited {
                Text("Phophy can only see the photos you selected. Change this in Settings to see your whole library.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .notDetermined:
            AccessCard(
                title: "See your photos here",
                message: "Phophy reads your library on this device. Nothing is uploaded.",
                buttonTitle: "Allow photo access"
            ) {
                Task { await library.requestAccess() }
            }
        default:
            AccessCard(
                title: "Photo access is off",
                message: "Turn on photo access for Phophy in Settings to browse and search your library.",
                buttonTitle: "Open Settings"
            ) {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Library")
                    .font(.largeTitle.bold())
            }
            Spacer()
            Button {
            } label: {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Open assistant")
        }
    }

    private var chips: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(chipFilters) { filter in
                        NavigationLink(value: Route.grid(filter)) {
                            HStack(spacing: 6) {
                                Text(filter.title).fontWeight(.semibold)
                                Text(library.counts[filter] ?? 0, format: .number)
                                    .foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.glass)
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    private var recents: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recents").font(.title3.bold())
                Spacer()
                NavigationLink(value: Route.grid(.all)) {
                    Text("See all \(library.counts[.all] ?? 0, format: .number)")
                        .font(.subheadline.weight(.semibold))
                }
            }
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(library.recents, id: \.localIdentifier) { asset in
                    NavigationLink(value: Route.photo(localIdentifier: asset.localIdentifier)) {
                        AssetThumbnail(asset: asset)
                            .frame(height: 84)
                    }
                    .buttonStyle(.plain)
                }
            }
            .clipShape(.rect(cornerRadius: 22))
        }
    }
}

/// Glass card that explains a permission state and offers the one next step.
struct AccessCard: View {
    let title: String
    let message: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 30))
                .accessibilityHidden(true)
            Text(title).font(.title3.bold())
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button(buttonTitle, action: action)
                .buttonStyle(.glassProminent)
                .tint(.white)
                .foregroundStyle(Color(hex: 0x131A44))
                .fontWeight(.bold)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }
}
