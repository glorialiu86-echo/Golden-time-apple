import Combine
import CoreLocation
import Foundation
import GoldenTimeCore
import OSLog
import WidgetKit

/// Watch UI state: GPS + heading + `GoldenTimeEngine`; mirrors iPhone twilight windows and compass inputs.
@MainActor
final class GoldenTimeWatchViewModel: ObservableObject {
    private struct DailyDerivedStateKey: Equatable {
        let latitude: Double
        let longitude: Double
        let dayStart: Date
        let language: GTAppLanguage
        let compassPageActive: Bool
    }

    private static let performanceLog = Logger(subsystem: GTPerformanceLog.subsystem, category: "WatchViewModel")

    private let engine = GoldenTimeEngine()
    /// Created after the first frame (`startLocationPipeline`) so `CLLocationManager` init never blocks app launch on watchOS Simulator.
    private var locationReader: WatchLocationReader?
    private var cancellables = Set<AnyCancellable>()
    private var compassHeadingOffsetDegrees = 0.0

    private var activeFix: LocationFix?
    private var lastEngineDayStart: Date?
    private var lastDailyDerivedStateKey: DailyDerivedStateKey?
    private var isCompassPageActive = false
    private var lastAuthorizationGrantedUptime: TimeInterval?

    @Published private(set) var blueStartText = "—"
    @Published private(set) var blueEndText = "—"
    @Published private(set) var goldenStartText = "—"
    @Published private(set) var goldenEndText = "—"
    @Published private(set) var blueTwilightFirst = true
    @Published private(set) var blueWindowRange: (start: Date, end: Date)?
    @Published private(set) var goldenWindowRange: (start: Date, end: Date)?
    @Published private(set) var phase: PhaseState?
    @Published private(set) var mapCoordinate: CLLocationCoordinate2D?
    @Published private(set) var deviceHeadingDegrees: Double?
    @Published private(set) var deviceHeadingUsesTrueNorth = false
    @Published private(set) var blueSectorArcAzimuths: [(Double, Double)] = []
    @Published private(set) var goldenSectorArcAzimuths: [(Double, Double)] = []
    @Published private(set) var compassDayNight: CompassDayNightInput?
    @Published private(set) var compassSunBodyAzimuthDegrees: Double?
    @Published private(set) var compassMoonBodyAzimuthDegrees: Double?
    @Published private(set) var clockNow: Date = {
        #if DEBUG
        GTDebugLaunchOverrides.currentDate()
        #else
        Date()
        #endif
    }()
    @Published private(set) var latitudeText = "—"
    @Published private(set) var longitudeText = "—"
    @Published private(set) var locationHint: String
    @Published private(set) var snapshot: GoldenTimeSnapshot = .init(
        hasFix: false,
        nextBlueStart: nil,
        nextGoldenStart: nil,
        todayHasBlueStart: false,
        todayHasGoldenStart: false
    )

    private(set) var contentLanguage: GTAppLanguage = GTAppLanguage.resolved()

    private static var defaults: UserDefaults { GTAppGroup.shared }
    private static let calibrationDefaults = UserDefaults.standard
    private static let sunIconMinAltitudeDegrees = -50.0 / 60.0
    private static let moonIconMinAltitudeDegrees = 0.0

