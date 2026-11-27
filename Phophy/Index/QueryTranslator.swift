import Foundation
import Translation

/// Turns a Chinese search into English on the phone, with Apple's
/// Translation framework, for the visual model (which reads English only)
/// and for matching English descriptions. On the Flickr test this found the
/// right photo for a full-sentence search in the top five 87% of the time,
/// against 60% with the concept dictionary alone (Eval/E3_CHINESE.md).
///
/// Nothing leaves the phone. It works only once the Chinese and English
/// translation languages are on the phone; until then searches use the
/// concept dictionary as before.
actor QueryTranslator {
    static let shared = QueryTranslator()

    private static let english = Locale.Language(identifier: "en")
    private static let sources = ["zh-Hans", "zh-Hant"].map(Locale.Language.init(identifier:))

    private var session: TranslationSession?
    private var checkedAt: Date?
    private var cache: [String: String] = [:]

    enum Status { case on, needsDownload, unsupported }

    /// Whether Chinese searches are being translated on this phone, or could be.
    func status() async -> Status {
        checkedAt = nil
        if await currentSession() != nil { return .on }
        let downloadable = await LanguageAvailability().status(from: Self.sources[0], to: Self.english) == .supported
        return downloadable ? .needsDownload : .unsupported
    }

    /// What Settings asks the system to download.
    static var download: TranslationSession.Configuration {
        TranslationSession.Configuration(source: sources[0], target: english)
    }

    /// English for a Chinese query, or nil when the languages aren't
    /// installed or the translation failed.
    func english(for query: String) async -> String? {
        if let cached = cache[query] { return cached }
        guard let session = await currentSession() else { return nil }
        guard let response = try? await session.translate(query) else {
            // The languages may have been removed: look again next time.
            self.session = nil
            checkedAt = nil
            return nil
        }
        let text = response.targetText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".。!?\"“”"))
        // An echo of the Chinese is no translation.
        guard !text.isEmpty, !TextNormalizer.containsCJK(text) else { return nil }
        if cache.count > 200 { cache.removeAll() }
        cache[query] = text
        return text
    }

    #if DEBUG
    /// The simulator has no Translation framework: the evaluation hands in
    /// translations made by the same framework on a Mac.
    func preload(_ translations: [String: String]) {
        cache.merge(translations) { _, new in new }
    }
    #endif

    /// The languages can be downloaded at any time (in Settings, or by the
    /// Translate app), so a "not installed" answer is only kept for a minute.
    private func currentSession() async -> TranslationSession? {
        if let session { return session }
        if let checkedAt, Date.now.timeIntervalSince(checkedAt) < 60 { return nil }
        checkedAt = .now
        let availability = LanguageAvailability()
        for source in Self.sources where await availability.status(from: source, to: Self.english) == .installed {
            session = TranslationSession(installedSource: source, target: Self.english)
            return session
        }
        return nil
    }
}
