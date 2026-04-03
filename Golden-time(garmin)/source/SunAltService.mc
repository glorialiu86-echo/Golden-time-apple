import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;

class SunAltService {
    const LOC_CHANGE_THRESHOLD_DEG = 0.01;
    const BISECT_TOLERANCE_SEC = 1;
    const COSH_CLAMP_EPS = 1e-6;
    const DENOM_EPS = 1e-9;
    const MAX_EVENTS = 16;
    const MAX_TRANSITIONS = 16;
    const TWO_DAY_HORIZON = true;

    var _hasFix as Boolean;
    var _lastFix as Lang.Dictionary or Null;
    var _lastComputeSlotKey as String or Null;
    var _cachedEvents as Array<Lang.Dictionary>;
    var _cachedTransitions as Array<Lang.Dictionary>;
    var _todayHasGoldenStart as Boolean;
    var _todayHasBlueStart as Boolean;
    function initialize() {
        _hasFix = false;
        _lastFix = null;
        _lastComputeSlotKey = null;
        _cachedEvents = [];
        _cachedTransitions = [];
        _todayHasGoldenStart = false;
        _todayHasBlueStart = false;
    }

    function updateIfNeeded(nowTs as Number, fix as Lang.Dictionary or Null) as Void {
        if (fix == null || fix[:lat] == null || fix[:lon] == null) {
            _clearFixState();
            return;
        }

        _hasFix = true;
        var slotKey = _getDaySlotKey(nowTs);
        var needRecompute = false;

        needRecompute = true;

        _lastFix = {
            :lat => fix[:lat],
            :lon => fix[:lon],
            :ts => fix[:ts]
        };
        _lastComputeSlotKey = slotKey;

        var window = _getTodayWindow(nowTs);
        var startTs = window[:startTs] as Number;
        var endTs = window[:endTs] as Number;
        var lat = fix[:lat] as Number;
        var lon = fix[:lon] as Number;

        // 两天视野：day0 精修，day1 降载（不 bisect），用于 nextXXX 搜索。
        var day0Events = _computeEventsAnalyticalForDayWithRefine(startTs, endTs, lat, lon, true);
        var day1Events = [] as Array<Lang.Dictionary>;
        if (TWO_DAY_HORIZON) {
            day1Events = _computeEventsAnalyticalForDayWithRefine(startTs + 86400, endTs + 86400, lat, lon, false);
        }

        var mergedEvents = [] as Array<Lang.Dictionary>;
        for (var e0 = 0; e0 < day0Events.size(); e0 += 1) {
            mergedEvents.add(day0Events[e0]);
        }
        for (var e1 = 0; e1 < day1Events.size(); e1 += 1) {
            mergedEvents.add(day1Events[e1]);
        }
        mergedEvents = _normalizeAndValidateEvents(mergedEvents);
        _cachedEvents = mergedEvents;

        // 状态机只看今天窗口，避免跨日事件污染当日 transitions。
        var eventsToday = _filterEventsInWindow(_cachedEvents, startTs, endTs);
        _todayHasBlueStart = _hasEvent(eventsToday, "BLUE_START");
        _todayHasGoldenStart = _hasEvent(eventsToday, "GOLDEN_START");

        if (eventsToday.size() == 0) {
            var polar = _detectPolarDayOrNight(startTs, lat, lon);
            if (polar != null) {
                _cachedTransitions = [{ :ts => startTs, :state => polar }] as Array<Lang.Dictionary>;
                _cachedTransitions = _normalizeAndValidateTransitions(startTs, _cachedTransitions);
            } else {
                _cachedTransitions = [];
            }
        } else {
            _cachedTransitions = _buildTransitionsFromEvents(
                startTs, endTs, eventsToday,
                _todayHasBlueStart, _todayHasGoldenStart
            );
            _cachedTransitions = _normalizeAndValidateTransitions(startTs, _cachedTransitions);
        }
    }

    function getCurrentState(nowTs as Number) as String or Null {
        if (!_hasFix) {
            return null;
        }
        if (_cachedTransitions.size() > 0) {
            return _resolveStateFromTransitions(nowTs, _cachedTransitions);
        }
        return null;
    }

