import Photos
import SwiftUI

/// Chat with the assistant about the photo library.
struct AssistantView: View {
    @Environment(AssistantModel.self) private var assistant
    @Environment(IndexStatus.self) private var indexStatus
    @Environment(CollectionsModel.self) private var collections
    @Environment(\.dismiss) private var dismiss

    @State private var draft = ""
    @FocusState private var isInputFocused: Bool

    private let suggestions = [
        "What was on my lecture slides this week?",
        "Find my receipts from this month",
        "Show me photos of waterfalls",
        "How many screenshots do I have?",
    ]

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        BackendBadge(backend: assistant.backend)
                        if assistant.messages.isEmpty {
                            emptyState
                        }
                        ForEach(assistant.messages) { message in
                            MessageView(message: message)
                                .id(message.id)
                        }
                        if assistant.isWorking {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Looking through your photos…")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .id("working")
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: assistant.messages.count) {
                    withAnimation { proxy.scrollTo(assistant.messages.last?.id, anchor: .bottom) }
                }
                .onChange(of: assistant.isWorking) {
                    if assistant.isWorking { withAnimation { proxy.scrollTo("working", anchor: .bottom) } }
                }
            }
            .background { AmbientBackground() }
            .safeAreaInset(edge: .bottom) { inputBar }
            .navigationTitle("Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        assistant.reset()
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("New conversation")
                    .disabled(assistant.messages.isEmpty || assistant.isWorking)
                }
            }
            .photoDestinations()
        }
        .presentationBackground(.clear)
        .onAppear {
            if assistant.messages.isEmpty { assistant.reset() }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ask about your photos")
                .font(.title2.bold())
            Text("Find photos by what's in them, by date, or by the words written on them.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        send(suggestion)
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

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask about your photos", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .focused($isInputFocused)
                .submitLabel(.send)
                // In a multi-line field Return types a newline; treat it as Send.
                .onChange(of: draft) {
                    if draft.contains("\n") { send(draft.replacingOccurrences(of: "\n", with: " ")) }
                }
            Button {
                send(draft)
            } label: {
                Image(systemName: "arrow.up")
                    .font(.body.weight(.bold))
                    .foregroundStyle(Color(hex: 0x131A44))
                    .frame(width: 36, height: 36)
                    .background(.white, in: .circle)
            }
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || assistant.isWorking)
            .opacity(draft.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
            .accessibilityLabel("Send")
        }
        .padding(.leading, 18)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func send(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        var categories: [String: PhotoCategory] = [:]
        for result in collections.snapshot.categories {
            for id in result.localIDs { categories[id] = result.category }
        }
        let indexed = indexStatus.indexed
        Task { await assistant.send(text, indexedCount: indexed, categories: categories) }
    }
}

private struct BackendBadge: View {
    let backend: AIBackend

    var body: some View {
        Label(backend.title, systemImage: symbol)
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glassEffect(.regular, in: .capsule)
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

                if !message.photoIDs.isEmpty {
                    PhotoStrip(localIDs: message.photoIDs)
                }
                ForEach(message.albums) { proposal in
                    AlbumProposalCard(proposal: proposal)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct PhotoStrip: View {
    let localIDs: [String]
    @Environment(PhotoLibrary.self) private var library

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(assets, id: \.localIdentifier) { asset in
                    NavigationLink(value: Route.photo(localIdentifier: asset.localIdentifier)) {
                        AssetThumbnail(asset: asset)
                            .frame(width: 112, height: 112)
                            .clipShape(.rect(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
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
