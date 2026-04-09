import XCTest

@MainActor
final class GoldenTimeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments.append("-GOLDEN_TIME_UI_TEST_MODE")
        app.launchEnvironment["GOLDEN_TIME_UI_TEST_SESSION"] = UUID().uuidString
        app.launchEnvironment["GOLDEN_TIME_UI_TEST_MODE"] = "1"
        app.launchEnvironment["GOLDEN_TIME_UI_TEST_DISABLE_LIVE_LOCATION"] = "1"
        app.launchEnvironment["GOLDEN_TIME_UI_TEST_REMINDER_ENABLED"] = "0"
        app.launchEnvironment["GOLDEN_TIME_UI_TEST_LOCATION"] = "31.230416,121.473701"
        app.launchEnvironment["GOLDEN_TIME_UI_TEST_REMINDER_SECONDS"] = "8,12,16,20,24"
        app.launchEnvironment["GOLDEN_TIME_DEBUG_UI_LANGUAGE"] = "en"
        app.launchEnvironment["GOLDEN_TIME_DEBUG_NOW_ISO8601"] = "2026-04-09T05:00:00Z"
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testTwilightReminderKeepsDeliveringUntilUserTurnsItOff() throws {
        let reminderToggle = openSettingsAndFindReminderToggle()
        XCTAssertTrue(reminderToggle.waitForExistence(timeout: 10), "Reminder toggle should exist")
        enableReminderIfNeeded(toggle: reminderToggle)
        waitForNotificationPipelineToStabilize()

        XCUIDevice.shared.press(.home)
        sleep(14)

        app.activate()
        let reopenedToggle = openSettingsAndFindReminderToggle()
        XCTAssertTrue(reopenedToggle.waitForExistence(timeout: 10), "Reminder toggle should still exist after returning")
        XCTAssertEqual(reopenedToggle.value as? String, "1", "Reminder should remain enabled after background delivery")

        refreshNotificationDebugMetrics()
        let pendingCount = notificationDebugValue(identifier: "gt.phone.debug.reminderPendingCount")
        let plannedCount = notificationDebugValue(identifier: "gt.phone.debug.reminderPlanCount")
        XCTAssertGreaterThanOrEqual(pendingCount, 1, "Reminder should still have future notifications queued")
        XCTAssertGreaterThanOrEqual(plannedCount, pendingCount, "Persisted reminder plan should remain populated")
    }

    private func enableReminderIfNeeded(toggle: XCUIElement) {
        guard (toggle.value as? String) != "1" else { return }
        let debugToggleButton = app.buttons["gt.phone.debug.toggleReminder"].firstMatch
        XCTAssertTrue(debugToggleButton.waitForExistence(timeout: 10), "Debug reminder toggle button should exist")
        debugToggleButton.tap()
        allowNotificationPermissionIfNeeded()
        let enabledPredicate = NSPredicate(format: "value == '1'")
        expectation(for: enabledPredicate, evaluatedWith: toggle)
        waitForExpectations(timeout: 10)
    }

    private func allowNotificationPermissionIfNeeded() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        let sheet = springboard.sheets.firstMatch
        let prompt: XCUIElement
        if alert.waitForExistence(timeout: 2) {
            prompt = alert
        } else if sheet.waitForExistence(timeout: 3) {
            prompt = sheet
        } else {
            return
        }

        let preferredLabels = [
            "Allow",
            "Allow Notifications",
            "允许",
            "允许通知"
        ]
        for label in preferredLabels {
            let button = prompt.buttons[label].firstMatch
            if button.exists {
                button.tap()
                return
            }
        }

        if let fallbackButton = prompt.buttons.allElementsBoundByIndex.last {
            fallbackButton.tap()
        }
    }

    private func waitForNotificationPipelineToStabilize() {
        waitForDebugMetric(identifier: "gt.phone.debug.reminderPlanCount", minimumValue: 1, timeout: 10)
    }

    private func waitForDebugMetric(identifier: String, minimumValue: Int, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            refreshNotificationDebugMetrics()
            if notificationDebugValue(identifier: identifier, shouldAssertExistence: false) >= minimumValue {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        XCTFail("\(identifier) did not reach \(minimumValue) within \(timeout)s")
    }

    private func refreshNotificationDebugMetrics() {
        let refreshButton = app.buttons["gt.phone.debug.refreshReminderDiagnostics"].firstMatch
        guard refreshButton.waitForExistence(timeout: 1) else { return }
        refreshButton.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    }

    @discardableResult
    private func openSettingsAndFindReminderToggle() -> XCUIElement {
        let reminderToggle = app.switches["gt.phone.reminderEnabledToggle"].firstMatch
        if reminderToggle.exists {
            return reminderToggle
        }

        let settingsButton = app.buttons["gt.phone.settingsButton"].firstMatch
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 20), "Settings button should appear on the home screen")
        if settingsButton.isHittable {
            settingsButton.tap()
        } else {
            settingsButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        return reminderToggle
    }

    private func notificationDebugValue(identifier: String, shouldAssertExistence: Bool = true) -> Int {
        let metric = app.otherElements[identifier].firstMatch
        if shouldAssertExistence {
            XCTAssertTrue(metric.waitForExistence(timeout: 10), "\(identifier) should exist")
        } else if !metric.waitForExistence(timeout: 1) {
            return -1
        }
        let raw = (metric.value as? String) ?? (metric.label)
        guard let value = Int(raw) else {
            XCTFail("Expected numeric debug value for \(identifier), got \(raw)")
            return -1
        }
        return value
    }
}
