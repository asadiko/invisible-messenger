import CryptoKit
import Foundation

public enum HandshakeError: Error, Equatable, Sendable {
    case malformed
    case versionMismatch
    case authenticationFailed
    case unknownPeer
    case outOfOrder
}

/// A message-driven handshake: `start()` yields the first message (initiators only),
/// `receive(_:)` consumes a peer message and yields the reply, or nil when there is nothing to send.
public protocol HandshakeMachine: AnyObject {
    func start() -> Data?
    func receive(_ message: Data) throws -> Data?
}

let protocolVersion = 1

// MARK: - Wire structs (binary plist)

protocol HandshakeMessage: Codable {}

extension HandshakeMessage {
    func encoded() throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> Self {
        do {
            return try PropertyListDecoder().decode(Self.self, from: data)
        } catch {
            throw HandshakeError.malformed
        }
    }
}

struct PairHello: HandshakeMessage {
    var v: Int
    var eph: Data
    var nonce: Data
}

struct PairIdentity: HandshakeMessage {
    var publicKey: Data
    var name: String
}

struct SealedPayload: HandshakeMessage {
    var box: Data
}

struct SessionHello1: HandshakeMessage {
    var v: Int
    var id: String
    var eph: Data
}

struct SessionHello2: HandshakeMessage {
    var v: Int
    var eph: Data
    var fin: Data
}

struct SessionFinished: HandshakeMessage {
    var fin: Data
}

// MARK: - Helpers

private let zeroNonce = try! ChaChaPoly.Nonce(data: Data(count: 12))

private func bytes(_ key: SymmetricKey) -> Data { key.withUnsafeBytes { Data($0) } }
private func bytes(_ secret: SharedSecret) -> Data { secret.withUnsafeBytes { Data($0) } }
private func sha256(_ data: Data) -> Data { Data(SHA256.hash(data: data)) }

private func hkdf(_ ikm: Data, salt: Data, info: String, count: Int) -> Data {
    bytes(HKDF<SHA256>.deriveKey(
        inputKeyMaterial: SymmetricKey(data: ikm),
        salt: salt,
        info: Data(info.utf8),
        outputByteCount: count
    ))
}

private func dh(_ priv: Curve25519.KeyAgreement.PrivateKey, _ pub: Data) throws -> Data {
    guard let key = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: pub) else {
        throw HandshakeError.malformed
    }
    return bytes(try priv.sharedSecretFromKeyAgreement(with: key))
}

private func sealOnce(_ plaintext: Data, key: Data) throws -> Data {
    let box = try ChaChaPoly.seal(plaintext, using: SymmetricKey(data: key), nonce: zeroNonce)
    return box.ciphertext + box.tag
}

private func openOnce(_ data: Data, key: Data) throws -> Data {
    guard data.count >= 16,
          let box = try? ChaChaPoly.SealedBox(nonce: zeroNonce, ciphertext: data.dropLast(16), tag: data.suffix(16)),
          let plain = try? ChaChaPoly.open(box, using: SymmetricKey(data: key))
    else { throw HandshakeError.authenticationFailed }
    return plain
}

private func checkVersion(_ v: Int) throws {
    guard v == protocolVersion else { throw HandshakeError.versionMismatch }
}

private func splitChannelKeys(_ okm: Data, info: String, firstSendsWithFirstHalf: Bool) -> SessionKeys {
    let material = hkdf(okm, salt: Data(), info: info, count: 64)
    let a = SymmetricKey(data: material.prefix(32)), b = SymmetricKey(data: material.suffix(32))
    return firstSendsWithFirstHalf ? SessionKeys(sendKey: a, receiveKey: b) : SessionKeys(sendKey: b, receiveKey: a)
}

// MARK: - Pairing

public struct PairingResult: Sendable {
    public let peerID: DeviceID
    public let peerName: String
    public let peerPublicKey: Data
    public let emoji: [String]
    public let keys: SessionKeys
}

/// Code-authenticated key exchange used once to introduce two Macs.
///
/// J→H hello · H→J hello · J→H sealed identity · H→J sealed identity.
/// Keys mix an ephemeral X25519 secret with the PBKDF2-stretched code, so only someone who knows the
/// code can complete it, and a wrong guess can't be checked offline cheaply.
public final class PairingHandshake: HandshakeMachine {
    public enum Role: Sendable { case host, joiner }

