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
    /// Home-screen widget: top-aligned, stacked times, title de-emphasized.
    case widgetStacked
}

/// Horizontal edge for home-screen widget halves (left column leading, right column trailing).
public enum GTTwilightWidgetEdgeAlignment: Sendable {
    case leading
    case trailing
}

public enum GTTwilightWidgetCountdownLayout: Sendable {
    case standard
    case splitHoursMinutes
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
    /// Used when `timeStyle == .widgetStacked` (medium widget right half uses `.trailing`).
    public var widgetEdgeAlignment: GTTwilightWidgetEdgeAlignment
    public var widgetCountdownLayout: GTTwilightWidgetCountdownLayout

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
        timeStyle: GTTwilightWindowTimeStyle = .standard,
        widgetEdgeAlignment: GTTwilightWidgetEdgeAlignment = .leading,
        widgetCountdownLayout: GTTwilightWidgetCountdownLayout = .standard
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
        self.widgetEdgeAlignment = widgetEdgeAlignment
        self.widgetCountdownLayout = widgetCountdownLayout
    }

    public var body: some View {
        let m = metrics
        Group {
            if showsCardFill {
                coreContent(m: m)
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
                coreContent(m: m)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    @ViewBuilder
    private func coreContent(m: GoldenTimeTwilightCardMetrics) -> some View {
        if timeStyle == .widgetStacked {
            widgetStackedCore(m: m)
        } else {
            standardCore(m: m)
        }
    }

    @ViewBuilder
    private func standardCore(m: GoldenTimeTwilightCardMetrics) -> some View {
        let columnSpacing: CGFloat = 7
        VStack(alignment: .center, spacing: columnSpacing) {
            HStack(alignment: .center, spacing: 7) {
                Image(systemName: systemImage)
                    .font(m.symbolFont)
                    .foregroundStyle(skin.twilightCardSecondaryForeground(blueCard: blue))
                Text(title)
                    .font(m.titleFont)
                    .foregroundStyle(skin.twilightCardPrimaryForeground(blueCard: blue))
            }

            Group {
                if useClockTimes {
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
                        Text(clockEnd)
                            .font(.system(size: m.timeFontSize, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(skin.twilightCardPrimaryForeground(blueCard: blue))
                            .lineLimit(1)
                            .minimumScaleFactor(0.42)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else if let w = window {
                    standardCountdownBody(window: w, m: m)
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
    }

    @ViewBuilder
    private func widgetStackedCore(m: GoldenTimeTwilightCardMetrics) -> some View {
        let edge = widgetEdgeAlignment
        let hAlign: HorizontalAlignment = edge == .leading ? .leading : .trailing
        let rowAlign: Alignment = edge == .leading ? .topLeading : .topTrailing
        VStack(alignment: hAlign, spacing: 0) {
            Group {
                if edge == .leading {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Image(systemName: systemImage)
                            .font(m.symbolFont)
                            .foregroundStyle(skin.twilightCardSecondaryForeground(blueCard: blue))
                        Text(title)
                            .font(m.titleFont)
                            .foregroundStyle(skin.twilightCardSecondaryForeground(blueCard: blue))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Spacer(minLength: 0)
                        Image(systemName: systemImage)
                            .font(m.symbolFont)
                            .foregroundStyle(skin.twilightCardSecondaryForeground(blueCard: blue))
                        Text(title)
                            .font(m.titleFont)
                            .foregroundStyle(skin.twilightCardSecondaryForeground(blueCard: blue))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: edge == .leading ? .leading : .trailing)
            .padding(.bottom, 6)

            Spacer(minLength: 0)

            Group {
                if useClockTimes {
                    clockTimesStacked(m: m, edge: edge)
                } else if let w = window {
                    widgetCountdownBody(window: w, m: m, edge: edge)
                } else {
                    Text("—")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(skin.twilightCardSecondaryForeground(blueCard: blue))
                        .frame(maxWidth: .infinity, alignment: edge == .leading ? .leading : .trailing)
                }
            }
            .frame(maxWidth: .infinity, alignment: rowAlign)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, m.horizontalPadding)
        .padding(.vertical, m.verticalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func standardCountdownBody(window w: (start: Date, end: Date), m: GoldenTimeTwilightCardMetrics) -> some View {
        let startTs = w.start.timeIntervalSince1970
        let endTs = w.end.timeIntervalSince1970
        let nowTs = now.timeIntervalSince1970
        if nowTs < startTs,
           let cd = GTTwilightCountdownLine.text(from: now, to: w.start, lang: lang)
        {
            let a11y = "\(GTCopy.countdownUntilStartLabel(lang)) \(cd)"
            countdownRow(label: GTCopy.countdownUntilStartLabel(lang), value: cd, a11y: a11y, blueCard: blue, skin: skin, m: m)
        } else if nowTs < endTs,
                  let cd = GTTwilightCountdownLine.text(from: now, to: w.end, lang: lang)
        {
            let a11y = "\(GTCopy.countdownUntilEndLabel(lang)) \(cd)"
            countdownRow(label: GTCopy.countdownUntilEndLabel(lang), value: cd, a11y: a11y, blueCard: blue, skin: skin, m: m)
        } else {
            Text("—")
                .font(.title3.weight(.bold))
                .foregroundStyle(skin.twilightCardSecondaryForeground(blueCard: blue))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    @ViewBuilder
    private func widgetCountdownBody(window w: (start: Date, end: Date), m: GoldenTimeTwilightCardMetrics, edge: GTTwilightWidgetEdgeAlignment) -> some View {
        let startTs = w.start.timeIntervalSince1970
        let endTs = w.end.timeIntervalSince1970
        let nowTs = now.timeIntervalSince1970
        if nowTs < startTs,
           let cd = GTTwilightCountdownLine.text(from: now, to: w.start, lang: lang)
        {
            let a11y = "\(GTCopy.countdownUntilStartLabel(lang)) \(cd)"
            countdownStacked(
                label: GTCopy.countdownUntilStartLabel(lang),
                value: cd,
                a11y: a11y,
                blueCard: blue,
                skin: skin,
                m: m,
                edge: edge
            )
        } else if nowTs < endTs,
                  let cd = GTTwilightCountdownLine.text(from: now, to: w.end, lang: lang)
        {
            let a11y = "\(GTCopy.countdownUntilEndLabel(lang)) \(cd)"
            countdownStacked(
                label: GTCopy.countdownUntilEndLabel(lang),
                value: cd,
                a11y: a11y,
                blueCard: blue,
                skin: skin,
                m: m,
                edge: edge
            )
        } else {
            Text("—")
                .font(.title2.weight(.bold))
                .foregroundStyle(skin.twilightCardSecondaryForeground(blueCard: blue))
                .frame(maxWidth: .infinity, alignment: edge == .leading ? .leading : .trailing)
        }
    }

    @ViewBuilder
    private func clockTimesStacked(m: GoldenTimeTwilightCardMetrics, edge: GTTwilightWidgetEdgeAlignment) -> some View {
        let frameAlign: Alignment = edge == .leading ? .leading : .trailing
        VStack(alignment: edge == .leading ? .leading : .trailing, spacing: 5) {
            clockLabeledInstantRow(
                tag: GTCopy.twilightClockStartTag(lang),
                value: clockStart,
                m: m,
                edge: edge
            )
            clockLabeledInstantRow(
                tag: GTCopy.twilightClockEndTag(lang),
                value: clockEnd,
                m: m,
                edge: edge
            )
        }
        .frame(maxWidth: .infinity, alignment: frameAlign)
        .accessibilityLabel(
            "\(GTCopy.twilightClockStartTag(lang)) \(clockStart), \(GTCopy.twilightClockEndTag(lang)) \(clockEnd)"
        )
    }

    @ViewBuilder
    private func clockLabeledInstantRow(
        tag: String,
        value: String,
        m: GoldenTimeTwilightCardMetrics,
        edge: GTTwilightWidgetEdgeAlignment
    ) -> some View {
        let digit = Font.system(size: m.timeFontSize, weight: .bold, design: .rounded)
        let tagSize = max(9, m.timeFontSize * 0.26)
        let rowAlign: Alignment = edge == .leading ? .leading : .trailing
        HStack(alignment: .center, spacing: 5) {
            Text(tag)
                .font(.system(size: tagSize, weight: .medium, design: .rounded))
                .foregroundStyle(skin.twilightCardSecondaryForeground(blueCard: blue))
                .fixedSize(horizontal: true, vertical: false)
            Text(value)
                .font(digit)
                .monospacedDigit()
                .foregroundStyle(skin.twilightCardPrimaryForeground(blueCard: blue))
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .multilineTextAlignment(edge == .leading ? .leading : .trailing)
        }
        .frame(maxWidth: .infinity, alignment: rowAlign)
    }

    @ViewBuilder
    private func countdownStacked(
        label: String,
        value: String,
        a11y: String,
        blueCard: Bool,
        skin: GTPhaseSkin,
        m: GoldenTimeTwilightCardMetrics,
        edge: GTTwilightWidgetEdgeAlignment
    ) -> some View {
        let textAlign: TextAlignment = edge == .leading ? .leading : .trailing
        let frameAlign: Alignment = edge == .leading ? .leading : .trailing
        VStack(alignment: edge == .leading ? .leading : .trailing, spacing: 4) {
            switch widgetCountdownLayout {
            case .standard:
                Text(label)
                    .font(.system(size: m.countdownLabelFontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(skin.twilightCardSecondaryForeground(blueCard: blueCard))
                    .multilineTextAlignment(textAlign)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, alignment: frameAlign)
                Text(value)
                    .font(.system(size: m.timeFontSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(skin.twilightCardPrimaryForeground(blueCard: blueCard))
                    .multilineTextAlignment(textAlign)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                    .frame(maxWidth: .infinity, alignment: frameAlign)
            case .splitHoursMinutes:
                splitCountdownStacked(
                    label: label,
                    value: value,
                    blueCard: blueCard,
                    skin: skin,
                    m: m,
                    edge: edge,
                    textAlign: textAlign,
                    frameAlign: frameAlign
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: frameAlign)
        .accessibilityLabel(a11y)
    }

    @ViewBuilder
    private func splitCountdownStacked(
        label: String,
        value: String,
        blueCard: Bool,
        skin: GTPhaseSkin,
        m: GoldenTimeTwilightCardMetrics,
        edge: GTTwilightWidgetEdgeAlignment,
        textAlign: TextAlignment,
        frameAlign: Alignment
    ) -> some View {
        let parts = splitWidgetCountdownParts(from: value)
        let valueFont = Font.system(size: m.timeFontSize, weight: .bold, design: .rounded)

        if let hours = parts.hoursLine {
            Text(label)
                .font(.system(size: m.countdownLabelFontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(skin.twilightCardSecondaryForeground(blueCard: blueCard))
                .multilineTextAlignment(textAlign)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: frameAlign)
            VStack(alignment: edge == .leading ? .leading : .trailing, spacing: 0) {
                Text(hours)
                    .font(valueFont)
                    .monospacedDigit()
                    .foregroundStyle(skin.twilightCardPrimaryForeground(blueCard: blueCard))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .frame(maxWidth: .infinity, alignment: frameAlign)
                Text(parts.minutesLine)
                    .font(valueFont)
                    .monospacedDigit()
                    .foregroundStyle(skin.twilightCardPrimaryForeground(blueCard: blueCard))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .frame(maxWidth: .infinity, alignment: frameAlign)
            }
        } else {
            VStack(alignment: edge == .leading ? .leading : .trailing, spacing: 2) {
                Text(label)
                    .font(.system(size: m.countdownLabelFontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(skin.twilightCardSecondaryForeground(blueCard: blueCard))
                    .multilineTextAlignment(textAlign)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, alignment: frameAlign)
                Text(parts.minutesLine)
                    .font(valueFont)
                    .monospacedDigit()
                    .foregroundStyle(skin.twilightCardPrimaryForeground(blueCard: blueCard))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .frame(maxWidth: .infinity, alignment: frameAlign)
            }
            .frame(maxWidth: .infinity, alignment: frameAlign)
        }
    }

    private func splitWidgetCountdownParts(from value: String) -> (hoursLine: String?, minutesLine: String) {
        switch lang {
        case .chinese:
            if let hourRange = value.range(of: "小时"),
               let minuteRange = value.range(of: "分", options: .backwards)
            {
                let hoursLine = String(value[..<hourRange.upperBound])
                let minutesLine = String(value[hourRange.upperBound..<minuteRange.upperBound])
                return (hoursLine, minutesLine)
            }
        case .english:
            let parts = value.split(separator: " ", omittingEmptySubsequences: true)
            if parts.count >= 2,
               parts[0].hasSuffix("h"),
               parts[1].hasSuffix("m")
            {
                return (String(parts[0]), String(parts[1]))
            }
        }
        return (nil, value)
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
