import Combine
import Foundation
import OSLog
#if canImport(WidgetKit)
import WidgetKit
#endif

#if DEBUG
enum GTDebugLaunchOverrides {
    static let nowEnvironmentKey = "GOLDEN_TIME_DEBUG_NOW_ISO8601"

    static func currentDate() -> Date {
        guard let raw = ProcessInfo.processInfo.environment[nowEnvironmentKey], !raw.isEmpty else {
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

/// App Group for iPhone + Watch + widgets: language preference (`gt.uiLanguage`: `zh` / `en` / `system`) + iPhone-written effective mirror for Watch, twilight card mode, compass UI flags, cached GPS.
public enum GTAppGroup {
    public static let suiteName = "group.time.golden.GoldenHourCompass"
    /// Keep one stable `UserDefaults` instance so SwiftUI `@AppStorage` observers stay on the same store object.
    public nonisolated(unsafe) static let shared: UserDefaults = UserDefaults(suiteName: suiteName) ?? .standard

    /// Copy keys from `UserDefaults.standard` into the group once so existing installs keep settings after enabling the group.
    public static func migrateStandardToSharedIfNeeded() {
        let suite = shared
        let std = UserDefaults.standard
        if suite.object(forKey: GTAppLanguage.storageKey) == nil,
           let v = std.string(forKey: GTAppLanguage.storageKey)
        {
            suite.set(v, forKey: GTAppLanguage.storageKey)
        }
        if suite.object(forKey: GTTwilightDisplayMode.storageKey) == nil,
           let v = std.string(forKey: GTTwilightDisplayMode.storageKey)
        {
            suite.set(v, forKey: GTTwilightDisplayMode.storageKey)
        }
        for key in [GoldenTimeLocationCache.latitudeKey, GoldenTimeLocationCache.longitudeKey, GoldenTimeLocationCache.timestampKey] {
            guard suite.object(forKey: key) == nil, std.object(forKey: key) != nil else { continue }
            suite.set(std.double(forKey: key), forKey: key)
        }
        materializeDefaultPreferencesIfNeeded()
    }

    /// Writes any missing preference keys into the App Group so user choices (and defaults) always exist on disk, not only in SwiftUI’s in-memory defaults.
    public static func materializeDefaultPreferencesIfNeeded() {
        let suite = shared
        if suite.object(forKey: GTAppLanguage.storageKey) == nil {
            suite.set(GTAppLanguage.followSystemStorageValue, forKey: GTAppLanguage.storageKey)
        }
        if suite.object(forKey: GTTwilightDisplayMode.storageKey) == nil {
            suite.set(GTTwilightDisplayMode.clockTimes.rawValue, forKey: GTTwilightDisplayMode.storageKey)
        }
        if suite.object(forKey: GTCompassMapSettings.storageKey) == nil {
            suite.set(GTCompassMapSettings.defaultCameraDistanceMeters, forKey: GTCompassMapSettings.storageKey)
        }
        if suite.object(forKey: GTCompanionUISync.showCompassMapBaseKey) == nil {
            suite.set(true, forKey: GTCompanionUISync.showCompassMapBaseKey)
        }
        if suite.object(forKey: GTTwilightReminderSettings.enabledKey) == nil {
            suite.set(false, forKey: GTTwilightReminderSettings.enabledKey)
        }
        if suite.object(forKey: GTTwilightReminderSettings.targetKey) == nil {
            suite.set(GTTwilightReminderSettings.Target.blue.rawValue, forKey: GTTwilightReminderSettings.targetKey)
        }
        if suite.object(forKey: GTTwilightReminderSettings.minutesBeforeKey) == nil {
            suite.set(GTTwilightReminderSettings.defaultMinutesBefore, forKey: GTTwilightReminderSettings.minutesBeforeKey)
        }
        if suite.object(forKey: GTAppLanguage.effectiveMirrorKey) == nil {
            #if os(iOS)
            let pref = suite.string(forKey: GTAppLanguage.storageKey) ?? GTAppLanguage.followSystemStorageValue
            suite.set(GTAppLanguage.phoneDisplayLanguage(preferenceRaw: pref).rawValue, forKey: GTAppLanguage.effectiveMirrorKey)
            #elseif os(watchOS)
            suite.set(GTAppLanguage.english.rawValue, forKey: GTAppLanguage.effectiveMirrorKey)
            #endif
        }
    }
}

enum GTPerformanceLog {
    static let subsystem = Bundle.main.bundleIdentifier ?? "time.golden.GoldenHourCompass"
}

enum GTPerfTrace {
    static func uptime() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    static func milliseconds(_ duration: TimeInterval) -> String {
        String(format: "%.1fms", duration * 1_000)
    }

    static func milliseconds(since start: TimeInterval?) -> String {
        guard let start else { return "n/a" }
        return milliseconds(uptime() - start)
    }

    static func mark(_ logger: Logger, _ message: String) {
        logger.notice("\(message, privacy: .public)")
        NSLog("[GTPerf] %@", message)
    }
}

/// Raw values stored in App Group (mirrors phone toggle).
public enum GTTwilightDisplayMode: String {
    case clockTimes
    case countdown
    public static let storageKey = "gt.twilightCardMode"
}

/// Shared compass map camera distance (meters); iPhone writes when the user adjusts zoom; Watch reads for matching scale.
public enum GTCompassMapSettings {
    public static let storageKey = "gt.compass.mapCameraDistance"
    /// Matches `TwilightCompassCard` / `CompassMapMetrics` default on iOS.
    public static let defaultCameraDistanceMeters: Double = 980
}

/// iPhone writes compass map visibility (network + debug env); Watch reads so UI matches phone without its own reachability check.
public enum GTCompanionUISync {
    public static let showCompassMapBaseKey = "gt.companion.showCompassMapBase"
}

/// In-app twilight reminder (iPhone local notification).
public enum GTTwilightReminderSettings {
    public static let enabledKey = "gt.reminder.enabled"
    public static let targetKey = "gt.reminder.target"
    public static let minutesBeforeKey = "gt.reminder.minutesBefore"
    public static let requestIdentifierPrefix = "time.golden.twilightReminder"
    public static let pendingRequestId = "\(requestIdentifierPrefix).pending"
    public static let scheduledSignatureKey = "gt.reminder.pendingSignature"
    public static let scheduledIdentifiersKey = "gt.reminder.pendingIdentifiers"
    public static let scheduleConfigurationKey = "gt.reminder.scheduleConfiguration"
    public static let defaultMinutesBefore = 15

    public enum Target: String, CaseIterable {
        case blue
        case golden
    }
}

@MainActor
public final class GTTwilightReminderStore: ObservableObject {
    @Published public private(set) var isEnabled: Bool
    @Published public private(set) var target: GTTwilightReminderSettings.Target
    @Published public private(set) var minutesBefore: Int

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = GTAppGroup.shared) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: GTTwilightReminderSettings.enabledKey)
        let targetRaw = defaults.string(forKey: GTTwilightReminderSettings.targetKey)
            ?? GTTwilightReminderSettings.Target.blue.rawValue
        target = GTTwilightReminderSettings.Target(rawValue: targetRaw) ?? .blue
        let storedMinutes = defaults.object(forKey: GTTwilightReminderSettings.minutesBeforeKey) as? Int
        minutesBefore = Self.clampedMinutes(storedMinutes ?? GTTwilightReminderSettings.defaultMinutesBefore)
    }

