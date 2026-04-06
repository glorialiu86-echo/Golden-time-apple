import CoreLocation
import GoldenTimeCore
import SwiftUI
#if os(iOS) || os(watchOS)
import MapKit
#endif

// MARK: - Map (iOS: MKMapView + zoom rail; watch: SwiftUI Map, distance synced via App Group)

#if os(iOS) || os(watchOS)
/// Shared camera limits with iOS `MKMapCamera` / watch `MapCamera`; default matches `GTCompassMapSettings`.
private enum CompassMapCamera {
    static let defaultDistance: CLLocationDistance = 980
    static let minDistance: CLLocationDistance = 120
    static let maxDistance: CLLocationDistance = 18_000
}

/// Map disk sizing only; compass `Canvas` is unchanged.
private enum CompassMapFrame {
    static func outerRimDiameter(side: CGFloat) -> CGFloat {
        let outerR = side / 2 - 20
        return 2 * outerR * 0.985
    }

    /// Map slightly inside rim-synced diameter (inset ~5 pt on radius). No other layout changes.
    static func mapDiskDiameter(side: CGFloat) -> CGFloat {
        max(outerRimDiameter(side: side) - 10, 1)
    }
}

/// Apple Maps in mainland China uses GCJ-02-style display coordinates; keep astro math on raw GPS and shift only the basemap camera.
private enum CompassMapDisplayCoordinate {
    private static let earthSemiMajorAxis = 6_378_245.0
    private static let eccentricitySquared = 0.006_693_421_622_965_943_23

    static func adjusted(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard CLLocationCoordinate2DIsValid(coordinate), isInMainlandChina(coordinate) else { return coordinate }
        let delta = offset(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return CLLocationCoordinate2D(
            latitude: coordinate.latitude + delta.latitude,
            longitude: coordinate.longitude + delta.longitude
        )
    }

    private static func isInMainlandChina(_ coordinate: CLLocationCoordinate2D) -> Bool {
        let lat = coordinate.latitude
        let lon = coordinate.longitude
        guard lon >= 72.004, lon <= 137.8347, lat >= 0.8293, lat <= 55.8271 else { return false }
        if lon >= 113.8, lon <= 114.5, lat >= 22.1, lat <= 22.6 { return false } // Hong Kong
        if lon >= 113.4, lon <= 113.7, lat >= 22.0, lat <= 22.3 { return false } // Macau
        if lon >= 119.0, lon <= 122.1, lat >= 21.8, lat <= 25.4 { return false } // Taiwan
        return true
    }

    private static func offset(latitude: Double, longitude: Double) -> (latitude: Double, longitude: Double) {
        let x = longitude - 105.0
        let y = latitude - 35.0
        let dLat = transformLatitude(x: x, y: y)
        let dLon = transformLongitude(x: x, y: y)
        let radLat = latitude / 180.0 * .pi
        let magic = 1.0 - eccentricitySquared * pow(sin(radLat), 2)
        let sqrtMagic = sqrt(magic)
        let latOffset = (dLat * 180.0) /
            ((earthSemiMajorAxis * (1.0 - eccentricitySquared)) / (magic * sqrtMagic) * .pi)
        let lonOffset = (dLon * 180.0) / (earthSemiMajorAxis / sqrtMagic * cos(radLat) * .pi)
        return (latOffset, lonOffset)
    }

    private static func transformLatitude(x: Double, y: Double) -> Double {
        var result = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
        result += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
        result += (20.0 * sin(y * .pi) + 40.0 * sin(y / 3.0 * .pi)) * 2.0 / 3.0
        result += (160.0 * sin(y / 12.0 * .pi) + 320.0 * sin(y * .pi / 30.0)) * 2.0 / 3.0
        return result
    }

    private static func transformLongitude(x: Double, y: Double) -> Double {
        var result = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
        result += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
        result += (20.0 * sin(x * .pi) + 40.0 * sin(x / 3.0 * .pi)) * 2.0 / 3.0
        result += (150.0 * sin(x / 12.0 * .pi) + 300.0 * sin(x / 30.0 * .pi)) * 2.0 / 3.0
        return result
    }
}
#endif

#if os(iOS)
private struct CompassMapUnderlay: UIViewRepresentable {
    @Binding var mapTilesReady: Bool
    var coordinate: CLLocationCoordinate2D
    /// True north clockwise; drives map rotation to match overlay geometry.
    var headingDegrees: Double
    /// Ground distance from camera to center (m); larger ⇒ more zoomed out.
    var cameraDistance: CLLocationDistance
    /// `true` when phase skin is dark (night / blue / golden) → MapKit uses dark standard tiles; matches light compass ring inks.
    var useDarkMapAppearance: Bool

    final class Coordinator: NSObject, MKMapViewDelegate {
        var mapTilesReady: Binding<Bool>

        init(mapTilesReady: Binding<Bool>) {
            self.mapTilesReady = mapTilesReady
        }

        /// `fullyRendered == true` is the closest signal MapKit offers that raster tiles finished drawing.
        func mapViewDidFinishRenderingMap(_ mapView: MKMapView, fullyRendered: Bool) {
            guard fullyRendered else { return }
            mapTilesReady.wrappedValue = true
        }

