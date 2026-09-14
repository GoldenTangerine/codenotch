/**
 @name: 偏好设置测试
 @Descripttion: 验证设置迁移与刘海触发高度持久化。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-09 09:41:19
 @LastEditTime: 2026-09-09 09:41:19
 @FilePath: Tests/PreferencesTests.swift
 */
import AppKit
import Combine
import XCTest
@testable import Codenotch

@MainActor
final class AccentColorPreferencesTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let name = "AccentColorPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    func testFreshInstallKeepsNotchOnSystemAfterChangingInterface() {
        let defaults = makeDefaults()
        let preferences = Preferences(defaults: defaults)
        XCTAssertEqual(preferences.accentColor, .system)
        XCTAssertEqual(preferences.notchAccentColor, .system)

        preferences.accentColor = .blue
        XCTAssertEqual(preferences.notchAccentColor, .system)
        let reloaded = Preferences(defaults: defaults)
        XCTAssertEqual(reloaded.accentColor, .blue)
        XCTAssertEqual(reloaded.notchAccentColor, .system)
    }

    func testUpgradePreservesEveryLegacyChoiceForBothScopes() {
        for choice in AccentColorChoice.allCases {
            let defaults = makeDefaults()
            defaults.set(choice.rawValue, forKey: "accentColor")

            let preferences = Preferences(defaults: defaults)
            XCTAssertEqual(preferences.accentColor, choice)
            XCTAssertEqual(preferences.notchAccentColor, choice)

            preferences.accentColor = choice == .blue ? .pink : .blue
            XCTAssertEqual(Preferences(defaults: defaults).notchAccentColor, choice)
        }
    }

    func testBothChoicesChangeIndependentlyAndSurviveRestart() {
        let defaults = makeDefaults()
        defaults.set(AccentColorChoice.green.rawValue, forKey: "accentColor")
        let preferences = Preferences(defaults: defaults)

        preferences.notchAccentColor = .pink
        XCTAssertEqual(preferences.accentColor, .green)
        preferences.accentColor = .blue
        XCTAssertEqual(preferences.notchAccentColor, .pink)

        let reloaded = Preferences(defaults: defaults)
        XCTAssertEqual(reloaded.accentColor, .blue)
        XCTAssertEqual(reloaded.notchAccentColor, .pink)
    }

    func testExistingNotchChoiceIsNeverOverwrittenByMigration() {
        let defaults = makeDefaults()
        defaults.set(AccentColorChoice.blue.rawValue, forKey: "accentColor")
        for choice in [AccentColorChoice.pink, .system] {
            defaults.set(choice.rawValue, forKey: "notchAccentColor")
            let preferences = Preferences(defaults: defaults)
            XCTAssertEqual(preferences.accentColor, .blue)
            XCTAssertEqual(preferences.notchAccentColor, choice)
            XCTAssertEqual(Preferences(defaults: defaults).notchAccentColor, choice)
        }
    }

    func testInvalidChoicesFallBackIndependently() {
        let defaults = makeDefaults()
        defaults.set("ultraviolet", forKey: "accentColor")
        let migrated = Preferences(defaults: defaults)
        XCTAssertEqual(migrated.accentColor, .system)
        XCTAssertEqual(migrated.notchAccentColor, .system)

        defaults.set(AccentColorChoice.pink.rawValue, forKey: "notchAccentColor")
        let invalidInterface = Preferences(defaults: defaults)
        XCTAssertEqual(invalidInterface.accentColor, .system)
        XCTAssertEqual(invalidInterface.notchAccentColor, .pink)

        defaults.set(AccentColorChoice.blue.rawValue, forKey: "accentColor")
        for invalidValue: Any in ["ultraviolet", 42] {
            defaults.set(invalidValue, forKey: "notchAccentColor")
            let invalidNotch = Preferences(defaults: defaults)
            XCTAssertEqual(invalidNotch.accentColor, .blue)
            XCTAssertEqual(invalidNotch.notchAccentColor, .system)
        }
    }

    func testFleetAppliesAccentToExistingAndRecreatedControllers() throws {
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("Requires a display") }
        let fleet = NotchFleet(scope: .allDisplays, edge: .top)
        defer { fleet.stop() }
        fleet.apply(accentColor: .pink)
        fleet.show()
        XCTAssertFalse(fleet.controllersForTesting.isEmpty)
        XCTAssertTrue(fleet.controllersForTesting.allSatisfy { $0.model.accentColor == .pink })

        fleet.apply(accentColor: .blue)
        XCTAssertTrue(fleet.controllersForTesting.allSatisfy { $0.model.accentColor == .blue })

        fleet.stop()
        fleet.show()
        XCTAssertFalse(fleet.controllersForTesting.isEmpty)
        XCTAssertTrue(fleet.controllersForTesting.allSatisfy { $0.model.accentColor == .blue })
    }

    func testFleetKeepsIndependentHandlesWhenControllersAreRecreated() throws {
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("Requires a display") }
        let fleet = NotchFleet(scope: .allDisplays, edge: .top)
        defer { fleet.stop() }
        for settings in [true, false] {
            for move in [true, false] {
                fleet.apply(showsSettingsHandle: settings)
                fleet.apply(showsMoveHandle: move)
                fleet.show()
                XCTAssertFalse(fleet.controllersForTesting.isEmpty)
                XCTAssertTrue(fleet.controllersForTesting.allSatisfy {
                    $0.model.showsSettingsHandle == settings && $0.model.showsMoveHandle == move
                })
                fleet.stop()
                fleet.show()
                XCTAssertTrue(fleet.controllersForTesting.allSatisfy {
                    $0.model.showsSettingsHandle == settings && $0.model.showsMoveHandle == move
                })
            }
        }
    }

    func testAppBindingUsesOnlyNotchAccentAndKeepsNewWindowsCurrent() throws {
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("Requires a display") }
        let preferences = Preferences(defaults: makeDefaults())
        preferences.accentColor = .blue
        preferences.notchAccentColor = .pink
        let fleet = NotchFleet(scope: .allDisplays, edge: .top)
        let binding = AppDelegate.bindNotchAccentColor(preferences, to: fleet)
        defer {
            binding.cancel()
            fleet.stop()
        }
        fleet.show()
        XCTAssertFalse(fleet.controllersForTesting.isEmpty)
        XCTAssertTrue(fleet.controllersForTesting.allSatisfy { $0.model.accentColor == .pink })

        preferences.accentColor = .green
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertTrue(fleet.controllersForTesting.allSatisfy { $0.model.accentColor == .pink })

        let updated = expectation(description: "All windows receive the notch colour")
        updated.expectedFulfillmentCount = fleet.controllersForTesting.count
        let observations = fleet.controllersForTesting.map { controller in
            controller.model.$accentColor.dropFirst().sink { colour in
                if colour == .purple { updated.fulfill() }
            }
        }
        defer { observations.forEach { $0.cancel() } }
        preferences.notchAccentColor = .purple
        wait(for: [updated], timeout: 1)
        XCTAssertEqual(preferences.accentColor, .green)
        XCTAssertTrue(fleet.controllersForTesting.allSatisfy { $0.model.accentColor == .purple })

        fleet.stop()
        preferences.notchAccentColor = .orange
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        fleet.show()
        XCTAssertFalse(fleet.controllersForTesting.isEmpty)
        XCTAssertTrue(fleet.controllersForTesting.allSatisfy { $0.model.accentColor == .orange })
    }
}

