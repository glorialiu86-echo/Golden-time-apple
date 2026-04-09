import Combine
import CoreLocation
import Foundation
import GoldenTimeCore
import OSLog

/// Core Location callbacks hop to the main actor for `@Published` updates (Swift 6 concurrency).
/// `CLLocationManager` and this delegate bridge are main-thread affinity; `@unchecked Sendable` avoids spurious `Task` capture diagnostics.
final class WatchLocationReader: NSObject, ObservableObject, @unchecked Sendable {
    private static let performanceLog = Logger(subsystem: GTPerformanceLog.subsystem, category: "WatchLocationReader")

    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var latestFix: LocationFix?
    /// Degrees clockwise from true north when available; else magnetic; `nil` until first heading update.
    @Published private(set) var headingDegrees: Double?
    @Published private(set) var headingUsesTrueNorth = false

    private let manager = CLLocationManager()
    private var isAwaitingAuthorizationPrompt = false
    private var shouldRequestLocationAfterAuthorization = false
    private var wantsHeadingUpdates = false
    private var authorizationPromptStartUptime: TimeInterval?
    private var locationRequestStartUptime: TimeInterval?

    override init() {
        super.init()
        manager.delegate = self
        // Match iPhone behavior: favor a fast first fix over meter-level precision we don't need for twilight UI.
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
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
            headingUsesTrueNorth = false
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
            GTPerfTrace.mark(
                Self.performanceLog,
                "watch requestLocation called auth=\(self.manager.authorizationStatus.rawValue)"
            )
            switch self.manager.authorizationStatus {
            case .notDetermined:
                self.shouldRequestLocationAfterAuthorization = true
                guard !self.isAwaitingAuthorizationPrompt else {
                    self.syncHeadingUpdates()
                    return
                }
                self.isAwaitingAuthorizationPrompt = true
                self.authorizationPromptStartUptime = GTPerfTrace.uptime()
                GTPerfTrace.mark(Self.performanceLog, "watch authorization prompt requested")
                self.manager.requestWhenInUseAuthorization()
            case .authorizedAlways, .authorizedWhenInUse:
                self.shouldRequestLocationAfterAuthorization = false
                self.locationRequestStartUptime = GTPerfTrace.uptime()
                GTPerfTrace.mark(Self.performanceLog, "watch requestCurrentLocation issued")
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
            GTPerfTrace.mark(
                Self.performanceLog,
                "watch authorization changed to \(status.rawValue) after \(GTPerfTrace.milliseconds(since: self.authorizationPromptStartUptime))"
            )
            if status != .notDetermined {
                self.isAwaitingAuthorizationPrompt = false
            }
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                if self.shouldRequestLocationAfterAuthorization {
                    self.shouldRequestLocationAfterAuthorization = false
                    self.locationRequestStartUptime = GTPerfTrace.uptime()
                    GTPerfTrace.mark(Self.performanceLog, "watch requestCurrentLocation issued after authorization")
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
                self.headingUsesTrueNorth = true
            } else if magH >= 0 {
                self.headingDegrees = magH
                self.headingUsesTrueNorth = false
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
            guard let self else { return }
            GTPerfTrace.mark(
                Self.performanceLog,
                "watch didUpdateLocations count=\(locations.count) accuracy=\(String(format: "%.1f", loc.horizontalAccuracy)) age=\(String(format: "%.3f", -loc.timestamp.timeIntervalSinceNow))s afterRequest=\(GTPerfTrace.milliseconds(since: self.locationRequestStartUptime))"
            )
            self.latestFix = fix
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.authorizationStatus = self.manager.authorizationStatus
            GTPerfTrace.mark(
                Self.performanceLog,
                "watch location request failed auth=\(self.manager.authorizationStatus.rawValue) error=\(error.localizedDescription)"
            )
        }
    }
}
