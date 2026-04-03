import Foundation

/// Sun-position crossings, event stream, and phase transitions are a **line-for-line port** of the Garmin watch face logic in
/// `Golden-time(garmin)/source/SunAltService.mc` (thresholds −10/−4/+6°, NOAA solar noon anchor, bisect refine, two-day horizon, polar fallback).
/// **Do not replace** with another ephemeris or third-party “golden hour” API—product expectation is parity with that proven implementation.
///
/// **Time zone:** Uses the same `TimeZone` as the rest of the device UI (`autoupdatingCurrent` by default), including when the user
/// turns off “Set Automatically” and picks a zone in Settings—Garmin parity assumes the watch is **at** that civil context.
public final class GoldenTimeEngine {
    private let bisectToleranceSec = 1.0
    private let cosHClampEps = 1e-6
    private let denomEps = 1e-9
    private let twoDayHorizon = true

    private let calendar: Calendar
    private let timeZone: TimeZone

    private var hasFix = false
    private var lastFix: LocationFix?
    private var cachedEvents: [PhaseEvent] = []
    private var cachedTransitions: [PhaseTransition] = []
    private var todayHasGoldenStart = false
    private var todayHasBlueStart = false

    public init(timeZone: TimeZone = .autoupdatingCurrent) {
        self.timeZone = timeZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
    }

    public func update(now: Date, fix: LocationFix?) {
        guard let fix else {
            clearFixState()
            return
        }

        hasFix = true
        lastFix = fix

        let window = todayWindow(for: now)
        let startTs = window.start
        let endTs = window.end
        let lat = fix.latitude
        let lon = fix.longitude

        let day0Events = computeEventsAnalyticalForDayWithRefine(
            dayStartTs: startTs,
            dayEndTs: endTs,
            lat: lat,
            lon: lon,
            refine: true
        )
        let day1Events = twoDayHorizon
            ? computeEventsAnalyticalForDayWithRefine(
                dayStartTs: startTs + 86_400,
                dayEndTs: endTs + 86_400,
                lat: lat,
                lon: lon,
                refine: false
            )
            : []

        cachedEvents = normalizeAndValidateEvents(day0Events + day1Events)

        let eventsToday = filterEvents(events: cachedEvents, startTs: startTs, endTs: endTs)
        todayHasBlueStart = hasEvent(events: eventsToday, type: .blueStart)
        todayHasGoldenStart = hasEvent(events: eventsToday, type: .goldenStart)

        if eventsToday.isEmpty {
            if let polarState = detectPolarDayOrNight(dayStartTs: startTs, lat: lat, lon: lon) {
                cachedTransitions = normalizeAndValidateTransitions(
                    dayStartTs: startTs,
                    transitions: [
                        PhaseTransition(date: Date(timeIntervalSince1970: startTs), state: polarState),
                    ]
                )
            } else {
                cachedTransitions = []
            }
        } else {
            cachedTransitions = normalizeAndValidateTransitions(
                dayStartTs: startTs,
                transitions: buildTransitionsFromEvents(
                    dayStartTs: startTs,
                    dayEndTs: endTs,
                    events: eventsToday,
                    hasBlue: todayHasBlueStart,
                    hasGolden: todayHasGoldenStart
                )
            )
        }
    }

    public func currentState(at now: Date) -> PhaseState? {
        guard hasFix else {
            return nil
        }
        return resolveStateFromTransitions(nowTs: now.timeIntervalSince1970, transitions: cachedTransitions)
    }

    public func snapshot(at now: Date) -> GoldenTimeSnapshot {
        guard hasFix, lastFix != nil else {
            return GoldenTimeSnapshot(
                hasFix: false,
                nextBlueStart: nil,
                nextGoldenStart: nil,
                todayHasBlueStart: false,
                todayHasGoldenStart: false
            )
        }

        return GoldenTimeSnapshot(
            hasFix: true,
            nextBlueStart: findNextEventDate(events: cachedEvents, nowTs: now.timeIntervalSince1970, type: .blueStart),
            nextGoldenStart: findNextEventDate(events: cachedEvents, nowTs: now.timeIntervalSince1970, type: .goldenStart),
            todayHasBlueStart: todayHasBlueStart,
            todayHasGoldenStart: todayHasGoldenStart
        )
    }

    public func cachedEventStream() -> [PhaseEvent] {
        cachedEvents
    }

