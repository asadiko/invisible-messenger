import Foundation
import Testing
@testable import MessengerCore

@Suite struct SecretStoreTests {
    @Test func inMemoryRoundTrip() throws {
        try exercise(InMemorySecretStore())
    }

    @Test func keychainStoreRoundTrip() throws {
        let store = KeychainSecretStore(service: "com.asadiko.InvisibleMessenger.tests.\(UUID().uuidString)")
        defer { try? store.deleteAll() }
        try exercise(store)
    }

    private func exercise(_ store: SecretStore) throws {
        #expect(try store.read("a") == nil)
        try store.write(Data([1, 2, 3]), account: "a")
        #expect(try store.read("a") == Data([1, 2, 3]))
        try store.write(Data([4]), account: "a")
        #expect(try store.read("a") == Data([4]))
        try store.write(Data([5]), account: "b")
        try store.delete("a")
        #expect(try store.read("a") == nil)
        #expect(try store.read("b") == Data([5]))
        try store.deleteAll()
        #expect(try store.read("b") == nil)
    }
}
