import Combine
import CoreLocation
import Foundation

/// GPS + device heading; feeds local sun-position math and heading-up compass. No network APIs.
final class PhoneLocationReader: NSObject, ObservableObject, @unchecked Sendable {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var latestFix: CLLocation?
    /// Cleared on each authorized `requestLocation` and on success; set when `didFailWithError` fires.
    @Published private(set) var lastLocationRequestFailed = false
    /// Degrees clockwise from true north when available; else magnetic; `nil` until first heading update.
    @Published private(set) var headingDegrees: Double?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.headingFilter = 3
        authorizationStatus = manager.authorizationStatus
        syncHeadingUpdates()
    }

    func requestLocation() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.authorizationStatus = self.manager.authorizationStatus
            switch self.manager.authorizationStatus {
            case .notDetermined:
                self.manager.requestWhenInUseAuthorization()
            case .authorizedAlways, .authorizedWhenInUse:
                self.lastLocationRequestFailed = false
                self.manager.requestLocation()
            case .denied, .restricted:
                break
            @unknown default:
                self.manager.requestWhenInUseAuthorization()
            }
            self.syncHeadingUpdates()
        }
    }

    private func syncHeadingUpdates() {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingHeading()
        default:
            manager.stopUpdatingHeading()
            headingDegrees = nil
        }
    }
}

extension PhoneLocationReader: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.authorizationStatus = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                self.manager.requestLocation()
            }
            self.syncHeadingUpdates()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let trueH = newHeading.trueHeading
        let magH = newHeading.magneticHeading
        DispatchQueue.main.async { [weak self] in
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
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.lastLocationRequestFailed = false
            self.latestFix = loc
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.authorizationStatus = self.manager.authorizationStatus
            self.lastLocationRequestFailed = true
        }
        _ = error
    }
}
