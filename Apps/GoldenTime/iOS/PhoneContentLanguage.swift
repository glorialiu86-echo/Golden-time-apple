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
        switch preferenceRaw {
        case chinese.rawValue: return .chinese
        case english.rawValue: return .english
        case followSystemStorageValue, "": return inferredFromSystem()
        default: return inferredFromSystem()
        }
    }

    /// Apple Watch：用户显式选 `zh`/`en` 时直接用；否则读 iPhone 写入的 `effectiveMirrorKey`（未同步前默认为英文）。
    public static func watchResolved(preferenceRaw: String, effectiveMirrorRaw: String) -> GTAppLanguage {
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

    static func compassCardNeedLocation(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese: return "需要定位后显示罗盘与方位。"
        case .english: return "Allow location to show the compass and bearings."
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
}

// MARK: - Date / time formatting (follows chosen UI language)

enum GTDateFormatters {
    /// Bumped when date patterns change so cached formatters are not reused incorrectly.
    private nonisolated(unsafe) static var headerCache: [GTAppLanguage: DateFormatter] = [:]
    private nonisolated(unsafe) static var timeCache: [GTAppLanguage: DateFormatter] = [:]
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
}
