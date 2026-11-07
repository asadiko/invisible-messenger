import CryptoKit
import Foundation
import Network

public enum MessengerEvent: Sendable {
    case messageAdded(ChatMessage)
    case messageUpdated(ChatMessage)
    case messageRemoved(UUID, DeviceID)
    case contactsChanged
    case presenceChanged(DeviceID, online: Bool)
    case transferProgress(UUID, Double)
}

public enum MessengerError: Error, Equatable, Sendable {
    case attachmentTooLarge
    case unreadableFile
    case unknownContact
}

/// Connects to paired Macs, keeps an outbox, and moves messages and attachments both ways.
@MainActor
public final class Messenger {
    public struct Configuration {
        public var identity: DeviceIdentity
        public var displayName: String
        public var store: ChatStore
        public var listenPort: NWEndpoint.Port
        public var advertise: Bool
        public var directory: PeerDirectory

        public init(
            identity: DeviceIdentity,
            displayName: String,
            store: ChatStore,
            listenPort: NWEndpoint.Port = .any,
            advertise: Bool,
            directory: PeerDirectory
        ) {
            self.identity = identity
            self.displayName = displayName
            self.store = store
            self.listenPort = listenPort
            self.advertise = advertise
            self.directory = directory
        }
    }

    private struct IncomingTransfer {
        let peer: DeviceID
        let sentAt: Date
        let info: AttachmentInfo
        var data: Data
        var nextIndex: Int
    }

    private struct Backoff {
        var delay: TimeInterval
        var next: Date
    }

    /// First byte of the first frame on a pairing connection.
    public static let pairingKind: UInt8 = 0x02
    static let pingInterval: TimeInterval = 15
    static let silenceTimeout: TimeInterval = 45

    public var onEvent: ((MessengerEvent) -> Void)?
    public private(set) var online: Set<DeviceID> = []
    public var displayName: String
    public let store: ChatStore
    public let identity: DeviceIdentity
    public var myID: DeviceID { identity.deviceID }
    public var listenerPort: NWEndpoint.Port? { listener.port }
    /// Peers currently visible on the network (excluding this Mac).
    public private(set) var discovered: [DiscoveredPeer] = []

    /// How long the Mac with the larger ID waits before dialing a peer it can see.
    var dialGrace: TimeInterval = 3
    var dialAttempts: [DeviceID: Int] = [:]
    private(set) var sessions: [DeviceID: SecureSession] = [:]

    let listener: PeerListener
    let directory: PeerDirectory
    private var dialing: Set<DeviceID> = []
    private var firstSeen: [DeviceID: Date] = [:]
    private var backoff: [DeviceID: Backoff] = [:]
    private var lastHeard: [DeviceID: Date] = [:]
    private var lastSent: [DeviceID: Date] = [:]
    private var incoming: [UUID: IncomingTransfer] = [:]
    /// Attachment transfers in progress, keyed by message id, valued by the session carrying them.
    private var outgoingInFlight: [UUID: ObjectIdentifier] = [:]
    private var ticker: Task<Void, Never>?
    var pairingConnectionHandler: ((FramedConnection, Data) -> Void)?
    var onDiscoveredChange: (() -> Void)?

    public init(_ config: Configuration) {
        identity = config.identity
        displayName = config.displayName
        store = config.store
        directory = config.directory
        listener = PeerListener(name: config.identity.deviceID.rawValue, port: config.listenPort, advertise: config.advertise)
    }

    // MARK: Lifecycle

