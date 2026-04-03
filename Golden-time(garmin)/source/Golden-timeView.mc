import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

class GoldenTimeView extends WatchUi.WatchFace {
    const SOFT_STALE_MAX_AGE_SEC = 259200;
    const HARD_STALE_MAX_AGE_SEC = 604800;
    const TRIAL_DURATION_SEC = 86400;
    const ACTIVATION_CODE_LEN = 12;
    const DATE_FROM_TOP_ANCHOR_OFFSET_Y = 0;
    const TIME_FROM_TOP_ANCHOR_OFFSET_Y = 42;
    const HINT_FROM_BOTTOM_ANCHOR_OFFSET_Y = 0;
    const COUNTDOWN_VALUE_FROM_BOTTOM_ANCHOR_OFFSET_Y = -24;
    const COUNTDOWN_LABEL_FROM_BOTTOM_ANCHOR_OFFSET_Y = -48;
    const COUNTDOWN_LABEL_OFFSET_Y = -12;
    const COUNTDOWN_VALUE_OFFSET_Y = 12;
    const SUNALT_RECALC_TRAVEL_THRESHOLD_KM = 30.0;
    const SUNALT_RECALC_MIN_INTERVAL_SEC = 60;
    const SUNALT_RECALC_LAT_COARSE_THRESHOLD_DEG = 0.27;
    const SUNALT_RECALC_LON_COARSE_THRESHOLD_DEG = 0.40;
    const SUNALT_UPDATE_COUNT_WINDOW_SEC = 60;
    const DEBUG_DIRECT_POSITION_READ = false;
    const SHORT_DEBUG_T4_PRINT = false;
    const COLOR_WHITE = 0xFFFFFF;
    const COLOR_BLACK = 0x000000;
    const COLOR_BLUE  = 0x8094B5;
    const COLOR_GOLD  = 0xFFAA00;
    const COLOR_TRIAL_EXPIRED = 0xFF0000;

    var _locationService as LocationService;
    var _sunAltService as SunAltService;
    var _phase as String;
    var _bgGolden as WatchUi.BitmapResource or Null;
    var _bgNight as WatchUi.BitmapResource or Null;
    var _bgDay as WatchUi.BitmapResource or Null;
    var _bgCurrentKey as Number or Null = null;
    var _bgCurrent as WatchUi.BitmapResource or Null = null;
    var _bgLastLoadFailKey as Number or Null = null;
    var _moonNight as WatchUi.BitmapResource;
    var _sunGolden as WatchUi.BitmapResource;
    var _sunDay as WatchUi.BitmapResource;
    var _firstInstallTs as Number or Null = null;
    var _isActivated as Boolean = false;
    var _lastHadFix as Boolean = false;
    var _lastSeenFixTs as Number or Null = null;
    var _lastDayKey as Number or Null = null;
    var _lastTzOffsetSec as Number or Null = null;
    var _lastRecalcTs as Number or Null = null;
    var _lastRecalcLat as Number or Null = null;
    var _lastRecalcLon as Number or Null = null;
    var _pendingTravelRecalc as Boolean = false;
    var _pendingTravelFixTs as Number or Null = null;
    var _sunAltUpdateCallCountWindow as Number = 0;
    var _sunAltUpdateCountWindowStartTs as Number or Null = null;
    var _shortDebugT4NewFix as Boolean = false;
    var _shortDebugT4LatDelta as Number or Null = null;
    var _shortDebugT4LonDelta as Number or Null = null;
    var _shortDebugT4DistanceKm as Float or Null = null;
    var _shortDebugT4Pending as Boolean = false;
    var _shortDebugT4PendingFired as Boolean = false;

    function initialize() {
        WatchFace.initialize();
        _locationService = new LocationService();
        _sunAltService = new SunAltService();
        _phase = "DAY";
        _moonNight = WatchUi.loadResource(Rez.Drawables.moon_night) as WatchUi.BitmapResource;
        _sunGolden = WatchUi.loadResource(Rez.Drawables.sun_golden) as WatchUi.BitmapResource;
        _sunDay = WatchUi.loadResource(Rez.Drawables.sun_day) as WatchUi.BitmapResource;
        _loadActivationData();
    }

    function onLayout(dc as Dc) as Void {
    }