        func mapViewDidFailLoadingMap(_ mapView: MKMapView, withError error: Error) {
            mapTilesReady.wrappedValue = false
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(mapTilesReady: $mapTilesReady)
    }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.isUserInteractionEnabled = false
        map.mapType = .standard
        map.pointOfInterestFilter = .excludingAll
        map.showsUserLocation = false
        map.showsCompass = false
        map.showsScale = false
        map.isPitchEnabled = false
        map.isZoomEnabled = false
        map.isScrollEnabled = false
        map.isRotateEnabled = false
        map.clipsToBounds = true
        if #available(iOS 13.0, *) {
            map.overrideUserInterfaceStyle = useDarkMapAppearance ? .dark : .unspecified
            let z = MKMapView.CameraZoomRange(
                minCenterCoordinateDistance: CompassMapCamera.minDistance,
                maxCenterCoordinateDistance: CompassMapCamera.maxDistance
            )
            map.setCameraZoomRange(z, animated: false)
        }
        return map
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        if #available(iOS 13.0, *) {
            mapView.overrideUserInterfaceStyle = useDarkMapAppearance ? .dark : .unspecified
        }
        guard CLLocationCoordinate2DIsValid(coordinate) else { return }
        let displayCoordinate = CompassMapDisplayCoordinate.adjusted(coordinate)
        let d = cameraDistance.clamped(
            to: CompassMapCamera.minDistance ... CompassMapCamera.maxDistance
        )
        let cam = MKMapCamera(
            lookingAtCenter: displayCoordinate,
            fromDistance: d,
            pitch: 0,
            heading: headingDegrees
        )
        mapView.setCamera(cam, animated: false)
    }
}

/// Vertical drag: top ⇒ zoom in (near), bottom ⇒ zoom out (far); spacing uses log scale between min/max distance.
/// Kept visually light: hairline track + small knob so it doesn’t read as a solid bar beside the dial.
private struct CompassMapZoomRail: View {
    @Binding var cameraDistance: CLLocationDistance
    /// `true` after MapKit reports a fully rendered frame; `false` disables drag and grays the knob.
    var mapTilesReady: Bool
    /// Matches compass chrome; drives subtle track/knob contrast.
    var chromeIsLight: Bool
    var a11yZoomLabel: String
    var a11yMapNotReadyHint: String

    private var dMin: CLLocationDistance { CompassMapCamera.minDistance }
    private var dMax: CLLocationDistance { CompassMapCamera.maxDistance }

    private var trackLineColor: Color {
        chromeIsLight ? Color.black.opacity(0.11) : Color.white.opacity(0.22)
    }

    private var knobFill: Color {
        if !mapTilesReady {
            return chromeIsLight ? Color(white: 0.78) : Color(white: 0.42)
        }
        return chromeIsLight ? Color.white.opacity(0.94) : Color.white.opacity(0.32)
    }

    private var knobStroke: Color {
        if !mapTilesReady {
            return chromeIsLight ? Color.black.opacity(0.12) : Color.white.opacity(0.22)
        }
        return chromeIsLight ? Color.black.opacity(0.14) : Color.white.opacity(0.42)
    }

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let w = geo.size.width
            let knobD: CGFloat = 11
            let travel = max(h - knobD, 1)
            let tNow = Self.normalizedT(for: cameraDistance, dMin: dMin, dMax: dMax)
            let thumbY = CGFloat(tNow) * travel

            ZStack(alignment: .top) {
                Capsule()
                    .fill(trackLineColor)
                    .frame(width: 1.5, height: h)
                    .frame(maxWidth: .infinity)

                Circle()
                    .fill(knobFill)
                    .overlay(Circle().stroke(knobStroke, lineWidth: 0.75))
                    .frame(width: knobD, height: knobD)
                    .shadow(color: Color.black.opacity(mapTilesReady ? (chromeIsLight ? 0.06 : 0.2) : 0.03), radius: 1.5, x: 0, y: 0.5)
                    .offset(y: thumbY)
            }
            .frame(width: w, height: h)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        guard mapTilesReady else { return }
                        let y = min(max(g.location.y - knobD / 2, 0), travel)
                        let t = Double(y / travel)
                        cameraDistance = Self.distance(forNormalizedT: t, dMin: dMin, dMax: dMax)
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(a11yZoomLabel))
            .accessibilityValue(Text(mapTilesReady ? String(format: "%.0f m", cameraDistance) : a11yMapNotReadyHint))
            .accessibilityAdjustableAction { direction in
                guard mapTilesReady else { return }
                switch direction {
                case .increment:
                    cameraDistance = Self.nudgeDistance(cameraDistance, inward: false, dMin: dMin, dMax: dMax)
                case .decrement:
                    cameraDistance = Self.nudgeDistance(cameraDistance, inward: true, dMin: dMin, dMax: dMax)
                @unknown default:
                    break
                }
            }
        }
    }

    /// 0 = zoomed in (min d), 1 = zoomed out (max d).
    private static func normalizedT(for d: CLLocationDistance, dMin: CLLocationDistance, dMax: CLLocationDistance) -> Double {
        let ln = log(dMin)
        let lx = log(dMax)
        let lv = log(max(dMin, min(dMax, d)))
        guard lx > ln else { return 0 }
        return max(0, min(1, (lv - ln) / (lx - ln)))
    }

    private static func distance(forNormalizedT t: Double, dMin: CLLocationDistance, dMax: CLLocationDistance) -> CLLocationDistance {
        let tt = max(0, min(1, t))
        let ln = log(dMin)
        let lx = log(dMax)
        return exp(ln + tt * (lx - ln))
    }

    private static func nudgeDistance(
        _ d: CLLocationDistance,
        inward: Bool,
        dMin: CLLocationDistance,
        dMax: CLLocationDistance
    ) -> CLLocationDistance {
        let t = normalizedT(for: d, dMin: dMin, dMax: dMax)
        let step = 0.08
        let next = inward ? t - step : t + step
        return distance(forNormalizedT: next, dMin: dMin, dMax: dMax)
    }
}
#endif

#if os(iOS) || os(watchOS)
private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
#endif

#if os(watchOS)
/// Non-interactive map disk; camera distance comes from App Group (written on iPhone).
private struct WatchCompassMapUnderlay: View {
    @Binding var mapTilesReady: Bool
    var coordinate: CLLocationCoordinate2D
    var headingDegrees: Double
    var cameraDistance: CLLocationDistance
    var useDarkMapAppearance: Bool

