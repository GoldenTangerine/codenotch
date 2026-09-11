/**
 @name: 上游同步模块
 @Descripttion: 维护 AppLanguage.swift 的项目实现与上游兼容。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-11 15:51:14
 @LastEditTime: 2026-09-11 15:51:14
 @FilePath: Sources/Settings/AppLanguage.swift
 */
import Foundation

/// Which language Codenotch's own copy uses.
///
/// Follow System is the default. A forced choice exists because the Mac's
/// language is not always the one the person wants this app in — bilingual
/// machines, or a Mac in a language we do not ship.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case english = "en"
    case french = "fr"
    case japanese = "ja"
    case brazilianPortuguese = "pt-BR"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }

    /// `nil` means follow the Mac.
    ///
    /// Plain `en`, not `en_US`: these identifiers are looked up against the
    /// string catalog, whose English is filed under `en`. A region-qualified
    /// identifier misses it and falls through to whatever localization the
    /// bundle offers next — which made choosing English serve Chinese.
    var locale: Locale? {
        switch self {
        case .system:              return nil
        case .english:             return Locale(identifier: "en")
        case .french:              return Locale(identifier: "fr")
        case .japanese:            return Locale(identifier: "ja")
        case .brazilianPortuguese: return Locale(identifier: "pt-BR")
        case .simplifiedChinese:   return Locale(identifier: "zh-Hans")
        }
    }

    /// English, Français, 日本語, Português (Brasil) and 简体中文 stay in their
    /// own language so the row is recognizable when the rest of Settings is in
    /// another one.
    var title: String {
        switch self {
        case .system:              return L10n.t("Follow System")
        case .english:             return "English"
        case .french:              return "Français"
        case .japanese:            return "日本語"
        case .brazilianPortuguese: return "Português (Brasil)"
        case .simplifiedChinese:   return "简体中文"
        }
    }

    var explanation: String {
        switch self {
        case .system:
            return L10n.t("Matches the Mac's preferred language.")
        case .english, .french, .japanese, .brazilianPortuguese, .simplifiedChinese:
            return L10n.t("Codenotch uses this language even if the Mac does not.")
        }
    }

    static var chinese: AppLanguage { .simplifiedChinese }

    /// The `AppleLanguages` value for this choice, or nil to follow macOS.
    private var languageCodes: [String]? {
        switch self {
        case .system:  return nil
        case .english: return ["en"]
        case .french: return ["fr"]
        case .japanese: return ["ja"]
        case .brazilianPortuguese: return ["pt-BR"]
        case .simplifiedChinese: return ["zh-Hans"]
        }
    }

    /// Writes the override for the *next* launch; the running process keeps
    /// the language it started with.
    func apply(to defaults: UserDefaults) {
        if let codes = languageCodes {
            defaults.set(codes, forKey: "AppleLanguages")
        } else {
            defaults.removeObject(forKey: "AppleLanguages")
        }
    }

    /// The override written to this app's *own* defaults domain — the same
    /// key System Settings writes for a per-app language, so a choice made
    /// there shows up here for free. A plain `object(forKey:)` read would fall
    /// through to the global domain and mistake the system's language list
    /// for a per-app choice.
    static func ownOverride(in defaults: UserDefaults, domainName: String?) -> AppLanguage? {
        guard let domainName,
              let code = (defaults.persistentDomain(forName: domainName)?["AppleLanguages"] as? [String])?.first
        else { return nil }
        return code.hasPrefix("zh") ? .simplifiedChinese : AppLanguage(rawValue: code) ?? .english
    }
}
