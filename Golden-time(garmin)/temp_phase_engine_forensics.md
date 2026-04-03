`rg -n "var |const " source/SunAltService.mc`
```text
7:    const DEBUG_LOG = false;
8:    const LOC_CHANGE_THRESHOLD_DEG = 0.01;
9:    const COARSE_STEP_SEC = 900;  // 15 分钟步长，更精确
10:    const BISECT_TOLERANCE_SEC = 1;
11:    const ALT_ZERO_EPS_DEG = 0.01;
13:    var _hasFix as Boolean;
14:    var _lastFix as Lang.Dictionary or Null;
15:    var _lastComputeSlotKey as String or Null;
16:    var _cachedEvents as Array<Lang.Dictionary>;
17:    var _todayHasGoldenStart as Boolean;
18:    var _todayHasBlueStart as Boolean;
19:    var _warnedInRecompute as Boolean;
43:        var needRecompute = false;
44:        var slotKey = _getLocalSlotKey();
53:            var dLat = _abs((fix[:lat] as Number) - (_lastFix[:lat] as Number));
54:            var dLon = _abs((fix[:lon] as Number) - (_lastFix[:lon] as Number));
71:        var lat = fix[:lat] as Number;
72:        var lon = fix[:lon] as Number;
76:        var dayWindow = _getTodayWindow(nowTs);
77:        var windowStartTs = dayWindow[:startTs] as Number;
79:        var eventData = _computeWindowEvents(windowStartTs, lat, lon);
84:        var nextGoldenStart = _findNextGoldenOrBlue(_cachedEvents, nowTs, "GOLDEN");
85:        var nextBlueStart = _findNextGoldenOrBlue(_cachedEvents, nowTs, "BLUE");
86:        var dMinText = "--";
106:            var altNow = _solarAltitudeDeg(nowTs, lat, lon);
107:            var altPlus5 = _solarAltitudeDeg(nowTs + COARSE_STEP_SEC, lat, lon);
108:            var dAlt = (altNow == null || altPlus5 == null) ? null : ((altPlus5 as Number) - (altNow as Number));
116:            for (var i = 0; i < _cachedEvents.size(); i++) {
117:                var e = _cachedEvents[i];
124:        var dayWindow = _getTodayWindow(nowTs);
125:        var windowStartTs = dayWindow[:startTs] as Number;
126:        var windowEndTs = windowStartTs + (86400 * 2);
127:        var dayStartUtc = _getUtcDayStart(nowTs);
152:        var lat = _lastFix[:lat] as Number;
153:        var lon = _lastFix[:lon] as Number;
154:        var alt = _solarAltitudeDeg(nowTs, lat, lon);
155:        var mode = _modeFromAltitude(alt);
158:        var nextGolden = _findNextGoldenOrBlue(_cachedEvents, nowTs, "GOLDEN");
159:        var nextBlue = _findNextGoldenOrBlue(_cachedEvents, nowTs, "BLUE");
160:        var morningBlueStartTs = _findFirstEventTsByType(_cachedEvents, "MORNING_BLUE_START");
161:        var morningBlueEndTs = _findFirstEventTsByType(_cachedEvents, "MORNING_BLUE_END");
162:        var morningGoldenStartTs = _findFirstEventTsByType(_cachedEvents, "MORNING_GOLDEN_START");
163:        var morningGoldenEndTs = _findFirstEventTsByType(_cachedEvents, "MORNING_GOLDEN_END");
164:        var eveningGoldenStartTs = _findFirstEventTsByType(_cachedEvents, "EVENING_GOLDEN_START");
165:        var eveningGoldenEndTs = _findFirstEventTsByType(_cachedEvents, "EVENING_GOLDEN_END");
166:        var eveningBlueStartTs = _findFirstEventTsByType(_cachedEvents, "EVENING_BLUE_START");
167:        var eveningBlueEndTs = _findFirstEventTsByType(_cachedEvents, "EVENING_BLUE_END");
198:        for (var i = 0; i < events.size(); i += 1) {
199:            var e = events[i];
200:            var typeStr = e[:type] as String;
215:        for (var i = 0; i < events.size(); i += 1) {
216:            var typeStr = events[i][:type] as String;
225:        for (var i = 0; i < events.size(); i += 1) {
226:            var e = events[i];
227:            var t = e[:type];
229:            var typeStr = t as String or Null;
233:            var typeText = Lang.format("$1$", [t]);
243:        var windowEndTs = startTs + (86400 * 2);
244:        var events = [] as Array<Lang.Dictionary>;
247:        var todayMorningStart = startTs + (4 * 3600);
248:        var todayMorningEnd = startTs + (10 * 3600);
249:        var todayEveningStart = startTs + (16 * 3600);
250:        var todayEveningEnd = startTs + (22 * 3600);
252:        var todayMorning = _scanPeriod(todayMorningStart, todayMorningEnd, lat, lon, true);
253:        var todayEvening = _scanPeriod(todayEveningStart, todayEveningEnd, lat, lon, false);
256:        var tomorrowStart = startTs + 86400;
257:        var tomorrowMorningStart = tomorrowStart + (4 * 3600);
258:        var tomorrowMorningEnd = tomorrowStart + (10 * 3600);
259:        var tomorrowEveningStart = tomorrowStart + (16 * 3600);
260:        var tomorrowEveningEnd = tomorrowStart + (22 * 3600);
262:        var tomorrowMorning = _scanPeriod(tomorrowMorningStart, tomorrowMorningEnd, lat, lon, true);
263:        var tomorrowEvening = _scanPeriod(tomorrowEveningStart, tomorrowEveningEnd, lat, lon, false);
266:        for (var i = 0; i < todayMorning.size(); i++) {
269:        for (var i = 0; i < todayEvening.size(); i++) {
272:        for (var i = 0; i < tomorrowMorning.size(); i++) {
275:        for (var i = 0; i < tomorrowEvening.size(); i++) {
285:        var events = [] as Array<Lang.Dictionary>;
299:        var morningBlueStart = null;      // 时间点 1
300:        var morningBlueGoldenBoundary = null;  // 时间点 2（共享）
301:        var morningGoldenEnd = null;      // 时间点 3
303:        var eveningGoldenStart = null;    // 时间点 4
304:        var eveningGoldenBlueBoundary = null;  // 时间点 5（共享）
305:        var eveningBlueEnd = null;        // 时间点 6
330:        var prefix = isMorning ? "MORNING" : "EVENING";
362:        var dayStart = _getUtcDayStart(startTs);
365:            var result = _solveAltitudeCrossing(dayStart, lat, lon, targetAlt, rising);
381:        var jd = (dayStartTs / 86400.0) + 2440587.5;
382:        var jc = (jd - 2451545.0) / 36525.0;
384:        var meanLong = _normalizeDeg(280.46646 + jc * (36000.76983 + jc * 0.0003032));
385:        var meanAnom = _normalizeDeg(357.52911 + jc * (35999.05029 - 0.0001537 * jc));
386:        var omega = 125.04 - 1934.136 * jc;
387:        var m_rad = _toRadians(meanAnom);
388:        var center = (_sin(m_rad) * (1.914602 - jc * (0.004817 + 0.000014 * jc))
391:        var trueLong = meanLong + center;
392:        var eclipLong = trueLong - 0.00569 - 0.00478 * _sin(_toRadians(omega));
393:        var obliqMean = 23.0 + (26.0 + ((21.448 - jc * (46.815 + jc * (0.00059 - jc * 0.001813))) / 60.0)) / 60.0;
394:        var obliqCorr = obliqMean + 0.00256 * _cos(_toRadians(omega));
395:        var eclipRad = _toRadians(eclipLong);
396:        var obliqRad = _toRadians(obliqCorr);
397:        var declRad = _asin(_sin(obliqRad) * _sin(eclipRad));
400:        var varY = _tan(obliqRad / 2.0) * _tan(obliqRad / 2.0);
401:        var eqOfTime = 4.0 * _toDegrees(
410:        var latRad = _toRadians(latDeg);
411:        var altRad = _toRadians(altDeg);
413:        var sinAlt = _sin(altRad);
414:        var sinLat = _sin(latRad);
415:        var cosLat = _cos(latRad);
416:        var sinDecl = _sin(declRad);
417:        var cosDecl = _cos(declRad);
419:        var numerator = sinAlt - sinLat * sinDecl;
420:        var denominator = cosLat * cosDecl;
426:        var cosH = numerator / denominator;
432:        var hourAngleDeg = _toDegrees(_acos(cosH));
435:        var timezoneOffset = _round(lonDeg / 15.0);
436:        var solarNoonMinutes = 720.0 - 4.0 * lonDeg - eqOfTime + timezoneOffset * 60.0;
437:        var solarNoonHourLocal = solarNoonMinutes / 60.0;
440:        var timeOffsetHours = hourAngleDeg / 15.0;
441:        var eventHourLocal = solarNoonHourLocal + (rising ? -timeOffsetHours : timeOffsetHours);
452:        var eventHourUtc = eventHourLocal - timezoneOffset;
453:        var eventTs = dayStartTs + (eventHourUtc * 3600.0).toNumber();
459:        for (var i = 0; i < events.size(); i += 1) {
460:            var e = events[i];
469:        for (var i = 0; i < events.size(); i += 1) {
478:        var out = [] as Array<Lang.Dictionary>;
479:        for (var i = 0; i < events.size(); i += 1) {
483:        var n = out.size();
484:        for (var p = 0; p < n; p += 1) {
485:            for (var q = 0; q < (n - 1 - p); q += 1) {
486:                var tA = out[q][:ts] as Number;
487:                var tB = out[q + 1][:ts] as Number;
489:                    var tmp = out[q];
507:        var lo = loTs;
508:        var hi = hiTs;
509:        var altLo = _solarAltitudeDeg(lo, lat, lon);
510:        var altHi = _solarAltitudeDeg(hi, lat, lon);
516:        var fLo = (altLo as Number) - threshold;
517:        var fHi = (altHi as Number) - threshold;
529:        var iterations = 0;
532:            var diff = hi - lo;
533:            var mid = lo + (diff / 2.0).toNumber();
539:            var altMid = _solarAltitudeDeg(mid, lat, lon);
544:            var fMid = (altMid as Number) - threshold;
568:        var result = lo + ((hi - lo) / 2.0).toNumber();
577:        var jd = (ts / 86400.0) + 2440587.5;
578:        var jc = (jd - 2451545.0) / 36525.0;
580:        var meanLong = _normalizeDeg(280.46646 + jc * (36000.76983 + jc * 0.0003032));
581:        var meanAnom = _normalizeDeg(357.52911 + jc * (35999.05029 - 0.0001537 * jc));
582:        var omega = 125.04 - 1934.136 * jc;
584:        var mRad = _degToRad(meanAnom);
585:        var center = Math.sin(mRad) * (1.914602 - jc * (0.004817 + 0.000014 * jc))
589:        var trueLong = meanLong + center;
590:        var eclipLong = trueLong - 0.00569 - 0.00478 * Math.sin(_degToRad(omega));
592:        var obliqMean = 23.0 + (26.0 + ((21.448 - jc * (46.815 + jc * (0.00059 - jc * 0.001813))) / 60.0)) / 60.0;
593:        var obliqCorr = obliqMean + 0.00256 * Math.cos(_degToRad(omega));
595:        var eclipRad = _degToRad(eclipLong);
596:        var obliqRad = _degToRad(obliqCorr);
598:        var declRad = Math.asin(Math.sin(obliqRad) * Math.sin(eclipRad));
599:        var raDeg = _normalizeDeg(_radToDeg(Math.atan2(Math.cos(obliqRad) * Math.sin(eclipRad), Math.cos(eclipRad))));
601:        var gmst = _normalizeDeg(
608:        var hourAngleDeg = _normalizeSignedDeg(gmst + lonDeg - raDeg);
610:        var latRad = _degToRad(latDeg);
611:        var haRad = _degToRad(hourAngleDeg);
613:        var sinAlt = Math.sin(latRad) * Math.sin(declRad)
615:        var sinAltClamped = sinAlt;
624:        var alt = _radToDeg(Math.asin(sinAltClamped));
657:        var info = Time.Gregorian.info(new Time.Moment(nowTs), Time.FORMAT_SHORT);
658:        var secondsSinceMidnight = (info[:hour] as Number) * 3600 
661:        var startTs = nowTs - secondsSinceMidnight;
669:        var info = Time.Gregorian.info(Time.now(), Time.FORMAT_SHORT);
670:        var slot = ((info[:hour] as Number) < 12) ? "AM" : "PM";
680:        var dayWindow = _getTodayWindow(nowTs);
681:        var startTs = dayWindow[:startTs] as Number;
682:        var clock = System.getClockTime();
736:        var turns = Math.floor(v / 360.0);
737:        var out = v - (turns * 360.0);
748:        var out = _normalizeDeg(v);
786:        var m = new Time.Moment(ts as Number);
787:        var info = Time.Gregorian.info(m, Time.FORMAT_SHORT);
813:        var altAtRoot = _solarAltitudeDeg(rootTs, lat, lon);
814:        var errDeg = (altAtRoot == null || _isNaN(altAtRoot)) ? "--" : _fmt2((altAtRoot as Number) - threshold);
```