    function getSnapshot(nowTs as Number) as Lang.Dictionary {
        if (!_hasFix || _lastFix == null) {
            return {
                :hasFix => false,
                :nextBlueStartTs => null,
                :nextGoldenStartTs => null,
                :todayHasBlueStart => false,
                :todayHasGoldenStart => false
            };
        }

        return {
            :hasFix => true,
            :nextBlueStartTs => _findNextEventTs(_cachedEvents, nowTs, "BLUE_START"),
            :nextGoldenStartTs => _findNextEventTs(_cachedEvents, nowTs, "GOLDEN_START"),
            :todayHasBlueStart => _todayHasBlueStart,
            :todayHasGoldenStart => _todayHasGoldenStart
        };
    }

    function _buildTransitionsFromEvents(
        dayStartTs as Number,
        dayEndTs as Number,
        events as Array<Lang.Dictionary>,
        hasBlue as Boolean,
        hasGolden as Boolean
    ) as Array<Lang.Dictionary> {
        var sorted = _sortEventsByTsAndPriority(events);
        var transitions = [] as Array<Lang.Dictionary>;
        var curState = _inferDayStartState(sorted, hasBlue, hasGolden);

        transitions.add({ :ts => dayStartTs, :state => curState });

        var i = 0;
        while (i < sorted.size()) {
            var ts = sorted[i][:ts] as Number;
            var groupStart = i;

            while (i < sorted.size() && (sorted[i][:ts] as Number) == ts) {
                i += 1;
            }

            if (ts < dayStartTs || ts >= dayEndTs) {
                continue;
            }

            for (var j = groupStart; j < i; j += 1) {
                var typeName = sorted[j][:type] as String or Null;
                if (typeName == null) {
                    continue;
                }
                curState = _nextStateForEvent(typeName as String, ts, curState, hasGolden, sorted, j);
            }

            _upsertTransition(transitions, ts, curState);
        }

        return transitions;
    }

    function _normalizeAndValidateTransitions(dayStartTs as Number, transitions as Array<Lang.Dictionary>) as Array<Lang.Dictionary> {
        if (transitions.size() == 0) {
            return [] as Array<Lang.Dictionary>;
        }

        var out = [] as Array<Lang.Dictionary>;
        for (var i = 0; i < transitions.size(); i += 1) {
            out.add(transitions[i]);
        }

        var n = out.size();
        for (var p = 0; p < n; p += 1) {
            for (var q = 0; q < (n - 1 - p); q += 1) {
                if ((out[q][:ts] as Number) > (out[q + 1][:ts] as Number)) {
                    var tmp = out[q];
                    out[q] = out[q + 1];
                    out[q + 1] = tmp;
                }
            }
        }

        var merged = [] as Array<Lang.Dictionary>;
        for (var k = 0; k < out.size(); k += 1) {
            var item = out[k];
            var ts = item[:ts] as Number or Null;
            var state = item[:state] as String or Null;
            if (ts == null || state == null || !_isValidState(state as String)) {
                return [] as Array<Lang.Dictionary>;
            }

            if (merged.size() > 0 && (merged[merged.size() - 1][:ts] as Number) == (ts as Number)) {
                merged[merged.size() - 1] = item;
            } else {
                merged.add(item);
            }
        }

        if (merged.size() == 0) {
            return [] as Array<Lang.Dictionary>;
        }

        if ((merged[0][:ts] as Number) != dayStartTs) {
            return [] as Array<Lang.Dictionary>;
        }

        for (var m = 1; m < merged.size(); m += 1) {
            if ((merged[m - 1][:ts] as Number) >= (merged[m][:ts] as Number)) {
                return [] as Array<Lang.Dictionary>;
            }
        }

        return merged;
    }

    function _resolveStateFromTransitions(nowTs as Number, transitions as Array<Lang.Dictionary>) as String or Null {
        if (transitions.size() == 0) {
            return null;
        }

        var first = transitions[0];
        if (nowTs < (first[:ts] as Number)) {
            return first[:state] as String;
        }

        var selected = first[:state] as String;
        for (var i = 0; i < transitions.size(); i += 1) {
            var t = transitions[i];
            if ((t[:ts] as Number) <= nowTs) {
                selected = t[:state] as String;
            } else {
                break;
            }
        }
        return selected;
    }

