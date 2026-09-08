import Foundation

/// The language Codenotch speaks, optionally overriding the system one.
///
/// The override is nothing more than `AppleLanguages` in the app's own
/// defaults — the same key System Settings writes for a per-app language — so
/// every lookup (`String(localized:)`, SwiftUI's `Text`, the AppKit menus)
/// follows it without any call site being aware. `Bundle.main` picks its
/// language once per process, which is why a change only takes effect on the
/// next launch.
enum AppLanguage: String, CaseIterable, Identifiable {
    /// Whatever macOS is set to. The default.
    case system
    case english
    case chinese

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:  return String(localized: "System")
        // Autonyms: each language names itself, so these read the same in
        // either UI language and are deliberately not localizable.
        case .english: return "English"
        case .chinese: return "简体中文"
        }
    }

    /// The `AppleLanguages` value for this choice, or nil to follow macOS.
    private var languageCodes: [String]? {
        switch self {
        case .system:  return nil
        case .english: return ["en"]
        case .chinese: return ["zh-Hans"]
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
        return code.hasPrefix("zh") ? .chinese : .english
    }
}
