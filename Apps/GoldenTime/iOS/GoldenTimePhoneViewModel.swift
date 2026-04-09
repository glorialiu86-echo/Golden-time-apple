import Combine
import CoreLocation
import Foundation
import GoldenTimeCore
import UIKit
#if canImport(WidgetKit)
import WidgetKit
#endif

enum GTSettingsLocationFeedback: Equatable {
    case idle
    case waitingForPermission
    case refreshing
    case success
    case denied
    case restricted
    case failed
}

#if DEBUG
private enum GTDebugNow {
    static let environmentKey = "GOLDEN_TIME_DEBUG_NOW_ISO8601"

    static func current() -> Date {
        guard let raw = ProcessInfo.processInfo.environment[environmentKey], !raw.isEmpty else {
            return Date()
        }
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plainFormatter = ISO8601DateFormatter()
        plainFormatter.formatOptions = [.withInternetDateTime]
        if let parsed = fractionalFormatter.date(from: raw) ?? plainFormatter.date(from: raw) {
            return parsed
        }
        return Date()
    }
}
#endif

@MainActor
enum GTPhoneStartupSyncGate {
    static var isUnlocked = false
}

/// Drives `GoldenTimeEngine` on-device only: GPS + cached coordinates + local time. No URLSession or remote APIs.
@MainActor
final class GoldenTimePhoneViewModel: ObservableObject {
    private struct DailyDerivedStateKey: Equatable {
        let latitude: Double
        let longitude: Double
        let dayStart: Date
        let language: GTAppLanguage
    }

    private enum SettingsLocationAction: Equatable {
        case requestingAuthorization
        case refreshing
    }

    private let engine = GoldenTimeEngine()
    /// Created after the first frame so `CLLocationManager` setup never blocks the launch screen.
    private var locationReader: PhoneLocationReader?
    private var cancellables = Set<AnyCancellable>()
    private var locationHeartbeat: AnyCancellable?
    private var pendingSettingsLocationAction: SettingsLocationAction?
    private var settingsLocationFeedbackResetTask: Task<Void, Never>?
    private var settingsLocationRefreshTimeoutTask: Task<Void, Never>?

    private var activeFix: LocationFix?
    private var lastEngineDayStart: Date?
    private var lastDailyDerivedStateKey: DailyDerivedStateKey?
    /// Last `[0,30)` … `[330,360)` bucket for device heading; haptic when crossing a 30° tick (like Apple Compass).
    private var headingThirtyDegreeBucket: Int?
    /// Skip the first tick per foreground session to avoid first-fire haptic stalls.
    private var shouldSkipNextHeadingTickHaptic = true
    /// `UIImpactFeedbackGenerator` is lazily initialized; pre-warm it off the first real tick.
    private var hasPrimedHeadingTickHaptic = false
    private let headingTickHaptic = UIImpactFeedbackGenerator(style: .light)

    /// Mirrors `GTAppLanguage.phoneDisplayLanguage` from App Group preference on iPhone.
    private(set) var contentLanguage: GTAppLanguage = GTAppLanguage.widgetLanguageIOS(suite: GTAppGroup.shared)
    private var compassHeadingOffsetDegrees: Double?

    @Published private(set) var latitudeText = "—"
    @Published private(set) var longitudeText = "—"
    @Published private(set) var statusLine = ""

    /// Start / end labels for the **relevant** blue segment (current window or next).
    @Published private(set) var blueStartText = "—"
    @Published private(set) var blueEndText = "—"
    @Published private(set) var goldenStartText = "—"
    @Published private(set) var goldenEndText = "—"

    /// `true` → blue section above golden; `false` → golden above blue.
    @Published private(set) var blueTwilightFirst = true

    /// Relevant segment for UI (current `[start,end)` or next); drives countdown mode.
    @Published private(set) var blueWindowRange: (start: Date, end: Date)?
    @Published private(set) var goldenWindowRange: (start: Date, end: Date)?

    @Published private(set) var phase: PhaseState?

    /// Mirrors `PhoneLocationReader.authorizationStatus` for settings UI.
    @Published private(set) var locationAuthorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var settingsLocationFeedback: GTSettingsLocationFeedback = .idle

