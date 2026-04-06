import GoldenTimeCore
import SwiftUI

/// Layout metrics for `GoldenTimeTwilightWindowCard` (phone vs watch).
public struct GoldenTimeTwilightCardMetrics: Sendable {
    public var timeFontSize: CGFloat
    public var mainSlotHeight: CGFloat
    public var countdownLabelFontSize: CGFloat
    public var horizontalPadding: CGFloat
    public var verticalPadding: CGFloat
    public var cornerRadius: CGFloat
    public var titleFont: Font
    public var symbolFont: Font

    public static let phone = GoldenTimeTwilightCardMetrics(
        timeFontSize: 36,
        mainSlotHeight: 50,
        countdownLabelFontSize: 22,
        horizontalPadding: 18,
        verticalPadding: 8,
        cornerRadius: 15,
        titleFont: .headline.weight(.bold),
        symbolFont: .body.weight(.semibold)
    )

    public static let watch = GoldenTimeTwilightCardMetrics(
        timeFontSize: 25,
        mainSlotHeight: 37,
        countdownLabelFontSize: 14,
        horizontalPadding: 8,
        verticalPadding: 5,
        cornerRadius: 10,
        titleFont: .system(size: 13, weight: .bold, design: .rounded),
        symbolFont: .system(size: 11, weight: .semibold, design: .rounded)
    )
}

/// Layout for the main time block on `GoldenTimeTwilightWindowCard`.
public enum GTTwilightWindowTimeStyle: Sendable {
    /// Single-line clock span with arrow; countdown label and value on one row (in-app default).
    case standard
    /// Home-screen widget: clock start / arrow / end on separate lines; countdown label above value.
    case widgetStacked
}

public enum GTTwilightCountdownLine {
    public static func text(from fromDate: Date, to toDate: Date, lang: GTAppLanguage) -> String? {
        let ti = toDate.timeIntervalSince(fromDate)
        guard ti > 0 else { return nil }
        let totalMinutes = max(0, Int(floor(ti / 60.0)))
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h == 0 {
            if m == 0 { return GTCopy.countdownLessThanOneMinute(lang) }
            return GTCopy.countdownMinutes(m, lang)
        }
        return GTCopy.countdownHoursMinutes(h: h, m: m, lang)
    }
}

/// Same twilight window card as iPhone; watch passes `.watch` metrics.
public struct GoldenTimeTwilightWindowCard: View {
    public var skin: GTPhaseSkin
    public var title: String
    public var systemImage: String
    public var blue: Bool
    public var useClockTimes: Bool
    public var window: (start: Date, end: Date)?
    public var clockStart: String
    public var clockEnd: String
    public var now: Date
    public var lang: GTAppLanguage
    public var metrics: GoldenTimeTwilightCardMetrics
    /// When `false`, only the foreground is drawn (no in-view gradient); use with a full-bleed `containerBackground` (e.g. home-screen widgets).
    public var showsCardFill: Bool
    public var timeStyle: GTTwilightWindowTimeStyle

    public init(
        skin: GTPhaseSkin,
        title: String,
        systemImage: String,
        blue: Bool,
        useClockTimes: Bool,
        window: (start: Date, end: Date)?,
        clockStart: String,
        clockEnd: String,
        now: Date,
        lang: GTAppLanguage,
        metrics: GoldenTimeTwilightCardMetrics,
        showsCardFill: Bool = true,
        timeStyle: GTTwilightWindowTimeStyle = .standard
    ) {
        self.skin = skin
        self.title = title
        self.systemImage = systemImage
        self.blue = blue
        self.useClockTimes = useClockTimes
        self.window = window
        self.clockStart = clockStart
        self.clockEnd = clockEnd
        self.now = now
        self.lang = lang
        self.metrics = metrics
        self.showsCardFill = showsCardFill
        self.timeStyle = timeStyle
    }