`rg -n "Ts" source/SunAltService.mc`
```text
31:    function updateIfNeeded(nowTs as Number, fix as Lang.Dictionary or Null) as Void {
76:        var dayWindow = _getTodayWindow(nowTs);
77:        var windowStartTs = dayWindow[:startTs] as Number;
79:        var eventData = _computeWindowEvents(windowStartTs, lat, lon);
84:        var nextGoldenStart = _findNextGoldenOrBlue(_cachedEvents, nowTs, "GOLDEN");
85:        var nextBlueStart = _findNextGoldenOrBlue(_cachedEvents, nowTs, "BLUE");
98:                    _fmtTs(nextGoldenStart),
99:                    _fmtTs(nextBlueStart),
105:            System.println(Lang.format("[DEBUG] nowTs=$1$ windowStartTs=$2$", [nowTs, windowStartTs]));
106:            var altNow = _solarAltitudeDeg(nowTs, lat, lon);
107:            var altPlus5 = _solarAltitudeDeg(nowTs + COARSE_STEP_SEC, lat, lon);
118:                System.println(Lang.format("  [$1$] $2$ at $3$", [i, e[:type], _fmtTs(e[:ts])]));
123:    function getSnapshot(nowTs as Number) as Lang.Dictionary {
124:        var dayWindow = _getTodayWindow(nowTs);
125:        var windowStartTs = dayWindow[:startTs] as Number;
126:        var windowEndTs = windowStartTs + (86400 * 2);
127:        var dayStartUtc = _getUtcDayStart(nowTs);
134:                :nextGoldenStartTs => null,
135:                :nextBlueStartTs => null,
136:                :morningBlueStartTs => null,
137:                :morningBlueEndTs => null,
138:                :morningGoldenStartTs => null,
139:                :morningGoldenEndTs => null,
140:                :eveningGoldenStartTs => null,
141:                :eveningGoldenEndTs => null,
142:                :eveningBlueStartTs => null,
143:                :eveningBlueEndTs => null,
147:                :windowStartTs => windowStartTs,
148:                :windowEndTs => windowEndTs
154:        var alt = _solarAltitudeDeg(nowTs, lat, lon);
158:        var nextGolden = _findNextGoldenOrBlue(_cachedEvents, nowTs, "GOLDEN");
159:        var nextBlue = _findNextGoldenOrBlue(_cachedEvents, nowTs, "BLUE");
160:        var morningBlueStartTs = _findFirstEventTsByType(_cachedEvents, "MORNING_BLUE_START");
161:        var morningBlueEndTs = _findFirstEventTsByType(_cachedEvents, "MORNING_BLUE_END");
162:        var morningGoldenStartTs = _findFirstEventTsByType(_cachedEvents, "MORNING_GOLDEN_START");
163:        var morningGoldenEndTs = _findFirstEventTsByType(_cachedEvents, "MORNING_GOLDEN_END");
164:        var eveningGoldenStartTs = _findFirstEventTsByType(_cachedEvents, "EVENING_GOLDEN_START");
165:        var eveningGoldenEndTs = _findFirstEventTsByType(_cachedEvents, "EVENING_GOLDEN_END");
166:        var eveningBlueStartTs = _findFirstEventTsByType(_cachedEvents, "EVENING_BLUE_START");
167:        var eveningBlueEndTs = _findFirstEventTsByType(_cachedEvents, "EVENING_BLUE_END");
170:            System.println(Lang.format("[getSnapshot] nowTs=$1$ nextGolden=$2$ nextBlue=$3$", [nowTs, nextGolden, nextBlue]));
177:            :nextGoldenStartTs => nextGolden,
178:            :nextBlueStartTs => nextBlue,
179:            :morningBlueStartTs => morningBlueStartTs,
180:            :morningBlueEndTs => morningBlueEndTs,
181:            :morningGoldenStartTs => morningGoldenStartTs,
182:            :morningGoldenEndTs => morningGoldenEndTs,
183:            :eveningGoldenStartTs => eveningGoldenStartTs,
184:            :eveningGoldenEndTs => eveningGoldenEndTs,
185:            :eveningBlueStartTs => eveningBlueStartTs,
186:            :eveningBlueEndTs => eveningBlueEndTs,
191:            :windowStartTs => windowStartTs,
192:            :windowEndTs => windowEndTs
196:    function _findNextGoldenOrBlue(events as Array<Lang.Dictionary>, nowTs as Number, kind as String) as Number or Null {
201:            if (typeStr.find(kind + "_START") != null && (e[:ts] as Number) > nowTs) {
209:            System.println(Lang.format("[_findNext] NOT FOUND: $1$ (nowTs=$2$)", [kind, nowTs]));
224:    function _findFirstEventTsByType(events as Array<Lang.Dictionary>, typeName as String) as Number or Null {
241:    function _computeWindowEvents(startTs as Number, lat as Number, lon as Number) as Lang.Dictionary {
243:        var windowEndTs = startTs + (86400 * 2);
247:        var todayMorningStart = startTs + (4 * 3600);
248:        var todayMorningEnd = startTs + (10 * 3600);
249:        var todayEveningStart = startTs + (16 * 3600);
250:        var todayEveningEnd = startTs + (22 * 3600);
256:        var tomorrowStart = startTs + 86400;
280:            :events => _sortEventsByTs(events)
284:    function _scanPeriod(startTs as Number, endTs as Number, lat as Number, lon as Number, isMorning as Boolean) as Array<Lang.Dictionary> {
288:            System.println(Lang.format("[_scanPeriod] start=$1$ end=$2$ isMorning=$3$", [startTs, endTs, isMorning ? "1" : "0"]));
309:            morningBlueStart = _scanForThreshold(startTs, endTs, lat, lon, -10.0, true);
310:            morningBlueGoldenBoundary = _scanForThreshold(startTs, endTs, lat, lon, -4.0, true);
311:            morningGoldenEnd = _scanForThreshold(startTs, endTs, lat, lon, 6.0, true);
314:            eveningGoldenStart = _scanForThreshold(startTs, endTs, lat, lon, 6.0, false);
315:            eveningGoldenBlueBoundary = _scanForThreshold(startTs, endTs, lat, lon, -4.0, false);
316:            eveningBlueEnd = _scanForThreshold(startTs, endTs, lat, lon, -10.0, false);
360:    function _scanForThreshold(startTs as Number, endTs as Number, lat as Number, lon as Number, targetAlt as Float, rising as Boolean) as Number or Null {
362:        var dayStart = _getUtcDayStart(startTs);
364:        while (dayStart < endTs) {
366:            if (result != null && result >= startTs && result <= endTs) {
379:    function _solveAltitudeCrossing(dayStartTs as Number, latDeg as Number, lonDeg as Number, altDeg as Float, rising as Boolean) as Number or Null {
381:        var jd = (dayStartTs / 86400.0) + 2440587.5;
453:        var eventTs = dayStartTs + (eventHourUtc * 3600.0).toNumber();
455:        return eventTs;
458:    function _findNextEventTs(events as Array<Lang.Dictionary>, nowTs as Number, typeName as String) as Number or Null {
461:            if (e[:type] == typeName && (e[:ts] as Number) > nowTs) {
477:    function _sortEventsByTs(events as Array<Lang.Dictionary>) as Array<Lang.Dictionary> {
506:    function _bisectRoot(loTs, hiTs, lat, lon, threshold) {
507:        var lo = loTs;
508:        var hi = hiTs;
655:    function _getTodayWindow(nowTs as Number) as Lang.Dictionary {
656:        // 使用传入的 nowTs 计算当天 00:00 的时间戳
657:        var info = Time.Gregorian.info(new Time.Moment(nowTs), Time.FORMAT_SHORT);
661:        var startTs = nowTs - secondsSinceMidnight;
663:            :startTs => startTs,
664:            :nextDayTs => startTs + 86400
679:    function _getSlotStartTs(nowTs as Number) as Number {
680:        var dayWindow = _getTodayWindow(nowTs);
681:        var startTs = dayWindow[:startTs] as Number;
684:            return startTs + 43200;
686:        return startTs;
782:    function _fmtTs(ts) as String {
809:    function _logCross(kind as String, dir as String, threshold, t0, alt0, t1, alt1, rootTs, lat, lon) as Void {
813:        var altAtRoot = _solarAltitudeDeg(rootTs, lat, lon);
817:            [kind, dir, threshold, t0, _fmt1(alt0), t1, _fmt1(alt1), _fmtTs(rootTs), errDeg]
```