    /// Map center / ray origin (same as last GPS fix used by the engine).
    @Published private(set) var mapCoordinate: CLLocationCoordinate2D?

    /// Apparent sunrise/sunset azimuths for the local civil day (all on-device math).
    @Published private(set) var sunHorizon: SunHorizonGeometry?

    /// Sunrise/sunset azimuths + midday sun bearing for compass day/night wedges; `nil` if polar or no geometry.
    @Published private(set) var compassDayNight: CompassDayNightInput?

    /// Device true (or magnetic) heading in degrees clockwise from north; `nil` until Core Location reports heading.
    @Published private(set) var deviceHeadingDegrees: Double?
    @Published private(set) var deviceHeadingUsesTrueNorth = false

    /// Sun azimuth arcs for **each** blue-hour clip in the local civil day (compass may show 0…n sectors).
    @Published private(set) var blueSectorArcAzimuths: [(Double, Double)] = []

    /// Sun azimuth arcs for each golden-hour clip in the same local day.
    @Published private(set) var goldenSectorArcAzimuths: [(Double, Double)] = []

    /// True-north sun azimuth for compass body icon when sun is above the same −50′ horizon as sunrise tables; `nil` if not up.
    @Published private(set) var compassSunBodyAzimuthDegrees: Double?

    /// True-north moon azimuth when moon is above geometric horizon; `nil` if below.
    @Published private(set) var compassMoonBodyAzimuthDegrees: Double?
    @Published private(set) var compassCalibrationDate: Date?

    /// Wall-clock instant for UI labels; updated every second (replaces `TimelineView`, which mis-sized on some simulators).
    @Published private(set) var clockNow: Date = {
        #if DEBUG
        GTDebugNow.current()
        #else
        Date()
        #endif
    }()

    private static var defaults: UserDefaults { GTAppGroup.shared }
    /// Matches `GoldenTimeEngine` apparent sunrise/sunset (−50′).
    private static let sunIconMinAltitudeDegrees = -50.0 / 60.0
    private static let moonIconMinAltitudeDegrees = 0.0
    private static let latKey = GoldenTimeLocationCache.latitudeKey
    private static let lonKey = GoldenTimeLocationCache.longitudeKey
    private static let tsKey = GoldenTimeLocationCache.timestampKey
    private static let pendingWidgetReloadKey = "gt.phone.pendingWidgetReload"
    private static let pendingPhoneStatePushKey = "gt.phone.pendingPhoneStatePush"
    private static let calibrationDefaults = UserDefaults.standard