    public var body: some View {
        let m = metrics
        let headerSpacing: CGFloat = timeStyle == .widgetStacked ? 5 : 7
        let columnSpacing: CGFloat = timeStyle == .widgetStacked ? 5 : 7
        let core = VStack(alignment: .center, spacing: columnSpacing) {
            HStack(alignment: .center, spacing: headerSpacing) {
                Image(systemName: systemImage)
                    .font(m.symbolFont)
                    .foregroundStyle(skin.twilightCardSecondaryForeground(blueCard: blue))
                Group {
                    if timeStyle == .widgetStacked {
                        Text(title)
                            .font(m.titleFont)
                            .foregroundStyle(skin.twilightCardPrimaryForeground(blueCard: blue))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    } else {
                        Text(title)
                            .font(m.titleFont)
                            .foregroundStyle(skin.twilightCardPrimaryForeground(blueCard: blue))
                    }
                }
            }

            Group {
                if useClockTimes {
                    if timeStyle == .widgetStacked {
                        clockTimesStacked(m: m)
                    } else {
                        HStack(alignment: .center, spacing: 6) {
                            Text(clockStart)
                                .font(.system(size: m.timeFontSize, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(skin.twilightCardPrimaryForeground(blueCard: blue))
                                .lineLimit(1)
                                .minimumScaleFactor(0.42)
                            Image(systemName: "arrow.right")
                                .font(.system(size: m.timeFontSize * 0.58, weight: .bold, design: .rounded))
                                .foregroundStyle(skin.twilightCardSecondaryForeground(blueCard: blue))
                                .frame(width: max(18, m.timeFontSize * 0.75), alignment: .center)
                                .offset(y: -1)
                            Text(clockEnd)
                                .font(.system(size: m.timeFontSize, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(skin.twilightCardPrimaryForeground(blueCard: blue))
                                .lineLimit(1)
                                .minimumScaleFactor(0.42)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    }
                } else if let w = window {
                    let startTs = w.start.timeIntervalSince1970
                    let endTs = w.end.timeIntervalSince1970
                    let nowTs = now.timeIntervalSince1970
                    if nowTs < startTs,
                       let cd = GTTwilightCountdownLine.text(from: now, to: w.start, lang: lang)
                    {
                        let a11y = "\(GTCopy.countdownUntilStartLabel(lang)) \(cd)"
                        if timeStyle == .widgetStacked {
                            countdownStacked(
                                label: GTCopy.countdownUntilStartLabel(lang),
                                value: cd,
                                a11y: a11y,
                                blueCard: blue,
                                skin: skin,
                                m: m
                            )
                        } else {
                            countdownRow(label: GTCopy.countdownUntilStartLabel(lang), value: cd, a11y: a11y, blueCard: blue, skin: skin, m: m)
                        }
                    } else if nowTs < endTs,
                              let cd = GTTwilightCountdownLine.text(from: now, to: w.end, lang: lang)
                    {
                        let a11y = "\(GTCopy.countdownUntilEndLabel(lang)) \(cd)"
                        if timeStyle == .widgetStacked {
                            countdownStacked(
                                label: GTCopy.countdownUntilEndLabel(lang),
                                value: cd,
                                a11y: a11y,
                                blueCard: blue,
                                skin: skin,
                                m: m
                            )
                        } else {
                            countdownRow(label: GTCopy.countdownUntilEndLabel(lang), value: cd, a11y: a11y, blueCard: blue, skin: skin, m: m)
                        }
                    } else {
                        Text("—")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(skin.twilightCardSecondaryForeground(blueCard: blue))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    }
                } else {
                    Text("—")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(skin.twilightCardSecondaryForeground(blueCard: blue))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
            .frame(height: m.mainSlotHeight)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, m.horizontalPadding)
        .padding(.vertical, m.verticalPadding)
        .frame(maxWidth: .infinity, alignment: .center)

        Group {
            if showsCardFill {
                core
                    .background(
                        RoundedRectangle(cornerRadius: m.cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: skin.twilightCardGradient(blue: blue),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: m.cornerRadius, style: .continuous)
                                    .strokeBorder(skin.panelStroke, lineWidth: 1)
                            )
                    )
            } else {
                core
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
    }

    @ViewBuilder
    private func clockTimesStacked(m: GoldenTimeTwilightCardMetrics) -> some View {
        let digit = Font.system(size: m.timeFontSize, weight: .bold, design: .rounded)
        let arrowSize = max(11, m.timeFontSize * 0.32)
        VStack(spacing: 3) {
            Text(clockStart)
                .font(digit)
                .monospacedDigit()
                .foregroundStyle(skin.twilightCardPrimaryForeground(blueCard: blue))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity)
            Image(systemName: "arrow.down")
                .font(.system(size: arrowSize, weight: .bold, design: .rounded))
                .foregroundStyle(skin.twilightCardSecondaryForeground(blueCard: blue))
            Text(clockEnd)
                .font(digit)
                .monospacedDigit()
                .foregroundStyle(skin.twilightCardPrimaryForeground(blueCard: blue))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func countdownStacked(label: String, value: String, a11y: String, blueCard: Bool, skin: GTPhaseSkin, m: GoldenTimeTwilightCardMetrics) -> some View {
        VStack(alignment: .center, spacing: 3) {
            Text(label)
                .font(.system(size: m.countdownLabelFontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(skin.twilightCardSecondaryForeground(blueCard: blueCard))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity)
            Text(value)
                .font(.system(size: m.timeFontSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(skin.twilightCardPrimaryForeground(blueCard: blueCard))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .accessibilityLabel(a11y)
    }

    @ViewBuilder
    private func countdownRow(label: String, value: String, a11y: String, blueCard: Bool, skin: GTPhaseSkin, m: GoldenTimeTwilightCardMetrics) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(label)
                .font(.system(size: m.countdownLabelFontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(skin.twilightCardSecondaryForeground(blueCard: blueCard))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .layoutPriority(-1)
            Text(value)
                .font(.system(size: m.timeFontSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(skin.twilightCardPrimaryForeground(blueCard: blueCard))
                .lineLimit(1)
                .minimumScaleFactor(0.42)
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .accessibilityLabel(a11y)
    }
}
