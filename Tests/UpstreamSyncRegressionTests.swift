/**
 @name: 上游同步兼容回归
 @Descripttion: 验证通知去重、模型偏好、多账户类型与日志缓存。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-14 12:00:00
 @LastEditTime: 2026-09-14 12:00:00
 @FilePath: Tests/UpstreamSyncRegressionTests.swift
 */
import Foundation
import Testing
import SQLite3
@testable import Codenotch

@Suite @MainActor struct UpstreamSyncRegressionTests {
    private func snapshot() -> ProviderSnapshot {
        ProviderSnapshot(id: "claude", displayName: "Claude", glyph: .claude,
            fidelity: .official, status: .ok,
            windows: [LimitWindow(id: "session", label: "Session", usedFraction: 0.8),
                      LimitWindow(id: "weekly_all", label: "Weekly", usedFraction: 0.1,
                                  resetsAt: Date().addingTimeInterval(3 * 86400))],
            headlineID: "session")
    }

    @Test func blockedNotificationsOnlyRepeatAfterRecovery() {
        var events: [UsageAlertEvent] = []
        let watcher = UsageLimitWatcher(deliver: { events.append($0) })
        var reading = snapshot()
        watcher.observe([reading])
        reading.block = UsageBlock(reason: "Blocked", resetsAt: nil)
        for _ in 0..<4 { watcher.observe([reading]) }
        #expect(events.count == 1)
        reading.block = nil
        watcher.observe([reading])
        reading.block = UsageBlock(reason: "Blocked again", resetsAt: nil)
        watcher.observe([reading])
        #expect(events.count == 2)
    }

    @Test func changingWindowEstablishesBaselineButRealResetNotifies() {
        var events: [UsageAlertEvent] = []
        let watcher = UsageResetWatcher(deliver: { events.append($0) })
        var reading = snapshot()
        watcher.observe([reading])
        reading.headlineID = "weekly_all"
        watcher.observe([reading])
        #expect(events.isEmpty)
        reading.headlineID = "session"
        watcher.observe([reading])
        #expect(events.isEmpty)
        reading.windows[0] = LimitWindow(id: "session", label: "Session", usedFraction: 0.1)
        watcher.observe([reading])
        #expect(events.count == 1)
    }

    @Test func switchingToExhaustedWindowDoesNotAnnounceANewLimit() {
        var events: [UsageAlertEvent] = []
        let watcher = UsageLimitWatcher(deliver: { events.append($0) })
        var reading = snapshot()
        watcher.observe([reading])
        reading.windows[1] = LimitWindow(id: "weekly_all", label: "Weekly", usedFraction: 1)
        reading.headlineID = "weekly_all"
        watcher.observe([reading])
        watcher.observe([reading])
        #expect(events.isEmpty)
    }

    @Test func hiddenModelSurvivesLaunchBeforeDiscovery() async {
        let suite = "SyncRegression.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = Preferences(defaults: defaults)
        let id = "ollama-local:model:qwen3:8b"
        prefs.setConnected(true, for: "ollama-local")
        prefs.setConnected(false, for: id)
        let restored = Preferences(defaults: defaults)
        let store = UsageStore(providers: [SyncRuntime()], archive: UsageArchive(defaults: defaults),
            disconnected: restored.disconnectedIDs(among: ["ollama-local"]))
        store.disconnected = restored.disconnectedIDs(among: store.knownIDs)
        await store.refresh()
        #expect(store.localModelSummaries.contains { $0.id == id })
        #expect(!store.notchSnapshots.contains { $0.id == id })
        restored.setConnected(true, for: id)
        store.disconnected = restored.disconnectedIDs(among: store.knownIDs)
        await store.refresh()
        #expect(store.notchSnapshots.contains { $0.id == id })
    }

    @Test func dailyPaceUsesNativeTypeWithoutChangingAccountIdentity() {
        var entry = QueryEntry()
        let provider = ConfiguredUsageProvider(entry: entry, automatic: nil, secrets: SyncSecrets())
        let reading = provider.decorate(snapshot())
        let paced = DailyPace.apply(to: reading, now: Date())
        #expect(paced.headlineID == DailyPace.windowID)
        #expect(paced.providerID == entry.id)
        entry.template = .custom
        let custom = ConfiguredUsageProvider(entry: entry, automatic: nil, secrets: SyncSecrets()).decorate(snapshot())
        #expect(DailyPace.apply(to: custom, now: Date()).headlineID != DailyPace.windowID)
    }