@MainActor
final class NotchTriggerPreferencesTests: XCTestCase {
    func testFleetAppliesHeightToExistingAndNewControllers() throws {
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("Requires a display") }
        let fleet = NotchFleet(scope: .mainDisplay, edge: .top)
        defer { fleet.stop() }
        fleet.apply(notchTriggerHeight: -2)
        fleet.show()
        XCTAssertFalse(fleet.controllersForTesting.isEmpty)
        XCTAssertTrue(fleet.controllersForTesting.allSatisfy { $0.model.notchTriggerHeight == -2 })
        fleet.apply(notchTriggerHeight: 0)
        XCTAssertTrue(fleet.controllersForTesting.allSatisfy { $0.model.notchTriggerHeight == 0 })
        fleet.stop()
        fleet.show()
        XCTAssertFalse(fleet.controllersForTesting.isEmpty)
        XCTAssertTrue(fleet.controllersForTesting.allSatisfy { $0.model.notchTriggerHeight == 0 })
    }

    func testDefaultAndSignedValuesSurviveReload() {
        let name = "NotchTriggerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = Preferences(defaults: defaults)
        XCTAssertEqual(preferences.notchTriggerHeight, 2)
        for value in [-20, -2, 0, 2, 20] {
            preferences.notchTriggerHeight = value
            XCTAssertEqual(Preferences(defaults: defaults).notchTriggerHeight, value)
        }
        for (value, expected) in [(-100, -20), (100, 20)] {
            preferences.notchTriggerHeight = value
            XCTAssertEqual(preferences.notchTriggerHeight, expected)
            XCTAssertEqual(Preferences(defaults: defaults).notchTriggerHeight, expected)
            defaults.set(value, forKey: "notchTriggerHeight")
            XCTAssertEqual(Preferences(defaults: defaults).notchTriggerHeight, expected)
        }
    }
}

