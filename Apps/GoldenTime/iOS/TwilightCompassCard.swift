import CoreLocation
import MapKit
import SwiftUI

// MARK: - Map underlay (fixed scale, no user gestures; camera centered on user, heading-up)

private enum CompassMapMetrics {
    /// Camera height in meters — ~1 km shows a few blocks so roads/labels stay readable under the compass.
    static let cameraDistance: CLLocationDistance = 980
}

private struct CompassMapUnderlay: UIViewRepresentable {
    var coordinate: CLLocationCoordinate2D
    /// True north clockwise; drives map rotation to match overlay geometry.
    var headingDegrees: Double

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
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
            let d = CompassMapMetrics.cameraDistance
            let lock = MKMapView.CameraZoomRange(minCenterCoordinateDistance: d, maxCenterCoordinateDistance: d)
            map.setCameraZoomRange(lock, animated: false)
        }
        return map
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        guard CLLocationCoordinate2DIsValid(coordinate) else { return }
        let cam = MKMapCamera(
            lookingAtCenter: coordinate,
            fromDistance: CompassMapMetrics.cameraDistance,
            pitch: 0,
            heading: headingDegrees
        )
        mapView.setCamera(cam, animated: false)
    }
}

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
    var uiLanguage: GTAppLanguage
    var coordinate: CLLocationCoordinate2D
    /// When `nil`, geometry assumes north-up (`0`) for simulator / no magnetometer.
    var deviceHeadingDegrees: Double?
    /// Each pair: sun azimuth at local-day clip start → end (may be empty, one, or several).
    var blueSectorArcAzimuths: [(Double, Double)]
    var goldenSectorArcAzimuths: [(Double, Double)]
    var blueSectorColors: [Color]
    var goldenSectorColors: [Color]

    private var heading: Double {
        deviceHeadingDegrees ?? 0
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            Group {
                if showMapBase {
                    ZStack {
                        CompassMapUnderlay(coordinate: coordinate, headingDegrees: heading)
                            .frame(width: side, height: side)
                        compassFaceLayers(side: side, basemapBehindFace: true)
                            .allowsHitTesting(false)
                    }
                } else {
                    ZStack {
                        LinearGradient(
                            colors: chromeGradient.map { $0.opacity(0.92) },
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        compassFaceLayers(side: side, basemapBehindFace: false)
                            .allowsHitTesting(false)
                    }
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 4)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private func compassFaceLayers(side: CGFloat, basemapBehindFace: Bool) -> some View {
        ZStack {
            TwilightCompassDrawing(
                compassInk: compassInk,
                compassStroke: compassStroke,
                headingDegrees: heading,
                cardinals: GTCopy.compassCardinals(uiLanguage),
                basemapBehindFace: basemapBehindFace,
                blueSectorArcAzimuths: blueSectorArcAzimuths,
                goldenSectorArcAzimuths: goldenSectorArcAzimuths,
                blueSectorColors: blueSectorColors,
                goldenSectorColors: goldenSectorColors
            )
            .compositingGroup()

            CompassNeedleOverlay(headingDegrees: heading, side: side)
        }
        .frame(width: side, height: side)
    }
}

/// True-north indicator using Apple’s **SF Symbol** `location.north.fill` (same family as Maps / compass), rotated with device heading.
private struct CompassNeedleOverlay: View {
    var headingDegrees: Double
    var side: CGFloat

    /// Clockwise degrees from screen top to geographic north (same convention as `TwilightCompassDrawing.screenAngleDeg`).
    private var northDegreesFromTopClockwise: Double {
        var d = 0 - headingDegrees
        while d > 180 { d -= 360 }
        while d < -180 { d += 360 }
        return d
    }

    var body: some View {
        ZStack {
            SystemNorthArrowGlyph(side: side)
                .shadow(color: .black.opacity(0.28), radius: 4, x: 0, y: 2)
        }
        .frame(width: side, height: side)
        .rotationEffect(.degrees(northDegreesFromTopClockwise))
    }
}

/// Renders Apple’s `location.north.fill` (Maps / compass family) at compass scale.
/// Red–coral gradient: intentionally **not** the icon gold/orange (`sunCore` / `sunGlow`) so the needle doesn’t merge with golden sectors or cards.
private struct SystemNorthArrowGlyph: View {
    var side: CGFloat

    /// Kept modest so the glyph visually aligns with sector/rays (large SF Symbol overshoots the pivot).
    private var glyphSize: CGFloat { side * 0.20 }

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
    /// When true, map fills the same circular face as the compass; bezel ink switches to dark so ticks stay visible on tiles.
    var basemapBehindFace: Bool
    var blueSectorArcAzimuths: [(Double, Double)]
    var goldenSectorArcAzimuths: [(Double, Double)]
    var blueSectorColors: [Color]
    var goldenSectorColors: [Color]

    private static let bezelInkOnBasemap = Color(red: 0.06, green: 0.06, blue: 0.08)

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outerR = min(size.width, size.height) / 2 - 20
            let sectorR = outerR * 0.935

            if !basemapBehindFace {
                drawInnerFace(context: &context, center: center, radius: outerR * 0.94, ink: compassInk)
            }

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

            let tickInk = basemapBehindFace ? Self.bezelInkOnBasemap : compassInk
            drawDegreeTicks(context: &context, center: center, outerR: outerR, heading: headingDegrees, ink: tickInk)
            drawBezelLabels(
                context: &context,
                center: center,
                outerR: outerR,
                heading: headingDegrees,
                ink: basemapBehindFace ? Self.bezelInkOnBasemap : compassInk,
                stroke: compassStroke,
                cardinals: cardinals,
                northRed: Color(red: 0.92, green: 0.24, blue: 0.22)
            )

            drawOuterRim(context: &context, center: center, radius: outerR * 0.985, ink: compassInk)
        }
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
        ink: Color,
        stroke: Color,
        cardinals: (n: String, e: String, s: String, w: String),
        northRed: Color
    ) {
        let tickEnd = outerR * 0.94
        let labelR = tickEnd + 12
        let cardinalFont: CGFloat = cardinals.n == "北" ? 12.5 : 11.5
        let digitFont: CGFloat = 8.5

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
                    stroke: stroke,
                    fillOpacity: 1
                )
            case 90:
                drawBezelGlyph(
                    context: &context,
                    label: cardinals.e,
                    at: pt,
                    fontSize: cardinalFont,
                    fill: ink,
                    stroke: stroke,
                    fillOpacity: 0.9
                )
            case 180:
                drawBezelGlyph(
                    context: &context,
                    label: cardinals.s,
                    at: pt,
                    fontSize: cardinalFont,
                    fill: ink,
                    stroke: stroke,
                    fillOpacity: 0.9
                )
            case 270:
                drawBezelGlyph(
                    context: &context,
                    label: cardinals.w,
                    at: pt,
                    fontSize: cardinalFont,
                    fill: ink,
                    stroke: stroke,
                    fillOpacity: 0.9
                )
            default:
                let halo = Text("\(d)")
                    .font(.system(size: digitFont, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(stroke.opacity(0.38))
                context.draw(halo, at: CGPoint(x: pt.x + 0.45, y: pt.y + 0.45), anchor: .center)
                let t = Text("\(d)")
                    .font(.system(size: digitFont, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(ink.opacity(0.8))
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
        stroke: Color,
        fillOpacity: Double
    ) {
        let halo = Text(label)
            .font(.system(size: fontSize, weight: .bold, design: .rounded))
            .foregroundStyle(stroke.opacity(0.42))
        context.draw(halo, at: CGPoint(x: pt.x + 0.5, y: pt.y + 0.5), anchor: .center)
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
        context.fill(path, with: .color(mid.opacity(0.34)))
        path = sectorPath(center: center, radius: radius, startDeg: s0, endDeg: s1)
        context.stroke(path, with: .color(mid.opacity(0.55)), lineWidth: 1.25)
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
