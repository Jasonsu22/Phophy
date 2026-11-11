import Photos
import SwiftUI

/// The Study tab: lecture slide photos grouped by lecture, with notes.
struct StudyView: View {
    @Environment(StudyModel.self) private var study
    @Environment(IndexStatus.self) private var indexStatus

    var body: some View {
        NavigationStack {
            // A List is backed by a collection view: only the rows on screen
            // exist, and rows that scroll away are reused for the ones coming
            // in, so a long list of lectures stays smooth.
            List {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notes from your lecture photos")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Study")
                        .font(.largeTitle.bold())
                }
                .padding(.top, 8)
                .studyRow()

                if study.sessions.isEmpty {
                    ContentUnavailableView(
                        "No lecture slides yet",
                        systemImage: "text.book.closed",
                        description: Text(indexStatus.isRunning
                            ? "Phophy is still looking through your photos. Slides appear here, grouped by lecture."
                            : "Photos of slides appear here, grouped by lecture.")
                    )
                    .padding(.top, 40)
                    .studyRow()
                }

                ForEach(study.sessions) { session in
                    // The invisible link keeps List from adding its own
                    // disclosure arrow next to the card's.
                    LectureCard(
                        session: session,
                        covers: study.covers[session.id] ?? [],
                        digest: study.digests[session.id]
                    )
                    .background {
                        NavigationLink(value: Route.lecture(session.id)) { EmptyView() }
                            .opacity(0)
                    }
                    .studyRow()
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .background { AmbientBackground() }
            .toolbar(.hidden, for: .navigationBar)
            .photoDestinations()
        }
    }
}

private extension View {
    /// A list row with no separator or background, spaced like the rest of the app.
    func studyRow() -> some View {
        listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 9, leading: 20, bottom: 9, trailing: 20))
    }
}

extension LectureSession {
    /// "Lecture on Tuesday" until notes give it a real title.
    var fallbackTitle: String {
        "Lecture on \(start.formatted(.dateTime.weekday(.wide)))"
    }

    var timeLine: String {
        let day = start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        let from = start.formatted(date: .omitted, time: .shortened)
        let to = end.formatted(date: .omitted, time: .shortened)
        return from == to ? "\(day) · \(from)" : "\(day) · \(from)–\(to)"
    }

    var slideCount: String { localIDs.count == 1 ? "1 slide" : "\(localIDs.count) slides" }
}

/// A lecture in a list: a small stack of its slides, when, and its title.
struct LectureCard: View {
    let session: LectureSession
    let covers: [PHAsset]
    let digest: LectureDigest?