/// The rename from UsageNotch to Codenotch moved every setting into a new,
/// empty defaults domain — the migration is the difference between a rename
/// and what looks like a reset, so it is pinned here. (Round-trip and
/// first-launch basics live with the other PreferencesTests.)
@MainActor
final class PreferencesMigrationTests: XCTestCase {
    func testHandleVisibilityPersistsIndependently() {
        let (fresh, _) = makeDefaults()
        let initial = Preferences(defaults: fresh)
        XCTAssertFalse(initial.showsSettingsHandle)
        XCTAssertFalse(initial.showsMoveHandle)
        for settings in [true, false] {
            for move in [true, false] {
                initial.showsSettingsHandle = settings
                initial.showsMoveHandle = move
                let restored = Preferences(defaults: fresh)
                XCTAssertEqual(restored.showsSettingsHandle, settings)
                XCTAssertEqual(restored.showsMoveHandle, move)
            }
        }
    }

    func testSavedQueryCatalogPreservesEnabledAccountsAndHiddenModels() {
        let (defaults, _) = makeDefaults()
        let preferences = Preferences(defaults: defaults)
        preferences.reconcile(discoveredIDs: ["claude", "codex", "kiro"])
        let model = "ollama-local:model:test"
        preferences.setConnected(false, for: model)
        var manual = QueryEntry()
        manual.id = "manual-account"
        manual.enabled = true
        var claude = QueryEntry()
        claude.id = "claude"
        claude.enabled = false
        preferences.reconcileCatalog([manual, claude])

        let restored = Preferences(defaults: defaults)
        restored.reconcile(discoveredIDs: ["claude", "codex", "kiro", "kimi"])
        XCTAssertTrue(restored.isConnected(manual.id))
        XCTAssertFalse(restored.isConnected("claude"))
        XCTAssertFalse(restored.isConnected("kiro"))
        XCTAssertFalse(restored.isConnected("kimi"))
        XCTAssertFalse(restored.isConnected(model))
    }

    func testCodexCompletionDefaultsToHooksAndPersistsLogOptIn() {
        let (defaults, _) = makeDefaults()
        let preferences = Preferences(defaults: defaults)
        XCTAssertFalse(preferences.codexRolloutCompletionEnabled)
        preferences.codexRolloutCompletionEnabled = true
        XCTAssertTrue(Preferences(defaults: defaults).codexRolloutCompletionEnabled)
        preferences.codexRolloutCompletionEnabled = false
        XCTAssertFalse(Preferences(defaults: defaults).codexRolloutCompletionEnabled)
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let name = "PreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (defaults, name)
    }

    private func setOldDomain(_ values: [String: Any], from name: String) {
        let old = UserDefaults(suiteName: name)!
        for (key, value) in values { old.set(value, forKey: key) }
        old.synchronize()
    }

    // MARK: Migration

    func testSettingsSurviveTheRename() {
        let (fresh, freshName) = makeDefaults()
        let oldName = "PreferencesTests.old.\(UUID().uuidString)"
        setOldDomain(["hiddenProviders": ["glm"], "notchVisibility": "alwaysShow"],
                     from: oldName)

        Preferences.migrateFromPreviousName(into: fresh, from: oldName)

        let preferences = Preferences(defaults: fresh)
        XCTAssertFalse(preferences.isConnected("glm"))
        XCTAssertTrue(preferences.isConnected("claude"))
        XCTAssertEqual(preferences.notchVisibility, .alwaysShow)
    }

