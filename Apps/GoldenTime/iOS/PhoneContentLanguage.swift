import Foundation

/// In-app UI language (separate from mixed bilingual card titles).
public enum GTAppLanguage: String, Hashable {
    case chinese = "zh"
    case english = "en"

    public static let storageKey = "gt.uiLanguage"

    /// 简体中文系统 → 默认中文界面；其余 → 默认英文。
    public static func systemDefault() -> GTAppLanguage {
        guard let first = Locale.preferredLanguages.first else { return .english }
        if first.hasPrefix("zh-Hans") { return .chinese }
        if first.hasPrefix("zh-CN") { return .chinese }
        return .english
    }

    public static func resolved() -> GTAppLanguage {
        let suite = GTAppGroup.shared
        let raw = suite.string(forKey: storageKey) ?? UserDefaults.standard.string(forKey: storageKey) ?? ""
        return fromStorageRaw(raw)
    }

    public static func fromStorageRaw(_ raw: String) -> GTAppLanguage {
        switch raw {
        case chinese.rawValue: return .chinese
        case english.rawValue: return .english
        default: return systemDefault()
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