    public func cachedTransitionsStream() -> [PhaseTransition] {
        cachedTransitions
    }

    /// Next occurrence of `startType` strictly after `now`, paired with the first `endType` strictly after **that** start (scan forward from the start index only).
    public func nextEventWindow(after now: Date, start startType: PhaseEventType, end endType: PhaseEventType) -> (start: Date, end: Date)? {
        guard hasFix else {
            return nil
        }
        let nowTs = now.timeIntervalSince1970
        guard let startIdx = cachedEvents.firstIndex(where: { $0.type == startType && $0.date.timeIntervalSince1970 > nowTs }) else {
            return nil
        }
        let startEvent = cachedEvents[startIdx]
        let startTs = startEvent.date.timeIntervalSince1970
        guard let endEvent = cachedEvents[(startIdx + 1)...].first(where: { $0.type == endType && $0.date.timeIntervalSince1970 > startTs }) else {
            return nil
        }
        return (startEvent.date, endEvent.date)
    }

    /// Next civil-twilight “blue” segment: `blueStart` → following `blueEnd` (local astronomical model, no network).
    public func nextBlueWindow(after now: Date) -> (start: Date, end: Date)? {
        nextEventWindow(after: now, start: .blueStart, end: .blueEnd)
    }

    /// Next golden-hour segment: `goldenStart` → following `goldenEnd` (local astronomical model, no network).
    public func nextGoldenWindow(after now: Date) -> (start: Date, end: Date)? {
        nextEventWindow(after: now, start: .goldenStart, end: .goldenEnd)
    }

    /// Blue segment containing `now` in `[start, end)`, otherwise the next future blue segment (same pairing rules as `nextBlueWindow`).
    public func blueWindowRelevant(at now: Date) -> (start: Date, end: Date)? {
        currentOrNextEventWindow(at: now, start: .blueStart, end: .blueEnd)
    }

    /// Golden segment containing `now` in `[start, end)`, otherwise the next future golden segment.
    public func goldenWindowRelevant(at now: Date) -> (start: Date, end: Date)? {
        currentOrNextEventWindow(at: now, start: .goldenStart, end: .goldenEnd)
    }

    /// Blue-hour intervals intersected with the **local civil day** of `now` (`[startOfDay, nextDay)`).
    /// Mid-latitudes often yield two clipped windows (dawn / dusk); polar edge cases may yield none, one, or partial clips.
    public func blueWindowsInLocalDay(containing now: Date) -> [(start: Date, end: Date)] {
        windowsIntersectingLocalDay(containing: now, startType: .blueStart, endType: .blueEnd)
    }

    /// Golden-hour intervals intersected with the same local civil day.
    public func goldenWindowsInLocalDay(containing now: Date) -> [(start: Date, end: Date)] {
        windowsIntersectingLocalDay(containing: now, startType: .goldenStart, endType: .goldenEnd)
    }

    private func windowsIntersectingLocalDay(
        containing now: Date,
        startType: PhaseEventType,
        endType: PhaseEventType
    ) -> [(start: Date, end: Date)] {
        guard hasFix else { return [] }
        let w = todayWindow(for: now)
        let dayStart = w.start
        let dayEnd = w.end
        var out: [(Date, Date)] = []
        let minDur = 1.0
        for i in cachedEvents.indices {
            guard cachedEvents[i].type == startType else { continue }
            let sTs = cachedEvents[i].date.timeIntervalSince1970
            guard let endEvent = cachedEvents[(i + 1)...].first(where: { $0.type == endType && $0.date.timeIntervalSince1970 > sTs }) else {
                continue
            }
            let eTs = endEvent.date.timeIntervalSince1970
            let clipStart = max(sTs, dayStart)
            let clipEnd = min(eTs, dayEnd)
            guard clipEnd - clipStart >= minDur else { continue }
            out.append((Date(timeIntervalSince1970: clipStart), Date(timeIntervalSince1970: clipEnd)))
        }
        out.sort { $0.0 < $1.0 }
        return out
    }

    /// Upper limb at the astronomical horizon (−50′), matching common “sunrise/sunset” tables.
    private var apparentHorizonAltitudeDegrees: Double { -50.0 / 60.0 }

