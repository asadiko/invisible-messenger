import CommonCrypto
import CryptoKit
import Foundation

/// The short one-time code one Mac shows and the other types to pair.
public enum PairingCode {
    /// Crockford-style base32 alphabet without I, L, O and U, so codes are easy to read aloud and type.
    public static let alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
    public static let length = 8
    public static let stretchIterations: UInt32 = 200_000

    public static func generate() -> String {
        let chars = Array(alphabet)
        var rng = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in chars[Int(rng.next(upperBound: UInt32(chars.count)))] })
    }

    /// Uppercases, drops spaces and dashes and maps look-alikes (O→0, I/L→1).
    /// Returns nil unless the result is exactly `length` valid characters.
    public static func normalize(_ input: String) -> String? {
        var out = ""
        for ch in input.uppercased() {
            switch ch {
            case " ", "-", "\t": continue
            case "O": out.append("0")
            case "I", "L": out.append("1")
            default: out.append(ch)
            }
        }
        guard out.count == length, out.allSatisfy({ alphabet.contains($0) }) else { return nil }
        return out
    }

    public static func display(_ code: String) -> String {
        guard code.count == length else { return code }
        return "\(code.prefix(4))-\(code.suffix(4))"
    }

    /// PBKDF2-HMAC-SHA256 so that guessing a short code offline is expensive.
    public static func stretch(_ code: String, salt: Data) -> SymmetricKey {
        let password = Array(code.utf8)
        var derived = [UInt8](repeating: 0, count: 32)
        let status = salt.withUnsafeBytes { saltPtr in
            password.withUnsafeBufferPointer { pwPtr in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    pwPtr.baseAddress.map { UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self) },
                    password.count,
                    saltPtr.bindMemory(to: UInt8.self).baseAddress,
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    stretchIterations,
                    &derived,
                    derived.count
                )
            }
        }
        precondition(status == kCCSuccess, "PBKDF2 failed: \(status)")
        return SymmetricKey(data: derived)
    }
}
