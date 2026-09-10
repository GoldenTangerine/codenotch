/**
 @name: 联动设置与订阅回归
 @Descripttion: 验证全量协商、增量读取、撤销、隐藏持久化与兼容恢复。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-10 18:00:00
 @LastEditTime: 2026-09-10 18:00:00
 @FilePath: Tests/CodeSwitchIntegrationTests.swift
 */
import Foundation
import Testing
@testable import Codenotch

@Suite struct CodeSwitchIntegrationTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func fixture() throws -> CodeSwitchSnapshot {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/code-switch-session-routing.json")
        return try JSONDecoder().decode(CodeSwitchSnapshot.self, from: Data(contentsOf: url))
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write<T: Encodable>(_ value: T, _ url: URL) throws {
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
    }

    @Test func legacyUpgradeRevisionReuseAndModeReprojection() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("tray-snapshot-v1.json")
        let reader = CodeSwitchReader(file: file)
        let original = try fixture()
        try write(original, file)
        let legacy = await reader.read(now: now, mode: .enabled, generation: 1)
        #expect(legacy?.connection == .legacy)
        #expect(legacy?.snapshots.count == 1)
        let leaseURL = dir.appendingPathComponent("codenotch-subscription-v1.json")
        let lease = try JSONDecoder().decode(CodeSwitchSubscription.self, from: Data(contentsOf: leaseURL))
        let permissions = try FileManager.default.attributesOfItem(atPath: leaseURL.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)
        let source = original.platforms[0]
        let enabled = CodeSwitchProvider(providerId: "idle", providerName: "Idle", icon: "openai", activeRequests: 0,
                                         status: "enabled", loading: false, updatedAt: 0, quotas: [], stats: nil)
        let platforms = [CodeSwitchPlatform(platform: source.platform, name: source.name, icon: source.icon, error: false,
                                            providers: source.providers + [enabled], sessionBindings: source.sessionBindings)]
        try write(CodeSwitchProviderFile(version: 1, session: original.session, revision: 1, platforms: platforms),
                  dir.appendingPathComponent("codenotch-providers-v1.json"))
        var upgraded = original
        upgraded.codenotch = CodeSwitchIntegrationInfo(version: 1, mode: "enabled", consumerSession: lease.session, revision: 1, error: false)
        try write(upgraded, file)
        let full = await reader.read(now: now, mode: .enabled, generation: 1)
        #expect(full?.connection == .connected)
        #expect(full?.snapshots.count == 2)
        for _ in 0..<20 { _ = await reader.read(now: now, mode: .enabled, generation: 1) }
        #expect(await reader.mainDecodes == 2)
        #expect(await reader.providerDecodes == 1)
        let tray = await reader.read(now: now, mode: .tray, generation: 1)
        #expect(tray?.snapshots.count == 1)
        #expect(!FileManager.default.fileExists(atPath: leaseURL.path))
        await reader.reset(generation: 2)
        #expect(await reader.read(now: now, mode: .enabled, generation: 1) == nil)
        #expect(!FileManager.default.fileExists(atPath: leaseURL.path))
    }

    @Test func optionalExtensionsCannotBreakTrayCompatibility() async throws {
        let original = try fixture()
        let encoded = try JSONEncoder().encode(original)
        let base = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("tray-snapshot-v1.json")
        for value: Any in [NSNull(), ["version": 2], ["version": 1, "mode": false], "invalid"] {
            var payload = base
            payload["codenotch"] = value
            let data = try JSONSerialization.data(withJSONObject: payload)
            let decoded = try JSONDecoder().decode(CodeSwitchSnapshot.self, from: data)
            #expect(decoded.platforms == original.platforms)
            #expect(decoded.codenotch == nil)
            try data.write(to: file, options: .atomic)
            let reader = CodeSwitchReader(file: file)
            let fallback = await reader.read(now: now, mode: .enabled, generation: 1)
            #expect(fallback?.connection == .legacy)
            #expect(fallback?.snapshots.count == 1)
            await reader.reset(generation: 2)
        }
        var invalidBase = base
        invalidBase["platforms"] = "invalid"
        let data = try JSONSerialization.data(withJSONObject: invalidBase)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(CodeSwitchSnapshot.self, from: data) }
    }

    @Test func invalidRevisionAndCorruptionRecoverWithoutStaleFullData() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("tray-snapshot-v1.json")
        let sidecar = dir.appendingPathComponent("codenotch-providers-v1.json")
        let reader = CodeSwitchReader(file: file)
        _ = await reader.read(now: now, mode: .enabled, generation: 1)
        let leaseURL = dir.appendingPathComponent("codenotch-subscription-v1.json")
        let lease = try JSONDecoder().decode(CodeSwitchSubscription.self, from: Data(contentsOf: leaseURL))
        var source = try fixture()
        source.codenotch = CodeSwitchIntegrationInfo(version: 1, mode: "enabled", consumerSession: lease.session, revision: 2, error: false)
        try write(source, file)
        try write(CodeSwitchProviderFile(version: 1, session: "retired", revision: 2, platforms: []), sidecar)
        #expect(await reader.read(now: now, mode: .enabled, generation: 1)?.connection == .failed)
        try write(CodeSwitchProviderFile(version: 1, session: source.session, revision: 2, platforms: []), sidecar)
        let recovered = await reader.read(now: now, mode: .enabled, generation: 1)
        #expect(recovered?.connection == .connected)
        #expect(recovered?.snapshots.isEmpty == true)
        try Data("broken".utf8).write(to: file, options: .atomic)
        #expect(await reader.read(now: now.addingTimeInterval(4), mode: .enabled, generation: 1)?.snapshots.isEmpty == true)
        try FileManager.default.removeItem(at: file)
        #expect(await reader.read(now: now, mode: .enabled, generation: 1)?.connection == .waiting)
        await reader.reset(generation: 2)
        #expect(!FileManager.default.fileExists(atPath: leaseURL.path))
    }

    @Test func resetCannotRevokeNewGenerationAndForeignLeaseIsPreserved() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let reader = CodeSwitchReader(file: dir.appendingPathComponent("tray-snapshot-v1.json"))
        let lease = dir.appendingPathComponent("codenotch-subscription-v1.json")
        _ = await reader.read(now: now, mode: .enabled, generation: 2)
        await reader.reset(generation: 2)
        await reader.reset(generation: 1)
        #expect(FileManager.default.fileExists(atPath: lease.path))
        try write(CodeSwitchSubscription(version: 1, session: "another-instance", mode: "enabled", heartbeatAt: 0), lease)
        await reader.reset(generation: 3)
        #expect(FileManager.default.fileExists(atPath: lease.path))
    }

    @Test @MainActor func hideSurvivesRelaunchAndBlocksSessionReinsertion() throws {
        let domain = "codenotch.integration.tests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = Preferences(defaults: defaults, domainName: domain)
        #expect(preferences.codeSwitchDisplayMode == .tray)
        var state = CodeSwitchSnapshotState()
        state.accept(try fixture(), now: now)
        let supplier = try #require(state.snapshots.first)
        preferences.hiddenCodeSwitchProviders.insert(supplier.id)
        preferences.hiddenCodeSwitchNames[supplier.id] = supplier.displayName
        preferences.codeSwitchDisplayMode = .enabled
        let restored = Preferences(defaults: defaults, domainName: domain)
        #expect(restored.hiddenCodeSwitchProviders == [supplier.id])
        #expect(restored.hiddenCodeSwitchNames[supplier.id] == supplier.displayName)
        #expect(restored.codeSwitchDisplayMode == .enabled)
        let session = AgentSession(id: "one", name: "Test", detail: "Codex", state: .waiting, waitingFor: "answer", since: now,
                                   hookSessionKey: HookEvent.sessionKey(tool: "codex", id: "session-1"))
        let local = ProviderSnapshot(id: "local", displayName: supplier.displayName, glyph: .openai, fidelity: .derived,
                                     status: .ok, windows: [], headlineID: nil)
        let hidden = ActivityRouting(local: [local], linked: [], sources: [:], sessions: ["codex": [session]],
                                     bindings: state.bindings, hiddenLinked: restored.hiddenCodeSwitchProviders, now: now)
        #expect(hidden.snapshots.map(\.id) == ["local"])
        #expect(hidden.sessions.isEmpty)
        let visible = ActivityRouting(local: [], linked: [], sources: [:], sessions: ["codex": [session]],
                                      bindings: state.bindings, now: now)
        #expect(visible.snapshots.map(\.id) == [supplier.id])
        #expect(visible.unmatched.isEmpty)
    }

    @Test @MainActor func repeatedBridgeToggleRevokesLeaseAndClearsPublishedData() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("tray-snapshot-v1.json")
        try write(fixture(), file)
        let bridge = CodeSwitchBridge(file: file)
        bridge.configure(enabled: true, mode: .enabled)
        bridge.stop()
        for _ in 0..<10 { await Task.yield() }
        #expect(bridge.connection == .disabled)
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("codenotch-subscription-v1.json").path))
        for _ in 0..<20 {
            bridge.configure(enabled: true, mode: .enabled)
            await bridge.poll(now: now)
            await bridge.stopAndWait()
            #expect(bridge.snapshots.isEmpty)
            #expect(bridge.bindings.isEmpty)
            #expect(bridge.connection == .disabled)
            #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("codenotch-subscription-v1.json").path))
        }
    }
}
