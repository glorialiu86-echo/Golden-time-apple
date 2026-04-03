import Toybox.Application;
import Toybox.Lang;
import Toybox.Position;
import Toybox.Time;

class LocationService {
    const FIX_REFRESH_INTERVAL_SEC = 5;
    const KEY_LASTFIX_LAT = "gt_lastfix_lat";
    const KEY_LASTFIX_LON = "gt_lastfix_lon";
    const KEY_LASTFIX_TS = "gt_lastfix_ts";
    const KEY_LASTFIX_ACC = "gt_lastfix_acc";
    const KEY_LASTFIX_VER = "gt_lastfix_ver";

    var _lastFix as Lang.Dictionary or Null;

    function initialize() {
        _lastFix = null;
        _loadPersistedFix();
    }

    function requestFixIfNeeded(nowTs as Number) as Void {
        var shouldRequest = false;
        if (_lastFix == null || _lastFix[:ts] == null) {
            shouldRequest = true;
        } else {
            var ageSec = nowTs - (_lastFix[:ts] as Number);
            shouldRequest = ageSec > FIX_REFRESH_INTERVAL_SEC;
        }

        if (!shouldRequest) {
            return;
        }

        try {
            var info = Position.getInfo();
            if (info == null || info.position == null) {
                _clearFix();
                return;
            }

            var coord = info.position.toDegrees();
            if (coord == null) {
                _clearFix();
                return;
            }

            var lat = coord[0];
            var lon = coord[1];
            if (lat == null || lon == null) {
                _clearFix();
                return;
            }
            if (lat < -90 || lat > 90 || lon < -180 || lon > 180) {
                _clearFix();
                return;
            }
            // Simulators often return (180,180) when no GPS fix is available.
            if (lat == 180 && lon == 180) {
                _clearFix();
                return;
            }

            var fix = {
                :lat => lat,
                :lon => lon,
                :ts => nowTs
            };

            if (info.accuracy != null) {
                fix[:acc] = info.accuracy;
            }

            _lastFix = fix;
            _persistFix(fix);
        } catch (ex) {
            _clearFix();
        }
    }

    function getLastFix() as Lang.Dictionary or Null {
        if (_lastFix != null && _lastFix[:ts] == null) {
            _lastFix[:ts] = Time.now().value();
            _persistFix(_lastFix);
        }
        return _lastFix;
    }

    function _loadPersistedFix() as Void {
        var app = Application.getApp();
        if (app == null) {
            return;
        }

        var lat = app.getProperty(KEY_LASTFIX_LAT) as Number or Null;
        var lon = app.getProperty(KEY_LASTFIX_LON) as Number or Null;
        var ts = app.getProperty(KEY_LASTFIX_TS) as Number or Null;
        var acc = app.getProperty(KEY_LASTFIX_ACC) as Number or Null;
        if (lat == null || lon == null || ts == null) {
            return;
        }
        if ((lat as Number) < -90 || (lat as Number) > 90 || (lon as Number) < -180 || (lon as Number) > 180) {
            return;
        }

        _lastFix = {
            :lat => lat,
            :lon => lon,
            :ts => ts
        };
        if (acc != null) {
            _lastFix[:acc] = acc;
        }
    }

    function _persistFix(fix as Lang.Dictionary) as Void {
        var app = Application.getApp();
        if (app == null) {
            return;
        }

        app.setProperty(KEY_LASTFIX_LAT, fix[:lat]);
        app.setProperty(KEY_LASTFIX_LON, fix[:lon]);
        app.setProperty(KEY_LASTFIX_TS, fix[:ts]);
        app.setProperty(KEY_LASTFIX_VER, 1);
        if (fix[:acc] != null) {
            app.setProperty(KEY_LASTFIX_ACC, fix[:acc]);
        } else {
            app.setProperty(KEY_LASTFIX_ACC, null);
        }
    }

    function _clearFix() as Void {
        _lastFix = null;

        var app = Application.getApp();
        if (app == null) {
            return;
        }

        app.setProperty(KEY_LASTFIX_LAT, null);
        app.setProperty(KEY_LASTFIX_LON, null);
        app.setProperty(KEY_LASTFIX_TS, null);
        app.setProperty(KEY_LASTFIX_ACC, null);
        app.setProperty(KEY_LASTFIX_VER, null);
    }
}