    /// Once this copy has launched, nothing may be copied again: a stale old
    /// domain beside a live one must never overwrite newer choices.
    func testMigrationRunsOnce() {
        let (fresh, _) = makeDefaults()
        let oldName = "PreferencesTests.old.\(UUID().uuidString)"
        setOldDomain(["notchVisibility": "alwaysShow"], from: oldName)

        Preferences.migrateFromPreviousName(into: fresh, from: oldName)
        let preferences = Preferences(defaults: fresh)
        preferences.notchVisibility = .hidden

        Preferences.migrateFromPreviousName(into: fresh, from: oldName)
        XCTAssertEqual(preferences.notchVisibility, .hidden)
    }

    func testAnEmptyOldDomainMigratesNothing() {
        let (fresh, _) = makeDefaults()
        let oldName = "PreferencesTests.old.\(UUID().uuidString)"
        Preferences.migrateFromPreviousName(into: fresh, from: oldName)
        let preferences = Preferences(defaults: fresh)
        XCTAssertEqual(preferences.notchVisibility, .onHover)
    }

    // MARK: Defaults

    func testAFirstLaunchReadsTheDesignedDefaults() {
        let (fresh, _) = makeDefaults()
        let preferences = Preferences(defaults: fresh)
        XCTAssertTrue(preferences.isFirstLaunch)
        XCTAssertEqual(preferences.notchVisibility, .onHover)
        XCTAssertTrue(preferences.foldsForFullScreen)
        XCTAssertEqual(preferences.appPresence, .dock)
        XCTAssertEqual(preferences.notchEdge, .right)
        XCTAssertEqual(preferences.notchSize, .medium)
        XCTAssertEqual(preferences.weeklyRing, .off)
        XCTAssertTrue(preferences.isConnected("claude"))
        XCTAssertTrue(preferences.isConnected("codex"))
        XCTAssertTrue(preferences.isConnected("claude-work"))
        XCTAssertFalse(preferences.isConnected("cursor"))
        XCTAssertFalse(preferences.isConnected("glm"))
        XCTAssertFalse(preferences.isConnected("kiro"))
        XCTAssertTrue(preferences.deepSeekPricingEnabled)
        XCTAssertEqual(preferences.deepSeekPricingSchedule, .current)
    }

    /// Kiro is discovered like everyone else, and stays off until switched on.
    /// Claude and Codex are the only families that default on.
    func testKiroStaysOffAfterReconcile() {
        let (fresh, name) = makeDefaults()
        let preferences = Preferences(defaults: fresh)
        preferences.reconcile(discoveredIDs: ["claude", "codex", "kiro"])
        XCTAssertFalse(preferences.isConnected("kiro"))
        XCTAssertTrue(preferences.isConnected("claude"))

        let again = Preferences(defaults: UserDefaults(suiteName: name)!)
        again.reconcile(discoveredIDs: ["claude", "codex", "cursor", "glm", "kiro", "deepseek"])
        XCTAssertFalse(again.isConnected("kiro"))
        XCTAssertFalse(again.isConnected("cursor"))
        XCTAssertFalse(again.isConnected("deepseek"))
        XCTAssertTrue(again.isConnected("claude"))
    }

    func testAFirstLaunchSeedsClaudeAndCodexOnceDiscovered() {
        let (fresh, name) = makeDefaults()
        let preferences = Preferences(defaults: fresh)
        preferences.reconcile(discoveredIDs: ["claude", "codex", "cursor", "glm", "kiro", "claude-work"])
        XCTAssertEqual(preferences.connectedProviders, ["claude", "codex", "claude-work"])
        XCTAssertFalse(preferences.isConnected("cursor"))
        XCTAssertFalse(preferences.isConnected("kiro"))

        let again = Preferences(defaults: UserDefaults(suiteName: name)!)
        again.reconcile(discoveredIDs: ["claude", "codex", "cursor", "glm", "kiro", "claude-work", "deepseek"])
        XCTAssertFalse(again.isConnected("cursor"))
        XCTAssertFalse(again.isConnected("kiro"))
        XCTAssertFalse(again.isConnected("deepseek"))
        XCTAssertTrue(again.isConnected("claude"))
    }

