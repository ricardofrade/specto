import Foundation
import Security

/// Where account tokens live. Never GRDB or UserDefaults (`docs/adr/0002`).
public protocol SecretStore: Sendable {
    func secret(for key: String) -> String?
    func setSecret(_ value: String?, for key: String)
}

/// Generic-password Keychain items, readable after first unlock so background refresh works.
public struct KeychainSecretStore: SecretStore {
    private let service: String

    public init(service: String = "dev.placeholder.player.secrets") {
        self.service = service
    }

    public func secret(for key: String) -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func setSecret(_ value: String?, for key: String) {
        SecItemDelete(baseQuery(key) as CFDictionary)
        guard let value else { return }
        var item = baseQuery(key)
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }

    private func baseQuery(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: key]
    }
}

/// For tests and previews.
public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    // Guarded by `lock`.
    private var values: [String: String] = [:]
    private let lock = NSLock()

    public init() {}

    public func secret(for key: String) -> String? {
        lock.withLock { values[key] }
    }

    public func setSecret(_ value: String?, for key: String) {
        lock.withLock { values[key] = value }
    }
}