    @Test func webAccountEventsOnlyRefreshAutomaticCatalogEntries() async throws {
        let suite = "MiniMaxCatalogSync.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let secrets = SyncSecrets()
        let original = QueryCatalog(providers: [], disconnected: [], defaults: defaults, secrets: secrets)
        var manual = QueryEntry()
        manual.id = "manual-minimax"
        manual.nativeID = "minimax"
        manual.template = .custom
        manual.code = "return []"
        try original.save(manual, secrets: nil)

        let native = SyncRegionalMiniMax()
        let catalog = QueryCatalog(providers: [native], disconnected: [], defaults: defaults, secrets: secrets)
        #expect(catalog.entries.map(\.id) == ["manual-minimax"])
        #expect(catalog.automaticEntryIDs(for: "minimax").isEmpty)
        var automatic = QueryEntry()
        automatic.id = "linked-minimax"
        automatic.nativeID = "minimax"
        automatic.mode = .automatic
        try catalog.save(automatic, secrets: nil)

        let ids = catalog.automaticEntryIDs(for: "minimax")
        #expect(ids == ["linked-minimax"])
        var manualDeepSeek = QueryEntry()
        manualDeepSeek.id = "manual-deepseek"
        manualDeepSeek.nativeID = "deepseek"
        manualDeepSeek.template = .custom
        manualDeepSeek.code = "return []"
        try catalog.save(manualDeepSeek, secrets: nil)
        #expect(catalog.automaticEntryIDs(for: "deepseek").isEmpty)
        var automaticDeepSeek = QueryEntry()
        automaticDeepSeek.id = "linked-deepseek"
        automaticDeepSeek.nativeID = "deepseek"
        automaticDeepSeek.mode = .automatic
        try catalog.save(automaticDeepSeek, secrets: nil)
        #expect(catalog.automaticEntryIDs(for: "deepseek") == [automaticDeepSeek.id])
        let store = UsageStore(providers: catalog.providers(), archive: UsageArchive(defaults: defaults),
                               disconnected: ["manual-minimax", "manual-deepseek", "linked-deepseek"])
        defer { store.stop() }
        for id in ids { store.providerAuthenticationChanged(providerID: id) }
        await store.refresh(providerID: automatic.id)?.value
        #expect(await native.calls == 1)
        #expect(store.snapshots.map(\.id) == [automatic.id])
        #expect(store.snapshots.first?.hasReading == true)
    }

    @Test func miniMaxRegionChangeInvalidatesArchivedAndInFlightReadings() async throws {
        let suite = "MiniMaxRegionSync.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let archive = UsageArchive(defaults: defaults)
        let native = SyncRegionalMiniMax()
        let store = UsageStore(providers: [native], archive: archive)
        defer { store.stop() }
        await store.refresh(providerID: native.id)?.value
        #expect(store.snapshots.first?.windows.first?.id == "international")

        await native.slowNextFetch()
        let old = store.refresh(providerID: native.id)
        for _ in 0..<100 {
            if await native.calls == 2 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await native.calls == 2)
        store.invalidateUsageSource(providerID: native.id)
        #expect(store.snapshots.first?.hasReading == false)
        #expect(archive.load()[native.id] == nil)

        await native.changeRegion()
        await store.refresh(providerID: native.id)?.value
        await old?.value
        #expect(store.snapshots.first?.windows.first?.id == "china")
        store.stop()
        #expect(archive.load()[native.id]?.snapshot.windows.first?.id == "china")
    }

    @Test func miniMaxRegionChangeClearsNativeRateLimit() async {
        let suite = "MiniMaxRateLimitSync.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let archive = UsageArchive(defaults: defaults)
        archive.saveBackoffUntil(Date().addingTimeInterval(300), providerID: "minimax")
        let native = MiniMaxProvider(region: .china, archive: archive,
            loadAPIKey: { nil }, loadCookieHeader: { nil })
        do {
            _ = try await native.fetchSnapshot()
            Issue.record("the saved rate limit should block the first attempt")
        } catch UsageProviderError.rateLimited {} catch {
            Issue.record("unexpected error: \(error)")
        }
        await native.regionDidChange()
        #expect(archive.loadBackoffUntil(providerID: "minimax") == nil)
        do {
            _ = try await native.fetchSnapshot()
            Issue.record("a missing credential should still require sign-in")
        } catch UsageProviderError.needsAuth {} catch {
            Issue.record("old region backoff survived the switch: \(error)")
        }
    }