    /// Today’s apparent sunrise & sunset times and sun azimuths at those instants (true-north clockwise).
    /// Returns `nil` if there is no fix or no horizon crossing (e.g. polar day/night).
    public func sunHorizonGeometry(for now: Date) -> SunHorizonGeometry? {
        guard hasFix, let fix = lastFix else {
            return nil
        }
        let window = todayWindow(for: now)
        let dayStart = window.start
        let dayEnd = window.end
        let lat = fix.latitude
        let lon = fix.longitude
        let thr = apparentHorizonAltitudeDegrees

        guard
            let riseTs = findHorizonCrossingUp(dayStartTs: dayStart, dayEndTs: dayEnd, lat: lat, lon: lon, threshold: thr),
            let setTs = findHorizonCrossingDown(dayStartTs: dayStart, dayEndTs: dayEnd, lat: lat, lon: lon, threshold: thr),
            setTs > riseTs,
            let risePos = solarAltitudeAndAzimuth(ts: riseTs, latDeg: lat, lonDeg: lon),
            let setPos = solarAltitudeAndAzimuth(ts: setTs, latDeg: lat, lonDeg: lon)
        else {
            return nil
        }
        let azRise = risePos.azimuthDegrees
        let azSet = setPos.azimuthDegrees

        return SunHorizonGeometry(
            sunrise: Date(timeIntervalSince1970: riseTs),
            sunset: Date(timeIntervalSince1970: setTs),
            sunriseAzimuthDegrees: azRise,
            sunsetAzimuthDegrees: azSet
        )
    }

    /// True-north clockwise solar azimuth (0…360°) at `instant`, same model as twilight phases.
    public func sunAzimuthDegrees(at instant: Date) -> Double? {
        guard hasFix, let fix = lastFix else {
            return nil
        }
        let ts = instant.timeIntervalSince1970
        return solarAltitudeAndAzimuth(ts: ts, latDeg: fix.latitude, lonDeg: fix.longitude)?.azimuthDegrees
    }

    private func currentOrNextEventWindow(at now: Date, start startType: PhaseEventType, end endType: PhaseEventType) -> (start: Date, end: Date)? {
        guard hasFix else {
            return nil
        }
        let nowTs = now.timeIntervalSince1970
        var bestStartTs = -Double.infinity
        var best: (Date, Date)?
        for i in cachedEvents.indices {
            guard cachedEvents[i].type == startType else { continue }
            let s = cachedEvents[i].date
            let sTs = s.timeIntervalSince1970
            guard sTs <= nowTs else { continue }
            guard let endEvent = cachedEvents[(i + 1)...].first(where: { $0.type == endType && $0.date.timeIntervalSince1970 > sTs }) else { continue }
            let eTs = endEvent.date.timeIntervalSince1970
            guard nowTs < eTs, sTs > bestStartTs else { continue }
            bestStartTs = sTs
            best = (s, endEvent.date)
        }
        if let best {
            return best
        }
        return nextEventWindow(after: now, start: startType, end: endType)
    }

    private func clearFixState() {
        hasFix = false
        lastFix = nil
        cachedEvents = []
        cachedTransitions = []
        todayHasGoldenStart = false
        todayHasBlueStart = false
    }

    private func todayWindow(for now: Date) -> (start: TimeInterval, end: TimeInterval) {
        let components = calendar.dateComponents(in: timeZone, from: now)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let second = components.second ?? 0
        let secondsSinceMidnight = Double(hour * 3_600 + minute * 60 + second)
        let start = now.timeIntervalSince1970 - secondsSinceMidnight
        return (start, start + 86_400)
    }

    private func computeEventsAnalyticalForDayWithRefine(
        dayStartTs: TimeInterval,
        dayEndTs: TimeInterval,
        lat: Double,
        lon: Double,
        refine: Bool
    ) -> [PhaseEvent] {
        solveAllCrossingsWithRefine(startTs: dayStartTs, endTs: dayEndTs, lat: lat, lon: lon, refine: refine)
    }

