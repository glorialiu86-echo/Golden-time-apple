import Foundation

/// In-app UI language (separate from mixed bilingual card titles).
public enum GTAppLanguage: String, Hashable {
    case chinese = "zh"
    case english = "en"

    public static let storageKey = "gt.uiLanguage"
    /// Persisted with `storageKey` when the user chooses to match the iPhone system rules (`inferredFromSystem()`).
    public static let followSystemStorageValue = "system"
    /// iPhone writes the **effective** `zh`/`en` here so Watch/widgets match when preference is `followSystemStorageValue` or empty.
    public static let effectiveMirrorKey = "gt.uiLanguage.effectiveForWatch"

    #if DEBUG
    private static let debugOverrideEnvironmentKey = "GOLDEN_TIME_DEBUG_UI_LANGUAGE"

    private static var debugOverride: GTAppLanguage? {
        guard let raw = ProcessInfo.processInfo.environment[debugOverrideEnvironmentKey]?.lowercased() else { return nil }
        switch raw {
        case chinese.rawValue: return .chinese
        case english.rawValue: return .english
        default: return nil
        }
    }
    #endif

    /// 仅当 iPhone 系统为简体中文时使用中文界面；繁体与其它系统语言一律英文（用于「跟随系统」选项）。
    public static func inferredFromSystem() -> GTAppLanguage {
        guard let first = Locale.preferredLanguages.first?.lowercased() else { return .english }
        if first.hasPrefix("zh-hans") { return .chinese }
        if first.hasPrefix("zh-cn") { return .chinese }
        return .english
    }

    /// Same rule as `inferredFromSystem()` (legacy name).
    public static func systemDefault() -> GTAppLanguage {
        inferredFromSystem()
    }

    /// iPhone / iOS 主程序与 iOS 小组件：`zh` / `en` 固定；`system` 或空字符串表示跟随 `inferredFromSystem()`。
    public static func phoneDisplayLanguage(preferenceRaw: String) -> GTAppLanguage {
        #if DEBUG
        if let debugOverride { return debugOverride }
        #endif
        switch preferenceRaw {
        case chinese.rawValue: return .chinese
        case english.rawValue: return .english
        case followSystemStorageValue, "": return inferredFromSystem()
        default: return inferredFromSystem()
        }
    }

    /// Apple Watch：用户显式选 `zh`/`en` 时直接用；否则读 iPhone 写入的 `effectiveMirrorKey`（未同步前默认为英文）。
    public static func watchResolved(preferenceRaw: String, effectiveMirrorRaw: String) -> GTAppLanguage {
        #if DEBUG
        if let debugOverride { return debugOverride }
        #endif
        switch preferenceRaw {
        case chinese.rawValue: return .chinese
        case english.rawValue: return .english
        default:
            switch effectiveMirrorRaw {
            case chinese.rawValue: return .chinese
            case english.rawValue: return .english
            default: return .english
            }
        }
    }

    public static func widgetLanguageIOS(suite: UserDefaults) -> GTAppLanguage {
        let raw = suite.string(forKey: storageKey) ?? UserDefaults.standard.string(forKey: storageKey) ?? ""
        return phoneDisplayLanguage(preferenceRaw: raw)
    }

    public static func widgetLanguageWatch(suite: UserDefaults) -> GTAppLanguage {
        let pref = suite.string(forKey: storageKey) ?? ""
        let mirror = suite.string(forKey: effectiveMirrorKey) ?? ""
        return watchResolved(preferenceRaw: pref, effectiveMirrorRaw: mirror)
    }

    /// 读 App Group：`watchOS` 走 `widgetLanguageWatch`，其它走 `widgetLanguageIOS`。
    public static func resolved() -> GTAppLanguage {
        let suite = GTAppGroup.shared
        #if os(watchOS)
        return widgetLanguageWatch(suite: suite)
        #else
        return widgetLanguageIOS(suite: suite)
        #endif
    }

    /// 仅解析字面 `zh`/`en`；其它情况按平台回退（兼容旧调用；Watch 展示请优先用 `watchResolved` / `resolved()`）。
    public static func fromStorageRaw(_ raw: String) -> GTAppLanguage {
        switch raw {
        case chinese.rawValue: return .chinese
        case english.rawValue: return .english
        default:
            #if os(watchOS)
            return .english
            #else
            return inferredFromSystem()
            #endif
        }
    }

