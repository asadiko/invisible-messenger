import Foundation
import Network

/// Accepts incoming connections and routes each by the kind byte at the start of its first frame.
/// Optionally advertises itself over Bonjour, with `p=1` in the TXT record while pairing is open.
@MainActor
public final class PeerListener {
    public static let serviceType = "_invmsg._tcp"
    static let firstFrameTimeout: TimeInterval = 10

    public var onConnection: ((FramedConnection, _ kind: UInt8, _ firstMessage: Data) -> Void)?
    public var onReady: (() -> Void)?
    public var onFailure: ((Error) -> Void)?
    public private(set) var port: NWEndpoint.Port?
    public var pairingOpen = false {
        didSet { if oldValue != pairingOpen, advertise { listener?.service = service() } }
    }

    private let name: String
    private let requestedPort: NWEndpoint.Port
    private let advertise: Bool
    private var listener: NWListener?
    private var pending: [ObjectIdentifier: FramedConnection] = [:]

    public init(name: String, port: NWEndpoint.Port = .any, advertise: Bool) {
        self.name = name
        requestedPort = port
        self.advertise = advertise
    }

    public func start() throws {
        let listener = try NWListener(using: .messenger(), on: requestedPort)
        if advertise { listener.service = service() }
        listener.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                guard let self else { return }
                switch state {
                case .ready:
                    self.port = listener.port
                    self.onReady?()
                case .failed(let error):
                    self.onFailure?(error)
                default:
                    break
                }
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated { self?.accept(connection) }
        }
        listener.start(queue: .main)
        self.listener = listener
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        port = nil
        pending.values.forEach { $0.close() }
        pending.removeAll()
    }

    private func service() -> NWListener.Service {
        var txt = NWTXTRecord()
        txt["v"] = "1"
        txt["p"] = pairingOpen ? "1" : "0"
        return NWListener.Service(name: name, type: Self.serviceType, domain: nil, txtRecord: txt)
    }

    private func accept(_ nw: NWConnection) {
        let connection = FramedConnection(connection: nw)
        let key = ObjectIdentifier(connection)
        pending[key] = connection
        connection.onFrame = { [weak self, weak connection] frame in
            guard let self, let connection else { return }
            self.pending[key] = nil
            connection.onFrame = nil
            connection.onClose = nil
            guard let kind = frame.first else { connection.close(); return }
            self.onConnection?(connection, kind, Data(frame.dropFirst()))
        }
        connection.onClose = { [weak self] _ in self?.pending[key] = nil }
        connection.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.firstFrameTimeout) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let stale = self.pending.removeValue(forKey: key) else { return }
                stale.close()
            }
        }
    }
}
