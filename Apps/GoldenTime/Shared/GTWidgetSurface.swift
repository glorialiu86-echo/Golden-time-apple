import SwiftUI

/// Fixed sRGB for WidgetKit surfaces — never `Color.primary` / `.foregroundStyle(.secondary)` (system Light/Dark).
public enum GTWidgetSurface {
    /// iOS home-screen widget tile (replaces `.fill.tertiary`, which flips with system appearance).
    public static let homeBackground = Color(red: 242 / 255, green: 242 / 255, blue: 246 / 255)

    public static let homeTitleMuted = Color(red: 100 / 255, green: 104 / 255, blue: 112 / 255)
    public static let homeBody = Color(red: 28 / 255, green: 30 / 255, blue: 36 / 255)
    public static let homeFootnote = Color(red: 118 / 255, green: 122 / 255, blue: 128 / 255)

    /// Lock screen complications & watch face: system backdrop is dark; fixed light glyphs.
    public static let accessoryPrimary = Color.white
    public static let accessorySecondary = Color.white.opacity(0.82)
}
