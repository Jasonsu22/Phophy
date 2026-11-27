import Photos
import SwiftUI

/// The conversation, shown over the app while the ask bar stays where it is.
/// The app behind is blurred rather than replaced.
struct AssistantPanel: View {
    let onClose: () -> Void
    let onSend: (String) -> Void

    @Environment(AssistantModel.self) private var assistant
    @State private var showingHistory = false

    private let suggestions = [
        "What was on my lecture slides this week?",
        "Find my receipts from this month",
        "Show me photos of waterfalls",
        "How many screenshots do I have?",
    ]

    var body: some View {
        ZStack {
            conversation
                .opacity(assistant.openedResults == nil ? 1 : 0)
            if let opened = assistant.openedResults {
                ResultsAlbum(results: opened) {
                    withAnimation(.smooth(duration: 0.3)) { assistant.openedResults = nil }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.3), value: assistant.openedResults)
    }

    /// The user's question an answer belongs to, for titling its results.
    private func question(before message: AssistantModel.Message) -> String {
        guard let i = assistant.messages.firstIndex(where: { $0.id == message.id }) else { return "Results" }
        return assistant.messages[..<i].last(where: { $0.role == .user })?.text ?? "Results"
    }

    private var conversation: some View {
        VStack(spacing: 0) {
            header
                .sheet(isPresented: $showingHistory) {
                    ChatHistoryView()
                }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if assistant.messages.isEmpty {
                            emptyState
                                .transition(.opacity.combined(with: .offset(y: 12)))
                        }
                        ForEach(assistant.messages) { message in
                            MessageView(message: message, question: question(before: message))
                                .id(message.id)
                                .transition(.opacity.combined(with: .offset(y: 16)))
                        }
                        if assistant.isWorking {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Looking through your photos…")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .id("working")
                            .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .animation(.smooth(duration: 0.3), value: assistant.messages.count)
                    .animation(.smooth(duration: 0.3), value: assistant.isWorking)
                }
                // Room for the ask bar, which floats over the bottom.
                .contentMargins(.bottom, 90, for: .scrollContent)
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: assistant.messages.count) {
                    withAnimation { proxy.scrollTo(assistant.messages.last?.id, anchor: .bottom) }
                }
                .onChange(of: assistant.isWorking) {
                    if assistant.isWorking { withAnimation { proxy.scrollTo("working", anchor: .bottom) } }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            BackendBadge(backend: assistant.backend)
            Spacer()
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Button {
                        showingHistory = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Chat history")

                    Button {
                        withAnimation(.smooth) { assistant.reset() }
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("New chat")
                    .disabled(assistant.messages.isEmpty || assistant.isWorking)

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Close assistant")
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Search or ask")
                .font(.title2.bold())
            Text("Type what you're looking for, like \u{201C}dog on the beach\u{201D}, or ask a question, like \u{201C}how much did I spend at Muji?\u{201D} Matching photos appear at once; the answer follows.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        onSend(suggestion)
                    } label: {
                        Text(suggestion)
                            .font(.subheadline)
                            .multilineTextAlignment(.leading)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.glass)
                }
            }
        }
        .padding(.top, 12)
    }
}

/// The one ask bar. It sits above the tab bar when the chat is closed;
/// tapping it opens the chat with the keyboard up, and it rides on the
/// keyboard while you type.
struct AskBar: View {
    var isFocused: FocusState<Bool>.Binding
    let onSend: (String) -> Void

    @Environment(AssistantModel.self) private var assistant

    var body: some View {
        @Bindable var assistant = assistant
        let canSend = !assistant.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !assistant.isWorking
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            // The placeholder is drawn here rather than by the field: a
            // multi-line field can lose its own placeholder after the
            // keyboard is dismissed from outside (opening a photo does that).
            TextField("", text: $assistant.draft, axis: .vertical)
                .lineLimit(1...4)
                .focused(isFocused)
                .submitLabel(.send)
                .accessibilityLabel("Search or ask about your photos")
                .overlay(alignment: .leading) {
                    if assistant.draft.isEmpty {
                        Text("Search or ask about your photos")
                            .foregroundStyle(.secondary)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                // In a multi-line field Return types a newline; treat it as Send.
                .onChange(of: assistant.draft) {
                    if assistant.draft.contains("\n") {
                        onSend(assistant.draft.replacingOccurrences(of: "\n", with: " "))
                    }
                }
            if assistant.isPresented {
                Button {
                    onSend(assistant.draft)
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.bold))
                        .foregroundStyle(Color(hex: 0x131A44))
                        .frame(width: 34, height: 34)
                        .background(.white, in: .circle)
                }
                .disabled(!canSend)
                .opacity(canSend ? 1 : 0.45)
                .accessibilityLabel("Send")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, assistant.isPresented ? 7 : 18)
        .frame(minHeight: 50)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 25))
    }
}

private struct BackendBadge: View {
    let backend: AIBackend

