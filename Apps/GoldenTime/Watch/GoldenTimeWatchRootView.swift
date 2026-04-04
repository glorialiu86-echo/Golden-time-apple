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
                        watchSkyBodyAzimuthRow(skin: skin)
                    }
                } else {
                    Text(GTCopy.compassCardNeedLocation(lang))
                        .font(.caption)
                        .foregroundStyle(skin.muted)
                        .multilineTextAlignment(.center)
                }

                Text(model.locationHint)
                    .font(.caption2)
                    .foregroundStyle(skin.muted.opacity(0.9))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("gt.watch.twilightPage")
        }
    }

    /// Sun/moon true-north azimuth (same offline engine as the compass page); compact row on the twilight tab.
    @ViewBuilder
    private func watchSkyBodyAzimuthRow(skin: GTPhaseSkin) -> some View {
        if model.compassSunBodyAzimuthDegrees != nil || model.compassMoonBodyAzimuthDegrees != nil {
            HStack(spacing: 12) {
                if let deg = model.compassSunBodyAzimuthDegrees {
                    HStack(spacing: 4) {
                        Image(systemName: "sun.max.fill")
                            .foregroundStyle(Self.skyBodySunColor(chromeIsLight: skin.isLightChrome))
                        Text(Self.displayAzimuthDegrees(deg))
                            .foregroundStyle(skin.ink)
                            .monospacedDigit()
                    }
                }
                if let deg = model.compassMoonBodyAzimuthDegrees {
                    HStack(spacing: 4) {
                        Image(systemName: "moon.fill")
                            .foregroundStyle(Self.skyBodyMoonColor(chromeIsLight: skin.isLightChrome))
                        Text(Self.displayAzimuthDegrees(deg))
                            .foregroundStyle(skin.ink)
                            .monospacedDigit()
                    }
                }
            }
            .font(.caption2.weight(.medium))
            .padding(.top, 4)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("gt.watch.sunMoonAzimuthRow")
        }
    }

    private static func displayAzimuthDegrees(_ deg: Double) -> String {
        var v = deg.truncatingRemainder(dividingBy: 360)
        if v < 0 { v += 360 }
        return "\(Int(v.rounded()))°"
    }

    private static func skyBodySunColor(chromeIsLight: Bool) -> Color {
        chromeIsLight
            ? Color(red: 0.96, green: 0.52, blue: 0.02)
            : Color(red: 1.0, green: 0.78, blue: 0.06)
    }

    private static func skyBodyMoonColor(chromeIsLight: Bool) -> Color {
        chromeIsLight
            ? Color(red: 0.22, green: 0.32, blue: 0.72)
            : Color(red: 0.93, green: 0.95, blue: 1.0)
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
                VStack(spacing: 4) {
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)
                    Text("\(GTCopy.watchCoordinatesPrefix(lang))\(model.latitudeText), \(model.longitudeText)")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(skin.muted)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.65)
                        .accessibilityIdentifier("gt.watch.compassCoordinates")
                }
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
