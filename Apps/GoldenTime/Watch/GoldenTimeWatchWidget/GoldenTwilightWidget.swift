import AppIntents
import GoldenTimeCore
import SwiftUI
import WidgetKit

// MARK: - Intent

struct GoldenTwilightWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { LocalizedStringResource(stringLiteral: "Twilight Compass") }

    static var description: IntentDescription {
        IntentDescription("Next blue hour and golden hour from cached location.")
    }

    @Parameter(title: "Rectangle shows", default: .blueHour)
    var rectangleSlot: GTWidgetTwilightFocus
}

// MARK: - Timeline

struct GoldenTwilightEntry: TimelineEntry {
    var date: Date
    var lang: GTAppLanguage
    var blueLine: String
    var goldenLine: String
    var rectangleSlot: GTWidgetTwilightFocus
}

struct GoldenTwilightProvider: AppIntentTimelineProvider {
    typealias Intent = GoldenTwilightWidgetIntent
    typealias Entry = GoldenTwilightEntry

    func recommendations() -> [AppIntentRecommendation<GoldenTwilightWidgetIntent>] {
        let blue = GoldenTwilightWidgetIntent()
        var golden = GoldenTwilightWidgetIntent()
        golden.rectangleSlot = .goldenHour
        return [
            AppIntentRecommendation(intent: blue, description: "Blue hour on the rectangular widget."),
            AppIntentRecommendation(intent: golden, description: "Golden hour on the rectangular widget."),
        ]
    }

    func placeholder(in _: Context) -> GoldenTwilightEntry {
        GoldenTwilightEntry(date: Date(), lang: .chinese, blueLine: "—", goldenLine: "—", rectangleSlot: .blueHour)
    }

    func snapshot(for configuration: GoldenTwilightWidgetIntent, in _: Context) async -> GoldenTwilightEntry {
        makeEntry(rectangleSlot: configuration.rectangleSlot)
    }

    func timeline(for configuration: GoldenTwilightWidgetIntent, in _: Context) async -> Timeline<GoldenTwilightEntry> {
        let entry = makeEntry(rectangleSlot: configuration.rectangleSlot)
        let refresh = Calendar.current.date(byAdding: .minute, value: 15, to: entry.date) ?? entry.date.addingTimeInterval(900)
        return Timeline(entries: [entry], policy: .after(refresh))
    }

    private func makeEntry(rectangleSlot: GTWidgetTwilightFocus) -> GoldenTwilightEntry {
        let suite = GTAppGroup.shared
        GTAppGroup.materializeDefaultPreferencesIfNeeded()
        let lang = GTAppLanguage.widgetLanguageWatch(suite: suite)
        let now = Date()
        guard suite.object(forKey: GoldenTimeLocationCache.latitudeKey) != nil else {
            return GoldenTwilightEntry(
                date: now,
                lang: lang,
                blueLine: "—",
                goldenLine: "—",
                rectangleSlot: rectangleSlot
            )
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
        return GoldenTwilightEntry(date: now, lang: lang, blueLine: b, goldenLine: g, rectangleSlot: rectangleSlot)
    }
}

// MARK: - Views

private struct TwilightWatchAccessoryModule: View {
    var blue: Bool
    var title: String
    var systemImage: String
    var valueLine: String

    var body: some View {
        let skin = GTPhaseSkin.day
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: skin.twilightCardGradient(blue: blue),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(skin.panelStroke, lineWidth: 1)
                )
                .frame(width: 36, height: 36)
                .overlay {
                    Image(systemName: systemImage)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(skin.twilightCardPrimaryForeground(blueCard: blue))
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(skin.twilightCardSecondaryForeground(blueCard: blue))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(valueLine)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(skin.twilightCardPrimaryForeground(blueCard: blue))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }
}

private extension GoldenTwilightEntry {
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

struct GoldenTwilightWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: GoldenTwilightEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image("WidgetComplicationMark")
                    .resizable()
                    .scaledToFit()
                    .padding(7)
            }
            .containerBackground(Color.clear, for: .widget)
        case .accessoryRectangular:
            let blue = entry.rectangleSlot == .blueHour
            TwilightWatchAccessoryModule(
                blue: blue,
                title: entry.title(blue: blue),
                systemImage: entry.symbol(blue: blue),
                valueLine: entry.line(blue: blue)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .containerBackground(Color.clear, for: .widget)
        default:
            ZStack {
                AccessoryWidgetBackground()
                Image("WidgetComplicationMark")
                    .resizable()
                    .scaledToFit()
                    .padding(7)
            }
            .containerBackground(Color.clear, for: .widget)
        }
    }
}

struct GoldenTwilightWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "time.golden.GoldenHourCompass.twilight",
            intent: GoldenTwilightWidgetIntent.self,
            provider: GoldenTwilightProvider()
        ) { entry in
            GoldenTwilightWidgetView(entry: entry)
        }
        .configurationDisplayName(GTCopy.systemAppDisplayName())
        .description("Circular: app mark. Rectangle: pick blue or golden. Uses cached location.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}
