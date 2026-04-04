import Combine
import CoreLocation
import Foundation
import GoldenTimeCore
import UIKit
import WidgetKit

/// Drives `GoldenTimeEngine` on-device only: GPS + cached coordinates + local time. No URLSession or remote APIs.
@MainActor
final class GoldenTimePhoneViewModel: ObservableObject {
    private let engine = GoldenTimeEngine()
    private let locationReader = PhoneLocationReader()
    private var cancellables = Set<AnyCancellable>()
    private var locationHeartbeat: AnyCancellable?

    private var activeFix: LocationFix?
    private var lastEngineDayStart: Date?
    /// Last `[0,30)` … `[330,360)` bucket for device heading; haptic when crossing a 30° tick (like Apple Compass).
    private var headingThirtyDegreeBucket: Int?
    private let headingTickHaptic = UIImpactFeedbackGenerator(style: .light)

    /// Mirrors `GTAppLanguage.resolved()`; refresh when UserDefaults override changes.
    private(set) var contentLanguage: GTAppLanguage = GTAppLanguage.resolved()

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

    /// Map center / ray origin (same as last GPS fix used by the engine).
    @Published private(set) var mapCoordinate: CLLocationCoordinate2D?

    /// Apparent sunrise/sunset azimuths for the local civil day (all on-device math).
    @Published private(set) var sunHorizon: SunHorizonGeometry?

    /// Sunrise/sunset azimuths + midday sun bearing for compass day/night wedges; `nil` if polar or no geometry.
    @Published private(set) var compassDayNight: CompassDayNightInput?

    /// Device true (or magnetic) heading in degrees clockwise from north; `nil` until Core Location reports heading.
    @Published private(set) var deviceHeadingDegrees: Double?

    /// Sun azimuth arcs for **each** blue-hour clip in the local civil day (compass may show 0…n sectors).
    @Published private(set) var blueSectorArcAzimuths: [(Double, Double)] = []

    /// Sun azimuth arcs for each golden-hour clip in the same local day.
    @Published private(set) var goldenSectorArcAzimuths: [(Double, Double)] = []

    /// True-north sun azimuth for compass body icon when sun is above the same −50′ horizon as sunrise tables; `nil` if not up.
    @Published private(set) var compassSunBodyAzimuthDegrees: Double?

    /// True-north moon azimuth when moon is above geometric horizon; `nil` if below.
    @Published private(set) var compassMoonBodyAzimuthDegrees: Double?

    /// Wall-clock instant for UI labels; updated every second (replaces `TimelineView`, which mis-sized on some simulators).
    @Published private(set) var clockNow = GTPreviewClock.now()

    private static var defaults: UserDefaults { GTAppGroup.shared }
    /// Matches `GoldenTimeEngine` apparent sunrise/sunset (−50′).
    private static let sunIconMinAltitudeDegrees = -50.0 / 60.0
    private static let moonIconMinAltitudeDegrees = 0.0
    private static let latKey = GoldenTimeLocationCache.latitudeKey
    private static let lonKey = GoldenTimeLocationCache.longitudeKey
    private static let tsKey = GoldenTimeLocationCache.timestampKey

