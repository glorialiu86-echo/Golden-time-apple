import SwiftUI

/// Key colors sampled from `Shared/Assets.xcassets/AppIcon.appiconset` (sunrise / horizon / water).
enum GTAppIconPalette {
    static let deepNavy = Color(red: 11 / 255, green: 30 / 255, blue: 59 / 255) // #0B1E3B
    static let reflectionBlue = Color(red: 26 / 255, green: 58 / 255, blue: 95 / 255) // #1A3A5F

    /// **Night page chrome only** — neutral slate (slightly warm) so blue-hour **cards** don’t sit on the same hue as the shell.
    static let nightShellUpper = Color(red: 20 / 255, green: 18 / 255, blue: 24 / 255)
    static let nightShellLower = Color(red: 32 / 255, green: 29 / 255, blue: 38 / 255)

    static let sunGlow = Color(red: 1, green: 193 / 255, blue: 94 / 255) // #FFC15E
    static let sunCore = Color(red: 249 / 255, green: 161 / 255, blue: 27 / 255) // #F9A11B
    static let sunDeep = Color(red: 185 / 255, green: 95 / 255, blue: 10 / 255) // under core, still on-icon
}