    private let coordFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.minimumFractionDigits = 5
        f.maximumFractionDigits = 4
        f.numberStyle = .decimal
        return f
    }()

    private func currentNow() -> Date {
        #if DEBUG
        GTDebugNow.current()
        #else
        Date()
        #endif
    }

    private func formatTwilightInstant(_ instant: Date) -> String {
        GTDateFormatters.twilightInstantLabel(instant, lang: contentLanguage)
    }

    private func normalizeDegrees(_ value: Double) -> Double {
        Self.normalizeDegrees(value)
    }

    private func triggerHeadingTickHapticIfNeeded(headingDegrees: Double) {
        var h = headingDegrees.truncatingRemainder(dividingBy: 360)
        if h < 0 { h += 360 }
        let bucket = min(11, Int(h / 30))
        if let prev = headingThirtyDegreeBucket, prev != bucket {
            if shouldSkipNextHeadingTickHaptic {
                shouldSkipNextHeadingTickHaptic = false
                headingTickHaptic.prepare()
            } else {
                headingTickHaptic.prepare()
                headingTickHaptic.impactOccurred(intensity: 0.55)
            }
        }
        headingThirtyDegreeBucket = bucket
    }

    private func primeHeadingTickHapticIfNeeded() {
        guard !hasPrimedHeadingTickHaptic else { return }
        headingTickHaptic.prepare()
        hasPrimedHeadingTickHaptic = true
    }

    init() {
        loadCompassCalibration()
        if let cached = Self.loadCachedFix() {
            activeFix = cached
            updateCoordLabels(lat: cached.latitude, lon: cached.longitude)
        }
        let now = currentNow()
        clockNow = now
        if activeFix != nil {
            recomputeEngineIfNeeded(now: now, force: true)
        }
        rebuildDailyDerivedStateIfNeeded(now: now, force: true)
        refreshLiveState(now: now)
        recomputeStatusLine()

        Timer.publish(every: 1, tolerance: 0.15, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                let now = self.currentNow()
                self.clockNow = now
                self.refreshForTick(at: now)
            }
            .store(in: &cancellables)
    }

    /// Wire Core Location after SwiftUI has presented the root view to avoid launch-screen stalls.
    func prepareLocationPipeline() {
        guard locationReader == nil else { return }
        let reader = PhoneLocationReader()
        locationReader = reader

        reader.$latestFix
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] loc in
                self?.handleLocationUpdate(loc)
            }
            .store(in: &cancellables)

        locationAuthorizationStatus = reader.authorizationStatus
        reader.$authorizationStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.locationAuthorizationStatus = status
                self?.recomputeStatusLine()
                self?.handleLocationAuthorizationChange(status)
            }
            .store(in: &cancellables)

        reader.$lastLocationRequestFailed
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.recomputeStatusLine()
                self?.handleLocationRequestFailure()
            }
            .store(in: &cancellables)

        reader.$headingDegrees
            .sink { [weak self] v in
                guard let self else { return }
                self.deviceHeadingDegrees = v
                if let h = v {
                    self.triggerHeadingTickHapticIfNeeded(headingDegrees: self.correctedHeadingDegrees ?? h)
                } else {
                    self.headingThirtyDegreeBucket = nil
                }
            }
            .store(in: &cancellables)

        reader.$headingUsesTrueNorth
            .receive(on: DispatchQueue.main)
            .sink { [weak self] usesTrueNorth in
                self?.deviceHeadingUsesTrueNorth = usesTrueNorth
            }
            .store(in: &cancellables)

        reader.setHeadingUpdatesEnabled(true)
    }

    var correctedHeadingDegrees: Double? {
        guard let raw = deviceHeadingDegrees else { return nil }
        guard let offset = compassHeadingOffsetDegrees else { return raw }
        return normalizeDegrees(raw + offset)
    }

    var hasCompassCalibration: Bool {
        compassHeadingOffsetDegrees != nil
    }

    var compassCalibrationStatusText: String {
        if let date = compassCalibrationDate {
            return GTCopy.compassCalibrationStatusCalibrated(date: date, lang: contentLanguage)
        }
        return GTCopy.compassCalibrationStatusNotCalibrated(contentLanguage)
    }

    var compassCalibrationAvailabilityText: String {
        if let reason = compassCalibrationUnavailableReason {
            return reason
        }
        return deviceHeadingUsesTrueNorth
            ? GTCopy.compassCalibrationSavedHeadingHint(contentLanguage)
            : GTCopy.compassCalibrationTrueNorthRequired(contentLanguage)
    }

    var compassCalibrationUnavailableReason: String? {
        let auth = locationReader?.authorizationStatus ?? locationAuthorizationStatus
        switch auth {
        case .denied, .restricted:
            return GTCopy.compassCalibrationNeedsLocationPermission(contentLanguage)
        default:
            break
        }
        guard activeFix != nil else {
            return GTCopy.compassCalibrationNeedsLocationFix(contentLanguage)
        }
        guard deviceHeadingDegrees != nil else {
            return GTCopy.compassCalibrationNeedsHeading(contentLanguage)
        }
        guard deviceHeadingUsesTrueNorth else {
            return GTCopy.compassCalibrationTrueNorthRequired(contentLanguage)
        }
        guard compassSunBodyAzimuthDegrees != nil else {
            return GTCopy.compassCalibrationSunUnavailable(contentLanguage)
        }
        return nil
    }

    var canSaveCompassCalibration: Bool {
        compassCalibrationUnavailableReason == nil
    }

    @discardableResult
    func saveCompassCalibrationFromCurrentSunAlignment() -> Bool {
        guard let rawHeading = deviceHeadingDegrees,
              let sunAzimuth = compassSunBodyAzimuthDegrees,
              deviceHeadingUsesTrueNorth
        else {
            return false
        }
        let savedAt = currentNow()
        let offset = normalizeDegrees(sunAzimuth - rawHeading)
        compassHeadingOffsetDegrees = offset
        compassCalibrationDate = savedAt
        headingThirtyDegreeBucket = nil
        shouldSkipNextHeadingTickHaptic = true
        Self.calibrationDefaults.set(offset, forKey: GTCompassCalibrationSettings.offsetDegreesKey)
        Self.calibrationDefaults.set(savedAt.timeIntervalSince1970, forKey: GTCompassCalibrationSettings.calibratedAtKey)
        Self.calibrationDefaults.set(GTCompassCalibrationSettings.sourceSun, forKey: GTCompassCalibrationSettings.sourceKey)
        Self.calibrationDefaults.set(GTCompassCalibrationSettings.version, forKey: GTCompassCalibrationSettings.versionKey)
        return true
    }

    func clearCompassCalibration() {
        compassHeadingOffsetDegrees = nil
        compassCalibrationDate = nil
        headingThirtyDegreeBucket = nil
        shouldSkipNextHeadingTickHaptic = true
        Self.calibrationDefaults.removeObject(forKey: GTCompassCalibrationSettings.offsetDegreesKey)
        Self.calibrationDefaults.removeObject(forKey: GTCompassCalibrationSettings.calibratedAtKey)
        Self.calibrationDefaults.removeObject(forKey: GTCompassCalibrationSettings.sourceKey)
        Self.calibrationDefaults.removeObject(forKey: GTCompassCalibrationSettings.versionKey)
    }

    /// Call when the persisted language preference or system locale may have changed.
    func syncContentLanguageWithAppPreference() {
        let next = GTAppLanguage.widgetLanguageIOS(suite: Self.defaults)
        guard next != contentLanguage else { return }
        contentLanguage = next
        rebuildDailyDerivedStateIfNeeded(now: clockNow, force: true)
        refreshLiveState(now: clockNow)
        recomputeStatusLine()
        objectWillChange.send()
    }

    func refreshForTick(at now: Date) {
        recomputeEngineIfNeeded(now: now)
        rebuildDailyDerivedStateIfNeeded(now: now)
        refreshLiveState(now: now)
    }

    var isPerformingSettingsLocationAction: Bool {
        pendingSettingsLocationAction != nil
    }

    var hasDeferredExternalOutputs: Bool {
        Self.defaults.bool(forKey: Self.pendingWidgetReloadKey) || Self.defaults.bool(forKey: Self.pendingPhoneStatePushKey)
    }

    func requestLocationAccessFromSettings() {
        prepareLocationPipeline()
        switch locationReader?.authorizationStatus ?? .notDetermined {
        case .notDetermined:
            settingsLocationFeedbackResetTask?.cancel()
            pendingSettingsLocationAction = .requestingAuthorization
            settingsLocationFeedback = .waitingForPermission
            locationReader?.requestLocation()
        case .authorizedAlways, .authorizedWhenInUse:
            refreshLocationFromSettings()
        case .denied:
            finishSettingsLocationAction(with: .denied, autoClear: false)
        case .restricted:
            finishSettingsLocationAction(with: .restricted, autoClear: false)
        @unknown default:
            settingsLocationFeedbackResetTask?.cancel()
            pendingSettingsLocationAction = .requestingAuthorization
            settingsLocationFeedback = .waitingForPermission
            locationReader?.requestLocation()
        }
    }

    func refreshLocationFromSettings() {
        prepareLocationPipeline()
        switch locationReader?.authorizationStatus ?? .notDetermined {
        case .authorizedAlways, .authorizedWhenInUse:
            settingsLocationFeedbackResetTask?.cancel()
            pendingSettingsLocationAction = .refreshing
            settingsLocationFeedback = .refreshing
            startSettingsLocationRefreshTimeout()
            locationReader?.requestLocation()
        case .notDetermined:
            requestLocationAccessFromSettings()
        case .denied:
            finishSettingsLocationAction(with: .denied, autoClear: false)
        case .restricted:
            finishSettingsLocationAction(with: .restricted, autoClear: false)
        @unknown default:
            requestLocationAccessFromSettings()
        }
    }

    /// Call when reminder-related App Group preferences change (settings sheet) so scheduling updates immediately.
    func refreshTwilightReminderSchedule() {
        TwilightReminderScheduler.shared.reschedule(engine: engine, now: clockNow)
    }

    /// Opens the app’s page in Settings (user can enable Location, etc.).
    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// Call when the scene becomes active; cancels when app leaves foreground.
    func beginForegroundLocationSession(requestImmediately: Bool) {
        prepareLocationPipeline()
        primeHeadingTickHapticIfNeeded()
        shouldSkipNextHeadingTickHaptic = true
        if requestImmediately {
            locationReader?.requestLocation()
        }
        locationHeartbeat?.cancel()
        locationHeartbeat = Timer.publish(every: 600, tolerance: 20, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.locationReader?.requestLocation()
            }
    }

    func endForegroundLocationSession() {
        locationHeartbeat?.cancel()
        locationHeartbeat = nil
        shouldSkipNextHeadingTickHaptic = true
    }

    func flushDeferredExternalOutputs() {
        if Self.defaults.bool(forKey: Self.pendingWidgetReloadKey) {
            Self.reloadTwilightWidgetTimelines()
            Self.defaults.removeObject(forKey: Self.pendingWidgetReloadKey)
        }
        if Self.defaults.bool(forKey: Self.pendingPhoneStatePushKey) {
            GTWatchConnectivitySync.shared.pushPhoneStateFromStore()
            Self.defaults.removeObject(forKey: Self.pendingPhoneStatePushKey)
        }
    }

    private func handleLocationUpdate(_ loc: CLLocation) {
        applyLocation(loc)
        guard pendingSettingsLocationAction != nil else { return }
        finishSettingsLocationAction(with: .success, autoClear: true)
    }

    private func handleLocationAuthorizationChange(_ status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            guard pendingSettingsLocationAction == .requestingAuthorization else { return }
            pendingSettingsLocationAction = .refreshing
            settingsLocationFeedback = .refreshing
            startSettingsLocationRefreshTimeout()
        case .denied:
            guard pendingSettingsLocationAction != nil || settingsLocationFeedback == .waitingForPermission else { return }
            finishSettingsLocationAction(with: .denied, autoClear: false)
        case .restricted:
            guard pendingSettingsLocationAction != nil || settingsLocationFeedback == .waitingForPermission else { return }
            finishSettingsLocationAction(with: .restricted, autoClear: false)
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    private func handleLocationRequestFailure() {
        guard locationReader?.lastLocationRequestFailed == true, pendingSettingsLocationAction == .refreshing else { return }
        finishSettingsLocationAction(with: .failed, autoClear: true)
    }

    private func applyLocation(_ loc: CLLocation) {
        let fix = LocationFix(
            latitude: loc.coordinate.latitude,
            longitude: loc.coordinate.longitude,
            timestamp: loc.timestamp
        )
        activeFix = fix
        Self.saveCachedFix(fix)
        updateCoordLabels(lat: fix.latitude, lon: fix.longitude)
        recomputeStatusLine()
        let now = currentNow()
        recomputeEngineIfNeeded(now: now, force: true)
        rebuildDailyDerivedStateIfNeeded(now: now, force: true)
        refreshLiveState(now: now)
    }

    private func startSettingsLocationRefreshTimeout() {
        settingsLocationRefreshTimeoutTask?.cancel()
        settingsLocationRefreshTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self, self.pendingSettingsLocationAction == .refreshing else { return }
            self.finishSettingsLocationAction(with: .failed, autoClear: true)
        }
    }

    private func finishSettingsLocationAction(with feedback: GTSettingsLocationFeedback, autoClear: Bool) {
        pendingSettingsLocationAction = nil
        settingsLocationRefreshTimeoutTask?.cancel()
        settingsLocationRefreshTimeoutTask = nil
        settingsLocationFeedbackResetTask?.cancel()
        settingsLocationFeedback = feedback
        guard autoClear else { return }
        settingsLocationFeedbackResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, !self.isPerformingSettingsLocationAction else { return }
            self.settingsLocationFeedback = .idle
        }
    }

    private func updateCoordLabels(lat: Double, lon: Double) {
        latitudeText = coordFormatter.string(from: NSNumber(value: lat)) ?? String(format: "%.5f", lat)
        longitudeText = coordFormatter.string(from: NSNumber(value: lon)) ?? String(format: "%.5f", lon)
    }

    private func recomputeEngineIfNeeded(now: Date, force: Bool = false) {
        guard let fix = activeFix else {
            engine.update(now: now, fix: nil)
            lastEngineDayStart = nil
            return
        }
        let dayStart = Calendar.autoupdatingCurrent.startOfDay(for: now)
        if force || lastEngineDayStart != dayStart {
            engine.update(now: now, fix: fix)
            lastEngineDayStart = dayStart
        }
    }

    private func rebuildDailyDerivedStateIfNeeded(now: Date, force: Bool = false) {
        guard let fix = activeFix else {
            lastDailyDerivedStateKey = nil
            mapCoordinate = nil
            sunHorizon = nil
            compassDayNight = nil
            blueSectorArcAzimuths = []
            goldenSectorArcAzimuths = []
            return
        }
        let key = DailyDerivedStateKey(
            latitude: fix.latitude,
            longitude: fix.longitude,
            dayStart: Calendar.autoupdatingCurrent.startOfDay(for: now),
            language: contentLanguage
        )
        guard force || key != lastDailyDerivedStateKey else { return }
        lastDailyDerivedStateKey = key
        mapCoordinate = CLLocationCoordinate2D(latitude: fix.latitude, longitude: fix.longitude)
        updateCoordLabels(lat: fix.latitude, lon: fix.longitude)

        if let h = engine.sunHorizonGeometry(for: now) {
            sunHorizon = h
            let midTs = (h.sunrise.timeIntervalSince1970 + h.sunset.timeIntervalSince1970) / 2
            compassDayNight = engine.sunAzimuthDegrees(at: Date(timeIntervalSince1970: midTs)).map {
                CompassDayNightInput(horizon: h, midDaySunAzimuthDegrees: $0)
            }
        } else {
            sunHorizon = nil
            compassDayNight = nil
        }

        blueSectorArcAzimuths = engine.blueWindowsInLocalDay(containing: now).compactMap { win in
            guard let a0 = engine.sunAzimuthDegrees(at: win.start), let a1 = engine.sunAzimuthDegrees(at: win.end) else { return nil }
            return (a0, a1)
        }
        goldenSectorArcAzimuths = engine.goldenWindowsInLocalDay(containing: now).compactMap { win in
            guard let a0 = engine.sunAzimuthDegrees(at: win.start), let a1 = engine.sunAzimuthDegrees(at: win.end) else { return nil }
            return (a0, a1)
        }
    }

    private func refreshLiveState(now: Date) {
        defer {
            TwilightReminderScheduler.shared.reschedule(engine: engine, now: now)
        }
        guard activeFix != nil else {
            blueStartText = "—"
            blueEndText = "—"
            goldenStartText = "—"
            goldenEndText = "—"
            blueTwilightFirst = true
            blueWindowRange = nil
            goldenWindowRange = nil
            phase = nil
            compassSunBodyAzimuthDegrees = nil
            compassMoonBodyAzimuthDegrees = nil
            return
        }

        phase = engine.currentState(at: now)

        let bWin = engine.blueWindowRelevant(at: now)
        let gWin = engine.goldenWindowRelevant(at: now)

        blueWindowRange = bWin.map { ($0.start, $0.end) }
        goldenWindowRange = gWin.map { ($0.start, $0.end) }

        let live = GTCopy.liveSegment(contentLanguage)

        if let w = bWin {
            let isLive = phase == .blue
            blueStartText = isLive ? live : formatTwilightInstant(w.start)
            blueEndText = formatTwilightInstant(w.end)
        } else {
            blueStartText = "—"
            blueEndText = "—"
        }

        if let w = gWin {
            let isLive = phase == .golden
            goldenStartText = isLive ? live : formatTwilightInstant(w.start)
            goldenEndText = formatTwilightInstant(w.end)
        } else {
            goldenStartText = "—"
            goldenEndText = "—"
        }

        blueTwilightFirst = stackBlueFirst(phase: phase, blue: bWin, golden: gWin)

        if let sun = engine.sunHorizontalPosition(at: now), sun.altitudeDegrees > Self.sunIconMinAltitudeDegrees {
            compassSunBodyAzimuthDegrees = sun.azimuthDegrees
        } else {
            compassSunBodyAzimuthDegrees = nil
        }
        if let moon = engine.moonHorizontalPosition(at: now), moon.altitudeDegrees > Self.moonIconMinAltitudeDegrees {
            compassMoonBodyAzimuthDegrees = moon.azimuthDegrees
        } else {
            compassMoonBodyAzimuthDegrees = nil
        }
    }

    /// Nearer upcoming (or active) twilight block on top.
    private func stackBlueFirst(phase: PhaseState?, blue: (start: Date, end: Date)?, golden: (start: Date, end: Date)?) -> Bool {
        switch phase {
        case .blue:
            return true
        case .golden:
            return false
        case .day, .night, nil:
            guard let b = blue else { return false }
            guard let g = golden else { return true }
            return b.start < g.start
        }
    }

    private func recomputeStatusLine() {
        guard activeFix == nil else {
            statusLine = ""
            return
        }
        let auth = locationReader?.authorizationStatus ?? locationAuthorizationStatus
        if auth == .denied || auth == .restricted {
            statusLine = GTCopy.coordinatesUnavailable(contentLanguage)
            return
        }
        if auth == .authorizedAlways || auth == .authorizedWhenInUse, locationReader?.lastLocationRequestFailed == true {
            statusLine = GTCopy.coordinatesUnavailable(contentLanguage)
            return
        }
        statusLine = ""
    }

    private static func loadCachedFix() -> LocationFix? {
        guard defaults.object(forKey: latKey) != nil else { return nil }
        let lat = defaults.double(forKey: latKey)
        let lon = defaults.double(forKey: lonKey)
        let ts = defaults.double(forKey: tsKey)
        guard ts > 0 else { return nil }
        return LocationFix(latitude: lat, longitude: lon, timestamp: Date(timeIntervalSince1970: ts))
    }

    private static func saveCachedFix(_ fix: LocationFix) {
        let existing = loadCachedFix()
        guard existing != fix else { return }
        defaults.set(fix.latitude, forKey: latKey)
        defaults.set(fix.longitude, forKey: lonKey)
        defaults.set(fix.timestamp.timeIntervalSince1970, forKey: tsKey)
        if GTPhoneStartupSyncGate.isUnlocked {
            reloadTwilightWidgetTimelines()
            GTWatchConnectivitySync.shared.pushPhoneStateFromStore()
        } else {
            defaults.set(true, forKey: pendingWidgetReloadKey)
            defaults.set(true, forKey: pendingPhoneStatePushKey)
        }
    }

    private func loadCompassCalibration() {
        let defaults = Self.calibrationDefaults
        if defaults.object(forKey: GTCompassCalibrationSettings.offsetDegreesKey) != nil {
            let offset = defaults.double(forKey: GTCompassCalibrationSettings.offsetDegreesKey)
            compassHeadingOffsetDegrees = normalizeDegrees(offset)
        } else {
            compassHeadingOffsetDegrees = nil
        }
        let ts = defaults.double(forKey: GTCompassCalibrationSettings.calibratedAtKey)
        compassCalibrationDate = ts > 0 ? Date(timeIntervalSince1970: ts) : nil
    }

    private static func normalizeDegrees(_ value: Double) -> Double {
        var normalized = value.truncatingRemainder(dividingBy: 360)
        if normalized < 0 {
            normalized += 360
        }
        return normalized
    }

    /// Home-screen widgets do not observe `UserDefaults`; ask WidgetKit to re-run the timeline after cache or settings change.
    private static func reloadTwilightWidgetTimelines() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: GTIOWidgetKind.twilight)
        #endif
    }
}
