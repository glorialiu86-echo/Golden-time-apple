import AppIntents

/// Home-screen small slot & watch rectangular slot: blue vs golden (medium shows both).
public enum GTWidgetTwilightFocus: String, AppEnum {
    case blueHour
    case goldenHour

    public static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: LocalizedStringResource(stringLiteral: "Twilight"))
    }

    public static var caseDisplayRepresentations: [GTWidgetTwilightFocus: DisplayRepresentation] {
        [
            .blueHour: DisplayRepresentation(title: LocalizedStringResource(stringLiteral: "Blue hour")),
            .goldenHour: DisplayRepresentation(title: LocalizedStringResource(stringLiteral: "Golden hour")),
        ]
    }
}