    function _clearFixState() as Void {
        _hasFix = false;
        _lastFix = null;
        _lastComputeSlotKey = null;
        _cachedEvents = [];
        _cachedTransitions = [];
        _todayHasGoldenStart = false;
        _todayHasBlueStart = false;
    }

    function _getDaySlotKey(nowTs as Number) as String {
        var info = Time.Gregorian.info(new Time.Moment(nowTs), Time.FORMAT_SHORT);
        return Lang.format("$1$-$2$-$3$", [
            (info[:year] as Number).format("%04d"),
            (info[:month] as Number).format("%02d"),
            (info[:day] as Number).format("%02d")
        ]);
    }

    function _getTodayWindow(nowTs as Number) as Lang.Dictionary {
        var info = Time.Gregorian.info(new Time.Moment(nowTs), Time.FORMAT_SHORT);
        var secondsSinceMidnight = (info[:hour] as Number) * 3600
            + (info[:min] as Number) * 60
            + (info[:sec] as Number);
        var startTs = nowTs - secondsSinceMidnight;
        return {
            :startTs => startTs,
            :endTs => startTs + 86400
        };
    }

    function _computeEventsAnalyticalForDay(
        dayStartTs as Number,
        dayEndTs as Number,
        lat,
        lon
    ) as Array<Lang.Dictionary> {
        return _computeEventsAnalyticalForDayWithRefine(dayStartTs, dayEndTs, lat, lon, true);
    }

    function _computeEventsAnalyticalForDayWithRefine(
        dayStartTs as Number,
        dayEndTs as Number,
        lat,
        lon,
        refine as Boolean
    ) as Array<Lang.Dictionary> {
        return _solveAllCrossingsWithRefine(dayStartTs, dayEndTs, lat, lon, refine);
    }

    function _solveAllCrossings(startTs as Number, endTs as Number, lat, lon) as Array<Lang.Dictionary> {
        return _solveAllCrossingsWithRefine(startTs, endTs, lat, lon, true);
    }