    @State private var cameraPosition: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $cameraPosition, interactionModes: [])
            .mapStyle(.standard(elevation: .flat))
            .mapControlVisibility(.hidden)
            .environment(\.colorScheme, useDarkMapAppearance ? .dark : .light)
            .onAppear {
                applyCamera()
                mapTilesReady = true
            }
            .onChange(of: headingDegrees) { _, _ in applyCamera() }
            .onChange(of: cameraDistance) { _, _ in applyCamera() }
            .onChange(of: coordinate.latitude) { _, _ in applyCamera() }
            .onChange(of: coordinate.longitude) { _, _ in applyCamera() }
    }

    private func applyCamera() {
        guard CLLocationCoordinate2DIsValid(coordinate) else { return }
        let displayCoordinate = CompassMapDisplayCoordinate.adjusted(coordinate)
        let d = cameraDistance.clamped(to: CompassMapCamera.minDistance ... CompassMapCamera.maxDistance)
        let cam = MapCamera(centerCoordinate: displayCoordinate, distance: d, heading: headingDegrees, pitch: 0)
        cameraPosition = .camera(cam)
    }
}
#endif

// MARK: - Public card

/// Circular **heading-up** compass: top of the disk = phone forward; optional `MapKit` basemap when `showMapBase`.
/// True-north **red glyph** pivots at center; optional degree ring + cardinals (localized). No system-style thick top heading bar.
struct TwilightCompassCard: View {
    var showMapBase: Bool
    var chromeGradient: [Color]
    /// Primary ink for NSEW labels and heading arrow (matches twilight cards).
    var compassInk: Color
    /// Arrow / label contrast stroke (e.g. `skin.panelStroke`).
    var compassStroke: Color
    /// `true` for day shell (light backdrop); `false` for night / blue / golden shells (light ink on dark).
    var chromeIsLight: Bool
    var uiLanguage: GTAppLanguage
    var coordinate: CLLocationCoordinate2D
    /// When `nil`, geometry assumes north-up (`0`) for simulator / no magnetometer.
    var deviceHeadingDegrees: Double?
    /// Each pair: sun azimuth at local-day clip start → end (may be empty, one, or several).
    var blueSectorArcAzimuths: [(Double, Double)]
    var goldenSectorArcAzimuths: [(Double, Double)]
    var blueSectorColors: [Color]
    var goldenSectorColors: [Color]
    /// When non-`nil`, fills the dial with translucent **day** / **night** wedges from sunrise→sunset geometry.
    var compassDayNight: CompassDayNightInput?
    var daySectorTint: Color
    var nightSectorTint: Color
    /// True-north sun azimuth when sun is up; `nil` hides the sun glyph.
    var sunBodyAzimuthDegrees: Double?
    /// True-north moon azimuth when moon is up; `nil` hides the moon glyph.
    var moonBodyAzimuthDegrees: Double?

    /// Synced via App Group (`GTCompassMapSettings`); iPhone zoom rail writes, watch reads the same scale.
    @AppStorage(GTCompassMapSettings.storageKey, store: GTAppGroup.shared) private var mapCameraDistanceStorage: Double =
        GTCompassMapSettings.defaultCameraDistanceMeters
    /// Set from `MKMapView` delegate when raster tiles finish rendering (best-effort); watch sets optimistically.
    @State private var mapTilesReady = false
    #if os(iOS)
    @State private var isMapPresentationReady = false
    @State private var frozenMapHeadingDegrees = 0.0
    #endif

    private var mapCameraDistanceValue: CLLocationDistance {
        let raw = mapCameraDistanceStorage
        guard raw.isFinite, raw > 0 else { return CompassMapCamera.defaultDistance }
        return CLLocationDistance(raw).clamped(to: CompassMapCamera.minDistance ... CompassMapCamera.maxDistance)
    }

    #if os(iOS)
    private var mapCameraDistanceBinding: Binding<CLLocationDistance> {
        Binding(
            get: { mapCameraDistanceValue },
            set: {
                mapCameraDistanceStorage = Double(
                    $0.clamped(to: CompassMapCamera.minDistance ... CompassMapCamera.maxDistance)
                )
            }
        )
    }
    #endif

    private var heading: Double {
        deviceHeadingDegrees ?? 0
    }

    #if os(iOS)
    private var effectiveMapHeading: Double {
        mapTilesReady ? heading : frozenMapHeadingDegrees
    }
    #endif

    private var shadowOpacity: Double {
        #if os(watchOS)
        return 0.12
        #else
        return 0.2
        #endif
    }

    private var shadowRadius: CGFloat {
        #if os(watchOS)
        return 4
        #else
        return 10
        #endif
    }

    private var shadowY: CGFloat {
        #if os(watchOS)
        return 2
        #else
        return 4
        #endif
    }

