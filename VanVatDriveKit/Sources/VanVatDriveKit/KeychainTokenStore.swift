import Foundation
import Security

/// Stores the Van Vat JWT in the Keychain (not UserDefaults).
public final class KeychainTokenStore: @unchecked Sendable {
    private let service: String
    private let account: String
    private let accessGroup: String?
    private let lock = NSLock()

    /// Pass the same `accessGroup` (e.g. "TEAMID.com.vanvatcorporation.shared", added under Keychain Sharing in both
    /// apps) to share one sign-in between Van Vat Drive and DoubleClips.
    public init(service: String = "com.vanvatcorporation.drive", account: String = "jwt", accessGroup: String? = nil) {
        self.service = service
        self.account = account
        self.accessGroup = accessGroup
    }

    private var baseQuery: [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: account]
        if let accessGroup { q[kSecAttrAccessGroup as String] = accessGroup }
        return q
    }

    public var token: String? {
        get {
            lock.lock(); defer { lock.unlock() }
            var query = baseQuery
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
                  let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }
        set {
            lock.lock(); defer { lock.unlock() }
            SecItemDelete(baseQuery as CFDictionary)
            guard let value = newValue, let data = value.data(using: .utf8) else { return }
            var query = baseQuery
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(query as CFDictionary, nil)
        }
    }

    public func clear() { token = nil }
}
