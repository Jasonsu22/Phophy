import SwiftUI

/// The app's top level: a native tab bar (Liquid Glass on iOS 26+), the ask
/// bar floating above it, the assistant's conversation over everything, and
/// the full-screen photo viewer on top.
struct RootView: View {
    @State private var library = PhotoLibrary()
    @State private var indexStatus = IndexStatus()
    @State private var describeStatus = DescribeStatus()
    @Environment(\.scenePhase) private var scenePhase
    @State private var collections = CollectionsModel()
    @State private var assistant = AssistantModel()
    @State private var study = StudyModel()
    @State private var viewer = PhotoViewerModel()
    @FocusState private var askFocused: Bool
    @Namespace private var photoZoom

    /// How far the ask bar sits above the bottom safe area while the tab bar shows.
    private let askBarLift: CGFloat = 62
    private let chatAnimation = Animation.smooth(duration: 0.38)
    @State private var keyboardShown = false
    @State private var tab = "library"
    /// The keyboard is up for a field other than the ask bar.
    private var otherKeyboard: Bool { keyboardShown && !askFocused && !assistant.isPresented }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $tab) {
                Tab("Library", systemImage: "photo.on.rectangle", value: "library") {
                    LibraryView().belowAskBar(chatOpen: assistant.isPresented)
                }
                Tab("Collections", systemImage: "square.stack", value: "collections") {
                    CollectionsView().belowAskBar(chatOpen: assistant.isPresented)
                }
                Tab("Study", systemImage: "text.book.closed", value: "study") {
                    StudyView().belowAskBar(chatOpen: assistant.isPresented)
                }
                Tab("Settings", systemImage: "gearshape", value: "settings") {
                    SettingsView().belowAskBar(chatOpen: assistant.isPresented)
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

            if !assistant.isPresented {
                AIEditStatusPill()
                    .padding(.bottom, askBarLift + 66)
                    .ignoresSafeArea(.keyboard)
            }

            AskBar(isFocused: $askFocused, onSend: send)
                .padding(.horizontal, assistant.isPresented ? 12 : 20)
                .padding(.bottom, assistant.isPresented ? 8 : askBarLift)
                // Closed, the bar must not jump above the keyboard of another field.
                .ignoresSafeArea(assistant.isPresented ? [] : .keyboard)
                // While another field (Search) is typed in, the bar steps
                // aside instead of floating over the results.
                .opacity(otherKeyboard ? 0 : 1)
                .allowsHitTesting(!otherKeyboard)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardShown = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardShown = false
        }
        .fullScreenCover(item: $viewer.presentation) { presentation in
            PhotoViewer(presentation: presentation)
                .navigationTransition(.zoom(sourceID: viewer.currentID, in: photoZoom))
                .environment(library)
                .environment(viewer)
                .environment(assistant)
        }
        // Watches indexing progress on its own, so progress updates redraw
        // this empty view rather than the whole app.
        .background { CollectionsRefresher() }
        .environment(\.photoZoomNamespace, photoZoom)
        .environment(library)
        .environment(indexStatus)
        .environment(describeStatus)
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
        .task { library.start() }
        #if DEBUG
        .task {
            // Testing aid: `-PhophyAsk "question"` asks the assistant on launch.
            let arguments = ProcessInfo.processInfo.arguments
            // Testing aid: `-PhophyEval` scores search against Documents/eval.json.
            if SearchEvaluation.isRequested {
                Task.detached(priority: .utility) { await SearchEvaluation.runWhenIndexed() }
            }
            // Testing aid: `-PhophyAgentEval` runs Documents/agent_tasks.json (E7).
            if AgentEvaluation.isRequested {
                Task { await AgentEvaluation.runWhenIndexed() }
            }
            // Testing aid: `-PhophyE3` compares ways to search in Chinese (E3).
            if ChineseQueryEvaluation.isRequested {
                Task { await ChineseQueryEvaluation.runWhenIndexed() }
            }
            // Testing aid: `-PhophyE4` measures vectors of the text in photos (E4).
            if OCRTextEvaluation.isRequested {
                Task { await OCRTextEvaluation.runWhenIndexed() }
            }
            Task.detached(priority: .utility) { await SearchEvaluation.probeDescribers() }
            Task.detached(priority: .userInitiated) { await SearchEvaluation.benchPhone() }
            Task.detached(priority: .userInitiated) { await SearchEvaluation.probeSearch() }
            if let index = arguments.firstIndex(of: "-PhophyAsk"), index + 1 < arguments.count {
                try? await Task.sleep(for: .seconds(3))
                send(arguments[index + 1])
            }
            // Testing aid: `-PhophyOpenTest` opens and closes the newest photo
            // a few times and prints how long the slowest frames took.
            if arguments.contains("-PhophyOpenTest") {
                try? await Task.sleep(for: .seconds(4))
                for round in 1...6 {
                    let monitor = FrameMonitor()
                    let start = CACurrentMediaTime()
                    let fetch = library.fetch(.all, oldestFirst: true)
                    let fetched = CACurrentMediaTime()
                    let loadsBefore = PhotoLoading.debugLoads
                    viewer.open(.fetch(fetch), at: fetch.count - 1)
                    try? await Task.sleep(for: .milliseconds(1500))
                    let openSummary = monitor.summary()
                    // Stay open a while: a steady page asks for its image once
                    // per page built (the open one and its neighbours), then never again.
                    try? await Task.sleep(for: .milliseconds(2500))
                    print(String(format: "OPENTEST round %d: %d photos, fetch %.0f ms, %@, image loads in 4 s: %d",
                                 round, fetch.count, (fetched - start) * 1000, openSummary,
                                 PhotoLoading.debugLoads - loadsBefore))
                    let closing = FrameMonitor()
                    viewer.close()
                    try? await Task.sleep(for: .milliseconds(1500))
                    print("OPENTEST round \(round) close: \(closing.summary())")
                }
            }
        }
        #endif
        .onChange(of: library.revision, initial: true) {
            guard library.hasAccess else { return }
            // Detached so that a later library change cannot cancel work in progress.
            let status = indexStatus
            let describing = describeStatus
            Task.detached(priority: .utility) {
                await PhotoIndexer.shared.run(status: status)
                // Descriptions are the costly layer: only once indexing is done.
                #if DEBUG
                // The phone test times describing itself; don't compete with it.
                if ProcessInfo.processInfo.arguments.contains("-PhophyPhoneBench") { return }
                #endif
                await DescriptionService.shared.run(status: describing)
            }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .background { BackgroundWork.schedule() }
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

/// Recomputes collections when indexing finishes, and every 100 photos
/// while it runs.
private struct CollectionsRefresher: View {
    @Environment(PhotoLibrary.self) private var library
    @Environment(IndexStatus.self) private var indexStatus
    @Environment(CollectionsModel.self) private var collections

    private struct Key: Equatable {
        let step: Int
        let total: Int
        let isRunning: Bool
    }

    var body: some View {
        Color.clear
            .task(id: Key(step: indexStatus.indexed / 100, total: indexStatus.total, isRunning: indexStatus.isRunning)) {
                guard library.hasAccess, indexStatus.total > 0 else { return }
                await collections.refresh()
            }
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