    var body: some View {
        HStack(spacing: 14) {
            SlideStack(assets: covers)
            VStack(alignment: .leading, spacing: 3) {
                Text(session.timeLine)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(digest?.title ?? session.fallbackTitle)
                    .font(.headline)
                    .lineLimit(2)
                Text(digest == nil ? session.slideCount : "\(session.slideCount) · Notes ready")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .accessibilityElement(children: .combine)
    }
}

/// Up to three slide thumbnails fanned like a stack of cards.
struct SlideStack: View {
    let assets: [PHAsset]

    var body: some View {
        ZStack {
            ForEach(Array(assets.enumerated().reversed()), id: \.element.localIdentifier) { index, asset in
                AssetThumbnail(asset: asset)
                    .frame(width: 50, height: 50)
                    .clipShape(.rect(cornerRadius: 10))
                    .rotationEffect(.degrees(Double(index) * 7 - 4))
                    .offset(x: CGFloat(index) * 4, y: CGFloat(index) * -2)
            }
        }
        .frame(width: 62, height: 62)
        .accessibilityHidden(true)
    }
}

// MARK: - Lecture page

struct LectureDetailView: View {
    let sessionID: String

    @Environment(StudyModel.self) private var study
    @Environment(PhotoLibrary.self) private var library

    var body: some View {
        if let session = study.session(id: sessionID) {
            content(session)
        } else {
            ContentUnavailableView("Lecture not found", systemImage: "text.book.closed")
                .background { AmbientBackground() }
        }
    }

    private func content(_ session: LectureSession) -> some View {
        let digest = study.digests[session.id]
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(metaLine(session, digest))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(digest?.title ?? session.fallbackTitle)
                        .font(.title.bold())
                }

                slideStrip(session)

                if let digest {
                    GlassCard(title: "Summary") {
                        Text(digest.summary)
                    }
                    GlassCard(title: "Key points") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(digest.keyPoints.enumerated()), id: \.offset) { index, point in
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text("\(index + 1)")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(Color(hex: 0x8FE3EA))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(point.displayText)
                                        if !point.slides.isEmpty {
                                            Text(point.slides.count == 1
                                                ? "Slide \(point.slides[0])"
                                                : "Slides " + point.slides.map(String.init).joined(separator: ", "))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    HStack(spacing: 10) {
                        NavigationLink(value: Route.flashcards(session.id)) {
                            ActionTile(title: "Flashcards", detail: digest.flashcards.count == 1 ? "1 card" : "\(digest.flashcards.count) cards", symbol: "rectangle.on.rectangle.angled")
                        }
                        NavigationLink(value: Route.slideNotes(session.id)) {
                            ActionTile(title: "Slide by slide", detail: "Text on each slide", symbol: "list.bullet.rectangle")
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    MakeNotesCard(session: session)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background { AmbientBackground() }
        .navigationTitle(digest?.title ?? session.fallbackTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if digest != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await study.makeDigest(for: session) }
                    } label: {
                        if study.working.contains(session.id) {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .accessibilityLabel("Make the notes again")
                    .disabled(study.working.contains(session.id))
                }
            }
        }
    }

    private func metaLine(_ session: LectureSession, _ digest: LectureDigest?) -> String {
        var parts = [session.timeLine, session.slideCount]
        if let digest, !digest.madeWith.isEmpty { parts.append("by \(digest.madeWith)") }
        return parts.joined(separator: " · ")
    }

    /// Every slide of the lecture, side by side on reusable cells, so a
    /// lecture with hundreds of slides scrolls smoothly.
    private func slideStrip(_ session: LectureSession) -> some View {
        let assets = study.assets(of: session)
        return ReusableCollection(
            sections: [.photos(
                .assets(assets),
                layout: .strip(itemSize: CGSize(width: 120, height: 84), spacing: 8),
                // Runs to the screen's edges, as before.
                insets: NSDirectionalEdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20),
                cornerRadius: 14
            )],
            axis: .horizontal,
            contentID: assets.map(\.localIdentifier)
        )
        .frame(height: 84)
        .padding(.horizontal, -20)
    }
}

private struct MakeNotesCard: View {
    let session: LectureSession
    @Environment(StudyModel.self) private var study

    var body: some View {
        let backend = AIBackend.resolve()
        let isWorking = study.working.contains(session.id)
        VStack(alignment: .leading, spacing: 12) {
            Text("Turn these slides into notes")
                .font(.headline)
            Text("Phophy reads the text on each slide and writes a summary, key points and flashcards. "
                + (backend == .cloud ? "Only the slide text is sent to \(AppSettings.cloudProvider.title)." : "It all happens on your iPhone."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let error = study.errors[session.id] {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.footnote)
            }
            Button {
                Task { await study.makeDigest(for: session) }
            } label: {
                HStack(spacing: 8) {
                    if isWorking { ProgressView() }
                    Text(isWorking ? "Writing notes…" : "Make notes")
                        .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
            .tint(.white)
            .foregroundStyle(Color(hex: 0x131A44))
            .disabled(isWorking || backend == .off)
        }
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }
}

private struct GlassCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }
}

private struct ActionTile: View {
    let title: String
    let detail: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.title3)
                .accessibilityHidden(true)
            Text(title).font(.headline)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Flashcards

struct FlashcardsView: View {
    let sessionID: String
    @Environment(StudyModel.self) private var study
    @State private var index = 0

    var body: some View {
        let cards = study.session(id: sessionID).flatMap { study.digests[$0.id] }?.flashcards ?? []
        VStack(spacing: 18) {
            if cards.isEmpty {
                ContentUnavailableView("No flashcards", systemImage: "rectangle.on.rectangle.angled")
            } else {
                Text("\(index + 1) of \(cards.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                TabView(selection: $index) {
                    ForEach(Array(cards.enumerated()), id: \.offset) { position, card in
                        FlipCard(card: card)
                            .padding(.horizontal, 24)
                            .tag(position)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                Text("Tap a card to see the answer. Swipe for the next one.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 24)
            }
        }
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { AmbientBackground() }
        .navigationTitle("Flashcards")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FlipCard: View {
    let card: LectureDigest.Flashcard
    @State private var isFlipped = false

    var body: some View {
        Button {
            withAnimation(.smooth(duration: 0.4)) { isFlipped.toggle() }
        } label: {
            ZStack {
                face(label: "QUESTION", text: card.question)
                    .opacity(isFlipped ? 0 : 1)
                face(label: "ANSWER", text: card.answer)
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                    .opacity(isFlipped ? 1 : 0)
            }
            .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
            .contentShape(.rect(cornerRadius: 32))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isFlipped ? "Answer: \(card.answer)" : "Question: \(card.question)")
        .accessibilityHint("Shows the other side")
    }

    private func face(label: String, text: String) -> some View {
        VStack(spacing: 16) {
            Text(label)
                .font(.caption.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: 420)
        .glassEffect(.regular, in: .rect(cornerRadius: 32))
    }
}

// MARK: - Slide by slide

struct SlideNotesView: View {
    let sessionID: String
    @Environment(StudyModel.self) private var study

    var body: some View {
        // Reusable rows: a long lecture builds only the slides on screen.
        let session = study.session(id: sessionID)
        let assets = session.map { study.assets(of: $0) } ?? []
        let slides = session.map { study.slides(of: $0) } ?? []
        ReusableCollection(
            sections: [ReusableSection(
                layout: .rows(spacing: 14, estimatedHeight: 160),
                count: slides.count,
                insets: NSDirectionalEdgeInsets(top: 8, leading: 20, bottom: 24, trailing: 20)
            ) { index in
                AnyView(SlideNoteRow(slide: slides[index], assets: assets).frame(maxWidth: .infinity, alignment: .leading))
            }],
            contentID: slides.map(\.number)
        )
        .ignoresSafeArea(.container, edges: .vertical)
        .background { AmbientBackground() }
        .navigationTitle("Slide by slide")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SlideNoteRow: View {
    let slide: DigestWriter.Slide
    let assets: [PHAsset]
    @Environment(PhotoViewerModel.self) private var viewer

    private var asset: PHAsset? {
        assets.indices.contains(slide.number - 1) ? assets[slide.number - 1] : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                if let asset {
                    AssetThumbnail(asset: asset)
                        .frame(width: 72, height: 52)
                        .clipShape(.rect(cornerRadius: 10))
                        .opensInViewer(.assets(assets), at: slide.number - 1, id: asset.localIdentifier)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Slide \(slide.number)").font(.headline)
                    Text(slide.time.formatted(date: .omitted, time: .shortened))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Text(slide.text.isEmpty ? "No text found on this slide." : slide.text)
                .font(.subheadline)
                .foregroundStyle(slide.text.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }
}
