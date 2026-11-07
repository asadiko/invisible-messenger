import CryptoKit
import Foundation
import Testing
@testable import MessengerCore

/// Runs a handshake to completion, alternating messages between the two sides.
func exchange(_ first: HandshakeMachine, _ second: HandshakeMachine) throws {
    var next = first.start()
    var toSecond = true
    while let message = next {
        next = try (toSecond ? second : first).receive(message)
        toSecond.toggle()
    }
}

@Suite struct HandshakeTests {
    let code = "K7Q4M2XP"

    @Test func pairingSucceedsWithSameCode() throws {
        let alice = DeviceIdentity.generate(), bob = DeviceIdentity.generate()
        let joiner = PairingHandshake(role: .joiner, code: code, identity: bob, displayName: "Bob")
        let host = PairingHandshake(role: .host, code: code, identity: alice, displayName: "Alice")
        try exchange(joiner, host)
        let j = try #require(joiner.result), h = try #require(host.result)
        #expect(j.peerID == alice.deviceID)
        #expect(j.peerName == "Alice")
        #expect(h.peerID == bob.deviceID)
        #expect(h.peerName == "Bob")
        #expect(j.peerPublicKey == alice.publicKeyData)
        #expect(j.emoji.count == 4)
        #expect(j.emoji == h.emoji)
        var cj = SecureChannel(keys: j.keys), ch = SecureChannel(keys: h.keys)
        #expect(try ch.open(cj.seal(Data("to host".utf8))) == Data("to host".utf8))
        #expect(try cj.open(ch.seal(Data("to joiner".utf8))) == Data("to joiner".utf8))
    }

    @Test func pairingWrongCodeFails() throws {
        let joiner = PairingHandshake(role: .joiner, code: "AAAAAAAA", identity: .generate(), displayName: "Bob")
        let host = PairingHandshake(role: .host, code: "BBBBBBBB", identity: .generate(), displayName: "Alice")
        let m1 = try #require(joiner.start())
        let m2 = try #require(try host.receive(m1))
        let m3 = try #require(try joiner.receive(m2))
        #expect(throws: HandshakeError.authenticationFailed) { try host.receive(m3) }
        #expect(host.result == nil)
    }

    @Test func pairingMitmChangesEmoji() throws {
        let alice = DeviceIdentity.generate(), bob = DeviceIdentity.generate()
        let joiner = PairingHandshake(role: .joiner, code: code, identity: bob, displayName: "Bob")
        let fakeHost = PairingHandshake(role: .host, code: code, identity: .generate(), displayName: "Alice")
        let fakeJoiner = PairingHandshake(role: .joiner, code: code, identity: .generate(), displayName: "Bob")
        let host = PairingHandshake(role: .host, code: code, identity: alice, displayName: "Alice")
        try exchange(joiner, fakeHost)
        try exchange(fakeJoiner, host)
        let j = try #require(joiner.result), h = try #require(host.result)
        #expect(j.emoji != h.emoji)
        #expect(j.peerPublicKey != alice.publicKeyData)
        #expect(h.peerPublicKey != bob.publicKeyData)
    }

    @Test func sessionSucceedsWithPinnedKeys() throws {
        let a = DeviceIdentity.generate(), b = DeviceIdentity.generate()
        let aKey = a.publicKeyData, aID = a.deviceID
        let i = SessionHandshake(initiator: a, peerPublicKey: b.publicKeyData)
        let r = SessionHandshake(responder: b, lookup: { $0 == aID ? aKey : nil })
        try exchange(i, r)
        let ir = try #require(i.result), rr = try #require(r.result)
        #expect(ir.peerID == b.deviceID)
        #expect(rr.peerID == a.deviceID)
        var ci = SecureChannel(keys: ir.keys), cr = SecureChannel(keys: rr.keys)
        #expect(try cr.open(ci.seal(Data("ping".utf8))) == Data("ping".utf8))
        #expect(try ci.open(cr.seal(Data("pong".utf8))) == Data("pong".utf8))
    }

    @Test func sessionRejectsUnknownInitiator() throws {
        let i = SessionHandshake(initiator: .generate(), peerPublicKey: DeviceIdentity.generate().publicKeyData)
        let r = SessionHandshake(responder: .generate(), lookup: { _ in nil })
        let m1 = try #require(i.start())
        #expect(throws: HandshakeError.unknownPeer) { try r.receive(m1) }
    }

    @Test func sessionRejectsImpostor() throws {
        let victim = DeviceIdentity.generate(), attacker = DeviceIdentity.generate(), b = DeviceIdentity.generate()
        let victimKey = victim.publicKeyData, victimID = victim.deviceID
        let impostor = SessionHandshake(initiator: attacker, peerPublicKey: b.publicKeyData)
        let r = SessionHandshake(responder: b, lookup: { $0 == victimID ? victimKey : nil })
        var hello = try SessionHello1.decode(try #require(impostor.start()))
        hello.id = victimID.rawValue
        let m2 = try #require(try r.receive(hello.encoded()))
        #expect(throws: HandshakeError.authenticationFailed) { try impostor.receive(m2) }
        let forged = try SessionFinished(fin: Data((0..<64).map { _ in UInt8.random(in: 0...255) })).encoded()
        #expect(throws: HandshakeError.authenticationFailed) { try r.receive(forged) }
        #expect(r.result == nil)
    }

    @Test func sessionInitiatorRejectsWrongResponder() throws {
        let a = DeviceIdentity.generate(), b = DeviceIdentity.generate(), expected = DeviceIdentity.generate()
        let aKey = a.publicKeyData, aID = a.deviceID
        let i = SessionHandshake(initiator: a, peerPublicKey: expected.publicKeyData)
        let r = SessionHandshake(responder: b, lookup: { $0 == aID ? aKey : nil })
        let m1 = try #require(i.start())
        let m2 = try #require(try r.receive(m1))
        #expect(throws: HandshakeError.authenticationFailed) { try i.receive(m2) }
    }
}
