import Foundation

public struct LocationFix: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let timestamp: Date

    public init(latitude: Double, longitude: Double, timestamp: Date) {
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
    }
}

public enum PhaseEventType: String, CaseIterable, Sendable {
    case blueStart = "BLUE_START"
    case blueEnd = "BLUE_END"
    case goldenStart = "GOLDEN_START"
    case goldenEnd = "GOLDEN_END"
}

public struct PhaseEvent: Equatable, Sendable {
    public let date: Date
    public let type: PhaseEventType

    public init(date: Date, type: PhaseEventType) {
        self.date = date
        self.type = type
    }
}

public enum PhaseState: String, CaseIterable, Sendable {
    case night = "NIGHT"
    case blue = "BLUE"
    case golden = "GOLDEN"
    case day = "DAY"
}

public struct PhaseTransition: Equatable, Sendable {
    public let date: Date
    public let state: PhaseState

    public init(date: Date, state: PhaseState) {
        self.date = date
        self.state = state
    }
}

/// Apparent solar rise & set for the observer’s **local calendar day** of `now`, with azimuths at those instants.
/// All values are computed on-device from the same solar model as twilight phases (no network).
public struct SunHorizonGeometry: Equatable, Sendable {
    public let sunrise: Date
    public let sunset: Date
    /// Clockwise from **true north**, 0…360° (map bearing).
    public let sunriseAzimuthDegrees: Double
    /// Clockwise from **true north**, 0…360°.
    public let sunsetAzimuthDegrees: Double

    public init(sunrise: Date, sunset: Date, sunriseAzimuthDegrees: Double, sunsetAzimuthDegrees: Double) {
        self.sunrise = sunrise
        self.sunset = sunset
        self.sunriseAzimuthDegrees = sunriseAzimuthDegrees
        self.sunsetAzimuthDegrees = sunsetAzimuthDegrees
    }
}

public struct GoldenTimeSnapshot: Equatable, Sendable {
    public let hasFix: Bool
    public let nextBlueStart: Date?
    public let nextGoldenStart: Date?
    public let todayHasBlueStart: Bool
    public let todayHasGoldenStart: Bool

    public init(
        hasFix: Bool,
        nextBlueStart: Date?,
        nextGoldenStart: Date?,
        todayHasBlueStart: Bool,
        todayHasGoldenStart: Bool
    ) {
        self.hasFix = hasFix
        self.nextBlueStart = nextBlueStart
        self.nextGoldenStart = nextGoldenStart
        self.todayHasBlueStart = todayHasBlueStart
        self.todayHasGoldenStart = todayHasGoldenStart
    }
}
