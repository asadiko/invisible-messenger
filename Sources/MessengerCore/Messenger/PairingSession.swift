import Foundation

public enum PairingFailure: Error, Equatable, Sendable {
    case wrongCode
    case tooManyAttempts
    case expired
    case notFound
    case rejected
    case cancelled
    case network
}

/// One attempt to introduce two Macs: the host shows a code, the joiner types it,
/// both compare four emoji, and the contact is saved only when both people confirm.
@MainActor
public final class PairingSession {
    public enum Role: Sendable { case host, joiner }

    public enum State: Equatable, Sendable {
        case showingCode(code: String, expiresAt: Date)
        case connecting
        case verify(emoji: [String], peerName: String)
        case waitingForPeer
        case done(Contact)
        case failed(PairingFailure)
    }

    static let maxFailedAttempts = 3

    public let role: Role
    public private(set) var state: State {
        didSet { if state != oldValue { onStateChange?(state) } }
    }
    public var onStateChange: ((State) -> Void)?

    private weak var messenger: Messenger?
    private let code: String?
    private var connection: FramedConnection?
    private var channel: SecureChannel?
    private var result: PairingResult?
    private var localAccepted = false
    private var remoteAccepted = false
    private var failedAttempts = 0
    private var tried: Set<String> = []
    private var sawWrongCode = false
    private var timer: Task<Void, Never>?

    public var isFinished: Bool {
        switch state {
        case .done, .failed: true
        default: false
        }
    }