    private let coordFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.minimumFractionDigits = 5
        f.maximumFractionDigits = 4
        f.numberStyle = .decimal
        return f
    }()

    private func currentNow() -> Date {
        #if DEBUG
        GTDebugLaunchOverrides.currentDate()
        #else
        Date()
        #endif
    }

    init() {
        locationHint = "…"
        loadCompassCalibration()

        if let cached = Self.loadCachedFix() {
            activeFix = cached
            locationHint = GTAppLanguage.resolved() == .chinese ? "已缓存 GPS" : "Cached GPS"
        }

        let now = currentNow()
        clockNow = now
        if activeFix != nil {
            recomputeEngineIfNeeded(now: now, force: true)
        }
        rebuildDailyDerivedStateIfNeeded(now: now, force: true)
        refreshTwilightPageState(now: now)
        refreshCompassStateIfNeeded(now: now, force: true)
    }

    /// Wire Core Location after SwiftUI has presented the root view (avoids hanging on the system launch screen).
    func startLocationPipeline() {
        guard locationReader == nil else { return }
        Self.performanceLog.notice("watch location pipeline start")
        let reader = WatchLocationReader()
        locationReader = reader

        reader.$latestFix
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] fix in
                GTPerfTrace.mark(
                    Self.performanceLog,
                    "watch latestFix published afterAuthorized=\(GTPerfTrace.milliseconds(since: self?.lastAuthorizationGrantedUptime))"
                )
                self?.applyNewFix(fix)
            }
            .store(in: &cancellables)

        reader.$headingDegrees
            .receive(on: DispatchQueue.main)
            .sink { [weak self] v in
                self?.deviceHeadingDegrees = v
            }
            .store(in: &cancellables)

        reader.$headingUsesTrueNorth
            .receive(on: DispatchQueue.main)
            .sink { [weak self] usesTrueNorth in
                self?.deviceHeadingUsesTrueNorth = usesTrueNorth
            }
            .store(in: &cancellables)

        reader.$authorizationStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                if status == .authorizedAlways || status == .authorizedWhenInUse {
                    self?.lastAuthorizationGrantedUptime = GTPerfTrace.uptime()
                    GTPerfTrace.mark(Self.performanceLog, "watch authorization became available")
                }
                self?.updateHint(for: status)
            }
            .store(in: &cancellables)

        reader.setHeadingUpdatesEnabled(isCompassPageActive)
        reader.refreshAuthorization()
        updateHint(for: reader.authorizationStatus)
        reader.requestLocation()
    }

    func setCompassPageActive(_ isActive: Bool) {
        guard isCompassPageActive != isActive else { return }
        isCompassPageActive = isActive
        locationReader?.setHeadingUpdatesEnabled(isActive)
        rebuildDailyDerivedStateIfNeeded(now: clockNow, force: true)
        refreshCompassStateIfNeeded(now: clockNow, force: true)
    }

    func syncContentLanguageWithStorage() {
        let next = GTAppLanguage.resolved()
        guard next != contentLanguage else { return }
        contentLanguage = next
        rebuildDailyDerivedStateIfNeeded(now: clockNow, force: true)
        refreshTwilightPageState(now: clockNow)
        refreshCompassStateIfNeeded(now: clockNow, force: true)
        objectWillChange.send()
    }

    var correctedHeadingDegrees: Double? {
        guard let raw = deviceHeadingDegrees else { return nil }
        return Self.normalizeDegrees(raw + compassHeadingOffsetDegrees)
    }

    var hasCompassCalibration: Bool {
        compassHeadingOffsetDegrees != 0 || Self.calibrationDefaults.object(forKey: GTWatchCompassCalibrationSettings.offsetDegreesKey) != nil
    }

    var canSaveCompassCalibration: Bool {
        guard activeFix != nil else { return false }
        guard deviceHeadingDegrees != nil else { return false }
        guard deviceHeadingUsesTrueNorth else { return false }
        return compassSunBodyAzimuthDegrees != nil
    }

    @discardableResult
    func saveCompassCalibrationFromCurrentSunAlignment() -> Bool {
        guard let rawHeading = deviceHeadingDegrees,
              let sunAzimuth = compassSunBodyAzimuthDegrees,
              canSaveCompassCalibration else {
            return false
        }
        let offset = Self.normalizeDegrees(sunAzimuth - rawHeading)
        let savedAt = currentNow()
        compassHeadingOffsetDegrees = offset
        Self.calibrationDefaults.set(offset, forKey: GTWatchCompassCalibrationSettings.offsetDegreesKey)
        Self.calibrationDefaults.set(savedAt.timeIntervalSince1970, forKey: GTWatchCompassCalibrationSettings.calibratedAtKey)
        Self.calibrationDefaults.set(GTWatchCompassCalibrationSettings.sourceSun, forKey: GTWatchCompassCalibrationSettings.sourceKey)
        Self.calibrationDefaults.set(GTWatchCompassCalibrationSettings.version, forKey: GTWatchCompassCalibrationSettings.versionKey)
        objectWillChange.send()
        return true
    }

    func clearCompassCalibration() {
        compassHeadingOffsetDegrees = 0
        Self.calibrationDefaults.removeObject(forKey: GTWatchCompassCalibrationSettings.offsetDegreesKey)
        Self.calibrationDefaults.removeObject(forKey: GTWatchCompassCalibrationSettings.calibratedAtKey)
        Self.calibrationDefaults.removeObject(forKey: GTWatchCompassCalibrationSettings.sourceKey)
        Self.calibrationDefaults.removeObject(forKey: GTWatchCompassCalibrationSettings.versionKey)
        objectWillChange.send()
    }

    func refreshForTimeline(now: Date) {
        clockNow = now
        recomputeEngineIfNeeded(now: now)
        rebuildDailyDerivedStateIfNeeded(now: now)
        refreshTwilightPageState(now: now)
        refreshCompassStateIfNeeded(now: now)
        updateHint(for: locationReader?.authorizationStatus ?? .notDetermined)
    }

    private func applyNewFix(_ fix: LocationFix) {
        let applyStart = GTPerfTrace.uptime()
        activeFix = fix
        Self.saveCachedFix(fix)
        locationHint = contentLanguage == .chinese ? "GPS 已更新" : "GPS updated"
        let now = currentNow()
        recomputeEngineIfNeeded(now: now, force: true)
        rebuildDailyDerivedStateIfNeeded(now: now, force: true)
        refreshTwilightPageState(now: now)
        refreshCompassStateIfNeeded(now: now, force: true)
        GTPerfTrace.mark(
            Self.performanceLog,
            "watch applyNewFix finished in \(GTPerfTrace.milliseconds(GTPerfTrace.uptime() - applyStart)) sinceAuthorized=\(GTPerfTrace.milliseconds(since: lastAuthorizationGrantedUptime)) lat=\(String(format: "%.5f", fix.latitude)) lon=\(String(format: "%.5f", fix.longitude))"
        )
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
            blueSectorArcAzimuths = []
            goldenSectorArcAzimuths = []
            compassDayNight = nil
            latitudeText = "—"
            longitudeText = "—"
            return
        }
        let key = DailyDerivedStateKey(
            latitude: fix.latitude,
            longitude: fix.longitude,
            dayStart: Calendar.autoupdatingCurrent.startOfDay(for: now),
            language: contentLanguage,
            compassPageActive: isCompassPageActive
        )
        guard force || key != lastDailyDerivedStateKey else { return }
        lastDailyDerivedStateKey = key
        mapCoordinate = CLLocationCoordinate2D(latitude: fix.latitude, longitude: fix.longitude)
        updateCoordLabels(lat: fix.latitude, lon: fix.longitude)

        guard isCompassPageActive else {
            blueSectorArcAzimuths = []
            goldenSectorArcAzimuths = []
            compassDayNight = nil
            return
        }

        if let h = engine.sunHorizonGeometry(for: now) {
            let midTs = (h.sunrise.timeIntervalSince1970 + h.sunset.timeIntervalSince1970) / 2
            compassDayNight = engine.sunAzimuthDegrees(at: Date(timeIntervalSince1970: midTs)).map {
                CompassDayNightInput(horizon: h, midDaySunAzimuthDegrees: $0)
            }
        } else {
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
        Self.performanceLog.debug("watch daily derived state rebuilt")
    }

    private func refreshTwilightPageState(now: Date) {
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
            snapshot = engine.snapshot(at: now)
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
        snapshot = engine.snapshot(at: now)
    }

    private func refreshCompassStateIfNeeded(now: Date, force: Bool = false) {
        guard isCompassPageActive || force else { return }
        guard activeFix != nil else {
            compassSunBodyAzimuthDegrees = nil
            compassMoonBodyAzimuthDegrees = nil
            return
        }
        guard isCompassPageActive else {
            compassSunBodyAzimuthDegrees = nil
            compassMoonBodyAzimuthDegrees = nil
            return
        }

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

    private func formatTwilightInstant(_ instant: Date) -> String {
        GTDateFormatters.twilightInstantLabel(instant, lang: contentLanguage)
    }

    private func updateCoordLabels(lat: Double, lon: Double) {
        latitudeText = coordFormatter.string(from: NSNumber(value: lat)) ?? String(format: "%.5f", lat)
        longitudeText = coordFormatter.string(from: NSNumber(value: lon)) ?? String(format: "%.5f", lon)
    }

    private func updateHint(for status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined:
            if activeFix == nil {
                locationHint = contentLanguage == .chinese ? "允许定位以推算" : "Allow location"
            }
        case .denied, .restricted:
            if activeFix != nil {
                locationHint = contentLanguage == .chinese ? "使用缓存坐标" : "Using cached fix"
            } else {
                locationHint = contentLanguage == .chinese ? "定位未授权" : "Location off"
            }
        case .authorizedAlways, .authorizedWhenInUse:
            if activeFix == nil {
                locationHint = contentLanguage == .chinese ? "获取 GPS…" : "Getting GPS…"
            }
        @unknown default:
            break
        }
    }

    private static func loadCachedFix() -> LocationFix? {
        guard defaults.object(forKey: GoldenTimeLocationCache.latitudeKey) != nil else { return nil }
        let lat = defaults.double(forKey: GoldenTimeLocationCache.latitudeKey)
        let lon = defaults.double(forKey: GoldenTimeLocationCache.longitudeKey)
        let ts = defaults.double(forKey: GoldenTimeLocationCache.timestampKey)
        guard ts > 0 else { return nil }
        return LocationFix(latitude: lat, longitude: lon, timestamp: Date(timeIntervalSince1970: ts))
    }

    private static func saveCachedFix(_ fix: LocationFix) {
        let existing = loadCachedFix()
        guard existing != fix else { return }
        defaults.set(fix.latitude, forKey: GoldenTimeLocationCache.latitudeKey)
        defaults.set(fix.longitude, forKey: GoldenTimeLocationCache.longitudeKey)
        defaults.set(fix.timestamp.timeIntervalSince1970, forKey: GoldenTimeLocationCache.timestampKey)
        WidgetCenter.shared.reloadTimelines(ofKind: GTWatchWidgetKind.twilight)
    }

    private func loadCompassCalibration() {
        let defaults = Self.calibrationDefaults
        guard defaults.object(forKey: GTWatchCompassCalibrationSettings.offsetDegreesKey) != nil else {
            compassHeadingOffsetDegrees = 0
            return
        }
        compassHeadingOffsetDegrees = Self.normalizeDegrees(
            defaults.double(forKey: GTWatchCompassCalibrationSettings.offsetDegreesKey)
        )
    }

    private static func normalizeDegrees(_ value: Double) -> Double {
        var normalized = value.truncatingRemainder(dividingBy: 360)
        if normalized > 180 { normalized -= 360 }
        if normalized < -180 { normalized += 360 }
        return normalized
    }
}
