import Combine
import CoreLocation
import Foundation
import GoldenTimeCore

/// Core Location callbacks hop to the main actor for `@Published` updates (Swift 6 concurrency).
/// `CLLocationManager` and this delegate bridge are main-thread affinity; `@unchecked Sendable` avoids spurious `Task` capture diagnostics.
final class WatchLocationReader: NSObject, ObservableObject, @unchecked Sendable {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var latestFix: LocationFix?
    /// Degrees clockwise from true north when available; else magnetic; `nil` until first heading update.
    @Published private(set) var headingDegrees: Double?

    private let manager = CLLocationManager()
    private var isAwaitingAuthorizationPrompt = false
    private var shouldRequestLocationAfterAuthorization = false
    private var wantsHeadingUpdates = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.headingFilter = 5
        authorizationStatus = manager.authorizationStatus
        syncHeadingUpdates()
    }

    private func syncHeadingUpdates() {
        switch (manager.authorizationStatus, wantsHeadingUpdates) {
        case (.authorizedAlways, true), (.authorizedWhenInUse, true):
            manager.startUpdatingHeading()
        default:
            manager.stopUpdatingHeading()
            headingDegrees = nil
        }
    }

    func refreshAuthorization() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.authorizationStatus = self.manager.authorizationStatus
        }
    }

    func requestLocation() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.authorizationStatus = self.manager.authorizationStatus
            switch self.manager.authorizationStatus {
            case .notDetermined:
                self.shouldRequestLocationAfterAuthorization = true
                guard !self.isAwaitingAuthorizationPrompt else {
                    self.syncHeadingUpdates()
                    return
                }
                self.isAwaitingAuthorizationPrompt = true
                self.manager.requestWhenInUseAuthorization()
            case .authorizedAlways, .authorizedWhenInUse:
                self.shouldRequestLocationAfterAuthorization = false
                self.manager.requestLocation()
            case .denied, .restricted:
                self.shouldRequestLocationAfterAuthorization = false
                break
            @unknown default:
                self.shouldRequestLocationAfterAuthorization = true
                guard !self.isAwaitingAuthorizationPrompt else {
                    self.syncHeadingUpdates()
                    return
                }
                self.isAwaitingAuthorizationPrompt = true
                self.manager.requestWhenInUseAuthorization()
            }
            self.syncHeadingUpdates()
        }
    }

    func setHeadingUpdatesEnabled(_ enabled: Bool) {
        wantsHeadingUpdates = enabled
        syncHeadingUpdates()
    }
}

extension WatchLocationReader: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.authorizationStatus = status
            if status != .notDetermined {
                self.isAwaitingAuthorizationPrompt = false
            }
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                if self.shouldRequestLocationAfterAuthorization {
                    self.shouldRequestLocationAfterAuthorization = false
                    self.manager.requestLocation()
                }
            } else if status == .denied || status == .restricted {
                self.shouldRequestLocationAfterAuthorization = false
            }
            self.syncHeadingUpdates()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let trueH = newHeading.trueHeading
        let magH = newHeading.magneticHeading
        Task { @MainActor [weak self] in
            guard let self else { return }
            if trueH >= 0 {
                self.headingDegrees = trueH
            } else if magH >= 0 {
                self.headingDegrees = magH
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let fix = LocationFix(
            latitude: loc.coordinate.latitude,
            longitude: loc.coordinate.longitude,
            timestamp: loc.timestamp
        )
        Task { @MainActor [weak self] in
            self?.latestFix = fix
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.authorizationStatus = self.manager.authorizationStatus
        }
        _ = error
    }
}
