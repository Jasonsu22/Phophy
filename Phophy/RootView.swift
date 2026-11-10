import SwiftUI

/// The app's top level: a native tab bar (Liquid Glass on iOS 26+) with a
/// separate search tab and an "ask" bar floating above it.
struct RootView: View {
    @State private var library = PhotoLibrary()

    var body: some View {
        TabView {
            Tab("Library", systemImage: "photo.on.rectangle") {
                LibraryView()
            }
            Tab("Collections", systemImage: "square.stack") {
                ComingSoonView(
                    title: "Collections",
                    systemImage: "square.stack",
                    message: "Albums the agent sorts for you: slides, receipts, screenshots, people and places."
                )
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
        .task { library.start() }
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

struct SearchView: View {
    @State private var query = ""

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                ContentUnavailableView(
                    "Describe a photo",
                    systemImage: "magnifyingglass",
                    description: Text("Try “the whiteboard from October”. Search arrives in Phase 2.")
                )
            }
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Describe a photo")
        }
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
