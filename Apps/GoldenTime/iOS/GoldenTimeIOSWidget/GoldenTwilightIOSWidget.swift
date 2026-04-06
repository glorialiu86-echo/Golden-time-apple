import AppIntents
import GoldenTimeCore
import SwiftUI
import WidgetKit

// MARK: - Timeline

struct GoldenTwilightIOSEntry: TimelineEntry {
    var date: Date
    var lang: GTAppLanguage
    var useClockTimes: Bool
    var phase: PhaseState?
    var blueWindow: (start: Date, end: Date)?
    var goldenWindow: (start: Date, end: Date)?
    /// Same ordering as iPhone `mainColumn` (`stackBlueFirst`).
    var blueTwilightFirst: Bool
    /// Small widget only; medium shows both.
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
        let golden = GoldenTwilightIOSWidgetIntent()
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
            useClockTimes: true,
            phase: nil,
            blueWindow: nil,
            goldenWindow: nil,
            blueTwilightFirst: true,
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
            return GoldenTwilightIOSEntry(
                date: now,
                lang: lang,
                useClockTimes: true,
                phase: nil,
                blueWindow: nil,
                goldenWindow: nil,
                blueTwilightFirst: true,
                smallSlot: smallSlot
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
        let blueFirst = stackBlueFirst(phase: phase, blue: bWin, golden: gWin)
        return GoldenTwilightIOSEntry(
            date: now,
            lang: lang,
            useClockTimes: useClockTimes,
            phase: phase,
            blueWindow: bWin,
            goldenWindow: gWin,
            blueTwilightFirst: blueFirst,
            smallSlot: smallSlot
        )
    }

    /// Mirrors `GoldenTimePhoneViewModel.stackBlueFirst`.
    private func stackBlueFirst(
        phase: PhaseState?,
        blue: (start: Date, end: Date)?,
        golden: (start: Date, end: Date)?
    ) -> Bool {
        switch phase {
        case .blue:
            return true
        case .golden:
            return false
        case .day, .night, nil:
            guard let b = blue else { return false }
            guard let g = golden else { return true }
            return b.start < g.start
        }
    }
}

// MARK: - Metrics (widget targets; same structure as in-app `GoldenTimeTwilightWindowCard`)

private extension GoldenTimeTwilightCardMetrics {
    /// Insets come from `@Environment(\.widgetContentMargins)` on the widget view; keep card padding at 0.
    static let iosWidgetSmall = GoldenTimeTwilightCardMetrics(
        timeFontSize: 38,
        mainSlotHeight: 0,
        countdownLabelFontSize: 17,
        horizontalPadding: 0,
        verticalPadding: 0,
        cornerRadius: 0,
        titleFont: .subheadline.weight(.semibold),
        symbolFont: .callout.weight(.semibold)
    )

    static let iosWidgetMediumHalf = GoldenTimeTwilightCardMetrics(
        timeFontSize: 29,
        mainSlotHeight: 0,
        countdownLabelFontSize: 14,
        horizontalPadding: 0,
        verticalPadding: 0,
        cornerRadius: 0,
        titleFont: .caption.weight(.semibold),
        symbolFont: .caption.weight(.semibold)
    )
}

/// Shorter labels (“下一次金调” / “下一次蓝调”) — same copy as reminder settings; widget-only use.
private func iosWidgetTwilightTitle(blue: Bool, lang: GTAppLanguage) -> String {
    blue ? GTCopy.settingsReminderTargetBlue(lang) : GTCopy.settingsReminderTargetGolden(lang)
}

