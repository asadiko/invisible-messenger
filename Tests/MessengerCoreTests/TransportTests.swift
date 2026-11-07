import Foundation
import Network
import Testing
@testable import MessengerCore

struct TimeoutError: Error {}

/// Polls `condition` on the main actor until it is true or `seconds` pass.
@MainActor
func waitUntil(_ seconds: Double = 5, _ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(seconds)
    while !condition() {
        if Date() > deadline { throw TimeoutError() }
        try await Task.sleep(for: .milliseconds(20))
    }
}

@MainActor
func readyListener(_ name: String = "test") async throws -> PeerListener {
    let listener = PeerListener(name: name, advertise: false)
    try listener.start()
    try await waitUntil { listener.port != nil }
    return listener
}

@MainActor
func loopback(_ listener: PeerListener) -> NWEndpoint {
    .hostPort(host: "127.0.0.1", port: listener.port!)
}

@MainActor @Suite(.serialized) struct TransportTests {
    @Test func framesTravelBothWays() async throws {
        let listener = try await readyListener()
        defer { listener.stop() }
        var server: FramedConnection?
        var firstKind: UInt8?, firstBody: Data?
        var serverGot: [Data] = []
        listener.onConnection = { conn, kind, body in
            server = conn
            firstKind = kind
            firstBody = body
            conn.onFrame = { serverGot.append($0); conn.send($0) }
        }
        let client = FramedConnection(endpoint: loopback(listener))
        var clientGot: [Data] = []
        client.onFrame = { clientGot.append($0) }
        client.start()
        let big = Data((0..<300_000).map { UInt8($0 % 251) })
        client.send(Data([0x09]) + Data("xyz".utf8))
        client.send(Data("abc".utf8))
        client.send(big)
        try await waitUntil { clientGot.count == 2 }
        #expect(firstKind == 0x09)
        #expect(firstBody == Data("xyz".utf8))
        #expect(serverGot == [Data("abc".utf8), big])
        #expect(clientGot == [Data("abc".utf8), big])
        client.close()
        _ = server
    }

    @Test func secureSessionExchangesMessages() async throws {
        let a = DeviceIdentity.generate(), b = DeviceIdentity.generate()
        let aKey = a.publicKeyData, aID = a.deviceID
        let listener = try await readyListener()
        defer { listener.stop() }
        var serverSession: SecureSession?
        var serverGot: [WireMessage] = []
        listener.onConnection = { conn, kind, first in
            #expect(kind == SecureSession.kind)
            SecureSession.respond(over: conn, firstMessage: first, identity: b, lookup: { $0 == aID ? aKey : nil }) { result in
                serverSession = try? result.get()
                serverSession?.onMessage = { message in
                    serverGot.append(message)
                    if case .text(let id, _, _) = message { serverSession?.send(.ack(id: id)) }
                }
            }
        }
        var clientSession: SecureSession?
        var clientGot: [WireMessage] = []
        SecureSession.initiate(over: FramedConnection(endpoint: loopback(listener)), identity: a, peerPublicKey: b.publicKeyData) { result in
            clientSession = try? result.get()
            clientSession?.onMessage = { clientGot.append($0) }
        }
        try await waitUntil { clientSession != nil && serverSession != nil }
        #expect(clientSession?.peerID == b.deviceID)
        #expect(clientSession?.isInitiator == true)
        #expect(serverSession?.peerID == a.deviceID)
        let id = UUID()
        clientSession?.send(.text(id: id, sentAt: Date(timeIntervalSince1970: 1), body: "hi"))
        try await waitUntil { clientGot.count == 1 }
        #expect(serverGot == [.text(id: id, sentAt: Date(timeIntervalSince1970: 1), body: "hi")])
        #expect(clientGot == [.ack(id: id)])
        clientSession?.close()
    }

    @Test func unknownInitiatorIsRejected() async throws {
        let a = DeviceIdentity.generate(), b = DeviceIdentity.generate()
        let listener = try await readyListener()
        defer { listener.stop() }
        var serverFailed = false
        listener.onConnection = { conn, _, first in
            SecureSession.respond(over: conn, firstMessage: first, identity: b, lookup: { _ in nil }) { result in
                if case .failure = result { serverFailed = true }
            }
        }
        var clientResult: Result<SecureSession, Error>?
        SecureSession.initiate(over: FramedConnection(endpoint: loopback(listener)), identity: a, peerPublicKey: b.publicKeyData) {
            clientResult = $0
        }
        try await waitUntil { clientResult != nil && serverFailed }
        #expect((try? clientResult?.get()) == nil)
    }

    @Test func listenerRoutesPairingKind() async throws {
        let listener = try await readyListener()
        defer { listener.stop() }
        var routed: UInt8?
        listener.onConnection = { _, kind, _ in routed = kind }
        let client = FramedConnection(endpoint: loopback(listener))
        client.start()
        client.send(Data([0x02, 0xAA]))
        try await waitUntil { routed != nil }
        #expect(routed == 0x02)
        client.close()
    }

    @Test func staticDirectoryPublishesChanges() async throws {
        let directory = StaticDirectory()
        var seen: [[DiscoveredPeer]] = []
        directory.onChange = { seen.append($0) }
        directory.start()
        let peer = DiscoveredPeer(name: "abc", endpoint: .hostPort(host: "127.0.0.1", port: 9), pairingOpen: true)
        directory.peers = [peer]
        #expect(seen.last == [peer])
    }
}
