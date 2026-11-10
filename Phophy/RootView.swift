import SwiftUI

/// The app's top level: a native tab bar (Liquid Glass on iOS 26+) with a
/// separate search tab and an "ask" bar floating above it.
struct RootView: View {
    @State private var library = PhotoLibrary()
    @State private var indexStatus = IndexStatus()
    @State private var collections = CollectionsModel()

    /// What decides when collections are recomputed.
    private struct CollectionsKey: Equatable {
        let indexed: Int
        let total: Int
        let isRunning: Bool
    }

    var body: some View {
        TabView {
            Tab("Library", systemImage: "photo.on.rectangle") {
                LibraryView()
            }
            Tab("Collections", systemImage: "square.stack") {
                CollectionsView()
            }
            Tab("Study", systemImage: "text.book.closed") {
                ComingSoonView(
                    title: "Study",
                    systemImage: "text.book.closed",
                    message: "Lecture photos turned into notes and flashcards."
                )
            }
            Tab(role: .search) {
                SearchView()
            }
        }
        .tabViewBottomAccessory {
            AskBar()
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(.white)
        .environment(library)
        .environment(indexStatus)
        .environment(collections)
        .task(id: CollectionsKey(indexed: indexStatus.indexed, total: indexStatus.total, isRunning: indexStatus.isRunning)) {
            guard library.hasAccess, indexStatus.total > 0 else { return }
            // Recompute when indexing finishes, and every 100 photos while it runs.
            guard !indexStatus.isRunning || indexStatus.indexed % 100 == 0 else { return }
            await collections.refresh()
        }
        .task { library.start() }
        .onChange(of: library.revision, initial: true) {
            guard library.hasAccess else { return }
            // Detached so that a later library change cannot cancel work in progress.
            let status = indexStatus
            Task.detached(priority: .utility) {
                await PhotoIndexer.shared.run(status: status)
            }
        }
    }
}

/// Entry point to the agent. A button for now; becomes a real input in Phase 4.
struct AskBar: View {
    var body: some View {
        Button {
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                Text("Ask about your photos")
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "mic")
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ask about your photos")
    }
}

struct ComingSoonView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
            }
            .navigationTitle(title)
        }
    }
}

#Preview {
    RootView()
        .preferredColorScheme(.dark)
}
