import AppIntents

/// Home-screen small slot & watch rectangular slot: blue vs golden (medium shows both).
public enum GTWidgetTwilightFocus: String, AppEnum {
    case blueHour
    case goldenHour

    public static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: LocalizedStringResource(stringLiteral: "Twilight"))
    }

    /// Picker labels aligned with widget headers (EN omits “hour”).
    public static var caseDisplayRepresentations: [GTWidgetTwilightFocus: DisplayRepresentation] {
        [
            .blueHour: DisplayRepresentation(title: LocalizedStringResource(stringLiteral: "Next Blue")),
            .goldenHour: DisplayRepresentation(title: LocalizedStringResource(stringLiteral: "Next Golden")),
        ]
    }
}
