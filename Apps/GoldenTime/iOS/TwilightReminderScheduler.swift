import Foundation
import GoldenTimeCore
import UserNotifications

/// Schedules a single local notification before the next blue or golden hour window (from in-app settings).
@MainActor
final class TwilightReminderScheduler {
    static let shared = TwilightReminderScheduler()

    private static let reminderChimeSoundName = UNNotificationSoundName("GTTwilightReminderChime.caf")

    private var lastScheduleSignature: String?

    private init() {}

    func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return await withCheckedContinuation { cont in
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    cont.resume(returning: granted)
                }
            }
        default:
            return false
        }
    }

    func reschedule(engine: GoldenTimeEngine, now: Date) {
        let suite = GTAppGroup.shared
        guard suite.bool(forKey: GTTwilightReminderSettings.enabledKey) else {
            cancelPending()
            lastScheduleSignature = nil
            return
        }
        guard engine.snapshot(at: now).hasFix else {
            cancelPending()
            return
        }

        let targetRaw = suite.string(forKey: GTTwilightReminderSettings.targetKey)
            ?? GTTwilightReminderSettings.Target.blue.rawValue
        let target = GTTwilightReminderSettings.Target(rawValue: targetRaw) ?? .blue
        let storedMinutes = suite.object(forKey: GTTwilightReminderSettings.minutesBeforeKey) as? Int
        let minutes = storedMinutes ?? GTTwilightReminderSettings.defaultMinutesBefore
        let m = max(1, min(180, minutes))

        let window: (start: Date, end: Date)?
        switch target {
        case .blue: window = engine.nextBlueWindow(after: now)
        case .golden: window = engine.nextGoldenWindow(after: now)
        }
        guard let start = window?.start else {
            cancelPending()
            lastScheduleSignature = nil
            return
        }

        let fireDate = start.addingTimeInterval(-Double(m * 60))
        guard fireDate > now else {
            cancelPending()
            lastScheduleSignature = nil
            return
        }

        let sig = "\(targetRaw)|\(Int(start.timeIntervalSince1970))|\(m)"
        if lastScheduleSignature == sig {
            return
        }

        let interval = max(1, fireDate.timeIntervalSince(now))
        guard interval.isFinite, interval < 86400 * 8 else {
            cancelPending()
            return
        }

        lastScheduleSignature = sig
        cancelPending()

        let lang = GTAppLanguage.widgetLanguageIOS(suite: suite)
        let content = UNMutableNotificationContent()
        content.title = GTCopy.reminderNotificationTitle(blue: target == .blue, lang: lang)
        content.body = GTCopy.reminderNotificationBody(blue: target == .blue, minutes: m, lang: lang)
        // Bundled short chime (~0.2s); avoids system default tri-tone “alarm” feel.
        content.sound = UNNotificationSound(named: Self.reminderChimeSoundName)

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(
            identifier: GTTwilightReminderSettings.pendingRequestId,
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    func cancelPending() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [GTTwilightReminderSettings.pendingRequestId]
        )
    }
}

/// `UNUserNotificationCenterDelegate` is invoked on an arbitrary queue; keep this type non-`MainActor` for Swift 6 concurrency.
final class TwilightReminderNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    nonisolated(unsafe) static let shared = TwilightReminderNotificationDelegate()

    private override init() {
        super.init()
    }

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