    private let coordFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.minimumFractionDigits = 5
        f.maximumFractionDigits = 4
        f.numberStyle = .decimal
        return f
    }()

    private func formatTwilightInstant(_ instant: Date) -> String {
        GTDateFormatters.twilightInstantLabel(instant, lang: contentLanguage)
    }

    private func triggerHeadingTickHapticIfNeeded(headingDegrees: Double) {
        var h = headingDegrees.truncatingRemainder(dividingBy: 360)
        if h < 0 { h += 360 }
        let bucket = min(11, Int(h / 30))
        if let prev = headingThirtyDegreeBucket, prev != bucket {
            headingTickHaptic.prepare()
            headingTickHaptic.impactOccurred(intensity: 0.55)
        }
        headingThirtyDegreeBucket = bucket
    }

    init() {
        if let cached = Self.loadCachedFix() {
            activeFix = cached
            updateCoordLabels(lat: cached.latitude, lon: cached.longitude)
        }

        locationReader.$latestFix
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] loc in
                self?.applyLocation(loc)
            }
            .store(in: &cancellables)

        locationReader.$authorizationStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.recomputeStatusLine()
            }
            .store(in: &cancellables)

        locationReader.$lastLocationRequestFailed
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.recomputeStatusLine()
            }
            .store(in: &cancellables)

        locationReader.$headingDegrees
            .receive(on: DispatchQueue.main)
            .sink { [weak self] v in
                guard let self else { return }
                self.deviceHeadingDegrees = v
                if let h = v {
                    self.triggerHeadingTickHapticIfNeeded(headingDegrees: h)
                } else {
                    self.headingThirtyDegreeBucket = nil
                }
            }
            .store(in: &cancellables)

        locationReader.requestLocation()
        let now = GTPreviewClock.now()
        if activeFix != nil {
            recomputeEngineIfNeeded(now: now, force: true)
            Self.reloadTwilightWidgetTimelines()
        }
        refreshWindows(at: now)
        recomputeStatusLine()

        Timer.publish(every: 1, tolerance: 0.15, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                let now = GTPreviewClock.now()
                self.clockNow = now
                self.refreshForTick(at: now)
            }
            .store(in: &cancellables)
    }

    /// Call when `GTAppLanguage.storageKey` changes (SwiftUI `AppStorage` / toggles).
    func syncContentLanguageWithStorage() {
        let next = GTAppLanguage.resolved()
        guard next != contentLanguage else { return }
        contentLanguage = next
        refreshWindows(at: clockNow)
        recomputeStatusLine()
        objectWillChange.send()
    }

    func refreshForTick(at now: Date) {
        recomputeEngineIfNeeded(now: now)
        refreshWindows(at: now)
    }

    func refreshGPS() {
        locationReader.requestLocation()
    }

    /// Call when the scene becomes active; cancels when app leaves foreground.
    func beginForegroundLocationSession() {
        refreshGPS()
        locationHeartbeat?.cancel()
        locationHeartbeat = Timer.publish(every: 600, tolerance: 20, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshGPS()
            }
    }

    func endForegroundLocationSession() {
        locationHeartbeat?.cancel()
        locationHeartbeat = nil
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
        let now = GTPreviewClock.now()
        recomputeEngineIfNeeded(now: now, force: true)
        refreshWindows(at: now)
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

    private func refreshWindows(at now: Date) {
        guard let fix = activeFix else {
            blueStartText = "—"
            blueEndText = "—"
            goldenStartText = "—"
            goldenEndText = "—"
            blueTwilightFirst = true
            blueWindowRange = nil
            goldenWindowRange = nil
            phase = nil
            mapCoordinate = nil
            sunHorizon = nil
            compassDayNight = nil
            blueSectorArcAzimuths = []
            goldenSectorArcAzimuths = []
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

        mapCoordinate = CLLocationCoordinate2D(latitude: fix.latitude, longitude: fix.longitude)
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
        let auth = locationReader.authorizationStatus
        if auth == .denied || auth == .restricted {
            statusLine = GTCopy.coordinatesUnavailable(contentLanguage)
            return
        }
        if auth == .authorizedAlways || auth == .authorizedWhenInUse, locationReader.lastLocationRequestFailed {
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
        defaults.set(fix.latitude, forKey: latKey)
        defaults.set(fix.longitude, forKey: lonKey)
        defaults.set(fix.timestamp.timeIntervalSince1970, forKey: tsKey)
        reloadTwilightWidgetTimelines()
    }

    /// Home-screen widgets do not observe `UserDefaults`; ask WidgetKit to re-run the timeline after cache or settings change.
    private static func reloadTwilightWidgetTimelines() {
        WidgetCenter.shared.reloadTimelines(ofKind: GTIOWidgetKind.twilight)
    }
}
