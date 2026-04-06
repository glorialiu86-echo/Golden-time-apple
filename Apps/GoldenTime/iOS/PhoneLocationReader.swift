import Combine
import CoreLocation
import Foundation
import OSLog

/// GPS + device heading; feeds local sun-position math and heading-up compass. No network APIs.
final class PhoneLocationReader: NSObject, ObservableObject, @unchecked Sendable {
    private static let performanceLog = Logger(subsystem: GTPerformanceLog.subsystem, category: "PhoneLocationReader")

    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var latestFix: CLLocation?
    /// Cleared on each authorized `requestLocation` and on success; set when `didFailWithError` fires.
    @Published private(set) var lastLocationRequestFailed = false
    /// Degrees clockwise from true north when available; else magnetic; `nil` until first heading update.
    @Published private(set) var headingDegrees: Double?

    private let manager = CLLocationManager()
    private var isAwaitingAuthorizationPrompt = false
    private var shouldRequestLocationAfterAuthorization = false
    private var wantsHeadingUpdates = false
    private var authorizationPromptStartUptime: TimeInterval?
    private var locationRequestStartUptime: TimeInterval?
    private var lastHeadingUpdateUptime: TimeInterval?

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
            GTPerfTrace.mark(
                Self.performanceLog,
                "phone requestLocation called auth=\(self.manager.authorizationStatus.rawValue)"
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
                GTPerfTrace.mark(Self.performanceLog, "phone authorization prompt requested")
                self.manager.requestWhenInUseAuthorization()
            case .authorizedAlways, .authorizedWhenInUse:
                self.shouldRequestLocationAfterAuthorization = false
                self.requestCurrentLocation()
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

    private func requestCurrentLocation() {
        lastLocationRequestFailed = false
        locationRequestStartUptime = GTPerfTrace.uptime()
        GTPerfTrace.mark(Self.performanceLog, "phone requestCurrentLocation issued")
        manager.requestLocation()
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
}

extension PhoneLocationReader: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.authorizationStatus = status
            GTPerfTrace.mark(
                Self.performanceLog,
                "phone authorization changed to \(status.rawValue) after \(GTPerfTrace.milliseconds(since: self.authorizationPromptStartUptime))"
            )
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
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let updateUptime = GTPerfTrace.uptime()
            if trueH >= 0 {
                self.headingDegrees = trueH
                GTPerfTrace.mark(
                    Self.performanceLog,
                    "phone didUpdateHeading source=true heading=\(String(format: "%.1f", trueH)) afterPrev=\(GTPerfTrace.milliseconds(since: self.lastHeadingUpdateUptime))"
                )
            } else if magH >= 0 {
                self.headingDegrees = magH
                GTPerfTrace.mark(
                    Self.performanceLog,
                    "phone didUpdateHeading source=mag heading=\(String(format: "%.1f", magH)) afterPrev=\(GTPerfTrace.milliseconds(since: self.lastHeadingUpdateUptime))"
                )
            }
            self.lastHeadingUpdateUptime = updateUptime
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.lastLocationRequestFailed = false
            self.latestFix = loc
            GTPerfTrace.mark(
                Self.performanceLog,
                "phone didUpdateLocations count=\(locations.count) accuracy=\(String(format: "%.1f", loc.horizontalAccuracy)) age=\(String(format: "%.3f", -loc.timestamp.timeIntervalSinceNow))s afterRequest=\(GTPerfTrace.milliseconds(since: self.locationRequestStartUptime))"
            )
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.authorizationStatus = self.manager.authorizationStatus
            self.lastLocationRequestFailed = true
            GTPerfTrace.mark(
                Self.performanceLog,
                "phone location request failed auth=\(self.manager.authorizationStatus.rawValue) error=\(error.localizedDescription)"
            )
        }
    }
}
