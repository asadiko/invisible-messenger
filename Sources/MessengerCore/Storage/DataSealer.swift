import CryptoKit
import Foundation

/// Encrypts everything written to disk with one random 256-bit key kept in the Keychain.
public struct DataSealer: Sendable {
    private let key: SymmetricKey

    public init(key: SymmetricKey) {
        self.key = key
    }

    public static func loadOrCreateKey(in store: SecretStore) throws -> SymmetricKey {
        if let raw = try store.read(SecretAccount.dataKey), raw.count == 32 {
            return SymmetricKey(data: raw)
        }
        let key = SymmetricKey(size: .bits256)
        try store.write(key.withUnsafeBytes { Data($0) }, account: SecretAccount.dataKey)
        return key
    }

    public func seal(_ data: Data) throws -> Data {
        try ChaChaPoly.seal(data, using: key).combined
    }

    public func open(_ data: Data) throws -> Data {
        try ChaChaPoly.open(ChaChaPoly.SealedBox(combined: data), using: key)
    }
}
