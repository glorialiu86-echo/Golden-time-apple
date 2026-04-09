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
    /// `true` when `headingDegrees` currently comes from `CLHeading.trueHeading`; `false` when using magnetic fallback or no heading.
    @Published private(set) var headingUsesTrueNorth = false

    private let manager = CLLocationManager()
    private var isAwaitingAuthorizationPrompt = false
    private var shouldRequestLocationAfterAuthorization = false
    private var wantsHeadingUpdates = false

    override init() {
        super.init()
        manager.delegate = self
        // First-launch UX matters more than a 10 m fix; coarse accuracy is sufficient for sunrise/sunset guidance.
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
                self.shouldRequestLocationAfterAuthorization = true
                guard !self.isAwaitingAuthorizationPrompt else {
                    self.syncHeadingUpdates()
                    return
                }
                self.isAwaitingAuthorizationPrompt = true
                self.manager.requestWhenInUseAuthorization()
            case .authorizedAlways, .authorizedWhenInUse:
                self.shouldRequestLocationAfterAuthorization = false
                self.requestCurrentLocation()
            case .denied, .restricted:
                self.shouldRequestLocationAfterAuthorization = false
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

    private func requestCurrentLocation() {
        lastLocationRequestFailed = false
        manager.requestLocation()
    }

    private func syncHeadingUpdates() {
        guard wantsHeadingUpdates, CLLocationManager.headingAvailable() else {
            manager.stopUpdatingHeading()
            headingDegrees = nil
            headingUsesTrueNorth = false
            return
        }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingHeading()
        default:
            manager.stopUpdatingHeading()
            headingDegrees = nil
            headingUsesTrueNorth = false
        }
    }

    private func applyHeadingUpdate(trueHeading: CLLocationDirection, magneticHeading: CLLocationDirection) {
        if trueHeading >= 0 {
            headingDegrees = trueHeading
            headingUsesTrueNorth = true
        } else if magneticHeading >= 0 {
            headingDegrees = magneticHeading
            headingUsesTrueNorth = false
        } else {
            headingDegrees = nil
            headingUsesTrueNorth = false
        }
    }
}

extension PhoneLocationReader: CLLocationManagerDelegate {
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
                    self.requestCurrentLocation()
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
        if Thread.isMainThread {
            applyHeadingUpdate(trueHeading: trueH, magneticHeading: magH)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.applyHeadingUpdate(trueHeading: trueH, magneticHeading: magH)
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
    }
}
