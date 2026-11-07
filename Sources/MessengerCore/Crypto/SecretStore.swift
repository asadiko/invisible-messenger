import Foundation
import Security
import Synchronization

/// Small secrets (identity key, data key, app password hash) keyed by account name.
public protocol SecretStore: Sendable {
    func read(_ account: String) throws -> Data?
    func write(_ data: Data, account: String) throws
    func delete(_ account: String) throws
    func deleteAll() throws
}

public enum SecretAccount {
    public static let identity = "identity"
    public static let dataKey = "data-key"
    public static let appPassword = "app-password"
}

public struct KeychainError: Error, Equatable {
    public let status: OSStatus
}

/// Generic-password items in the user's login keychain, scoped by `service`.
public final class KeychainSecretStore: SecretStore {
    public let service: String

    public init(service: String) {
        self.service = service
    }

    private func baseQuery(_ account: String? = nil) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        if let account { q[kSecAttrAccount as String] = account }
        return q
    }

    public func read(_ account: String) throws -> Data? {
        var q = baseQuery(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        return out as? Data
    }

    public func write(_ data: Data, account: String) throws {
        let update = SecItemUpdate(baseQuery(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw KeychainError(status: update) }
        var add = baseQuery(account)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    public func delete(_ account: String) throws {
        let status = SecItemDelete(baseQuery(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }

    public func deleteAll() throws {
        // The file-based keychain may delete one match per call, so repeat until nothing is left.
        for _ in 0..<64 {
            let status = SecItemDelete(baseQuery() as CFDictionary)
            if status == errSecItemNotFound { return }
            guard status == errSecSuccess else { throw KeychainError(status: status) }
        }
    }
}

/// Process-local store for tests and throwaway profiles.
public final class InMemorySecretStore: SecretStore {
    private let items = Mutex<[String: Data]>([:])

    public init() {}

    public func read(_ account: String) throws -> Data? { items.withLock { $0[account] } }
    public func write(_ data: Data, account: String) throws { items.withLock { $0[account] = data } }
    public func delete(_ account: String) throws { _ = items.withLock { $0.removeValue(forKey: account) } }
    public func deleteAll() throws { items.withLock { $0.removeAll() } }
}
