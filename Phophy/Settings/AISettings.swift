import Foundation
import FoundationModels

/// Keys and defaults for user settings, stored in UserDefaults.
/// Read them with `@AppStorage(AppSettings.Key.x)` in views, or through the
/// static accessors from non-UI code.
enum AppSettings {
    nonisolated enum Key {
        static let useAppleIntelligence = "useAppleIntelligence"
        static let allowCloudAI = "allowCloudAI"
        static let indexICloudPhotos = "indexICloudPhotos"
        static let cloudProvider = "cloudProvider"
        static let customBaseURL = "customBaseURL"
        static func cloudModel(_ provider: CloudProvider) -> String { "cloudModel.\(provider.rawValue)" }
    }

    /// Register defaults once at launch so unset values read as intended.
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.useAppleIntelligence: true,
            Key.allowCloudAI: true,
            Key.indexICloudPhotos: true,
            Key.cloudProvider: CloudProvider.anthropic.rawValue,
            Key.customBaseURL: "",
        ])
    }

    nonisolated static var useAppleIntelligence: Bool {
        UserDefaults.standard.bool(forKey: Key.useAppleIntelligence)
    }

    nonisolated static var allowCloudAI: Bool {
        UserDefaults.standard.bool(forKey: Key.allowCloudAI)
    }

    nonisolated static var cloudProvider: CloudProvider {
        UserDefaults.standard.string(forKey: Key.cloudProvider).flatMap(CloudProvider.init) ?? .anthropic
    }

    nonisolated static var customBaseURL: String {
        UserDefaults.standard.string(forKey: Key.customBaseURL) ?? ""
    }

    /// The model name for a provider: what the user typed, else its default.
    nonisolated static func cloudModel(for provider: CloudProvider) -> String {
        let saved = UserDefaults.standard.string(forKey: Key.cloudModel(provider))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return saved.isEmpty ? provider.defaultModel : saved
    }

    /// Whether the indexer may download originals that are only in iCloud.
    nonisolated static var indexICloudPhotos: Bool {
        UserDefaults.standard.bool(forKey: Key.indexICloudPhotos)
    }
}

/// Whether this iPhone can run Apple's on-device model, and if not, why.
enum AppleIntelligenceStatus: Equatable {
    case available
    case notSupported
    case turnedOff
    case preparing
    case unavailable

    static var current: AppleIntelligenceStatus {
        #if DEBUG
        // Lets us test the older-iPhone path in the simulator:
        // add -SimulateNoAppleIntelligence to the scheme's launch arguments.
        if ProcessInfo.processInfo.arguments.contains("-SimulateNoAppleIntelligence") {
            return .notSupported
        }
        #endif
        switch SystemLanguageModel.default.availability {
        case .available: return .available
        case .unavailable(.deviceNotEligible): return .notSupported
        case .unavailable(.appleIntelligenceNotEnabled): return .turnedOff
        case .unavailable(.modelNotReady): return .preparing
        case .unavailable: return .unavailable
        }
    }

    var isAvailable: Bool { self == .available }

    var summary: String {
        switch self {
        case .available: "Available on this iPhone"
        case .notSupported: "Not supported on this iPhone"
        case .turnedOff: "Turned off in iPhone Settings"
        case .preparing: "Downloading, try again later"
        case .unavailable: "Not available right now"
        }
    }
}

/// Where requests that need a language model (agent, lecture digest,
/// captions) are sent. Search and indexing never use this: they always run
/// on the device.
enum AIBackend: Equatable {
    case appleIntelligence
    case cloud
    case off

    static func resolve(
        status: AppleIntelligenceStatus = .current,
        useAppleIntelligence: Bool = AppSettings.useAppleIntelligence,
        allowCloud: Bool = AppSettings.allowCloudAI
    ) -> AIBackend {
        if status.isAvailable && useAppleIntelligence { return .appleIntelligence }
        if allowCloud { return .cloud }
        return .off
    }

    var title: String {
        switch self {
        case .appleIntelligence: "Apple Intelligence on this iPhone"
        case .cloud: "Cloud: \(AppSettings.cloudProvider.title)"
        case .off: "Off"
        }
    }

    var detail: String {
        switch self {
        case .appleIntelligence:
            "Free and private. Nothing leaves your iPhone."
        case .cloud:
            "Sends only the text a request needs, such as slide text or your question. Your library is never uploaded."
        case .off:
            "The assistant and lecture digests are unavailable. Search still works on your iPhone."
        }
    }
}
