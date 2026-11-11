import Foundation
import Security

/// API keys for the cloud services, one per provider, kept in the iPhone's
/// Keychain. A key leaves the device only in requests to its own service.
nonisolated enum APIKeyStore {
    private static let service = "app.phophy.api-keys"

    static func load(for provider: CloudProvider) -> String? { load(account: provider.rawValue) }

    @discardableResult
    static func save(_ key: String, for provider: CloudProvider) -> Bool { save(key, account: provider.rawValue) }

    static func delete(for provider: CloudProvider) { delete(account: provider.rawValue) }

    static func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8), !key.isEmpty
        else { return nil }
        return key
    }

    @discardableResult
    static func save(_ key: String, account: String) -> Bool {
        delete(account: account)
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(key.utf8),
        ]
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
