import CryptoKit
import Foundation

/// Directional keys produced by a handshake.
public struct SessionKeys: Sendable {
    public let sendKey: SymmetricKey
    public let receiveKey: SymmetricKey

    public init(sendKey: SymmetricKey, receiveKey: SymmetricKey) {
        self.sendKey = sendKey
        self.receiveKey = receiveKey
    }
}

/// ChaCha20-Poly1305 with an implicit per-direction counter nonce.
/// Frames must be opened in the order they were sealed; replays and reordering fail.
public struct SecureChannel: Sendable {
    private let keys: SessionKeys
    private var sendCounter: UInt64 = 0
    private var receiveCounter: UInt64 = 0

    public init(keys: SessionKeys) {
        self.keys = keys
    }

    public mutating func seal(_ plaintext: Data) throws -> Data {
        let box = try ChaChaPoly.seal(plaintext, using: keys.sendKey, nonce: Self.nonce(sendCounter))
        sendCounter += 1
        return box.ciphertext + box.tag
    }

    public mutating func open(_ ciphertext: Data) throws -> Data {
        guard ciphertext.count >= 16 else { throw HandshakeError.authenticationFailed }
        do {
            let box = try ChaChaPoly.SealedBox(
                nonce: Self.nonce(receiveCounter),
                ciphertext: ciphertext.dropLast(16),
                tag: ciphertext.suffix(16)
            )
            let plain = try ChaChaPoly.open(box, using: keys.receiveKey)
            receiveCounter += 1
            return plain
        } catch {
            throw HandshakeError.authenticationFailed
        }
    }

    static func nonce(_ counter: UInt64) -> ChaChaPoly.Nonce {
        var bytes = Data(count: 4)
        withUnsafeBytes(of: counter.bigEndian) { bytes.append(contentsOf: $0) }
        return try! ChaChaPoly.Nonce(data: bytes)
    }
}
