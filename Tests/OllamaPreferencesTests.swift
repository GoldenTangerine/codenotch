/**
 @name: 上游同步回归测试
 @Descripttion: 维护 OllamaPreferencesTests.swift 的项目实现与上游兼容。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-11 15:51:14
 @LastEditTime: 2026-09-11 15:51:14
 @FilePath: Tests/OllamaPreferencesTests.swift
 */
import XCTest
@testable import Codenotch

@MainActor
final class OllamaPreferencesTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let suite = "OllamaPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    func testFreshAndUpstreamUsersKeepInventoryEnabledWithoutStartingRelay() {
        let store = defaults()
        let fresh = Preferences(defaults: store)
        XCTAssertTrue(fresh.isConnected("ollama-local"))
        XCTAssertFalse(fresh.ollamaMetricsEnabled)
        fresh.setConnected(false, for: "ollama-local")
        let next = Preferences(defaults: store)
        XCTAssertFalse(next.isConnected("ollama-local"))
        XCTAssertFalse(next.ollamaMetricsEnabled)
    }

    func testLegacyDisabledRuntimeAndHiddenModelsMigrateOnlyOnce() {
        let store = defaults()
        store.set(true, forKey: "introducedOllama")
        store.set(["cursor", "ollama", "ollama:model:qwen3"], forKey: "hiddenProviders")
        store.set(["ollama:model:qwen3", "codex", "ollama-local:model:qwen3", "ollama"], forKey: "providerOrder")
        store.set(["ollama", "claude"], forKey: "mutedAlertProviders")
        let preferences = Preferences(defaults: store)
        XCTAssertEqual(preferences.disconnectedProviders, ["cursor", "ollama-local", "ollama-local:model:qwen3"])
        XCTAssertEqual(preferences.providerOrder, ["ollama-local:model:qwen3", "codex", "ollama-local"])
        XCTAssertEqual(preferences.mutedAlertProviders, ["ollama-local", "claude"])
        XCTAssertFalse(preferences.ollamaMetricsEnabled)
        preferences.setConnected(true, for: "ollama-local")
        preferences.ollamaMetricsEnabled = false
        let next = Preferences(defaults: store)
        XCTAssertTrue(next.isConnected("ollama-local"))
        XCTAssertFalse(next.isConnected("ollama-local:model:qwen3"))
        XCTAssertFalse(next.ollamaMetricsEnabled)
    }

    func testLegacyEnabledRelayChoiceSurvivesAndCanonicalDisconnectionWins() {
        let store = defaults()
        store.set(true, forKey: "introducedOllama")
        XCTAssertTrue(Preferences(defaults: store).ollamaMetricsEnabled)
        store.set(["ollama-local"], forKey: "hiddenProviders")
        XCTAssertFalse(Preferences(defaults: store).ollamaMetricsEnabled)
    }

    func testUnrelatedOllamaIDIsNotRenamedWithoutLegacySentinel() {
        let store = defaults()
        store.set(["ollama"], forKey: "hiddenProviders")
        store.set(["ollama", "codex"], forKey: "providerOrder")
        let preferences = Preferences(defaults: store)
        XCTAssertEqual(preferences.disconnectedProviders, ["ollama"])
        XCTAssertEqual(preferences.providerOrder, ["ollama", "codex"])
        XCTAssertTrue(preferences.isConnected("ollama-local"))
    }
}