    public func start() throws {
        listener.onConnection = { [weak self] connection, kind, first in
            self?.route(connection, kind: kind, first: first)
        }
        try listener.start()
        directory.onChange = { [weak self] peers in self?.peersChanged(peers) }
        directory.start()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.tick()
            }
        }
    }

    public func stop() {
        ticker?.cancel()
        ticker = nil
        directory.stop()
        listener.stop()
        for session in sessions.values {
            session.onClose = nil
            session.close()
        }
        sessions.removeAll()
        let wasOnline = online
        online.removeAll()
        incoming.removeAll()
        outgoingInFlight.removeAll()
        wasOnline.forEach { emit(.presenceChanged($0, online: false)) }
    }

    // MARK: Public actions

    @discardableResult
    public func sendText(_ text: String, to contact: DeviceID) throws -> ChatMessage {
        guard store.contact(contact) != nil else { throw MessengerError.unknownContact }
        let message = ChatMessage(contactID: contact, direction: .outgoing, body: .text(text), status: .sending)
        try store.append(message)
        emit(.messageAdded(message))
        if let session = sessions[contact] { transmit(message, over: session) }
        return message
    }

    @discardableResult
    public func sendFile(at url: URL, kind: AttachmentKind, to contact: DeviceID) throws -> ChatMessage {
        guard store.contact(contact) != nil else { throw MessengerError.unknownContact }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
        if let size, size > maxAttachmentBytes { throw MessengerError.attachmentTooLarge }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { throw MessengerError.unreadableFile }
        return try sendData(data, fileName: url.lastPathComponent, kind: kind, to: contact)
    }

    @discardableResult
    public func sendData(_ data: Data, fileName: String, kind: AttachmentKind, to contact: DeviceID) throws -> ChatMessage {
        guard Int64(data.count) <= maxAttachmentBytes else { throw MessengerError.attachmentTooLarge }
        guard store.contact(contact) != nil else { throw MessengerError.unknownContact }
        let info = AttachmentInfo(
            kind: kind,
            fileName: fileName,
            byteCount: Int64(data.count),
            sha256: Data(SHA256.hash(data: data))
        )
        let message = ChatMessage(contactID: contact, direction: .outgoing, body: .attachment(info), status: .sending)
        try store.writeAttachment(data, messageID: message.id)
        try store.append(message)
        emit(.messageAdded(message))
        if let session = sessions[contact] { transmit(message, over: session) }
        return message
    }

    public func markRead(_ id: DeviceID) {
        guard var contact = store.contact(id), contact.unreadCount != 0 else { return }
        contact.unreadCount = 0
        try? store.upsert(contact)
        emit(.contactsChanged)
    }

    public func deleteMessage(_ id: UUID, contact: DeviceID) {
        try? store.deleteMessage(id, contact: contact)
        emit(.messageRemoved(id, contact))
    }

    public func clearChat(_ id: DeviceID) {
        try? store.clearChat(id)
        emit(.contactsChanged)
    }

    public func renameContact(_ id: DeviceID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var contact = store.contact(id), !trimmed.isEmpty else { return }
        contact.name = String(trimmed.prefix(64))
        try? store.upsert(contact)
        emit(.contactsChanged)
    }

    public func removeContact(_ id: DeviceID) {
        if let session = sessions.removeValue(forKey: id) {
            session.onClose = nil
            session.close()
            online.remove(id)
            emit(.presenceChanged(id, online: false))
        }
        try? store.removeContact(id)
        backoff[id] = nil
        emit(.contactsChanged)
    }

    @discardableResult
    public func addPairedContact(_ result: PairingResult) throws -> Contact {
        var contact = store.contact(result.peerID)
            ?? Contact(id: result.peerID, name: result.peerName, publicKey: result.peerPublicKey)
        contact.publicKey = result.peerPublicKey
        try store.upsert(contact)
        backoff[result.peerID] = nil
        emit(.contactsChanged)
        tick()
        return contact
    }

    // MARK: Discovery and dialing

    private func peersChanged(_ peers: [DiscoveredPeer]) {
        discovered = peers.filter { $0.name != myID.rawValue }
        let now = Date()
        let names = Set(discovered.map(\.name))
        for peer in discovered {
            let id = DeviceID(rawValue: peer.name)
            if firstSeen[id] == nil { firstSeen[id] = now }
        }
        for id in firstSeen.keys where !names.contains(id.rawValue) {
            firstSeen[id] = nil
        }
        onDiscoveredChange?()
        tick()
    }

    func tick() {
        let now = Date()
        for peer in discovered {
            let id = DeviceID(rawValue: peer.name)
            guard sessions[id] == nil, !dialing.contains(id), let contact = store.contact(id) else { continue }
            if let wait = backoff[id], now < wait.next { continue }
            let graceOver = now.timeIntervalSince(firstSeen[id] ?? now) >= dialGrace
            guard myID < id || graceOver else { continue }
            dial(id, endpoint: peer.endpoint, publicKey: contact.publicKey)
        }
        for (id, session) in sessions {
            if now.timeIntervalSince(lastHeard[id] ?? now) >= Self.silenceTimeout {
                session.close()
            } else if now.timeIntervalSince(lastSent[id] ?? .distantPast) >= Self.pingInterval {
                send(.ping, over: session)
            }
        }
    }

    private func dial(_ id: DeviceID, endpoint: NWEndpoint, publicKey: Data) {
        dialing.insert(id)
        dialAttempts[id, default: 0] += 1
        SecureSession.initiate(over: FramedConnection(endpoint: endpoint), identity: identity, peerPublicKey: publicKey) { [weak self] result in
            guard let self else { return }
            self.dialing.remove(id)
            switch result {
            case .success(let session) where session.peerID == id:
                self.backoff[id] = nil
                self.adopt(session)
            case .success(let session):
                session.close()
                self.bumpBackoff(id)
            case .failure:
                self.bumpBackoff(id)
            }
        }
    }

    private func bumpBackoff(_ id: DeviceID) {
        let delay = min((backoff[id]?.delay ?? 1) * 2, 60)
        backoff[id] = Backoff(delay: delay, next: Date().addingTimeInterval(delay))
    }

    private func route(_ connection: FramedConnection, kind: UInt8, first: Data) {
        switch kind {
        case SecureSession.kind:
            let keys = Dictionary(uniqueKeysWithValues: store.contacts.map { ($0.id, $0.publicKey) })
            SecureSession.respond(over: connection, firstMessage: first, identity: identity, lookup: { keys[$0] }) { [weak self] result in
                if case .success(let session) = result { self?.adopt(session) }
            }
        case Self.pairingKind:
            if let handler = pairingConnectionHandler { handler(connection, first) } else { connection.close() }
        default:
            connection.close()
        }
    }

    // MARK: Sessions

    private func adopt(_ session: SecureSession) {
        let id = session.peerID
        guard store.contact(id) != nil else { session.close(); return }
        if let existing = sessions[id] {
            // Both sides keep the session started by the Mac with the smaller ID.
            let keepNew = session.isInitiator == (myID < id)
            guard keepNew else { session.close(); return }
            existing.onClose = nil
            existing.close()
            dropTransfers(of: existing)
        }
        install(session)
    }

    private func install(_ session: SecureSession) {
        let id = session.peerID
        let wasOnline = online.contains(id)
        sessions[id] = session
        online.insert(id)
        lastHeard[id] = Date()
        session.onMessage = { [weak self, weak session] message in
            guard let self, let session else { return }
            self.handle(message, from: id, session: session)
        }
        session.onClose = { [weak self, weak session] in
            guard let self, let session else { return }
            self.sessionClosed(session)
        }
        if !wasOnline { emit(.presenceChanged(id, online: true)) }
        flushOutbox(id, over: session)
    }

    private func sessionClosed(_ session: SecureSession) {
        let id = session.peerID
        guard sessions[id] === session else { return }
        sessions[id] = nil
        online.remove(id)
        dropTransfers(of: session)
        emit(.presenceChanged(id, online: false))
    }

    /// Forgets partial transfers carried by a session that ended, so they restart on the next session.
    private func dropTransfers(of session: SecureSession) {
        let token = ObjectIdentifier(session)
        incoming = incoming.filter { $0.value.peer != session.peerID }
        outgoingInFlight = outgoingInFlight.filter { $0.value != token }
    }

    private func send(_ message: WireMessage, over session: SecureSession, completion: (@MainActor @Sendable () -> Void)? = nil) {
        lastSent[session.peerID] = Date()
        session.send(message, completion: completion)
    }

    // MARK: Outbox

    private func flushOutbox(_ id: DeviceID, over session: SecureSession) {
        let pending = store.messages(for: id).filter {
            $0.direction == .outgoing && ($0.status == .sending || $0.status == .sent)
        }
        pending.forEach { transmit($0, over: session) }
    }

    private func transmit(_ message: ChatMessage, over session: SecureSession) {
        switch message.body {
        case .text(let body):
            send(.text(id: message.id, sentAt: message.sentAt, body: body), over: session)
            markSent(message)
        case .attachment(let info):
            guard outgoingInFlight[message.id] == nil,
                  let data = try? store.readAttachment(messageID: message.id)
            else { return }
            outgoingInFlight[message.id] = ObjectIdentifier(session)
            send(.attachmentStart(id: message.id, sentAt: message.sentAt, info: info), over: session)
            sendChunk(0, of: data, message: message, over: session)
        }
    }

    private func sendChunk(_ index: Int, of data: Data, message: ChatMessage, over session: SecureSession) {
        let token = ObjectIdentifier(session)
        guard sessions[message.contactID] === session, outgoingInFlight[message.id] == token else {
            if outgoingInFlight[message.id] == token { outgoingInFlight[message.id] = nil }
            return
        }
        let start = index * attachmentChunkSize
        guard start < data.count || (index == 0 && data.isEmpty) else {
            send(.attachmentEnd(id: message.id), over: session)
            outgoingInFlight[message.id] = nil
            markSent(message)
            return
        }
        let end = min(start + attachmentChunkSize, data.count)
        let chunk = data.isEmpty ? Data() : data.subdata(in: start..<end)
        send(.attachmentChunk(id: message.id, index: index, data: chunk), over: session) { [weak self, weak session] in
            guard let self, let session else { return }
            self.emit(.transferProgress(message.id, data.isEmpty ? 1 : Double(end) / Double(data.count)))
            if data.isEmpty {
                self.send(.attachmentEnd(id: message.id), over: session)
                self.outgoingInFlight[message.id] = nil
                self.markSent(message)
            } else {
                self.sendChunk(index + 1, of: data, message: message, over: session)
            }
        }
    }

    private func markSent(_ message: ChatMessage) {
        guard var current = store.message(message.id, contact: message.contactID), current.status == .sending else { return }
        current.status = .sent
        try? store.update(current)
        emit(.messageUpdated(current))
    }

    // MARK: Incoming

    private func handle(_ message: WireMessage, from id: DeviceID, session: SecureSession) {
        lastHeard[id] = Date()
        switch message {
        case let .text(messageID, sentAt, body):
            let chat = ChatMessage(id: messageID, contactID: id, direction: .incoming, sentAt: sentAt, body: .text(body), status: .delivered)
            receive(chat)
            send(.ack(id: messageID), over: session)

        case let .attachmentStart(messageID, sentAt, info):
            if store.message(messageID, contact: id) != nil {
                incoming[messageID] = nil
                return
            }
            guard info.byteCount >= 0, info.byteCount <= maxAttachmentBytes else { return }
            incoming[messageID] = IncomingTransfer(
                peer: id, sentAt: sentAt, info: info,
                data: Data(capacity: Int(info.byteCount)), nextIndex: 0
            )

        case let .attachmentChunk(messageID, index, data):
            guard var transfer = incoming[messageID], transfer.peer == id else { return }
            guard index == transfer.nextIndex, Int64(transfer.data.count + data.count) <= transfer.info.byteCount else {
                incoming[messageID] = nil
                return
            }
            transfer.data.append(data)
            transfer.nextIndex += 1
            incoming[messageID] = transfer
            let total = max(transfer.info.byteCount, 1)
            emit(.transferProgress(messageID, Double(transfer.data.count) / Double(total)))

        case let .attachmentEnd(messageID):
            if store.message(messageID, contact: id) != nil {
                send(.ack(id: messageID), over: session)
                return
            }
            guard let transfer = incoming.removeValue(forKey: messageID), transfer.peer == id else { return }
            guard Int64(transfer.data.count) == transfer.info.byteCount,
                  Data(SHA256.hash(data: transfer.data)) == transfer.info.sha256,
                  (try? store.writeAttachment(transfer.data, messageID: messageID)) != nil
            else { return }
            let chat = ChatMessage(
                id: messageID, contactID: id, direction: .incoming, sentAt: transfer.sentAt,
                body: .attachment(transfer.info), status: .delivered
            )
            receive(chat)
            send(.ack(id: messageID), over: session)

        case let .ack(messageID):
            guard var original = store.message(messageID, contact: id),
                  original.direction == .outgoing, original.status != .delivered
            else { return }
            original.status = .delivered
            try? store.update(original)
            emit(.messageUpdated(original))

        case .ping:
            send(.pong, over: session)

        case .pong, .pairConfirm:
            break
        }
    }

    private func receive(_ message: ChatMessage) {
        guard (try? store.append(message)) == true else { return }
        if var contact = store.contact(message.contactID) {
            contact.unreadCount += 1
            try? store.upsert(contact)
        }
        emit(.messageAdded(message))
        emit(.contactsChanged)
    }

    func emit(_ event: MessengerEvent) {
        onEvent?(event)
    }
}
