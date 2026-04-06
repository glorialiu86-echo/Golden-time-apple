import Foundation
import GoldenTimeCore
import SwiftUI
import WidgetKit

struct GoldenTimePhoneRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = GoldenTimePhoneViewModel()
    @StateObject private var networkReachability = NetworkReachability()
    @AppStorage(GTAppLanguage.storageKey, store: GTAppGroup.shared) private var langPreferenceRaw: String =
        GTAppLanguage.followSystemStorageValue
    @AppStorage(GTTwilightDisplayMode.storageKey, store: GTAppGroup.shared) private var twilightModeRaw: String = GTTwilightDisplayMode.clockTimes.rawValue
    @AppStorage(GTCompassMapSettings.storageKey, store: GTAppGroup.shared) private var mapCameraDistanceStorage: Double =
        GTCompassMapSettings.defaultCameraDistanceMeters
    @State private var showSettings = false
    /// Bumps when `NSLocale.currentLocaleDidChangeNotification` fires so `uiLang` re-evaluates while preference is「跟随系统」.
    @State private var systemLocaleBump = UUID()

    private var uiLang: GTAppLanguage {
        let _ = systemLocaleBump
        return GTAppLanguage.phoneDisplayLanguage(preferenceRaw: langPreferenceRaw)
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
    private static let mainClockFontSize: CGFloat = 65
    /// User-requested 20% larger compass presentation on iPhone home screen.
    private static let compassDialHeight: CGFloat = 336

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
                        .padding(.horizontal, 19)
                        .padding(.top, 10)
                        .padding(.bottom, 28)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .scrollContentBackground(.hidden)
                .contentMargins(0, for: .scrollContent)
            }
            .onAppear {
                GTAppGroup.migrateStandardToSharedIfNeeded()
                GTWatchConnectivitySync.shared.activate()
                model.syncContentLanguageWithAppPreference()
                publishCompanionSyncAndReloadWidgets()
                model.startLocationPipeline()
                model.beginForegroundLocationSession()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in
                systemLocaleBump = UUID()
                model.syncContentLanguageWithAppPreference()
                publishCompanionSyncAndReloadWidgets()
            }
            .onChange(of: langPreferenceRaw) { _, _ in
                model.syncContentLanguageWithAppPreference()
                publishCompanionSyncAndReloadWidgets()
            }
            .onChange(of: twilightModeRaw) { _, _ in
                publishCompanionSyncAndReloadWidgets()
                WidgetCenter.shared.reloadTimelines(ofKind: GTIOWidgetKind.twilight)
            }
            .onChange(of: mapCameraDistanceStorage) { _, _ in
                publishCompanionSyncAndReloadWidgets()
            }
            .onChange(of: networkReachability.hasNetworkRoute) { _, _ in
                publishCompanionSyncAndReloadWidgets()
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    publishCompanionSyncAndReloadWidgets()
                    model.beginForegroundLocationSession()
                default:
                    model.endForegroundLocationSession()
                }
            }
            .sheet(isPresented: $showSettings) {
                GoldenTimePhoneSettingsView(model: model)
            }
    }

    @ViewBuilder
    private func mainColumn(skin: GTPhaseSkin, lang: GTAppLanguage) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                timeHeaderBlock(skin: skin, lang: lang, date: model.clockNow)

                HStack {
                    Spacer(minLength: 0)
                    Text("\(GTCopy.currentCoordinatesPrefix(lang))\(model.latitudeText), \(model.longitudeText)")
                        .font(.body.monospacedDigit().weight(.semibold))
                        .foregroundStyle(skin.chromeSecondaryForeground)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.65)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
            }

            VStack(spacing: 14) {
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
                    .foregroundStyle(skin.chromeSecondaryForeground)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 7)
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
            .frame(height: Self.compassDialHeight)
            .frame(maxWidth: .infinity)
        } else {
            Text(GTCopy.compassCardNeedLocation(lang))
                .font(.caption)
                .foregroundStyle(skin.chromeSecondaryForeground)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.vertical, 8)
        }
    }

    /// Compass usage note at page bottom (below dial).
    @ViewBuilder
    private func compassFooterCopy(skin: GTPhaseSkin, lang: GTAppLanguage) -> some View {
        if model.mapCoordinate != nil {
            Text(GTCopy.compassCardGuide(lang))
                .font(.caption)
                .foregroundStyle(skin.chromeSecondaryForeground)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
        }
    }

    /// Weekday / month / date on the left; twilight mode shortcut + settings gear on the **far right**, same row.
    private func timeHeaderBlock(skin: GTPhaseSkin, lang: GTAppLanguage, date: Date) -> some View {
        VStack(alignment: .center, spacing: 9) {
            HStack(alignment: .center, spacing: 8) {
                Text(GTDateFormatters.headerLine(date, lang: lang))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(skin.chromeSecondaryForeground)
                    .multilineTextAlignment(.leading)
                    .minimumScaleFactor(0.72)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 4) {
                    twilightModeIconButton(skin: skin, lang: lang)
                    settingsGearButton(skin: skin, lang: lang)
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

    /// Shared chrome for header icon buttons (timer/clock + gear).
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

    private func settingsGearButton(skin: GTPhaseSkin, lang: GTAppLanguage) -> some View {
        Button {
            showSettings = true
        } label: {
            Image(systemName: "gearshape")
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
        .accessibilityLabel(GTCopy.a11ySettings(lang))
    }

    /// Writes effective language mirror + compass map flag for Watch; does **not** overwrite the user’s language preference key.
    private func publishCompanionSyncAndReloadWidgets() {
        let effective = GTAppLanguage.phoneDisplayLanguage(preferenceRaw: langPreferenceRaw)
        GTAppGroup.shared.set(effective.rawValue, forKey: GTAppLanguage.effectiveMirrorKey)
        GTAppGroup.shared.set(compassShowsMapBase, forKey: GTCompanionUISync.showCompassMapBaseKey)
        GTWatchConnectivitySync.shared.pushPhoneState(
            languagePreferenceRaw: langPreferenceRaw,
            effectiveLanguageRaw: effective.rawValue,
            twilightModeRaw: twilightModeRaw,
            mapCameraDistance: mapCameraDistanceStorage
        )
        model.syncContentLanguageWithAppPreference()
        WidgetCenter.shared.reloadTimelines(ofKind: GTIOWidgetKind.twilight)
    }
}
