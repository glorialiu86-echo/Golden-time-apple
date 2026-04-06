import AppIntents
import GoldenTimeCore
import SwiftUI
import WidgetKit

// MARK: - Timeline

struct GoldenTwilightIOSEntry: TimelineEntry {
    var date: Date
    var lang: GTAppLanguage
    var blueLine: String
    var goldenLine: String
    /// Small widget only; medium ignores and shows both.
    var smallSlot: GTWidgetTwilightFocus
}

struct GoldenTwilightIOSWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { LocalizedStringResource(stringLiteral: "Twilight Compass") }

    static var description: IntentDescription {
        IntentDescription("Next blue hour and golden hour from cached location.")
    }

    @Parameter(title: "Small widget shows", default: .blueHour)
    var smallSlot: GTWidgetTwilightFocus
}

struct GoldenTwilightIOSProvider: AppIntentTimelineProvider {
    typealias Intent = GoldenTwilightIOSWidgetIntent
    typealias Entry = GoldenTwilightIOSEntry

    func recommendations() -> [AppIntentRecommendation<GoldenTwilightIOSWidgetIntent>] {
        let blue = GoldenTwilightIOSWidgetIntent()
        var golden = GoldenTwilightIOSWidgetIntent()
        golden.smallSlot = .goldenHour
        return [
            AppIntentRecommendation(intent: blue, description: "Blue hour on the small widget."),
            AppIntentRecommendation(intent: golden, description: "Golden hour on the small widget."),
        ]
    }

    func placeholder(in _: Context) -> GoldenTwilightIOSEntry {
        GoldenTwilightIOSEntry(
            date: Date(),
            lang: .chinese,
            blueLine: "—",
            goldenLine: "—",
            smallSlot: .blueHour
        )
    }

    func snapshot(for configuration: GoldenTwilightIOSWidgetIntent, in _: Context) async -> GoldenTwilightIOSEntry {
        makeEntry(smallSlot: configuration.smallSlot)
    }

    func timeline(for configuration: GoldenTwilightIOSWidgetIntent, in _: Context) async -> Timeline<GoldenTwilightIOSEntry> {
        let entry = makeEntry(smallSlot: configuration.smallSlot)
        let refresh = Calendar.current.date(byAdding: .minute, value: 15, to: entry.date) ?? entry.date.addingTimeInterval(900)
        return Timeline(entries: [entry], policy: .after(refresh))
    }

    private func makeEntry(smallSlot: GTWidgetTwilightFocus) -> GoldenTwilightIOSEntry {
        let suite = GTAppGroup.shared
        GTAppGroup.materializeDefaultPreferencesIfNeeded()
        let lang = GTAppLanguage.widgetLanguageIOS(suite: suite)
        let now = Date()
        guard suite.object(forKey: GoldenTimeLocationCache.latitudeKey) != nil else {
            return GoldenTwilightIOSEntry(date: now, lang: lang, blueLine: "—", goldenLine: "—", smallSlot: smallSlot)
        }
        let lat = suite.double(forKey: GoldenTimeLocationCache.latitudeKey)
        let lon = suite.double(forKey: GoldenTimeLocationCache.longitudeKey)
        let ts = suite.double(forKey: GoldenTimeLocationCache.timestampKey)
        let fix = LocationFix(latitude: lat, longitude: lon, timestamp: Date(timeIntervalSince1970: ts))
        let engine = GoldenTimeEngine()
        engine.update(now: now, fix: fix)
        let modeRaw =
            suite.string(forKey: GTTwilightDisplayMode.storageKey)
            ?? UserDefaults.standard.string(forKey: GTTwilightDisplayMode.storageKey)
        let useClockTimes =
            (modeRaw ?? GTTwilightDisplayMode.clockTimes.rawValue) != GTTwilightDisplayMode.countdown.rawValue
        func line(for window: (start: Date, end: Date)?) -> String {
            guard let window else { return "—" }
            if useClockTimes {
                return GTDateFormatters.twilightInstantLabel(window.start, lang: lang)
            }
            return GTTwilightCountdownLine.text(from: now, to: window.start, lang: lang)
                ?? GTCopy.countdownLessThanOneMinute(lang)
        }
        let b = line(for: engine.nextBlueWindow(after: now))
        let g = line(for: engine.nextGoldenWindow(after: now))
        return GoldenTwilightIOSEntry(date: now, lang: lang, blueLine: b, goldenLine: g, smallSlot: smallSlot)
    }
}

// MARK: - Module-style cards (aligned with `GoldenTimeTwilightWindowCard` / `GTPhaseSkin.day`)

private struct TwilightIOSHomeModuleCard: View {
    var blue: Bool
    var title: String
    var systemImage: String
    var valueLine: String
    var cornerRadius: CGFloat

    var body: some View {
        let skin = GTPhaseSkin.day
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(skin.twilightCardSecondaryForeground(blueCard: blue))
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(skin.twilightCardPrimaryForeground(blueCard: blue))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Text(valueLine)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(skin.twilightCardPrimaryForeground(blueCard: blue))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: skin.twilightCardGradient(blue: blue),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(skin.panelStroke, lineWidth: 1)
                )
        )
    }
}

private extension GoldenTwilightIOSEntry {
    func title(blue: Bool) -> String {
        blue ? GTCopy.blueHourTitle(lang) : GTCopy.goldenHourTitle(lang)
    }

    func symbol(blue: Bool) -> String {
        blue ? "moon.stars.fill" : "sun.horizon.fill"
    }

    func line(blue: Bool) -> String {
        blue ? blueLine : goldenLine
    }
}

struct GoldenTwilightIOSWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: GoldenTwilightIOSEntry

    var body: some View {
        switch family {
        case .systemSmall:
            smallBody
                .containerBackground(homeWidgetChromeBackground, for: .widget)
        case .systemMedium:
            mediumBody
                .containerBackground(homeWidgetChromeBackground, for: .widget)
        default:
            mediumBody
                .containerBackground(homeWidgetChromeBackground, for: .widget)
        }
    }

    private var homeWidgetChromeBackground: Color {
        Color(red: 14 / 255, green: 15 / 255, blue: 18 / 255)
    }

    private var smallBody: some View {
        let blue = entry.smallSlot == .blueHour
        return TwilightIOSHomeModuleCard(
            blue: blue,
            title: entry.title(blue: blue),
            systemImage: entry.symbol(blue: blue),
            valueLine: entry.line(blue: blue),
            cornerRadius: 18
        )
        .padding(10)
    }

    private var mediumBody: some View {
        HStack(spacing: 8) {
            TwilightIOSHomeModuleCard(
                blue: true,
                title: entry.title(blue: true),
                systemImage: entry.symbol(blue: true),
                valueLine: entry.line(blue: true),
                cornerRadius: 16
            )
            TwilightIOSHomeModuleCard(
                blue: false,
                title: entry.title(blue: false),
                systemImage: entry.symbol(blue: false),
                valueLine: entry.line(blue: false),
                cornerRadius: 16
            )
        }
        .padding(10)
    }
}

struct GoldenTwilightIOSWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: GTIOWidgetKind.twilight, intent: GoldenTwilightIOSWidgetIntent.self, provider: GoldenTwilightIOSProvider()) {
            entry in
            GoldenTwilightIOSWidgetView(entry: entry)
        }
        .configurationDisplayName(GTCopy.systemAppDisplayName())
        .description("Small: pick blue or golden. Medium: both side by side. Uses cached location — open the app once to refresh GPS.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
