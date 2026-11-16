import Foundation

/// Minimal two-language localisation: Chinese when the system prefers Chinese, English otherwise.
let prefersChinese: Bool = Locale.preferredLanguages.first?.hasPrefix("zh") ?? false

func L(_ en: String, _ zh: String) -> String {
    prefersChinese ? zh : en
}
