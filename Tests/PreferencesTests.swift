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
import XCTest
@testable import Codenotch

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
        XCTAssertEqual(preferences.disconnectedProviders, ["glm"])
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
        XCTAssertEqual(preferences.appPresence, .dock)
        XCTAssertEqual(preferences.notchEdge, .right)
    }
}