    private enum State { case initial, awaitingHello, awaitingIdentity, done }

    private let role: Role
    private let code: String
    private let identity: DeviceIdentity
    private let displayName: String
    private let eph = Curve25519.KeyAgreement.PrivateKey()
    private let nonce = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
    private var state = State.initial
    private var firstMessage = Data()
    private var keyJH = Data(), keyHJ = Data(), keySAS = Data(), okm = Data()

    public private(set) var result: PairingResult?

    public init(role: Role, code: String, identity: DeviceIdentity, displayName: String) {
        self.role = role
        self.code = PairingCode.normalize(code) ?? code
        self.identity = identity
        self.displayName = displayName
    }

    public func start() -> Data? {
        guard state == .initial else { return nil }
        state = .awaitingHello
        guard role == .joiner else { return nil }
        firstMessage = try! PairHello(v: protocolVersion, eph: eph.publicKey.rawRepresentation, nonce: nonce).encoded()
        return firstMessage
    }

    public func receive(_ message: Data) throws -> Data? {
        if state == .initial { _ = start() }
        switch (role, state) {
        case (.host, .awaitingHello):
            let hello = try PairHello.decode(message)
            try checkVersion(hello.v)
            let reply = try PairHello(v: protocolVersion, eph: eph.publicKey.rawRepresentation, nonce: nonce).encoded()
            try deriveKeys(peerEph: hello.eph, nonceJ: hello.nonce, nonceH: nonce, transcript: message + reply)
            state = .awaitingIdentity
            return reply

        case (.joiner, .awaitingHello):
            let hello = try PairHello.decode(message)
            try checkVersion(hello.v)
            try deriveKeys(peerEph: hello.eph, nonceJ: nonce, nonceH: hello.nonce, transcript: firstMessage + message)
            state = .awaitingIdentity
            return try sealedIdentity(key: keyJH)

        case (.host, .awaitingIdentity):
            let peer = try openIdentity(message, key: keyJH)
            let reply = try sealedIdentity(key: keyHJ)
            finish(peer: peer, joinerKey: peer.publicKey, hostKey: identity.publicKeyData)
            return reply

        case (.joiner, .awaitingIdentity):
            let peer = try openIdentity(message, key: keyHJ)
            finish(peer: peer, joinerKey: identity.publicKeyData, hostKey: peer.publicKey)
            return nil

        default:
            throw HandshakeError.outOfOrder
        }
    }

    private func deriveKeys(peerEph: Data, nonceJ: Data, nonceH: Data, transcript: Data) throws {
        let shared = try dh(eph, peerEph)
        let stretched = bytes(PairingCode.stretch(code, salt: nonceJ + nonceH))
        okm = hkdf(shared + stretched, salt: sha256(transcript), info: "invmsg pair v1", count: 96)
        keyJH = okm.prefix(32)
        keyHJ = okm.dropFirst(32).prefix(32)
        keySAS = okm.suffix(32)
    }

    private func sealedIdentity(key: Data) throws -> Data {
        let plain = try PairIdentity(publicKey: identity.publicKeyData, name: displayName).encoded()
        return try SealedPayload(box: sealOnce(plain, key: key)).encoded()
    }

    private func openIdentity(_ message: Data, key: Data) throws -> PairIdentity {
        let sealed = try SealedPayload.decode(message)
        let peer = try PairIdentity.decode(try openOnce(sealed.box, key: key))
        guard peer.publicKey.count == 32 else { throw HandshakeError.malformed }
        return peer
    }

    private func finish(peer: PairIdentity, joinerKey: Data, hostKey: Data) {
        let emoji = EmojiFingerprint.emojis(for: sha256(keySAS + joinerKey + hostKey))
        result = PairingResult(
            peerID: DeviceIdentity.deviceID(for: peer.publicKey),
            peerName: String(peer.name.prefix(64)),
            peerPublicKey: peer.publicKey,
            emoji: emoji,
            keys: splitChannelKeys(okm, info: "invmsg pair channel v1", firstSendsWithFirstHalf: role == .joiner)
        )
        state = .done
    }
}

// MARK: - Session

public struct SessionResult: Sendable {
    public let peerID: DeviceID
    public let keys: SessionKeys
}