    @ViewBuilder
    private func gradientCompassDisk(side: CGFloat) -> some View {
        ZStack {
            LinearGradient(
                colors: chromeGradient.map { $0.opacity(0.92) },
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            compassFaceLayers(side: side, basemapBehindFace: false, chromeIsLight: chromeIsLight)
                .allowsHitTesting(false)
        }
    }

    var body: some View {
        GeometryReader { geo in
            #if os(iOS)
            let railW: CGFloat = showMapBase && isMapPresentationReady ? 15 : 0
            let railGap: CGFloat = showMapBase && isMapPresentationReady ? 6 : 0
            let side = min(geo.size.width - railW - railGap, geo.size.height)
            #else
            let side = min(geo.size.width, geo.size.height)
            #endif
            Group {
                #if os(iOS)
                if showMapBase, isMapPresentationReady {
                    let mapDiameter = CompassMapFrame.mapDiskDiameter(side: side)
                    let railH = min(side * 0.58, 172)
                    HStack(alignment: .center, spacing: railGap) {
                        ZStack {
                            CompassMapUnderlay(
                                mapTilesReady: $mapTilesReady,
                                coordinate: coordinate,
                                headingDegrees: effectiveMapHeading,
                                cameraDistance: mapCameraDistanceValue,
                                useDarkMapAppearance: !chromeIsLight
                            )
                            .frame(width: mapDiameter, height: mapDiameter)
                            .clipShape(Circle())
                            compassFaceLayers(side: side, basemapBehindFace: true, chromeIsLight: chromeIsLight)
                                .allowsHitTesting(false)
                        }
                        .frame(width: side, height: side)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, x: 0, y: shadowY)

                        CompassMapZoomRail(
                            cameraDistance: mapCameraDistanceBinding,
                            mapTilesReady: mapTilesReady,
                            chromeIsLight: chromeIsLight,
                            a11yZoomLabel: uiLanguage == .chinese ? "地图缩放" : "Map zoom",
                            a11yMapNotReadyHint: uiLanguage == .chinese ? "地图未加载" : "Map not loaded"
                        )
                        .frame(width: railW, height: railH)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    mapOffCompassBlock(side: side)
                }
                #else
                if showMapBase {
                    let mapDiameter = CompassMapFrame.mapDiskDiameter(side: side)
                    ZStack {
                        WatchCompassMapUnderlay(
                            mapTilesReady: $mapTilesReady,
                            coordinate: coordinate,
                            headingDegrees: heading,
                            cameraDistance: mapCameraDistanceValue,
                            useDarkMapAppearance: !chromeIsLight
                        )
                        .frame(width: mapDiameter, height: mapDiameter)
                        .clipShape(Circle())
                        compassFaceLayers(side: side, basemapBehindFace: true, chromeIsLight: chromeIsLight)
                            .allowsHitTesting(false)
                    }
                    .frame(width: side, height: side)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, x: 0, y: shadowY)
                } else {
                    gradientCompassDisk(side: side)
                        .frame(width: side, height: side)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, x: 0, y: shadowY)
                }
                #endif
            }
        }
        .aspectRatio(1, contentMode: .fit)
        #if os(iOS) || os(watchOS)
        .onChange(of: showMapBase) { _, isOn in
            if isOn {
                mapTilesReady = false
                #if os(iOS)
                frozenMapHeadingDegrees = heading
                #endif
            }
        }
        .onChange(of: chromeIsLight) { _, _ in
            if showMapBase {
                mapTilesReady = false
                #if os(iOS)
                frozenMapHeadingDegrees = heading
                #endif
            }
        }
        #if os(iOS)
        .onChange(of: mapTilesReady) { _, isReady in
            if isReady {
                frozenMapHeadingDegrees = heading
            }
        }
        .task(id: showMapBase) {
            guard showMapBase else {
                isMapPresentationReady = false
                return
            }
            await Task.yield()
            guard !Task.isCancelled else { return }
            isMapPresentationReady = true
        }
        #endif
        #endif
    }

    @ViewBuilder
    private func mapOffCompassBlock(side: CGFloat) -> some View {
        gradientCompassDisk(side: side)
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .clipShape(Circle())
            .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, x: 0, y: shadowY)
    }

    @ViewBuilder
    private func compassFaceLayers(side: CGFloat, basemapBehindFace: Bool, chromeIsLight: Bool) -> some View {
        ZStack {
            TwilightCompassDrawing(
                compassInk: compassInk,
                compassStroke: compassStroke,
                headingDegrees: heading,
                cardinals: GTCopy.compassCardinals(uiLanguage),
                basemapBehindFace: basemapBehindFace,
                chromeIsLight: chromeIsLight,
                compassDayNight: compassDayNight,
                daySectorTint: daySectorTint,
                nightSectorTint: nightSectorTint,
                blueSectorArcAzimuths: blueSectorArcAzimuths,
                goldenSectorArcAzimuths: goldenSectorArcAzimuths,
                blueSectorColors: blueSectorColors,
                goldenSectorColors: goldenSectorColors
            )
            .compositingGroup()

            CompassSkyBodyMarkers(
                side: side,
                headingDegrees: heading,
                sunAzimuthDegrees: sunBodyAzimuthDegrees,
                moonAzimuthDegrees: moonBodyAzimuthDegrees,
                chromeIsLight: chromeIsLight
            )

            CompassNeedleOverlay(side: side)
        }
        .frame(width: side, height: side)
    }
}

/// Screen angle (° clockwise from top) toward `geoAzimuth` with device `headingDegrees` (heading-up compass).
private func compassBodyScreenAngleDeg(geoAzimuth: Double, headingDegrees: Double) -> Double {
    var d = geoAzimuth - headingDegrees
    while d > 180 { d -= 360 }
    while d < -180 { d += 360 }
    return d
}

/// Live sun/moon direction from analytical alt/az (no network). Sun stays on the **outer** ring; moon sits **inward** between the center needle and the sun so tracks don’t stack.
private struct CompassSkyBodyMarkers: View {
    var side: CGFloat
    var headingDegrees: Double
    var sunAzimuthDegrees: Double?
    var moonAzimuthDegrees: Double?
    var chromeIsLight: Bool

    /// Sun ring — unchanged (do not move).
    private var sunRadius: CGFloat {
        #if os(watchOS)
        side * 0.28
        #else
        side * 0.29
        #endif
    }

    /// Moon ring — between center arrow and `sunRadius` (tighter than sun so both read without stacking).
    private var moonRadius: CGFloat {
        #if os(watchOS)
        side * 0.15
        #else
        side * 0.165
        #endif
    }

    /// Sun and moon use the **same** point size (sun metrics kept as the source of truth).
    private var bodyGlyphSize: CGFloat {
        #if os(watchOS)
        max(12, side * 0.10)
        #else
        max(15, side * 0.076)
        #endif
    }

