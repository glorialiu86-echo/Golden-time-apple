import Combine
import GoldenTimeCore
import SwiftUI

struct GoldenTimeWatchRootView: View {
    @StateObject private var model = GoldenTimeWatchViewModel()
    /// Drive clock / engine ticks without `TimelineView` (watchOS Simulator has been observed stuck on the launch screen with periodic Timeline + TabView).
    @State private var tickNow = Date()
    @AppStorage(GTAppLanguage.storageKey, store: GTAppGroup.shared) private var langStorageRaw: String = ""
    @AppStorage(GTTwilightDisplayMode.storageKey, store: GTAppGroup.shared) private var twilightModeRaw: String = GTTwilightDisplayMode.clockTimes.rawValue

    private var lang: GTAppLanguage {
        GTAppLanguage.fromStorageRaw(langStorageRaw)
    }

    private var twilightUsesClockTimes: Bool {
        twilightModeRaw != GTTwilightDisplayMode.countdown.rawValue
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
            TabView {
                watchTwilightPage(skin: skin, now: tickNow)
                watchCompassPage(skin: skin)
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in
            tickNow = date
            model.refreshForTimeline(now: date)
        }
        .onAppear {
            GTAppGroup.migrateStandardToSharedIfNeeded()
            model.syncContentLanguageWithStorage()
            model.refreshForTimeline(now: tickNow)
        }
        .task {
            model.startLocationPipeline()
        }
        .onChange(of: langStorageRaw) { _, _ in
            model.syncContentLanguageWithStorage()
        }
        .onChange(of: twilightModeRaw) { _, _ in
            model.objectWillChange.send()
        }
    }

    @ViewBuilder
    private func watchTwilightPage(skin: GTPhaseSkin, now: Date) -> some View {
        ScrollView {
            VStack(alignment: .center, spacing: 10) {
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
                            .font(.caption2.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(skin.muted)
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
                        .foregroundStyle(skin.muted)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
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
            if let coord = model.mapCoordinate {
                GeometryReader { geo in
                    let side = min(geo.size.width, geo.size.height)
                    TwilightCompassCard(
                        showMapBase: false,
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
            } else {
                Text(GTCopy.compassCardNeedLocation(lang))
                    .font(.caption)
                    .foregroundStyle(skin.muted)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
        .accessibilityIdentifier("gt.watch.compassPage")
    }
}
