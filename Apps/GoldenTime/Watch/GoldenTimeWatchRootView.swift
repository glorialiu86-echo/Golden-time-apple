import Combine
import GoldenTimeCore
import OSLog
import SwiftUI

struct GoldenTimeWatchRootView: View {
    private enum WatchPage: Hashable {
        case twilight
        case compass
    }

    private static let performanceLog = Logger(subsystem: GTPerformanceLog.subsystem, category: "WatchLaunch")

    @StateObject private var model = GoldenTimeWatchViewModel()
    /// Drive clock / engine ticks without `TimelineView` (watchOS Simulator has been observed stuck on the launch screen with periodic Timeline + TabView).
    @State private var tickNow: Date = {
        #if DEBUG
        GTDebugLaunchOverrides.currentDate()
        #else
        Date()
        #endif
    }()
    @AppStorage(GTAppLanguage.storageKey, store: GTAppGroup.shared) private var langPreferenceRaw: String =
        GTAppLanguage.followSystemStorageValue
    @AppStorage(GTAppLanguage.effectiveMirrorKey, store: GTAppGroup.shared) private var langEffectiveMirrorRaw: String = ""
    @AppStorage(GTTwilightDisplayMode.storageKey, store: GTAppGroup.shared) private var twilightModeRaw: String = GTTwilightDisplayMode.clockTimes.rawValue
    /// Written on iPhone; avoids a separate reachability check on Watch.
    @AppStorage(GTCompanionUISync.showCompassMapBaseKey, store: GTAppGroup.shared) private var companionShowCompassMapBase = true
    @State private var selectedPage: WatchPage = .twilight
    @State private var hasVisitedCompassPage = false
    @State private var hasCompletedCompassWarmup = false
    @State private var isCompassPagePresentationReady = false
    @State private var compassPageActivationTask: Task<Void, Never>?
    @State private var hasBootstrapped = false
    @State private var bootstrapScheduledUptime: TimeInterval?
    @State private var loggedFirstTwilightRenderable = false
    @State private var loggedFirstCompassRenderable = false
    @State private var showCompassCalibration = false

    private var lang: GTAppLanguage {
        GTAppLanguage.watchResolved(
            preferenceRaw: langPreferenceRaw,
            effectiveMirrorRaw: langEffectiveMirrorRaw
        )
    }

    private var twilightUsesClockTimes: Bool {
        twilightModeRaw != GTTwilightDisplayMode.countdown.rawValue
    }

    private var compassShowsMapBase: Bool {
        companionShowCompassMapBase
    }

    private func currentNow() -> Date {
        #if DEBUG
        GTDebugLaunchOverrides.currentDate()
        #else
        Date()
        #endif
    }