    var body: some View {
        ZStack {
            if let sa = sunAzimuthDegrees {
                skyGlyph(systemName: "sun.max.fill", size: bodyGlyphSize, fill: sunFill)
                    .offset(offset(geoAzimuth: sa, radius: sunRadius))
            }
            if let ma = moonAzimuthDegrees {
                skyGlyph(systemName: "moon.fill", size: bodyGlyphSize, fill: moonFill)
                    .offset(offset(geoAzimuth: ma, radius: moonRadius))
            }
        }
        .frame(width: side, height: side)
        .allowsHitTesting(false)
    }

    /// Opaque, high-chroma fills so glyphs read on translucent compass wedges / map.
    private var sunFill: Color {
        chromeIsLight
            ? Color(red: 0.96, green: 0.52, blue: 0.02)
            : Color(red: 1.0, green: 0.78, blue: 0.06)
    }

    private var moonFill: Color {
        chromeIsLight
            ? Color(red: 0.22, green: 0.32, blue: 0.72)
            : Color(red: 0.93, green: 0.95, blue: 1.0)
    }

    private func offset(geoAzimuth: Double, radius: CGFloat) -> CGSize {
        let ang = compassBodyScreenAngleDeg(geoAzimuth: geoAzimuth, headingDegrees: headingDegrees)
        let rad = ang * .pi / 180
        return CGSize(width: CGFloat(sin(rad)) * radius, height: CGFloat(-cos(rad)) * radius)
    }

    private func skyGlyph(systemName: String, size: CGFloat, fill: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .foregroundStyle(fill)
    }
}

/// Fixed orientation indicator using Apple’s **SF Symbol** `location.north.fill` (same family as Maps / compass).
private struct CompassNeedleOverlay: View {
    var side: CGFloat

    var body: some View {
        ZStack {
            SystemNorthArrowGlyph(side: side)
                .shadow(color: .black.opacity(0.28), radius: 4, x: 0, y: 2)
        }
        .frame(width: side, height: side)
    }
}

/// Renders Apple’s `location.north.fill` (Maps / compass family) at compass scale.
/// Red–coral gradient: intentionally **not** the icon gold/orange (`sunCore` / `sunGlow`) so the needle doesn’t merge with golden sectors or cards.
private struct SystemNorthArrowGlyph: View {
    var side: CGFloat

    /// Slightly smaller than before so an inner moon marker can pass without overlapping the arrow when bearings align.
    private var glyphSize: CGFloat { side * 0.13 }

    private var arrowGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 1.0, green: 0.44, blue: 0.38),
                Color(red: 0.72, green: 0.14, blue: 0.16)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var body: some View {
        Image(systemName: "location.north.fill")
            .font(.system(size: glyphSize, weight: .bold, design: .rounded))
            .foregroundStyle(arrowGradient)
            .frame(width: side, height: side)
    }
}

// MARK: - Drawing (Canvas)

private struct TwilightCompassDrawing: View {
    var compassInk: Color
    var compassStroke: Color
    var headingDegrees: Double
    var cardinals: (n: String, e: String, s: String, w: String)
    var basemapBehindFace: Bool
    var chromeIsLight: Bool
    var compassDayNight: CompassDayNightInput?
    var daySectorTint: Color
    var nightSectorTint: Color
    var blueSectorArcAzimuths: [(Double, Double)]
    var goldenSectorArcAzimuths: [(Double, Double)]
    var blueSectorColors: [Color]
    var goldenSectorColors: [Color]

    /// Light basemap (day shell): dark ink for ticks / numerals on map tiles.
    private static let tickInkLightBasemap = Color(red: 0.06, green: 0.06, blue: 0.08)

    private struct FacePaints {
        var tickInk: Color
        /// East / South / West and 30° numerals (north uses `northRed` separately).
        var bezelLabelInk: Color
        var bezelLabelHalo: Color
        var northLabelHalo: Color
        var outerRimInk: Color
    }

    /// With map: **light shell** ⇒ light map tiles + dark ring; **dark shell** ⇒ dark MapKit + light ring (same ink for ticks and labels). No map: `compassInk` only.
    private static func facePaints(basemap: Bool, chromeIsLight: Bool, compassInk: Color, compassStroke: Color) -> FacePaints {
        if basemap {
            if chromeIsLight {
                let ink = tickInkLightBasemap
                return FacePaints(
                    tickInk: ink,
                    bezelLabelInk: ink,
                    bezelLabelHalo: Color.white.opacity(0.55),
                    northLabelHalo: Color.black.opacity(0.34),
                    outerRimInk: ink
                )
            }
            let ink = Color.white.opacity(0.94)
            return FacePaints(
                tickInk: ink,
                bezelLabelInk: ink,
                bezelLabelHalo: Color.black.opacity(0.48),
                northLabelHalo: Color.black.opacity(0.45),
                outerRimInk: ink
            )
        }
        let halo = compassStroke.opacity(0.42)
        return FacePaints(
            tickInk: compassInk,
            bezelLabelInk: compassInk,
            bezelLabelHalo: halo,
            northLabelHalo: halo,
            outerRimInk: compassInk
        )
    }