    function _solveAllCrossingsWithRefine(startTs as Number, endTs as Number, lat, lon, refine as Boolean) as Array<Lang.Dictionary> {
        // 解析解：太阳高度角在一天内近似正弦曲线
        // alt(t) ≈ A·sin(ω·t + φ) + B
        // 其中 A = cos(lat)·cos(decl), B = sin(lat)·sin(decl), ω = 2π/86400
        // 求穿越 threshold 的时间点：A·sin(ω·t + φ) + B = threshold
        // => sin(ω·t + φ) = (threshold - B) / A
        // 每个 threshold 最多 2 个解

        var midTs = startTs + 43200;
        var jd = (midTs / 86400.0) + 2440587.5;
        var jc = (jd - 2451545.0) / 36525.0;

        // 太阳赤纬
        var meanLong = _normalizeDeg(280.46646 + jc * (36000.76983 + jc * 0.0003032));
        var meanAnom = _normalizeDeg(357.52911 + jc * (35999.05029 - 0.0001537 * jc));
        var omega = 125.04 - 1934.136 * jc;
        var mRad = _degToRad(meanAnom);
        var center = Math.sin(mRad) * (1.914602 - jc * (0.004817 + 0.000014 * jc))
            + Math.sin(2.0 * mRad) * (0.019993 - 0.000101 * jc)
            + Math.sin(3.0 * mRad) * 0.000289;
        var trueLong = meanLong + center;
        var eclipLong = trueLong - 0.00569 - 0.00478 * Math.sin(_degToRad(omega));
        var obliqMean = 23.0 + (26.0 + ((21.448 - jc * (46.815 + jc * (0.00059 - jc * 0.001813))) / 60.0)) / 60.0;
        var obliqCorr = obliqMean + 0.00256 * Math.cos(_degToRad(omega));
        var declRad = Math.asin(Math.sin(_degToRad(obliqCorr)) * Math.sin(_degToRad(eclipLong)));

        var latRad = _degToRad(lat);
        var A = Math.cos(latRad) * Math.cos(declRad);
        var B = Math.sin(latRad) * Math.sin(declRad);

        // NOAA 正午锚点（使用设备系统时区偏移，含 DST）
        var solarNoonTs = _computeNoaaSolarNoonTs(startTs, lat, lon);
        var events = [] as Array<Lang.Dictionary>;
        var thresholds = [-10.0, -4.0, 6.0];

        for (var ti = 0; ti < 3; ti += 1) {
            var threshold = thresholds[ti];
            var denom = A;
            if (_abs(denom) < DENOM_EPS) {
                continue;
            }
            // alt = asin(sin(lat)*sin(decl) + cos(lat)*cos(decl)*cos(H))
            // 令 alt = threshold => sin(threshold_rad) = B + A*cos(H)
            // => cos(H) = (sin(threshold_rad) - B) / A
            var threshRad = _degToRad(threshold);
            var rawCosH = (Math.sin(threshRad) - B) / denom;
            var cosH = rawCosH;
            var hasCrossing = true;
            if (cosH > 1.0) {
                if (cosH <= (1.0 + COSH_CLAMP_EPS)) {
                    cosH = 1.0;
                } else {
                    hasCrossing = false;
                }
            } else if (cosH < -1.0) {
                if (cosH >= (-1.0 - COSH_CLAMP_EPS)) {
                    cosH = -1.0;
                } else {
                    hasCrossing = false;
                }
            }

            if (cosH < -1.0 || cosH > 1.0) {
                hasCrossing = false;
            }

            if (!hasCrossing) {
                continue;
            }

            var H = Math.acos(cosH); // 弧度，正值
            var Hdeg = _radToDeg(H);

            // 两个穿越时刻：正午 ± H/ω
            // H 是以弧度表示的时角，转换为秒：H_sec = H_deg / (360/86400) = H_deg * 240
            var offsetSec = Hdeg * 240.0;

            var tRising = _normalizeCrossingTsToWindow(solarNoonTs - offsetSec, startTs, endTs);
            var tSetting = _normalizeCrossingTsToWindow(solarNoonTs + offsetSec, startTs, endTs);

            // day1 可关闭二分法精修以降低 watchdog 风险
            if (tRising >= startTs && tRising < endTs) {
                if (refine) {
                    var refined = _bisectRoot(tRising - 450, tRising + 450, lat, lon, threshold);
                    if (refined != null) { tRising = refined as Number; }
                }
                _addCrossingEvents(events, tRising, threshold, true);
            }
            if (tSetting >= startTs && tSetting < endTs) {
                if (refine) {
                    var refined2 = _bisectRoot(tSetting - 450, tSetting + 450, lat, lon, threshold);
                    if (refined2 != null) { tSetting = refined2 as Number; }
                }
                _addCrossingEvents(events, tSetting, threshold, false);
            }
        }

        return _sortAndDedupeEvents(events);
    }

    function _filterEventsInWindow(events as Array<Lang.Dictionary>, startTs as Number, endTs as Number) as Array<Lang.Dictionary> {
        var out = [] as Array<Lang.Dictionary>;
        for (var i = 0; i < events.size(); i += 1) {
            var ts = events[i][:ts] as Number;
            if (ts >= startTs && ts < endTs) {
                out.add(events[i]);
            }
        }
        return out;
    }

    function _normalizeCrossingTsToWindow(ts as Number, dayStartTs as Number, dayEndTs as Number) as Number {
        // 规则2：解析解若超出当日窗口且距边界小于12小时，按跨日解做 +/-86400 归一。
        if (ts < dayStartTs) {
            var dLow = dayStartTs - ts;
            if (dLow < 43200) {
                return ts + 86400;
            }
            return ts;
        }
        if (ts >= dayEndTs) {
            var dHigh = ts - dayEndTs;
            if (dHigh < 43200) {
                return ts - 86400;
            }
            return ts;
        }
        return ts;
    }

    function _addCrossingEvents(events as Array<Lang.Dictionary>, ts as Number, threshold, rising as Boolean) as Void {
        if (threshold == -10.0) {
            events.add({ :ts => ts, :type => (rising ? "BLUE_START" : "BLUE_END") });
        } else if (threshold == -4.0) {
            if (rising) {
                events.add({ :ts => ts, :type => "BLUE_END" });
                events.add({ :ts => ts, :type => "GOLDEN_START" });
            } else {
                events.add({ :ts => ts, :type => "GOLDEN_END" });
                events.add({ :ts => ts, :type => "BLUE_START" });
            }
        } else if (threshold == 6.0) {
            events.add({ :ts => ts, :type => (rising ? "GOLDEN_END" : "GOLDEN_START") });
        }
    }

