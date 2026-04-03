import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class GoldenTimeApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
    }

    function onStop(state as Dictionary?) as Void {
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        return [ new GoldenTimeView() ];
    }

    function onSettingsChanged() as Void {
        WatchUi.requestUpdate();
    }
}

function getApp() as GoldenTimeApp {
    return Application.getApp() as GoldenTimeApp;
}