`rg -n "alt" source/SunAltService.mc`
```text
106:            var altNow = _solarAltitudeDeg(nowTs, lat, lon);
107:            var altPlus5 = _solarAltitudeDeg(nowTs + COARSE_STEP_SEC, lat, lon);
108:            var dAlt = (altNow == null || altPlus5 == null) ? null : ((altPlus5 as Number) - (altNow as Number));
110:                "[AltDelta] altNow=$1$ alt+5m=$2$ dAlt=$3$deg",
111:                [_fmtAlt(altNow), _fmtAlt(altPlus5), _fmtAlt(dAlt)]
133:                :altDeg => null,
154:        var alt = _solarAltitudeDeg(nowTs, lat, lon);
155:        var mode = _modeFromAltitude(alt);
176:            :altDeg => alt,
368:                    System.println(Lang.format("[_scanForThreshold] Solved crossing at $1$ for alt=$2$", [result, targetAlt]));
379:    function _solveAltitudeCrossing(dayStartTs as Number, latDeg as Number, lonDeg as Number, altDeg as Float, rising as Boolean) as Number or Null {
411:        var altRad = _toRadians(altDeg);
413:        var sinAlt = _sin(altRad);
499:    function _isCrossing(alt0, alt1, thresholdAltDeg, rising) {
501:            return alt0 < thresholdAltDeg && alt1 >= thresholdAltDeg;
503:        return alt0 > thresholdAltDeg && alt1 <= thresholdAltDeg;
509:        var altLo = _solarAltitudeDeg(lo, lat, lon);
510:        var altHi = _solarAltitudeDeg(hi, lat, lon);
512:        if (altLo == null || altHi == null || _isNaN(altLo) || _isNaN(altHi)) {
516:        var fLo = (altLo as Number) - threshold;
517:        var fHi = (altHi as Number) - threshold;
539:            var altMid = _solarAltitudeDeg(mid, lat, lon);
540:            if (altMid == null || _isNaN(altMid)) {
544:            var fMid = (altMid as Number) - threshold;
552:                    System.println(Lang.format("[_bisect] CONVERGED: mid=$1$ altMid=$2$ iter=$3$", [mid, altMid, iterations]));
576:        // NOAA-style approximate solar position for solar-center altitude.
624:        var alt = _radToDeg(Math.asin(sinAltClamped));
625:        if (_isNaN(declRad) || _isNaN(raDeg) || _isNaN(gmst) || _isNaN(hourAngleDeg) || _isNaN(sinAlt) || _isNaN(alt)) {
627:                "[SolarWarn] NaN decl=$1$ ra=$2$ gmst=$3$ ha=$4$ sinAlt=$5$ alt=$6$",
628:                [declRad, raDeg, gmst, hourAngleDeg, sinAlt, alt]
633:        return alt;
636:    function _modeFromAltitude(altDeg) {
637:        if (altDeg == null || _isNaN(altDeg)) {
640:        if (_abs(altDeg) < ALT_ZERO_EPS_DEG) {
643:        if (altDeg > 6.0) {
646:        if (altDeg >= 0.0) {
649:        if (altDeg >= -6.0) {
809:    function _logCross(kind as String, dir as String, threshold, t0, alt0, t1, alt1, rootTs, lat, lon) as Void {
813:        var altAtRoot = _solarAltitudeDeg(rootTs, lat, lon);
814:        var errDeg = (altAtRoot == null || _isNaN(altAtRoot)) ? "--" : _fmt2((altAtRoot as Number) - threshold);
816:            "[Cross] kind=$1$ dir=$2$ thr=$3$ t0=$4$ alt0=$5$ t1=$6$ alt1=$7$ root=$8$ errDeg=$9$",
817:            [kind, dir, threshold, t0, _fmt1(alt0), t1, _fmt1(alt1), _fmtTs(rootTs), errDeg]
```

