/**
 @name: 原生费用隔离回归
 @Descripttion: 验证费用确认、账号映射、停用和计费设置持久化。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-10-09 17:00:00
 @LastEditTime: 2026-10-09 17:00:00
 @FilePath: Tests/NativeCostSyncTests.swift
 */
import Foundation
import Testing
@testable import Codenotch

@Suite @MainActor struct NativeCostSyncTests {
    private func entry(_ id: String, native: String, mode: QueryMode = .automatic) -> QueryEntry {
        var e = QueryEntry()
        e.id = id; e.nativeID = native; e.mode = mode; e.name = "Account " + id
        return e
    }

    @Test func confirmationIsPerAccountAndSurvivesRestartAlongsideCodeSwitch() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("accounts.json")
        let profiles = [ClaudeProfile.default(home: root),
                        ClaudeProfile(slug: "work", configDirectory: root.appendingPathComponent(".claude-work"))]
        let entries = [entry("local-personal", native: "claude"), entry("local-work", native: "claude-work"),
                       entry("manual", native: "claude", mode: .manual)]
        let store = CostAccountStore(storageURL: url)
        store.configure(entries: entries, claude: profiles, codex: [], disconnected: [], linkedMode: true)
        #expect(store.candidates.count == 2)
        #expect(store.accounts.isEmpty)
        #expect(store.nativeID(for: "manual") == nil)
        store.setNativeOnly(true, for: "claude-work")
        store.setMonthlyPrice("claude-work", 435)
        store.setBilling("claude-work", .api)
        #expect(store.accounts.map(\.id) == ["claude-work"])
        #expect(store.nativeID(for: "local-work") == "claude-work")
        let restored = CostAccountStore(storageURL: url)
        restored.configure(entries: entries, claude: profiles, codex: [], disconnected: [], linkedMode: true)
        #expect(restored.accounts.map(\.id) == ["claude-work"])
        #expect(restored.accounts.first?.monthlyPrice == 435)
        #expect(restored.accounts.first?.billing == .api)
        #expect(restored.accounts.first?.transcriptsRoot == profiles[1].configDirectory.appendingPathComponent("projects"))
        restored.setNativeOnly(false, for: "claude-work")
        #expect(restored.accounts.isEmpty)
    }

    @Test func disabledDeletedManualAndDisconnectedAccountsCannotEnterCosts() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let profile = CodexProfile.default(home: root)
        var e = entry("alias", native: "codex")
        let store = CostAccountStore()
        func configure(_ entries: [QueryEntry], disconnected: Set<String> = []) {
            store.configure(entries: entries, claude: [], codex: [profile], disconnected: disconnected, linkedMode: false)
        }
        configure([e]); store.setNativeOnly(true, for: "codex")
        #expect(store.accounts.count == 1)
        e.name = "Renamed"
        configure([e])
        #expect(store.accounts.first?.name == "Renamed")
        e.enabled = false; configure([e]); #expect(store.accounts.isEmpty)
        e.enabled = true; configure([e]); #expect(store.accounts.count == 1)
        configure([e], disconnected: [e.id]); #expect(store.accounts.isEmpty)
        e.mode = .manual; configure([e]); #expect(store.accounts.isEmpty)
        #expect(store.nativeID(for: e.id) == nil)
        configure([]); #expect(store.candidates.isEmpty)
    }

    @Test func aliasesForOneNativeAccountShareOneCostLedger() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = CostAccountStore()
        store.configure(entries: [entry("a", native: "claude"), entry("b", native: "claude")],
                        claude: [.default(home: root)], codex: [], disconnected: [], linkedMode: false)
        store.setNativeOnly(true, for: "claude")
        #expect(store.accounts.count == 1)
        #expect(store.nativeID(for: "a") == store.nativeID(for: "b"))
        #expect(store.nativeID(for: "linked-claude") == nil)
        store.setPlan("claude", tier: "pro")
        store.setMonthlyPrice("claude", 200)
        store.rediscover()
        #expect(store.isNativeOnly("claude"))
        #expect(store.accounts.first?.monthlyPrice == 200)
    }

    @Test func transcriptIndexIsIsolatedDeduplicatesStreamingAndStopsAfterRevocation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("first/projects/project")
        let second = root.appendingPathComponent("second/projects/project")
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        func line(_ request: String, output: Int) throws -> Data {
            let payload: [String: Any] = ["type": "assistant", "cwd": root.appendingPathComponent("code").path,
                "sessionId": "synthetic-session", "requestId": request, "timestamp": "2026-10-09T09:00:00Z",
                "message": ["model": "synthetic-model", "usage": ["input_tokens": 100, "output_tokens": output]]]
            return try JSONSerialization.data(withJSONObject: payload) + Data([10])
        }
        let file = first.appendingPathComponent("session.jsonl")
        try (line("same", output: 10) + line("same", output: 20)).write(to: file)
        try line("other-account", output: 900).write(to: second.appendingPathComponent("session.jsonl"))
        let store = try #require(CostStore(url: root.appendingPathComponent("test.sqlite")))
        let indexer = try #require(CostIndexer(store: store, root: first.deletingLastPathComponent()))
        defer { indexer.stop() }
        indexer.scan()
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while store.stats().events == 0 {
            try #require(ContinuousClock.now < deadline)
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(store.stats().events == 1)
        let pricer = Pricer(prices: [.init(model: "synthetic-model", input: 1_000_000,
                                         output: 1_000_000, cacheRead: 0, cacheWrite: 0)], rate: 1)
        #expect(store.projectCosts(from: 0, to: Int.max / 2, pricer: pricer).values.reduce(0, +) == 120)
        indexer.stop()
        try (line("same", output: 20) + line("after-revocation", output: 500)).write(to: file)
        indexer.scan()
        try await Task.sleep(for: .milliseconds(100))
        #expect(store.stats().events == 1)
    }
}
