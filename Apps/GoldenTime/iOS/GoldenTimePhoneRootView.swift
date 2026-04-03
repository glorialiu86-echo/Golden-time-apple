import GoldenTimeCore
import SwiftUI

// MARK: - Phase skin (fixed palettes + gradients; does not follow system Light/Dark)

private enum PhoneSkin: Equatable {
    case day
    case night
    case blueHour
    case goldenHour

    init(phase: PhaseState?) {
        switch phase {
        case .night:
            self = .night
        case .blue:
            self = .blueHour
        case .golden:
            self = .goldenHour
        case .day, nil:
            self = .day
        }
    }

    var upper: Color {
        switch self {
        case .day:
            Color(red: 0.93, green: 0.95, blue: 0.99)
        case .night:
            GTAppIconPalette.nightShellUpper
        case .blueHour:
            GTAppIconPalette.deepNavy
        case .goldenHour:
            Color(red: 46 / 255, green: 26 / 255, blue: 14 / 255)
        }
    }

    var lower: Color {
        switch self {
        case .day:
            Color(red: 0.82, green: 0.88, blue: 0.96)
        case .night:
            GTAppIconPalette.nightShellLower
        case .blueHour:
            Color(red: 32 / 255, green: 52 / 255, blue: 88 / 255)
        case .goldenHour:
            GTAppIconPalette.sunCore
        }
    }

    var ink: Color {
        switch self {
        case .day:
            Color(red: 0.12, green: 0.14, blue: 0.20)
        case .night, .blueHour, .goldenHour:
            Color.white.opacity(0.94)
        }
    }

    var muted: Color {
        ink.opacity(skinMutedOpacity)
    }

    private var skinMutedOpacity: CGFloat {
        switch self {
        case .day: 0.52
        case .night: 0.55
        case .blueHour: 0.58
        case .goldenHour: 0.55
        }
    }

    var panelStroke: Color {
        switch self {
        case .day:
            Color.black.opacity(0.08)
        case .night:
            Color.white.opacity(0.14)
        case .blueHour:
            Color.cyan.opacity(0.28)
        case .goldenHour:
            GTAppIconPalette.sunCore.opacity(0.42)
        }
    }

    var chromeGradient: [Color] {
        [upper.opacity(0.42), lower.opacity(0.42)]
    }

    /// Distinct blue-hour vs golden-hour card gradients per phase backdrop (keeps `ink` readable).
    func twilightCardGradient(blue: Bool) -> [Color] {
        switch self {
        case .day:
            return blue
                ? [Color(red: 0.7, green: 0.82, blue: 0.99), Color(red: 0.48, green: 0.66, blue: 0.93)]
                : [GTAppIconPalette.sunGlow, GTAppIconPalette.sunCore]
        case .night:
            return blue
                ? [GTAppIconPalette.deepNavy, Color(red: 48 / 255, green: 82 / 255, blue: 128 / 255)]
                : [GTAppIconPalette.sunDeep, GTAppIconPalette.sunCore]
        case .blueHour:
            return blue
                ? [Color(red: 0.16, green: 0.3, blue: 0.58), Color(red: 0.26, green: 0.48, blue: 0.88)]
                : [Color(red: 0.48, green: 0.28, blue: 0.14), GTAppIconPalette.sunCore]
        case .goldenHour:
            return blue
                ? [Color(red: 0.22, green: 0.34, blue: 0.52), Color(red: 0.32, green: 0.5, blue: 0.76)]
                : [GTAppIconPalette.sunCore, GTAppIconPalette.sunGlow]
        }
    }
}

private enum TwilightCardMode {
    case clockTimes
    case countdown
}

