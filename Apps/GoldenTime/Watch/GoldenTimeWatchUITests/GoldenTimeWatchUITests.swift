import XCTest

/// UI tests run on watchOS Simulator; host app is `GoldenTimeWatch` (bundle `time.golden.GoldenHourCompass.watchkitapp`).
final class GoldenTimeWatchUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func testTwilightPageVisible() throws {
        let twilight = app.scrollViews["gt.watch.twilightPage"].firstMatch
        XCTAssertTrue(twilight.waitForExistence(timeout: 20), "Twilight TabView page should be on screen")
    }

    func testSwipeToCompassPage() throws {
        let twilight = app.scrollViews["gt.watch.twilightPage"].firstMatch
        XCTAssertTrue(twilight.waitForExistence(timeout: 20), "Twilight page should appear first")

        app.swipeUp()

        let compass = app.otherElements["gt.watch.compassPage"].firstMatch
        XCTAssertTrue(compass.waitForExistence(timeout: 15), "Compass page should appear after vertical paging")
    }
}