    func testHiddenProvidersInvertAgainstWhatThisMacHas() {
        let (fresh, _) = makeDefaults()
        fresh.set(["glm", "cursor"], forKey: "hiddenProviders")
        let preferences = Preferences(defaults: fresh)
        XCTAssertFalse(preferences.isConnected("glm"))
        XCTAssertTrue(preferences.isConnected("claude"))
        preferences.reconcile(discoveredIDs: ["claude", "codex", "cursor", "glm"])
        XCTAssertEqual(preferences.connectedProviders, ["claude", "codex"])
        XCTAssertFalse(preferences.isConnected("cursor"))
        XCTAssertTrue(preferences.isConnected("claude"))
    }

    func testANewClaudeProfileTurnsOnWithoutReopeningCursor() {
        let (fresh, name) = makeDefaults()
        let preferences = Preferences(defaults: fresh)
        preferences.reconcile(discoveredIDs: ["claude", "codex", "cursor"])
        XCTAssertFalse(preferences.isConnected("cursor"))

        let later = Preferences(defaults: UserDefaults(suiteName: name)!)
        later.reconcile(discoveredIDs: ["claude", "codex", "cursor", "claude-work"])
        XCTAssertTrue(later.isConnected("claude-work"))
        XCTAssertFalse(later.isConnected("cursor"))
    }

    /// A 1.9 install with nothing hidden still shows each loaded model after
    /// the invert. Model cells are not providers: they are absent from the
    /// on-list, and absence there must not mean off.
    func testAnUpgradeDoesNotHideLoadedModels() {
        let (fresh, _) = makeDefaults()
        fresh.set([String](), forKey: "hiddenProviders")
        let preferences = Preferences(defaults: fresh)
        preferences.reconcile(discoveredIDs: ["claude", "codex", "ollama-local"])
        let model = "ollama-local:model:qwen3:8b"
        XCTAssertFalse(preferences.disconnectedIDs(among: [
            "claude", "codex", "ollama-local", model
        ]).contains(model))
        XCTAssertTrue(preferences.isConnected(model))
        XCTAssertTrue(preferences.isConnected("ollama-local"))
        XCTAssertTrue(preferences.disabledModels.isEmpty)
    }

    /// Model ids on the old off-list stay off. They are not inverted onto
    /// `connectedProviders`.
    func testAHiddenModelStaysHiddenAfterTheOnListInvert() {
        let (fresh, name) = makeDefaults()
        fresh.set(["glm", "ollama-local:model:qwen3"], forKey: "hiddenProviders")
        let preferences = Preferences(defaults: fresh)
        preferences.reconcile(discoveredIDs: ["claude", "codex", "glm", "ollama-local"])
        XCTAssertFalse(preferences.isConnected("glm"))
        XCTAssertTrue(preferences.isConnected("ollama-local"))
        XCTAssertFalse(preferences.isConnected("ollama-local:model:qwen3"))
        XCTAssertEqual(preferences.disabledModels, ["ollama-local:model:qwen3"])
        XCTAssertFalse(preferences.connectedProviders.contains { Preferences.isModelCell($0) })

        let again = Preferences(defaults: UserDefaults(suiteName: name)!)
        XCTAssertFalse(again.isConnected("ollama-local:model:qwen3"))
        XCTAssertTrue(again.isConnected("ollama-local"))
    }

    /// An invert that already wrote `connectedProviders` still left model ids
    /// on `hiddenProviders`. Those hides must not be forgotten.
    func testModelHidesSurviveAPreviousInvertThatDroppedThem() {
        let (fresh, _) = makeDefaults()
        fresh.set(["claude", "codex", "ollama-local"], forKey: "connectedProviders")
        fresh.set(["claude", "codex", "ollama-local"], forKey: "seenProviders")
        fresh.set(["ollama-local:model:qwen3"], forKey: "hiddenProviders")
        let preferences = Preferences(defaults: fresh)
        XCTAssertFalse(preferences.isConnected("ollama-local:model:qwen3"))
        XCTAssertTrue(preferences.isConnected("ollama-local"))
        XCTAssertEqual(preferences.disabledModels, ["ollama-local:model:qwen3"])
    }