    private func solveAllCrossingsWithRefine(
        startTs: TimeInterval,
        endTs: TimeInterval,
        lat: Double,
        lon: Double,
        refine: Bool
    ) -> [PhaseEvent] {
        let midTs = startTs + 43_200
        let jd = (midTs / 86_400.0) + 2_440_587.5
        let jc = (jd - 2_451_545.0) / 36_525.0

        let meanLong = normalizeDegrees(280.46646 + jc * (36_000.76983 + jc * 0.0003032))
        let meanAnom = normalizeDegrees(357.52911 + jc * (35_999.05029 - 0.0001537 * jc))
        let omega = 125.04 - 1934.136 * jc
        let mRad = degreesToRadians(meanAnom)
        let center =
            sin(mRad) * (1.914602 - jc * (0.004817 + 0.000014 * jc))
            + sin(2.0 * mRad) * (0.019993 - 0.000101 * jc)
            + sin(3.0 * mRad) * 0.000289
        let trueLong = meanLong + center
        let eclipLong = trueLong - 0.00569 - 0.00478 * sin(degreesToRadians(omega))
        let obliqMean =
            23.0 + (26.0 + ((21.448 - jc * (46.815 + jc * (0.00059 - jc * 0.001813))) / 60.0)) / 60.0
        let obliqCorr = obliqMean + 0.00256 * cos(degreesToRadians(omega))
        let declRad = asin(sin(degreesToRadians(obliqCorr)) * sin(degreesToRadians(eclipLong)))

        let latRad = degreesToRadians(lat)
        let amplitude = cos(latRad) * cos(declRad)
        let base = sin(latRad) * sin(declRad)
        let solarNoonTs = computeNoaaSolarNoonTs(dayStartTs: startTs, lon: lon)

        var events: [PhaseEvent] = []
        let thresholds = [-10.0, -4.0, 6.0]

        for threshold in thresholds {
            if abs(amplitude) < denomEps {
                continue
            }

            let thresholdRad = degreesToRadians(threshold)
            let rawCosH = (sin(thresholdRad) - base) / amplitude
            var cosH = rawCosH
            var hasCrossing = true

            if cosH > 1.0 {
                if cosH <= 1.0 + cosHClampEps {
                    cosH = 1.0
                } else {
                    hasCrossing = false
                }
            } else if cosH < -1.0 {
                if cosH >= -1.0 - cosHClampEps {
                    cosH = -1.0
                } else {
                    hasCrossing = false
                }
            }

            if !hasCrossing || cosH < -1.0 || cosH > 1.0 {
                continue
            }

            let hourAngle = acos(cosH)
            let offsetSec = radiansToDegrees(hourAngle) * 240.0

            var risingTs = normalizeCrossingTsToWindow(ts: solarNoonTs - offsetSec, dayStartTs: startTs, dayEndTs: endTs)
            var settingTs = normalizeCrossingTsToWindow(ts: solarNoonTs + offsetSec, dayStartTs: startTs, dayEndTs: endTs)

            if risingTs >= startTs, risingTs < endTs {
                if refine, let refined = bisectRoot(loTs: risingTs - 450.0, hiTs: risingTs + 450.0, lat: lat, lon: lon, threshold: threshold) {
                    risingTs = refined
                }
                addCrossingEvents(events: &events, ts: risingTs, threshold: threshold, rising: true)
            }

            if settingTs >= startTs, settingTs < endTs {
                if refine, let refined = bisectRoot(loTs: settingTs - 450.0, hiTs: settingTs + 450.0, lat: lat, lon: lon, threshold: threshold) {
                    settingTs = refined
                }
                addCrossingEvents(events: &events, ts: settingTs, threshold: threshold, rising: false)
            }
        }

        return sortAndDedupeEvents(events)
    }

    private func filterEvents(events: [PhaseEvent], startTs: TimeInterval, endTs: TimeInterval) -> [PhaseEvent] {
        events.filter {
            let ts = $0.date.timeIntervalSince1970
            return ts >= startTs && ts < endTs
        }
    }

    private func normalizeCrossingTsToWindow(ts: TimeInterval, dayStartTs: TimeInterval, dayEndTs: TimeInterval) -> TimeInterval {
        if ts < dayStartTs {
            let delta = dayStartTs - ts
            return delta < 43_200 ? ts + 86_400 : ts
        }
        if ts >= dayEndTs {
            let delta = ts - dayEndTs
            return delta < 43_200 ? ts - 86_400 : ts
        }
        return ts
    }

    private func addCrossingEvents(events: inout [PhaseEvent], ts: TimeInterval, threshold: Double, rising: Bool) {
        let date = Date(timeIntervalSince1970: ts)

        switch threshold {
        case -10.0:
            events.append(PhaseEvent(date: date, type: rising ? .blueStart : .blueEnd))
        case -4.0:
            if rising {
                events.append(PhaseEvent(date: date, type: .blueEnd))
                events.append(PhaseEvent(date: date, type: .goldenStart))
            } else {
                events.append(PhaseEvent(date: date, type: .goldenEnd))
                events.append(PhaseEvent(date: date, type: .blueStart))
            }
        case 6.0:
            events.append(PhaseEvent(date: date, type: rising ? .goldenEnd : .goldenStart))
        default:
            break
        }
    }

