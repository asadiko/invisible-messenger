import CryptoKit
import Foundation

/// A Mac's long-term identity: an X25519 key pair whose public key is pinned by paired contacts.
public struct DeviceIdentity: Sendable {
    public let privateKey: Curve25519.KeyAgreement.PrivateKey

    public var publicKeyData: Data { privateKey.publicKey.rawRepresentation }
    public var deviceID: DeviceID { Self.deviceID(for: publicKeyData) }

    public init(privateKey: Curve25519.KeyAgreement.PrivateKey) {
        self.privateKey = privateKey
    }

    public init(rawRepresentation: Data) throws {
        privateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: rawRepresentation)
    }

    public static func generate() -> DeviceIdentity {
        DeviceIdentity(privateKey: Curve25519.KeyAgreement.PrivateKey())
    }

    /// Hex of the first 8 bytes of SHA-256(publicKey).
    public static func deviceID(for publicKey: Data) -> DeviceID {
        let digest = SHA256.hash(data: publicKey)
        return DeviceID(rawValue: digest.prefix(8).map { String(format: "%02x", $0) }.joined())
    }

    public static func loadOrCreate(in store: SecretStore) throws -> DeviceIdentity {
        if let raw = try store.read(SecretAccount.identity) {
            return try DeviceIdentity(rawRepresentation: raw)
        }
        let identity = generate()
        try store.write(identity.privateKey.rawRepresentation, account: SecretAccount.identity)
        return identity
    }
}
