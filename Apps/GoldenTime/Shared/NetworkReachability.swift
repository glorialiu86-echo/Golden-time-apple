import Foundation
import Network

/// Publishes whether the device has a routable network path (used to gate MapKit tiles under the compass).
public final class NetworkReachability: ObservableObject, @unchecked Sendable {
    @Published public private(set) var hasNetworkRoute: Bool = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "time.golden.network")

    public init() {
        monitor.pathUpdateHandler = { path in
            let satisfied = path.status == .satisfied
            DispatchQueue.main.async { [weak self] in
                self?.hasNetworkRoute = satisfied
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
