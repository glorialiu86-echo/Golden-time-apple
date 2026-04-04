import AppIntents
import GoldenTimeCore
import SwiftUI
import WidgetKit

/// 无参数配置；用于在 watchOS「你的小组件 / Smart Stack」与表盘复杂功能中注册 Widget（`AppIntentConfiguration` 比纯 `StaticConfiguration` 更容易出现在系统列表里）。
struct GoldenTwilightWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Golden Hour Compass" }

    static var description: IntentDescription {
        IntentDescription("Next blue hour and golden hour from cached location.")
    }
}

struct GoldenTwilightEntry: TimelineEntry {
    var date: Date
    var lang: GTAppLanguage
    var blueLine: String
    var goldenLine: String
}

struct GoldenTwilightProvider: AppIntentTimelineProvider {
    typealias Intent = GoldenTwilightWidgetIntent
    typealias Entry = GoldenTwilightEntry

    func recommendations() -> [AppIntentRecommendation<GoldenTwilightWidgetIntent>] {
        [
            AppIntentRecommendation(
                intent: GoldenTwilightWidgetIntent(),
                description: "Blue and golden hour from cached location."
            ),
        ]
    }

    func placeholder(in _: Context) -> GoldenTwilightEntry {
        GoldenTwilightEntry(date: Date(), lang: .chinese, blueLine: "—", goldenLine: "—")
    }

    func snapshot(for _: GoldenTwilightWidgetIntent, in _: Context) async -> GoldenTwilightEntry {
        makeEntry()
    }

    func timeline(for _: GoldenTwilightWidgetIntent, in _: Context) async -> Timeline<GoldenTwilightEntry> {
        let entry = makeEntry()
        let refresh = Calendar.current.date(byAdding: .minute, value: 15, to: entry.date) ?? entry.date.addingTimeInterval(900)
        return Timeline(entries: [entry], policy: .after(refresh))
    }

    private func makeEntry() -> GoldenTwilightEntry {
        let suite = GTAppGroup.shared
        let lang = GTAppLanguage.resolved()
        let now = Date()
        guard suite.object(forKey: GoldenTimeLocationCache.latitudeKey) != nil else {
            return GoldenTwilightEntry(
                date: now,
                lang: lang,
                blueLine: "—",
                goldenLine: "—"
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
                return GTDateFormatters.twilightInstantLabel(window.start, now: now, lang: lang)
            }
            return GTTwilightCountdownLine.text(from: now, to: window.start, lang: lang)
                ?? GTCopy.countdownLessThanOneMinute(lang)
        }
        let b = line(for: engine.nextBlueWindow(after: now))
        let g = line(for: engine.nextGoldenWindow(after: now))
        return GoldenTwilightEntry(date: now, lang: lang, blueLine: b, goldenLine: g)
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
                VStack(spacing: 2) {
                    Image(systemName: "sun.horizon.fill")
                        .font(.caption2)
                    Text(entry.goldenLine)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.45)
                }
                .padding(.horizontal, 2)
            }
            .containerBackground(.fill.tertiary, for: .widget)
        case .accessoryRectangular:
            // Smart Stack 大卡与模块化矩形复杂功能共用此 family（watchOS 无 systemMedium）。
            VStack(alignment: .leading, spacing: 6) {
                Text(GTCopy.widgetStackTitle(entry.lang))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                twilightRows(font: .subheadline.weight(.medium), iconSize: 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(6)
            .containerBackground(.fill.tertiary, for: .widget)
        case .accessoryInline:
            Text("\(entry.blueLine)  \(entry.goldenLine)")
                .font(.caption2.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .containerBackground(.fill.tertiary, for: .widget)
        case .accessoryCorner:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "sun.horizon.fill")
                    .font(.caption2)
            }
            .containerBackground(.fill.tertiary, for: .widget)
        @unknown default:
            VStack(alignment: .leading, spacing: 4) {
                twilightRows(font: .caption2, iconSize: nil)
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
    }

    @ViewBuilder
    private func twilightRows(font: Font, iconSize: CGFloat?) -> some View {
        Label {
            Text(entry.blueLine)
                .font(font.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        } icon: {
            Image(systemName: "moon.stars.fill")
                .font(iconSize.map { .system(size: $0) } ?? .caption2)
        }
        Label {
            Text(entry.goldenLine)
                .font(font.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        } icon: {
            Image(systemName: "sun.horizon.fill")
                .font(iconSize.map { .system(size: $0) } ?? .caption2)
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
        .configurationDisplayName("Golden Hour Compass")
        .description("Next blue hour and golden hour starts from cached location.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
            .accessoryCorner,
        ])
    }
}