`rg -n "dayStart|window" source/SunAltService.mc`
```text
77:        var windowStartTs = dayWindow[:startTs] as Number;
79:        var eventData = _computeWindowEvents(windowStartTs, lat, lon);
105:            System.println(Lang.format("[DEBUG] nowTs=$1$ windowStartTs=$2$", [nowTs, windowStartTs]));
125:        var windowStartTs = dayWindow[:startTs] as Number;
126:        var windowEndTs = windowStartTs + (86400 * 2);
127:        var dayStartUtc = _getUtcDayStart(nowTs);
146:                :dayStartUtc => dayStartUtc,
147:                :windowStartTs => windowStartTs,
148:                :windowEndTs => windowEndTs
190:            :dayStartUtc => dayStartUtc,
191:            :windowStartTs => windowStartTs,
192:            :windowEndTs => windowEndTs
243:        var windowEndTs = startTs + (86400 * 2);
362:        var dayStart = _getUtcDayStart(startTs);
364:        while (dayStart < endTs) {
365:            var result = _solveAltitudeCrossing(dayStart, lat, lon, targetAlt, rising);
372:            dayStart += 86400;  // 下一天
379:    function _solveAltitudeCrossing(dayStartTs as Number, latDeg as Number, lonDeg as Number, altDeg as Float, rising as Boolean) as Number or Null {
381:        var jd = (dayStartTs / 86400.0) + 2440587.5;
453:        var eventTs = dayStartTs + (eventHourUtc * 3600.0).toNumber();
```

`rg -n "_phase" source/Golden-timeView.mc`
```text
20:    var _phase as String;
32:        _phase = "DAY";
61:        _phase = phase;
64:            System.println(Lang.format("[PHASE_BYTES] phaseText=$1$", [Lang.format("$1$", [_phase])]));
65:            System.println(Lang.format("[PHASE_TOSTR] phaseToString=$1$", [_phase.toString()]));
153:            System.println(Lang.format("[BG_PICK] phase=$1$", [_phase]));
163:        var bmp = _getBackgroundBitmap(_phase);
183:        var isDay = (_phase != null) && (_phase as String).equals("DAY");
191:            System.println(Lang.format("[COLOR_MAIN] func=_drawTime phase=$1$ mainColor=$2$ cond=$3$", [_phase, mainColor, isDay]));
218:        var isDay = (_phase != null) && (_phase as String).equals("DAY");
226:            System.println(Lang.format("[COLOR_MAIN] func=_drawDate phase=$1$ mainColor=$2$ cond=$3$", [_phase, mainColor, isDay]));
249:        var bmp = _getCelestialBitmap(_phase);
453:            return _phaseFromMode(snap[:mode] as String or Null);
466:    function _phaseFromMode(mode as String or Null) as String {
```

`rg -n "getPhase" source/Golden-timeView.mc`
```text
57:        var phase = _getPhase(nowTs, snap);
106:                        _getPhase(morningProbe, snap),
108:                        _getPhase(dayProbe, snap),
110:                        _getPhase(eveningProbe, snap),
112:                        _getPhase(nightProbe, snap)
127:                    _getPhase(150, phaseTestSnap),
128:                    _getPhase(300, phaseTestSnap),
129:                    _getPhase(550, phaseTestSnap),
130:                    _getPhase(50, phaseTestSnap)
442:    function _getPhase(nowTs as Number, snap as Lang.Dictionary) as String {
```