    @Test func rolloutCacheReusesNilAndInvalidatesAfterFileChanges() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("{}".utf8).write(to: url)
        let cache = CodexRolloutActivity.Cache()
        var reads = 0
        let read: (URL) -> CodexRolloutActivity.State? = { _ in reads += 1; return nil }
        #expect(cache.state(from: url, read: read) == nil)
        #expect(cache.state(from: url, read: read) == nil)
        #expect(reads == 1)
        try Data("{}\n{}".utf8).write(to: url)
        _ = cache.state(from: url, read: read)
        #expect(reads == 2)
    }

    @Test func rolloutCacheRefreshesCompletionWhenAnotherTurnStarts() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let completed = #"{"type":"event_msg","payload":{"type":"task_complete"}}"#
        try Data(completed.utf8).write(to: url)
        let cache = CodexRolloutActivity.Cache()
        #expect(cache.state(from: url) == .success)
        let started = #"{"type":"event_msg","payload":{"type":"task_started"}}"#
        try Data((completed + "\n" + started).utf8).write(to: url)
        #expect(cache.state(from: url) == .busy)
    }

    @Test func zeroVolumeDoesNotAttemptSoundPlayback() {
        #expect(!SessionChime.play("SyncRegressionNoSound", volume: 0))
    }

    @Test func stoppedCodexScanCannotPublishAfterRestart() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = directory.appendingPathComponent("desktop.sqlite")
        var db: OpaquePointer?
        #expect(sqlite3_open(store.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        let sql = """
        CREATE TABLE local_thread_catalog (thread_id TEXT, display_title TEXT, source_updated_at REAL);
        INSERT INTO local_thread_catalog VALUES ('test-thread', 'Fixture', \(Date().timeIntervalSince1970));
        """
        #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
        let absent = directory.appendingPathComponent("absent.sqlite")
        #expect(CodexActivityMonitor.read(stateStore: absent, desktopStore: store, staleAfter: 60).count == 1)
        let monitor = CodexActivityMonitor(stateStore: absent, desktopStore: store, interval: 60)
        monitor.start()
        monitor.stop()
        monitor.start()
        monitor.stop()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(monitor.sessions.isEmpty)
        monitor.start()
        defer { monitor.stop() }
        for _ in 0..<100 {
            if !monitor.sessions.isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(monitor.sessions.first?.nativeSessionKey == HookEvent.sessionKey(tool: "codex", id: "test-thread"))
    }
}

private struct SyncRuntime: UsageProvider {
    let id = "ollama-local"
    let displayName = "Ollama"
    let glyph = ProviderGlyph.ollamaLocal
    let kind = ProviderKind.localRuntime
    func fetchSnapshot() async throws -> ProviderSnapshot {
        ProviderSnapshot(id: id, displayName: displayName, glyph: glyph, fidelity: .official,
            status: .ok, windows: [], kind: kind,
            localRuntime: LocalRuntimeReading(models: [.init(name: "qwen3:8b", memoryBytes: nil,
                contextLength: nil, quantizationLevel: nil)]))
    }
}

private actor SyncRegionalMiniMax: UsageProvider {
    nonisolated let id = "minimax"
    nonisolated let displayName = "MiniMax"
    nonisolated let glyph = ProviderGlyph.minimax
    private(set) var calls = 0
    private var region = "international"
    private var slow = false

    func slowNextFetch() { slow = true }
    func changeRegion() { region = "china" }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        calls += 1
        let source = region
        if slow {
            slow = false
            try? await Task.sleep(for: .milliseconds(200))
        }
        return ProviderSnapshot(id: id, displayName: displayName, glyph: glyph,
            fidelity: .official, status: .ok,
            windows: [LimitWindow(id: source, label: source, usedFraction: 0.25)])
    }
}

private final class SyncSecrets: QuerySecretStorage {
    func load(_ reference: String) throws -> QuerySecrets { QuerySecrets() }
    func save(_ secrets: QuerySecrets, reference: String) throws {}
    func remove(_ reference: String) throws {}
}
