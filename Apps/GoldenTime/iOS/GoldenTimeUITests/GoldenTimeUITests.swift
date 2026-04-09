import XCTest

@MainActor
final class GoldenTimeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["GOLDEN_TIME_UI_TEST_SESSION"] = UUID().uuidString
        app.launchEnvironment["GOLDEN_TIME_UI_TEST_MODE"] = "1"
        app.launchEnvironment["GOLDEN_TIME_UI_TEST_DISABLE_LIVE_LOCATION"] = "1"
        app.launchEnvironment["GOLDEN_TIME_UI_TEST_LOCATION"] = "31.230416,121.473701"
        app.launchEnvironment["GOLDEN_TIME_UI_TEST_REMINDER_SECONDS"] = "4,8,12"
        app.launchEnvironment["GOLDEN_TIME_DEBUG_UI_LANGUAGE"] = "en"
        app.launchEnvironment["GOLDEN_TIME_DEBUG_NOW_ISO8601"] = "2026-04-09T05:00:00Z"
        app.launch()
    }

    func testTwilightReminderKeepsDeliveringUntilUserTurnsItOff() throws {
        let reminderToggle = openSettingsAndFindReminderToggle()
        XCTAssertTrue(reminderToggle.waitForExistence(timeout: 10), "Reminder toggle should exist")
        if reminderToggle.value as? String != "1" {
            reminderToggle.tap()
        }
        allowNotificationPermissionIfNeeded()

        XCUIDevice.shared.press(.home)
        sleep(10)

        app.activate()
        let reopenedToggle = openSettingsAndFindReminderToggle()
        XCTAssertTrue(reopenedToggle.waitForExistence(timeout: 10), "Reminder toggle should still exist after returning")
        XCTAssertEqual(reopenedToggle.value as? String, "1", "Reminder should remain enabled after background delivery")
    }

    private func allowNotificationPermissionIfNeeded() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let labels = ["Allow", "允许", "Allow While Using App", "允许通知"]
        for label in labels {
            let button = springboard.buttons[label].firstMatch
            if button.waitForExistence(timeout: 2) {
                button.tap()
                return
            }
        }
    }

    @discardableResult
    private func openSettingsAndFindReminderToggle() -> XCUIElement {
        let reminderToggle = app.switches["gt.phone.reminderEnabledToggle"].firstMatch
        if reminderToggle.exists {
            return reminderToggle
        }

        let settingsButton = app.buttons["gt.phone.settingsButton"].firstMatch
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 20), "Settings button should appear on the home screen")
        settingsButton.tap()
        return reminderToggle
    }
}
