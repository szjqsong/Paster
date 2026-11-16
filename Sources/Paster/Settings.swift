import AppKit
import Carbon.HIToolbox

extension Notification.Name {
    static let pasterHotKeyChanged = Notification.Name("PasterHotKeyChanged")
    static let pasterAppearanceChanged = Notification.Name("PasterAppearanceChanged")
}

final class Settings: ObservableObject {
    static let shared = Settings()
    private let d = UserDefaults.standard

    @Published var historyLimit: Int { didSet { d.set(historyLimit, forKey: "historyLimit"); Store.shared.trim() } }
    @Published var hotKeyCode: UInt32 { didSet { d.set(Int(hotKeyCode), forKey: "hotKeyCode") } }
    @Published var hotKeyModifiers: UInt32 { didSet { d.set(Int(hotKeyModifiers), forKey: "hotKeyModifiers") } }
    @Published var excludedBundleIDs: [String] { didSet { d.set(excludedBundleIDs, forKey: "excludedBundleIDs") } }
    @Published var pasteDirectly: Bool { didSet { d.set(pasteDirectly, forKey: "pasteDirectly") } }
    @Published var plainTextByDefault: Bool { didSet { d.set(plainTextByDefault, forKey: "plainTextByDefault") } }
    @Published var ignoreConcealed: Bool { didSet { d.set(ignoreConcealed, forKey: "ignoreConcealed") } }
    @Published var paused: Bool { didSet { d.set(paused, forKey: "paused") } }
    @Published var hideFromScreenSharing: Bool {
        didSet { d.set(hideFromScreenSharing, forKey: "hideFromScreenSharing"); NotificationCenter.default.post(name: .pasterAppearanceChanged, object: nil) }
    }
    @Published var recognizeTextInImages: Bool { didSet { d.set(recognizeTextInImages, forKey: "recognizeTextInImages") } }

    /// Display names for the default entries, used when the app isn't installed.
    static let knownAppNames: [String: String] = [
        "com.1password.1password": "1Password", "com.1password": "1Password",
        "com.agilebits.onepassword-osx": "1Password 6", "com.agilebits.onepassword4": "1Password 4",
        "com.agilebits.onepassword7": "1Password 7", "com.bitwarden.desktop": "Bitwarden",
        "com.dashlane.Dashlane": "Dashlane", "com.lastpass.LastPass": "LastPass",
        "com.keepersecurity": "Keeper", "com.apple.Passwords": L("Passwords", "密碼"),
        "com.apple.keychainaccess": L("Keychain Access", "鑰匙圈存取"),
    ]

    /// Password managers ignored by default (same set Paste ships with).
    static let defaultExcludedBundleIDs = [
        "com.1password.1password", "com.1password", "com.agilebits.onepassword-osx",
        "com.agilebits.onepassword4", "com.agilebits.onepassword7",
        "com.bitwarden.desktop", "com.dashlane.Dashlane", "com.lastpass.LastPass",
        "com.keepersecurity", "com.apple.Passwords", "com.apple.keychainaccess",
    ]

    var hasLaunchedBefore: Bool {
        get { d.bool(forKey: "hasLaunchedBefore") }
        set { d.set(newValue, forKey: "hasLaunchedBefore") }
    }

    private init() {
        d.register(defaults: [
            "historyLimit": 1000,
            "hotKeyCode": kVK_ANSI_V,
            "hotKeyModifiers": cmdKey | shiftKey,
            "pasteDirectly": true,
            "plainTextByDefault": false,
            "ignoreConcealed": true,
            "paused": false,
            "hideFromScreenSharing": true,
            "recognizeTextInImages": true,
            "excludedBundleIDs": Settings.defaultExcludedBundleIDs,
        ])
        historyLimit = d.integer(forKey: "historyLimit")
        hotKeyCode = UInt32(d.integer(forKey: "hotKeyCode"))
        hotKeyModifiers = UInt32(d.integer(forKey: "hotKeyModifiers"))
        excludedBundleIDs = d.stringArray(forKey: "excludedBundleIDs") ?? Settings.defaultExcludedBundleIDs
        pasteDirectly = d.bool(forKey: "pasteDirectly")
        plainTextByDefault = d.bool(forKey: "plainTextByDefault")
        ignoreConcealed = d.bool(forKey: "ignoreConcealed")
        paused = d.bool(forKey: "paused")
        hideFromScreenSharing = d.bool(forKey: "hideFromScreenSharing")
        recognizeTextInImages = d.bool(forKey: "recognizeTextInImages")
    }

    var hotKeyDisplay: String {
        KeyNames.display(keyCode: hotKeyCode, carbonModifiers: hotKeyModifiers)
    }
}

enum KeyNames {
    static let names: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7",
        27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
        36: "↩", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
        45: "N", 46: "M", 47: ".", 48: "⇥", 49: "Space", 50: "`", 51: "⌫", 53: "⎋",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]

    static func display(keyCode: UInt32, carbonModifiers m: UInt32) -> String {
        var s = ""
        if m & UInt32(controlKey) != 0 { s += "⌃" }
        if m & UInt32(optionKey) != 0 { s += "⌥" }
        if m & UInt32(shiftKey) != 0 { s += "⇧" }
        if m & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + (names[keyCode] ?? "Key\(keyCode)")
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        return m
    }

    static func cocoaModifiers(fromCarbon m: UInt32) -> NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = []
        if m & UInt32(cmdKey) != 0 { f.insert(.command) }
        if m & UInt32(shiftKey) != 0 { f.insert(.shift) }
        if m & UInt32(optionKey) != 0 { f.insert(.option) }
        if m & UInt32(controlKey) != 0 { f.insert(.control) }
        return f
    }
}