`rg -n "altDeg" source/Golden-timeView.mc`
```text
66:            System.println("[SNAP_KEYS] [:mode, :hasFix, :altDeg, :nextGoldenStartTs, :nextBlueStartTs, :todayHasGoldenStart, :todayHasBlueStart, :dayStartUtc, :windowStartTs, :windowEndTs, :dbgDeltaMin, :morningBlueStartTs, :morningBlueEndTs, :morningGoldenStartTs, :morningGoldenEndTs, :eveningGoldenStartTs, :eveningGoldenEndTs, :eveningBlueStartTs, :eveningBlueEndTs]");
69:                "[SNAP_MAP] phase=$1$ mode=$2$ hasFix=$3$ altDeg=$4$ nextGoldenStartTs=$5$ nextBlueStartTs=$6$ todayHasGoldenStart=$7$ todayHasBlueStart=$8$ dayStartUtc=$9$ windowStartTs=$10$ windowEndTs=$11$ dbgDeltaMin=$12$ morningBlueStartTs=$13$ morningBlueEndTs=$14$ morningGoldenStartTs=$15$ morningGoldenEndTs=$16$ eveningGoldenStartTs=$17$ eveningGoldenEndTs=$18$ eveningBlueStartTs=$19$ eveningBlueEndTs=$20$",
74:                    snap[:altDeg],
```

`rg -n "SunAltService" source/Golden-timeView.mc`
```text
19:    var _sunAltService as SunAltService;
31:        _sunAltService = new SunAltService();
```

`rg -n "function _getPhase|function _phaseFromMode|_getPhase\(|_phaseFromMode\(|updateIfNeeded|getSnapshot|_drawDualCountdown|_formatRemaining" source/Golden-timeView.mc`
```text
55:        _sunAltService.updateIfNeeded(nowTs, hardStale ? null : fix);
56:        var snap = _sunAltService.getSnapshot(nowTs);
57:        var phase = _getPhase(nowTs, snap);
106:                        _getPhase(morningProbe, snap),
108:                        _getPhase(dayProbe, snap),
110:                        _getPhase(eveningProbe, snap),
112:                        _getPhase(nightProbe, snap)
127:                    _getPhase(150, phaseTestSnap),
128:                    _getPhase(300, phaseTestSnap),
129:                    _getPhase(550, phaseTestSnap),
130:                    _getPhase(50, phaseTestSnap)
138:        _drawDualCountdown(dc, snap, nowTs, w, h, hardStale, softStale);
253:    function _drawDualCountdown(dc as Dc, snap as Lang.Dictionary, nowTs as Number, w as Number, h as Number, hardStale as Boolean, softStale as Boolean) as Void {
442:    function _getPhase(nowTs as Number, snap as Lang.Dictionary) as String {
453:            return _phaseFromMode(snap[:mode] as String or Null);
466:    function _phaseFromMode(mode as String or Null) as String {
```

`rg -n "Blue" source/Golden-timeView.mc`
```text
66:            System.println("[SNAP_KEYS] [:mode, :hasFix, :altDeg, :nextGoldenStartTs, :nextBlueStartTs, :todayHasGoldenStart, :todayHasBlueStart, :dayStartUtc, :windowStartTs, :windowEndTs, :dbgDeltaMin, :morningBlueStartTs, :morningBlueEndTs, :morningGoldenStartTs, :morningGoldenEndTs, :eveningGoldenStartTs, :eveningGoldenEndTs, :eveningBlueStartTs, :eveningBlueEndTs]");
69:                "[SNAP_MAP] phase=$1$ mode=$2$ hasFix=$3$ altDeg=$4$ nextGoldenStartTs=$5$ nextBlueStartTs=$6$ todayHasGoldenStart=$7$ todayHasBlueStart=$8$ dayStartUtc=$9$ windowStartTs=$10$ windowEndTs=$11$ dbgDeltaMin=$12$ morningBlueStartTs=$13$ morningBlueEndTs=$14$ morningGoldenStartTs=$15$ morningGoldenEndTs=$16$ eveningGoldenStartTs=$17$ eveningGoldenEndTs=$18$ eveningBlueStartTs=$19$ eveningBlueEndTs=$20$",
76:                    snap[:nextBlueStartTs],
78:                    snap[:todayHasBlueStart],
83:                    snap[:morningBlueStartTs],
84:                    snap[:morningBlueEndTs],
89:                    snap[:eveningBlueStartTs],
90:                    snap[:eveningBlueEndTs]
93:            var morningBlueStartTs = snap[:morningBlueStartTs] as Number or Null;
96:            var eveningBlueEndTs = snap[:eveningBlueEndTs] as Number or Null;
97:            if (morningBlueStartTs != null && morningGoldenEndTs != null && eveningGoldenStartTs != null && eveningBlueEndTs != null) {
98:                var morningProbe = ((morningBlueStartTs as Number) + (((morningGoldenEndTs as Number) - (morningBlueStartTs as Number)) / 2.0)).toNumber();
100:                var eveningProbe = ((eveningGoldenStartTs as Number) + (((eveningBlueEndTs as Number) - (eveningGoldenStartTs as Number)) / 2.0)).toNumber();
101:                var nightProbe = (morningBlueStartTs as Number) - 60;
119:                :morningBlueStartTs => 100,
122:                :eveningBlueEndTs => 600
142:        var blueTs = hasFix ? (snap[:nextBlueStartTs] as Number or Null) : null;
144:        if (!((snap[:todayHasBlueStart] as Boolean) || false)) {
156:                [phase, snap[:dayStartUtc], snap[:windowStartTs], snap[:windowEndTs], blueText, goldenText, snap[:nextBlueStartTs], snap[:nextGoldenStartTs]]
266:        var blueTs = hasFix ? (snap[:nextBlueStartTs] as Number or Null) : null;
269:        if (!((snap[:todayHasBlueStart] as Boolean) || false)) {
276:        var morningBlueStartTs = snap[:morningBlueStartTs] as Number or Null;
277:        var morningBlueEndTs = snap[:morningBlueEndTs] as Number or Null;
278:        var eveningBlueStartTs = snap[:eveningBlueStartTs] as Number or Null;
279:        var eveningBlueEndTs = snap[:eveningBlueEndTs] as Number or Null;
285:        var isBlueNow =
286:            (morningBlueStartTs != null && morningBlueEndTs != null
287:                && nowTs >= (morningBlueStartTs as Number) && nowTs < (morningBlueEndTs as Number))
288:            || (eveningBlueStartTs != null && eveningBlueEndTs != null
289:                && nowTs >= (eveningBlueStartTs as Number) && nowTs < (eveningBlueEndTs as Number));
296:        isBlueNow = isBlueNow && (blueTs != null);
300:        if (isBlueNow && isGoldenNow) {
301:            isBlueNow = false;
306:        if (isBlueNow) {
448:        var morningBlueStartTs = snap[:morningBlueStartTs] as Number or Null;
451:        var eveningBlueEndTs = snap[:eveningBlueEndTs] as Number or Null;
452:        if (morningBlueStartTs == null || morningGoldenEndTs == null || eveningGoldenStartTs == null || eveningBlueEndTs == null) {
456:        if ((nowTs >= (morningBlueStartTs as Number) && nowTs < (morningGoldenEndTs as Number))
457:            || (nowTs >= (eveningGoldenStartTs as Number) && nowTs < (eveningBlueEndTs as Number))) {
```

