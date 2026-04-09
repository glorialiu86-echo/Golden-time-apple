import Foundation
import GoldenTimeCore
import UserNotifications

/// Schedules a rolling set of local notifications before upcoming blue or golden hour windows.
@MainActor
final class TwilightReminderScheduler {
    static let shared = TwilightReminderScheduler()

    private static let reminderChimeSoundName = UNNotificationSoundName("GTTwilightReminderChime.caf")
    /// Keep the system queue as full as iOS allows so reminders continue long after setup even if the app
    /// is not foregrounded for a while. Local notifications cap pending requests at 64.
    private static let maxScheduledReminders = 64

    private struct ScheduledReminder {
        let start: Date
        let fireDate: Date
        let identifier: String
    }

    private var lastScheduleSignature: String?
    private var rescheduleTask: Task<Void, Never>?

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
        rescheduleTask?.cancel()
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

        let reminders = debugScheduledReminders(targetRaw: targetRaw, minutes: m, now: now)
            ?? nextSchedulableReminders(
                engine: engine,
                target: target,
                targetRaw: targetRaw,
                minutes: m,
                now: now
            )
        guard !reminders.isEmpty else {
            cancelPending(clearScheduleState: true)
            lastScheduleSignature = nil
            return
        }

        let sig = reminders.map(\.identifier).joined(separator: ",")
        if lastScheduleSignature == sig {
            return
        }
        lastScheduleSignature = sig
        let storedIdentifiers = suite.stringArray(forKey: GTTwilightReminderSettings.scheduledIdentifiersKey) ?? []
        let configurationFingerprint = scheduleConfigurationFingerprint(suite: suite, targetRaw: targetRaw, minutes: m)
        let shouldReplaceExisting = suite.string(forKey: GTTwilightReminderSettings.scheduleConfigurationKey) != configurationFingerprint

