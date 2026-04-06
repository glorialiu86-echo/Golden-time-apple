import Foundation
import GoldenTimeCore
import SwiftUI

#if DEBUG
private enum GTDebugTwilightMode {
    static let environmentKey = "GOLDEN_TIME_DEBUG_TWILIGHT_MODE"

    static var override: GTTwilightDisplayMode? {
        guard let raw = ProcessInfo.processInfo.environment[environmentKey] else { return nil }
        return GTTwilightDisplayMode(rawValue: raw)
    }
}
#endif

struct GoldenTimePhoneRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = GoldenTimePhoneViewModel()
    @StateObject private var networkReachability = NetworkReachability()
    @AppStorage(GTAppLanguage.storageKey, store: GTAppGroup.shared) private var langPreferenceRaw: String =
        GTAppLanguage.followSystemStorageValue
    @AppStorage(GTTwilightDisplayMode.storageKey, store: GTAppGroup.shared) private var twilightModeRaw: String = GTTwilightDisplayMode.clockTimes.rawValue
    @AppStorage(GTCompassMapSettings.storageKey, store: GTAppGroup.shared) private var mapCameraDistanceStorage: Double =
        GTCompassMapSettings.defaultCameraDistanceMeters
    @AppStorage("gt.phone.initialCompassOverlayShown") private var hasShownInitialCompassOverlay = false
    @State private var showSettings = false
    @State private var allowCompassMapBase = false
    @State private var hasBootstrapped = false
    @State private var needsForegroundResume = false
    @State private var companionSyncTask: Task<Void, Never>?
    @State private var startupSyncTask: Task<Void, Never>?
    @State private var hasUnlockedStartupSync = false
    @State private var needsDeferredCompanionSync = false
    @State private var showInitialCompassOverlay = false
    @State private var initialCompassOverlayTask: Task<Void, Never>?
    /// Bumps when `NSLocale.currentLocaleDidChangeNotification` fires so `uiLang` re-evaluates while preference is「跟随系统」.
    @State private var systemLocaleBump = UUID()

    private var uiLang: GTAppLanguage {
        let _ = systemLocaleBump
        return GTAppLanguage.phoneDisplayLanguage(preferenceRaw: langPreferenceRaw)
    }

    private var twilightUsesClockTimes: Bool {
        #if DEBUG
        if let override = GTDebugTwilightMode.override {
            return override != .countdown
        }
        #endif
        return twilightModeRaw != GTTwilightDisplayMode.countdown.rawValue
    }

    private var compassShowsMapBase: Bool {
        guard allowCompassMapBase else { return false }
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
                model.syncContentLanguageWithAppPreference()
                if !hasShownInitialCompassOverlay {
                    hasShownInitialCompassOverlay = true
                    showInitialCompassOverlay = true
                    if scenePhase == .active {
                        scheduleInitialCompassOverlayDismissal()
                    }
                }
            }
            .task {
                guard !hasBootstrapped else { return }
                hasBootstrapped = true
                await Task.yield()
                GTPhoneStartupSyncGate.isUnlocked = false
                hasUnlockedStartupSync = false
                needsDeferredCompanionSync = true
                model.syncContentLanguageWithAppPreference()
                model.beginForegroundLocationSession(requestImmediately: true)
                allowCompassMapBase = true
                if scenePhase == .active {
                    scheduleStartupSyncUnlock()
                }
                if showInitialCompassOverlay, scenePhase == .active {
                    scheduleInitialCompassOverlayDismissal()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in
                systemLocaleBump = UUID()
                model.syncContentLanguageWithAppPreference()
                requestCompanionSync()
            }
            .onChange(of: langPreferenceRaw) { _, _ in
                model.syncContentLanguageWithAppPreference()
                requestCompanionSync()
            }
            .onChange(of: twilightModeRaw) { _, _ in
                requestCompanionSync()
            }
            .onChange(of: mapCameraDistanceStorage) { _, _ in
                requestCompanionSync()
            }
            .onChange(of: networkReachability.hasNetworkRoute) { _, _ in
                requestCompanionSync()
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    if showInitialCompassOverlay {
                        scheduleInitialCompassOverlayDismissal()
                    }
                    if hasBootstrapped, !hasUnlockedStartupSync {
                        scheduleStartupSyncUnlock()
                    }
                    guard hasBootstrapped, needsForegroundResume else { return }
                    needsForegroundResume = false
                    model.beginForegroundLocationSession(requestImmediately: true)
                case .background:
                    initialCompassOverlayTask?.cancel()
                    startupSyncTask?.cancel()
                    needsForegroundResume = true
                    model.endForegroundLocationSession()
                    flushDeferredExternalSync()
                default:
                    initialCompassOverlayTask?.cancel()
                    startupSyncTask?.cancel()
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
        ZStack {
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
            } else {
                Text(GTCopy.compassCardNeedLocation(lang))
                    .font(.caption)
                    .foregroundStyle(skin.chromeSecondaryForeground)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 8)
            }
            if showInitialCompassOverlay {
                compassInitialLoadingOverlay(skin: skin, lang: lang)
            }
        }
        .frame(height: Self.compassDialHeight)
        .frame(maxWidth: .infinity)
    }

    private func compassInitialLoadingOverlay(skin: GTPhaseSkin, lang: GTAppLanguage) -> some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(skin.ink)
                .scaleEffect(1.08)

            Text(GTCopy.compassInitialLoadingTitle(lang))
                .font(.headline.weight(.semibold))
                .foregroundStyle(skin.ink)
                .multilineTextAlignment(.center)

            Text(GTCopy.compassInitialLoadingSubtitle(lang))
                .font(.caption)
                .foregroundStyle(skin.chromeSecondaryForeground)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(height: Self.compassDialHeight)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [skin.upper.opacity(0.985), skin.lower.opacity(0.985)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(skin.panelStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .allowsHitTesting(false)
        .zIndex(1)
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
        GTWatchConnectivitySync.shared.activate()
        GTWatchConnectivitySync.shared.pushPhoneState(
            languagePreferenceRaw: langPreferenceRaw,
            effectiveLanguageRaw: effective.rawValue,
            twilightModeRaw: twilightModeRaw,
            mapCameraDistance: mapCameraDistanceStorage
        )
        model.flushDeferredExternalOutputs()
    }

    private func scheduleCompanionSync() {
        companionSyncTask?.cancel()
        companionSyncTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            publishCompanionSyncAndReloadWidgets()
        }
    }

    private func requestCompanionSync() {
        if hasUnlockedStartupSync {
            scheduleCompanionSync()
        } else {
            needsDeferredCompanionSync = true
        }
    }

    private func scheduleStartupSyncUnlock() {
        startupSyncTask?.cancel()
        startupSyncTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            GTAppGroup.migrateStandardToSharedIfNeeded()
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            GTWatchConnectivitySync.shared.activate()
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            hasUnlockedStartupSync = true
            GTPhoneStartupSyncGate.isUnlocked = true
            flushDeferredExternalSync()
        }
    }

    private func flushDeferredExternalSync() {
        guard needsDeferredCompanionSync || model.hasDeferredExternalOutputs else { return }
        publishCompanionSyncAndReloadWidgets()
        needsDeferredCompanionSync = false
    }

    private func scheduleInitialCompassOverlayDismissal() {
        initialCompassOverlayTask?.cancel()
        initialCompassOverlayTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            showInitialCompassOverlay = false
        }
    }
}
