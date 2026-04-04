import Foundation

/// When `GOLDEN_TIME_DEBUG_NOW` is set (e.g. from `simctl launch` via `SIMCTL_CHILD_GOLDEN_TIME_DEBUG_NOW`),
/// returns that instant; otherwise returns the system wall clock (`Date()`).
enum GTPreviewClock {
    private static let envKey = "GOLDEN_TIME_DEBUG_NOW"

    static func now(wallClock: Date = Date()) -> Date {
        guard let raw = ProcessInfo.processInfo.environment[envKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else { return wallClock }

        let formatters: [ISO8601DateFormatter] = {
            let a = ISO8601DateFormatter()
            a.formatOptions = [.withInternetDateTime, .withColonSeparatorInTime, .withTimeZone]
            let b = ISO8601DateFormatter()
            b.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime, .withTimeZone]
            return [a, b]
        }()

        for f in formatters {
            if let d = f.date(from: raw) { return d }
        }
        return wallClock
    }
}
