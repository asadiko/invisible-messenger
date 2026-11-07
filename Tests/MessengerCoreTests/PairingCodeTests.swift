import CryptoKit
import Foundation
import Testing
@testable import MessengerCore

@Suite struct PairingCodeTests {
    @Test func generateUsesAlphabetAndLength() {
        let allowed = Set(PairingCode.alphabet)
        for _ in 0..<100 {
            let code = PairingCode.generate()
            #expect(code.count == 8)
            #expect(code.allSatisfy { allowed.contains($0) })
        }
    }

    @Test func normalizeAcceptsHumanInput() {
        #expect(PairingCode.normalize(" k7q4-m2xp ") == "K7Q4M2XP")
        #expect(PairingCode.normalize("O1IL-0000") == "01110000")
        #expect(PairingCode.normalize("K7Q4M2X") == nil)
        #expect(PairingCode.normalize("K7Q4M2XU") == nil)
    }

    @Test func displayGroups() {
        #expect(PairingCode.display("K7Q4M2XP") == "K7Q4-M2XP")
    }

    @Test func stretchIsDeterministicAndSaltSensitive() {
        let salt = Data([1, 2, 3, 4])
        let a = PairingCode.stretch("K7Q4M2XP", salt: salt)
        let b = PairingCode.stretch("K7Q4M2XP", salt: salt)
        let c = PairingCode.stretch("K7Q4M2XP", salt: Data([9]))
        let d = PairingCode.stretch("K7Q4M2XQ", salt: salt)
        func bytes(_ k: SymmetricKey) -> Data { k.withUnsafeBytes { Data($0) } }
        #expect(bytes(a) == bytes(b))
        #expect(bytes(a).count == 32)
        #expect(bytes(a) != bytes(c))
        #expect(bytes(a) != bytes(d))
    }
}