        rescheduleTask = Task { @MainActor [weak self] in
            await self?.applySchedule(
                reminders: reminders,
                replaceExisting: shouldReplaceExisting,
                targetIsBlue: target == .blue,
                minutes: m,
                configurationFingerprint: configurationFingerprint,
                storedIdentifiers: storedIdentifiers
            )
        }
    }

    func cancelPending(clearScheduleState: Bool = true) {
        rescheduleTask?.cancel()
        Task {
            let identifiers = await pendingReminderIdentifiers()
            guard !identifiers.isEmpty else { return }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
        }
        guard clearScheduleState else { return }
        let suite = GTAppGroup.shared
        suite.removeObject(forKey: GTTwilightReminderSettings.scheduledSignatureKey)
        suite.removeObject(forKey: GTTwilightReminderSettings.scheduledIdentifiersKey)
        suite.removeObject(forKey: GTTwilightReminderSettings.scheduleConfigurationKey)
        suite.synchronize()
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
            identifier: reminderIdentifier(targetRaw: targetRaw, start: window.start, minutes: minutes)
        )
    }

    private func nextSchedulableReminders(
        engine: GoldenTimeEngine,
        target: GTTwilightReminderSettings.Target,
        targetRaw: String,
        minutes: Int,
        now: Date
    ) -> [ScheduledReminder] {
        var searchDate = now
        var reminders: [ScheduledReminder] = []
        for _ in 0 ..< (Self.maxScheduledReminders * 2) where reminders.count < Self.maxScheduledReminders {
            guard let reminder = reminderForNextWindow(
                engine: engine,
                target: target,
                targetRaw: targetRaw,
                minutes: minutes,
                after: searchDate
            ) else {
                break
            }
            let interval = reminder.fireDate.timeIntervalSince(now)
            if interval.isFinite, interval > 0 {
                reminders.append(reminder)
            }
            searchDate = reminder.start.addingTimeInterval(1)
        }
        return reminders
    }

    private func reminderIdentifier(targetRaw: String, start: Date, minutes: Int) -> String {
        "\(GTTwilightReminderSettings.requestIdentifierPrefix).\(targetRaw).\(minutes).\(Int(start.timeIntervalSince1970))"
    }

    private func scheduleConfigurationFingerprint(suite: UserDefaults, targetRaw: String, minutes: Int) -> String {
        let latitude = suite.object(forKey: GoldenTimeLocationCache.latitudeKey) == nil
            ? "nil"
            : String(format: "%.5f", suite.double(forKey: GoldenTimeLocationCache.latitudeKey))
        let longitude = suite.object(forKey: GoldenTimeLocationCache.longitudeKey) == nil
            ? "nil"
            : String(format: "%.5f", suite.double(forKey: GoldenTimeLocationCache.longitudeKey))
        return "\(targetRaw)|\(minutes)|\(TimeZone.autoupdatingCurrent.identifier)|\(latitude)|\(longitude)"
    }

    private func debugScheduledReminders(targetRaw: String, minutes: Int, now: Date) -> [ScheduledReminder]? {
        guard let offsets = GTUITestLaunchOverrides.reminderOffsets else { return nil }
        return offsets.enumerated().map { index, offset in
            ScheduledReminder(
                start: now.addingTimeInterval(offset + Double(minutes * 60)),
                fireDate: now.addingTimeInterval(offset),
                identifier: "\(GTTwilightReminderSettings.requestIdentifierPrefix).debug.\(targetRaw).\(minutes).\(index)"
            )
        }
    }

    private func applySchedule(
        reminders: [ScheduledReminder],
        replaceExisting: Bool,
        targetIsBlue: Bool,
        minutes: Int,
        configurationFingerprint: String,
        storedIdentifiers: [String]
    ) async {
        guard !Task.isCancelled else { return }

        if replaceExisting {
            let identifiers = await pendingReminderIdentifiers()
            if !identifiers.isEmpty {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
            }
        }

        let desiredIdentifiers = Set(reminders.map(\.identifier))
        let carriedIdentifiers = replaceExisting ? [] : storedIdentifiers.filter { desiredIdentifiers.contains($0) }
        let remindersToAdd = reminders.filter { !carriedIdentifiers.contains($0.identifier) }

        let suite = GTAppGroup.shared
        let lang = GTAppLanguage.widgetLanguageIOS(suite: suite)
        var successfulIdentifiers = carriedIdentifiers
        for reminder in remindersToAdd {
            guard !Task.isCancelled else { return }
            do {
                try await addRequest(
                    for: reminder,
                    targetIsBlue: targetIsBlue,
                    minutes: minutes,
                    lang: lang
                )
                successfulIdentifiers.append(reminder.identifier)
            } catch {
                NSLog(
                    "[TwilightReminderScheduler] Failed to schedule notification %@: %@",
                    reminder.identifier,
                    error.localizedDescription
                )
            }
        }

        let persistedSignature = successfulIdentifiers.joined(separator: ",")
        if successfulIdentifiers.isEmpty {
            suite.removeObject(forKey: GTTwilightReminderSettings.scheduledSignatureKey)
            suite.removeObject(forKey: GTTwilightReminderSettings.scheduledIdentifiersKey)
            suite.removeObject(forKey: GTTwilightReminderSettings.scheduleConfigurationKey)
            suite.synchronize()
            lastScheduleSignature = nil
            return
        }
        suite.set(persistedSignature, forKey: GTTwilightReminderSettings.scheduledSignatureKey)
        suite.set(successfulIdentifiers, forKey: GTTwilightReminderSettings.scheduledIdentifiersKey)
        suite.set(configurationFingerprint, forKey: GTTwilightReminderSettings.scheduleConfigurationKey)
        suite.synchronize()
        lastScheduleSignature = persistedSignature
    }

    private func addRequest(
        for reminder: ScheduledReminder,
        targetIsBlue: Bool,
        minutes: Int,
        lang: GTAppLanguage
    ) async throws {
        let interval = reminder.fireDate.timeIntervalSinceNow
        guard interval.isFinite, interval > 0 else {
            throw NSError(domain: "TwilightReminderScheduler", code: 1)
        }
        let content = UNMutableNotificationContent()
        content.title = GTCopy.reminderNotificationTitle(blue: targetIsBlue, lang: lang)
        content.body = GTCopy.reminderNotificationBody(blue: targetIsBlue, minutes: minutes, lang: lang)
        content.sound = UNNotificationSound(named: Self.reminderChimeSoundName)
        content.userInfo["scheduleIdentifier"] = reminder.identifier

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: trigger)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            UNUserNotificationCenter.current().add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func pendingReminderIdentifiers() async -> [String] {
        let prefix = GTTwilightReminderSettings.requestIdentifierPrefix
        return await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                continuation.resume(returning: requests.map(\.identifier).filter { $0.hasPrefix(prefix) })
            }
        }
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
