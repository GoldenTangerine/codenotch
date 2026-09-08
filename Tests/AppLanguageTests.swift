import XCTest
@testable import Codenotch

@MainActor
final class AppLanguageTests: XCTestCase {
    /// A scratch suite is its own domain: reading `AppleLanguages` straight
    /// off it would fall through to the *global* domain and find the Mac's
    /// system languages, so every check here goes through the suite's own
    /// persistent domain instead.
    private func makeDefaults() -> (name: String, defaults: UserDefaults) {
        let name = "AppLanguageTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return (name, defaults)
    }

    private func ownOverride(in suite: String, _ defaults: UserDefaults) -> [String]? {
        defaults.persistentDomain(forName: suite)?["AppleLanguages"] as? [String]
    }

    func testDefaultFollowsTheSystemWithNoOverride() {
        let (name, defaults) = makeDefaults()

        let preferences = Preferences(defaults: defaults, domainName: name)

        XCTAssertEqual(preferences.language, .system)
        XCTAssertEqual(preferences.appliedLanguage, .system)
        XCTAssertNil(ownOverride(in: name, defaults))
    }

    func testChoosingChineseWritesTheOverrideForTheNextLaunch() {
        let (name, defaults) = makeDefaults()
        let preferences = Preferences(defaults: defaults, domainName: name)

        preferences.language = .chinese

        XCTAssertEqual(ownOverride(in: name, defaults), ["zh-Hans"])
        // The running process is unaffected — it launched as .system.
        XCTAssertEqual(preferences.appliedLanguage, .system)
    }

    func testChoosingSystemAgainRemovesTheOverride() {
        let (name, defaults) = makeDefaults()
        let preferences = Preferences(defaults: defaults, domainName: name)

        preferences.language = .english
        preferences.language = .system

        XCTAssertNil(ownOverride(in: name, defaults))
        XCTAssertEqual(preferences.language, .system)
    }

    func testAStoredChoiceSurvivesRelaunch() {
        let (name, defaults) = makeDefaults()
        Preferences(defaults: defaults, domainName: name).language = .chinese

        let preferences = Preferences(defaults: defaults, domainName: name)

        XCTAssertEqual(preferences.language, .chinese)
        XCTAssertEqual(preferences.appliedLanguage, .chinese)
    }

    /// System Settings writes the very same key for a per-app language, so a
    /// choice made there is simply what the picker shows — nothing to
    /// reconcile, no second source to disagree.
    func testAnOverrideWrittenOutsideTheAppIsWhatThePickerShows() {
        let (name, defaults) = makeDefaults()
        defaults.set(["zh-Hans"], forKey: "AppleLanguages")

        let preferences = Preferences(defaults: defaults, domainName: name)

        XCTAssertEqual(preferences.language, .chinese)
        XCTAssertEqual(preferences.appliedLanguage, .chinese)
    }
}
