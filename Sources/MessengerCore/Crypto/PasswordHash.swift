import CryptoKit
import Foundation

/// Salted PBKDF2-SHA256 hash for the optional app password: version byte (1) ‖ 16-byte salt ‖ 32-byte hash.
public enum PasswordHash {
    static let version: UInt8 = 1

    public static func make(_ password: String) -> Data {
        let salt = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        return Data([version]) + salt + derive(password, salt: salt)
    }

    public static func verify(_ password: String, against stored: Data) -> Bool {
        let bytes = [UInt8](stored)
        guard bytes.count == 1 + 16 + 32, bytes[0] == version else { return false }
        let salt = Data(bytes[1..<17])
        let expected = bytes[17...]
        let actual = [UInt8](derive(password, salt: salt))
        // Constant-time comparison.
        var difference: UInt8 = 0
        for (a, b) in zip(actual, expected) { difference |= a ^ b }
        return difference == 0
    }

    private static func derive(_ password: String, salt: Data) -> Data {
        PairingCode.stretch(password, salt: salt).withUnsafeBytes { Data($0) }
    }
}
