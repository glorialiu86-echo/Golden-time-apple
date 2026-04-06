import Foundation
#if canImport(WidgetKit)
import WidgetKit
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
    public static let pendingRequestId = "time.golden.twilightReminder.pending"
    public static let defaultMinutesBefore = 15

    public enum Target: String, CaseIterable {
        case blue
        case golden
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
