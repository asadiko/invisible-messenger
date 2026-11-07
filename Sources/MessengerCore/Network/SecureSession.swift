import Foundation

public struct HandshakeTimeout: Error {}

/// Drives a `HandshakeMachine` over a framed connection until it completes, fails or times out.
@MainActor
final class HandshakeDriver {
    static var timeout: TimeInterval = 10

    private let connection: FramedConnection
    private let machine: HandshakeMachine
    private let isComplete: () -> Bool
    private var completion: ((Result<Void, Error>) -> Void)?

    init(connection: FramedConnection, machine: HandshakeMachine, isComplete: @escaping () -> Bool) {
        self.connection = connection
        self.machine = machine
        self.isComplete = isComplete
    }

    /// `kind` prefixes the first outgoing message (initiators); `firstIncoming` is a message already read by the listener.
    func run(kind: UInt8?, firstIncoming: Data?, completion: @escaping (Result<Void, Error>) -> Void) {
        self.completion = completion
        // The connection keeps this driver alive through its handlers until the handshake ends.
        connection.onFrame = { frame in self.handle(frame) }
        connection.onClose = { error in self.finish(.failure(error ?? HandshakeError.malformed)) }
        connection.start()
        if let first = machine.start() {
            connection.send((kind.map { Data([$0]) } ?? Data()) + first)
        }
        if let firstIncoming { handle(firstIncoming) }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.timeout) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.completion != nil else { return }
                self.finish(.failure(HandshakeTimeout()))
                self.connection.close()
            }
        }
    }

    private func handle(_ frame: Data) {
        guard completion != nil else { return }
        do {
            if let reply = try machine.receive(frame) { connection.send(reply) }
            if isComplete() { finish(.success(())) }
        } catch {
            // Report the real error first; closing would otherwise report a generic failure.
            finish(.failure(error))
            connection.close()
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        guard let completion else { return }
        self.completion = nil
        connection.onFrame = nil
        connection.onClose = nil
        completion(result)
    }
}

/// An authenticated, encrypted connection to a paired Mac.
@MainActor
public final class SecureSession {
    /// First byte of the first frame on a session connection.
    public static let kind: UInt8 = 0x01

    public let peerID: DeviceID
    public let isInitiator: Bool
    public var onMessage: ((WireMessage) -> Void)?
    public var onClose: (() -> Void)?

    private let connection: FramedConnection
    private var channel: SecureChannel
    private var closed = false

    init(connection: FramedConnection, peerID: DeviceID, isInitiator: Bool, keys: SessionKeys) {
        self.connection = connection
        self.peerID = peerID
        self.isInitiator = isInitiator
        channel = SecureChannel(keys: keys)
        connection.onFrame = { [weak self] frame in self?.receive(frame) }
        connection.onClose = { [weak self] _ in self?.handleClose() }
    }

    public static func initiate(
        over connection: FramedConnection,
        identity: DeviceIdentity,
        peerPublicKey: Data,
        completion: @escaping (Result<SecureSession, Error>) -> Void
    ) {
        let machine = SessionHandshake(initiator: identity, peerPublicKey: peerPublicKey)
        HandshakeDriver(connection: connection, machine: machine, isComplete: { machine.result != nil })
            .run(kind: kind, firstIncoming: nil) { outcome in
                completion(outcome.flatMap {
                    guard let r = machine.result else { return .failure(HandshakeError.outOfOrder) }
                    return .success(SecureSession(connection: connection, peerID: r.peerID, isInitiator: true, keys: r.keys))
                })
            }
    }

    public static func respond(
        over connection: FramedConnection,
        firstMessage: Data,
        identity: DeviceIdentity,
        lookup: @escaping @Sendable (DeviceID) -> Data?,
        completion: @escaping (Result<SecureSession, Error>) -> Void
    ) {
        let machine = SessionHandshake(responder: identity, lookup: lookup)
        HandshakeDriver(connection: connection, machine: machine, isComplete: { machine.result != nil })
            .run(kind: nil, firstIncoming: firstMessage) { outcome in
                completion(outcome.flatMap {
                    guard let r = machine.result else { return .failure(HandshakeError.outOfOrder) }
                    return .success(SecureSession(connection: connection, peerID: r.peerID, isInitiator: false, keys: r.keys))
                })
            }
    }

    /// Returns false (and sends nothing) if the session is closed or the message would not fit in one frame.
    @discardableResult
    public func send(_ message: WireMessage, completion: (@MainActor @Sendable () -> Void)? = nil) -> Bool {
        guard !closed, let plain = try? message.encoded() else { return false }
        // Check before sealing: sealing advances the nonce counter, so a refused frame must never be sealed.
        guard plain.count + 16 <= Framing.maxFrameLength else { return false }
        do {
            connection.send(try channel.seal(plain), completion: completion)
            return true
        } catch {
            close()
            return false
        }
    }

    public func close() {
        connection.close()
        handleClose()
    }

    private func receive(_ frame: Data) {
        guard !closed else { return }
        do {
            onMessage?(try WireMessage.decode(channel.open(frame)))
        } catch {
            close()
        }
    }

    private func handleClose() {
        guard !closed else { return }
        closed = true
        let handler = onClose
        onClose = nil
        onMessage = nil
        handler?()
    }
}
