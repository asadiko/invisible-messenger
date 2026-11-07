import Foundation
import Network

/// A Mac seen on the network. `name` is its DeviceID raw value.
public struct DiscoveredPeer: Hashable, Sendable {
    public let name: String
    public let endpoint: NWEndpoint
    public let pairingOpen: Bool

    public init(name: String, endpoint: NWEndpoint, pairingOpen: Bool) {
        self.name = name
        self.endpoint = endpoint
        self.pairingOpen = pairingOpen
    }
}

/// Source of the Macs currently reachable.
@MainActor
public protocol PeerDirectory: AnyObject {
    var onChange: (([DiscoveredPeer]) -> Void)? { get set }
    func start()
    func stop()
}

/// Bonjour browsing for `_invmsg._tcp`, including Apple peer-to-peer Wi-Fi.
@MainActor
public final class BonjourDirectory: PeerDirectory {
    public var onChange: (([DiscoveredPeer]) -> Void)?
    private let serviceType: String
    private var browser: NWBrowser?

    public init(serviceType: String = PeerListener.serviceType) {
        self.serviceType = serviceType
    }

    public func start() {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: serviceType, domain: nil), using: parameters)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            MainActor.assumeIsolated { self?.publish(results) }
        }
        browser.stateUpdateHandler = { [weak self] state in
            guard case .failed = state else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                self.stop()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    MainActor.assumeIsolated { self?.start() }
                }
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    public func stop() {
        browser?.cancel()
        browser = nil
    }

    private func publish(_ results: Set<NWBrowser.Result>) {
        var byName: [String: DiscoveredPeer] = [:]
        for result in results {
            guard case let .service(name, _, _, _) = result.endpoint else { continue }
            var open = false
            if case let .bonjour(txt) = result.metadata { open = txt["p"] == "1" }
            if byName[name] == nil || open {
                byName[name] = DiscoveredPeer(name: name, endpoint: result.endpoint, pairingOpen: open)
            }
        }
        onChange?(byName.values.sorted { $0.name < $1.name })
    }
}

/// A fixed list of peers, for tests and direct connections.
@MainActor
public final class StaticDirectory: PeerDirectory {
    public var onChange: (([DiscoveredPeer]) -> Void)?
    private var started = false
    public var peers: [DiscoveredPeer] {
        didSet { if started { onChange?(peers) } }
    }

    public init(peers: [DiscoveredPeer] = []) {
        self.peers = peers
    }

    public func start() {
        started = true
        onChange?(peers)
    }

    public func stop() {
        started = false
    }
}
