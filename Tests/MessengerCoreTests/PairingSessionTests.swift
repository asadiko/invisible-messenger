import Foundation
import Network
import Testing
@testable import MessengerCore

@MainActor
func hostEntry(_ node: Node) -> DiscoveredPeer {
    DiscoveredPeer(name: node.id.rawValue, endpoint: .hostPort(host: "127.0.0.1", port: node.messenger.listenerPort!), pairingOpen: true)
}

@MainActor @Suite(.serialized) struct PairingSessionTests {
    func started() async throws -> (Node, Node) {
        let a = try Node("Alice"), b = try Node("Bob")
        try await a.start()
        try await b.start()
        return (a, b)
    }

    @Test func pairsAndBecomesContacts() async throws {
        let (a, b) = try await started()
        defer { a.messenger.stop(); b.messenger.stop() }
        let host = a.messenger.startHostingPairing()
        guard case .showingCode(let code, _) = host.state else { Issue.record("no code"); return }
        #expect(a.messenger.listener.pairingOpen)
        a.directory.peers = [b.entry]
        b.directory.peers = [hostEntry(a)]
        let typed = PairingCode.display(code).lowercased()
        let joiner = b.messenger.joinPairing(code: typed)
        try await waitUntil(8) {
            if case .verify = host.state, case .verify = joiner.state { return true }
            return false
        }
        guard case .verify(let hostEmoji, let hostSees) = host.state,
              case .verify(let joinEmoji, let joinSees) = joiner.state else { return }
        #expect(hostEmoji == joinEmoji)
        #expect(hostSees == "Bob")
        #expect(joinSees == "Alice")
        host.confirm(true)
        joiner.confirm(true)
        try await waitUntil {
            if case .done = host.state, case .done = joiner.state { return true }
            return false
        }
        #expect(a.store.contact(b.id)?.name == "Bob")
        #expect(b.store.contact(a.id)?.name == "Alice")
        #expect(!a.messenger.listener.pairingOpen)
        b.directory.peers = [a.entry]
        try await waitUntil(8) { a.messenger.online.contains(b.id) }
        let sent = try b.messenger.sendText("paired!", to: a.id)
        try await waitUntil { b.store.message(sent.id, contact: a.id)?.status == .delivered }
    }

    @Test func wrongCodeThenTooMany() async throws {
        let (a, b) = try await started()
        defer { a.messenger.stop(); b.messenger.stop() }
        let host = a.messenger.startHostingPairing()
        b.directory.peers = [hostEntry(a)]
        var joiners: [PairingSession] = []
        for wrong in ["AAAAAAAA", "BBBBBBBB", "CCCCCCCC"] {
            let joiner = b.messenger.joinPairing(code: wrong)
            joiners.append(joiner)
            try await waitUntil(12) { if case .failed = joiner.state { return true } else { return false } }
        }
        #expect(joiners[0].state == .failed(.wrongCode))
        #expect(joiners[1].state == .failed(.wrongCode))
        try await waitUntil { host.state == .failed(.tooManyAttempts) }
        #expect(!a.messenger.listener.pairingOpen)
        #expect(a.store.contacts.isEmpty)
    }

    @Test func invalidCodeFailsImmediately() async throws {
        let (a, b) = try await started()
        defer { a.messenger.stop(); b.messenger.stop() }
        #expect(b.messenger.joinPairing(code: "nope").state == .failed(.wrongCode))
    }

    @Test func notFoundWhenNobodyHosts() async throws {
        let (a, b) = try await started()
        defer { a.messenger.stop(); b.messenger.stop() }
        b.messenger.pairingSearchTimeout = 0.5
        let joiner = b.messenger.joinPairing(code: "K7Q4M2XP")
        try await waitUntil { joiner.state == .failed(.notFound) }
    }

    @Test func rejectOnEitherSide() async throws {
        let (a, b) = try await started()
        defer { a.messenger.stop(); b.messenger.stop() }
        let host = a.messenger.startHostingPairing()
        guard case .showingCode(let code, _) = host.state else { return }
        b.directory.peers = [hostEntry(a)]
        let joiner = b.messenger.joinPairing(code: code)
        try await waitUntil(8) {
            if case .verify = host.state, case .verify = joiner.state { return true }
            return false
        }
        host.confirm(true)
        joiner.confirm(false)
        try await waitUntil { host.state == .failed(.rejected) && joiner.state == .failed(.rejected) }
        #expect(a.store.contacts.isEmpty)
        #expect(b.store.contacts.isEmpty)
    }

    @Test func expiresAfterTimeout() async throws {
        let (a, b) = try await started()
        defer { a.messenger.stop(); b.messenger.stop() }
        a.messenger.pairingTimeout = 0.5
        let host = a.messenger.startHostingPairing()
        try await waitUntil { host.state == .failed(.expired) }
        #expect(!a.messenger.listener.pairingOpen)
    }
}