    public func reloadFromPersistentStore() {
        let nextEnabled = defaults.bool(forKey: GTTwilightReminderSettings.enabledKey)
        let targetRaw = defaults.string(forKey: GTTwilightReminderSettings.targetKey)
            ?? GTTwilightReminderSettings.Target.blue.rawValue
        let nextTarget = GTTwilightReminderSettings.Target(rawValue: targetRaw) ?? .blue
        let storedMinutes = defaults.object(forKey: GTTwilightReminderSettings.minutesBeforeKey) as? Int
        let nextMinutes = Self.clampedMinutes(storedMinutes ?? GTTwilightReminderSettings.defaultMinutesBefore)

        guard nextEnabled != isEnabled || nextTarget != target || nextMinutes != minutesBefore else { return }
        isEnabled = nextEnabled
        target = nextTarget
        minutesBefore = nextMinutes
    }

    public func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: GTTwilightReminderSettings.enabledKey)
        defaults.synchronize()
    }

    public func setTarget(_ nextTarget: GTTwilightReminderSettings.Target) {
        guard nextTarget != target else { return }
        target = nextTarget
        defaults.set(nextTarget.rawValue, forKey: GTTwilightReminderSettings.targetKey)
        defaults.synchronize()
    }

    public func setMinutesBefore(_ value: Int) {
        let nextMinutes = Self.clampedMinutes(value)
        guard nextMinutes != minutesBefore else { return }
        minutesBefore = nextMinutes
        defaults.set(nextMinutes, forKey: GTTwilightReminderSettings.minutesBeforeKey)
        defaults.synchronize()
    }

    private static func clampedMinutes(_ value: Int) -> Int {
        max(1, min(180, value))
    }
}

/// Shared keys for GPS cache (phone, watch, widget).
public enum GoldenTimeLocationCache {
    public static let latitudeKey = "gt.cached.latitude"
    public static let longitudeKey = "gt.cached.longitude"
    public static let timestampKey = "gt.cached.timestamp"
}

/// `WidgetKit` `StaticConfiguration(kind:)` — must match `GoldenTwilightIOSWidget`.
public enum GTIOWidgetKind {
    public static let twilight = "time.golden.GoldenHourCompass.ios.twilight"
}

/// `WidgetKit` `AppIntentConfiguration(kind:)` — must match `GoldenTwilightWidget` on watchOS.
public enum GTWatchWidgetKind {
    public static let twilight = "time.golden.GoldenHourCompass.twilight"
}