    public var locale: Locale {
        switch self {
        case .chinese: Locale(identifier: "zh_CN")
        case .english: Locale(identifier: "en_US")
        }
    }
}

// MARK: - Copy (single language per line; no zh·en mixing)

enum GTCopy {
    static func appDisplayName(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "光影罗盘"
        case .english: return "Twilight Compass"
        }
    }

    static func systemAppDisplayName() -> String {
        appDisplayName(GTAppLanguage.inferredFromSystem())
    }

    static func currentCoordinatesPrefix(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "当前经纬度 "
        case .english: return "Now at "
        }
    }

    /// 手表罗盘页坐标行前缀（更短，省横向空间）。
    static func watchCoordinatesPrefix(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "经纬度 "
        case .english: return "Now at "
        }
    }

    /// Shown only when there is no usable coordinate fix (no cache and no new GPS).
    static func coordinatesUnavailable(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "无法获取当前经纬度，太阳时刻与罗盘不可用。"
        case .english: return "Unable to read coordinates; sun windows and compass are unavailable."
        }
    }

    static func blueHourTitle(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "下一次蓝调时间"
        case .english: return "Next Blue Hour"
        }
    }

    static func goldenHourTitle(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "下一次金调时间"
        case .english: return "Next Golden Hour"
        }
    }

    static func widgetBlueHourTitle(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "下一次蓝调"
        case .english: return "Next Blue"
        }
    }

    static func widgetGoldenHourTitle(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "下一次金调"
        case .english: return "Next Golden"
        }
    }

    /// watchOS Smart Stack（systemSmall / systemMedium）顶部标题。
    static func widgetStackTitle(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "蓝调与金调"
        case .english: return "Blue & Golden Hour"
        }
    }

    /// iOS 主屏幕大组件底部提示（小组件不跑定位）。
    static func widgetOpenAppHint(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "打开 App 可更新定位与数据。"
        case .english: return "Open the app to refresh location."
        }
    }

    /// N, E, S, W in the active UI language (for circular dial).
    static func compassCardinals(_ lang: GTAppLanguage) -> (n: String, e: String, s: String, w: String) {
        switch lang {
        case .chinese: return ("北", "东", "南", "西")
        case .english: return ("N", "E", "S", "W")
        }
    }

    /// Three-line note under the compass (heading, sectors, offline + map).
    static func compassCardGuide(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese:
            return "红色箭头为手机当前朝向。太阳 / 月亮图标指示当前所在方位。\n罗盘扇区表示对应时段的光线方向（包含日/夜/金调/蓝调）。\n所有计算均在本地完成，除地图加载外，无需联网。"
        case .english:
            return "The red arrow shows how your phone is oriented. The sun and moon icons mark their directions on the dial.\nThe compass sectors show where sunlight comes from in each period (day, night, golden hour, and blue hour).\nAll calculations run on your device; aside from loading the map, no network connection is needed."
        }
    }

    static func compassCalibrationPersistentNote(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese:
            return "如果你觉得手机指南针受环境影响，可前往设置页手动校对并保存。"
        case .english:
            return "If your phone's compass seems affected by the environment, you can calibrate and save an adjustment in Settings."
        }
    }

    static func compassCardNeedLocation(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "需要定位后显示罗盘与方位。"
        case .english: return "Allow location to show the compass and bearings."
        }
    }

    static func compassInitialLoadingTitle(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "正在准备罗盘与方位…"
        case .english: return "Preparing compass and bearings..."
        }
    }

    static func compassInitialLoadingSubtitle(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "首次打开可能需要几秒。"
        case .english: return "First launch can take a few seconds."
        }
    }

    static func liveSegment(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "进行中"
        case .english: return "NOW"
        }
    }

    static func countdownLessThanOneMinute(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "不足1分"
        case .english: return "< 1 min"
        }
    }

    static func countdownMinutes(_ m: Int, _ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "\(m)分"
        case .english: return "\(m) min"
        }
    }

    static func countdownHoursMinutes(h: Int, m: Int, _ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return String(format: "%d小时%02d分", h, m)
        case .english: return String(format: "%dh %02dm", h, m)
        }
    }

    /// Small label above the countdown time on twilight cards.
    static func countdownUntilStartLabel(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "距开始"
        case .english: return "Until start"
        }
    }

    static func countdownUntilEndLabel(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "距结束"
        case .english: return "Until end"
        }
    }

    /// Tiny prefix on home-screen widget clock rows (before start / end instant or “live”).
    static func twilightClockStartTag(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "开始"
        case .english: return "Start"
        }
    }

    static func twilightClockEndTag(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "结束"
        case .english: return "End"
        }
    }

    /// Home-screen twilight widget header. English uses title case and omits “hour”.
    static func widgetTwilightTitleBlue(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "下一次蓝调"
        case .english: return "Next Blue"
        }
    }

    static func widgetTwilightTitleGolden(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "下一次金调"
        case .english: return "Next Golden"
        }
    }

    static func a11ySwitchToCountdown(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "切换到倒计时"
        case .english: return "Switch to countdown"
        }
    }

    static func a11ySwitchToClock(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "切换到时刻"
        case .english: return "Switch to clock times"
        }
    }

    static func a11yModeToggleHint(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "在固定起止时刻与剩余时间之间切换"
        case .english: return "Toggle between window times and time remaining"
        }
    }

    static func a11yLanguageToggle(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "切换为英文界面"
        case .english: return "Switch to Chinese UI"
        }
    }

    static func a11ySettings(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "设置"
        case .english: return "Settings"
        }
    }

    static func settingsTitle(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "设置"
        case .english: return "Settings"
        }
    }

    static func settingsLanguageSectionTitle(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "语言"
        case .english: return "Language"
        }
    }

    static func settingsLanguageOptionFollowSystem(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "跟随系统"
        case .english: return "Follow system"
        }
    }

    static func settingsLanguageOptionChinese(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "简体中文"
        case .english: return "Chinese"
        }
    }

    static func settingsLanguageOptionEnglish(_ lang: GTAppLanguage) -> String {
        "English"
    }

    static func settingsLocation(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "定位"
        case .english: return "Location"
        }
    }

    static func settingsCompassSectionTitle(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "指南"
        case .english: return "Compass"
        }
    }

    static func settingsCompassCalibrationTitle(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "指南校对"
        case .english: return "Compass Calibration"
        }
    }

    static func settingsCompassCalibrationClear(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "清除校对"
        case .english: return "Clear Calibration"
        }
    }

    static func watchCompassCalibrationHint(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "长按罗盘校对"
        case .english: return "Long press to calibrate"
        }
    }

    static func watchCompassCalibrationSave(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "保存校对"
        case .english: return "Save"
        }
    }

    static func watchCompassCalibrationClear(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "清除校对"
        case .english: return "Clear"
        }
    }

    static func settingsStatusPrefix(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "状态"
        case .english: return "Status"
        }
    }

    static func settingsLocationAuthorized(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "已授权"
        case .english: return "Allowed"
        }
    }

    static func settingsLocationDenied(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "已拒绝"
        case .english: return "Denied"
        }
    }

    static func settingsLocationNotDetermined(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "尚未询问"
        case .english: return "Not asked"
        }
    }

    static func settingsLocationRestricted(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "受限制"
        case .english: return "Restricted"
        }
    }

    static func settingsAllowLocation(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "授权使用定位"
        case .english: return "Allow location access"
        }
    }

    static func settingsOpenSystemSettings(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "前往系统设置"
        case .english: return "Open system settings"
        }
    }

    static func settingsRefreshLocation(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "刷新定位"
        case .english: return "Refresh location"
        }
    }

    static func settingsLocationFeedbackWaitingForPermission(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "等待系统弹出定位授权..."
        case .english: return "Waiting for the system location prompt..."
        }
    }

    static func settingsLocationFeedbackRefreshing(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "正在刷新定位..."
        case .english: return "Refreshing location..."
        }
    }

    static func settingsLocationFeedbackSuccess(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "定位已更新。"
        case .english: return "Location updated."
        }
    }

    static func settingsLocationFeedbackDenied(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "定位权限已关闭，请前往系统设置开启。"
        case .english: return "Location access is off. Open system settings to enable it."
        }
    }

    static func settingsLocationFeedbackRestricted(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "此设备当前限制了定位访问。"
        case .english: return "Location access is restricted on this device."
        }
    }

    static func settingsLocationFeedbackFailed(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "暂时没有拿到新的定位，请稍后再试。"
        case .english: return "No new location was received. Try again in a moment."
        }
    }

    static func settingsTwilightDisplay(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "蓝调 / 金调卡片"
        case .english: return "Twilight cards"
        }
    }

    static func settingsTwilightClockTimes(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "显示起止时刻"
        case .english: return "Window times"
        }
    }

    static func settingsTwilightCountdown(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "显示倒计时"
        case .english: return "Countdown"
        }
    }

    static func settingsReminderSection(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "一次性时段提醒"
        case .english: return "One-time twilight alert"
        }
    }

    static func settingsReminderToggle(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "开启下一次提醒"
        case .english: return "Enable next alert"
        }
    }

    static func settingsReminderOneShotNote(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "提醒只会触发一次。触发后如需下次提醒，请重新开启。"
        case .english: return "This alert fires once. Turn it on again after it fires if you want the next one."
        }
    }

    static func settingsReminderTarget(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "提醒对象"
        case .english: return "Alert for"
        }
    }

    static func settingsReminderTargetBlue(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "下一次蓝调"
        case .english: return "Next blue hour"
        }
    }

    static func settingsReminderTargetGolden(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "下一次金调"
        case .english: return "Next golden hour"
        }
    }

    static func settingsReminderLeadTime(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "提前"
        case .english: return "Minutes before"
        }
    }

    static func settingsReminderLeadTimeSuffix(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "分钟"
        case .english: return "minutes"
        }
    }

    static func reminderNotificationTitle(blue: Bool, lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return blue ? "蓝调即将开始" : "金调即将开始"
        case .english: return blue ? "Blue hour soon" : "Golden hour soon"
        }
    }

    static func reminderNotificationBody(blue: Bool, minutes: Int, lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese:
            return blue
                ? "约 \(minutes) 分钟后进入蓝调时段。"
                : "约 \(minutes) 分钟后进入金调时段。"
        case .english:
            let unit = minutes == 1 ? "minute" : "minutes"
            return blue
                ? "Blue hour starts in about \(minutes) \(unit)."
                : "Golden hour starts in about \(minutes) \(unit)."
        }
    }

    static func settingsRestorePurchases(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "恢复购买"
        case .english: return "Restore purchases"
        }
    }

    static func settingsRestoreWorking(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "正在同步…"
        case .english: return "Syncing…"
        }
    }

    static func settingsRestoreDone(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "已与 App Store 同步"
        case .english: return "Synced with the App Store"
        }
    }

    static func settingsRestoreFailed(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "同步失败"
        case .english: return "Could not sync"
        }
    }

    static func settingsDone(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "完成"
        case .english: return "Done"
        }
    }

    static func settingsPrivacyPolicy(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "隐私政策"
        case .english: return "Privacy Policy"
        }
    }

    static func settingsSupport(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "支持"
        case .english: return "Support"
        }
    }

    static func compassCalibrationStatusNotCalibrated(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "未校对"
        case .english: return "Not calibrated"
        }
    }

    static func compassCalibrationStatusCalibrated(date: Date, lang: GTAppLanguage) -> String {
        let formatted = GTDateFormatters.calibrationStatusDate(date, lang: lang)
        switch lang {
        case .chinese: return "已于 \(formatted) 校对"
        case .english: return "Calibrated on \(formatted)"
        }
    }

    static func compassCalibrationPageInstruction(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "将手机顶部对准当前太阳方向，再保存校对。"
        case .english: return "Point the top of your phone toward the sun, then save calibration."
        }
    }

    static func compassCalibrationPageAction(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "确认对准后，点“保存校对”。"
        case .english: return "When you're aligned, tap Save Calibration."
        }
    }

    static func compassCalibrationPagePersistence(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "校对结果会保存在这台 iPhone 上，之后罗盘会一直使用这次校对值，直到你再次手动校对或清除。"
        case .english: return "This calibration is saved on this iPhone and stays active until you recalibrate or clear it."
        }
    }

    static func compassCalibrationSave(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "保存校对"
        case .english: return "Save Calibration"
        }
    }

    static func compassCalibrationCancel(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "取消"
        case .english: return "Cancel"
        }
    }

    static func compassCalibrationClearTitle(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "清除指南校对？"
        case .english: return "Clear Compass Calibration?"
        }
    }

    static func compassCalibrationClearBody(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "清除后，罗盘将恢复使用设备当前原始方向。"
        case .english: return "After clearing, the compass will return to the device's current raw heading."
        }
    }

    static func compassCalibrationNeedsLocationPermission(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "需要定位权限后才能校对"
        case .english: return "Location access is required before calibration."
        }
    }

    static func compassCalibrationNeedsLocationFix(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "暂时无法获取当前位置"
        case .english: return "Current location is temporarily unavailable."
        }
    }

    static func compassCalibrationNeedsHeading(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "暂时无法获取设备方向"
        case .english: return "Device direction is temporarily unavailable."
        }
    }

    static func compassCalibrationTrueNorthRequired(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "当前未拿到真北方向，暂时不能保存校对"
        case .english: return "True north is unavailable right now, so calibration cannot be saved yet."
        }
    }

    static func compassCalibrationSunUnavailable(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "当前太阳不可见，暂时无法进行太阳校对"
        case .english: return "The sun is not visible right now, so sun calibration is unavailable."
        }
    }

    static func compassCalibrationSavedHeadingHint(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "当前已满足保存条件"
        case .english: return "Ready to save the current calibration."
        }
    }

    static func compassCalibrationSaved(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "已保存指南校对"
        case .english: return "Compass calibration saved"
        }
    }

    static func compassCalibrationCleared(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "已清除指南校对"
        case .english: return "Compass calibration cleared"
        }
    }

    static func legalPrivacyPolicyBody(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese:
            return """
            生效日期：2026 年 4 月 5 日

            光影罗盘会读取你设备的定位，用于在本地计算蓝调、金调和罗盘方位。除 Apple 提供的地图底图加载外，本 App 不依赖自建网络服务。

            我们如何使用数据
            1. 定位信息
            用于在你的设备上计算当前经纬度对应的蓝调、金调、日夜分区和太阳 / 月亮方位。默认不会上传到开发者服务器。

            2. 通知权限
            如果你开启时段提醒，App 会在设备本地安排通知，在蓝调或金调开始前提醒你。

            3. 本地偏好设置
            语言、卡片显示方式、提醒选项和罗盘地图缩放等设置会保存在设备本地；当你启用同一 App Group 的组件时，这些设置也可能在本机的 App Group 容器内共享。

            4. 地图底图
            当罗盘显示地图底图时，地图瓦片由 Apple MapKit 提供。对应的网络请求由 Apple 处理，不会进入开发者自建服务器。

            我们不做什么
            • 不创建用户账号
            • 不出售个人信息
            • 不使用广告追踪
            • 不把定位数据上传到开发者自建服务器

            你的选择
            • 你可以在系统设置中关闭定位权限
            • 你可以在设置页关闭提醒
            • 你可以随时删除 App 来移除本地数据

            联系与支持
            开发者：上海佑一程信息科技有限公司
            支持邮箱：developer@auroracapture.com
            """
        case .english:
            return """
            Effective date: April 5, 2026

            Twilight Compass reads your device location to calculate blue hour, golden hour, and compass bearings on-device. The app does not rely on a developer-run backend, except that Apple may load map tiles when the compass shows a map base.

            How data is used
            1. Location
            Used to calculate blue hour, golden hour, daylight sectors, and sun / moon bearings on your device. Location is not uploaded to a developer-operated server by default.

            2. Notifications
            If you enable twilight alerts, the app schedules local notifications on your device to remind you before the next blue or golden hour.

            3. Local preferences
            Language, twilight card display mode, alert settings, and compass map zoom are stored locally on your device. When components in the same App Group are enabled, these settings may also be shared through the local App Group container on the same device.

            4. Map base
            When the compass shows a map base, map tiles are provided by Apple MapKit. Any related network requests are handled by Apple rather than a developer-operated server.

            What we do not do
            • No account creation
            • No sale of personal data
            • No advertising tracking
            • No upload of location data to a developer-operated server

            Your choices
            • You can disable location access in system settings
            • You can turn off alerts in Settings
            • You can delete the app to remove local data

            Contact and support
            Developer: Shanghai Youyicheng Information Technology Co., Ltd.
            Support email: developer@auroracapture.com
            """
        }
    }

    static func legalSupportBody(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese:
            return """
            光影罗盘支持信息

            适用版本
            1.0

            功能说明
            • 根据当前经纬度本地计算蓝调与金调
            • 显示太阳、月亮与罗盘方位
            • 可选本地提醒
            • 支持中文 / 英文界面

            常见问题
            1. 时间或方位不更新
            请确认已授予定位权限，并在设置页点击“刷新定位”。

            2. 罗盘底图没有显示
            地图底图依赖 Apple MapKit 网络瓦片；离线或网络受限时，App 仍可继续本地计算，只是不显示地图底图。

            3. 提醒没有触发
            请确认系统通知权限已开启，并检查是否已在设置页打开时段提醒。

            4. 语言没有切换
            请在设置页修改语言选项；如果仍未刷新，完全退出并重新打开 App。

            开发者
            上海佑一程信息科技有限公司

            支持邮箱
            developer@auroracapture.com
            """
        case .english:
            return """
            Twilight Compass Support

            App version
            1.0

            Features
            • On-device blue hour and golden hour calculations from current coordinates
            • Sun, moon, and compass bearings
            • Optional local alerts
            • Chinese and English UI

            Frequently asked questions
            1. Time or bearings are not updating
            Make sure location access is allowed, then tap “Refresh location” in Settings.

            2. The compass map base is missing
            The map base depends on Apple MapKit tiles. The app can continue calculating on-device while offline, but the map base may not appear.

            3. Alerts are not firing
            Confirm that system notification permission is enabled and that twilight alerts are turned on in Settings.

            4. The language did not change
            Change the language in Settings. If the screen still looks stale, fully quit and reopen the app.

            Developer
            Shanghai Youyicheng Information Technology Co., Ltd.

            Support email
            developer@auroracapture.com
            """
        }
    }
}

