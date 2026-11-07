import Foundation
import Testing
@testable import MessengerCore

@Suite struct PasswordHashTests {
    @Test func hashVerifies() {
        let stored = PasswordHash.make("1234")
        #expect(PasswordHash.verify("1234", against: stored))
        #expect(!PasswordHash.verify("1235", against: stored))
        #expect(!PasswordHash.verify("", against: stored))
    }

    @Test func hashSalted() {
        #expect(PasswordHash.make("1234") != PasswordHash.make("1234"))
    }

    @Test func rejectsGarbage() {
        #expect(!PasswordHash.verify("1234", against: Data([1, 2, 3])))
        #expect(!PasswordHash.verify("1234", against: Data()))
    }

    @Test func formatIsVersionSaltHash() {
        let stored = PasswordHash.make("pw")
        #expect(stored.count == 1 + 16 + 32)
        #expect(stored.first == 1)
    }
}