    function _bisectRoot(loTs as Number, hiTs as Number, lat as Number, lon as Number, threshold) as Number or Null {
        var lo = loTs;
        var hi = hiTs;
        var altLo = _solarAltitudeDeg(lo, lat, lon);
        var altHi = _solarAltitudeDeg(hi, lat, lon);
        if (altLo == null || altHi == null) {
            return null;
        }
        if (_isNaN(altLo) || _isNaN(altHi)) {
            return null;
        }
        var fLo = (altLo as Number) - threshold;
        var fHi = (altHi as Number) - threshold;

        if (_isNaN(fLo) || _isNaN(fHi)) {
            return null;
        }

        var iter = 0;
        while ((hi - lo) > BISECT_TOLERANCE_SEC && iter < 30) {
            var mid = lo + ((hi - lo) / 2.0);
            var altMid = _solarAltitudeDeg(mid.toNumber(), lat, lon);
            if (altMid == null || _isNaN(altMid)) {
                return null;
            }
            var fMid = (altMid as Number) - threshold;

            if (_abs(fMid) < 0.001) {
                return mid.toNumber();
            }

            if ((fLo < 0 && fMid > 0) || (fLo > 0 && fMid < 0)) {
                hi = mid;
                fHi = fMid;
            } else {
                lo = mid;
                fLo = fMid;
            }

            iter += 1;
        }

        return (lo + ((hi - lo) / 2.0)).toNumber();
    }

    function _strEq(a as String or Null, b as String) as Boolean {
        return (a != null) && (a as String).equals(b);
    }

    function _findNextEventTs(events as Array<Lang.Dictionary>, nowTs as Number, typeName as String) as Number or Null {
        for (var i = 0; i < events.size(); i += 1) {
            var e = events[i];
            var ts = e[:ts] as Number;
            if (_strEq(e[:type] as String or Null, typeName) && ts > nowTs) {
                return ts;
            }
        }
        return null;
    }

    function _hasEvent(events as Array<Lang.Dictionary>, typeName as String) as Boolean {
        for (var i = 0; i < events.size(); i += 1) {
            if (_strEq(events[i][:type] as String or Null, typeName)) {
                return true;
            }
        }
        return false;
    }

    function _normalizeAndValidateEvents(events as Array<Lang.Dictionary>) as Array<Lang.Dictionary> {
        var normalized = events;
        if (!_isSortedByTs(normalized)) {
            normalized = _sortAndDedupeEvents(normalized);
        }
        if (!_hasOnlyAllowedEventTypes(normalized)) {
            return [] as Array<Lang.Dictionary>;
        }
        return normalized;
    }

    function _isSortedByTs(events as Array<Lang.Dictionary>) as Boolean {
        if (events.size() <= 1) {
            return true;
        }
        for (var i = 1; i < events.size(); i += 1) {
            if ((events[i - 1][:ts] as Number) > (events[i][:ts] as Number)) {
                return false;
            }
        }
        return true;
    }

    function _hasOnlyAllowedEventTypes(events as Array<Lang.Dictionary>) as Boolean {
        for (var i = 0; i < events.size(); i += 1) {
            var t = events[i][:type] as String or Null;
            if (t == null) {
                return false;
            }
            if (!_strEq(t, "BLUE_START") && !_strEq(t, "BLUE_END") && !_strEq(t, "GOLDEN_START") && !_strEq(t, "GOLDEN_END")) {
                return false;
            }
        }
        return true;
    }

    function _sortAndDedupeEvents(events as Array<Lang.Dictionary>) as Array<Lang.Dictionary> {
        var out = _sortEventsByTsAndPriority(events);

        var dedup = [] as Array<Lang.Dictionary>;
        for (var k = 0; k < out.size(); k += 1) {
            var cur = out[k];
            if (dedup.size() == 0) {
                dedup.add(cur);
                continue;
            }
            var last = dedup[dedup.size() - 1];
            var lastType = last[:type] as String or Null;
            var curType = cur[:type] as String or Null;
            var sameType = (lastType != null) && (curType != null) && (lastType as String).equals(curType as String);
            var sameTs = _abs((last[:ts] as Number) - (cur[:ts] as Number)) <= 1;
            if (!(sameType && sameTs)) {
                dedup.add(cur);
            }
        }

        return dedup;
    }