`rg -n "Golden" source/Golden-timeView.mc`
```text
8:class GoldenTimeView extends WatchUi.WatchFace {
21:    var _bgGolden as WatchUi.BitmapResource;
25:    var _sunGolden as WatchUi.BitmapResource;
33:        _bgGolden = WatchUi.loadResource(Rez.Drawables.bg_golden) as WatchUi.BitmapResource;
37:        _sunGolden = WatchUi.loadResource(Rez.Drawables.sun_golden) as WatchUi.BitmapResource;
66:            System.println("[SNAP_KEYS] [:mode, :hasFix, :altDeg, :nextGoldenStartTs, :nextBlueStartTs, :todayHasGoldenStart, :todayHasBlueStart, :dayStartUtc, :windowStartTs, :windowEndTs, :dbgDeltaMin, :morningBlueStartTs, :morningBlueEndTs, :morningGoldenStartTs, :morningGoldenEndTs, :eveningGoldenStartTs, :eveningGoldenEndTs, :eveningBlueStartTs, :eveningBlueEndTs]");
69:                "[SNAP_MAP] phase=$1$ mode=$2$ hasFix=$3$ altDeg=$4$ nextGoldenStartTs=$5$ nextBlueStartTs=$6$ todayHasGoldenStart=$7$ todayHasBlueStart=$8$ dayStartUtc=$9$ windowStartTs=$10$ windowEndTs=$11$ dbgDeltaMin=$12$ morningBlueStartTs=$13$ morningBlueEndTs=$14$ morningGoldenStartTs=$15$ morningGoldenEndTs=$16$ eveningGoldenStartTs=$17$ eveningGoldenEndTs=$18$ eveningBlueStartTs=$19$ eveningBlueEndTs=$20$",
75:                    snap[:nextGoldenStartTs],
77:                    snap[:todayHasGoldenStart],
85:                    snap[:morningGoldenStartTs],
86:                    snap[:morningGoldenEndTs],
87:                    snap[:eveningGoldenStartTs],
88:                    snap[:eveningGoldenEndTs],
94:            var morningGoldenEndTs = snap[:morningGoldenEndTs] as Number or Null;
95:            var eveningGoldenStartTs = snap[:eveningGoldenStartTs] as Number or Null;
97:            if (morningBlueStartTs != null && morningGoldenEndTs != null && eveningGoldenStartTs != null && eveningBlueEndTs != null) {
98:                var morningProbe = ((morningBlueStartTs as Number) + (((morningGoldenEndTs as Number) - (morningBlueStartTs as Number)) / 2.0)).toNumber();
99:                var dayProbe = ((morningGoldenEndTs as Number) + (((eveningGoldenStartTs as Number) - (morningGoldenEndTs as Number)) / 2.0)).toNumber();
100:                var eveningProbe = ((eveningGoldenStartTs as Number) + (((eveningBlueEndTs as Number) - (eveningGoldenStartTs as Number)) / 2.0)).toNumber();
120:                :morningGoldenEndTs => 200,
121:                :eveningGoldenStartTs => 500,
143:        var goldenTs = hasFix ? (snap[:nextGoldenStartTs] as Number or Null) : null;
147:        if (!((snap[:todayHasGoldenStart] as Boolean) || false)) {
156:                [phase, snap[:dayStartUtc], snap[:windowStartTs], snap[:windowEndTs], blueText, goldenText, snap[:nextBlueStartTs], snap[:nextGoldenStartTs]]
169:            return _bgGolden;
243:            return _sunGolden;
267:        var goldenTs = hasFix ? (snap[:nextGoldenStartTs] as Number or Null) : null;
272:        if (!((snap[:todayHasGoldenStart] as Boolean) || false)) {
280:        var morningGoldenStartTs = snap[:morningGoldenStartTs] as Number or Null;
281:        var morningGoldenEndTs = snap[:morningGoldenEndTs] as Number or Null;
282:        var eveningGoldenStartTs = snap[:eveningGoldenStartTs] as Number or Null;
283:        var eveningGoldenEndTs = snap[:eveningGoldenEndTs] as Number or Null;
291:        var isGoldenNow =
292:            (morningGoldenStartTs != null && morningGoldenEndTs != null
293:                && nowTs >= (morningGoldenStartTs as Number) && nowTs < (morningGoldenEndTs as Number))
294:            || (eveningGoldenStartTs != null && eveningGoldenEndTs != null
295:                && nowTs >= (eveningGoldenStartTs as Number) && nowTs < (eveningGoldenEndTs as Number));
297:        isGoldenNow = isGoldenNow && (goldenTs != null);
300:        if (isBlueNow && isGoldenNow) {
309:        if (isGoldenNow) {
449:        var morningGoldenEndTs = snap[:morningGoldenEndTs] as Number or Null;
450:        var eveningGoldenStartTs = snap[:eveningGoldenStartTs] as Number or Null;
452:        if (morningBlueStartTs == null || morningGoldenEndTs == null || eveningGoldenStartTs == null || eveningBlueEndTs == null) {
456:        if ((nowTs >= (morningBlueStartTs as Number) && nowTs < (morningGoldenEndTs as Number))
457:            || (nowTs >= (eveningGoldenStartTs as Number) && nowTs < (eveningBlueEndTs as Number))) {
460:        if (nowTs >= (morningGoldenEndTs as Number) && nowTs < (eveningGoldenStartTs as Number)) {
```

`rg -n "Countdown" source/Golden-timeView.mc`
```text
138:        _drawDualCountdown(dc, snap, nowTs, w, h, hardStale, softStale);
155:                "[SNAPSHOT] buildId=v1.1 phase=$1$ dayStartUtc=$2$ windowStartTs=$3$ windowEndTs=$4$ blueCountdown=$5$ goldenCountdown=$6$ blueTs=$7$ goldenTs=$8$",
253:    function _drawDualCountdown(dc as Dc, snap as Lang.Dictionary, nowTs as Number, w as Number, h as Number, hardStale as Boolean, softStale as Boolean) as Void {
```