    /// Recomputing the store off-list after a provider toggle must not hide
    /// models that nobody hid.
    func testSwitchingAProviderDoesNotHideLoadedModels() {
        let (fresh, _) = makeDefaults()
        let preferences = Preferences(defaults: fresh)
        preferences.reconcile(discoveredIDs: ["claude", "codex", "cursor", "ollama-local"])
        let model = "ollama-local:model:qwen3:8b"
        XCTAssertTrue(preferences.isConnected(model))
        preferences.setConnected(true, for: "cursor")
        XCTAssertTrue(preferences.isConnected(model))
        XCTAssertFalse(preferences.disconnectedIDs(among: [
            "claude", "codex", "cursor", "ollama-local", model
        ]).contains(model))
        XCTAssertTrue(preferences.disabledModels.isEmpty)
    }

    /// A newly loaded model is on until hidden, and hiding it does not put it
    /// on the provider on-list.
    func testALoadedModelStaysOffTheProviderOnList() {
        let (fresh, name) = makeDefaults()
        let preferences = Preferences(defaults: fresh)
        preferences.reconcile(discoveredIDs: ["claude", "codex", "ollama-local"])
        let model = "ollama-local:model:qwen3:8b"
        XCTAssertTrue(preferences.isConnected(model))
        preferences.setConnected(false, for: model)
        XCTAssertEqual(preferences.disabledModels, [model])
        XCTAssertFalse(preferences.connectedProviders.contains(model))
        XCTAssertFalse(preferences.seenProviders.contains(model))

        let hidden = Preferences(defaults: UserDefaults(suiteName: name)!)
        XCTAssertFalse(hidden.isConnected(model))
        hidden.setConnected(true, for: model)
        XCTAssertTrue(hidden.disabledModels.isEmpty)

        let shown = Preferences(defaults: UserDefaults(suiteName: name)!)
        XCTAssertTrue(shown.isConnected(model))
        XCTAssertFalse(shown.connectedProviders.contains(model))
    }

    func testDeepSeekPricingSettingsSurviveARelaunchAndCanBeReset() {
        let (fresh, name) = makeDefaults()
        let preferences = Preferences(defaults: fresh)
        preferences.deepSeekPricingEnabled = false
        preferences.deepSeekPricingSchedule = DeepSeekPricing.Schedule(
            peakWeekdays: [2],
            windows: [
                .init(startMinute: 120, endMinute: 180),
                .init(startMinute: 360, endMinute: 420),
                .init(startMinute: 900, endMinute: 960)
            ]
        )

        let reloaded = Preferences(defaults: UserDefaults(suiteName: name)!)
        XCTAssertFalse(reloaded.deepSeekPricingEnabled)
        XCTAssertEqual(reloaded.deepSeekPricingSchedule.peakWeekdays, [2])
        XCTAssertEqual(reloaded.deepSeekPricingSchedule.windows.count, 3)
        XCTAssertEqual(reloaded.deepSeekPricingSchedule.windows[2].startMinute, 900)

        reloaded.resetDeepSeekPricingSchedule()
        XCTAssertEqual(reloaded.deepSeekPricingSchedule, .current)
    }

    /// Off by default, and it has to stay chosen once it is chosen: an extra
    /// arc in a 44pt circle changes how every reading looks, so it is not
    /// something to switch on for somebody, nor to forget they switched on.
    func testTheWeeklyRingIsOffUntilAskedForAndThenSurvivesARelaunch() {
        let (fresh, name) = makeDefaults()
        XCTAssertEqual(Preferences(defaults: fresh).weeklyRing, .off)

        Preferences(defaults: fresh).weeklyRing = .outside

        XCTAssertEqual(Preferences(defaults: UserDefaults(suiteName: name)!).weeklyRing, .outside)
    }

    /// Keep the fork's hidden default and persist both explicit choices.
    func testTheMoveHandleStaysHiddenUntilEnabledAndPersistsBothChoices() {
        let (fresh, name) = makeDefaults()
        XCTAssertFalse(Preferences(defaults: fresh).showsMoveHandle)

        Preferences(defaults: fresh).showsMoveHandle = true
        XCTAssertTrue(Preferences(defaults: UserDefaults(suiteName: name)!).showsMoveHandle)

        Preferences(defaults: fresh).showsMoveHandle = false

        XCTAssertFalse(Preferences(defaults: UserDefaults(suiteName: name)!).showsMoveHandle)
    }

    /// The size has to outlive the launch that chose it, or it reads as a
    /// setting that did not take.
    func testTheNotchSizeSurvivesARelaunch() {
        let (fresh, name) = makeDefaults()
        Preferences(defaults: fresh).notchSize = .large

        XCTAssertEqual(Preferences(defaults: UserDefaults(suiteName: name)!).notchSize, .large)
    }

