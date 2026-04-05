import GoldenTimeCore
import SwiftUI
import WidgetKit

// MARK: - Timeline (same data as watch widget: App Group cache + engine)

struct GoldenTwilightIOSEntry: TimelineEntry {
    var date: Date
    var lang: GTAppLanguage
    var blueLine: String
    var goldenLine: String
}

struct GoldenTwilightIOSProvider: TimelineProvider {
    func placeholder(in _: Context) -> GoldenTwilightIOSEntry {
        GoldenTwilightIOSEntry(date: Date(), lang: .chinese, blueLine: "—", goldenLine: "—")
    }

    func getSnapshot(in _: Context, completion: @escaping (GoldenTwilightIOSEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<GoldenTwilightIOSEntry>) -> Void) {
        let entry = makeEntry()
        let refresh = Calendar.current.date(byAdding: .minute, value: 15, to: entry.date) ?? entry.date.addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    private func makeEntry() -> GoldenTwilightIOSEntry {
        let suite = GTAppGroup.shared
        GTAppGroup.materializeDefaultPreferencesIfNeeded()
        let lang = GTAppLanguage.widgetLanguageIOS(suite: suite)
        let now = Date()
        guard suite.object(forKey: GoldenTimeLocationCache.latitudeKey) != nil else {
            return GoldenTwilightIOSEntry(date: now, lang: lang, blueLine: "—", goldenLine: "—")
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
        return GoldenTwilightIOSEntry(date: now, lang: lang, blueLine: b, goldenLine: g)
    }
}

// MARK: - Views

struct GoldenTwilightIOSWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: GoldenTwilightIOSEntry

    var body: some View {
        switch family {
        case .systemSmall:
            smallContent
                .containerBackground(GTWidgetSurface.homeBackground, for: .widget)
        case .systemMedium:
            mediumContent
                .containerBackground(GTWidgetSurface.homeBackground, for: .widget)
        case .systemLarge:
            largeContent
                .containerBackground(GTWidgetSurface.homeBackground, for: .widget)
        case .systemExtraLarge:
            extraLargeContent
                .containerBackground(GTWidgetSurface.homeBackground, for: .widget)
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
                .foregroundStyle(GTWidgetSurface.accessoryPrimary)
                .padding(.horizontal, 2)
            }
            .containerBackground(Color.clear, for: .widget)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 4) {
                Text(GTCopy.widgetStackTitle(entry.lang))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(GTWidgetSurface.accessorySecondary)
                twilightRows(
                    font: .subheadline.weight(.medium),
                    iconSize: 12,
                    rowForeground: GTWidgetSurface.accessoryPrimary
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(6)
            .containerBackground(Color.clear, for: .widget)
        case .accessoryInline:
            Text("\(entry.blueLine)  \(entry.goldenLine)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(GTWidgetSurface.accessoryPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .containerBackground(Color.clear, for: .widget)
        @unknown default:
            mediumContent
                .containerBackground(GTWidgetSurface.homeBackground, for: .widget)
        }
    }

    private var smallContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(GTCopy.widgetStackTitle(entry.lang))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(GTWidgetSurface.homeTitleMuted)
            twilightRows(
                font: .caption2.weight(.medium),
                iconSize: 11,
                rowForeground: GTWidgetSurface.homeBody
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var mediumContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(GTCopy.widgetStackTitle(entry.lang))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(GTWidgetSurface.homeBody)
            twilightRows(
                font: .body.weight(.medium),
                iconSize: 14,
                rowForeground: GTWidgetSurface.homeBody
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var largeContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(GTCopy.widgetStackTitle(entry.lang))
                .font(.headline)
                .foregroundStyle(GTWidgetSurface.homeBody)
            twilightRows(
                font: .title3.weight(.medium),
                iconSize: 18,
                rowForeground: GTWidgetSurface.homeBody
            )
            Text(GTCopy.widgetOpenAppHint(entry.lang))
                .font(.caption)
                .foregroundStyle(GTWidgetSurface.homeFootnote)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var extraLargeContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(GTCopy.widgetStackTitle(entry.lang))
                .font(.title3.weight(.semibold))
                .foregroundStyle(GTWidgetSurface.homeBody)
            twilightRows(
                font: .title2.weight(.medium),
                iconSize: 20,
                rowForeground: GTWidgetSurface.homeBody
            )
            Spacer(minLength: 0)
            Text(GTCopy.widgetOpenAppHint(entry.lang))
                .font(.footnote)
                .foregroundStyle(GTWidgetSurface.homeFootnote)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func twilightRows(font: Font, iconSize: CGFloat?, rowForeground: Color) -> some View {
        Label {
            Text(entry.blueLine)
                .font(font.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        } icon: {
            Image(systemName: "moon.stars.fill")
                .font(iconSize.map { .system(size: $0) } ?? .caption2)
        }
        .foregroundStyle(rowForeground)
        Label {
            Text(entry.goldenLine)
                .font(font.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        } icon: {
            Image(systemName: "sun.horizon.fill")
                .font(iconSize.map { .system(size: $0) } ?? .caption2)
        }
        .foregroundStyle(rowForeground)
    }
}

struct GoldenTwilightIOSWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: GTIOWidgetKind.twilight, provider: GoldenTwilightIOSProvider()) { entry in
            GoldenTwilightIOSWidgetView(entry: entry)
        }
        .configurationDisplayName(GTCopy.systemAppDisplayName())
        .description("Next blue hour and golden hour from cached location. Open the app once to refresh GPS.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .systemExtraLarge,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
        ])
    }
}
