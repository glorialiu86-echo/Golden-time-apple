import SwiftUI
import UserNotifications

#if DEBUG
enum GTUITestLaunchOverrides {
    static let isEnabled = ProcessInfo.processInfo.environment["GOLDEN_TIME_UI_TEST_MODE"] == "1"
    private static let sessionEnvironmentKey = "GOLDEN_TIME_UI_TEST_SESSION"
    private static let persistedSessionKey = "gt.uiTest.activeSession"

    static var disablesLiveLocation: Bool {
        isEnabled || ProcessInfo.processInfo.environment["GOLDEN_TIME_UI_TEST_DISABLE_LIVE_LOCATION"] == "1"
    }

    static var reminderOffsets: [TimeInterval]? {
        guard let raw = ProcessInfo.processInfo.environment["GOLDEN_TIME_UI_TEST_REMINDER_SECONDS"], !raw.isEmpty else {
            return nil
        }
        let offsets = raw
            .split(separator: ",")
            .compactMap { TimeInterval($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { $0 > 0 }
            .sorted()
        return offsets.isEmpty ? nil : offsets
    }

    static var cachedLocation: (latitude: Double, longitude: Double)? {
        guard let raw = ProcessInfo.processInfo.environment["GOLDEN_TIME_UI_TEST_LOCATION"], !raw.isEmpty else {
            return nil
        }
        let parts = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.count == 2, let latitude = Double(parts[0]), let longitude = Double(parts[1]) else {
            return nil
        }
        return (latitude, longitude)
    }

    static func bootstrap() {
        guard isEnabled else { return }
        let suite = GTAppGroup.shared
        GTAppGroup.migrateStandardToSharedIfNeeded()

        let session = ProcessInfo.processInfo.environment[sessionEnvironmentKey] ?? "default"
        guard suite.string(forKey: persistedSessionKey) != session else { return }
        suite.set(session, forKey: persistedSessionKey)

        if let location = cachedLocation {
            suite.set(location.latitude, forKey: GoldenTimeLocationCache.latitudeKey)
            suite.set(location.longitude, forKey: GoldenTimeLocationCache.longitudeKey)
            suite.set(Date().timeIntervalSince1970, forKey: GoldenTimeLocationCache.timestampKey)
        }
        suite.set(false, forKey: GTTwilightReminderSettings.enabledKey)
        suite.set(GTTwilightReminderSettings.Target.blue.rawValue, forKey: GTTwilightReminderSettings.targetKey)
        suite.set(GTTwilightReminderSettings.defaultMinutesBefore, forKey: GTTwilightReminderSettings.minutesBeforeKey)
        suite.removeObject(forKey: GTTwilightReminderSettings.scheduledSignatureKey)
        suite.removeObject(forKey: GTTwilightReminderSettings.scheduledIdentifiersKey)
        suite.removeObject(forKey: GTTwilightReminderSettings.scheduleConfigurationKey)
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
