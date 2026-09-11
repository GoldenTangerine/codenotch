/**
 @name: Code Switch 联动测试
 @Descripttion: 验证快照协议、离线隐藏、身份隔离与动态布局。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-08 17:08:00
 @LastEditTime: 2026-09-08 17:08:00
 @FilePath: Tests/CodeSwitchBridgeTests.swift
 */
import XCTest
@testable import Codenotch

@MainActor
final class CodeSwitchBridgeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_788_886_800)

    private func fixture(session: String = "one", sequence: UInt64 = 1, heartbeat: Date? = nil,
                         id: String = "42", version: Int = 1) throws -> CodeSwitchSnapshot {
        let json = #"{"providerId":"42","providerName":"Shared","icon":"openai","activeRequests":2,"status":"active","loading":false,"updatedAt":1788886800000,"quotas":[{"key":"daily","used":3,"total":10,"active":true,"displayKind":"progress","valueMode":"currency"},{"key":"balance","used":0,"total":12.34,"active":true,"displayKind":"balance","valueMode":"currency"}],"stats":null}"#
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        object["providerId"] = id
        let provider = try JSONDecoder().decode(CodeSwitchProvider.self, from: JSONSerialization.data(withJSONObject: object))
        return CodeSwitchSnapshot(version: version, session: session, sequence: sequence,
            heartbeatAt: (heartbeat ?? now).timeIntervalSince1970 * 1000,
            platforms: [CodeSwitchPlatform(platform: "codex", name: "Codex", icon: "openai", error: false, providers: [provider])])
    }

    func testQuotaAndBalanceMappingPreservesUnitsAndIdentity() throws {
        let source = try fixture()
        let provider = source.platforms[0].providers[0]
        let snapshot = provider.snapshot(platform: source.platforms[0])
        XCTAssertEqual(snapshot.windows[0].usedFraction, 0.3)
        XCTAssertEqual(snapshot.windows[0].quantity?.remaining, 7)
        XCTAssertNil(snapshot.windows[1].usedFraction)
        XCTAssertEqual(snapshot.windows[1].quantity?.remaining, 12.34)
        XCTAssertEqual(snapshot.windows[1].quantity?.unit, "USD")
        let other = CodeSwitchPlatform(platform: "claude", name: "Claude", icon: "claude", error: false, providers: [provider])
        XCTAssertNotEqual(snapshot.id, provider.snapshot(platform: other).id)
    }

    func testInactiveQuotaDoesNotBecomeHeadlineReading() throws {
        let raw = #"{"key":"five_hour","used":0,"total":10,"active":false,"displayKind":"progress"}"#
        let quota = try JSONDecoder().decode(CodeSwitchQuota.self, from: Data(raw.utf8))
        XCTAssertNil(quota.window)
    }

    func testBrandIconAliasesAndPathValidation() {
        XCTAssertEqual(CodeSwitchIcon.resourceKey("DeepSeek"), "deepseek-color")
        XCTAssertEqual(CodeSwitchIcon.resourceKey("kimi"), "kimi-color")
        XCTAssertEqual(CodeSwitchIcon.resourceKey("volcengine"), "doubao-color")
        XCTAssertNil(CodeSwitchIcon.resourceKey("../../secret"))
        XCTAssertNil(CodeSwitchIcon.resourceKey(""))
    }

    func testKimiAppearanceVariantsRemainColoredAndUseSeparateCacheEntries() throws {
        XCTAssertTrue(CodeSwitchIcon.isKimi("code-switch: KIMI "))
        XCTAssertFalse(CodeSwitchIcon.isKimi("kimi"))
        XCTAssertFalse(CodeSwitchIcon.isKimi("code-switch:openai"))
        let dark = try XCTUnwrap(CodeSwitchIcon.image("code-switch:kimi"))
        let light = try XCTUnwrap(CodeSwitchIcon.image("code-switch:kimi", useLightVariant: true))
        XCTAssertFalse(dark.isTemplate)
        XCTAssertFalse(light.isTemplate)
        XCTAssertFalse(dark === light)
        XCTAssertEqual(dark.size, light.size)
        XCTAssertTrue(dark === CodeSwitchIcon.image("code-switch:kimi"))
    }

    func testStalledHeartbeatHidesEvenWhenSameFileIsReadRepeatedly() throws {
        var state = CodeSwitchSnapshotState()
        let snapshot = try fixture()
        state.accept(snapshot, now: now)
        state.accept(snapshot, now: now.addingTimeInterval(2))
        XCTAssertEqual(state.snapshots.count, 1)
        state.accept(snapshot, now: now.addingTimeInterval(3.1))
        XCTAssertTrue(state.snapshots.isEmpty)
        state.accept(try fixture(sequence: 2, heartbeat: now.addingTimeInterval(4)), now: now.addingTimeInterval(4))
        XCTAssertEqual(state.snapshots.count, 1)
    }

    func testOldSessionAndOutOfOrderResultsCannotReplaceNewSupplier() throws {
        var state = CodeSwitchSnapshotState()
        state.accept(try fixture(sequence: 2), now: now)
        state.accept(try fixture(sequence: 1, id: "old"), now: now)
        XCTAssertTrue(state.snapshots[0].id.hasSuffix(":42"))
        state.accept(try fixture(session: "two", id: "new"), now: now)
        state.accept(try fixture(sequence: 99, id: "old"), now: now)
        XCTAssertTrue(state.snapshots[0].id.hasSuffix(":new"))
        state.accept(try fixture(session: "three", version: 2), now: now.addingTimeInterval(4))
        XCTAssertTrue(state.snapshots.isEmpty)
    }

    func testAtomicReplacementCorruptionAndDeletion() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("snapshot.json")
        let bridge = CodeSwitchBridge(file: file)
        defer { bridge.stop() }
        await bridge.poll(now: now)
        XCTAssertTrue(bridge.snapshots.isEmpty)
        try JSONEncoder().encode(fixture()).write(to: file, options: .atomic)
        await bridge.poll(now: now)
        XCTAssertEqual(bridge.snapshots.count, 1)
        try Data("broken".utf8).write(to: file, options: .atomic)
        await bridge.poll(now: now.addingTimeInterval(1))
        XCTAssertEqual(bridge.snapshots.count, 1)
        await bridge.poll(now: now.addingTimeInterval(4))
        XCTAssertTrue(bridge.snapshots.isEmpty)
        try JSONEncoder().encode(fixture(sequence: 2, heartbeat: now.addingTimeInterval(5))).write(to: file, options: .atomic)
        await bridge.poll(now: now.addingTimeInterval(5))
        XCTAssertEqual(bridge.snapshots.count, 1)
        try FileManager.default.removeItem(at: file)
        await bridge.poll(now: now.addingTimeInterval(5))
        XCTAssertTrue(bridge.snapshots.isEmpty)
    }

    func testOriginalProvidersStayFirstAndHoverFollowsIdentity() throws {
        let model = NotchViewModel()
        let local = ProviderSnapshot(id: "local", displayName: "Local", glyph: .claude, fidelity: .official, status: .ok, windows: [])
        let source = try fixture()
        let linked = source.platforms[0].providers[0].snapshot(platform: source.platforms[0])
        model.replaceSnapshots([local, linked])
        model.hoveredIndex = 1
        model.replaceSnapshots([local, localWithID("second"), linked])
        XCTAssertEqual(model.hoveredIndex, 2)
        XCTAssertEqual(model.snapshots.first?.id, "local")
        XCTAssertEqual(model.activity(for: linked.id)?.state, .working)
        model.replaceSnapshots([local])
        XCTAssertNil(model.hoveredIndex)
        XCTAssertEqual(model.visibleStart, 0)
    }

    private func localWithID(_ id: String) -> ProviderSnapshot {
        ProviderSnapshot(id: id, displayName: id, glyph: .claude, fidelity: .official, status: .ok, windows: [])
    }
}