    function _sortEventsByTsAndPriority(events as Array<Lang.Dictionary>) as Array<Lang.Dictionary> {
        var out = [] as Array<Lang.Dictionary>;
        for (var i = 0; i < events.size(); i += 1) {
            out.add(events[i]);
        }

        var n = out.size();
        for (var p = 0; p < n; p += 1) {
            for (var q = 0; q < (n - 1 - p); q += 1) {
                var aTs = out[q][:ts] as Number;
                var bTs = out[q + 1][:ts] as Number;
                var aType = out[q][:type] as String;
                var bType = out[q + 1][:type] as String;
                var swap = false;
                if (aTs > bTs) {
                    swap = true;
                } else if (aTs == bTs && _eventPriority(aType) > _eventPriority(bType)) {
                    swap = true;
                }
                if (swap) {
                    var tmp = out[q];
                    out[q] = out[q + 1];
                    out[q + 1] = tmp;
                }
            }
        }

        return out;
    }

    function _eventPriority(typeName as String) as Number {
        if (_strEq(typeName, "BLUE_END")) {
            return 0;
        }
        if (_strEq(typeName, "GOLDEN_START")) {
            return 1;
        }
        if (_strEq(typeName, "GOLDEN_END")) {
            return 2;
        }
        if (_strEq(typeName, "BLUE_START")) {
            return 3;
        }
        return 9;
    }

    function _inferDayStartState(events as Array<Lang.Dictionary>, hasBlue as Boolean, hasGolden as Boolean) as String {
        if (events.size() == 0) {
            if (!hasBlue && !hasGolden) {
                return "DAY";
            }
            return "DAY";
        }

        var firstType = events[0][:type] as String or Null;
        if (_strEq(firstType, "BLUE_START") || _strEq(firstType, "GOLDEN_START")) {
            return "NIGHT";
        }
        if (_strEq(firstType, "BLUE_END")) {
            return "BLUE";
        }
        if (_strEq(firstType, "GOLDEN_END")) {
            return "GOLDEN";
        }
        return "DAY";
    }

    function _detectPolarDayOrNight(dayStartTs as Number, lat as Number, lon as Number) as String or Null {
        if (_abs(lat) < 60.0) {
            return null;
        }

        var t1 = dayStartTs + 21600;
        var t2 = dayStartTs + 43200;
        var t3 = dayStartTs + 64800;

        var alt1 = _solarAltitudeDeg(t1, lat, lon);
        var alt2 = _solarAltitudeDeg(t2, lat, lon);
        var alt3 = _solarAltitudeDeg(t3, lat, lon);
        if (alt1 == null || alt2 == null || alt3 == null) {
            return null;
        }
        if (_isNaN(alt1) || _isNaN(alt2) || _isNaN(alt3)) {
            return null;
        }

        var a1 = alt1 as Number;
        var a2 = alt2 as Number;
        var a3 = alt3 as Number;
        if (a1 < -10.0 && a2 < -10.0 && a3 < -10.0) {
            return "NIGHT";
        }
        if (a1 > 6.0 && a2 > 6.0 && a3 > 6.0) {
            return "DAY";
        }
        return null;
    }

    function _nextStateForEvent(
        typeName as String,
        ts as Number,
        currentState as String,
        hasGolden as Boolean,
        sortedEvents as Array<Lang.Dictionary>,
        indexHint as Number
    ) as String {
        if (_strEq(typeName, "BLUE_START")) {
            return "BLUE";
        }
        if (_strEq(typeName, "BLUE_END")) {
            if (hasGolden && _hasGoldenStartAtOrAfter(sortedEvents, ts, indexHint)) {
                return "GOLDEN";
            }
            return "NIGHT";
        }
        if (_strEq(typeName, "GOLDEN_START")) {
            return "GOLDEN";
        }
        if (_strEq(typeName, "GOLDEN_END")) {
            return "DAY";
        }
        return currentState;
    }