    private func bisectRoot(loTs: TimeInterval, hiTs: TimeInterval, lat: Double, lon: Double, threshold: Double) -> TimeInterval? {
        var lo = loTs
        var hi = hiTs
        guard
            let altLo = solarAltitudeDegrees(ts: lo, latDeg: lat, lonDeg: lon),
            let altHi = solarAltitudeDegrees(ts: hi, latDeg: lat, lonDeg: lon)
        else {
            return nil
        }

        var fLo = altLo - threshold
        let fHi = altHi - threshold

        guard !fLo.isNaN, !fHi.isNaN else {
            return nil
        }

        var iteration = 0
        while (hi - lo) > bisectToleranceSec, iteration < 30 {
            let mid = lo + (hi - lo) / 2.0
            guard let altMid = solarAltitudeDegrees(ts: mid, latDeg: lat, lonDeg: lon), !altMid.isNaN else {
                return nil
            }
            let fMid = altMid - threshold

            if abs(fMid) < 0.001 {
                return mid
            }

            if (fLo < 0 && fMid > 0) || (fLo > 0 && fMid < 0) {
                hi = mid
            } else {
                lo = mid
                fLo = fMid
            }

            iteration += 1
        }

        return lo + (hi - lo) / 2.0
    }

    private func findNextEventDate(events: [PhaseEvent], nowTs: TimeInterval, type: PhaseEventType) -> Date? {
        for event in events {
            let ts = event.date.timeIntervalSince1970
            if event.type == type, ts > nowTs {
                return event.date
            }
        }
        return nil
    }

    private func hasEvent(events: [PhaseEvent], type: PhaseEventType) -> Bool {
        events.contains { $0.type == type }
    }

    private func normalizeAndValidateEvents(_ events: [PhaseEvent]) -> [PhaseEvent] {
        let normalized = isSortedByTs(events) ? events : sortAndDedupeEvents(events)
        let allowed = Set(PhaseEventType.allCases)
        return normalized.allSatisfy { allowed.contains($0.type) } ? normalized : []
    }

    private func isSortedByTs(_ events: [PhaseEvent]) -> Bool {
        guard events.count > 1 else {
            return true
        }

        for index in 1..<events.count where events[index - 1].date > events[index].date {
            return false
        }
        return true
    }

    private func sortAndDedupeEvents(_ events: [PhaseEvent]) -> [PhaseEvent] {
        let sorted = sortEventsByTsAndPriority(events)
        var deduped: [PhaseEvent] = []

        for current in sorted {
            guard let last = deduped.last else {
                deduped.append(current)
                continue
            }

            let sameType = last.type == current.type
            let sameTs = abs(last.date.timeIntervalSince1970 - current.date.timeIntervalSince1970) <= 1.0

            if !(sameType && sameTs) {
                deduped.append(current)
            }
        }

        return deduped
    }

    private func sortEventsByTsAndPriority(_ events: [PhaseEvent]) -> [PhaseEvent] {
        events.sorted { lhs, rhs in
            let lhsTs = lhs.date.timeIntervalSince1970
            let rhsTs = rhs.date.timeIntervalSince1970

            if lhsTs == rhsTs {
                return eventPriority(lhs.type) < eventPriority(rhs.type)
            }

            return lhsTs < rhsTs
        }
    }

    private func eventPriority(_ type: PhaseEventType) -> Int {
        switch type {
        case .blueEnd:
            return 0
        case .goldenStart:
            return 1
        case .goldenEnd:
            return 2
        case .blueStart:
            return 3
        }
    }

