import Combine
import CoreLocation
import Foundation
import GoldenTimeCore

/// Watch UI state: GPS + `GoldenTimeEngine` only; no URLSession or remote APIs.
@MainActor
final class GoldenTimeWatchViewModel: ObservableObject {
    private let engine = GoldenTimeEngine()
    private let locationReader = WatchLocationReader()
    private var cancellables = Set<AnyCancellable>()

    private var activeFix: LocationFix?
    private var lastEngineDayStart: Date?

    @Published private(set) var snapshot: GoldenTimeSnapshot
    @Published private(set) var phase: PhaseState?
    @Published private(set) var locationHint: String

    private static let defaults = UserDefaults.standard
    private static let latKey = "gt.cached.latitude"
    private static let lonKey = "gt.cached.longitude"
    private static let tsKey = "gt.cached.timestamp"

    init() {
        snapshot = GoldenTimeSnapshot(
            hasFix: false,
            nextBlueStart: nil,
            nextGoldenStart: nil,
            todayHasBlueStart: false,
            todayHasGoldenStart: false
        )
        phase = nil
        locationHint = "正在准备…"

        if let cached = Self.loadCachedFix() {
            activeFix = cached
            locationHint = "使用已缓存 GPS（完全离线可用）"
        }

        locationReader.$latestFix
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] fix in
                self?.applyNewFix(fix)
            }
            .store(in: &cancellables)

        locationReader.$authorizationStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.updateHint(for: status)
            }
            .store(in: &cancellables)

        locationReader.refreshAuthorization()
        updateHint(for: locationReader.authorizationStatus)
        locationReader.requestLocation()

        let now = Date()
        if activeFix != nil {
            recomputeEngineIfNeeded(now: now)
        }
        refreshDerivedState(at: now)
    }

    func refreshForTimeline(now: Date) {
        recomputeEngineIfNeeded(now: now)
        refreshDerivedState(at: now)
        updateHint(for: locationReader.authorizationStatus)
    }

    private func applyNewFix(_ fix: LocationFix) {
        activeFix = fix
        Self.saveCachedFix(fix)
        locationHint = "GPS 已更新"
        let now = Date()
        recomputeEngineIfNeeded(now: now, force: true)
        refreshDerivedState(at: now)
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

    private func refreshDerivedState(at now: Date) {
        guard activeFix != nil else {
            snapshot = GoldenTimeSnapshot(
                hasFix: false,
                nextBlueStart: nil,
                nextGoldenStart: nil,
                todayHasBlueStart: false,
                todayHasGoldenStart: false
            )
            phase = nil
            return
        }

        snapshot = engine.snapshot(at: now)
        phase = engine.currentState(at: now)
    }

    private func updateHint(for status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined:
            if activeFix == nil {
                locationHint = "请在提示中允许定位"
            }
        case .denied, .restricted:
            if activeFix != nil {
                locationHint = "定位已关闭，仍使用上次 GPS 缓存（离线）"
            } else {
                locationHint = "定位未授权：可在 iPhone 的 Watch 应用里为本 App 打开定位"
            }
        case .authorizedAlways, .authorizedWhenInUse:
            if activeFix == nil {
                locationHint = "正在获取 GPS…"
            }
        @unknown default:
            break
        }
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
    }
}