    function _hasGoldenStartAtOrAfter(events as Array<Lang.Dictionary>, ts as Number, indexHint as Number) as Boolean {
        for (var i = indexHint; i < events.size(); i += 1) {
            var eTs = events[i][:ts] as Number;
            if (eTs < ts) {
                continue;
            }
            if (_strEq(events[i][:type] as String or Null, "GOLDEN_START")) {
                return true;
            }
        }
        return false;
    }

    function _upsertTransition(transitions as Array<Lang.Dictionary>, ts as Number, state as String) as Void {
        if (transitions.size() == 0) {
            transitions.add({ :ts => ts, :state => state });
            return;
        }

        var last = transitions[transitions.size() - 1];
        var lastTs = last[:ts] as Number;
        if (lastTs == ts) {
            transitions[transitions.size() - 1] = { :ts => ts, :state => state };
            return;
        }

        if (!_strEq(last[:state] as String or Null, state)) {
            transitions.add({ :ts => ts, :state => state });
        }
    }

    function _isValidState(state as String) as Boolean {
        return _strEq(state, "NIGHT") || _strEq(state, "BLUE") || _strEq(state, "GOLDEN") || _strEq(state, "DAY");
    }

    function _solarAltitudeDeg(ts as Number, latDeg as Number, lonDeg as Number) as Number or Null {
        var jd = (ts / 86400.0) + 2440587.5;
        var jc = (jd - 2451545.0) / 36525.0;

        var meanLong = _normalizeDeg(280.46646 + jc * (36000.76983 + jc * 0.0003032));
        var meanAnom = _normalizeDeg(357.52911 + jc * (35999.05029 - 0.0001537 * jc));
        var omega = 125.04 - 1934.136 * jc;

        var mRad = _degToRad(meanAnom);
        var center = Math.sin(mRad) * (1.914602 - jc * (0.004817 + 0.000014 * jc))
            + Math.sin(2.0 * mRad) * (0.019993 - 0.000101 * jc)
            + Math.sin(3.0 * mRad) * 0.000289;

        var trueLong = meanLong + center;
        var eclipLong = trueLong - 0.00569 - 0.00478 * Math.sin(_degToRad(omega));

        var obliqMean = 23.0 + (26.0 + ((21.448 - jc * (46.815 + jc * (0.00059 - jc * 0.001813))) / 60.0)) / 60.0;
        var obliqCorr = obliqMean + 0.00256 * Math.cos(_degToRad(omega));

        var eclipRad = _degToRad(eclipLong);
        var obliqRad = _degToRad(obliqCorr);

        var declRad = Math.asin(Math.sin(obliqRad) * Math.sin(eclipRad));
        var raDeg = _normalizeDeg(_radToDeg(Math.atan2(Math.cos(obliqRad) * Math.sin(eclipRad), Math.cos(eclipRad))));

        var gmst = _normalizeDeg(
            280.46061837
            + 360.98564736629 * (jd - 2451545.0)
            + 0.000387933 * jc * jc
            - (jc * jc * jc) / 38710000.0
        );

        var hourAngleDeg = _normalizeSignedDeg(gmst + lonDeg - raDeg);

        var latRad = _degToRad(latDeg);
        var haRad = _degToRad(hourAngleDeg);

        var sinAlt = Math.sin(latRad) * Math.sin(declRad)
            + Math.cos(latRad) * Math.cos(declRad) * Math.cos(haRad);

        if (sinAlt > 1.0) {
            sinAlt = 1.0;
        } else if (sinAlt < -1.0) {
            sinAlt = -1.0;
        }

        return _radToDeg(Math.asin(sinAlt));
    }

    function _degToRad(v) {
        return v * Math.PI / 180.0;
    }

    function _radToDeg(v) {
        return v * 180.0 / Math.PI;
    }

    function _tail5Str(v as Number or Null) as String {
        if (v == null) {
            return "N";
        }
        var s = (v as Number).format("%d");
        if (s.length() <= 5) {
            return s;
        }
        return s.substring(s.length() - 5, s.length());
    }

    function _shortType(t as String) as String {
        if (_strEq(t, "BLUE_START")) { return "BS"; }
        if (_strEq(t, "BLUE_END")) { return "BE"; }
        if (_strEq(t, "GOLDEN_START")) { return "GS"; }
        if (_strEq(t, "GOLDEN_END")) { return "GE"; }
        return "??";
    }

