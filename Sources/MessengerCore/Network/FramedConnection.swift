import Foundation
import Network

extension NWParameters {
    /// Plain TCP with keep-alive, allowed over Apple peer-to-peer Wi-Fi as well as the local network.
    static func messenger() -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 10
        tcp.connectionTimeout = 8
        let parameters = NWParameters(tls: nil, tcp: tcp)
        parameters.includePeerToPeer = true
        return parameters
    }
}

/// A TCP connection that sends and receives length-prefixed frames. All callbacks run on the main queue.
@MainActor
public final class FramedConnection {
    public var onReady: (() -> Void)?
    public var onFrame: ((Data) -> Void)?
    public var onClose: ((Error?) -> Void)?

    private let connection: NWConnection
    private var decoder = FrameDecoder()
    private var started = false
    private var closed = false

    public init(connection: NWConnection) {
        self.connection = connection
    }

    public convenience init(endpoint: NWEndpoint) {
        self.init(connection: NWConnection(to: endpoint, using: .messenger()))
    }

    deinit {
        connection.cancel()
    }

    public var remoteEndpoint: NWEndpoint { connection.endpoint }

    public func start() {
        guard !started else { return }
        started = true
        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated { self?.handle(state) }
        }
        connection.start(queue: .main)
        receiveNext()
    }

    public func send(_ payload: Data) {
        guard !closed else { return }
        connection.send(content: Framing.encode(payload), completion: .contentProcessed { [weak self] error in
            guard let error else { return }
            MainActor.assumeIsolated { self?.finish(error) }
        })
    }

    public func close() {
        finish(nil)
    }

    private func handle(_ state: NWConnection.State) {
        switch state {
        case .ready: onReady?()
        case .failed(let error), .waiting(let error): finish(error)
        case .cancelled: finish(nil)
        default: break
        }
    }

    private func receiveNext() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self, !self.closed else { return }
                if let data, !data.isEmpty {
                    do {
                        for frame in try self.decoder.append(data) {
                            guard !self.closed else { return }
                            self.onFrame?(frame)
                        }
                    } catch {
                        self.finish(error)
                        return
                    }
                }
                if let error { self.finish(error); return }
                if isComplete { self.finish(nil); return }
                self.receiveNext()
            }
        }
    }

    private func finish(_ error: Error?) {
        guard !closed else { return }
        closed = true
        connection.cancel()
        let handler = onClose
        onFrame = nil
        onClose = nil
        onReady = nil
        handler?(error)
    }
}