    var body: some View {
        let skin = GTPhaseSkin(phase: model.phase)
        let pageGradient = LinearGradient(
            colors: [skin.upper, skin.lower],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        NavigationStack {
            ZStack {
                pageGradient
                    .ignoresSafeArea()
                TabView(selection: $selectedPage) {
                    watchTwilightPage(skin: skin, now: tickNow)
                        .tag(WatchPage.twilight)
                    watchCompassPage(skin: skin)
                        .tag(WatchPage.compass)
                }
                .tabViewStyle(.verticalPage)
            }
            .navigationDestination(isPresented: $showCompassCalibration) {
                GTWatchCompassCalibrationView(model: model, lang: lang)
            }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in
            let now = currentNow()
            tickNow = now
            model.refreshForTimeline(now: now)
        }
        .onAppear {
            tickNow = currentNow()
            model.syncContentLanguageWithStorage()
            model.refreshForTimeline(now: tickNow)
        }
        .task {
            guard !hasBootstrapped else { return }
            hasBootstrapped = true
            bootstrapScheduledUptime = GTPerfTrace.uptime()
            GTPerfTrace.mark(Self.performanceLog, "watch bootstrap scheduled")
            await Task.yield()
            GTAppGroup.migrateStandardToSharedIfNeeded()
            GTWatchConnectivitySync.shared.activate()
            model.syncContentLanguageWithStorage()
            model.refreshForTimeline(now: tickNow)
            model.startLocationPipeline()
            GTPerfTrace.mark(
                Self.performanceLog,
                "watch bootstrap finished after \(GTPerfTrace.milliseconds(since: bootstrapScheduledUptime))"
            )
        }
        .onChange(of: model.mapCoordinate != nil) { _, hasCoordinate in
            guard hasCoordinate, !loggedFirstTwilightRenderable else { return }
            loggedFirstTwilightRenderable = true
            GTPerfTrace.mark(
                Self.performanceLog,
                "watch first twilight-page content visible after \(GTPerfTrace.milliseconds(since: bootstrapScheduledUptime))"
            )
            guard hasVisitedCompassPage, !loggedFirstCompassRenderable else { return }
            loggedFirstCompassRenderable = true
            GTPerfTrace.mark(
                Self.performanceLog,
                "watch compass page became renderable after \(GTPerfTrace.milliseconds(since: bootstrapScheduledUptime))"
            )
        }
        .onChange(of: langPreferenceRaw) { _, _ in
            model.syncContentLanguageWithStorage()
        }
        .onChange(of: langEffectiveMirrorRaw) { _, _ in
            model.syncContentLanguageWithStorage()
        }
        .onChange(of: twilightModeRaw) { _, _ in
            model.objectWillChange.send()
        }
        .onChange(of: selectedPage) { _, page in
            let isCompassPage = page == .compass
            if isCompassPage, !hasVisitedCompassPage {
                hasVisitedCompassPage = true
                GTPerfTrace.mark(
                    Self.performanceLog,
                    "watch compass page first mounted after \(GTPerfTrace.milliseconds(since: bootstrapScheduledUptime))"
                )
                if model.mapCoordinate != nil, !loggedFirstCompassRenderable {
                    loggedFirstCompassRenderable = true
                    GTPerfTrace.mark(
                        Self.performanceLog,
                        "watch compass page became renderable after \(GTPerfTrace.milliseconds(since: bootstrapScheduledUptime))"
                    )
                }
            }
            if isCompassPage {
                activateCompassPageIfNeeded()
            } else {
                compassPageActivationTask?.cancel()
                model.setCompassPageActive(false)
            }
        }
    }

    @ViewBuilder
    private func watchTwilightPage(skin: GTPhaseSkin, now: Date) -> some View {
        GeometryReader { geo in
            VStack(alignment: .center, spacing: 10) {
                Spacer(minLength: 0)
                if model.mapCoordinate != nil {
                    VStack(spacing: 8) {
                        if model.blueTwilightFirst {
                            watchTwilightCard(skin: skin, blue: true, now: now)
                            watchTwilightCard(skin: skin, blue: false, now: now)
                        } else {
                            watchTwilightCard(skin: skin, blue: false, now: now)
                            watchTwilightCard(skin: skin, blue: true, now: now)
                        }
                        Text("\(GTCopy.watchCoordinatesPrefix(lang))\(model.latitudeText), \(model.longitudeText)")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(skin.chromeSecondaryForeground)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                            .accessibilityIdentifier("gt.watch.compassCoordinates")
                    }
                } else {
                    Text(GTCopy.compassCardNeedLocation(lang))
                        .font(.caption)
                        .foregroundStyle(skin.chromeSecondaryForeground)
                        .multilineTextAlignment(.center)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            .frame(width: geo.size.width, height: geo.size.height)
            .accessibilityIdentifier("gt.watch.twilightPage")
        }
    }

    @ViewBuilder
    private func watchTwilightCard(skin: GTPhaseSkin, blue: Bool, now: Date) -> some View {
        GoldenTimeTwilightWindowCard(
            skin: skin,
            title: blue ? GTCopy.blueHourTitle(lang) : GTCopy.goldenHourTitle(lang),
            systemImage: blue ? "moon.stars.fill" : "sun.horizon.fill",
            blue: blue,
            useClockTimes: twilightUsesClockTimes,
            window: blue ? model.blueWindowRange : model.goldenWindowRange,
            clockStart: blue ? model.blueStartText : model.goldenStartText,
            clockEnd: blue ? model.blueEndText : model.goldenEndText,
            now: now,
            lang: lang,
            metrics: .watch
        )
    }

    @ViewBuilder
    private func watchCompassPage(skin: GTPhaseSkin) -> some View {
        Group {
            if !hasCompletedCompassWarmup || !isCompassPagePresentationReady {
                watchCompassLoadingShell(skin: skin)
            } else if let coord = model.mapCoordinate {
                ZStack(alignment: .bottom) {
                    GeometryReader { geo in
                        let span = min(geo.size.width, geo.size.height)
                        let side = max(span * 0.9, 1)
                        TwilightCompassCard(
                            showMapBase: compassShowsMapBase && isCompassPagePresentationReady,
                            chromeGradient: skin.chromeGradient,
                            compassInk: skin.ink,
                            compassStroke: skin.panelStroke,
                            chromeIsLight: skin.isLightChrome,
                            uiLanguage: lang,
                            coordinate: coord,
                            deviceHeadingDegrees: model.correctedHeadingDegrees ?? model.deviceHeadingDegrees,
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
                        .frame(width: side, height: side)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    Text(GTCopy.watchCompassCalibrationHint(lang))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(skin.chromeSecondaryForeground)
                        .padding(.bottom, 4)
                }
                .padding(.horizontal, -12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 1) {
                    showCompassCalibration = true
                }
            } else {
                Text(GTCopy.compassCardNeedLocation(lang))
                    .font(.caption)
                    .foregroundStyle(skin.chromeSecondaryForeground)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
        .accessibilityIdentifier("gt.watch.compassPage")
    }

    private func watchCompassLoadingShell(skin: GTPhaseSkin) -> some View {
        VStack {
            VStack(spacing: 12) {
                ProgressView()
                    .tint(skin.ink)
                    .scaleEffect(1.12)

                Text(GTCopy.compassInitialLoadingTitle(lang))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(skin.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                Text(GTCopy.compassInitialLoadingSubtitle(lang))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(skin.chromeSecondaryForeground)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.82)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [skin.upper.opacity(0.985), skin.lower.opacity(0.985)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(skin.panelStroke, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(skin.isLightChrome ? 0.08 : 0.22), radius: 10, y: 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func activateCompassPageIfNeeded() {
        compassPageActivationTask?.cancel()
        guard !hasCompletedCompassWarmup else {
            isCompassPagePresentationReady = true
            model.setCompassPageActive(true)
            return
        }

        isCompassPagePresentationReady = false
        compassPageActivationTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, selectedPage == .compass else { return }
            hasCompletedCompassWarmup = true
            isCompassPagePresentationReady = true
            model.setCompassPageActive(true)
        }
    }
}

private struct GTWatchCompassCalibrationView: View {
    @ObservedObject var model: GoldenTimeWatchViewModel
    let lang: GTAppLanguage

    var body: some View {
        let skin = GTPhaseSkin(phase: model.phase)
        ZStack {
            LinearGradient(
                colors: [skin.upper, skin.lower],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ZStack(alignment: .bottom) {
                if let coord = model.mapCoordinate {
                    GeometryReader { geo in
                        let side = max(min(geo.size.width + 18, geo.size.height - 22), 1)
                        TwilightCompassCard(
                            showMapBase: false,
                            chromeGradient: skin.chromeGradient,
                            compassInk: skin.ink,
                            compassStroke: skin.panelStroke,
                            chromeIsLight: skin.isLightChrome,
                            uiLanguage: lang,
                            coordinate: coord,
                            deviceHeadingDegrees: model.correctedHeadingDegrees ?? model.deviceHeadingDegrees,
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
                        .frame(width: side, height: side)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(.top, 4)
                } else {
                    Text(GTCopy.compassCardNeedLocation(lang))
                        .font(.caption)
                        .foregroundStyle(skin.chromeSecondaryForeground)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                HStack(spacing: 8) {
                    watchCalibrationButton(
                        title: GTCopy.compassCalibrationSave(lang),
                        background: Color(red: 0, green: 122 / 255, blue: 1),
                        foreground: .white,
                        isEnabled: model.canSaveCompassCalibration
                    ) {
                        _ = model.saveCompassCalibrationFromCurrentSunAlignment()
                    }

                    watchCalibrationButton(
                        title: GTCopy.settingsCompassCalibrationClear(lang),
                        background: Color.white.opacity(0.9),
                        foreground: Color(red: 88 / 255, green: 91 / 255, blue: 99 / 255),
                        isEnabled: model.hasCompassCalibration
                    ) {
                        model.clearCompassCalibration()
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .navigationTitle(GTCopy.settingsCompassCalibrationTitle(lang))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func watchCalibrationButton(
        title: String,
        background: Color,
        foreground: Color,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundStyle(foreground.opacity(isEnabled ? 1 : 0.6))
                .background(
                    Capsule(style: .continuous)
                        .fill(background.opacity(isEnabled ? 1 : 0.55))
                )
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .disabled(!isEnabled)
    }
}