`rg -n "_cachedEvents" source/SunAltService.mc`
```text
16:    var _cachedEvents as Array<Lang.Dictionary>;
25:        _cachedEvents = [];
35:            _cachedEvents = [];
80:        _cachedEvents = eventData[:events] as Array<Lang.Dictionary>;
81:        _todayHasGoldenStart = _hasGoldenOrBlue(_cachedEvents, "GOLDEN");
82:        _todayHasBlueStart = _hasGoldenOrBlue(_cachedEvents, "BLUE");
84:        var nextGoldenStart = _findNextGoldenOrBlue(_cachedEvents, nowTs, "GOLDEN");
85:        var nextBlueStart = _findNextGoldenOrBlue(_cachedEvents, nowTs, "BLUE");
115:            System.println(Lang.format("[Events] Found $1$ events:", [_cachedEvents.size()]));
116:            for (var i = 0; i < _cachedEvents.size(); i++) {
117:                var e = _cachedEvents[i];
158:        var nextGolden = _findNextGoldenOrBlue(_cachedEvents, nowTs, "GOLDEN");
159:        var nextBlue = _findNextGoldenOrBlue(_cachedEvents, nowTs, "BLUE");
160:        var morningBlueStartTs = _findFirstEventTsByType(_cachedEvents, "MORNING_BLUE_START");
161:        var morningBlueEndTs = _findFirstEventTsByType(_cachedEvents, "MORNING_BLUE_END");
162:        var morningGoldenStartTs = _findFirstEventTsByType(_cachedEvents, "MORNING_GOLDEN_START");
163:        var morningGoldenEndTs = _findFirstEventTsByType(_cachedEvents, "MORNING_GOLDEN_END");
164:        var eveningGoldenStartTs = _findFirstEventTsByType(_cachedEvents, "EVENING_GOLDEN_START");
165:        var eveningGoldenEndTs = _findFirstEventTsByType(_cachedEvents, "EVENING_GOLDEN_END");
166:        var eveningBlueStartTs = _findFirstEventTsByType(_cachedEvents, "EVENING_BLUE_START");
167:        var eveningBlueEndTs = _findFirstEventTsByType(_cachedEvents, "EVENING_BLUE_END");
187:            :todayHasGoldenStart => _hasGoldenOrBlue(_cachedEvents, "GOLDEN"),
188:            :todayHasBlueStart => _hasGoldenOrBlue(_cachedEvents, "BLUE"),
```

`rg -n "Events" source/SunAltService.mc`
```text
16:    var _cachedEvents as Array<Lang.Dictionary>;
25:        _cachedEvents = [];
35:            _cachedEvents = [];
79:        var eventData = _computeWindowEvents(windowStartTs, lat, lon);
80:        _cachedEvents = eventData[:events] as Array<Lang.Dictionary>;
81:        _todayHasGoldenStart = _hasGoldenOrBlue(_cachedEvents, "GOLDEN");
82:        _todayHasBlueStart = _hasGoldenOrBlue(_cachedEvents, "BLUE");
84:        var nextGoldenStart = _findNextGoldenOrBlue(_cachedEvents, nowTs, "GOLDEN");
85:        var nextBlueStart = _findNextGoldenOrBlue(_cachedEvents, nowTs, "BLUE");
115:            System.println(Lang.format("[Events] Found $1$ events:", [_cachedEvents.size()]));
116:            for (var i = 0; i < _cachedEvents.size(); i++) {
117:                var e = _cachedEvents[i];
158:        var nextGolden = _findNextGoldenOrBlue(_cachedEvents, nowTs, "GOLDEN");
159:        var nextBlue = _findNextGoldenOrBlue(_cachedEvents, nowTs, "BLUE");
160:        var morningBlueStartTs = _findFirstEventTsByType(_cachedEvents, "MORNING_BLUE_START");
161:        var morningBlueEndTs = _findFirstEventTsByType(_cachedEvents, "MORNING_BLUE_END");
162:        var morningGoldenStartTs = _findFirstEventTsByType(_cachedEvents, "MORNING_GOLDEN_START");
163:        var morningGoldenEndTs = _findFirstEventTsByType(_cachedEvents, "MORNING_GOLDEN_END");
164:        var eveningGoldenStartTs = _findFirstEventTsByType(_cachedEvents, "EVENING_GOLDEN_START");
165:        var eveningGoldenEndTs = _findFirstEventTsByType(_cachedEvents, "EVENING_GOLDEN_END");
166:        var eveningBlueStartTs = _findFirstEventTsByType(_cachedEvents, "EVENING_BLUE_START");
167:        var eveningBlueEndTs = _findFirstEventTsByType(_cachedEvents, "EVENING_BLUE_END");
187:            :todayHasGoldenStart => _hasGoldenOrBlue(_cachedEvents, "GOLDEN"),
188:            :todayHasBlueStart => _hasGoldenOrBlue(_cachedEvents, "BLUE"),
241:    function _computeWindowEvents(startTs as Number, lat as Number, lon as Number) as Lang.Dictionary {
280:            :events => _sortEventsByTs(events)
477:    function _sortEventsByTs(events as Array<Lang.Dictionary>) as Array<Lang.Dictionary> {
```

`rg -n "Dictionary" source/SunAltService.mc`
```text
14:    var _lastFix as Lang.Dictionary or Null;
16:    var _cachedEvents as Array<Lang.Dictionary>;
31:    function updateIfNeeded(nowTs as Number, fix as Lang.Dictionary or Null) as Void {
80:        _cachedEvents = eventData[:events] as Array<Lang.Dictionary>;
123:    function getSnapshot(nowTs as Number) as Lang.Dictionary {
196:    function _findNextGoldenOrBlue(events as Array<Lang.Dictionary>, nowTs as Number, kind as String) as Number or Null {
214:    function _hasGoldenOrBlue(events as Array<Lang.Dictionary>, kind as String) as Boolean {
224:    function _findFirstEventTsByType(events as Array<Lang.Dictionary>, typeName as String) as Number or Null {
241:    function _computeWindowEvents(startTs as Number, lat as Number, lon as Number) as Lang.Dictionary {
244:        var events = [] as Array<Lang.Dictionary>;
284:    function _scanPeriod(startTs as Number, endTs as Number, lat as Number, lon as Number, isMorning as Boolean) as Array<Lang.Dictionary> {
285:        var events = [] as Array<Lang.Dictionary>;
458:    function _findNextEventTs(events as Array<Lang.Dictionary>, nowTs as Number, typeName as String) as Number or Null {
468:    function _hasEventType(events as Array<Lang.Dictionary>, typeName as String) as Boolean {
477:    function _sortEventsByTs(events as Array<Lang.Dictionary>) as Array<Lang.Dictionary> {
478:        var out = [] as Array<Lang.Dictionary>;
655:    function _getTodayWindow(nowTs as Number) as Lang.Dictionary {
```

