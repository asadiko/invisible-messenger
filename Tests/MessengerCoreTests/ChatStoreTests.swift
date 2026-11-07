import CryptoKit
import Foundation
import Testing
@testable import MessengerCore

func makeTempDir() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("im-tests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@MainActor @Suite struct ChatStoreTests {
    let dir = makeTempDir()
    let key = SymmetricKey(size: .bits256)
    let peer = DeviceIdentity.generate()
    let contact: Contact

    func store(_ key: SymmetricKey? = nil) throws -> ChatStore {
        try ChatStore(directory: dir, sealer: DataSealer(key: key ?? self.key))
    }

    init() {
        contact = Contact(id: peer.deviceID, name: "Sam", publicKey: peer.publicKeyData, pairedAt: Date(timeIntervalSince1970: 1_800_000_000))
    }

    func message(_ text: String, _ direction: MessageDirection = .incoming, status: MessageStatus = .delivered, at t: TimeInterval = 0) -> ChatMessage {
        ChatMessage(contactID: peer.deviceID, direction: direction, sentAt: Date(timeIntervalSince1970: 1_800_000_000 + t), body: .text(text), status: status)
    }

    func allFileBytes() -> Data {
        let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)!
        var all = Data()
        for case let url as URL in e { all += (try? Data(contentsOf: url)) ?? Data() }
        return all
    }

    @Test func persistsAcrossInstances() throws {
        let s1 = try store()
        try s1.upsert(contact)
        try s1.append(message("one", at: 1))
        try s1.append(message("two", at: 2))
        let s2 = try store()
        #expect(s2.contacts == [contact])
        #expect(s2.messages(for: peer.deviceID).map(\.body) == [.text("one"), .text("two")])
    }

    @Test func appendIsIdempotent() throws {
        let s = try store()
        let m = message("hi")
        #expect(try s.append(m) == true)
        #expect(try s.append(m) == false)
        #expect(s.messages(for: peer.deviceID).count == 1)
    }

    @Test func pendingOutgoingOrdered() throws {
        let s = try store()
        try s.append(message("late", .outgoing, status: .sending, at: 5))
        try s.append(message("done", .outgoing, status: .delivered, at: 1))
        try s.append(message("early", .outgoing, status: .sending, at: 2))
        try s.append(message("theirs", .incoming, status: .sending, at: 3))
        #expect(s.pendingOutgoing(for: peer.deviceID).map(\.body) == [.text("early"), .text("late")])
    }

    @Test func noPlaintextOnDisk() throws {
        let s = try store()
        try s.upsert(contact)
        let m = message("SECRET-CANARY-42")
        try s.append(m)
        try s.writeAttachment(Data("ATTACH-CANARY-42".utf8), messageID: m.id)
        #expect(try s.readAttachment(messageID: m.id) == Data("ATTACH-CANARY-42".utf8))
        let bytes = allFileBytes()
        #expect(bytes.range(of: Data("SECRET-CANARY-42".utf8)) == nil)
        #expect(bytes.range(of: Data("ATTACH-CANARY-42".utf8)) == nil)
        #expect(bytes.range(of: Data("Sam".utf8)) == nil)
    }

    @Test func wrongKeyFailsLoudly() throws {
        try store().upsert(contact)
        #expect(throws: (any Error).self) { try store(SymmetricKey(size: .bits256)) }
    }

    @Test func corruptChatMovedAside() throws {
        let s1 = try store()
        try s1.upsert(contact)
        try s1.append(message("x"))
        let chatFile = dir.appendingPathComponent("chats/\(peer.deviceID.rawValue).bin")
        try Data("junk".utf8).write(to: chatFile)
        let s2 = try store()
        #expect(s2.messages(for: peer.deviceID).isEmpty)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("chats").path)
        #expect(names.contains { $0.hasPrefix("\(peer.deviceID.rawValue).bin.corrupt-") })
        #expect(try s2.append(message("after")) == true)
        #expect(try store().messages(for: peer.deviceID).count == 1)
    }

    @Test func removeContactDeletesData() throws {
        let s = try store()
        try s.upsert(contact)
        let m = message("bye")
        try s.append(m)
        try s.writeAttachment(Data([1]), messageID: m.id)
        try s.removeContact(peer.deviceID)
        #expect(s.contacts.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("chats/\(peer.deviceID.rawValue).bin").path))
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("attachments/\(m.id.uuidString).bin").path))
    }

    @Test func deleteAndClear() throws {
        let s = try store()
        let a = message("a", at: 1), b = message("b", at: 2)
        try s.append(a)
        try s.append(b)
        try s.deleteMessage(a.id, contact: peer.deviceID)
        #expect(s.messages(for: peer.deviceID).map(\.id) == [b.id])
        try s.clearChat(peer.deviceID)
        #expect(try store().messages(for: peer.deviceID).isEmpty)
    }

    @Test func dataKeyLoadOrCreate() throws {
        let secrets = InMemorySecretStore()
        let k1 = try DataSealer.loadOrCreateKey(in: secrets)
        let k2 = try DataSealer.loadOrCreateKey(in: secrets)
        #expect(k1.withUnsafeBytes { Data($0) } == k2.withUnsafeBytes { Data($0) })
    }
}
