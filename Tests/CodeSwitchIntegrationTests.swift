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
import AppKit
import SwiftUI
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

    @Test func subscriptionUsesIntegerMillisecondsAtFractionalClockTime() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("tray-snapshot-v1.json")
        let reader = CodeSwitchReader(file: file)
        let fractionalNow = now.addingTimeInterval(0.000125)
        _ = await reader.read(now: fractionalNow, mode: .enabled, generation: 1)
        // Go's original int64 decoder rejects fractional JSON numbers.
        struct IntegerLease: Decodable { let heartbeatAt: Int64 }
        let data = try Data(contentsOf: dir.appendingPathComponent("codenotch-subscription-v1.json"))
        let lease = try JSONDecoder().decode(IntegerLease.self, from: data)
        #expect(lease.heartbeatAt == Int64((fractionalNow.timeIntervalSince1970 * 1000).rounded(.down)))
        await reader.reset(generation: 2)
    }

    @Test func settingsTableKeepsSupplierIdentityAndOfflineHiddenEntries() throws {
        var state = CodeSwitchSnapshotState()
        state.accept(try fixture(), now: now)
        let live = try #require(state.snapshots.first)
        let platform = "custom:工具"
        let offlineID = "code-switch:\(platform.utf8.count):\(platform):ref:offline"
        let rows = CodeSwitchSettingsRow.rows(snapshots: state.snapshots + state.snapshots,
            bindings: state.bindings, hidden: [live.id, offlineID], names: [offlineID: live.displayName], search: "")
        #expect(Set(rows.map(\.id)).count == rows.count)
        #expect(rows.first(where: { $0.id == live.id })?.snapshot == live)
        let offline = try #require(rows.first(where: { $0.id == offlineID }))
        #expect(offline.snapshot == nil)
        #expect(offline.reference == "ref:offline")
        #expect(offline.savedName == live.displayName)
        let searched = CodeSwitchSettingsRow.rows(snapshots: state.snapshots, bindings: state.bindings,
            hidden: [offlineID], names: [offlineID: live.displayName], search: "  REF:OFFLINE  ")
        #expect(searched.map(\.id) == [offlineID])
        let platformSearch = CodeSwitchSettingsRow.rows(snapshots: state.snapshots, bindings: [:], hidden: [], names: [:], search: "codex")
        #expect(platformSearch.map(\.id) == state.snapshots.map(\.id))
        let noMatch = CodeSwitchSettingsRow.rows(snapshots: state.snapshots, bindings: state.bindings,
            hidden: [], names: [:], search: "nonexistent-fixture")
        #expect(noMatch.isEmpty)
    }

    @Test func settingsMetricsMatchUpstreamAndDistinguishMissingFromZero() {
        let absent = CodeSwitchTableMetrics(stats: nil)
        #expect([absent.success, absent.requests, absent.tokens, absent.cost, absent.firstToken, absent.speed].allSatisfy { $0 == "—" })
        let stats = CodeSwitchStats(totalRequests: 10, successfulRequests: 8, failedRequests: 2, successRate: 0.8,
                                   inputTokens: 100, outputTokens: 200, cacheReadTokens: 300,
                                   costTotal: 0.0012, avgFirstTokenSec: 0.263, avgTokensPerSec: 29.8)
        let values = CodeSwitchTableMetrics(stats: stats)
        #expect(values.success == "80%")
        #expect(values.requests == "10")
        #expect(values.tokens == "600")
        #expect(values.firstToken == "263 ms")
        #expect(values.speed == QuotaQuantity.format(29.8) + " t/s")
        #expect(values.cost == 0.0012.formatted(.currency(code: "USD").precision(.fractionLength(2...4))))
        let zero = CodeSwitchTableMetrics(stats: CodeSwitchStats(totalRequests: 0, successfulRequests: 0, failedRequests: 0,
            successRate: 0, inputTokens: 0, outputTokens: 0, cacheReadTokens: 0, costTotal: 0, avgFirstTokenSec: 0, avgTokensPerSec: 0))
        #expect(zero.success == "—")
        #expect(zero.requests == "0")
        #expect(zero.tokens == "0")
        #expect(zero.cost != "—")
        #expect(zero.firstToken == "—")
        #expect(zero.speed == "—")
    }

    @Test func settingsValuesHighlightNumbersWithoutChangingCopyOrUnits() {
        let samples: [(String, String)] = [
            ("US$31.4026", "31.4026"), ("1.234,56 US$", "1.234,56"),
            ("6.22 s", "6.22"), ("9.24 t/s", "9.24"), ("23.35M", "23.35"),
            ("0.00", "0.00"), ("4 天 6 小时后重置", "46"),
            ("Resets Thu 12:05 PM", "1205"), ("١٢٫٥ USD", "١٢٫٥")
        ]
        for (copy, numbers) in samples {
            let styled = CodeSwitchTableText.attributed(copy)
            #expect(String(styled.characters) == copy)
            let highlighted = styled.runs.filter { $0.foregroundColor == CodeSwitchTableText.valueColor }
                .map { String(styled[$0.range].characters) }.joined()
            #expect(highlighted == numbers)
            for run in styled.runs where run.foregroundColor != CodeSwitchTableText.valueColor {
                #expect(run.foregroundColor == Color.secondary)
                #expect(run.font == Font.caption)
            }
        }
    }

    @Test func settingsMissingAndUnlimitedReadingsStaySecondary() {
        let readings = ["—", QuotaQuantity().summary, QuotaQuantity(unlimited: true).summary,
                        "No reading", "Unlimited", "Resetting…", "额度暂不可用"]
        for reading in readings {
            let styled = CodeSwitchTableText.attributed(reading)
            #expect(String(styled.characters) == reading)
            #expect(styled.runs.allSatisfy { $0.foregroundColor == Color.secondary && $0.font == Font.caption })
        }
        let zero = CodeSwitchTableText.attributed(QuotaQuantity(remaining: 0, unit: "USD").summary)
        #expect(zero.runs.contains { $0.foregroundColor == CodeSwitchTableText.valueColor })
    }

    @Test func settingsQuotaEmphasisKeepsPercentUnitSecondary() {
        for band in [UsageBand.ample, .watch, .critical, .exhausted] {
            let color = CodeSwitchTableText.quotaColor(band)
            let styled = CodeSwitchTableText.attributed("100.37%", color: color)
            #expect(styled.runs.contains {
                String(styled[$0.range].characters) == "100.37" && $0.foregroundColor == color
            })
            #expect(styled.runs.contains {
                String(styled[$0.range].characters) == "%" && $0.foregroundColor == Color.secondary
            })
        }
    }

    @Test @MainActor func settingsValueColorsStayReadableOnLightAndDarkSurfaces() throws {
        let surfaces: [(NSAppearance.Name, Double)] = [(.aqua, 0.8), (.darkAqua, 0.2)]
        func linear(_ component: Double) -> Double {
            component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        for (name, background) in surfaces {
            let appearance = try #require(NSAppearance(named: name))
            appearance.performAsCurrentDrawingAppearance {
                for band in [UsageBand.ample, .watch, .critical, .exhausted] {
                    let color = NSColor(CodeSwitchTableText.quotaColor(band)).usingColorSpace(.sRGB)!
                    let foreground = 0.2126 * linear(color.redComponent)
                        + 0.7152 * linear(color.greenComponent) + 0.0722 * linear(color.blueComponent)
                    let surface = linear(background)
                    let contrast = (max(foreground, surface) + 0.05) / (min(foreground, surface) + 0.05)
                    #expect(contrast >= 4.5)
                }
            }
        }
    }

    private func tableQuota(_ key: String, used: Double = 25, active: Bool = true,
                            kind: String = "progress", unlimited: Bool = false) -> CodeSwitchQuota {
        CodeSwitchQuota(key: key, label: nil, used: used, total: 100, unlimited: unlimited,
            nextReset: "2027-01-16T12:00:00Z", active: active, valueMode: "count", unit: "",
            extra: nil, invalidMessage: nil, displayKind: kind)
    }

    private func tableProvider(_ quotas: [CodeSwitchQuota]) -> CodeSwitchProvider {
        CodeSwitchProvider(providerId: "42", providerName: "GLM Coding Plan · 联动供应商", icon: "openai",
            activeRequests: 0, status: "enabled", loading: false, updatedAt: now.timeIntervalSince1970 * 1000,
            quotas: quotas, stats: CodeSwitchStats(totalRequests: 10, successfulRequests: 8, failedRequests: 2,
                successRate: 0.8, inputTokens: 100, outputTokens: 200, cacheReadTokens: 300,
                costTotal: 0.0012, avgFirstTokenSec: 0.263, avgTokensPerSec: 29.8))
    }

    @Test func displayScopesKeepUnknownAndUseAnyExhaustedQuota() throws {
        let platform = try fixture().platforms[0]
        let available = tableProvider([tableQuota("daily")]).snapshot(platform: platform)
        var provider = tableProvider([tableQuota("daily"), tableQuota("weekly", used: 100)])
        let exhausted = provider.snapshot(platform: platform)
        let unknown = tableProvider([]).snapshot(platform: platform)
        let tray: Set<String> = [available.id]
        #expect(CodeSwitchDisplayMode.enabled.includes(exhausted, trayIDs: []))
        #expect(CodeSwitchDisplayMode.available.includes(unknown, trayIDs: []))
        #expect(CodeSwitchDisplayMode.available.includes(available, trayIDs: []))
        #expect(!CodeSwitchDisplayMode.available.includes(exhausted, trayIDs: []))
        #expect(CodeSwitchDisplayMode.exhausted.includes(exhausted, trayIDs: []))
        #expect(!CodeSwitchDisplayMode.exhausted.includes(unknown, trayIDs: []))
        #expect(CodeSwitchDisplayMode.tray.includes(available, trayIDs: tray))
        #expect(!CodeSwitchDisplayMode.tray.includes(available, trayIDs: []))
        #expect(!CodeSwitchDisplayMode.active.includes(available, trayIDs: []))
        let active = CodeSwitchProvider(providerId: "active", providerName: "Active", icon: "openai",
            activeRequests: 1, status: "active", loading: true, updatedAt: 0, quotas: [], stats: nil)
        #expect(CodeSwitchDisplayMode.active.includes(active.snapshot(platform: platform), trayIDs: []))
        provider.quotaState = "unknown"
        #expect(provider.effectiveQuotaState == "unknown")
        provider.quotaAutoDisabled = true
        #expect(provider.effectiveQuotaState == "exhausted")
        #expect(CodeSwitchDisplayMode(rawValue: "enabled") == .enabled)
        #expect(CodeSwitchDisplayMode(rawValue: "tray") == .tray)
    }

    @Test func zeroInactiveBalanceAndInvalidQuotaCompatibility() {
        let zero = CodeSwitchQuota(key: "balance", label: nil, used: 0, total: 0, unlimited: false,
            nextReset: nil, active: false, valueMode: "currency", unit: "USD", extra: nil,
            invalidMessage: nil, displayKind: "balance")
        #expect(tableProvider([zero]).effectiveQuotaState == "exhausted")
        #expect(tableProvider([tableQuota("daily", used: 100, unlimited: true)]).effectiveQuotaState == "available")
        #expect(tableProvider([tableQuota("daily", used: 100, kind: "error")]).effectiveQuotaState == "unknown")
    }

    @Test func settingsTableDoesNotPresentSessionCacheAsCurrentData() throws {
        let source = try fixture()
        let platform = source.platforms[0]
        let provider = tableProvider([tableQuota("daily")])
        func snapshot(_ time: Date, _ sequence: UInt64, _ providers: [CodeSwitchProvider]) -> CodeSwitchSnapshot {
            CodeSwitchSnapshot(version: 1, session: source.session, sequence: sequence,
                heartbeatAt: time.timeIntervalSince1970 * 1000, platforms: [CodeSwitchPlatform(
                    platform: platform.platform, name: platform.name, icon: platform.icon,
                    error: false, providers: providers, sessionBindings: platform.sessionBindings)])
        }
        var state = CodeSwitchSnapshotState()
        state.accept(snapshot(now, 1, [provider]), now: now)
        let id = try #require(state.snapshots.first?.id)
        func row() throws -> CodeSwitchSettingsRow {
            try #require(CodeSwitchSettingsRow.rows(snapshots: state.snapshots, bindings: state.bindings,
                hidden: [id], names: [id: "Saved supplier"], search: "").first)
        }
        #expect(try row().currentSnapshot?.linked?.provider.stats?.totalRequests == 10)
        let later = now.addingTimeInterval(23 * 3600)
        state.accept(snapshot(later, 2, []), now: later)
        let sessionOnly = try row()
        #expect(state.snapshots.isEmpty)
        #expect(sessionOnly.snapshot?.linked?.provider.stats?.totalRequests == 10)
        #expect(sessionOnly.snapshot?.windows.isEmpty == false)
        #expect(!sessionOnly.isCurrent)
        #expect(sessionOnly.currentSnapshot == nil)
        #expect(sessionOnly.reference == "42")
        #expect(sessionOnly.savedName.contains(platform.name))
        state.accept(snapshot(later, 3, [provider]), now: later)
        #expect(try row().currentSnapshot?.windows.count == 1)
        state.expire(now: later, missing: true)
        #expect(try row().currentSnapshot == nil)
        #expect(try row().savedName == "Saved supplier")
    }

    @Test func settingsQuotasPreserveWindowAlignmentAndWarningPriority() throws {
        let quotas = [tableQuota("daily", active: false), tableQuota("daily", used: 50),
                      tableQuota("weekly", used: 95), tableQuota("balance", kind: "balance"),
                      tableQuota("total", unlimited: true), tableQuota("broken", kind: "error")]
        let snapshot = tableProvider(quotas).snapshot(platform: try fixture().platforms[0])
        let items = CodeSwitchTableQuota.items(snapshot)
        #expect(items.count == quotas.count)
        #expect(items[0].window == nil)
        #expect(items[1].window?.usedFraction == 0.5)
        #expect(items[1].band == .watch)
        #expect(items[2].band == .critical)
        #expect(items[3].window?.quantity?.remaining == 75)
        #expect(items[4].window?.quantity?.unlimited == true)
        #expect(items[5].window == nil)
        #expect(items.compactMap(\.window) == snapshot.windows)
        #expect(items.max(by: { $0.priority < $1.priority })?.quota.key == "broken")
        #expect(items.dropLast().max(by: { $0.priority < $1.priority })?.quota.key == "weekly")
    }

    @Test @MainActor func settingsProviderDetailsKeepSummaryRowsCompact() throws {
        _ = NSApplication.shared
        let snapshot = tableProvider([tableQuota("five_hour"), tableQuota("weekly", used: 95), tableQuota("monthly")])
            .snapshot(platform: try fixture().platforms[0])
        let row = try #require(CodeSwitchSettingsRow.rows(snapshots: [snapshot], bindings: [:], hidden: [], names: [:], search: "").first)
        let domain = "codenotch.row.render." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = Preferences(defaults: defaults, domainName: domain)
        for width in [444.0, 640.0, 900.0] {
            func height(expanded: Bool) -> CGFloat {
                let host = NSHostingView(rootView: CodeSwitchSettingsProviderRow(row: row, width: width,
                    preferences: preferences, duplicate: false, canReorder: true,
                    drag: CodeSwitchProviderDrag(), acceptDrop: { _, _ in false }, expanded: expanded)
                    .fixedSize(horizontal: false, vertical: true))
                host.layoutSubtreeIfNeeded()
                return host.fittingSize.height
            }
            let collapsed = height(expanded: false)
            let expanded = height(expanded: true)
            #expect(collapsed > 0 && collapsed < 110)
            #expect(expanded > collapsed + 80)
        }
    }

    @Test @MainActor func settingsOrderPersistsAndPreservesAbsentSlots() throws {
        let domain = "codenotch.order." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let ids = ["a", "offline", "b", "new"].map { "code-switch:5:codex:" + $0 }
        defaults.set([ids[0], ids[1], ids[2], ids[0], "local"], forKey: "codeSwitchProviderOrder")
        let preferences = Preferences(defaults: defaults, domainName: domain)
        preferences.hiddenCodeSwitchProviders = [ids[2]]
        #expect(preferences.codeSwitchProviderOrder == Array(ids.prefix(3)))
        #expect(preferences.moveCodeSwitchProvider(ids[3], onto: ids[0], placement: .before, visible: [ids[0], ids[2], ids[3]]))
        let restored = Preferences(defaults: defaults, domainName: domain)
        #expect(restored.codeSwitchProviderOrder == [ids[3], ids[1], ids[0], ids[2]])
        #expect(restored.hiddenCodeSwitchProviders == [ids[2]])
        let names = Dictionary(uniqueKeysWithValues: ids.map { ($0, $0) })
        let rows = CodeSwitchSettingsRow.rows(snapshots: [], bindings: [:], hidden: Set(ids), names: names,
                                              search: "", order: restored.codeSwitchProviderOrder)
        #expect(rows.map(\.id) == restored.codeSwitchProviderOrder)
        #expect(!restored.moveCodeSwitchProvider("missing", onto: ids[0], placement: .before, visible: ids))
        #expect(!restored.moveCodeSwitchProvider(ids[0], onto: ids[0], placement: .before, visible: ids))
        #expect(restored.codeSwitchProviderOrder == preferences.codeSwitchProviderOrder)
    }

    @Test @MainActor func settingsDragRejectsForeignAndCancelledPayloads() {
        let drag = CodeSwitchProviderDrag()
        let first = drag.begin("code-switch:5:codex:1")
        #expect(!drag.accepts(["foreign"], target: "other"))
        #expect(!drag.accepts([first], target: "code-switch:5:codex:1"))
        #expect(drag.takeSource(["foreign"]) == nil)
        #expect(drag.isActive)
        #expect(drag.takeSource([first]) == "code-switch:5:codex:1")
        let cancelled = drag.begin("code-switch:5:codex:1")
        drag.update(.ended(.cancel), items: [cancelled])
        #expect(!drag.isActive)
        #expect(drag.takeSource([cancelled]) == nil)
        let rejected = drag.begin("code-switch:5:codex:1")
        drag.update(.ended(.forbidden), items: [rejected])
        #expect(!drag.isActive)
        #expect(drag.takeSource([rejected]) == nil)
        let token = drag.begin("code-switch:5:codex:2")
        drag.update(.dataTransferCompleted, items: [cancelled])
        #expect(drag.accepts([token], target: "other"))
        drag.update(.ended(.move), items: [token])
        #expect(!drag.isActive)
        #expect(drag.takeSource([token]) == "code-switch:5:codex:2")
        #expect(drag.takeSource([token]) == nil)
        let completed = drag.begin("code-switch:5:codex:2")
        drag.update(.ended(.move), items: [completed])
        drag.update(.dataTransferCompleted, items: [completed])
        #expect(drag.takeSource([completed]) == nil)
    }

    @Test func insertionFeedbackMatchesMovesInBothDirections() {
        let ids = ["a", "b", "c", "d"].map { "code-switch:5:codex:" + $0 }
        func move(_ source: Int, _ target: Int, y: CGFloat) -> [String]? {
            CodeSwitchProviderOrder.moving(ids[source], onto: ids[target],
                placement: .at(y: y, height: 100), visible: ids, remembered: [])
        }
        #expect(move(0, 2, y: 25) == [ids[1], ids[0], ids[2], ids[3]])
        #expect(move(0, 2, y: 75) == [ids[1], ids[2], ids[0], ids[3]])
        #expect(move(3, 1, y: 25) == [ids[0], ids[3], ids[1], ids[2]])
        #expect(move(3, 1, y: 75) == [ids[0], ids[1], ids[3], ids[2]])
        #expect(move(0, 1, y: 25) == nil)
        #expect(move(1, 0, y: 75) == nil)
        #expect(move(1, 1, y: 25) == nil)
        #expect(move(3, 0, y: 0) == [ids[3], ids[0], ids[1], ids[2]])
        #expect(move(0, 3, y: 100) == [ids[1], ids[2], ids[3], ids[0]])
    }

    @Test @MainActor func settingsWindowSupportsResizingAndRestoresSavedDimensions() throws {
        _ = NSApplication.shared
        let name = "codenotch.window.test." + UUID().uuidString
        defer { NSWindow.removeFrame(usingName: name) }
        func window() -> NSWindow {
            NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 520),
                     styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        }
        let first = window()
        first.isReleasedWhenClosed = false
        SettingsWindowController.configureResizing(first, autosaveName: name)
        #expect(first.styleMask.contains(.resizable))
        #expect(first.contentMinSize == NSSize(width: 680, height: 520))
        first.setContentSize(NSSize(width: 920, height: 680))
        first.saveFrame(usingName: name)
        first.setFrameAutosaveName("")
        let expected = first.frame.size
        let saved = try #require(UserDefaults.standard.string(forKey: "NSWindow Frame " + name))
            .split(separator: " ").compactMap { Double($0) }
        try #require(saved.count == 8)
        #expect(abs(saved[2] - Double(expected.width)) < 1)
        #expect(abs(saved[3] - Double(expected.height)) < 1)
        let second = window()
        second.isReleasedWhenClosed = false
        SettingsWindowController.configureResizing(second, autosaveName: name)
        // AppKit declines frame restoration when no display is connected.
        if !NSScreen.screens.isEmpty {
            #expect(abs(second.frame.width - expected.width) < 1)
            #expect(abs(second.frame.height - expected.height) < 1)
        }
        second.setFrameAutosaveName("")
        first.close()
        second.close()
    }

    @Test @MainActor func settingsTableRendersLoadingAndOfflineRowsAtBothWidths() async throws {
        _ = NSApplication.shared
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let source = try fixture()
        let loading = CodeSwitchProvider(providerId: "loading", providerName: "Loading fixture", icon: "openai",
                                         activeRequests: 0, status: "enabled", loading: true, updatedAt: 0, quotas: [], stats: nil)
        let original = source.platforms[0]
        let file = dir.appendingPathComponent("tray-snapshot-v1.json")
        try write(CodeSwitchSnapshot(version: 1, session: source.session, sequence: 1, heartbeatAt: source.heartbeatAt,
            platforms: [CodeSwitchPlatform(platform: original.platform, name: original.name, icon: original.icon,
                error: false, providers: [tableProvider([tableQuota("five_hour"), tableQuota("weekly", used: 95),
                                                        tableQuota("monthly")]), loading])]), file)
        let bridge = CodeSwitchBridge(file: file)
        await bridge.poll(now: now)
        let domain = "codenotch.table.render." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = Preferences(defaults: defaults, domainName: domain)
        preferences.hiddenCodeSwitchProviders = ["code-switch:5:codex:offline"]
        preferences.hiddenCodeSwitchNames = ["code-switch:5:codex:offline": "Offline fixture"]
        let height = SettingsView.height - SettingsView.headerHeight
        for width in [SettingsView.width - SettingsView.sidebarWidth, SettingsView.width, 900] {
            for scheme in [ColorScheme.light, .dark] {
                let view = CodeSwitchSettingsView(preferences: preferences, bridge: bridge)
                    .frame(width: width, height: height).environment(\.colorScheme, scheme)
                let host = NSHostingView(rootView: view)
                host.frame = NSRect(x: 0, y: 0, width: width, height: height)
                host.layoutSubtreeIfNeeded()
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                // Exercise conditional cell content; it must not become extra columns.
                host.cacheDisplay(in: host.bounds, to: bitmap)
                #expect(bitmap.pixelsWide >= Int(width))
                #expect(host.bounds.height == height)
            }
        }
    }

    @Test func limitedSenderKeepsUpgradeHintWhenAPlatformFails() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("tray-snapshot-v1.json")
        let reader = CodeSwitchReader(file: file)
        var main = try fixture()
        try write(main, file)
        _ = await reader.read(now: now, mode: .tray, generation: 1)
        let lease = try JSONDecoder().decode(CodeSwitchSubscription.self,
            from: Data(contentsOf: dir.appendingPathComponent("codenotch-subscription-v1.json")))
        let failed = CodeSwitchPlatform(platform: "codex", name: "Codex", icon: "openai", error: true, providers: [])
        try write(CodeSwitchProviderFile(version: 1, session: main.session, revision: 1, platforms: [failed]),
            dir.appendingPathComponent("codenotch-providers-v1.json"))
        main.codenotch = CodeSwitchIntegrationInfo(version: 1, mode: "enabled", consumerSession: lease.session,
            revision: 1, error: false)
        try write(main, file)
        #expect(await reader.read(now: now, mode: .tray, generation: 1)?.connection == .limited)
        main.codenotch?.providerScope = "enabled-or-quota-disabled"
        try write(main, file)
        #expect(await reader.read(now: now, mode: .tray, generation: 1)?.connection == .partial)
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
        #expect(full?.connection == .limited)
        #expect(full?.snapshots.count == 2)
        for _ in 0..<20 { _ = await reader.read(now: now, mode: .enabled, generation: 1) }
        #expect(await reader.mainDecodes == 2)
        #expect(await reader.providerDecodes == 1)
        let tray = await reader.read(now: now, mode: .tray, generation: 1)
        #expect(tray?.snapshots.count == 2)
        #expect(tray?.trayIDs.count == 1)
        #expect(FileManager.default.fileExists(atPath: leaseURL.path))
        upgraded.codenotch?.providerScope = "enabled-or-quota-disabled"
        try write(upgraded, file)
        let supported = await reader.read(now: now, mode: .exhausted, generation: 1)
        #expect(supported?.connection == .connected)
        #expect(supported?.snapshots.count == 2)
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
        #expect(recovered?.connection == .limited)
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
