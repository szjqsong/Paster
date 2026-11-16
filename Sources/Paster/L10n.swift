import Foundation

/// UI language: English, Traditional Chinese (Taiwan terms) or Simplified Chinese (mainland terms).
enum AppLanguage: String, CaseIterable, Identifiable {
    case auto, en, zhHant, zhHans
    var id: String { rawValue }

    static let defaultsKey = "appLanguage"

    /// The user's choice in Preferences ("auto" follows the system language order).
    static var preference: AppLanguage {
        get { AppLanguage(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .auto }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }

    /// The preference as it was when Paster started.
    static let launchPreference = preference

    /// Resolved once per launch; changing the language asks for a relaunch.
    static let current: AppLanguage = {
        let pref = launchPreference
        if pref != .auto { return pref }
        for lang in Locale.preferredLanguages {
            if lang.hasPrefix("en") { return .en }
            if lang.hasPrefix("zh") {
                if lang.contains("Hans") { return .zhHans }
                if lang.contains("Hant") { return .zhHant }
                return (lang.hasSuffix("CN") || lang.hasSuffix("SG")) ? .zhHans : .zhHant
            }
        }
        return .en
    }()

    /// Shown in its own language so it is recognisable whatever the UI language is.
    var displayName: String {
        switch self {
        case .auto: return L("Automatic (System)", "自動（跟隨系統）")
        case .en: return "English"
        case .zhHant: return "繁體中文"
        case .zhHans: return "简体中文"
        }
    }
}

/// `L(english, traditionalChinese)`. Simplified Chinese is derived from the Traditional text:
/// Taiwan-specific terms are first replaced with their mainland equivalents, then the remaining
/// characters are converted with ICU's Hant→Hans transform.
func L(_ en: String, _ zhHant: String) -> String {
    switch AppLanguage.current {
    case .zhHant: return zhHant
    case .zhHans: return SimplifiedChinese.convert(zhHant)
    case .en, .auto: return en
    }
}

enum SimplifiedChinese {
    /// Longest phrases first so e.g. 偏好設定 wins over 設定.
    private static let terms: [(String, String)] = [
        ("偏好設定", "偏好设置"),
        ("剪貼簿", "剪贴板"),
        ("釘選板", "固定板"),
        ("釘選", "固定"),
        ("輔助使用", "辅助功能"),
        ("重新命名", "重命名"),
        ("結束 Paster", "退出 Paster"),
        ("錄影", "录屏"),
        ("螢幕", "屏幕"),
        ("檔案", "文件"),
        ("連結", "链接"),
        ("字元", "字符"),
        ("文字", "文本"),
        ("搜尋", "搜索"),
        ("預設", "默认"),
        ("設定", "设置"),
        ("登入", "登录"),
        ("貼上", "粘贴"),
        ("貼到", "粘贴到"),
        ("儲存", "存储"),
        ("新增", "新建"),
        ("一般", "通用"),
        ("套用", "应用"),
        ("空白鍵", "空格键"),
        ("符合", "匹配"),
        ("目前", "当前"),
        ("暫時性", "临时"),
        ("按右鍵", "右键点按"),
        ("辨識", "识别"),
        ("裝置", "设备"),
        ("「", "“"),
        ("」", "”"),
    ]

    private static var cache: [String: String] = [:]
    private static let lock = NSLock()

    static func convert(_ s: String) -> String {
        lock.lock(); defer { lock.unlock() }
        if let hit = cache[s] { return hit }
        var out = s
        for (tw, cn) in terms { out = out.replacingOccurrences(of: tw, with: cn) }
        out = out.applyingTransform(StringTransform("Hant-Hans"), reverse: false) ?? out
        if cache.count > 2000 { cache.removeAll() }
        cache[s] = out
        return out
    }
}