// MARK: - Date / time formatting (follows chosen UI language)

enum GTDateFormatters {
    /// Bumped when date patterns change so cached formatters are not reused incorrectly.
    private nonisolated(unsafe) static var headerCache: [GTAppLanguage: DateFormatter] = [:]
    private nonisolated(unsafe) static var timeCache: [GTAppLanguage: DateFormatter] = [:]
    private nonisolated(unsafe) static var calibrationDateCache: [GTAppLanguage: DateFormatter] = [:]
    private static func headerFormatter(_ lang: GTAppLanguage) -> DateFormatter {
        if let f = headerCache[lang] { return f }
        let f = DateFormatter()
        f.locale = lang.locale
        // Weekday + month + day + year (localized order).
        f.setLocalizedDateFormatFromTemplate("yMMMEd")
        headerCache[lang] = f
        return f
    }

    private static func timeFormatter(_ lang: GTAppLanguage) -> DateFormatter {
        if let f = timeCache[lang] { return f }
        let f = DateFormatter()
        f.locale = lang.locale
        f.dateStyle = .none
        switch lang {
        case .chinese:
            f.setLocalizedDateFormatFromTemplate("jm")
        case .english:
            f.dateFormat = "HH:mm"
        }
        timeCache[lang] = f
        return f
    }

    private static func calibrationDateFormatter(_ lang: GTAppLanguage) -> DateFormatter {
        if let f = calibrationDateCache[lang] { return f }
        let f = DateFormatter()
        f.locale = lang.locale
        f.dateStyle = .medium
        f.timeStyle = .none
        calibrationDateCache[lang] = f
        return f
    }

    static func headerLine(_ date: Date, lang: GTAppLanguage) -> String {
        headerFormatter(lang).string(from: date)
    }

    static func timeLine(_ date: Date, lang: GTAppLanguage) -> String {
        timeFormatter(lang).string(from: date)
    }

    /// Twilight window endpoints on cards/widgets: **time only** (no date / 今天明天).
    static func twilightInstantLabel(_ instant: Date, lang: GTAppLanguage) -> String {
        timeFormatter(lang).string(from: instant)
    }

    static func calibrationStatusDate(_ date: Date, lang: GTAppLanguage) -> String {
        calibrationDateFormatter(lang).string(from: date)
    }
}