struct GoldenTimePhoneRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = GoldenTimePhoneViewModel()
    @StateObject private var networkReachability = NetworkReachability()
    @State private var twilightCardMode: TwilightCardMode = .clockTimes
    @AppStorage(GTAppLanguage.storageKey) private var langStorageRaw: String = ""

    private var uiLang: GTAppLanguage {
        GTAppLanguage.fromStorageRaw(langStorageRaw)
    }

    /// `GOLDEN_TIME_NO_MAP_BASE=1` forces gradient-only compass. Otherwise show `MapKit` when the device has a network route.
    private var compassShowsMapBase: Bool {
        if ProcessInfo.processInfo.environment["GOLDEN_TIME_NO_MAP_BASE"] == "1" {
            return false
        }
        return networkReachability.hasNetworkRoute
    }

    /// Large time in the page header only.
    private static let mainClockFontSize: CGFloat = 56

    /// Blue/golden cards: clock-times mode **and** countdown duration (`2h 03m` / `3小时15分`) use this size.
    private static let twilightCardTimeFontSize: CGFloat = 36

    /// Main slot height for both clock-times and countdown (same time font size).
    private static let twilightMainSlotHeight: CGFloat = 48

    private static func countdownLine(from fromDate: Date, to toDate: Date, lang: GTAppLanguage) -> String? {
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

    var body: some View {
        let skin = PhoneSkin(phase: model.phase)
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                LinearGradient(
                    colors: [skin.upper, skin.lower],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(edges: .all)
            }
            .overlay(alignment: .topLeading) {
                ScrollView {
                    mainColumn(skin: skin, lang: uiLang)
                        .padding(.horizontal, 18)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .scrollContentBackground(.hidden)
                .contentMargins(0, for: .scrollContent)
            }
            .onAppear {
                model.syncContentLanguageWithStorage()
                model.beginForegroundLocationSession()
            }
            .onChange(of: langStorageRaw) { _, _ in
                model.syncContentLanguageWithStorage()
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    model.beginForegroundLocationSession()
                default:
                    model.endForegroundLocationSession()
                }
            }
    }

    @ViewBuilder
    private func mainColumn(skin: PhoneSkin, lang: GTAppLanguage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            timeHeaderBlock(skin: skin, lang: lang, date: model.clockNow)

            HStack {
                Spacer(minLength: 0)
                Text("\(GTCopy.currentCoordinatesPrefix(lang))\(model.latitudeText), \(model.longitudeText)")
                    .font(.body.monospacedDigit().weight(.semibold))
                    .foregroundStyle(skin.muted)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.65)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 12) {
                if model.blueTwilightFirst {
                    twilightPanel(
                        skin: skin,
                        title: GTCopy.blueHourTitle(lang),
                        systemImage: "moon.stars.fill",
                        blue: true,
                        cardMode: twilightCardMode,
                        window: model.blueWindowRange,
                        clockStart: model.blueStartText,
                        clockEnd: model.blueEndText,
                        now: model.clockNow,
                        lang: lang
                    )
                    twilightPanel(
                        skin: skin,
                        title: GTCopy.goldenHourTitle(lang),
                        systemImage: "sun.horizon.fill",
                        blue: false,
                        cardMode: twilightCardMode,
                        window: model.goldenWindowRange,
                        clockStart: model.goldenStartText,
                        clockEnd: model.goldenEndText,
                        now: model.clockNow,
                        lang: lang
                    )
                } else {
                    twilightPanel(
                        skin: skin,
                        title: GTCopy.goldenHourTitle(lang),
                        systemImage: "sun.horizon.fill",
                        blue: false,
                        cardMode: twilightCardMode,
                        window: model.goldenWindowRange,
                        clockStart: model.goldenStartText,
                        clockEnd: model.goldenEndText,
                        now: model.clockNow,
                        lang: lang
                    )
                    twilightPanel(
                        skin: skin,
                        title: GTCopy.blueHourTitle(lang),
                        systemImage: "moon.stars.fill",
                        blue: true,
                        cardMode: twilightCardMode,
                        window: model.blueWindowRange,
                        clockStart: model.blueStartText,
                        clockEnd: model.blueEndText,
                        now: model.clockNow,
                        lang: lang
                    )
                }
            }

            compassDialBlock(skin: skin, lang: lang)

            if !model.statusLine.isEmpty {
                Text(model.statusLine)
                    .font(.caption)
                    .foregroundStyle(skin.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
                    .fixedSize(horizontal: false, vertical: true)
            }

            compassFooterCopy(skin: skin, lang: lang)
        }
    }

    /// Circular compass below twilight cards (cards stay the visual focus).
    @ViewBuilder
    private func compassDialBlock(skin: PhoneSkin, lang: GTAppLanguage) -> some View {
        if let coord = model.mapCoordinate {
            TwilightCompassCard(
                showMapBase: compassShowsMapBase,
                chromeGradient: skin.chromeGradient,
                compassInk: skin.ink,
                compassStroke: skin.panelStroke,
                uiLanguage: lang,
                coordinate: coord,
                deviceHeadingDegrees: model.deviceHeadingDegrees,
                blueSectorArcAzimuths: model.blueSectorArcAzimuths,
                goldenSectorArcAzimuths: model.goldenSectorArcAzimuths,
                blueSectorColors: skin.twilightCardGradient(blue: true),
                goldenSectorColors: skin.twilightCardGradient(blue: false)
            )
            .frame(height: 280)
            .frame(maxWidth: .infinity)
        } else {
            Text(GTCopy.compassCardNeedLocation(lang))
                .font(.caption)
                .foregroundStyle(skin.muted)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.vertical, 8)
        }
    }

    /// Legend + footnote stay at page bottom (below cards).
    @ViewBuilder
    private func compassFooterCopy(skin: PhoneSkin, lang: GTAppLanguage) -> some View {
        if model.mapCoordinate != nil {
            VStack(alignment: .center, spacing: 8) {
                Text(GTCopy.compassCardLegend(lang))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(skin.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)

                Text(GTCopy.compassCardFootnote(lang))
                    .font(.caption2)
                    .foregroundStyle(skin.muted.opacity(0.92))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
        }
    }

    /// Weekday / month / date on the left; mode + language controls on the **far right**, same row.
    private func timeHeaderBlock(skin: PhoneSkin, lang: GTAppLanguage, date: Date) -> some View {
        VStack(alignment: .center, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text(GTDateFormatters.headerLine(date, lang: lang))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(skin.muted)
                    .multilineTextAlignment(.leading)
                    .minimumScaleFactor(0.72)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 4) {
                    twilightModeIconButton(skin: skin, lang: lang)
                    languageToggleButton(skin: skin, lang: lang)
                }
                .fixedSize(horizontal: true, vertical: false)
            }

            Text(GTDateFormatters.timeLine(model.clockNow, lang: lang))
                .font(.system(size: Self.mainClockFontSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(skin.ink)
                .minimumScaleFactor(0.45)
                .lineLimit(1)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }

    /// Shared chrome for header icon buttons (timer/clock + language).
    private static let headerChromeButtonSize: CGFloat = 32
    private static let headerChromeStrokeWidth: CGFloat = 1

    private func twilightModeIconButton(skin: PhoneSkin, lang: GTAppLanguage) -> some View {
        Button {
            twilightCardMode = twilightCardMode == .clockTimes ? .countdown : .clockTimes
        } label: {
            Image(systemName: twilightCardMode == .clockTimes ? "timer" : "clock")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(skin.ink.opacity(0.92))
                .frame(width: Self.headerChromeButtonSize, height: Self.headerChromeButtonSize)
                .background {
                    Circle()
                        .strokeBorder(skin.panelStroke, lineWidth: Self.headerChromeStrokeWidth)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            twilightCardMode == .clockTimes ? GTCopy.a11ySwitchToCountdown(lang) : GTCopy.a11ySwitchToClock(lang)
        )
        .accessibilityHint(GTCopy.a11yModeToggleHint(lang))
    }

    private func languageToggleButton(skin: PhoneSkin, lang: GTAppLanguage) -> some View {
        Button {
            switch lang {
            case .chinese:
                langStorageRaw = GTAppLanguage.english.rawValue
            case .english:
                langStorageRaw = GTAppLanguage.chinese.rawValue
            }
        } label: {
            Text(lang == .chinese ? "EN" : "CN")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(skin.ink.opacity(0.92))
                .frame(width: Self.headerChromeButtonSize, height: Self.headerChromeButtonSize)
                .background {
                    Circle()
                        .strokeBorder(skin.panelStroke, lineWidth: Self.headerChromeStrokeWidth)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(GTCopy.a11yLanguageToggle(lang))
    }

    private func twilightPanel(
        skin: PhoneSkin,
        title: String,
        systemImage: String,
        blue: Bool,
        cardMode: TwilightCardMode,
        window: (start: Date, end: Date)?,
        clockStart: String,
        clockEnd: String,
        now: Date,
        lang: GTAppLanguage
    ) -> some View {
        VStack(alignment: .center, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(skin.muted)
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(skin.ink)
            }

            Group {
                if cardMode == .clockTimes {
                    /// `firstTextBaseline` makes SF Symbol sit low vs large rounded digits; center + matched scale reads aligned.
                    HStack(alignment: .center, spacing: 10) {
                        Text(clockStart)
                            .font(.system(size: Self.twilightCardTimeFontSize, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(skin.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.42)
                        Image(systemName: "arrow.right")
                            .font(.system(size: Self.twilightCardTimeFontSize * 0.58, weight: .bold, design: .rounded))
                            .foregroundStyle(skin.muted.opacity(0.95))
                            .frame(width: 28, alignment: .center)
                            .offset(y: -1)
                        Text(clockEnd)
                            .font(.system(size: Self.twilightCardTimeFontSize, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(skin.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.42)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else if let w = window {
                    let startTs = w.start.timeIntervalSince1970
                    let endTs = w.end.timeIntervalSince1970
                    let nowTs = now.timeIntervalSince1970
                    if nowTs < startTs,
                       let cd = Self.countdownLine(from: now, to: w.start, lang: lang)
                    {
                        let a11y = "\(GTCopy.countdownUntilStartLabel(lang)) \(cd)"
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(GTCopy.countdownUntilStartLabel(lang))
                                .font(.system(size: 22, weight: .semibold, design: .rounded))
                                .foregroundStyle(skin.muted)
                                .lineLimit(1)
                                .minimumScaleFactor(0.65)
                                .layoutPriority(-1)
                            Text(cd)
                                .font(.system(size: Self.twilightCardTimeFontSize, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(skin.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.42)
                                .layoutPriority(1)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .accessibilityLabel(a11y)
                    } else if nowTs < endTs,
                              let cd = Self.countdownLine(from: now, to: w.end, lang: lang)
                    {
                        let a11y = "\(GTCopy.countdownUntilEndLabel(lang)) \(cd)"
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(GTCopy.countdownUntilEndLabel(lang))
                                .font(.system(size: 22, weight: .semibold, design: .rounded))
                                .foregroundStyle(skin.muted)
                                .lineLimit(1)
                                .minimumScaleFactor(0.65)
                                .layoutPriority(-1)
                            Text(cd)
                                .font(.system(size: Self.twilightCardTimeFontSize, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(skin.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.42)
                                .layoutPriority(1)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .accessibilityLabel(a11y)
                    } else {
                        Text("—")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(skin.muted)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    }
                } else {
                    Text("—")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(skin.muted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
            .frame(height: Self.twilightMainSlotHeight)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: skin.twilightCardGradient(blue: blue),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(skin.panelStroke, lineWidth: 1)
                )
        )
    }
}