    function _normalizeDeg(v) {
        var turns = Math.floor(v / 360.0);
        var out = v - (turns * 360.0);
        while (out < 0) {
            out += 360.0;
        }
        while (out >= 360.0) {
            out -= 360.0;
        }
        return out;
    }

    function _normalizeSignedDeg(v) {
        var out = _normalizeDeg(v);
        if (out > 180.0) {
            out -= 360.0;
        }
        return out;
    }

    function _inferTzOffsetSecFromLocalMidnight(localMidnightTs as Number) as Number {
        // localMidnightTs 是“本地当天 00:00”的 epoch 秒。
        // 用它在 UTC 日内的位置反推本地时区偏移（含 DST）。
        var utcSecInDay = localMidnightTs % 86400;
        if (utcSecInDay < 0) {
            utcSecInDay += 86400;
        }

        var tzOffsetSec = -utcSecInDay;
        // 归一到常见时区偏移区间，避免 +8 被表示成 -16h。
        if (tzOffsetSec <= -43200) {
            tzOffsetSec += 86400;
        } else if (tzOffsetSec > 50400) {
            tzOffsetSec -= 86400;
        }
        return tzOffsetSec;
    }

    function _getSystemUtcOffsetSec() as Number {
        var ct = System.getClockTime();
        return (ct.timeZoneOffset as Number) + (ct.dst as Number);
    }

    function _computeNoaaSolarNoonTs(dayStartTs as Number, lat as Number, lon as Number) as Number {
        var jd = (dayStartTs / 86400.0) + 2440587.5;
        var jc = (jd - 2451545.0) / 36525.0;

        var geomMeanLongSun = _normalizeDeg(280.46646 + jc * (36000.76983 + jc * 0.0003032));
        var geomMeanAnomSun = _normalizeDeg(357.52911 + jc * (35999.05029 - 0.0001537 * jc));
        var eccentEarthOrbit = 0.016708634 - jc * (0.000042037 + 0.0000001267 * jc);
        var omega = 125.04 - 1934.136 * jc;

        var mRad = _degToRad(geomMeanAnomSun);
        var sunEqOfCtr = Math.sin(mRad) * (1.914602 - jc * (0.004817 + 0.000014 * jc))
            + Math.sin(2.0 * mRad) * (0.019993 - 0.000101 * jc)
            + Math.sin(3.0 * mRad) * 0.000289;
        var sunTrueLong = geomMeanLongSun + sunEqOfCtr;
        var sunAppLong = sunTrueLong - 0.00569 - 0.00478 * Math.sin(_degToRad(omega));

        var meanObliqEcliptic = 23.0 + (26.0 + ((21.448 - jc * (46.815 + jc * (0.00059 - jc * 0.001813))) / 60.0)) / 60.0;
        var obliqCorr = meanObliqEcliptic + 0.00256 * Math.cos(_degToRad(omega));
        var varY = Math.tan(_degToRad(obliqCorr) / 2.0);
        varY = varY * varY;

        var eqOfTimeMinutes = 4.0 * _radToDeg(
            varY * Math.sin(2.0 * _degToRad(geomMeanLongSun))
            - 2.0 * eccentEarthOrbit * Math.sin(mRad)
            + 4.0 * eccentEarthOrbit * varY * Math.sin(mRad) * Math.cos(2.0 * _degToRad(geomMeanLongSun))
            - 0.5 * varY * varY * Math.sin(4.0 * _degToRad(geomMeanLongSun))
            - 1.25 * eccentEarthOrbit * eccentEarthOrbit * Math.sin(2.0 * mRad)
        );

        var tzOffsetSec = _getSystemUtcOffsetSec();
        var tzOffsetMinutes = tzOffsetSec / 60.0;
        var solarNoonMinutes = 720.0 - 4.0 * lon - eqOfTimeMinutes + tzOffsetMinutes;
        var solarNoonTs = dayStartTs + (solarNoonMinutes * 60.0).toNumber();
        var dayEndTs = dayStartTs + 86400;

        while (solarNoonTs < dayStartTs) { solarNoonTs += 86400; }
        while (solarNoonTs >= dayEndTs) { solarNoonTs -= 86400; }
        return solarNoonTs;
    }

    function _abs(v) {
        return (v < 0) ? -v : v;
    }

    function _isNaN(x) {
        return x != x;
    }
}
