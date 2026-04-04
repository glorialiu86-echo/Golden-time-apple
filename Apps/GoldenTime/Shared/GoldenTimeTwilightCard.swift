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
        timeFontSize: 22,
        mainSlotHeight: 34,
        countdownLabelFontSize: 14,
        horizontalPadding: 8,
        verticalPadding: 5,
        cornerRadius: 10,
        titleFont: .subheadline.weight(.bold),
        symbolFont: .caption.weight(.semibold)
    )
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
        metrics: GoldenTimeTwilightCardMetrics
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
    }

    public var body: some View {
        let m = metrics
        VStack(alignment: .center, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
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
                            .offset(y: -1)
                        Text(clockEnd)
                            .font(.system(size: m.timeFontSize, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(skin.twilightCardPrimaryForeground(blueCard: blue))
                            .lineLimit(1)
                            .minimumScaleFactor(0.42)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else if let w = window {
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
