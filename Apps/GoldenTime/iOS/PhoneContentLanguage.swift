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
            return "圆盘外圈刻度；外缘每 30° 有标注：0/90/180/270 为东南西北（北为红色），其余为数字。无表盘内方位字。上边为手机前向。红色指北符号随真机航向指向真北；真机转过 30° 整刻度时轻触反馈（模拟器常无罗盘/无震动）。半透明扇区为当天本地时区内各段蓝调/金调对应的太阳方位。无日出日落硬线、无系统指南针顶部粗标线。"
        case .english:
            return "Outer ticks; every 30° is labeled: N/E/S/W at 0/90/180/270 (N in red), other marks show degrees. No inner cardinal letters. Top = device forward. Red north glyph = true north; light haptic when heading crosses each 30° tick on device (simulator often has no compass/haptics). Sectors = blue/golden clips for the local day. No sunrise/sunset radial lines, no thick top heading bar."
        }
    }

    static func compassCardFootnote(_ lang: GTAppLanguage) -> String {
        switch lang {
        case .chinese:
            return "有网络路由时在罗盘圆盘下叠地图底图（不可缩放）；无网络时仅渐变底。角度均由本机推算。"
        case .english:
            return "With a network route, a non-interactive map sits under the compass; offline, only the gradient. Angles are computed on device."
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
