import Foundation

/// In-app UI language (separate from mixed bilingual card titles).
enum GTAppLanguage: String, Hashable {
    case chinese = "zh"
    case english = "en"

    static let storageKey = "gt.uiLanguage"

    /// 简体中文系统 → 默认中文界面；其余 → 默认英文。
    static func systemDefault() -> GTAppLanguage {
        guard let first = Locale.preferredLanguages.first else { return .english }
        if first.hasPrefix("zh-Hans") { return .chinese }
        if first.hasPrefix("zh-CN") { return .chinese }
        return .english
    }

    static func resolved() -> GTAppLanguage {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? ""
        return fromStorageRaw(raw)
    }

    static func fromStorageRaw(_ raw: String) -> GTAppLanguage {
        switch raw {
        case chinese.rawValue: return .chinese
        case english.rawValue: return .english
        default: return systemDefault()
        }
    }

    var locale: Locale {
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

    /// N, E, S, W in the active UI language (for circular dial).
    static func compassCardinals(_ lang: GTAppLanguage) -> (n: String, e: String, s: String, w: String) {
        switch lang {
        case .chinese: return ("北", "东", "南", "西")
        case .english: return ("N", "E", "S", "W")
        }
    }

    static func compassCardLegend(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese:
            return "外圈是方向刻度：每 30° 一处标注，正北、正东、正南、正西在 0°、90°、180°、270°（北为红色），其余为度数。圆盘朝上的一边表示你握手机时正对的方向。红色指北标指向真北。浅色半透明扇区表示今天各段蓝调、金调里太阳大致所在的方位。"
        case .english:
            return "The outer ring shows direction: a label every 30°, with N, E, S, W at the cardinal points (N in red) and degree numbers in between. The top of the dial matches the way you’re facing. The red marker points to true north. Light shaded sectors show roughly where the sun sits during today’s blue hour and golden hour windows."
        }
    }

    static func compassCardFootnote(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese:
            return "能加载地图时，罗盘背后会显示你当前位置附近的简图，仅供对照、不能缩放或拖动；无法加载时用柔和底色。太阳方位与罗盘角度均在手机上本地计算，不会把位置发到我们的服务器。"
        case .english:
            return "When map tiles can load, a simple map of your area appears behind the dial for context only—you can’t pan or zoom. Otherwise you’ll see a soft colored backdrop. Sun bearings and compass angles are calculated on your device; we don’t send your location to our servers."
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
    private nonisolated(unsafe) static var otherDayCache: [GTAppLanguage: DateFormatter] = [:]

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

    private static func otherDayFormatter(_ lang: GTAppLanguage) -> DateFormatter {
        if let f = otherDayCache[lang] { return f }
        let f = DateFormatter()
        f.locale = lang.locale
        switch lang {
        case .chinese:
            f.setLocalizedDateFormatFromTemplate("Mdjm")
        case .english:
            f.dateFormat = "MMM d, yyyy, HH:mm"
        }
        otherDayCache[lang] = f
        return f
    }

    static func headerLine(_ date: Date, lang: GTAppLanguage) -> String {
        headerFormatter(lang).string(from: date)
    }

    static func timeLine(_ date: Date, lang: GTAppLanguage) -> String {
        timeFormatter(lang).string(from: date)
    }

    /// Same calendar day as `now` → time only; else month/day + time.
    static func twilightInstantLabel(_ instant: Date, now: Date, lang: GTAppLanguage) -> String {
        let cal = Calendar.autoupdatingCurrent
        if cal.isDate(instant, inSameDayAs: now) {
            return timeFormatter(lang).string(from: instant)
        }
        return otherDayFormatter(lang).string(from: instant)
    }
}
