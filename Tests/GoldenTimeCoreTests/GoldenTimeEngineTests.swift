import Foundation
import Testing
@testable import GoldenTimeCore

struct GoldenTimeEngineTests {
    @Test
    func snapshotWithoutFixReturnsEmptyState() {
        let engine = GoldenTimeEngine(timeZone: TimeZone(secondsFromGMT: 0)!)
        let now = Date(timeIntervalSince1970: 1_773_312_000)

        let snapshot = engine.snapshot(at: now)

        #expect(snapshot.hasFix == false)
        #expect(snapshot.nextBlueStart == nil)
        #expect(snapshot.nextGoldenStart == nil)
        #expect(snapshot.todayHasBlueStart == false)
        #expect(snapshot.todayHasGoldenStart == false)
        #expect(engine.currentState(at: now) == nil)
    }

    @Test
    func updateWithFixProducesUsableSnapshot() {
        let engine = GoldenTimeEngine(timeZone: TimeZone(secondsFromGMT: 0)!)
        let now = Date(timeIntervalSince1970: 1_773_312_000)
        let fix = LocationFix(
            latitude: 37.7749,
            longitude: -122.4194,
            timestamp: now
        )

        engine.update(now: now, fix: fix)
        let snapshot = engine.snapshot(at: now)

        #expect(snapshot.hasFix)
        #expect(snapshot.nextBlueStart != nil)
        #expect(snapshot.nextGoldenStart != nil)
        #expect(engine.currentState(at: now) != nil)

        if let blue = engine.nextBlueWindow(after: now) {
            #expect(blue.start < blue.end)
        }
        if let gold = engine.nextGoldenWindow(after: now) {
            #expect(gold.start < gold.end)
        }
    }

    @Test
    func dawnBlueWindowStartsBeforeGoldenWhenEngineTZMatchesCoordinates() {
        // Civil TZ aligned with SF; before dawn, next blue segment should start before next golden (Garmin morning order).
        let la = TimeZone(identifier: "America/Los_Angeles")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = la
        let nightBeforeDawn = cal.date(from: DateComponents(year: 2026, month: 4, day: 4, hour: 1, minute: 14))!
        let fix = LocationFix(latitude: 37.7749, longitude: -122.4194, timestamp: nightBeforeDawn)

        let engine = GoldenTimeEngine(timeZone: la)
        engine.update(now: nightBeforeDawn, fix: fix)

        let blue = engine.blueWindowRelevant(at: nightBeforeDawn)
        let golden = engine.goldenWindowRelevant(at: nightBeforeDawn)
        #expect(blue != nil && golden != nil)
        guard let blue, let golden else { return }
        #expect(blue.start < golden.start)
    }

    @Test
    func clearingFixResetsSnapshot() {
        let engine = GoldenTimeEngine(timeZone: TimeZone(secondsFromGMT: 0)!)
        let now = Date(timeIntervalSince1970: 1_773_312_000)
        let fix = LocationFix(
            latitude: 0.0,
            longitude: 0.0,
            timestamp: now
        )

        engine.update(now: now, fix: fix)
        engine.update(now: now, fix: nil)

        let snapshot = engine.snapshot(at: now)

        #expect(snapshot.hasFix == false)
        #expect(snapshot.nextBlueStart == nil)
        #expect(snapshot.nextGoldenStart == nil)
    }
}
