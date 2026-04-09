import SwiftUI
import UserNotifications

#if DEBUG
enum GTUITestLaunchOverrides {
    private static let modeLaunchArgument = "-GOLDEN_TIME_UI_TEST_MODE"
    private static let modeEnvironmentKey = "GOLDEN_TIME_UI_TEST_MODE"
    private static let disableLiveLocationEnvironmentKey = "GOLDEN_TIME_UI_TEST_DISABLE_LIVE_LOCATION"
    private static let reminderEnabledEnvironmentKey = "GOLDEN_TIME_UI_TEST_REMINDER_ENABLED"
    private static let reminderOffsetsEnvironmentKey = "GOLDEN_TIME_UI_TEST_REMINDER_SECONDS"
    private static let locationEnvironmentKey = "GOLDEN_TIME_UI_TEST_LOCATION"
    private static let sessionEnvironmentKey = "GOLDEN_TIME_UI_TEST_SESSION"
    private static let xctestConfigurationEnvironmentKey = "XCTestConfigurationFilePath"
    private static let persistedSessionKey = "gt.uiTest.activeSession"
    private static let persistedDisableLiveLocationKey = "gt.uiTest.disableLiveLocation"
    private static let persistedReminderOffsetsKey = "gt.uiTest.reminderOffsets"
    private static let persistedLatitudeKey = "gt.uiTest.location.latitude"
    private static let persistedLongitudeKey = "gt.uiTest.location.longitude"

    private static var environment: [String: String] {
        ProcessInfo.processInfo.environment
    }

    private static var isRunningUnderXCTest: Bool {
        environment[xctestConfigurationEnvironmentKey] != nil
    }

    private static var hasExplicitUITestMode: Bool {
        environment[modeEnvironmentKey] == "1" || CommandLine.arguments.contains(modeLaunchArgument)
    }

    private static var explicitSession: String? {
        guard let raw = environment[sessionEnvironmentKey], !raw.isEmpty else { return nil }
        return raw
    }

    static var disablesLiveLocation: Bool {
        if environment[disableLiveLocationEnvironmentKey] == "1" {
            return true
        }
        if hasExplicitUITestMode {
            return true
        }
        return isEnabled && GTAppGroup.shared.bool(forKey: persistedDisableLiveLocationKey)
    }

    static let isEnabled: Bool = {
        if hasExplicitUITestMode {
            return true
        }
        return isRunningUnderXCTest && GTAppGroup.shared.string(forKey: persistedSessionKey) != nil
    }()

    private static func parseReminderOffsets(_ raw: String?) -> [TimeInterval]? {
        guard let raw, !raw.isEmpty else { return nil }
        let offsets = raw
            .split(separator: ",")
            .compactMap { TimeInterval($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { $0 > 0 }
            .sorted()
        return offsets.isEmpty ? nil : offsets
    }

    static var reminderOffsets: [TimeInterval]? {
        if let offsets = parseReminderOffsets(environment[reminderOffsetsEnvironmentKey]) {
            return offsets
        }
        guard isEnabled else { return nil }
        return parseReminderOffsets(GTAppGroup.shared.string(forKey: persistedReminderOffsetsKey))
    }

    private static func parseLocation(_ raw: String?) -> (latitude: Double, longitude: Double)? {
        guard let raw, !raw.isEmpty else { return nil }
        let parts = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.count == 2, let latitude = Double(parts[0]), let longitude = Double(parts[1]) else {
            return nil
        }
        return (latitude, longitude)
    }

    static var cachedLocation: (latitude: Double, longitude: Double)? {
        if let location = parseLocation(environment[locationEnvironmentKey]) {
            return location
        }
        guard isEnabled else { return nil }
        let suite = GTAppGroup.shared
        guard suite.object(forKey: persistedLatitudeKey) != nil, suite.object(forKey: persistedLongitudeKey) != nil else {
            return nil
        }
        return (
            latitude: suite.double(forKey: persistedLatitudeKey),
            longitude: suite.double(forKey: persistedLongitudeKey)
        )
    }

    static func bootstrap() {
        guard let session = explicitSession else {
            return
        }
        let suite = GTAppGroup.shared
        GTAppGroup.migrateStandardToSharedIfNeeded()

        guard suite.string(forKey: persistedSessionKey) != session else { return }
        suite.set(session, forKey: persistedSessionKey)
        suite.set(environment[disableLiveLocationEnvironmentKey] == "1", forKey: persistedDisableLiveLocationKey)
        if let rawOffsets = environment[reminderOffsetsEnvironmentKey], !rawOffsets.isEmpty {
            suite.set(rawOffsets, forKey: persistedReminderOffsetsKey)
        } else {
            suite.removeObject(forKey: persistedReminderOffsetsKey)
        }

        if let location = cachedLocation {
            suite.set(location.latitude, forKey: persistedLatitudeKey)
            suite.set(location.longitude, forKey: persistedLongitudeKey)
            suite.set(location.latitude, forKey: GoldenTimeLocationCache.latitudeKey)
            suite.set(location.longitude, forKey: GoldenTimeLocationCache.longitudeKey)
            suite.set(Date().timeIntervalSince1970, forKey: GoldenTimeLocationCache.timestampKey)
        }
        suite.set(environment[reminderEnabledEnvironmentKey] == "1", forKey: GTTwilightReminderSettings.enabledKey)
        suite.set(GTTwilightReminderSettings.Target.blue.rawValue, forKey: GTTwilightReminderSettings.targetKey)
        suite.set(GTTwilightReminderSettings.defaultMinutesBefore, forKey: GTTwilightReminderSettings.minutesBeforeKey)
        suite.removeObject(forKey: GTTwilightReminderSettings.scheduledSignatureKey)
        suite.removeObject(forKey: GTTwilightReminderSettings.scheduledIdentifiersKey)
        suite.removeObject(forKey: GTTwilightReminderSettings.scheduleConfigurationKey)
        suite.synchronize()
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }
}
#else
enum GTUITestLaunchOverrides {
    static let isEnabled = false
    static let disablesLiveLocation = false
    static let reminderOffsets: [TimeInterval]? = nil

    static func bootstrap() {}
}
#endif

@main
struct GoldenTimeApp: App {
    init() {
        UNUserNotificationCenter.current().delegate = TwilightReminderNotificationDelegate.shared
        GTUITestLaunchOverrides.bootstrap()
    }

    var body: some Scene {
        WindowGroup {
            GoldenTimePhoneRootView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