    function onUpdate(dc as Dc) as Void {
        var nowMoment = Time.now();
        var nowTs = nowMoment.value();
        var w = dc.getWidth();
        var h = dc.getHeight();

        _syncActivationState(nowTs);
        _locationService.requestFixIfNeeded(nowTs);
        var fix = _locationService.getLastFix();
        var trialExpired = isTrialExpired(nowTs);
        var hardStale = _isHardStale(nowTs);
        var softStale = (!hardStale) && _isSoftStale(nowTs);

        _updateSunAltIfNeeded(nowTs, hardStale ? null : fix);
        var snap = _sunAltService.getSnapshot(nowTs);
        var state = _sunAltService.getCurrentState(nowTs);
        var phase = _phaseFromState(state);
        if (hardStale) {
            phase = "DAY";
        }
        _phase = phase;
        var desiredBgKey = _getDesiredBackgroundKey(fix, hardStale, phase);

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.fillRectangle(0, 0, w, h);
        _drawBackground(dc, desiredBgKey);
        _drawTime(dc, w, h);
        _drawDate(dc, nowMoment, w, h);
        _drawDualCountdown(dc, snap, state, nowTs, w, h, hardStale, softStale, trialExpired);
        _drawCelestial(dc);

        if (DEBUG_DIRECT_POSITION_READ) {
            var info = Position.getInfo();
            var latStr = "NULL";
            var lonStr = "NULL";

            if (info != null) {
                if (info.position != null) {
                    var pos = info.position;
                    var coord = pos.toDegrees();
                    if (coord != null) {
                        latStr = coord[0] != null ? coord[0].toString() : "NULL";
                        lonStr = coord[1] != null ? coord[1].toString() : "NULL";
                    }
                }
            }

            var debugText = "LAT=" + latStr + " LON=" + lonStr;

            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                dc.getWidth() / 2,
                dc.getHeight() / 2,
                Graphics.FONT_XTINY,
                debugText,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
            );
        }