`rg -n ":type|:ts|MORNING_|EVENING_|GOLDEN|BLUE" source/SunAltService.mc`
```text
67:            :ts => fix[:ts]
81:        _todayHasGoldenStart = _hasGoldenOrBlue(_cachedEvents, "GOLDEN");
82:        _todayHasBlueStart = _hasGoldenOrBlue(_cachedEvents, "BLUE");
84:        var nextGoldenStart = _findNextGoldenOrBlue(_cachedEvents, nowTs, "GOLDEN");
85:        var nextBlueStart = _findNextGoldenOrBlue(_cachedEvents, nowTs, "BLUE");
118:                System.println(Lang.format("  [$1$] $2$ at $3$", [i, e[:type], _fmtTs(e[:ts])]));
158:        var nextGolden = _findNextGoldenOrBlue(_cachedEvents, nowTs, "GOLDEN");
159:        var nextBlue = _findNextGoldenOrBlue(_cachedEvents, nowTs, "BLUE");
160:        var morningBlueStartTs = _findFirstEventTsByType(_cachedEvents, "MORNING_BLUE_START");
161:        var morningBlueEndTs = _findFirstEventTsByType(_cachedEvents, "MORNING_BLUE_END");
162:        var morningGoldenStartTs = _findFirstEventTsByType(_cachedEvents, "MORNING_GOLDEN_START");
163:        var morningGoldenEndTs = _findFirstEventTsByType(_cachedEvents, "MORNING_GOLDEN_END");
164:        var eveningGoldenStartTs = _findFirstEventTsByType(_cachedEvents, "EVENING_GOLDEN_START");
165:        var eveningGoldenEndTs = _findFirstEventTsByType(_cachedEvents, "EVENING_GOLDEN_END");
166:        var eveningBlueStartTs = _findFirstEventTsByType(_cachedEvents, "EVENING_BLUE_START");
167:        var eveningBlueEndTs = _findFirstEventTsByType(_cachedEvents, "EVENING_BLUE_END");
187:            :todayHasGoldenStart => _hasGoldenOrBlue(_cachedEvents, "GOLDEN"),
188:            :todayHasBlueStart => _hasGoldenOrBlue(_cachedEvents, "BLUE"),
197:        // 查找下一次 GOLDEN_START 或 BLUE_START（不管是 MORNING 还是 EVENING）
200:            var typeStr = e[:type] as String;
201:            if (typeStr.find(kind + "_START") != null && (e[:ts] as Number) > nowTs) {
203:                    System.println(Lang.format("[_findNext] Found $1$: ts=$2$ type=$3$", [kind, e[:ts], typeStr]));
205:                return e[:ts] as Number;
216:            var typeStr = events[i][:type] as String;
227:            var t = e[:type];
231:                return e[:ts] as Number;
235:                return e[:ts] as Number;
334:                events.add({ :ts => morningBlueStart, :type => prefix + "_BLUE_START" });
337:                events.add({ :ts => morningBlueGoldenBoundary, :type => prefix + "_BLUE_END" });
338:                events.add({ :ts => morningBlueGoldenBoundary, :type => prefix + "_GOLDEN_START" });
341:                events.add({ :ts => morningGoldenEnd, :type => prefix + "_GOLDEN_END" });
345:                events.add({ :ts => eveningGoldenStart, :type => prefix + "_GOLDEN_START" });
348:                events.add({ :ts => eveningGoldenBlueBoundary, :type => prefix + "_GOLDEN_END" });
349:                events.add({ :ts => eveningGoldenBlueBoundary, :type => prefix + "_BLUE_START" });
352:                events.add({ :ts => eveningBlueEnd, :type => prefix + "_BLUE_END" });
461:            if (e[:type] == typeName && (e[:ts] as Number) > nowTs) {
462:                return e[:ts] as Number;
470:            if (events[i][:type] == typeName) {
486:                var tA = out[q][:ts] as Number;
487:                var tB = out[q + 1][:ts] as Number;
641:            return "GOLDEN";
647:            return "GOLDEN";
650:            return "BLUE";
```

`rg -n "_formatRemaining|remaining|blueText|goldenText|nextBlueStartTs|nextGoldenStartTs|todayHasBlueStart|todayHasGoldenStart" source/Golden-timeView.mc`
```text
66:            System.println("[SNAP_KEYS] [:mode, :hasFix, :altDeg, :nextGoldenStartTs, :nextBlueStartTs, :todayHasGoldenStart, :todayHasBlueStart, :dayStartUtc, :windowStartTs, :windowEndTs, :dbgDeltaMin, :morningBlueStartTs, :morningBlueEndTs, :morningGoldenStartTs, :morningGoldenEndTs, :eveningGoldenStartTs, :eveningGoldenEndTs, :eveningBlueStartTs, :eveningBlueEndTs]");
69:                "[SNAP_MAP] phase=$1$ mode=$2$ hasFix=$3$ altDeg=$4$ nextGoldenStartTs=$5$ nextBlueStartTs=$6$ todayHasGoldenStart=$7$ todayHasBlueStart=$8$ dayStartUtc=$9$ windowStartTs=$10$ windowEndTs=$11$ dbgDeltaMin=$12$ morningBlueStartTs=$13$ morningBlueEndTs=$14$ morningGoldenStartTs=$15$ morningGoldenEndTs=$16$ eveningGoldenStartTs=$17$ eveningGoldenEndTs=$18$ eveningBlueStartTs=$19$ eveningBlueEndTs=$20$",
75:                    snap[:nextGoldenStartTs],
76:                    snap[:nextBlueStartTs],
77:                    snap[:todayHasGoldenStart],
78:                    snap[:todayHasBlueStart],
142:        var blueTs = hasFix ? (snap[:nextBlueStartTs] as Number or Null) : null;
143:        var goldenTs = hasFix ? (snap[:nextGoldenStartTs] as Number or Null) : null;
144:        if (!((snap[:todayHasBlueStart] as Boolean) || false)) {
147:        if (!((snap[:todayHasGoldenStart] as Boolean) || false)) {
150:        var blueText = Lang.format("b=$1$", [_formatStartTime(blueTs)]);
151:        var goldenText = Lang.format("g=$1$", [_formatStartTime(goldenTs)]);
156:                [phase, snap[:dayStartUtc], snap[:windowStartTs], snap[:windowEndTs], blueText, goldenText, snap[:nextBlueStartTs], snap[:nextGoldenStartTs]]
266:        var blueTs = hasFix ? (snap[:nextBlueStartTs] as Number or Null) : null;
267:        var goldenTs = hasFix ? (snap[:nextGoldenStartTs] as Number or Null) : null;
269:        if (!((snap[:todayHasBlueStart] as Boolean) || false)) {
272:        if (!((snap[:todayHasGoldenStart] as Boolean) || false)) {
304:        var blueText = _formatStartTime(blueTs);
305:        var goldenText = _formatStartTime(goldenTs);
307:            blueText = "NOW";
310:            goldenText = "NOW";
313:            blueText = "--:--";
314:            goldenText = "--:--";
327:        var blueValueW = dc.getTextWidthInPixels(blueText, fontValue);
328:        var goldValueW = dc.getTextWidthInPixels(goldenText, fontValue);
337:        dc.drawText(blueValueX, yValue, fontValue, blueText, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
341:        dc.drawText(goldValueX, yValue, fontValue, goldenText, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
```

`rg -n "function _format" source/Golden-timeView.mc`
```text
396:    function _formatStartTime(targetTs as Number or Null) as String {
```

- 当前 phase 变量真实名称：`_phase`
- altDeg 真实变量名：`snap[:altDeg]`（Service 快照键 `:altDeg`）
- 四关键时间点真实变量名：`morningBlueStartTs`、`morningGoldenEndTs`、`eveningGoldenStartTs`、`eveningBlueEndTs`
- 倒计时真实变量名：`blueTs`、`goldenTs`（来源 `snap[:nextBlueStartTs]`、`snap[:nextGoldenStartTs]`，受 `snap[:todayHasBlueStart]`、`snap[:todayHasGoldenStart]` 控制）
- 事件数组真实结构：`Array<Lang.Dictionary>`，元素键名 `:ts` + `:type`，`type` 取值由 `prefix + "_BLUE_START/_BLUE_END/_GOLDEN_START/_GOLDEN_END"` 组成（`prefix` 为 `MORNING` 或 `EVENING`）