    /// An install that predates the setting keeps exactly the notch it had.
    /// `medium` is the design frame at 1:1, so this is what makes that true.
    func testMediumIsTheSizeEveryEarlierVersionDrew() {
        XCTAssertEqual(NotchSize.medium.scale, 1)
    }

    // MARK: The slider, and which control is in charge

    /// The presets stay in charge until the slider is explicitly chosen, so
    /// an install that predates it draws exactly the notch it always drew.
    func testThePresetsAreStillInChargeByDefault() {
        let (defaults, _) = makeDefaults()
        let preferences = Preferences(defaults: defaults)

        XCTAssertFalse(preferences.usesCustomNotchScale)
        XCTAssertEqual(preferences.notchScale, NotchSize.medium.scale)
    }

    /// Whichever control is in charge is the one `notchScale` answers with —
    /// that resolution is the whole point of keeping the two apart.
    func testTheScaleFollowsWhicheverControlIsInCharge() {
        let (defaults, _) = makeDefaults()
        let preferences = Preferences(defaults: defaults)
        preferences.notchSize = .large
        preferences.customNotchScale = 0.9

        XCTAssertEqual(preferences.notchScale, NotchSize.large.scale)
        preferences.usesCustomNotchScale = true
        XCTAssertEqual(preferences.notchScale, 0.9, accuracy: 0.0001)
    }

    /// Switching back to the presets returns to the preset that was chosen,
    /// not to whichever one happens to sit nearest the slider.
    func testLeavingTheSliderReturnsToTheChosenPreset() {
        let (defaults, _) = makeDefaults()
        let preferences = Preferences(defaults: defaults)
        preferences.notchSize = .small
        preferences.usesCustomNotchScale = true
        preferences.customNotchScale = 1.5
        preferences.usesCustomNotchScale = false

        XCTAssertEqual(preferences.notchScale, NotchSize.small.scale)
    }

    /// A value written straight into `defaults` could otherwise shrink the
    /// notch to nothing or blow it off the screen, so it is clamped on the
    /// way in as well as on the way out of the slider.
    func testAnOutOfRangeScaleIsClamped() {
        let (defaults, name) = makeDefaults()
        let preferences = Preferences(defaults: defaults)

        preferences.customNotchScale = 12
        XCTAssertEqual(preferences.customNotchScale,
                       Preferences.customScaleRange.upperBound, accuracy: 0.0001)

        preferences.customNotchScale = -3
        XCTAssertEqual(preferences.customNotchScale,
                       Preferences.customScaleRange.lowerBound, accuracy: 0.0001)

        UserDefaults(suiteName: name)!.set(99.0, forKey: "customNotchScale")
        XCTAssertEqual(Preferences(defaults: UserDefaults(suiteName: name)!).customNotchScale,
                       Preferences.customScaleRange.upperBound, accuracy: 0.0001)
    }

    /// Both halves of the choice have to outlive the launch that made it.
    func testTheSliderChoiceSurvivesARelaunch() {
        let (fresh, name) = makeDefaults()
        let preferences = Preferences(defaults: fresh)
        preferences.usesCustomNotchScale = true
        preferences.customNotchScale = 1.35

        let reloaded = Preferences(defaults: UserDefaults(suiteName: name)!)
        XCTAssertTrue(reloaded.usesCustomNotchScale)
        XCTAssertEqual(reloaded.customNotchScale, 1.35, accuracy: 0.0001)
        XCTAssertEqual(reloaded.notchScale, 1.35, accuracy: 0.0001)
    }
}

@MainActor
final class NotchPositionPersistenceTests: XCTestCase {
    func testEachEdgesPositionSurvivesReopeningPreferences() throws {
        let name = "NotchPositionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = Preferences(defaults: defaults)
        for (index, edge) in NotchEdge.allCases.enumerated() {
            preferences.setOffset(CGFloat(index * 150 - 225), for: edge)
        }
        let reopened = Preferences(defaults: defaults)
        for (index, edge) in NotchEdge.allCases.enumerated() {
            XCTAssertEqual(reopened.offset(for: edge), CGFloat(index * 150 - 225))
        }
    }
}