        _drawShortDebugT4(dc);

    }

    function _updateSunAltIfNeeded(nowTs as Number, fix as Lang.Dictionary or Null) as Void {
        _maybeLogSunAltUpdateCallCount(nowTs);

        var hasFix = fix != null && fix[:lat] != null && fix[:lon] != null && fix[:ts] != null;
        _shortDebugT4NewFix = false;
        _shortDebugT4LatDelta = null;
        _shortDebugT4LonDelta = null;
        _shortDebugT4DistanceKm = null;
        _shortDebugT4Pending = _pendingTravelRecalc;
        _shortDebugT4PendingFired = false;

        if (!hasFix) {
            // 保持 hard stale / 无定位时清空 SunAlt 快照的行为，但避免每帧重复调用。
            if (_lastHadFix) {
                _callSunAltUpdate(nowTs, null);
            }
            _pendingTravelRecalc = false;
            _pendingTravelFixTs = null;
            _shortDebugT4Pending = false;
            _lastHadFix = false;
            return;
        }

        var lat = fix[:lat] as Number;
        var lon = fix[:lon] as Number;
        var fixTs = fix[:ts] as Number;
        var dayKey = _getLocalDayKey(nowTs);
        var tzOffsetSec = _getGateSystemUtcOffsetSec();
        var newFix = _lastSeenFixTs == null || (fixTs as Number) != (_lastSeenFixTs as Number);
        var shouldRecompute = false;
        var pendingFired = false;
        var debugDistanceKm = null;

        _shortDebugT4NewFix = newFix;
        if (_lastRecalcLat != null && _lastRecalcLon != null) {
            var debugLatDelta = _absNumber((lat as Number) - (_lastRecalcLat as Number));
            var debugLonDelta = _absNumber((lon as Number) - (_lastRecalcLon as Number));
            _shortDebugT4LatDelta = debugLatDelta;
            _shortDebugT4LonDelta = debugLonDelta;
            if (SHORT_DEBUG_T4_PRINT) {
                debugDistanceKm = _haversineKm(lat, lon, (_lastRecalcLat as Number), (_lastRecalcLon as Number));
                _shortDebugT4DistanceKm = debugDistanceKm;
            }
        }

        if (!_lastHadFix) {
            shouldRecompute = true; // T1: no-fix -> has-fix
        }

        if (!shouldRecompute && (_lastDayKey == null || (dayKey as Number) != (_lastDayKey as Number))) {
            shouldRecompute = true; // T2: local day changed
        }

        if (!shouldRecompute && (_lastTzOffsetSec == null || (tzOffsetSec as Number) != (_lastTzOffsetSec as Number))) {
            shouldRecompute = true; // T3: tz/dst offset changed
        }

        if (!shouldRecompute && newFix) {
            if (_lastRecalcLat != null && _lastRecalcLon != null) {
                var latDelta = _absNumber((lat as Number) - (_lastRecalcLat as Number));
                var lonDelta = _absNumber((lon as Number) - (_lastRecalcLon as Number));
                if (latDelta > SUNALT_RECALC_LAT_COARSE_THRESHOLD_DEG || lonDelta > SUNALT_RECALC_LON_COARSE_THRESHOLD_DEG) {
                    var travelKm = debugDistanceKm;
                    if (travelKm == null) {
                        travelKm = _haversineKm(lat, lon, (_lastRecalcLat as Number), (_lastRecalcLon as Number));
                    }
                    if (travelKm >= SUNALT_RECALC_TRAVEL_THRESHOLD_KM) {
                        var canFireTravelNow = _lastRecalcTs == null || (nowTs - (_lastRecalcTs as Number)) >= SUNALT_RECALC_MIN_INTERVAL_SEC;
                        if (canFireTravelNow) {
                            shouldRecompute = true; // T4: travel >= 30km and min interval satisfied
                            _pendingTravelRecalc = false;
                            _pendingTravelFixTs = null;
                        } else {
                            if (!_pendingTravelRecalc || _pendingTravelFixTs == null || (fixTs as Number) != (_pendingTravelFixTs as Number)) {
                                System.println("T4_DETECTED_PENDING");
                            }
                            _pendingTravelRecalc = true;
                            _pendingTravelFixTs = fixTs;
                        }
                    }
                }
            }
        }

        if (!shouldRecompute && _pendingTravelRecalc) {
            if (_lastRecalcTs == null || (nowTs - (_lastRecalcTs as Number)) >= SUNALT_RECALC_MIN_INTERVAL_SEC) {
                System.println("T4_PENDING_FIRED");
                shouldRecompute = true;
                pendingFired = true;
            }
        }

        if (shouldRecompute) {
            _callSunAltUpdate(nowTs, fix);
            _lastDayKey = dayKey;
            _lastTzOffsetSec = tzOffsetSec;
            _lastRecalcTs = nowTs;
            _lastRecalcLat = lat;
            _lastRecalcLon = lon;
            _pendingTravelRecalc = false;
            _pendingTravelFixTs = null;
        }

        _shortDebugT4Pending = _pendingTravelRecalc;
        _shortDebugT4PendingFired = pendingFired;
        _lastSeenFixTs = fixTs;
        _lastHadFix = true;
    }

    function _callSunAltUpdate(nowTs as Number, fix as Lang.Dictionary or Null) as Void {
        _sunAltUpdateCallCountWindow += 1;
        _sunAltService.updateIfNeeded(nowTs, fix);
    }

    function _maybeLogSunAltUpdateCallCount(nowTs as Number) as Void {
        if (_sunAltUpdateCountWindowStartTs == null) {
            _sunAltUpdateCountWindowStartTs = nowTs;
            _sunAltUpdateCallCountWindow = 0;
            return;
        }

        if ((nowTs - (_sunAltUpdateCountWindowStartTs as Number)) < SUNALT_UPDATE_COUNT_WINDOW_SEC) {
            return;
        }

        System.println(
            "GT SunAltService.updateIfNeeded calls/60s="
            + (_sunAltUpdateCallCountWindow as Number).toString()
        );
        _sunAltUpdateCountWindowStartTs = nowTs;
        _sunAltUpdateCallCountWindow = 0;
    }

    function _getLocalDayKey(nowTs as Number) as Number {
        var info = Time.Gregorian.info(new Time.Moment(nowTs), Time.FORMAT_SHORT);
        return ((info[:year] as Number) * 10000) + ((info[:month] as Number) * 100) + (info[:day] as Number);
    }

    function _getGateSystemUtcOffsetSec() as Number {
        var ct = System.getClockTime();
        return (ct.timeZoneOffset as Number) + (ct.dst as Number);
    }

    function _absNumber(v as Number) as Number {
        return v < 0 ? -v : v;
    }

    function _degToRadView(deg as Number) as Float {
        return deg * Math.PI / 180.0;
    }

    function _haversineKm(lat1 as Number, lon1 as Number, lat2 as Number, lon2 as Number) as Float {
        var dLat = _degToRadView(lat2 - lat1);
        var dLon = _degToRadView(lon2 - lon1);
        var lat1Rad = _degToRadView(lat1);
        var lat2Rad = _degToRadView(lat2);

        var sinHalfDLat = Math.sin(dLat / 2.0);
        var sinHalfDLon = Math.sin(dLon / 2.0);
        var a = (sinHalfDLat * sinHalfDLat)
            + (Math.cos(lat1Rad) * Math.cos(lat2Rad) * sinHalfDLon * sinHalfDLon);
        if (a < 0.0) {
            a = 0.0;
        } else if (a > 1.0) {
            a = 1.0;
        }

        var c = 2.0 * Math.atan2(Math.sqrt(a), Math.sqrt(1.0 - a));
        return 6371.0 * c;
    }

    function _drawShortDebugT4(dc as Dc) as Void {
        if (!SHORT_DEBUG_T4_PRINT) {
            return;
        }

        var insets = _getSafeInsets(dc);
        var x0 = (insets[:left] as Number) + 2;
        var y0 = (insets[:top] as Number) + 6;
        var lineStep = 10;
        var font = Graphics.FONT_XTINY;

        dc.setColor(COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x0, y0, font, "NEWFIX:" + _shortDebugFlag(_shortDebugT4NewFix), Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(
            x0,
            y0 + lineStep,
            font,
            "dLat:" + _shortDebugFmt1(_shortDebugT4LatDelta) + " dLon:" + _shortDebugFmt1(_shortDebugT4LonDelta),
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER
        );
        dc.drawText(
            x0,
            y0 + (lineStep * 2),
            font,
            "DIST:" + _shortDebugFmt1(_shortDebugT4DistanceKm) + "km",
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER
        );
        dc.drawText(
            x0,
            y0 + (lineStep * 3),
            font,
            "PEND:" + _shortDebugFlag(_shortDebugT4Pending) + " FIRE:" + _shortDebugFlag(_shortDebugT4PendingFired),
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER
        );
    }

    function _shortDebugFlag(v as Boolean) as String {
        return v ? "Y" : "N";
    }

    function _shortDebugFmt1(v as Number or Null) as String {
        if (v == null) {
            return "--";
        }
        return (v as Number).format("%.1f");
    }

    function _drawBackground(dc as Dc, desiredKey) as Void {
        _ensureBackgroundLoaded(desiredKey);
        var bmp = _bgCurrent;
        var w = dc.getWidth();
        var h = dc.getHeight();
        if (bmp == null) {
            return;
        }
        if (_isProLargeMipLayout(w, h)) {
            dc.setColor(_getPhaseEdgeFillColor(_phase), _getPhaseEdgeFillColor(_phase));
            dc.clear();
            var x = ((w - bmp.getWidth()) / 2).toNumber();
            var y = ((h - bmp.getHeight()) / 2).toNumber();
            dc.drawBitmap(x, y, bmp);
            return;
        }
        dc.drawBitmap(0, 0, bmp);
    }

    function _getDesiredBackgroundKey(fix, hardStale as Boolean, phase as String or Null) {
        if (fix == null || hardStale) {
            return Rez.Drawables.bg_day;
        }
        if (phase != null && phase.equals("NIGHT")) {
            return Rez.Drawables.bg_night;
        }
        if (phase != null && phase.equals("TWILIGHT")) {
            return Rez.Drawables.bg_golden;
        }
        if (phase != null && phase.equals("GOLDEN")) {
            return Rez.Drawables.bg_golden;
        }
        return Rez.Drawables.bg_day;
    }

    function _ensureBackgroundLoaded(desiredKey) as Void {
        if (_bgCurrent != null && _bgCurrentKey != null && (_bgCurrentKey as Number) == (desiredKey as Number)) {
            return;
        }

        _bgCurrent = null;

        try {
            _bgCurrent = WatchUi.loadResource(desiredKey) as WatchUi.BitmapResource;
        } catch (e) {
            _bgCurrent = null;
        }

        _bgCurrentKey = desiredKey as Number;

        if (_bgCurrent != null) {
            _bgLastLoadFailKey = null;
            return;
        }

        if (_bgLastLoadFailKey == null || (_bgLastLoadFailKey as Number) != (_bgCurrentKey as Number)) {
            System.println("BG_LOAD_FAIL key=" + _bgCurrentKey);
            _bgLastLoadFailKey = _bgCurrentKey;
        }
    }

    function _drawTime(dc as Dc, w as Number, h as Number) as Void {
        var clock = System.getClockTime();
        var hh = clock.hour.format("%02d");
        var mm = clock.min.format("%02d");
        var text = Lang.format("$1$:$2$", [hh, mm]);

        var isDay = (_phase != null) && (_phase as String).equals("DAY");
        var mainColor;
        if (isDay) {
            mainColor = 0x000000;
        } else {
            mainColor = 0xFFFFFF;
        }
        dc.setColor(mainColor, Graphics.COLOR_TRANSPARENT);
        var topAnchorY = _getTopAnchorY(w, h);
        dc.drawText(
            w / 2,
            topAnchorY + TIME_FROM_TOP_ANCHOR_OFFSET_Y + _getTimeYOffsetAdjust(w, h),
            Graphics.FONT_NUMBER_HOT,
            text,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );
    }

    function _drawDate(dc as Dc, nowMoment as Time.Moment, w as Number, h as Number) as Void {
        var info = Time.Gregorian.info(nowMoment, Time.FORMAT_SHORT);
        var dayNames = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"];
        var monthNames = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"];
        var dowRaw = info[:day_of_week] as Number;
        var dowIdx = ((dowRaw - 1) % 7).toNumber();
        if (dowIdx < 0) {
            dowIdx += 7;
        }
        var monthIdx = (info[:month] as Number) - 1;
        var dateText = Lang.format("$1$ | $2$ $3$", [
            dayNames[dowIdx],
            monthNames[monthIdx],
            (info[:day] as Number).format("%02d")
        ]);
        var isDay = (_phase != null) && (_phase as String).equals("DAY");
        var mainColor;
        if (isDay) {
            mainColor = 0x000000;
        } else {
            mainColor = 0xFFFFFF;
        }
        dc.setColor(mainColor, Graphics.COLOR_TRANSPARENT);
        var topAnchorY = _getTopAnchorY(w, h);
        dc.drawText(
            w / 2,
            topAnchorY + DATE_FROM_TOP_ANCHOR_OFFSET_Y + _getDateYOffsetAdjust(w, h),
            Graphics.FONT_TINY,
            dateText,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );
    }

    function _getCelestialBitmap(phase as String) as WatchUi.BitmapResource {
        if (phase != null && phase.equals("NIGHT")) {
            return _moonNight;
        }
        if (phase != null && phase.equals("TWILIGHT")) {
            return _sunGolden;
        }
        return _sunDay;
    }

    function _drawCelestial(dc as Dc) as Void {
        var bmp = _getCelestialBitmap(_phase);
        var w = dc.getWidth();
        var h = dc.getHeight();
        if (_isProLargeMipLayout(w, h)) {
            var x = ((w - bmp.getWidth()) / 2).toNumber();
            var y = ((h - bmp.getHeight()) / 2).toNumber();
            dc.drawBitmap(x, y, bmp);
            return;
        }
        dc.drawBitmap(0, 0, bmp);
    }

    function _drawDualCountdown(dc as Dc, snap as Lang.Dictionary, state as String or Null, nowTs as Number, w as Number, h as Number, hardStale as Boolean, softStale as Boolean, trialExpired as Boolean) as Void {
        var hasFix = snap[:hasFix] as Boolean;
        var pad = 6;
        var fontLabel = _getCountdownLabelFont(w, h);
        var fontValue = Graphics.FONT_MEDIUM;
        var fontHint = _getCountdownHintFont(w, h);
        var insets = _getSafeInsets(dc);
        var safeLeft = (insets[:left] as Number) + pad;
        var safeRight = w - (insets[:right] as Number) - pad;
        var safeTop = (insets[:top] as Number) + pad;
        var safeBottom = h - (insets[:bottom] as Number) - pad;
        var safeW = safeRight - safeLeft;
        var safeH = safeBottom - safeTop;

        var blueTs = hasFix ? (snap[:nextBlueStartTs] as Number or Null) : null;
        var goldenTs = hasFix ? (snap[:nextGoldenStartTs] as Number or Null) : null;

        var blueText = "--:--";
        var goldenText = "--:--";
        if (!hasFix || hardStale) {
            blueText = "--:--";
            goldenText = "--:--";
        } else {
            if (state != null && state.equals("BLUE")) {
                blueText = "NOW";
                goldenText = _formatStartTime(goldenTs);
            } else if (state != null && state.equals("GOLDEN")) {
                goldenText = "NOW";
                blueText = _formatStartTime(blueTs);
            } else {
                blueText = _formatStartTime(blueTs);
                goldenText = _formatStartTime(goldenTs);
            }
        }
        if (blueText.equals("NOW") && goldenText.equals("NOW")) {
            if (goldenTs != null) {
                goldenText = _formatStartTime(goldenTs);
            } else {
                goldenText = "--:--";
            }
        }

        var bottomAnchorY = _getBottomAnchorY(w, h);
        var yHint = bottomAnchorY + HINT_FROM_BOTTOM_ANCHOR_OFFSET_Y + _getHintYOffsetAdjust(w, h);
        var countdownBlockYOffsetAdjust = _getCountdownBlockYOffsetAdjust(w, h);
        var yValue = bottomAnchorY + COUNTDOWN_VALUE_FROM_BOTTOM_ANCHOR_OFFSET_Y + countdownBlockYOffsetAdjust + _getCountdownValueYOffsetAdjust(w, h);
        var yLabel = bottomAnchorY + COUNTDOWN_LABEL_FROM_BOTTOM_ANCHOR_OFFSET_Y + countdownBlockYOffsetAdjust + _getCountdownLabelYOffsetAdjust(w, h);
        var leftCenterX = 80;
        var rightCenterX = 160;
        var useSymmetricCountdownLayout = _isSymmetricCountdownLayout(w, h);
        if (useSymmetricCountdownLayout) {
            var cx = (w / 2).toNumber();
            var moduleOffset = _getCountdownModuleOffsetPx(w, h);
            leftCenterX = cx - moduleOffset;
            rightCenterX = cx + moduleOffset;
        }

        // 临时关闭试用过期 UI 警告，方便模拟器调试；后续可直接恢复该 if 块。
        
        if (trialExpired) {
            dc.setColor(COLOR_TRIAL_EXPIRED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                w / 2,
                yLabel,
                fontHint,
                "24H TRIAL EXPIRED",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
            );
            dc.drawText(
                w / 2,
                yValue,
                fontHint,
                "ENTER CODE",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
            );
            return;
        }
        

        var blueLabel = "BLUE";
        var goldLabel = "GOLDEN";
        var blueLabelW = dc.getTextWidthInPixels(blueLabel, fontLabel);
        var goldLabelW = dc.getTextWidthInPixels(goldLabel, fontLabel);
        var blueValueW = dc.getTextWidthInPixels(blueText, fontValue);
        var goldValueW = dc.getTextWidthInPixels(goldenText, fontValue);

        var blueX = _clamp(leftCenterX, safeLeft + (blueLabelW / 2), safeRight - (blueLabelW / 2));
        var goldX = _clamp(rightCenterX, safeLeft + (goldLabelW / 2), safeRight - (goldLabelW / 2));
        var blueValueX = _clamp(leftCenterX, safeLeft + (blueValueW / 2), safeRight - (blueValueW / 2));
        var goldValueX = _clamp(rightCenterX, safeLeft + (goldValueW / 2), safeRight - (goldValueW / 2));

        dc.setColor(COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
        if (useSymmetricCountdownLayout) {
            dc.drawText((blueX - (blueLabelW / 2)).toNumber(), yLabel, fontLabel, blueLabel, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.drawText((blueValueX - (blueValueW / 2)).toNumber(), yValue, fontValue, blueText, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        } else {
            dc.drawText(blueX, yLabel, fontLabel, blueLabel, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.drawText(blueValueX, yValue, fontValue, blueText, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        dc.setColor(COLOR_GOLD, Graphics.COLOR_TRANSPARENT);
        if (useSymmetricCountdownLayout) {
            dc.drawText((goldX - (goldLabelW / 2)).toNumber(), yLabel, fontLabel, goldLabel, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.drawText((goldValueX - (goldValueW / 2)).toNumber(), yValue, fontValue, goldenText, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        } else {
            dc.drawText(goldX, yLabel, fontLabel, goldLabel, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.drawText(goldValueX, yValue, fontValue, goldenText, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        var hintColor = COLOR_WHITE;

        if (hardStale) {
            dc.setColor(hintColor, Graphics.COLOR_TRANSPARENT);
            if (useSymmetricCountdownLayout) {
                var hardHint = "Enable GPS Once";
                var hardHintW = dc.getTextWidthInPixels(hardHint, fontHint);
                dc.drawText((((w / 2) - (hardHintW / 2))).toNumber(), yHint, fontHint, hardHint, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            } else {
                dc.drawText(w / 2, yHint, fontHint, "Enable GPS Once", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            }
        } else if (softStale) {
            dc.setColor(hintColor, Graphics.COLOR_TRANSPARENT);
            if (useSymmetricCountdownLayout) {
                var softHint = "GPS Outdated";
                var softHintW = dc.getTextWidthInPixels(softHint, fontHint);
                dc.drawText((((w / 2) - (softHintW / 2))).toNumber(), yHint, fontHint, softHint, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            } else {
                dc.drawText(w / 2, yHint, fontHint, "GPS Outdated", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            }
        }

    }

    function _isHardStale(nowTs as Number) as Boolean {
        var fix = _locationService.getLastFix();
        var fixTs = null;
        var ageSec = null;
        var hardStale = true;

        if (fix != null && fix[:ts] != null) {
            fixTs = fix[:ts] as Number;
            ageSec = nowTs - (fixTs as Number);
            hardStale = (ageSec as Number) > HARD_STALE_MAX_AGE_SEC;
        }

        return hardStale;
    }

    function _isSoftStale(nowTs as Number) as Boolean {
        var fix = _locationService.getLastFix();
        if (fix == null || fix[:ts] == null) {
            return false;
        }

        var ageSec = nowTs - (fix[:ts] as Number);
        var softStale = (ageSec > SOFT_STALE_MAX_AGE_SEC) && (ageSec <= HARD_STALE_MAX_AGE_SEC);
        return softStale;
    }

    function _formatStartTime(targetTs as Number or Null) as String {
        if (targetTs == null) {
            return "--:--";
        }

        var info = Time.Gregorian.info(new Time.Moment(targetTs as Number), Time.FORMAT_SHORT);
        return Lang.format(
            "$1$:$2$",
            [
                (info[:hour] as Number).format("%02d"),
                (info[:min] as Number).format("%02d")
            ]
        );
    }

    function _getSafeInsets(dc as Dc) as Lang.Dictionary {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var settings = System.getDeviceSettings();
        if (settings != null && settings.screenShape == System.SCREEN_SHAPE_ROUND) {
            var inset = ((w - (w * 0.70710678)) / 2).toNumber();
            return {
                :left => inset,
                :top => inset,
                :right => inset,
                :bottom => inset
            };
        }
        return {
            :left => 0,
            :top => 0,
            :right => 0,
            :bottom => 0
        };
    }

    function _isProLargeMipLayout(w as Number, h as Number) as Boolean {
        return (w == 260 && h == 260) || (w == 280 && h == 280);
    }

    function _isSymmetricCountdownLayout(w as Number, h as Number) as Boolean {
        return (w == 218 && h == 218)
            || (w == 240 && h == 240)
            || (w == 260 && h == 260)
            || (w == 280 && h == 280)
            || (w == 360 && h == 360)
            || (w == 390 && h == 390)
            || (w == 416 && h == 416)
            || (w == 454 && h == 454);
    }

    function _getTopAnchorY(w as Number, h as Number) as Number {
        if (w == 218 && h == 218) {
            return 28;
        }
        if (w == 240 && h == 240) {
            return 31;
        }
        if (w == 260 && h == 260) {
            return 36;
        }
        if (w == 280 && h == 280) {
            return 40;
        }
        if (w == 360 && h == 360) {
            return 52;
        }
        if (w == 390 && h == 390) {
            return 56;
        }
        if (w == 416 && h == 416) {
            return 60;
        }
        if (w == 454 && h == 454) {
            return 65;
        }
        return 31;
    }

    function _getBottomAnchorY(w as Number, h as Number) as Number {
        if (w == 218 && h == 218) {
            return h - 23;
        }
        if (w == 240 && h == 240) {
            return h - 24;
        }
        if (w == 260 && h == 260) {
            return h - 24;
        }
        if (w == 280 && h == 280) {
            return h - 30;
        }
        if (w == 360 && h == 360) {
            return h - 38;
        }
        if (w == 390 && h == 390) {
            return h - 41;
        }
        if (w == 416 && h == 416) {
            return h - 44;
        }
        if (w == 454 && h == 454) {
            return h - 48;
        }
        if (_isSymmetricCountdownLayout(w, h)) {
            return h - 24;
        }
        return h - 24;
    }

    function _getDateYOffsetAdjust(w as Number, h as Number) as Number {
        if (w == 218 && h == 218) {
            return -2;
        }
        if (w == 240 && h == 240) {
            return 0;
        }
        if (w == 260 && h == 260) {
            return -4;
        }
        if (w == 280 && h == 280) {
            return -3;
        }
        if (w == 360 && h == 360) {
            return -8;
        }
        if (w == 390 && h == 390) {
            return -7;
        }
        if (w == 416 && h == 416) {
            return -7;
        }
        if (w == 454 && h == 454) {
            return -7;
        }
        return 0;
    }

    function _getTimeYOffsetAdjust(w as Number, h as Number) as Number {
        if (w == 218 && h == 218) {
            return -9;
        }
        if (w == 240 && h == 240) {
            return 0;
        }
        if (w == 260 && h == 260) {
            return 0;
        }
        if (w == 280 && h == 280) {
            return 3;
        }
        if (w == 360 && h == 360) {
            return 8;
        }
        if (w == 390 && h == 390) {
            return 16;
        }
        if (w == 416 && h == 416) {
            return 20;
        }
        if (w == 454 && h == 454) {
            return 26;
        }
        return 0;
    }

    function _getCountdownModuleOffsetPx(w as Number, h as Number) as Number {
        if (w == 260 && h == 260) {
            return 43;
        }
        if (w == 218 && h == 218) {
            return 36;
        }
        if (w == 240 && h == 240) {
            return 40;
        }
        if (w == 280 && h == 280) {
            return 46;
        }
        if (w == 360 && h == 360) {
            return 58;
        }
        if (w == 390 && h == 390) {
            return 63;
        }
        if (w == 416 && h == 416) {
            return 67;
        }
        if (w == 454 && h == 454) {
            return 73;
        }
        return 40;
    }

    function _getCountdownLabelFont(w as Number, h as Number) {
        return Graphics.FONT_XTINY;
    }

    function _getCountdownHintFont(w as Number, h as Number) {
        return Graphics.FONT_XTINY;
    }

    function _getCountdownBlockYOffsetAdjust(w as Number, h as Number) as Number {
        if (w == 218 && h == 218) {
            return 0;
        }
        if (w == 240 && h == 240) {
            return 0;
        }
        if (w == 260 && h == 260) {
            return -7;
        }
        if (w == 280 && h == 280) {
            return -6;
        }
        if (w == 360 && h == 360) {
            return -8;
        }
        if (w == 390 && h == 390) {
            return -9;
        }
        if (w == 416 && h == 416) {
            return -10;
        }
        if (w == 454 && h == 454) {
            return -10;
        }
        return 0;
    }

    function _getCountdownValueYOffsetAdjust(w as Number, h as Number) as Number {
        if (w == 280 && h == 280) {
            return 3;
        }
        if (w == 390 && h == 390) {
            return -11;
        }
        if (w == 416 && h == 416) {
            return -10;
        }
        if (w == 454 && h == 454) {
            return -11;
        }
        return 0;
    }

    function _getCountdownLabelYOffsetAdjust(w as Number, h as Number) as Number {
        if (w == 218 && h == 218) {
            return 2;
        }
        if (w == 360 && h == 360) {
            return -10;
        }
        if (w == 390 && h == 390) {
            return -21;
        }
        if (w == 416 && h == 416) {
            return -26;
        }
        if (w == 454 && h == 454) {
            return -28;
        }
        return 0;
    }

    function _getHintYOffsetAdjust(w as Number, h as Number) as Number {
        if (w == 218 && h == 218) {
            return -1;
        }
        if (w == 240 && h == 240) {
            return 0;
        }
        if (w == 260 && h == 260) {
            return -3;
        }
        if (w == 280 && h == 280) {
            return 0;
        }
        if (w == 360 && h == 360) {
            return -2;
        }
        if (w == 390 && h == 390) {
            return -3;
        }
        if (w == 416 && h == 416) {
            return -3;
        }
        if (w == 454 && h == 454) {
            return -4;
        }
        return 0;
    }

    function _getPhaseEdgeFillColor(phase as String or Null) as Number {
        if (phase != null && phase.equals("NIGHT")) {
            return COLOR_BLACK;
        }
        if (phase != null && phase.equals("TWILIGHT")) {
            return 0x1C2432;
        }
        return COLOR_WHITE;
    }

    function _clamp(x, minV, maxV) {
        if (x < minV) {
            return minV;
        }
        if (x > maxV) {
            return maxV;
        }
        return x;
    }

    function _phaseFromState(state as String or Null) as String {
        if (state != null && (state.equals("BLUE") || state.equals("GOLDEN"))) {
            return "TWILIGHT";
        }
        if (state != null && state.equals("NIGHT")) {
            return "NIGHT";
        }
        return "DAY";
    }

    function _loadActivationData() as Void {
        _firstInstallTs = null;
        _isActivated = false;

        var stg = Application.Storage.getValue("activationData");
        if (stg == null) {
            return;
        }

        var dict = stg as Lang.Dictionary;
        if (dict["firstInstallTs"] != null) {
            _firstInstallTs = dict["firstInstallTs"] as Number;
        }
        if (dict["isActivated"] != null) {
            _isActivated = dict["isActivated"] as Boolean;
        }
    }

    function _persistActivationData() as Void {
        Application.Storage.setValue("activationData", {
            "firstInstallTs" => _firstInstallTs,
            "isActivated" => _isActivated
        });
    }

    function _syncActivationState(nowTs as Number) as Void {
        if (_firstInstallTs == null) {
            _firstInstallTs = nowTs;
            _persistActivationData();
        }

        if (_isActivated) {
            return;
        }

        var codeVal = Application.Properties.getValue("ActivationCode");
        if (codeVal == null) {
            return;
        }

        var code = codeVal as String;
        if (isValidActivationCode(code)) {
            _isActivated = true;
            _persistActivationData();
        }
    }

    function isTrialExpired(nowTs as Number) as Boolean {
        if (_isActivated) {
            return false;
        }
        if (_firstInstallTs == null) {
            return false;
        }
        return (nowTs - (_firstInstallTs as Number)) > TRIAL_DURATION_SEC;
    }

    function isValidActivationCode(code as String or Null) as Boolean {
        if (code == null) {
            return false;
        }

        var chars = (code as String).toUpper().toCharArray();
        if (chars.size() != ACTIVATION_CODE_LEN) {
            return false;
        }

        var sum = 0;
        for (var i = 0; i < chars.size(); i += 1) {
            var codePoint = chars[i].toNumber();
            var val = _activationCharValue(codePoint);
            if (val == null) {
                return false;
            }
            sum += (i + 1) * ((val as Number) + 7);
        }

        return (sum % 97) == 1;
    }

    function _activationCharValue(codePoint as Number) as Number or Null {
        if (codePoint >= 48 && codePoint <= 57) {
            return codePoint - 48;
        }
        if (codePoint >= 65 && codePoint <= 90) {
            return (codePoint - 65) + 10;
        }
        return null;
    }

}
