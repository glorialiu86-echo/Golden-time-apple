import GoldenTimeCore
import SwiftUI
import WidgetKit

struct GoldenTimePhoneRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = GoldenTimePhoneViewModel()
    @StateObject private var networkReachability = NetworkReachability()
    @AppStorage(GTAppLanguage.storageKey, store: GTAppGroup.shared) private var langStorageRaw: String = ""
    @AppStorage(GTTwilightDisplayMode.storageKey, store: GTAppGroup.shared) private var twilightModeRaw: String = GTTwilightDisplayMode.clockTimes.rawValue

    private var uiLang: GTAppLanguage {
        GTAppLanguage.fromStorageRaw(langStorageRaw)
    }

    private var twilightUsesClockTimes: Bool {
        twilightModeRaw != GTTwilightDisplayMode.countdown.rawValue
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

    var body: some View {
        let skin = GTPhaseSkin(phase: model.phase)
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
                GTAppGroup.migrateStandardToSharedIfNeeded()
                WidgetCenter.shared.reloadTimelines(ofKind: GTIOWidgetKind.twilight)
                model.syncContentLanguageWithStorage()
                model.beginForegroundLocationSession()
            }
            .onChange(of: langStorageRaw) { _, _ in
                model.syncContentLanguageWithStorage()
                WidgetCenter.shared.reloadTimelines(ofKind: GTIOWidgetKind.twilight)
            }
            .onChange(of: twilightModeRaw) { _, _ in
                WidgetCenter.shared.reloadTimelines(ofKind: GTIOWidgetKind.twilight)
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
    private func mainColumn(skin: GTPhaseSkin, lang: GTAppLanguage) -> some View {
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
                    GoldenTimeTwilightWindowCard(
                        skin: skin,
                        title: GTCopy.blueHourTitle(lang),
                        systemImage: "moon.stars.fill",
                        blue: true,
                        useClockTimes: twilightUsesClockTimes,
                        window: model.blueWindowRange,
                        clockStart: model.blueStartText,
                        clockEnd: model.blueEndText,
                        now: model.clockNow,
                        lang: lang,
                        metrics: .phone
                    )
                    GoldenTimeTwilightWindowCard(
                        skin: skin,
                        title: GTCopy.goldenHourTitle(lang),
                        systemImage: "sun.horizon.fill",
                        blue: false,
                        useClockTimes: twilightUsesClockTimes,
                        window: model.goldenWindowRange,
                        clockStart: model.goldenStartText,
                        clockEnd: model.goldenEndText,
                        now: model.clockNow,
                        lang: lang,
                        metrics: .phone
                    )
                } else {
                    GoldenTimeTwilightWindowCard(
                        skin: skin,
                        title: GTCopy.goldenHourTitle(lang),
                        systemImage: "sun.horizon.fill",
                        blue: false,
                        useClockTimes: twilightUsesClockTimes,
                        window: model.goldenWindowRange,
                        clockStart: model.goldenStartText,
                        clockEnd: model.goldenEndText,
                        now: model.clockNow,
                        lang: lang,
                        metrics: .phone
                    )
                    GoldenTimeTwilightWindowCard(
                        skin: skin,
                        title: GTCopy.blueHourTitle(lang),
                        systemImage: "moon.stars.fill",
                        blue: true,
                        useClockTimes: twilightUsesClockTimes,
                        window: model.blueWindowRange,
                        clockStart: model.blueStartText,
                        clockEnd: model.blueEndText,
                        now: model.clockNow,
                        lang: lang,
                        metrics: .phone
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
    private func compassDialBlock(skin: GTPhaseSkin, lang: GTAppLanguage) -> some View {
        if let coord = model.mapCoordinate {
            TwilightCompassCard(
                showMapBase: compassShowsMapBase,
                chromeGradient: skin.chromeGradient,
                compassInk: skin.ink,
                compassStroke: skin.panelStroke,
                chromeIsLight: skin.isLightChrome,
                uiLanguage: lang,
                coordinate: coord,
                deviceHeadingDegrees: model.deviceHeadingDegrees,
                blueSectorArcAzimuths: model.blueSectorArcAzimuths,
                goldenSectorArcAzimuths: model.goldenSectorArcAzimuths,
                blueSectorColors: skin.twilightCardGradient(blue: true),
                goldenSectorColors: skin.twilightCardGradient(blue: false),
                compassDayNight: model.compassDayNight,
                daySectorTint: skin.compassDayDiskTint,
                nightSectorTint: skin.compassNightDiskTint,
                sunBodyAzimuthDegrees: model.compassSunBodyAzimuthDegrees,
                moonBodyAzimuthDegrees: model.compassMoonBodyAzimuthDegrees
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
    private func compassFooterCopy(skin: GTPhaseSkin, lang: GTAppLanguage) -> some View {
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
    private func timeHeaderBlock(skin: GTPhaseSkin, lang: GTAppLanguage, date: Date) -> some View {
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

    private func twilightModeIconButton(skin: GTPhaseSkin, lang: GTAppLanguage) -> some View {
        Button {
            if twilightUsesClockTimes {
                twilightModeRaw = GTTwilightDisplayMode.countdown.rawValue
            } else {
                twilightModeRaw = GTTwilightDisplayMode.clockTimes.rawValue
            }
        } label: {
            Image(systemName: twilightUsesClockTimes ? "timer" : "clock")
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
            twilightUsesClockTimes ? GTCopy.a11ySwitchToCountdown(lang) : GTCopy.a11ySwitchToClock(lang)
        )
        .accessibilityHint(GTCopy.a11yModeToggleHint(lang))
    }

    private func languageToggleButton(skin: GTPhaseSkin, lang: GTAppLanguage) -> some View {
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
}
