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
    @State private var tickNow = Date()
    @AppStorage(GTAppLanguage.storageKey, store: GTAppGroup.shared) private var langPreferenceRaw: String =
        GTAppLanguage.followSystemStorageValue
    @AppStorage(GTAppLanguage.effectiveMirrorKey, store: GTAppGroup.shared) private var langEffectiveMirrorRaw: String = ""
    @AppStorage(GTTwilightDisplayMode.storageKey, store: GTAppGroup.shared) private var twilightModeRaw: String = GTTwilightDisplayMode.clockTimes.rawValue
    /// Written on iPhone; avoids a separate reachability check on Watch.
    @AppStorage(GTCompanionUISync.showCompassMapBaseKey, store: GTAppGroup.shared) private var companionShowCompassMapBase = true
    @State private var selectedPage: WatchPage = .twilight
    @State private var hasVisitedCompassPage = false
    @State private var hasBootstrapped = false

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

    var body: some View {
        let skin = GTPhaseSkin(phase: model.phase)
        let pageGradient = LinearGradient(
            colors: [skin.upper, skin.lower],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in
            tickNow = date
            model.refreshForTimeline(now: date)
        }
        .onAppear {
            model.syncContentLanguageWithStorage()
            model.refreshForTimeline(now: tickNow)
        }
        .task {
            guard !hasBootstrapped else { return }
            hasBootstrapped = true
            Self.performanceLog.notice("watch bootstrap scheduled")
            await Task.yield()
            GTAppGroup.migrateStandardToSharedIfNeeded()
            GTWatchConnectivitySync.shared.activate()
            model.syncContentLanguageWithStorage()
            model.refreshForTimeline(now: tickNow)
            model.startLocationPipeline()
            Self.performanceLog.notice("watch bootstrap finished")
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
                Self.performanceLog.notice("watch compass page first mounted")
            }
            model.setCompassPageActive(isCompassPage)
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
            if hasVisitedCompassPage, let coord = model.mapCoordinate {
                GeometryReader { geo in
                    let span = min(geo.size.width, geo.size.height)
                    let side = max(span * 0.9, 1)
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
                    .frame(width: side, height: side)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.horizontal, -12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
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
}
