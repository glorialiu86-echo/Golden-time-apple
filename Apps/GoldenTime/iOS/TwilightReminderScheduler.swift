import Foundation
import GoldenTimeCore
import UserNotifications

/// Schedules a single local notification before the next blue or golden hour window (from in-app settings).
@MainActor
final class TwilightReminderScheduler {
    static let shared = TwilightReminderScheduler()

    private static let reminderChimeSoundName = UNNotificationSoundName("GTTwilightReminderChime.caf")

    private struct ScheduledReminder {
        let start: Date
        let fireDate: Date
        let signature: String
    }

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
            cancelPending(clearScheduleState: true)
            lastScheduleSignature = nil
            return
        }
        guard engine.snapshot(at: now).hasFix else {
            cancelPending(clearScheduleState: true)
            lastScheduleSignature = nil
            return
        }

        let targetRaw = suite.string(forKey: GTTwilightReminderSettings.targetKey)
            ?? GTTwilightReminderSettings.Target.blue.rawValue
        let target = GTTwilightReminderSettings.Target(rawValue: targetRaw) ?? .blue
        let storedMinutes = suite.object(forKey: GTTwilightReminderSettings.minutesBeforeKey) as? Int
        let minutes = storedMinutes ?? GTTwilightReminderSettings.defaultMinutesBefore
        let m = max(1, min(180, minutes))

        if let pendingReminder = reminderForNextWindow(engine: engine, target: target, targetRaw: targetRaw, minutes: m, after: now),
           pendingReminder.fireDate <= now,
           suite.string(forKey: GTTwilightReminderSettings.scheduledSignatureKey) == pendingReminder.signature
        {
            lastScheduleSignature = pendingReminder.signature
            return
        }

        guard let reminder = nextSchedulableReminder(
            engine: engine,
            target: target,
            targetRaw: targetRaw,
            minutes: m,
            now: now
        ) else {
            cancelPending(clearScheduleState: true)
            lastScheduleSignature = nil
            return
        }

        let sig = reminder.signature
        if lastScheduleSignature == sig {
            return
        }

        let interval = max(1, reminder.fireDate.timeIntervalSince(now))
        guard interval.isFinite, interval < 86400 * 8 else {
            cancelPending(clearScheduleState: true)
            lastScheduleSignature = nil
            return
        }

        lastScheduleSignature = sig
        cancelPending(clearScheduleState: true)

        let lang = GTAppLanguage.widgetLanguageIOS(suite: suite)
        let content = UNMutableNotificationContent()
        content.title = GTCopy.reminderNotificationTitle(blue: target == .blue, lang: lang)
        content.body = GTCopy.reminderNotificationBody(blue: target == .blue, minutes: m, lang: lang)
        // Bundled short chime (~0.2s); avoids system default tri-tone “alarm” feel.
        content.sound = UNNotificationSound(named: Self.reminderChimeSoundName)
        content.userInfo["scheduleSignature"] = sig

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(
            identifier: GTTwilightReminderSettings.pendingRequestId,
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            Task { @MainActor [weak self] in
                self?.finishScheduling(signature: sig, error: error)
            }
        }
    }

    func cancelPending(clearScheduleState: Bool = true) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [GTTwilightReminderSettings.pendingRequestId]
        )
        guard clearScheduleState else { return }
        GTAppGroup.shared.removeObject(forKey: GTTwilightReminderSettings.scheduledSignatureKey)
    }

    private func reminderForNextWindow(
        engine: GoldenTimeEngine,
        target: GTTwilightReminderSettings.Target,
        targetRaw: String,
        minutes: Int,
        after date: Date
    ) -> ScheduledReminder? {
        let window: (start: Date, end: Date)?
        switch target {
        case .blue:
            window = engine.nextBlueWindow(after: date)
        case .golden:
            window = engine.nextGoldenWindow(after: date)
        }
        guard let window else { return nil }
        return ScheduledReminder(
            start: window.start,
            fireDate: window.start.addingTimeInterval(-Double(minutes * 60)),
            signature: scheduleSignature(targetRaw: targetRaw, start: window.start, minutes: minutes)
        )
    }

    private func nextSchedulableReminder(
        engine: GoldenTimeEngine,
        target: GTTwilightReminderSettings.Target,
        targetRaw: String,
        minutes: Int,
        now: Date
    ) -> ScheduledReminder? {
        var searchDate = now
        for _ in 0 ..< 12 {
            guard let reminder = reminderForNextWindow(
                engine: engine,
                target: target,
                targetRaw: targetRaw,
                minutes: minutes,
                after: searchDate
            ) else {
                return nil
            }
            if reminder.fireDate > now {
                return reminder
            }
            searchDate = reminder.start.addingTimeInterval(1)
        }
        return nil
    }

    private func scheduleSignature(targetRaw: String, start: Date, minutes: Int) -> String {
        "\(targetRaw)|\(Int(start.timeIntervalSince1970))|\(minutes)"
    }

    private func finishScheduling(signature: String, error: Error?) {
        if let error {
            if lastScheduleSignature == signature {
                lastScheduleSignature = nil
            }
            GTAppGroup.shared.removeObject(forKey: GTTwilightReminderSettings.scheduledSignatureKey)
            NSLog("[TwilightReminderScheduler] Failed to schedule notification: %@", error.localizedDescription)
            return
        }
        GTAppGroup.shared.set(signature, forKey: GTTwilightReminderSettings.scheduledSignatureKey)
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
