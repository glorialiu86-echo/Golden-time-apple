import GoldenTimeCore
import SwiftUI

/// Phase-driven chrome shared by iPhone and Apple Watch (not system Light/Dark).
public enum GTPhaseSkin: Equatable {
    case day
    case night
    case blueHour
    case goldenHour

    public init(phase: PhaseState?) {
        switch phase {
        case .night:
            self = .night
        case .blue:
            self = .blueHour
        case .golden:
            self = .goldenHour
        case .day, nil:
            self = .day
        }
    }

    public var upper: Color {
        switch self {
        case .day:
            Color(red: 0.93, green: 0.95, blue: 0.99)
        case .night:
            GTAppIconPalette.nightShellUpper
        case .blueHour:
            GTAppIconPalette.deepNavy
        case .goldenHour:
            Color(red: 46 / 255, green: 26 / 255, blue: 14 / 255)
        }
    }

    public var lower: Color {
        switch self {
        case .day:
            Color(red: 0.82, green: 0.88, blue: 0.96)
        case .night:
            GTAppIconPalette.nightShellLower
        case .blueHour:
            Color(red: 32 / 255, green: 52 / 255, blue: 88 / 255)
        case .goldenHour:
            GTAppIconPalette.sunCore
        }
    }

    public var ink: Color {
        switch self {
        case .day:
            Color(red: 0.12, green: 0.14, blue: 0.20)
        case .night, .blueHour, .goldenHour:
            Color.white.opacity(0.94)
        }
    }

    public var muted: Color {
        ink.opacity(skinMutedOpacity)
    }

    /// Secondary labels on the **full-screen phase gradient** (coordinates, date line, status, compass captions — not list cells, not twilight cards).
    public var chromeSecondaryForeground: Color {
        switch self {
        case .day:
            ink.opacity(0.52)
        case .night, .blueHour:
            Color.white.opacity(0.88)
        case .goldenHour:
            Color.white.opacity(0.92)
        }
    }

    /// Primary text on a twilight **card** body (times, titles). Do not use `ink` here: it stays white on golden-hour sun gradients.
    public func twilightCardPrimaryForeground(blueCard: Bool) -> Color {
        switch self {
        case .day:
            Color(red: 0.12, green: 0.14, blue: 0.20)
        case .night, .blueHour:
            Color.white.opacity(0.94)
        case .goldenHour:
            blueCard ? Color.white.opacity(0.96) : Color(red: 0.14, green: 0.09, blue: 0.055)
        }
    }

    /// Secondary text and symbols on a twilight **card** (labels, arrows, icons).
    public func twilightCardSecondaryForeground(blueCard: Bool) -> Color {
        switch self {
        case .day:
            Color(red: 0.32, green: 0.36, blue: 0.44)
        case .night, .blueHour:
            Color.white.opacity(0.76)
        case .goldenHour:
            blueCard ? Color.white.opacity(0.80) : Color(red: 0.40, green: 0.26, blue: 0.14)
        }
    }

    /// Alias for `twilightCardSecondaryForeground` (muted accents on the card gradient).
    public func twilightCardMuted(blueCard: Bool) -> Color {
        twilightCardSecondaryForeground(blueCard: blueCard)
    }

    /// Secondary text on **plain white** `List` rows. `muted` follows `ink` and is wrong on white cells when `ink` is light (golden / night chrome).
    public var settingsCellSecondaryForeground: Color {
        switch self {
        case .day:
            ink.opacity(0.52)
        case .night, .blueHour, .goldenHour:
            Color(red: 0.38, green: 0.38, blue: 0.42)
        }
    }

    /// Section titles sit on the phase gradient (`scrollContentBackground(.hidden)`); must stay legible on golden orange and dark brown.
    public var settingsSectionHeaderForeground: Color {
        switch self {
        case .day:
            ink.opacity(0.48)
        case .night, .blueHour, .goldenHour:
            Color.white.opacity(0.96)
        }
    }

    /// Hairline shadow so light headers stay readable on bright golden-hour lower gradient.
    public var settingsSectionHeaderShadowColor: Color {
        switch self {
        case .day:
            .clear
        case .night, .blueHour:
            Color.black.opacity(0.4)
        case .goldenHour:
            Color.black.opacity(0.55)
        }
    }

    private var skinMutedOpacity: CGFloat {
        switch self {
        case .day: 0.52
        case .night: 0.55
        case .blueHour: 0.58
        case .goldenHour: 0.55
        }
    }

    public var panelStroke: Color {
        switch self {
        case .day:
            Color.black.opacity(0.08)
        case .night:
            Color.white.opacity(0.14)
        case .blueHour:
            Color.cyan.opacity(0.28)
        case .goldenHour:
            GTAppIconPalette.sunCore.opacity(0.42)
        }
    }

    public var chromeGradient: [Color] {
        [upper.opacity(0.42), lower.opacity(0.42)]
    }

    public var isLightChrome: Bool {
        switch self {
        case .day: return true
        case .night, .blueHour, .goldenHour: return false
        }
    }

    /// Translucent compass wedge for “sun above horizon” span (between blue/golden clips).
    public var compassDayDiskTint: Color {
        switch self {
        case .day:
            Color(red: 0.98, green: 0.86, blue: 0.42)
        case .night, .blueHour:
            Color(red: 0.95, green: 0.78, blue: 0.38)
        case .goldenHour:
            Color(red: 1.0, green: 0.9, blue: 0.48)
        }
    }

    /// Translucent wedge for the complementary night span on the dial (sun below horizon, outside blue/golden clips).
    /// On dark shells this is a **low-chroma slate** so it reads as “night sky”, not the saturated blue-hour arcs.
    public var compassNightDiskTint: Color {
        switch self {
        case .day:
            Color(red: 0.36, green: 0.48, blue: 0.82)
        case .night, .blueHour:
            Color(red: 0.21, green: 0.23, blue: 0.29)
        case .goldenHour:
            Color(red: 0.22, green: 0.21, blue: 0.30)
        }
    }

    public func twilightCardGradient(blue: Bool) -> [Color] {
        switch self {
        case .day:
            return blue
                ? [Color(red: 0.7, green: 0.82, blue: 0.99), Color(red: 0.48, green: 0.66, blue: 0.93)]
                : [GTAppIconPalette.sunGlow, GTAppIconPalette.sunCore]
        case .night:
            return blue
                ? [
                    Color(red: 0.10, green: 0.40, blue: 0.74),
                    Color(red: 0.22, green: 0.58, blue: 0.92)
                ]
                : [GTAppIconPalette.sunDeep, GTAppIconPalette.sunCore]
        case .blueHour:
            return blue
                ? [
                    Color(red: 0.14, green: 0.36, blue: 0.68),
                    Color(red: 0.28, green: 0.52, blue: 0.95)
                ]
                : [Color(red: 0.48, green: 0.28, blue: 0.14), GTAppIconPalette.sunCore]
        case .goldenHour:
            return blue
                ? [Color(red: 0.22, green: 0.34, blue: 0.52), Color(red: 0.32, green: 0.5, blue: 0.76)]
                : [
                    Color(red: 236 / 255, green: 142 / 255, blue: 22 / 255),
                    Color(red: 210 / 255, green: 128 / 255, blue: 48 / 255),
                ]
        }
    }
}