    var body: some View {
        Label(shortTitle, systemImage: symbol)
            .font(.footnote.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glassEffect(.regular, in: .capsule)
    }

    private var shortTitle: String {
        switch backend {
        case .appleIntelligence: "Apple Intelligence"
        case .cloud: AppSettings.cloudProvider.title
        case .off: "Off"
        }
    }

    private var symbol: String {
        switch backend {
        case .appleIntelligence: "apple.intelligence"
        case .cloud: "cloud"
        case .off: "pause"
        }
    }
}

private struct MessageView: View {
    let message: AssistantModel.Message
    var question = "Results"

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 48)
                Text(message.text)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassEffect(.regular.tint(Color(hex: 0x5A3FD6).opacity(0.6)), in: .rect(cornerRadius: 22))
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 10) {
                if message.text.isEmpty {
                    // Search results shown at once, before the answer is written.
                    Label("Found in your photos", systemImage: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 6)
                } else {
                    HStack(alignment: .top, spacing: 8) {
                        if message.isError {
                            Image(systemName: "exclamationmark.circle")
                                .accessibilityHidden(true)
                        }
                        Text(message.text)
                            .textSelection(.enabled)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: .rect(cornerRadius: 22))
                }

                if let steps = message.steps, !steps.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                            Label(step, systemImage: step.hasPrefix("Searched") ? "magnifyingglass" : "calendar")
                                .labelStyle(.titleAndIcon)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Steps: " + steps.joined(separator: ", "))
                }

                if !message.photoIDs.isEmpty {
                    MatchesStrip(shown: message.photoIDs, more: message.moreIDs ?? [], title: question)
                }
                ForEach(message.albums) { proposal in
                    AlbumProposalCard(proposal: proposal)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The photos the assistant picked, with "Show all" opening everything its
/// search found as a grid (it only reads the top few, the user sees them all).
private struct MatchesStrip: View {
    let shown: [String]
    let more: [String]
    let title: String
    @Environment(AssistantModel.self) private var assistant

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PhotoStrip(localIDs: shown)
            if more.count > shown.count {
                Button {
                    withAnimation(.smooth(duration: 0.3)) {
                        assistant.openedResults = .init(title: title, ids: more)
                    }
                } label: {
                    Label("Show all \(more.count) results", systemImage: "square.grid.2x2")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .padding(.leading, 6)
            }
        }
    }
}

/// Every result of one answer as a photo grid, best match first, like an album.
private struct ResultsAlbum: View {
    let results: AssistantModel.OpenedResults
    let onBack: () -> Void
    @Environment(PhotoLibrary.self) private var library

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Back to chat")
                VStack(alignment: .leading, spacing: 2) {
                    Text(results.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text("\(assets.count) photos, best match first · pinch to zoom")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            ReusableCollection(
                sections: [.photos(.assets(assets), layout: .grid(columns: 3, spacing: 2))],
                contentID: results.ids,
                startsAtEnd: false,
                bottomInset: 96,
                zoomKey: "gridColumns.results"
            )
        }
    }

    private var assets: [PHAsset] {
        _ = library.revision
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: results.ids, options: nil)
        var byID: [String: PHAsset] = [:]
        fetched.enumerateObjects { asset, _, _ in byID[asset.localIdentifier] = asset }
        return results.ids.compactMap { byID[$0] }
    }
}

private struct PhotoStrip: View {
    let localIDs: [String]
    @Environment(PhotoLibrary.self) private var library

    /// Reusable cells side by side: only the photos on screen are built.
    var body: some View {
        let assets = assets
        ReusableCollection(
            sections: [.photos(
                .assets(assets),
                layout: .strip(itemSize: CGSize(width: 112, height: 112), spacing: 6),
                cornerRadius: 16
            )],
            axis: .horizontal,
            contentID: ContentKey(ids: localIDs, revision: library.revision)
        )
        .frame(height: 112)
    }

    private struct ContentKey: Hashable {
        let ids: [String]
        let revision: Int
    }

    private var assets: [PHAsset] {
        _ = library.revision
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: localIDs, options: nil)
        var byID: [String: PHAsset] = [:]
        fetched.enumerateObjects { asset, _, _ in byID[asset.localIdentifier] = asset }
        return localIDs.compactMap { byID[$0] }
    }
}

private struct AlbumProposalCard: View {
    let proposal: AlbumProposal
    @Environment(PhotoLibrary.self) private var library
    @State private var state: SaveState = .idle

    private enum SaveState { case idle, saving, saved, failed }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.title3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(proposal.title).font(.headline)
                Text(proposal.localIDs.count == 1 ? "1 photo" : "\(proposal.localIDs.count) photos")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            switch state {
            case .saved:
                Label("Saved", systemImage: "checkmark")
                    .font(.subheadline.weight(.semibold))
            case .failed:
                Text("Couldn't save").font(.footnote).foregroundStyle(.secondary)
            default:
                Button("Save album") {
                    Task {
                        state = .saving
                        do {
                            try await library.addToAlbum(named: proposal.title, localIDs: proposal.localIDs)
                            state = .saved
                        } catch {
                            state = .failed
                        }
                    }
                }
                .buttonStyle(.glass)
                .disabled(state == .saving)
            }
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }
}

/// Earlier conversations, newest first. Tap one to read or continue it;
/// swipe to delete.
private struct ChatHistoryView: View {
    @Environment(AssistantModel.self) private var assistant
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if assistant.history.isEmpty {
                    ContentUnavailableView(
                        "No chats yet",
                        systemImage: "bubble.left.and.text.bubble.right",
                        description: Text("Your conversations with the assistant appear here. They stay on this iPhone.")
                    )
                } else {
                    List {
                        ForEach(assistant.history) { conversation in
                            Button {
                                withAnimation(.smooth) { assistant.resume(conversation) }
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(conversation.title)
                                        .font(.body.weight(.semibold))
                                        .lineLimit(2)
                                    Text("\(conversation.updated.formatted(.relative(presentation: .named))) · \(conversation.messages.count) messages")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 2)
                            }
                            .tint(.primary)
                            .listRowBackground(
                                conversation.id == assistant.conversationID ? Color.white.opacity(0.12) : Color.clear
                            )
                        }
                        .onDelete { offsets in
                            for index in offsets { assistant.delete(assistant.history[index]) }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Chat history")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