    private func buildTransitionsFromEvents(
        dayStartTs: TimeInterval,
        dayEndTs: TimeInterval,
        events: [PhaseEvent],
        hasBlue: Bool,
        hasGolden: Bool
    ) -> [PhaseTransition] {
        let sorted = sortEventsByTsAndPriority(events)
        var transitions = [
            PhaseTransition(
                date: Date(timeIntervalSince1970: dayStartTs),
                state: inferDayStartState(events: sorted, hasBlue: hasBlue, hasGolden: hasGolden)
            ),
        ]
        var currentState = transitions[0].state
        var index = 0

        while index < sorted.count {
            let ts = sorted[index].date.timeIntervalSince1970
            let groupStart = index

            while index < sorted.count, sorted[index].date.timeIntervalSince1970 == ts {
                index += 1
            }

            if ts < dayStartTs || ts >= dayEndTs {
                continue
            }

            for eventIndex in groupStart..<index {
                currentState = nextStateForEvent(
                    type: sorted[eventIndex].type,
                    ts: ts,
                    hasGolden: hasGolden,
                    sortedEvents: sorted,
                    indexHint: eventIndex
                )
            }

            upsertTransition(
                transitions: &transitions,
                ts: ts,
                state: currentState
            )
        }

        return transitions
    }

    private func normalizeAndValidateTransitions(dayStartTs: TimeInterval, transitions: [PhaseTransition]) -> [PhaseTransition] {
        guard !transitions.isEmpty else {
            return []
        }

        let sorted = transitions.sorted { $0.date < $1.date }
        var merged: [PhaseTransition] = []

        for item in sorted {
            if let last = merged.last, last.date == item.date {
                merged[merged.count - 1] = item
            } else if PhaseState.allCases.contains(item.state) {
                merged.append(item)
            } else {
                return []
            }
        }

        guard let first = merged.first, first.date.timeIntervalSince1970 == dayStartTs else {
            return []
        }

        for index in 1..<merged.count where merged[index - 1].date >= merged[index].date {
            return []
        }

        return merged
    }

    private func resolveStateFromTransitions(nowTs: TimeInterval, transitions: [PhaseTransition]) -> PhaseState? {
        guard let first = transitions.first else {
            return nil
        }

        if nowTs < first.date.timeIntervalSince1970 {
            return first.state
        }

        var selected = first.state
        for transition in transitions where transition.date.timeIntervalSince1970 <= nowTs {
            selected = transition.state
        }
        return selected
    }

    private func inferDayStartState(events: [PhaseEvent], hasBlue: Bool, hasGolden: Bool) -> PhaseState {
        guard let firstType = events.first?.type else {
            return (!hasBlue && !hasGolden) ? .day : .day
        }

        switch firstType {
        case .blueStart, .goldenStart:
            return .night
        case .blueEnd:
            return .blue
        case .goldenEnd:
            return .golden
        }
    }

    private func detectPolarDayOrNight(dayStartTs: TimeInterval, lat: Double, lon: Double) -> PhaseState? {
        guard abs(lat) >= 60.0 else {
            return nil
        }

        guard
            let alt1 = solarAltitudeDegrees(ts: dayStartTs + 21_600, latDeg: lat, lonDeg: lon),
            let alt2 = solarAltitudeDegrees(ts: dayStartTs + 43_200, latDeg: lat, lonDeg: lon),
            let alt3 = solarAltitudeDegrees(ts: dayStartTs + 64_800, latDeg: lat, lonDeg: lon)
        else {
            return nil
        }

        if [alt1, alt2, alt3].contains(where: \.isNaN) {
            return nil
        }

        if alt1 < -10.0, alt2 < -10.0, alt3 < -10.0 {
            return .night
        }
        if alt1 > 6.0, alt2 > 6.0, alt3 > 6.0 {
            return .day
        }
        return nil
    }

    private func nextStateForEvent(
        type: PhaseEventType,
        ts: TimeInterval,
        hasGolden: Bool,
        sortedEvents: [PhaseEvent],
        indexHint: Int
    ) -> PhaseState {
        switch type {
        case .blueStart:
            return .blue
        case .blueEnd:
            return hasGolden && hasGoldenStartAtOrAfter(events: sortedEvents, ts: ts, indexHint: indexHint) ? .golden : .night
        case .goldenStart:
            return .golden
        case .goldenEnd:
            return .day
        }
    }

    private func hasGoldenStartAtOrAfter(events: [PhaseEvent], ts: TimeInterval, indexHint: Int) -> Bool {
        for index in indexHint..<events.count {
            let event = events[index]
            if event.date.timeIntervalSince1970 < ts {
                continue
            }
            if event.type == .goldenStart {
                return true
            }
        }
        return false
    }