    init(hostFor messenger: Messenger, timeout: TimeInterval) {
        role = .host
        self.messenger = messenger
        let code = PairingCode.generate()
        self.code = code
        state = .showingCode(code: code, expiresAt: Date().addingTimeInterval(timeout))
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard let self, !Task.isCancelled, !self.isFinished else { return }
            if case .showingCode = self.state { self.fail(.expired) }
        }
    }

    init(joinFor messenger: Messenger, code: String, searchTimeout: TimeInterval) {
        role = .joiner
        self.messenger = messenger
        self.code = PairingCode.normalize(code)
        guard self.code != nil else {
            state = .failed(.wrongCode)
            return
        }
        state = .connecting
        let deadline = Date().addingTimeInterval(searchTimeout)
        timer = Task { [weak self] in
            while let self, !Task.isCancelled, !self.isFinished {
                if self.connection == nil { self.tryNextHost(deadline: deadline) }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    /// Answers whether the emoji on both Macs match.
    public func confirm(_ match: Bool) {
        guard case .verify = state else { return }
        sendConfirm(match)
        guard match else {
            fail(.rejected)
            return
        }
        localAccepted = true
        if remoteAccepted { finish() } else { state = .waitingForPeer }
    }

    public func cancel() {
        guard !isFinished else { return }
        if channel != nil { sendConfirm(false) }
        fail(.cancelled)
    }

    // MARK: Host

    func acceptIncoming(_ incoming: FramedConnection, firstMessage: Data) {
        guard let messenger, !isFinished, connection == nil, let code, case .showingCode = state else {
            incoming.close()
            return
        }
        connection = incoming
        let machine = PairingHandshake(role: .host, code: code, identity: messenger.identity, displayName: messenger.displayName)
        HandshakeDriver(connection: incoming, machine: machine, isComplete: { machine.result != nil })
            .run(kind: nil, firstIncoming: firstMessage) { [weak self] outcome in
                guard let self else { return }
                if case .success = outcome, let result = machine.result {
                    self.beginVerify(incoming, result)
                    return
                }
                self.connection = nil
                if case .failure(let error) = outcome, error as? HandshakeError == .authenticationFailed {
                    self.failedAttempts += 1
                    if self.failedAttempts >= Self.maxFailedAttempts { self.fail(.tooManyAttempts) }
                }
            }
    }

    // MARK: Joiner

    private func tryNextHost(deadline: Date) {
        guard let messenger, let code else { return }
        let candidates = messenger.discovered.filter { $0.pairingOpen && !tried.contains($0.name) }
        guard let peer = candidates.first else {
            if !tried.isEmpty {
                fail(sawWrongCode ? .wrongCode : .network)
            } else if Date() >= deadline {
                fail(.notFound)
            }
            return
        }
        tried.insert(peer.name)
        let outgoing = FramedConnection(endpoint: peer.endpoint)
        connection = outgoing
        let machine = PairingHandshake(role: .joiner, code: code, identity: messenger.identity, displayName: messenger.displayName)
        HandshakeDriver(connection: outgoing, machine: machine, isComplete: { machine.result != nil })
            .run(kind: Messenger.pairingKind, firstIncoming: nil) { [weak self] outcome in
                guard let self else { return }
                if case .success = outcome, let result = machine.result {
                    self.beginVerify(outgoing, result)
                    return
                }
                // The host hangs up right after failing to open our sealed identity: that means a wrong code.
                if machine.sentIdentity { self.sawWrongCode = true }
                self.connection = nil
            }
    }

    // MARK: Shared

    private func beginVerify(_ connection: FramedConnection, _ result: PairingResult) {
        guard !isFinished else {
            connection.close()
            return
        }
        self.connection = connection
        self.result = result
        channel = SecureChannel(keys: result.keys)
        connection.onFrame = { [weak self] frame in self?.receive(frame) }
        connection.onClose = { [weak self] _ in
            guard let self, !self.isFinished else { return }
            self.connection = nil
            self.fail(.network)
        }
        state = .verify(emoji: result.emoji, peerName: result.peerName)
    }

    private func receive(_ frame: Data) {
        guard var channel, !isFinished else { return }
        guard let plain = try? channel.open(frame), case .pairConfirm(let accepted)? = try? WireMessage.decode(plain) else {
            fail(.network)
            return
        }
        self.channel = channel
        guard accepted else {
            fail(.rejected)
            return
        }
        remoteAccepted = true
        if localAccepted { finish() }
    }

    private func sendConfirm(_ accepted: Bool) {
        guard var channel, let connection, let payload = try? channel.seal(WireMessage.pairConfirm(accepted: accepted).encoded()) else {
            return
        }
        self.channel = channel
        connection.send(payload)
    }

    private func finish() {
        guard let messenger, let result, !isFinished else { return }
        do {
            state = .done(try messenger.addPairedContact(result))
        } catch {
            state = .failed(.network)
        }
        end()
    }

    private func fail(_ reason: PairingFailure) {
        guard !isFinished else { return }
        state = .failed(reason)
        end()
    }

    private func end() {
        timer?.cancel()
        timer = nil
        messenger?.pairingEnded(self)
        if let connection {
            connection.onFrame = nil
            connection.onClose = nil
            // Give the last confirmation a moment to leave before hanging up.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { connection.close() }
        }
        connection = nil
    }
}

extension Messenger {
    /// Shows a fresh code and accepts pairing connections until it is used, expires or is cancelled.
    public func startHostingPairing() -> PairingSession {
        hostingPairing?.cancel()
        let session = PairingSession(hostFor: self, timeout: pairingTimeout)
        hostingPairing = session
        pairingConnectionHandler = { [weak session] connection, first in
            if let session { session.acceptIncoming(connection, firstMessage: first) } else { connection.close() }
        }
        listener.pairingOpen = true
        return session
    }

    /// Looks for a Mac showing a code on this network and pairs with it using `code`.
    public func joinPairing(code: String) -> PairingSession {
        PairingSession(joinFor: self, code: code, searchTimeout: pairingSearchTimeout)
    }

    func pairingEnded(_ session: PairingSession) {
        guard hostingPairing === session else { return }
        hostingPairing = nil
        pairingConnectionHandler = nil
        listener.pairingOpen = false
    }
}
