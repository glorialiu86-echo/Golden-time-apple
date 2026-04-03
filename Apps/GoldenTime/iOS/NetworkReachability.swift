import Foundation
import Network
import Combine

/// Best-effort route check for showing MapKit tiles under the compass (tiles still may be cached when “offline”).
@MainActor
final class NetworkReachability: ObservableObject {
    @Published private(set) var hasNetworkRoute = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "time.golden.network")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.hasNetworkRoute = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }
}