    private func upsertTransition(transitions: inout [PhaseTransition], ts: TimeInterval, state: PhaseState) {
        let date = Date(timeIntervalSince1970: ts)

        guard let last = transitions.last else {
            transitions.append(PhaseTransition(date: date, state: state))
            return
        }

        if last.date.timeIntervalSince1970 == ts {
            transitions[transitions.count - 1] = PhaseTransition(date: date, state: state)
            return
        }

        if last.state != state {
            transitions.append(PhaseTransition(date: date, state: state))
        }
    }

    private func solarAltitudeAndAzimuth(ts: TimeInterval, latDeg: Double, lonDeg: Double) -> (altitudeDegrees: Double, azimuthDegrees: Double)? {
        let jd = (ts / 86_400.0) + 2_440_587.5
        let jc = (jd - 2_451_545.0) / 36_525.0

        let meanLong = normalizeDegrees(280.46646 + jc * (36_000.76983 + jc * 0.0003032))
        let meanAnom = normalizeDegrees(357.52911 + jc * (35_999.05029 - 0.0001537 * jc))
        let omega = 125.04 - 1934.136 * jc
        let mRad = degreesToRadians(meanAnom)
        let center =
            sin(mRad) * (1.914602 - jc * (0.004817 + 0.000014 * jc))
            + sin(2.0 * mRad) * (0.019993 - 0.000101 * jc)
            + sin(3.0 * mRad) * 0.000289

        let trueLong = meanLong + center
        let eclipLong = trueLong - 0.00569 - 0.00478 * sin(degreesToRadians(omega))
        let obliqMean =
            23.0 + (26.0 + ((21.448 - jc * (46.815 + jc * (0.00059 - jc * 0.001813))) / 60.0)) / 60.0
        let obliqCorr = obliqMean + 0.00256 * cos(degreesToRadians(omega))

        let eclipRad = degreesToRadians(eclipLong)
        let obliqRad = degreesToRadians(obliqCorr)
        let declRad = asin(sin(obliqRad) * sin(eclipRad))
        let raDeg = normalizeDegrees(radiansToDegrees(atan2(cos(obliqRad) * sin(eclipRad), cos(eclipRad))))

        let gmst = normalizeDegrees(
            280.46061837
                + 360.98564736629 * (jd - 2_451_545.0)
                + 0.000387933 * jc * jc
                - (jc * jc * jc) / 38_710_000.0
        )

        let hourAngleDeg = normalizeSignedDegrees(gmst + lonDeg - raDeg)
        let latRad = degreesToRadians(latDeg)
        let haRad = degreesToRadians(hourAngleDeg)

        let unclampedSinAlt =
            sin(latRad) * sin(declRad)
            + cos(latRad) * cos(declRad) * cos(haRad)
        let sinAlt = min(1.0, max(-1.0, unclampedSinAlt))

        let altitudeDegrees = radiansToDegrees(asin(sinAlt))

        let y = -sin(haRad)
        let x = cos(latRad) * sin(declRad) - sin(latRad) * cos(declRad) * cos(haRad)
        let azimuthDegrees = normalizeDegrees(radiansToDegrees(atan2(y, x)))

        return (altitudeDegrees, azimuthDegrees)
    }

    private func solarAltitudeDegrees(ts: TimeInterval, latDeg: Double, lonDeg: Double) -> Double? {
        solarAltitudeAndAzimuth(ts: ts, latDeg: latDeg, lonDeg: lonDeg)?.altitudeDegrees
    }

    private func findHorizonCrossingUp(
        dayStartTs: TimeInterval,
        dayEndTs: TimeInterval,
        lat: Double,
        lon: Double,
        threshold: Double
    ) -> TimeInterval? {
        let solarNoon = computeNoaaSolarNoonTs(dayStartTs: dayStartTs, lon: lon)
        let step: TimeInterval = 300
        var t = dayStartTs
        guard let firstAlt = solarAltitudeAndAzimuth(ts: t, latDeg: lat, lonDeg: lon)?.altitudeDegrees else {
            return nil
        }
        var prevF = firstAlt - threshold
        while t < min(solarNoon, dayEndTs - step) {
            t += step
            guard let alt = solarAltitudeAndAzimuth(ts: t, latDeg: lat, lonDeg: lon)?.altitudeDegrees else {
                continue
            }
            let f = alt - threshold
            if prevF < 0, f >= 0 {
                return bisectRoot(loTs: t - step, hiTs: t, lat: lat, lon: lon, threshold: threshold)
            }
            prevF = f
        }
        return nil
    }

