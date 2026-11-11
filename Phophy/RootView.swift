import SwiftUI

/// The app's top level: a native tab bar (Liquid Glass on iOS 26+), the ask
/// bar floating above it, the assistant's conversation over everything, and
/// the full-screen photo viewer on top.
struct RootView: View {
    @State private var library = PhotoLibrary()
    @State private var indexStatus = IndexStatus()
    @State private var collections = CollectionsModel()
    @State private var assistant = AssistantModel()
    @State private var study = StudyModel()
    @State private var viewer = PhotoViewerModel()
    @FocusState private var askFocused: Bool
    @Namespace private var photoZoom

    /// How far the ask bar sits above the bottom safe area while the tab bar shows.
    private let askBarLift: CGFloat = 62
    private let chatAnimation = Animation.smooth(duration: 0.38)

    /// What decides when collections are recomputed.
    private struct CollectionsKey: Equatable {
        let indexed: Int
        let total: Int
        let isRunning: Bool
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView {
                Tab("Library", systemImage: "photo.on.rectangle") {
                    LibraryView().belowAskBar(chatOpen: assistant.isPresented)
                }
                Tab("Collections", systemImage: "square.stack") {
                    CollectionsView().belowAskBar(chatOpen: assistant.isPresented)
                }
                Tab("Study", systemImage: "text.book.closed") {
                    StudyView().belowAskBar(chatOpen: assistant.isPresented)
                }
                Tab(role: .search) {
                    SearchView().belowAskBar(chatOpen: assistant.isPresented)
                }
            }
            .tint(.white)

            if assistant.isPresented {
                // The app stays visible, softly blurred, behind the conversation.
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Color.black.opacity(0.2))
                    .ignoresSafeArea()
                    .onTapGesture { askFocused = false }
                    .transition(.opacity)

                AssistantPanel(onClose: closeChat, onSend: send)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottom)))
            }

            AskBar(isFocused: $askFocused, onSend: send)
                .padding(.horizontal, assistant.isPresented ? 12 : 20)
                .padding(.bottom, assistant.isPresented ? 8 : askBarLift)
                // Closed, the bar must not jump above the keyboard of another field.
                .ignoresSafeArea(assistant.isPresented ? [] : .keyboard)
        }
        .fullScreenCover(item: $viewer.presentation) { presentation in
            PhotoViewer(presentation: presentation)
                .navigationTransition(.zoom(sourceID: viewer.currentID, in: photoZoom))
                .environment(library)
                .environment(viewer)
                .environment(assistant)
        }
        .environment(\.photoZoomNamespace, photoZoom)
        .environment(library)
        .environment(indexStatus)
        .environment(collections)
        .environment(assistant)
        .environment(study)
        .environment(viewer)
        .onChange(of: askFocused) {
            // Tapping the ask bar opens the chat in place, ready to type.
            if askFocused && !assistant.isPresented {
                withAnimation(chatAnimation) { assistant.open() }
            }
        }
        .onChange(of: viewer.presentation?.id) {
            // A photo opening takes the whole screen: put any keyboard away,
            // whether it belongs to the ask bar or to the Search field.
            if viewer.presentation != nil {
                askFocused = false
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        }
        .onChange(of: collections.snapshot, initial: true) {
            study.refresh(slideIDs: collections.ids(for: .slides))
        }
        .task(id: CollectionsKey(indexed: indexStatus.indexed, total: indexStatus.total, isRunning: indexStatus.isRunning)) {
            guard library.hasAccess, indexStatus.total > 0 else { return }
            // Recompute when indexing finishes, and every 100 photos while it runs.
            guard !indexStatus.isRunning || indexStatus.indexed % 100 == 0 else { return }
            await collections.refresh()
        }
        .task { library.start() }
        #if DEBUG
        .task {
            // Testing aid: `-PhophyAsk "question"` asks the assistant on launch.
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: "-PhophyAsk"), index + 1 < arguments.count {
                try? await Task.sleep(for: .seconds(3))
                send(arguments[index + 1])
            }
        }
        #endif
        .onChange(of: library.revision, initial: true) {
            guard library.hasAccess else { return }
            // Detached so that a later library change cannot cancel work in progress.
            let status = indexStatus
            Task.detached(priority: .utility) {
                await PhotoIndexer.shared.run(status: status)
            }
        }
    }

    private func closeChat() {
        askFocused = false
        withAnimation(chatAnimation) { assistant.close() }
    }

    private func send(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !assistant.isWorking else { return }
        assistant.draft = ""
        if !assistant.isPresented { withAnimation(chatAnimation) { assistant.open() } }
        var categories: [String: PhotoCategory] = [:]
        for result in collections.snapshot.categories {
            for id in result.localIDs { categories[id] = result.category }
        }
        let indexed = indexStatus.indexed
        Task { await assistant.send(text, indexedCount: indexed, categories: categories) }
    }
}

private extension View {
    /// Lets the tab bar slide away while the chat is open.
    func belowAskBar(chatOpen: Bool) -> some View {
        toolbarVisibility(chatOpen ? .hidden : .visible, for: .tabBar)
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
