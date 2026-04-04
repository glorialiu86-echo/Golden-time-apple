import Foundation

/// App Group for iPhone + Watch + widgets: language, twilight card mode, and cached GPS keys stay in sync.
public enum GTAppGroup {
    public static let suiteName = "group.time.golden.GoldenHourCompass"

    public static var shared: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

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
    }
}

/// Raw values stored in App Group (mirrors phone toggle).
public enum GTTwilightDisplayMode: String {
    case clockTimes
    case countdown
    public static let storageKey = "gt.twilightCardMode"
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
