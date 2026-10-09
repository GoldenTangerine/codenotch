/**
 @name: 刷新升级兼容回归
 @Descripttion: 验证悬停和任务结束刷新遵守本地开关、限流及请求新鲜度。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-10-09 17:00:00
 @LastEditTime: 2026-10-09 17:00:00
 @FilePath: Tests/RefreshUpgradeTests.swift
 */
import Foundation
import Testing
@testable import Codenotch

@Suite @MainActor struct RefreshUpgradeTests {
    private func withStore(enabled: Bool = true, limited: Bool = false,
                           _ body: (UsageStore, RefreshUpgradeProbe) async throws -> Void) async throws {
        let suite = "RefreshUpgrade." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let probe = RefreshUpgradeProbe(limited: limited)
        var entry = QueryEntry()
        entry.id = "local-alias"; entry.nativeID = probe.id; entry.mode = .automatic
        entry.schedule.enabled = enabled
        let provider = ConfiguredUsageProvider(entry: entry, automatic: probe, secrets: RefreshUpgradeSecrets())
        let store = UsageStore(providers: [provider], archive: UsageArchive(defaults: defaults))
        defer { store.stop() }
        try await body(store, probe)
    }

    private func settle(_ store: UsageStore) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !store.refreshing.isEmpty {
            try #require(ContinuousClock.now < deadline)
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func automaticOffBlocksLookWorkAndScheduleButAllowsManualRefresh() async throws {
        try await withStore(enabled: false) { store, probe in
            store.refreshBecauseSomeoneIsLooking()
            store.refreshBecauseWorkFinished(providerID: "local-alias")
            store.refreshDue()
            try await Task.sleep(for: .milliseconds(30))
            #expect(await probe.readings.isEmpty)
            await store.refresh(providerID: "local-alias")?.value
            #expect(await probe.readings == [.fromSource])
        }
    }

    @Test func lookAndCompletionForwardFreshnessAndThrottleRepeatedEvents() async throws {
        try await withStore { store, probe in
            store.refreshBecauseSomeoneIsLooking()
            try await settle(store)
            store.refreshBecauseSomeoneIsLooking()
            #expect(await probe.readings == [.live])
            store.refreshBecauseWorkFinished(providerID: "local-alias")
            try await settle(store)
            store.refreshBecauseWorkFinished(providerID: "local-alias")
            #expect(await probe.readings == [.live, .live])
            store.refreshBecauseWorkFinished(providerID: "linked-claude")
            store.disconnected = ["local-alias"]
            store.refreshBecauseWorkFinished(providerID: "local-alias")
            #expect(await probe.readings.count == 2)
        }
    }

    @Test func optedInLookAsksSourceAndRateLimitBlocksAllRefreshEntrypoints() async throws {
        try await withStore(limited: true) { store, probe in
            store.asksProviderOnLook = { true }
            store.refreshBecauseSomeoneIsLooking()
            try await settle(store)
            #expect(await probe.readings == [.fromSource])
            #expect(store.snapshots.first?.queryRetryAfter != nil)
            store.refreshBecauseWorkFinished(providerID: "local-alias")
            store.refreshDue(now: Date().addingTimeInterval(600))
            await store.refresh(providerID: "local-alias")?.value
            #expect(await probe.readings.count == 1)
        }
    }

    @Test func endpointSamplesCannotUndoEditsOrResurrectDeletedEndpoints() throws {
        let suite = "EndpointSample." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)
        let original = CustomEndpoint(id: "sample", name: "Original", baseURL: "https://example.invalid/v1")
        preferences.addCustomEndpoint(original)
        var sample = original
        sample.currentTokensUsedM = 1
        sample.usageHistory = [.init(day: "2026-10-09", totalTokens: 1_000_000)]
        var renamed = original
        renamed.name = "Renamed"
        preferences.updateCustomEndpoint(renamed)
        Preferences.updateStoredCustomEndpoint(sample, defaults: defaults)
        #expect(Preferences.storedCustomEndpoints(defaults: defaults).first?.name == "Renamed")
        #expect(Preferences.storedCustomEndpoints(defaults: defaults).first?.currentTokensUsedM == 1)
        renamed.baseURL = "https://other.invalid/v1"
        preferences.updateCustomEndpoint(renamed)
        Preferences.updateStoredCustomEndpoint(sample, defaults: defaults)
        #expect(Preferences.storedCustomEndpoints(defaults: defaults).first?.baseURL == renamed.baseURL)
        #expect(Preferences.storedCustomEndpoints(defaults: defaults).first?.currentTokensUsedM == nil)
        preferences.removeCustomEndpoint(id: original.id)
        Preferences.updateStoredCustomEndpoint(sample, defaults: defaults)
        #expect(Preferences.storedCustomEndpoints(defaults: defaults).isEmpty)
    }
}

private actor RefreshUpgradeProbe: UsageProvider {
    nonisolated let id = "claude-synthetic"
    nonisolated let displayName = "Synthetic"
    nonisolated let glyph = ProviderGlyph.claude
    let limited: Bool
    var readings: [UsageFreshness] = []
    init(limited: Bool) { self.limited = limited }
    func fetchSnapshot() async throws -> ProviderSnapshot { try await fetchSnapshot(freshness: .standard) }
    func fetchSnapshot(freshness: UsageFreshness) async throws -> ProviderSnapshot {
        readings.append(freshness)
        if limited { throw UsageProviderError.rateLimited(retryAfter: 3600) }
        return ProviderSnapshot(id: id, displayName: displayName, glyph: glyph,
                                fidelity: .official, status: .ok, windows: [])
    }
}

private final class RefreshUpgradeSecrets: QuerySecretStorage {
    func load(_ reference: String) throws -> QuerySecrets { QuerySecrets() }
    func save(_ secrets: QuerySecrets, reference: String) throws {}
    func remove(_ reference: String) throws {}
}