    var body: some View {
        Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: true) { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outerR = min(size.width, size.height) / 2 - 20
            let sectorR = outerR * 0.935
            let paints = Self.facePaints(
                basemap: basemapBehindFace,
                chromeIsLight: chromeIsLight,
                compassInk: compassInk,
                compassStroke: compassStroke
            )
            let northRed = Color(red: 0.92, green: 0.24, blue: 0.22)

            if !basemapBehindFace {
                drawInnerFace(context: &context, center: center, radius: outerR * 0.94, ink: compassInk)
            }

            drawDayNightSectors(
                context: &context,
                center: center,
                radius: sectorR,
                dayNight: compassDayNight,
                dayTint: daySectorTint,
                nightTint: nightSectorTint,
                goldenSectorArcAzimuths: goldenSectorArcAzimuths,
                blueSectorArcAzimuths: blueSectorArcAzimuths
            )

            for (g0, g1) in goldenSectorArcAzimuths {
                drawSector(
                    context: &context,
                    center: center,
                    radius: sectorR,
                    geoStart: g0,
                    geoEnd: g1,
                    colors: goldenSectorColors
                )
            }
            for (g0, g1) in blueSectorArcAzimuths {
                drawSector(
                    context: &context,
                    center: center,
                    radius: sectorR,
                    geoStart: g0,
                    geoEnd: g1,
                    colors: blueSectorColors
                )
            }

            drawDegreeTicks(context: &context, center: center, outerR: outerR, heading: headingDegrees, ink: paints.tickInk)
            drawBezelLabels(
                context: &context,
                center: center,
                outerR: outerR,
                heading: headingDegrees,
                eswAndDigitInk: paints.bezelLabelInk,
                eswAndDigitHalo: paints.bezelLabelHalo,
                northRed: northRed,
                northHalo: paints.northLabelHalo,
                cardinals: cardinals
            )

            drawOuterRim(context: &context, center: center, radius: outerR * 0.985, ink: paints.outerRimInk)
        }
    }

    private func drawDayNightSectors(
        context: inout GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        dayNight: CompassDayNightInput?,
        dayTint: Color,
        nightTint: Color,
        goldenSectorArcAzimuths: [(Double, Double)],
        blueSectorArcAzimuths: [(Double, Double)]
    ) {
        guard let dn = dayNight else { return }
        let rise = Self.screenAngleDeg(geoAzimuth: dn.sunriseAzimuthDegrees, heading: headingDegrees)
        let set = Self.screenAngleDeg(geoAzimuth: dn.sunsetAzimuthDegrees, heading: headingDegrees)
        let mid = Self.screenAngleDeg(geoAzimuth: dn.midDaySunAzimuthDegrees, heading: headingDegrees)
        guard let secs = Self.dayNightSectorsScreen(riseScreen: rise, setScreen: set, midScreen: mid) else { return }

        let twilightHoles = Self.twilightMinorArcsScreen(
            golden: goldenSectorArcAzimuths,
            blue: blueSectorArcAzimuths,
            heading: headingDegrees
        )

        let nightSweepEff = min(secs.nightSweep, 359.99)
        if nightSweepEff > 0.75 {
            let nightPieces = Self.subtractTwilightHolesFromClockwiseArc(
                baseStart: secs.nightStart,
                baseSweep: nightSweepEff,
                holes: twilightHoles
            )
            for piece in nightPieces where piece.sweep > 0.75 {
                drawTranslucentCompassWedge(
                    context: &context,
                    center: center,
                    radius: radius,
                    startScreenDeg: piece.start,
                    sweepDeg: piece.sweep,
                    tint: nightTint
                )
            }
        }

        let daySweepEff = min(secs.daySweep, 359.99)
        if daySweepEff > 0.75 {
            let dayPieces = Self.subtractTwilightHolesFromClockwiseArc(
                baseStart: secs.dayStart,
                baseSweep: daySweepEff,
                holes: twilightHoles
            )
            for piece in dayPieces where piece.sweep > 0.75 {
                drawTranslucentCompassWedge(
                    context: &context,
                    center: center,
                    radius: radius,
                    startScreenDeg: piece.start,
                    sweepDeg: piece.sweep,
                    tint: dayTint
                )
            }
        }
    }

    private func drawTranslucentCompassWedge(
        context: inout GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        startScreenDeg: Double,
        sweepDeg: Double,
        tint: Color
    ) {
        guard sweepDeg > 0.75 else { return }
        let clampedSweep = min(sweepDeg, 359.5)
        var path = sectorPathSweep(center: center, radius: radius, startDeg: startScreenDeg, sweepDeg: clampedSweep)
        context.fill(path, with: .color(tint.opacity(0.34)))
        path = sectorPathSweep(center: center, radius: radius, startDeg: startScreenDeg, sweepDeg: clampedSweep)
        context.stroke(path, with: .color(tint.opacity(0.55)), lineWidth: 1.25)
    }

    private func sectorPathSweep(center: CGPoint, radius: CGFloat, startDeg: Double, sweepDeg: Double) -> Path {
        guard abs(sweepDeg) >= 0.25 else { return Path() }
        let steps = max(8, min(72, Int(abs(sweepDeg) / 3) + 8))
        var p = Path()
        p.move(to: center)
        for i in 0 ... steps {
            let t = Double(i) / Double(steps)
            let deg = startDeg + sweepDeg * t
            let pt = Self.pointOnCircle(center: center, radius: radius, degFromTopCW: deg)
            if i == 0 {
                p.addLine(to: pt)
            } else {
                p.addLine(to: pt)
            }
        }
        p.closeSubpath()
        return p
    }

    private static func norm360(_ a: Double) -> Double {
        var x = a.truncatingRemainder(dividingBy: 360)
        if x < 0 { x += 360 }
        return x
    }

    private static func clockwiseDelta(from: Double, to: Double) -> Double {
        let d = norm360(to) - norm360(from)
        return d <= 0 ? d + 360 : d
    }

    /// Picks the daytime great-arc (contains midday sun bearing); returns paired night arc.
    private static func dayNightSectorsScreen(
        riseScreen: Double,
        setScreen: Double,
        midScreen: Double
    ) -> (dayStart: Double, daySweep: Double, nightStart: Double, nightSweep: Double)? {
        let r = norm360(riseScreen)
        let s = norm360(setScreen)
        let m = norm360(midScreen)
        let L = clockwiseDelta(from: r, to: s)
        if L < 0.25 { return nil }
        if L >= 359.75 {
            return (r, 360, r, 0)
        }
        let dMid = clockwiseDelta(from: r, to: m)
        let onCW = dMid <= L + 0.5
        let dayStart: Double
        let daySweep: Double
        if onCW {
            dayStart = r
            daySweep = L
        } else {
            dayStart = s
            daySweep = 360 - L
        }
        let nightStart = norm360(dayStart + daySweep)
        let nightSweep = 360 - daySweep
        return (dayStart, daySweep, nightStart, nightSweep)
    }

    /// Minor-arc wedges for blue/golden sectors (same convention as `sectorPath`), screen space.
    private static func twilightMinorArcsScreen(
        golden: [(Double, Double)],
        blue: [(Double, Double)],
        heading: Double
    ) -> [(start: Double, sweep: Double)] {
        var out: [(Double, Double)] = []
        for (g0, g1) in golden + blue {
            let s0 = screenAngleDeg(geoAzimuth: g0, heading: heading)
            let s1 = screenAngleDeg(geoAzimuth: g1, heading: heading)
            var delta = s1 - s0
            while delta > 180 { delta -= 360 }
            while delta < -180 { delta += 360 }
            let start: Double
            let sweep: Double
            if delta >= 0 {
                start = s0
                sweep = delta
            } else {
                start = s1
                sweep = -delta
            }
            if sweep > 0.5 {
                out.append((norm360(start), sweep))
            }
        }
        return out.map { (start: $0.0, sweep: $0.1) }
    }

    private static func angleOnClockwiseArc(angle: Double, arcStart: Double, arcSweep: Double) -> Bool {
        let a = norm360(angle)
        let s0 = norm360(arcStart)
        let span = clockwiseDelta(from: s0, to: a)
        return span >= -1e-4 && span <= arcSweep + 1e-3
    }

    /// Removes one clockwise hole from a clockwise base arc; returns 0…n remaining fragments.
    private static func subtractOneTwilightHoleFromClockwiseArc(
        baseStart: Double,
        baseSweep: Double,
        holeStart: Double,
        holeSweep: Double
    ) -> [(Double, Double)] {
        guard baseSweep > 0.5 else { return [] }
        guard holeSweep > 0.5 else { return [(baseStart, baseSweep)] }

        var cut: [Double] = [0, baseSweep]
        for b in [norm360(holeStart), norm360(holeStart + holeSweep)] {
            for k in -4 ... 6 {
                let t = b - baseStart + Double(k) * 360
                if t >= -1e-3 && t <= baseSweep + 1e-3 {
                    cut.append(min(baseSweep, max(0, t)))
                }
            }
        }
        cut.sort()
        var merged: [Double] = []
        for x in cut {
            if merged.isEmpty || abs(x - merged.last!) > 0.06 {
                merged.append(x)
            }
        }

        var fr: [(Double, Double)] = []
        var i = 0
        while i < merged.count - 1 {
            let t0 = merged[i]
            let t1 = merged[i + 1]
            let span = t1 - t0
            if span > 0.08 {
                let midT = (t0 + t1) / 2
                let midAngle = norm360(baseStart + midT)
                if !angleOnClockwiseArc(angle: midAngle, arcStart: holeStart, arcSweep: holeSweep) {
                    fr.append((baseStart + t0, span))
                }
            }
            i += 1
        }
        return fr
    }

    private static func subtractTwilightHolesFromClockwiseArc(
        baseStart: Double,
        baseSweep: Double,
        holes: [(start: Double, sweep: Double)]
    ) -> [(start: Double, sweep: Double)] {
        var pieces: [(Double, Double)] = [(baseStart, baseSweep)]
        for h in holes where h.sweep > 0.5 {
            pieces = pieces.flatMap { p in
                subtractOneTwilightHoleFromClockwiseArc(
                    baseStart: p.0,
                    baseSweep: p.1,
                    holeStart: h.start,
                    holeSweep: h.sweep
                )
            }
        }
        return pieces.map { (start: $0.0, sweep: $0.1) }
    }

    private func drawInnerFace(context: inout GraphicsContext, center: CGPoint, radius: CGFloat, ink: Color) {
        var circle = Path()
        circle.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        context.fill(circle, with: .color(ink.opacity(0.04)))
        context.stroke(circle, with: .color(ink.opacity(0.12)), lineWidth: 0.75)
    }

    private func drawOuterRim(context: inout GraphicsContext, center: CGPoint, radius: CGFloat, ink: Color) {
        var circle = Path()
        circle.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        context.stroke(circle, with: .color(ink.opacity(0.22)), lineWidth: 1)
    }

    private func drawDegreeTicks(context: inout GraphicsContext, center: CGPoint, outerR: CGFloat, heading: Double, ink: Color) {
        let tickEnd = outerR * 0.94
        let startMinor = outerR * 0.90
        let startTen = outerR * 0.875
        let startThirty = outerR * 0.855

        for d in 0 ..< 360 {
            let s = Self.screenAngleDeg(geoAzimuth: Double(d), heading: heading)
            let rad = CGFloat(s) * .pi / 180
            let ux = CGFloat(sin(rad))
            let uy = CGFloat(-cos(rad))
            let major = d % 30 == 0
            let ten = d % 10 == 0 && !major
            let inner: CGFloat = major ? startThirty : (ten ? startTen : startMinor)
            let w: CGFloat = major ? 1.35 : (ten ? 0.95 : 0.4)
            let opacity: Double = major ? 0.92 : (ten ? 0.72 : 0.32)
            var p = Path()
            p.move(to: CGPoint(x: center.x + inner * ux, y: center.y + inner * uy))
            p.addLine(to: CGPoint(x: center.x + tickEnd * ux, y: center.y + tickEnd * uy))
            context.stroke(p, with: .color(ink.opacity(opacity)), lineWidth: w)
        }
    }

    /// Every 30°: numeric labels 30, 60, …, 330; at 0/90/180/270 use 北/N (red) / 东/E / 南/S / 西/W instead of digits.
    private func drawBezelLabels(
        context: inout GraphicsContext,
        center: CGPoint,
        outerR: CGFloat,
        heading: Double,
        eswAndDigitInk: Color,
        eswAndDigitHalo: Color,
        northRed: Color,
        northHalo: Color,
        cardinals: (n: String, e: String, s: String, w: String)
    ) {
        let tickEnd = outerR * 0.94
        let labelR = tickEnd + 12
        let cardinalFont: CGFloat = cardinals.n == "北" ? 14 : 12.75
        let digitFont: CGFloat = 9.75

        for d in stride(from: 0, through: 330, by: 30) {
            let geo = Double(d)
            let s = Self.screenAngleDeg(geoAzimuth: geo, heading: heading)
            let rad = CGFloat(s) * .pi / 180
            let ux = CGFloat(sin(rad))
            let uy = CGFloat(-cos(rad))
            let pt = CGPoint(x: center.x + labelR * ux, y: center.y + labelR * uy)

            switch d {
            case 0:
                drawBezelGlyph(
                    context: &context,
                    label: cardinals.n,
                    at: pt,
                    fontSize: cardinalFont,
                    fill: northRed,
                    halo: northHalo,
                    fillOpacity: 1
                )
            case 90:
                drawBezelGlyph(
                    context: &context,
                    label: cardinals.e,
                    at: pt,
                    fontSize: cardinalFont,
                    fill: eswAndDigitInk,
                    halo: eswAndDigitHalo,
                    fillOpacity: 0.9
                )
            case 180:
                drawBezelGlyph(
                    context: &context,
                    label: cardinals.s,
                    at: pt,
                    fontSize: cardinalFont,
                    fill: eswAndDigitInk,
                    halo: eswAndDigitHalo,
                    fillOpacity: 0.9
                )
            case 270:
                drawBezelGlyph(
                    context: &context,
                    label: cardinals.w,
                    at: pt,
                    fontSize: cardinalFont,
                    fill: eswAndDigitInk,
                    halo: eswAndDigitHalo,
                    fillOpacity: 0.9
                )
            default:
                let halo = Text("\(d)")
                    .font(.system(size: digitFont, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(eswAndDigitHalo.opacity(0.72))
                context.draw(halo, at: CGPoint(x: pt.x + 0.45, y: pt.y + 0.45), anchor: .center)
                let t = Text("\(d)")
                    .font(.system(size: digitFont, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(eswAndDigitInk.opacity(0.82))
                context.draw(t, at: pt, anchor: .center)
            }
        }
    }

    private func drawBezelGlyph(
        context: inout GraphicsContext,
        label: String,
        at pt: CGPoint,
        fontSize: CGFloat,
        fill: Color,
        halo: Color,
        fillOpacity: Double
    ) {
        let haloLayer = Text(label)
            .font(.system(size: fontSize, weight: .bold, design: .rounded))
            .foregroundStyle(halo)
        context.draw(haloLayer, at: CGPoint(x: pt.x + 0.5, y: pt.y + 0.5), anchor: .center)
        let t = Text(label)
            .font(.system(size: fontSize, weight: .bold, design: .rounded))
            .foregroundStyle(fill.opacity(fillOpacity))
        context.draw(t, at: pt, anchor: .center)
    }

    private func drawSector(
        context: inout GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        geoStart: Double,
        geoEnd: Double,
        colors: [Color]
    ) {
        let g0 = geoStart
        let g1 = geoEnd
        let s0 = Self.screenAngleDeg(geoAzimuth: g0, heading: headingDegrees)
        let s1 = Self.screenAngleDeg(geoAzimuth: g1, heading: headingDegrees)
        var path = sectorPath(center: center, radius: radius, startDeg: s0, endDeg: s1)
        let mid = colors.indices.contains(colors.count / 2) ? colors[colors.count / 2] : colors[0]
        // Slightly more opaque than day/night wedges so blue/golden sectors read more solid on the dial.
        context.fill(path, with: .color(mid.opacity(0.52)))
        path = sectorPath(center: center, radius: radius, startDeg: s0, endDeg: s1)
        context.stroke(path, with: .color(mid.opacity(0.78)), lineWidth: 1.25)
    }

    private func sectorPath(center: CGPoint, radius: CGFloat, startDeg: Double, endDeg: Double) -> Path {
        var delta = endDeg - startDeg
        while delta > 180 { delta -= 360 }
        while delta < -180 { delta += 360 }
        let steps = max(10, min(48, Int(abs(delta) / 4) + 8))
        var p = Path()
        p.move(to: center)
        for i in 0 ... steps {
            let t = Double(i) / Double(steps)
            let deg = startDeg + delta * t
            let pt = Self.pointOnCircle(center: center, radius: radius, degFromTopCW: deg)
            if i == 0 {
                p.addLine(to: pt)
            } else {
                p.addLine(to: pt)
            }
        }
        p.closeSubpath()
        return p
    }

    /// Angle from **top of screen** clockwise toward geographic azimuth `geoAzimuth`, given device true heading.
    private static func screenAngleDeg(geoAzimuth: Double, heading: Double) -> Double {
        var d = geoAzimuth - heading
        while d > 180 { d -= 360 }
        while d < -180 { d += 360 }
        return d
    }

    private static func pointOnCircle(center: CGPoint, radius: CGFloat, degFromTopCW: Double) -> CGPoint {
        let rad = degFromTopCW * .pi / 180
        return CGPoint(
            x: center.x + CGFloat(sin(rad)) * radius,
            y: center.y - CGFloat(cos(rad)) * radius
        )
    }
}
