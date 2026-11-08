import CryptoKit
import Foundation
import Network
import Testing
@testable import MessengerCore

/// One app instance: its own identity, encrypted store and loopback listener.
@MainActor
final class Node {
    let identity = DeviceIdentity.generate()
    let store: ChatStore
    let directory = StaticDirectory()
    let messenger: Messenger
    var events: [MessengerEvent] = []

    init(_ name: String) throws {
        store = try ChatStore(directory: makeTempDir(), sealer: DataSealer(key: SymmetricKey(size: .bits256)))
        messenger = Messenger(.init(identity: identity, displayName: name, store: store, advertise: false, directory: directory))
        messenger.onEvent = { [weak self] in self?.events.append($0) }
    }

    var id: DeviceID { identity.deviceID }

    func start() async throws {
        try messenger.start()
        try await waitUntil { self.messenger.listenerPort != nil }
    }

    var entry: DiscoveredPeer {
        DiscoveredPeer(name: id.rawValue, endpoint: .hostPort(host: "127.0.0.1", port: messenger.listenerPort!), pairingOpen: false)
    }

    func messages(with other: Node) -> [ChatMessage] { store.messages(for: other.id) }
}

/// Pins each node's key in the other's contacts, as a finished pairing would.
@MainActor
func pinEachOther(_ a: Node, _ b: Node) throws {
    let joiner = PairingHandshake(role: .joiner, code: "K7Q4M2XP", identity: b.identity, displayName: "B")
    let host = PairingHandshake(role: .host, code: "K7Q4M2XP", identity: a.identity, displayName: "A")
    try exchange(joiner, host)
    _ = try a.messenger.addPairedContact(host.result!)
    _ = try b.messenger.addPairedContact(joiner.result!)
}

@MainActor
func link(_ a: Node, _ b: Node) {
    a.directory.peers = [b.entry]
    b.directory.peers = [a.entry]
}

@MainActor
func makePairedPair() async throws -> (Node, Node) {
    let a = try Node("A"), b = try Node("B")
    try pinEachOther(a, b)
    try await a.start()
    try await b.start()
    link(a, b)
    try await waitUntil(8) { a.messenger.online.contains(b.id) && b.messenger.online.contains(a.id) }
    return (a, b)
}

@MainActor @Suite(.serialized) struct MessengerTests {
    @Test func textIsDeliveredAndAcked() async throws {
        let (a, b) = try await makePairedPair()
        defer { a.messenger.stop(); b.messenger.stop() }
        let sent = try a.messenger.sendText("hi", to: b.id)
        try await waitUntil { a.store.message(sent.id, contact: b.id)?.status == .delivered }
        #expect(b.messages(with: a).map(\.body) == [.text("hi")])
        #expect(b.messages(with: a).first?.direction == .incoming)
        #expect(b.store.contact(a.id)?.unreadCount == 1)
        #expect(b.events.contains { if case .messageAdded(let m) = $0 { return m.id == sent.id } else { return false } })
        b.messenger.markRead(a.id)
        #expect(b.store.contact(a.id)?.unreadCount == 0)
    }

    @Test func offlineQueueFlushesOnReconnect() async throws {
        let a = try Node("A"), b = try Node("B")
        try pinEachOther(a, b)
        try await a.start()
        defer { a.messenger.stop(); b.messenger.stop() }
        let ids = try ["1", "2", "3"].map { try a.messenger.sendText($0, to: b.id).id }
        #expect(a.messages(with: b).allSatisfy { $0.status == .sending })
        try await b.start()
        link(a, b)
        try await waitUntil(8) { a.messages(with: b).allSatisfy { $0.status == .delivered } }
        #expect(b.messages(with: a).map(\.id) == ids)
    }

    @Test func simultaneousDialYieldsOneSession() async throws {
        let a = try Node("A"), b = try Node("B")
        try pinEachOther(a, b)
        a.messenger.dialGrace = 0
        b.messenger.dialGrace = 0
        try await a.start()
        try await b.start()
        defer { a.messenger.stop(); b.messenger.stop() }
        link(a, b)
        try await Task.sleep(for: .seconds(3))
        #expect(a.messenger.sessions.count == 1)
        #expect(b.messenger.sessions.count == 1)
        #expect(a.messenger.sessions[b.id]?.isInitiator != b.messenger.sessions[a.id]?.isInitiator)
        let sent = try a.messenger.sendText("once", to: b.id)
        try await waitUntil { a.store.message(sent.id, contact: b.id)?.status == .delivered }
        #expect(b.messages(with: a).count == 1)
    }

    @Test func attachmentRoundTrip() async throws {
        let (a, b) = try await makePairedPair()
        defer { a.messenger.stop(); b.messenger.stop() }
        let payload = Data((0..<1_000_000).map { _ in UInt8.random(in: 0...255) })
        let sent = try a.messenger.sendData(payload, fileName: "blob.bin", kind: .file, to: b.id)
        try await waitUntil(8) { a.store.message(sent.id, contact: b.id)?.status == .delivered }
        #expect(try b.store.readAttachment(messageID: sent.id) == payload)
        guard case .attachment(let info) = b.messages(with: a).first?.body else { Issue.record("no attachment"); return }
        #expect(info.fileName == "blob.bin")
        #expect(info.byteCount == 1_000_000)
        #expect(b.events.contains { if case .transferProgress(sent.id, _) = $0 { return true } else { return false } })
    }

