import Foundation
import Testing
@testable import MessengerCore

@Suite struct DeviceIdentityTests {
    @Test func deviceIDIsStableHex() {
        let id = DeviceIdentity.generate()
        let raw = id.deviceID.rawValue
        #expect(raw.count == 16)
        #expect(raw.allSatisfy { "0123456789abcdef".contains($0) })
        #expect(DeviceIdentity.deviceID(for: id.publicKeyData) == id.deviceID)
    }

    @Test func identityRoundTrip() throws {
        let id = DeviceIdentity.generate()
        let restored = try DeviceIdentity(rawRepresentation: id.privateKey.rawRepresentation)
        #expect(restored.deviceID == id.deviceID)
        #expect(restored.publicKeyData == id.publicKeyData)
    }

    @Test func loadOrCreateReusesStoredIdentity() throws {
        let store = InMemorySecretStore()
        let first = try DeviceIdentity.loadOrCreate(in: store)
        let second = try DeviceIdentity.loadOrCreate(in: store)
        #expect(first.deviceID == second.deviceID)
    }
}
