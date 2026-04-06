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
                    .strokeBorder(skin.panelStroke, lineWidth: 1)
            )
    }
}
