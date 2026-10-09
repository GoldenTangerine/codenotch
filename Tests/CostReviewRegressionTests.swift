/**
 @name: 费用与端点评审回归
 @Descripttion: 使用隔离配置和合成会话验证端点历史、套餐匹配、计价及增量索引。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-10-09 11:25:22
 @LastEditTime: 2026-10-09 11:25:22
 @FilePath: Tests/CostReviewRegressionTests.swift
 */
import Foundation
import Testing
@testable import Codenotch

@Suite @MainActor struct CostReviewRegressionTests {
    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CostReview-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(6))
        while !condition() {
            try #require(ContinuousClock.now < deadline)
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func jsonLine(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) + Data([10])
    }

    private func append(_ data: Data, to file: URL) throws {
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    @Test func editingAddingAndRemovingOtherEndpointsPreservesAllSamples() throws {
        let suite = "CostReview.Endpoints." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)
        let a = CustomEndpoint(id: "a", name: "A", baseURL: "https://example.invalid/a")
        var b = CustomEndpoint(id: "b", name: "B", baseURL: "https://example.invalid/b")
        preferences.addCustomEndpoint(a)
        preferences.addCustomEndpoint(b)
        var sample = a
        sample.currentTokensUsedM = 3
        sample.usageHistory = [.init(day: "2026-10-08", totalTokens: 1), .init(day: "2026-10-09", totalTokens: 2)]
        Preferences.updateStoredCustomEndpoint(sample, defaults: defaults)
        b.name = "Renamed"
        preferences.updateCustomEndpoint(b)
        #expect(preferences.customEndpoints.first?.usageHistory == sample.usageHistory)
        #expect(Preferences.storedCustomEndpoints(defaults: defaults).first?.usageHistory == sample.usageHistory)
        sample.currentTokensUsedM = 4
        Preferences.updateStoredCustomEndpoint(sample, defaults: defaults)
        preferences.addCustomEndpoint(CustomEndpoint(id: "c", name: "C", baseURL: "https://example.invalid/c"))
        #expect(preferences.customEndpoints.first?.currentTokensUsedM == 4)
        sample.currentTokensUsedM = 5
        Preferences.updateStoredCustomEndpoint(sample, defaults: defaults)
        preferences.removeCustomEndpoint(id: "b")
        let reloaded = Preferences(defaults: defaults)
        #expect(reloaded.customEndpoints.map(\.id) == ["a", "c"])
        #expect(reloaded.customEndpoints.first?.currentTokensUsedM == 5)
        #expect(reloaded.customEndpoints.first?.usageHistory == sample.usageHistory)
    }

    @Test func endpointResetMappingChangesAndDisabledSourcesRejectStaleSamples() throws {
        let suite = "CostReview.EndpointReset." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)
        var a = CustomEndpoint(id: "a", name: "A", baseURL: "https://example.invalid/a")
        a.currentTokensUsedM = 1
        a.usageHistory = [.init(day: "2026-10-09", totalTokens: 1)]
        preferences.addCustomEndpoint(a)
        var sample = a
        sample.currentTokensUsedM = 2
        Preferences.updateStoredCustomEndpoint(sample, defaults: defaults)
        var reset = a
        reset.currentTokensUsedM = 0
        reset.usageHistory = []
        preferences.updateCustomEndpoint(reset)
        #expect(preferences.customEndpoints.first?.currentTokensUsedM == 0)
        #expect(preferences.customEndpoints.first?.usageHistory.isEmpty == true)
        reset.baseURL = "https://example.invalid/new"
        preferences.updateCustomEndpoint(reset)
        Preferences.updateStoredCustomEndpoint(sample, defaults: defaults)
        #expect(Preferences.storedCustomEndpoints(defaults: defaults).first?.currentTokensUsedM == 0)
        reset.isEnabled = false
        preferences.updateCustomEndpoint(reset)
        var disabledSample = reset
        disabledSample.currentTokensUsedM = 10
        Preferences.updateStoredCustomEndpoint(disabledSample, defaults: defaults)
        #expect(Preferences.storedCustomEndpoints(defaults: defaults).first?.currentTokensUsedM == 0)
        preferences.removeCustomEndpoint(id: "a")
        Preferences.updateStoredCustomEndpoint(disabledSample, defaults: defaults)
        #expect(Preferences.storedCustomEndpoints(defaults: defaults).isEmpty)
    }

    @Test func claudeAndCodexPlansUseTheirOwnCatalogPrices() throws {
        let catalogURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Resources/plans.json")
        let catalog = PlanCatalog(data: try Data(contentsOf: catalogURL))
        for (name, price) in [("Pro", 20.0), ("Team", 30.0), ("Max 5x", 100.0), ("Max 20x", 200.0)] {
            let key = PlanCatalog.key(for: "claude", plan: name)
            #expect(catalog.monthly(for: key, currency: "USD", rate: 1) == price)
        }
        #expect(PlanCatalog.key(for: "claude", plan: "default_claude_pro") == "default_claude_pro")
        #expect(catalog.usd(for: PlanCatalog.key(for: "codex", plan: "Pro")) == 200)
        #expect(catalog.usd(for: PlanCatalog.key(for: "claude", plan: "Max")) == nil)
        #expect(PlanCatalog.key(for: "claude", plan: "custom-contract") == "custom-contract")
    }

    @Test func detectedAndLegacyPlanNamesAreMappedOnSaveAndReload() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("accounts.json")
        try JSONSerialization.data(withJSONObject: ["claude": ["nativeOnly": true, "planTier": "Pro"]]).write(to: file)
        var entry = QueryEntry()
        entry.id = "alias"; entry.nativeID = "claude"; entry.mode = .automatic
        func configured() -> CostAccountStore {
            let store = CostAccountStore(storageURL: file)
            store.configure(entries: [entry], claude: [.default(home: root)], codex: [], disconnected: [], linkedMode: true)
            return store
        }
        let store = configured()
        #expect(store.account("claude")?.planTier == "default_claude_pro")
        store.setPlan("claude", tier: "Team")
        store.setMonthlyPrice("claude", 123)
        #expect(store.account("claude")?.planTier == "default_claude_team")
        #expect(configured().account("claude")?.planTier == "default_claude_team")
        #expect(configured().account("claude")?.monthlyPrice == 123)
    }

    @Test func openRouterPreservesOpenAIDecimalsAndMatchesSpecificModel() throws {
        let data = try JSONSerialization.data(withJSONObject: ["data": [
            ["id": "openai/gpt-5", "pricing": ["prompt": "0.000001", "completion": "0.000002"]],
            ["id": "openai/gpt-5.4", "pricing": ["prompt": "0.000003", "completion": "0.000006"]],
            ["id": "anthropic/claude-sonnet-4.6", "pricing": ["prompt": "0.000004", "completion": "0.000008"]]
        ]])
        let prices = PriceTable.parseOpenRouter(data)
        #expect(Set(prices.map(\.model)) == ["gpt-5", "gpt-5.4", "claude-sonnet-4-6"])
        let pricer = Pricer(prices: prices, rate: 1)
        #expect(pricer.local(model: "gpt-5.4-2026-10-09", input: 1_000_000, output: 1_000_000, cacheRead: 0, cacheWrite: 0) == 9)
        #expect(pricer.local(model: "claude-sonnet-4-6", input: 1_000_000, output: 0, cacheRead: 0, cacheWrite: 0) == 4)
    }

    private func tokenLine(second: Int) throws -> Data {
        try jsonLine(["timestamp": String(format: "2026-10-09T09:00:%02dZ", second), "type": "event_msg",
            "payload": ["type": "token_count", "info": ["last_token_usage": ["input_tokens": 100, "output_tokens": 20]]]])
    }

    @Test func codexRestartRecoversLatestConsumedModelBeyondFirstChunk() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("rollout.jsonl")
        let store = try #require(CostStore(url: root.appendingPathComponent("test.sqlite")))
        var data = try jsonLine(["type": "session_meta", "payload": ["id": "session", "cwd": root.path]])
        data += try jsonLine(["type": "turn_context", "payload": ["model": "gpt-5", "cwd": root.path]])
        data += try jsonLine(["type": "synthetic-padding", "padding": String(repeating: "x", count: 70_000)])
        data += try jsonLine(["type": "turn_context", "payload": ["model": "gpt-5.4", "cwd": root.path]])
        data += try tokenLine(second: 1)
        try data.write(to: file)
        let first = try #require(CostIndexer(store: store, root: root, format: .codex))
        first.scan()
        try await waitUntil { store.stats().events == 1 }
        first.stop()
        #expect(store.sessions(from: 0, to: Int.max / 2).first?.model == "gpt-5.4")
        var tail = try tokenLine(second: 2)
        tail += try jsonLine(["type": "turn_context", "payload": ["model": "gpt-5.5", "cwd": root.path]])
        tail += try tokenLine(second: 3)
        try append(tail, to: file)
        let resumed = try #require(CostIndexer(store: store, root: root, format: .codex))
        defer { resumed.stop() }
        resumed.scan()
        try await waitUntil { store.stats().events == 3 }
        let middle = Int(ISO8601DateFormatter().date(from: "2026-10-09T09:00:02Z")!.timeIntervalSince1970)
        #expect(store.sessions(from: middle, to: middle).first?.model == "gpt-5.4")
        #expect(store.sessions(from: middle + 1, to: middle + 1).first?.model == "gpt-5.5")
        #expect(store.sessions(from: 0, to: Int.max / 2).first?.models == ["gpt-5.4", "gpt-5.5"])
    }

    @Test func codexRotationClearsPreviousFilesModel() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("rollout.jsonl")
        let store = try #require(CostStore(url: root.appendingPathComponent("test.sqlite")))
        let indexer = try #require(CostIndexer(store: store, root: root, format: .codex))
        defer { indexer.stop() }
        var data = try jsonLine(["type": "session_meta", "payload": ["id": "old", "cwd": root.path]])
        data += try jsonLine(["type": "turn_context", "payload": ["model": "gpt-5.4"]])
        data += try tokenLine(second: 1)
        try data.write(to: file)
        indexer.scan()
        try await waitUntil { store.stats().events == 1 }
        let replacement = try jsonLine(["type": "session_meta", "payload": ["id": "new", "cwd": root.path]]) + tokenLine(second: 2)
        try replacement.write(to: file, options: .atomic)
        indexer.scan()
        try await waitUntil { store.stats().events == 2 }
        #expect(store.sessions(from: 0, to: Int.max / 2).first { $0.sessionID == "new" }?.model == "codex")
    }

    @Test func mixedModelSessionSumsEachCallsPriceAndHonorsDateRange() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try #require(CostStore(url: root.appendingPathComponent("test.sqlite")))
        let pricer = Pricer(prices: [
            .init(model: "haiku", input: 1, output: 5, cacheRead: 0.1, cacheWrite: 1.25),
            .init(model: "opus", input: 5, output: 25, cacheRead: 0.5, cacheWrite: 6.25)
        ], rate: 2)
        func event(_ model: String, at ts: Int) -> UsageEvent {
            UsageEvent(ts: ts, sessionId: "mixed", dedupeKey: "r:\(ts)", project: root.path, cwd: root.path,
                       branch: nil, model: model, input: 1_000_000, output: 1_000_000,
                       cacheRead: 1_000_000, cacheWrite: 1_000_000, ccVersion: nil)
        }
        store.commit(events: [event("haiku", at: 1), event("opus", at: 2)], path: "synthetic", inode: 1, size: 2, offset: 2, mtime: 0)
        let session = try #require(store.sessions(from: 1, to: 2, pricer: pricer).first)
        #expect(session.models == ["haiku", "opus"])
        #expect(abs(try #require(session.apiCost) - 88.2) < 0.000001)
        #expect(session.apiCost == store.projectCosts(from: 1, to: 2, pricer: pricer)[root.path])
        #expect(abs(try #require(store.sessions(from: 1, to: 1, pricer: pricer).first?.apiCost) - 14.7) < 0.000001)
        store.commit(events: [event("unknown", at: 3), event("haiku", at: 4)], path: "synthetic", inode: 1, size: 4, offset: 4, mtime: 0)
        #expect(store.sessions(from: 1, to: 4, pricer: pricer).first?.apiCost == nil)
        #expect(store.sessions(from: 3, to: 4, pricer: pricer).first?.apiCost == nil)
    }

    @Test(arguments: [false, true]) func missingDirectoryStartsIndexingAfterFirstSession(codex: Bool) async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appendingPathComponent(codex ? "sessions" : "projects")
        let store = try #require(CostStore(url: root.appendingPathComponent("test.sqlite")))
        let indexer = try #require(CostIndexer(store: store, root: sessions, format: codex ? .codex : .claude))
        defer { indexer.stop() }
        indexer.start()
        try await Task.sleep(for: .milliseconds(150))
        #expect(!FileManager.default.fileExists(atPath: sessions.path))
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let data: Data
        if codex {
            data = try jsonLine(["type": "session_meta", "payload": ["id": "session", "cwd": root.path]]) + tokenLine(second: 1)
        } else {
            data = try jsonLine(["type": "assistant", "cwd": root.path, "sessionId": "session", "requestId": "request",
                "timestamp": "2026-10-09T09:00:01Z", "message": ["model": "haiku", "usage": ["input_tokens": 100, "output_tokens": 20]]])
        }
        try data.write(to: sessions.appendingPathComponent("session.jsonl"))
        try await waitUntil { store.stats().events == 1 }
        #expect(store.sessions(from: 0, to: Int.max / 2).first?.tokens == 120)
    }

    @Test func stopBeforeDirectoryExistsCancelsRetry() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appendingPathComponent("sessions")
        let store = try #require(CostStore(url: root.appendingPathComponent("test.sqlite")))
        let indexer = try #require(CostIndexer(store: store, root: sessions, format: .codex))
        indexer.start()
        try await Task.sleep(for: .milliseconds(150))
        indexer.stop()
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try tokenLine(second: 1).write(to: sessions.appendingPathComponent("session.jsonl"))
        try await Task.sleep(for: .milliseconds(2200))
        #expect(store.stats().events == 0)
    }
}
