import AppIntents
import GoldenTimeCore
import SwiftUI
import WidgetKit

// MARK: - Intent

struct GoldenTwilightWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { LocalizedStringResource(stringLiteral: "Twilight Compass") }

    static var description: IntentDescription {
        IntentDescription("Next blue and golden twilight from cached location.")
    }

    @Parameter(title: LocalizedStringResource(stringLiteral: "Rectangular widget shows"), default: .blueHour)
    var rectangleSlot: GTWidgetTwilightFocus
}

// MARK: - Timeline

struct GoldenTwilightEntry: TimelineEntry {
    var date: Date
    var lang: GTAppLanguage
    var useClockTimes: Bool
    var phase: PhaseState?
    var blueWindow: (start: Date, end: Date)?
    var goldenWindow: (start: Date, end: Date)?
    var rectangleSlot: GTWidgetTwilightFocus
}

struct GoldenTwilightProvider: AppIntentTimelineProvider {
    typealias Intent = GoldenTwilightWidgetIntent
    typealias Entry = GoldenTwilightEntry

    func recommendations() -> [AppIntentRecommendation<GoldenTwilightWidgetIntent>] {
        let blue = GoldenTwilightWidgetIntent()
        let golden = GoldenTwilightWidgetIntent()
        golden.rectangleSlot = .goldenHour
        return [
            AppIntentRecommendation(intent: blue, description: "Next Blue on the rectangular widget."),
            AppIntentRecommendation(intent: golden, description: "Next Golden on the rectangular widget."),
        ]
    }

    func placeholder(in _: Context) -> GoldenTwilightEntry {
        GoldenTwilightEntry(
            date: Date(),
            lang: .chinese,
            useClockTimes: true,
            phase: nil,
            blueWindow: nil,
            goldenWindow: nil,
            rectangleSlot: .blueHour
        )
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
                useClockTimes: true,
                phase: nil,
                blueWindow: nil,
                goldenWindow: nil,
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
        let phase = engine.currentState(at: now)
        let bWin = engine.blueWindowRelevant(at: now)
        let gWin = engine.goldenWindowRelevant(at: now)
        return GoldenTwilightEntry(
            date: now,
            lang: lang,
            useClockTimes: useClockTimes,
            phase: phase,
            blueWindow: bWin,
            goldenWindow: gWin,
            rectangleSlot: rectangleSlot
        )
    }
}

// MARK: - Metrics (watch accessory rectangular ≈ iPhone small layout, tighter type)

private extension GoldenTimeTwilightCardMetrics {
    static let watchAccessoryRectangular = GoldenTimeTwilightCardMetrics(
        timeFontSize: 24,
        mainSlotHeight: 0,
        countdownLabelFontSize: 12,
        horizontalPadding: 0,
        verticalPadding: 0,
        cornerRadius: 0,
        titleFont: .system(size: 12, weight: .semibold, design: .rounded),
        symbolFont: .system(size: 11, weight: .semibold, design: .rounded)
    )
}

private extension GoldenTwilightEntry {
    func clockStartEnd(blue: Bool) -> (String, String) {
        let window = blue ? blueWindow : goldenWindow
        guard let w = window else { return ("—", "—") }
        let isLive = (blue && phase == .blue) || (!blue && phase == .golden)
        let startStr: String = isLive
            ? GTCopy.liveSegment(lang)
            : GTDateFormatters.twilightInstantLabel(w.start, lang: lang)
        let endStr = GTDateFormatters.twilightInstantLabel(w.end, lang: lang)
        return (startStr, endStr)
    }
}

struct GoldenTwilightWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetContentMargins) private var widgetContentMargins
    var entry: GoldenTwilightEntry

    private var skin: GTPhaseSkin {
        GTPhaseSkin(phase: entry.phase)
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularComplicationMark
        case .accessoryRectangular:
            rectangularBody
        default:
            Image("WidgetComplicationMark")
                .resizable()
                .scaledToFit()
                .padding(7)
                .containerBackground(Color.clear, for: .widget)
        }
    }

    @ViewBuilder
    private var rectangularBody: some View {
        let blue = entry.rectangleSlot == .blueHour
        let (cs, ce) = entry.clockStartEnd(blue: blue)
        GoldenTimeTwilightWindowCard(
            skin: skin,
            title: blue ? GTCopy.widgetTwilightTitleBlue(entry.lang) : GTCopy.widgetTwilightTitleGolden(entry.lang),
            systemImage: blue ? "moon.stars.fill" : "sun.horizon.fill",
            blue: blue,
            useClockTimes: entry.useClockTimes,
            window: blue ? entry.blueWindow : entry.goldenWindow,
            clockStart: cs,
            clockEnd: ce,
            now: entry.date,
            lang: entry.lang,
            metrics: .watchAccessoryRectangular,
            showsCardFill: false,
            timeStyle: .widgetStacked,
            widgetEdgeAlignment: .leading
        )
        .padding(widgetContentMargins)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) {
            GTTwilightWidgetChrome.singleContainerBackground(skin: skin, blue: blue)
        }
    }

    private var circularComplicationMark: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let stroke = max(1.8, size * 0.07)
            let outerRadius = size * 0.24
            let innerRadius = size * 0.12
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height * 0.58)
            let foreground = GTWidgetSurface.accessoryPrimary

            ZStack {
                Circle()
                    .stroke(foreground.opacity(0.92), lineWidth: stroke)

                Path { path in
                    path.addArc(
                        center: center,
                        radius: outerRadius,
                        startAngle: .degrees(180),
                        endAngle: .degrees(0),
                        clockwise: false
                    )
                }
                .stroke(foreground, style: StrokeStyle(lineWidth: stroke, lineCap: .round))

                Path { path in
                    path.addArc(
                        center: center,
                        radius: innerRadius,
                        startAngle: .degrees(180),
                        endAngle: .degrees(0),
                        clockwise: false
                    )
                }
                .stroke(foreground.opacity(0.88), style: StrokeStyle(lineWidth: stroke, lineCap: .round))

                Capsule()
                    .fill(foreground)
                    .frame(width: size * 0.76, height: stroke)
                    .position(x: proxy.size.width / 2, y: center.y)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(5)
        .containerBackground(Color.clear, for: .widget)
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
        .description("Circular: app mark only. Rectangular: same twilight card as iPhone small (pick Next Blue or Next Golden). Cached location — open the app on iPhone once to refresh.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}