    @Test func attachmentSizeLimit() async throws {
        let a = try Node("A"), b = try Node("B")
        try pinEachOther(a, b)
        #expect(throws: MessengerError.attachmentTooLarge) {
            try a.messenger.sendData(Data(count: 104_857_601), fileName: "big", kind: .file, to: b.id)
        }
        let ok = try a.messenger.sendData(Data(count: 104_857_600), fileName: "max", kind: .file, to: b.id)
        #expect(ok.status == .sending)
        #expect(throws: MessengerError.unreadableFile) {
            try a.messenger.sendFile(at: URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString)"), kind: .file, to: b.id)
        }
        #expect(throws: MessengerError.unknownContact) {
            try a.messenger.sendText("x", to: DeviceID(rawValue: "0000000000000000"))
        }
    }

    @Test func transferResumesAfterDrop() async throws {
        let (a, b) = try await makePairedPair()
        defer { a.messenger.stop(); b.messenger.stop() }
        var dropped = false
        b.messenger.onEvent = { event in
            b.events.append(event)
            if case .transferProgress = event, !dropped {
                dropped = true
                b.messenger.sessions[a.id]?.close()
            }
        }
        let payload = Data((0..<3_000_000).map { UInt8($0 % 253) })
        let sent = try a.messenger.sendData(payload, fileName: "big.bin", kind: .file, to: b.id)
        try await waitUntil(15) { a.store.message(sent.id, contact: b.id)?.status == .delivered }
        #expect(dropped)
        #expect(b.messages(with: a).count == 1)
        #expect(try b.store.readAttachment(messageID: sent.id) == payload)
    }

    @Test func removedPeerIsRejectedWithBackoff() async throws {
        let (a, b) = try await makePairedPair()
        defer { a.messenger.stop(); b.messenger.stop() }
        b.messenger.removeContact(a.id)
        try await waitUntil { !a.messenger.online.contains(b.id) }
        a.messenger.dialAttempts[b.id] = 0
        try await Task.sleep(for: .seconds(5))
        #expect(!a.messenger.online.contains(b.id))
        #expect(!b.messenger.online.contains(a.id))
        #expect((a.messenger.dialAttempts[b.id] ?? 0) <= 3)
    }

    @Test func oversizedTextIsRejected() async throws {
        let a = try Node("A"), b = try Node("B")
        try pinEachOther(a, b)
        #expect(throws: MessengerError.messageTooLarge) {
            try a.messenger.sendText(String(repeating: "x", count: 1_100_000), to: b.id)
        }
        #expect(a.messages(with: b).isEmpty)
        _ = try a.messenger.sendText(String(repeating: "y", count: 100_000), to: b.id)
        #expect(a.messages(with: b).count == 1)
    }

    @Test func incomingFileNameIsSanitized() async throws {
        let (a, b) = try await makePairedPair()
        defer { a.messenger.stop(); b.messenger.stop() }
        let sent = try a.messenger.sendData(Data("x".utf8), fileName: "../../Library/LaunchAgents/evil.plist", kind: .file, to: b.id)
        try await waitUntil { a.store.message(sent.id, contact: b.id)?.status == .delivered }
        guard case .attachment(let info) = b.messages(with: a).first?.body else { Issue.record("no attachment"); return }
        #expect(info.fileName == "evil.plist")
    }

    @Test func staleSessionIsReplacedByFreshOne() async throws {
        let (a, b) = try await makePairedPair()
        defer { a.messenger.stop(); b.messenger.stop() }
        a.messenger.duplicateWindow = 1
        b.messenger.duplicateWindow = 1
        try await Task.sleep(for: .seconds(1.5))
        // The Mac with the larger ID "restarts": it forgets its session while the socket stays half-open.
        let (larger, smaller) = a.id > b.id ? (a, b) : (b, a)
        larger.messenger.abandonSession(smaller.id)
        try await waitUntil(4) { larger.messenger.online.contains(smaller.id) }
        let sent = try larger.messenger.sendText("back", to: smaller.id)
        try await waitUntil(4) { larger.store.message(sent.id, contact: smaller.id)?.status == .delivered }
    }

    @Test func backoffResetsWhenPeerReappears() async throws {
        let a = try Node("A"), b = try Node("B")
        try pinEachOther(a, b)
        a.messenger.dialGrace = 0
        try await a.start()
        try await b.start()
        defer { a.messenger.stop(); b.messenger.stop() }
        let staleEntry = b.entry
        b.messenger.stop()
        a.directory.peers = [staleEntry]
        // Dials to the vanished address fail until A is in a backoff longer than the 3 s we allow below.
        try await waitUntil(30) { (a.messenger.backoffRemaining(for: b.id) ?? 0) > 3 }
        try await b.start()
        // Only A can see B, so only A's dialing can reconnect them.
        a.directory.peers = []
        a.directory.peers = [b.entry]
        try await waitUntil(3) { a.messenger.online.contains(b.id) }
    }

    @Test func stoppedMessengerTakesNoNewSessions() async throws {
        let a = try Node("A"), b = try Node("B")
        try pinEachOther(a, b)
        b.messenger.dialGrace = 0
        try await a.start()
        try await b.start()
        defer { a.messenger.stop() }
        // Only B can dial; its dial is still in flight when it stops.
        b.directory.peers = [a.entry]
        b.messenger.stop()
        try await Task.sleep(for: .seconds(2))
        #expect(b.messenger.sessions.isEmpty)
        #expect(!b.messenger.online.contains(a.id))
        #expect(!a.messenger.online.contains(b.id))
    }
}

