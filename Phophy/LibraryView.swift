import Photos
import SwiftUI

/// Home screen: the newest photos, quick filters, and the way into everything else.
struct LibraryView: View {
    @Environment(PhotoLibrary.self) private var library
    @Environment(\.openURL) private var openURL
    @State private var isShowingSettings = false
    @Environment(AssistantModel.self) private var assistant
    @Environment(StudyModel.self) private var study

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
            .photoDestinations()
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
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
            if let session = study.sessions.first {
                NavigationLink(value: Route.lecture(session.id)) {
                    LatestLectureCard(session: session, covers: study.covers[session.id] ?? [], digest: study.digests[session.id])
                }
                .buttonStyle(.plain)
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
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        withAnimation(.smooth(duration: 0.38)) { assistant.open() }
                    } label: {
                        Image(systemName: "sparkles")
                            .font(.title3)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Open assistant")

                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.title3)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Settings")
                }
            }
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
                ForEach(Array(library.recents.enumerated()), id: \.element.localIdentifier) { index, asset in
                    AssetThumbnail(asset: asset)
                        .frame(height: 84)
                        // Page through the library in Photos order: swiping left goes to newer photos.
                        .opensInViewer(.fetch(library.fetch(.all, oldestFirst: true)), at: (library.counts[.all] ?? 0) - 1 - index, id: asset.localIdentifier)
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

/// The newest lecture, offered on the home screen.
private struct LatestLectureCard: View {
    let session: LectureSession
    let covers: [PHAsset]
    let digest: LectureDigest?

    var body: some View {
        HStack(spacing: 14) {
            SlideStack(assets: covers)
            VStack(alignment: .leading, spacing: 3) {
                Text(digest == nil ? "LATEST LECTURE" : "NOTES READY")
                    .font(.caption.weight(.bold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                Text(digest?.title ?? session.fallbackTitle)
                    .font(.headline)
                    .lineLimit(2)
                Text(digest == nil ? "\(session.slideCount) · make notes" : "\(session.slideCount) → 1 page of notes")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Text(digest == nil ? "Open" : "Read")
                .fontWeight(.bold)
                .foregroundStyle(Color(hex: 0x131A44))
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(.white, in: .capsule)
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .accessibilityElement(children: .combine)
    }
}
