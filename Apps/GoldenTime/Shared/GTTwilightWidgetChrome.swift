import GoldenTimeCore
import SwiftUI
import WidgetKit

/// Full-bleed twilight gradient used by iPhone small / watch rectangular widgets.
public enum GTTwilightWidgetChrome {
    public static func singleContainerBackground(skin: GTPhaseSkin, blue: Bool) -> some View {
        let gradient = LinearGradient(
            colors: skin.twilightCardGradient(blue: blue),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        return ContainerRelativeShape()
            .fill(gradient)
            .overlay(
                ContainerRelativeShape()
                    .strokeBorder(widgetCardStroke(skin: skin, blue: blue), lineWidth: 1)
            )
    }

    private static func widgetCardStroke(skin: GTPhaseSkin, blue: Bool) -> Color {
        if blue {
            switch skin {
            case .day:
                return Color(red: 72 / 255, green: 154 / 255, blue: 245 / 255).opacity(0.34)
            case .night, .blueHour, .goldenHour:
                return Color.cyan.opacity(0.28)
            }
        }

        switch skin {
        case .day:
            return GTAppIconPalette.sunCore.opacity(0.34)
        case .night, .blueHour, .goldenHour:
            return GTAppIconPalette.sunCore.opacity(0.42)
        }
    }
}