private extension GoldenTwilightIOSEntry {
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

struct GoldenTwilightIOSWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetContentMargins) private var widgetContentMargins
    var entry: GoldenTwilightIOSEntry

    private var skin: GTPhaseSkin {
        GTPhaseSkin(phase: entry.phase)
    }

    var body: some View {
        switch family {
        case .systemSmall:
            smallBody
        case .systemMedium:
            mediumBody
        default:
            mediumBody
        }
    }

    @ViewBuilder
    private var smallBody: some View {
        let blue = entry.smallSlot == .blueHour
        let (cs, ce) = entry.clockStartEnd(blue: blue)
        GoldenTimeTwilightWindowCard(
            skin: skin,
            title: iosWidgetTwilightTitle(blue: blue, lang: entry.lang),
            systemImage: blue ? "moon.stars.fill" : "sun.horizon.fill",
            blue: blue,
            useClockTimes: entry.useClockTimes,
            window: blue ? entry.blueWindow : entry.goldenWindow,
            clockStart: cs,
            clockEnd: ce,
            now: entry.date,
            lang: entry.lang,
            metrics: .iosWidgetSmall,
            showsCardFill: false,
            timeStyle: .widgetStacked,
            widgetEdgeAlignment: .leading
        )
        .padding(widgetContentMargins)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) {
            twilightWidgetSingleContainerBackground(skin: skin, blue: blue)
        }
    }

    @ViewBuilder
    private var mediumBody: some View {
        HStack(spacing: 0) {
            if entry.blueTwilightFirst {
                mediumHalfCard(blue: true, edge: .leading)
                mediumHalfCard(blue: false, edge: .trailing)
            } else {
                mediumHalfCard(blue: false, edge: .leading)
                mediumHalfCard(blue: true, edge: .trailing)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) {
            twilightWidgetMediumContainerBackground(skin: skin, blueTwilightFirst: entry.blueTwilightFirst)
        }
    }

    private func mediumHalfCard(blue: Bool, edge: GTTwilightWidgetEdgeAlignment) -> some View {
        let (cs, ce) = entry.clockStartEnd(blue: blue)
        return GoldenTimeTwilightWindowCard(
            skin: skin,
            title: iosWidgetTwilightTitle(blue: blue, lang: entry.lang),
            systemImage: blue ? "moon.stars.fill" : "sun.horizon.fill",
            blue: blue,
            useClockTimes: entry.useClockTimes,
            window: blue ? entry.blueWindow : entry.goldenWindow,
            clockStart: cs,
            clockEnd: ce,
            now: entry.date,
            lang: entry.lang,
            metrics: .iosWidgetMediumHalf,
            showsCardFill: false,
            timeStyle: .widgetStacked,
            widgetEdgeAlignment: edge
        )
        .padding(widgetInsetsForMediumHalf(edge: edge))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Split system widget margins: left column uses leading/top/bottom; right column uses trailing/top/bottom.
    private func widgetInsetsForMediumHalf(edge: GTTwilightWidgetEdgeAlignment) -> EdgeInsets {
        let m = widgetContentMargins
        if edge == .leading {
            return EdgeInsets(top: m.top, leading: m.leading, bottom: m.bottom, trailing: m.trailing * 0.35)
        }
        return EdgeInsets(top: m.top, leading: m.leading * 0.35, bottom: m.bottom, trailing: m.trailing)
    }
}

// MARK: - Full-bleed widget chrome (gradient is the container, like Maps)

private func twilightWidgetSingleContainerBackground(skin: GTPhaseSkin, blue: Bool) -> some View {
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

private func twilightWidgetMediumContainerBackground(skin: GTPhaseSkin, blueTwilightFirst: Bool) -> some View {
    HStack(spacing: 0) {
        if blueTwilightFirst {
            twilightWidgetHalfGradient(skin: skin, blue: true)
            twilightWidgetHalfGradient(skin: skin, blue: false)
        } else {
            twilightWidgetHalfGradient(skin: skin, blue: false)
            twilightWidgetHalfGradient(skin: skin, blue: true)
        }
    }
    .clipShape(ContainerRelativeShape())
    .overlay(
        ContainerRelativeShape()
            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
    )
}

private func twilightWidgetHalfGradient(skin: GTPhaseSkin, blue: Bool) -> some View {
    LinearGradient(
        colors: skin.twilightCardGradient(blue: blue),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}

struct GoldenTwilightIOSWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: GTIOWidgetKind.twilight, intent: GoldenTwilightIOSWidgetIntent.self, provider: GoldenTwilightIOSProvider()) {
            entry in
            GoldenTwilightIOSWidgetView(entry: entry)
        }
        .configurationDisplayName(GTCopy.systemAppDisplayName())
        .description("Same twilight cards as the app (clock or countdown). Small: pick blue or golden. Medium: both. Cached location — open the app once to refresh GPS.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}