    private func findHorizonCrossingDown(
        dayStartTs: TimeInterval,
        dayEndTs: TimeInterval,
        lat: Double,
        lon: Double,
        threshold: Double
    ) -> TimeInterval? {
        let solarNoon = computeNoaaSolarNoonTs(dayStartTs: dayStartTs, lon: lon)
        let step: TimeInterval = 300
        var t = max(solarNoon, dayStartTs)
        guard let firstAlt = solarAltitudeAndAzimuth(ts: t, latDeg: lat, lonDeg: lon)?.altitudeDegrees else {
            return nil
        }
        var prevF = firstAlt - threshold
        while t < dayEndTs - step {
            t += step
            guard let alt = solarAltitudeAndAzimuth(ts: t, latDeg: lat, lonDeg: lon)?.altitudeDegrees else {
                continue
            }
            let f = alt - threshold
            if prevF > 0, f <= 0 {
                return bisectRoot(loTs: t - step, hiTs: t, lat: lat, lon: lon, threshold: threshold)
            }
            prevF = f
        }
        return nil
    }

    private func computeNoaaSolarNoonTs(dayStartTs: TimeInterval, lon: Double) -> TimeInterval {
        let jd = (dayStartTs / 86_400.0) + 2_440_587.5
        let jc = (jd - 2_451_545.0) / 36_525.0

        let geomMeanLongSun = normalizeDegrees(280.46646 + jc * (36_000.76983 + jc * 0.0003032))
        let geomMeanAnomSun = normalizeDegrees(357.52911 + jc * (35_999.05029 - 0.0001537 * jc))
        let eccentEarthOrbit = 0.016708634 - jc * (0.000042037 + 0.0000001267 * jc)
        let omega = 125.04 - 1934.136 * jc

        let mRad = degreesToRadians(geomMeanAnomSun)
        let sunEqOfCtr =
            sin(mRad) * (1.914602 - jc * (0.004817 + 0.000014 * jc))
            + sin(2.0 * mRad) * (0.019993 - 0.000101 * jc)
            + sin(3.0 * mRad) * 0.000289
        let sunTrueLong = geomMeanLongSun + sunEqOfCtr
        let _ = sunTrueLong - 0.00569 - 0.00478 * sin(degreesToRadians(omega))

        let meanObliqEcliptic =
            23.0 + (26.0 + ((21.448 - jc * (46.815 + jc * (0.00059 - jc * 0.001813))) / 60.0)) / 60.0
        let obliqCorr = meanObliqEcliptic + 0.00256 * cos(degreesToRadians(omega))
        let varY = pow(tan(degreesToRadians(obliqCorr) / 2.0), 2.0)

        let eqOfTimeMinutes = 4.0 * radiansToDegrees(
            varY * sin(2.0 * degreesToRadians(geomMeanLongSun))
                - 2.0 * eccentEarthOrbit * sin(mRad)
                + 4.0 * eccentEarthOrbit * varY * sin(mRad) * cos(2.0 * degreesToRadians(geomMeanLongSun))
                - 0.5 * varY * varY * sin(4.0 * degreesToRadians(geomMeanLongSun))
                - 1.25 * eccentEarthOrbit * eccentEarthOrbit * sin(2.0 * mRad)
        )

        let timeZoneOffsetMinutes = Double(timeZone.secondsFromGMT(for: Date(timeIntervalSince1970: dayStartTs))) / 60.0
        let solarNoonMinutes = 720.0 - 4.0 * lon - eqOfTimeMinutes + timeZoneOffsetMinutes
        var solarNoonTs = dayStartTs + solarNoonMinutes * 60.0
        let dayEndTs = dayStartTs + 86_400

        while solarNoonTs < dayStartTs {
            solarNoonTs += 86_400
        }
        while solarNoonTs >= dayEndTs {
            solarNoonTs -= 86_400
        }
        return solarNoonTs
    }

    private func degreesToRadians(_ value: Double) -> Double {
        value * .pi / 180.0
    }

    private func radiansToDegrees(_ value: Double) -> Double {
        value * 180.0 / .pi
    }

    private func normalizeDegrees(_ value: Double) -> Double {
        var output = value - floor(value / 360.0) * 360.0
        while output < 0 {
            output += 360.0
        }
        while output >= 360.0 {
            output -= 360.0
        }
        return output
    }

    private func normalizeSignedDegrees(_ value: Double) -> Double {
        let output = normalizeDegrees(value)
        return output > 180.0 ? output - 360.0 : output
    }
}