/// Mutually authenticated key exchange between already-paired Macs (pinned static keys),
/// with ephemeral keys for forward secrecy.
///
/// I→R {id, eph} · R→I {eph, fin_R} · I→R {fin_I}
public final class SessionHandshake: HandshakeMachine {
    private enum Role { case initiator, responder }
    private enum State { case initial, awaitingHello2, awaitingHello1, awaitingFinish, done }

    private let role: Role
    private let identity: DeviceIdentity
    private var peerPublicKey: Data?
    private let lookup: (@Sendable (DeviceID) -> Data?)?
    private let eph = Curve25519.KeyAgreement.PrivateKey()
    private var state = State.initial
    private var firstMessage = Data()
    private var peerID: DeviceID?
    private var transcript = Data()
    private var keyIR = Data(), keyRI = Data(), okm = Data()

    public private(set) var result: SessionResult?

    public init(initiator identity: DeviceIdentity, peerPublicKey: Data) {
        role = .initiator
        self.identity = identity
        self.peerPublicKey = peerPublicKey
        lookup = nil
    }

    public init(responder identity: DeviceIdentity, lookup: @escaping @Sendable (DeviceID) -> Data?) {
        role = .responder
        self.identity = identity
        self.lookup = lookup
        state = .awaitingHello1
    }

    public func start() -> Data? {
        guard role == .initiator, state == .initial else { return nil }
        firstMessage = try! SessionHello1(
            v: protocolVersion, id: identity.deviceID.rawValue, eph: eph.publicKey.rawRepresentation
        ).encoded()
        state = .awaitingHello2
        return firstMessage
    }

    public func receive(_ message: Data) throws -> Data? {
        switch (role, state) {
        case (.responder, .awaitingHello1):
            let hello = try SessionHello1.decode(message)
            try checkVersion(hello.v)
            let claimed = DeviceID(rawValue: hello.id)
            guard let key = lookup?(claimed), DeviceIdentity.deviceID(for: key) == claimed else {
                throw HandshakeError.unknownPeer
            }
            peerPublicKey = key
            peerID = claimed
            let ephR = eph.publicKey.rawRepresentation
            transcript = sha256(message + ephR)
            let ikm = try dh(eph, hello.eph)                       // ee
                + dh(identity.privateKey, hello.eph)               // es = DH(eI, sR)
                + dh(eph, key)                                     // se = DH(sI, eR)
                + dh(identity.privateKey, key)                     // ss
            deriveKeys(ikm)
            state = .awaitingFinish
            return try SessionHello2(v: protocolVersion, eph: ephR, fin: sealOnce(transcript, key: keyRI)).encoded()

        case (.initiator, .awaitingHello2):
            guard let key = peerPublicKey else { throw HandshakeError.outOfOrder }
            let hello = try SessionHello2.decode(message)
            try checkVersion(hello.v)
            transcript = sha256(firstMessage + hello.eph)
            let ikm = try dh(eph, hello.eph)                       // ee
                + dh(eph, key)                                     // es
                + dh(identity.privateKey, hello.eph)               // se
                + dh(identity.privateKey, key)                     // ss
            deriveKeys(ikm)
            guard try openOnce(hello.fin, key: keyRI) == transcript else { throw HandshakeError.authenticationFailed }
            let reply = try SessionFinished(fin: sealOnce(transcript, key: keyIR)).encoded()
            result = SessionResult(
                peerID: DeviceIdentity.deviceID(for: key),
                keys: splitChannelKeys(okm, info: "invmsg channel v1", firstSendsWithFirstHalf: true)
            )
            state = .done
            return reply

        case (.responder, .awaitingFinish):
            let finished = try SessionFinished.decode(message)
            guard try openOnce(finished.fin, key: keyIR) == transcript, let peerID else {
                throw HandshakeError.authenticationFailed
            }
            result = SessionResult(
                peerID: peerID,
                keys: splitChannelKeys(okm, info: "invmsg channel v1", firstSendsWithFirstHalf: false)
            )
            state = .done
            return nil

        default:
            throw HandshakeError.outOfOrder
        }
    }

    private func deriveKeys(_ ikm: Data) {
        okm = hkdf(ikm, salt: transcript, info: "invmsg session v1", count: 96)
        keyIR = okm.prefix(32)
        keyRI = okm.dropFirst(32).prefix(32)
    }
}
