/**
 @name: 可配置额度查询回归测试
 @Descripttion: 验证条目迁移、凭据隔离、额度解析和独立调度。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-08 14:56:06
 @LastEditTime: 2026-09-08 14:56:06
 @FilePath: Tests/QueryConfigurationTests.swift
 */
import XCTest
@testable import Codenotch

@MainActor
final class QueryConfigurationTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "QueryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    func testMigrationKeepsIdentityAndDisabledStateAndNeverRecreatesDeletedEntries() throws {
        let defaults = defaults()
        let secrets = MemoryQuerySecrets()
        let catalog = QueryCatalog(providers: [QueryProbe(id: "claude"), QueryProbe(id: "glm")],
            disconnected: ["glm"], defaults: defaults, secrets: secrets)
        XCTAssertEqual(catalog.entries.map(\.id), ["claude", "glm"])
        XCTAssertFalse(catalog.entries[1].enabled)
        XCTAssertEqual(catalog.entries[0].mode, .automatic)
        try catalog.delete("claude")
        let reloaded = QueryCatalog(providers: [QueryProbe(id: "claude"), QueryProbe(id: "glm")],
            disconnected: [], defaults: defaults, secrets: secrets)
        XCTAssertEqual(reloaded.entries.map(\.id), ["glm"])
        XCTAssertFalse(reloaded.entries[0].enabled)
    }

    func testTwoAccountsHaveSeparateSecretsAndDefaultsContainNoSecrets() throws {
        let defaults = defaults()
        let secrets = MemoryQuerySecrets()
        let catalog = QueryCatalog(providers: [], disconnected: [], defaults: defaults, secrets: secrets)
        var first = QueryEntry()
        first.name = "Personal"
        var second = QueryEntry()
        second.name = "Work"
        var a = QuerySecrets()
        a.apiKey = "fixture-personal-key"
        var b = QuerySecrets()
        b.cookie = "fixture-work-cookie"
        try catalog.save(first, secrets: a)
        try catalog.save(second, secrets: b)
        XCTAssertNotEqual(first.credentialReference, second.credentialReference)
        XCTAssertEqual(try secrets.load(first.credentialReference), a)
        let data = defaults.data(forKey: "queryEntries.v1")!
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains(a.apiKey))
        XCTAssertFalse(text.contains(b.cookie))
        try catalog.delete(first.id)
        XCTAssertEqual(try secrets.load(first.credentialReference), QuerySecrets())
        XCTAssertEqual(try secrets.load(second.credentialReference), b)
    }

    func testMissingManualCredentialsNeverReadAutomaticProvider() async {
        let native = QueryProbe(id: "claude")
        let provider = ConfiguredUsageProvider(entry: QueryEntry(), automatic: native, secrets: MemoryQuerySecrets())
        do {
            _ = try await provider.fetchSnapshot()
            XCTFail("Missing credentials must fail")
        } catch UsageProviderError.needsAuth {} catch { XCTFail("Unexpected error: \(error)") }
        let calls = await native.calls
        XCTAssertEqual(calls, 0)
    }

    func testManualRequestsUseTheCorrectCredentialType() throws {
        var entry = QueryEntry()
        var secrets = QuerySecrets()
        secrets.cookie = "session=fixture-cookie"
        secrets.accessToken = "fixture-oauth"
        secrets.accountID = "fixture-account"
        entry.nativeID = "cursor"
        XCTAssertEqual(try ManualNativeQuery.request(entry: entry, secrets: secrets).value(forHTTPHeaderField: "Cookie"), secrets.cookie)
        entry.nativeID = "codex"
        let request = try ManualNativeQuery.request(entry: entry, secrets: secrets)
        XCTAssertEqual(request.value(forHTTPHeaderField: "ChatGPT-Account-Id"), secrets.accountID)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-oauth")
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
    }

    func testZeroBalanceAndDecimalValuesAreReadingsWithoutInventedDenominators() throws {
        let json = Data(#"[{"key":"zero","remaining":0,"unit":"USD"},{"key":"one","remaining":1},{"key":"balance","remaining":12.345,"used":5.25,"unit":"USD"}]"#.utf8)
        let windows = try QueryResultParser.windows(JSONSerialization.jsonObject(with: json))
        XCTAssertEqual(windows[0].quantity?.remaining, 0)
        XCTAssertEqual(windows[1].quantity?.remaining, 1)
        XCTAssertEqual(windows[2].quantity?.remaining, 12.345)
        XCTAssertNil(windows[2].usedFraction)
    }

    func testPercentageRoundingRemainsConsistentWithTheDetail() {
        let snapshot = ProviderSnapshot(id: "rounding", displayName: "Rounding", glyph: .third,
            fidelity: .official, status: .ok,
            windows: [LimitWindow(id: "session", label: "Session", usedFraction: 0.125)])
        XCTAssertEqual(snapshot.headlineText, "13%")
        XCTAssertTrue(snapshot.headline!.summary.hasPrefix("13%"))
    }

    func testLongListsFitEachEdgeAndTheLastEntryIsReachable() {
        for edge in NotchEdge.allCases {
            let model = NotchViewModel()
            model.edge = edge
            model.screenSize = CGSize(width: 1440, height: 900)
            model.screenUsableSize = CGSize(width: 1440, height: 850)
            model.snapshots = (0..<30).map { index in
                ProviderSnapshot(id: "p\(index)", displayName: "P\(index)", glyph: .third,
                    fidelity: .official, status: .ok, windows: [])
            }
            let length = edge.isVertical ? model.panelSize.height : model.panelSize.width
            XCTAssertLessThanOrEqual(length, edge.isVertical ? 850 : 1440)
            model.scroll(by: 30)
            XCTAssertEqual(model.visibleIndices.last, 29)
            XCTAssertLessThan(model.visibleIndices.count, model.snapshots.count)
        }
    }

    func testDisabledEntryPreservesBackoffUntilCredentialsChange() throws {
        let defaults = defaults()
        let catalog = QueryCatalog(providers: [QueryProbe(id: "claude")], disconnected: [],
            defaults: defaults, secrets: MemoryQuerySecrets())
        let archive = UsageArchive(defaults: defaults)
        let until = Date().addingTimeInterval(300)
        archive.saveBackoffUntil(until, providerID: "claude")
        let store = UsageStore(providers: catalog.providers(), archive: archive)
        catalog.onChange = { invalidated in
            store.reconfigure(providers: catalog.providers(),
                disconnected: Set(catalog.entries.filter { !$0.enabled }.map(\.id)), invalidated: invalidated)
        }
        catalog.setEnabled(false, id: "claude")
        catalog.setEnabled(true, id: "claude")
        XCTAssertEqual(archive.loadBackoffUntil(providerID: "claude"), until)
        var changed = catalog.entries[0]
        changed.schedule.enabled = false
        changed.mode = .manual
        try catalog.save(changed, secrets: QuerySecrets(accessToken: "fixture-new-account"))
        XCTAssertNil(archive.loadBackoffUntil(providerID: "claude"))
        catalog.onChange = nil
        store.stop()
    }

    func testQuotaFractionResetAndUnlimited() throws {
        let windows = try QueryResultParser.windows([
            ["key": "daily", "total": 100, "remaining": 25, "nextReset": "2026-09-09T00:00:00Z"],
            ["key": "unlimited", "unlimited": true]
        ])
        XCTAssertEqual(windows[0].usedFraction, 0.75)
        XCTAssertNotNil(windows[0].resetsAt)
        XCTAssertTrue(windows[1].quantity!.unlimited)
        XCTAssertNil(windows[1].usedFraction)
    }

    func testMalformedNumbersAndDuplicateKeysFail() {
        for payload: Any in [
            ["remaining": true], ["remaining": "NaN"], ["used": -2],
            ["label": "No metric"], ["remaining": 1, "isValid": false],
            [["key": "same", "remaining": 1], ["key": "same", "remaining": 2]]
        ] {
            XCTAssertThrowsError(try QueryResultParser.windows(payload))
        }
    }

    func testExplicitMissingHeadlineDoesNotSwitchToAnotherMetric() throws {
        var entry = QueryEntry()
        entry.headlineID = "monthly"
        entry.template = .custom
        let provider = ConfiguredUsageProvider(entry: entry, automatic: nil, secrets: MemoryQuerySecrets())
        let snapshot = provider.decorate(ProviderSnapshot(id: "fixture", displayName: "Fixture", glyph: .third,
            fidelity: .official, status: .ok, windows: [LimitWindow(id: "daily", label: "Daily", usedFraction: 0.5)]))
        XCTAssertNil(snapshot.headline)
        XCTAssertEqual(snapshot.headlineText, "—")
    }

    func testArchiveReadsOldWindowsAndNewDecimalQuantities() throws {
        let oldData = Data(#"{"id":"daily","label":"Daily","remaining":4}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(LimitWindow.self, from: oldData).remaining, 4)
        let archive = UsageArchive(defaults: defaults())
        let window = LimitWindow(id: "money", label: "Money", quantity: QuotaQuantity(remaining: 12.34, unit: "USD"))
        let snapshot = ProviderSnapshot(id: "custom", displayName: "Custom", glyph: .third,
            fidelity: .official, status: .ok, windows: [window], icon: ProviderIcon(kind: .symbol, value: "cloud"), manualQuery: true)
        archive.save([snapshot.id: (snapshot, Date())])
        let restored = archive.load()[snapshot.id]!.snapshot
        XCTAssertEqual(restored.windows, [window])
        XCTAssertEqual(restored.icon, snapshot.icon)
        XCTAssertTrue(restored.manualQuery)
    }

    func testIndependentSchedulesAndDisabledAutomaticRefresh() async throws {
        let a = QueryProbe(id: "a")
        let b = QueryProbe(id: "b")
        let defaults = defaults()
        let catalog = QueryCatalog(providers: [a, b], disconnected: [], defaults: defaults, secrets: MemoryQuerySecrets())
        var entry = catalog.entries[1]
        entry.schedule.enabled = false
        try catalog.save(entry, secrets: nil)
        let store = UsageStore(providers: catalog.providers(), archive: UsageArchive(defaults: defaults))
        store.refreshDue()
        try await Task.sleep(for: .milliseconds(50))
        let first = await a.calls
        let second = await b.calls
        XCTAssertEqual(first, 1)
        XCTAssertEqual(second, 0)
        store.refresh(providerID: "b")
        try await Task.sleep(for: .milliseconds(50))
        let manual = await b.calls
        XCTAssertEqual(manual, 1)
        store.stop()
    }

    func testReplacementDiscardsInFlightOldAccount() async throws {
        let old = QueryProbe(id: "claude", delay: .milliseconds(200))
        var entry = QueryEntry()
        entry.id = "entry"
        entry.mode = .automatic
        entry.schedule.enabled = false
        let defaults = defaults()
        let archive = UsageArchive(defaults: defaults)
        let store = UsageStore(providers: [ConfiguredUsageProvider(entry: entry, automatic: old, secrets: MemoryQuerySecrets())], archive: archive)
        store.refresh(providerID: entry.id)
        try await Task.sleep(for: .milliseconds(30))
        entry.mode = .manual
        store.reconfigure(providers: [ConfiguredUsageProvider(entry: entry, automatic: old, secrets: MemoryQuerySecrets())],
            disconnected: [], invalidated: [entry.id])
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertFalse(store.snapshots[0].hasReading)
        XCTAssertNil(archive.load()[entry.id])
        XCTAssertTrue(store.refreshing.isEmpty)
        store.stop()
    }

    func testStoppedRequestCannotClearReplacementSpinner() async throws {
        let probe = QueryProbe(id: "claude", delay: .milliseconds(500))
        let store = UsageStore(providers: [probe], archive: UsageArchive(defaults: defaults()))
        defer { store.stop() }
        store.refresh(providerID: probe.id)
        try await Task.sleep(for: .milliseconds(30))
        store.stop()
        store.refresh(providerID: probe.id)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(store.refreshing.contains(probe.id))
        try await Task.sleep(for: .seconds(1))
        XCTAssertTrue(store.refreshing.isEmpty)
    }

    func testPresentationEditKeepsInFlightRequestAndUsesLatestMetadata() async throws {
        let probe = QueryProbe(id: "claude", delay: .milliseconds(150))
        var entry = QueryEntry()
        entry.id = "presentation"
        entry.mode = .automatic
        let store = UsageStore(providers: [ConfiguredUsageProvider(entry: entry, automatic: probe, secrets: MemoryQuerySecrets())],
            archive: UsageArchive(defaults: defaults()))
        defer { store.stop() }
        store.refreshDue()
        try await Task.sleep(for: .milliseconds(30))
        entry.name = "Renamed"
        entry.icon = ProviderIcon(kind: .symbol, value: "cloud")
        store.reconfigure(providers: [ConfiguredUsageProvider(entry: entry, automatic: probe, secrets: MemoryQuerySecrets())],
            disconnected: [], invalidated: [])
        try await Task.sleep(for: .milliseconds(600))
        let calls = await probe.calls
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(store.snapshots.first?.displayName, "Renamed")
        XCTAssertEqual(store.snapshots.first?.icon, entry.icon)
        XCTAssertTrue(store.snapshots.first?.hasReading == true)
    }

    func testAutomaticQueryHonorsConfiguredTimeout() async throws {
        var entry = QueryEntry()
        entry.mode = .automatic
        entry.timeout = 1
        let provider = ConfiguredUsageProvider(entry: entry,
            automatic: QueryProbe(id: "claude", delay: .seconds(5)), secrets: MemoryQuerySecrets())
        let start = Date()
        do {
            _ = try await provider.fetchSnapshot()
            XCTFail("Automatic query must time out")
        } catch QueryError.timeout {}
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }

    func testScriptDeadlineCancelsPendingFetch() async throws {
        let runner = QueryScriptRunner(fetch: { _ in
            try await Task.sleep(for: .seconds(5))
            return Data(#"{"balance":1}"#.utf8)
        })
        let start = Date()
        do {
            _ = try await runner.run(code: QueryTemplate.general.code,
                variables: ["baseUrl": "https://example.test", "apiKey": "fixture"], timeout: 1)
            XCTFail("Pending fetch must time out")
        } catch QueryError.timeout {}
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }

    func testBalanceTemplateRejectsMissingValuesButAcceptsZero() async throws {
        for value in ["null", "\"\"", "\"  \"", "false"] {
            let data = Data("{\"balance\":\(value)}".utf8)
            do {
                _ = try await QueryScriptRunner(fetch: { _ in data }).run(code: QueryTemplate.stepfun.code,
                    variables: ["baseUrl": "https://example.test", "apiKey": "fixture"], timeout: 2)
                XCTFail("Invalid balance accepted: \(value)")
            } catch QueryError.script {}
        }
        let windows = try await QueryScriptRunner(fetch: { _ in Data(#"{"balance":0}"#.utf8) })
            .run(code: QueryTemplate.stepfun.code,
                variables: ["baseUrl": "https://example.test", "apiKey": "fixture"], timeout: 2)
        XCTAssertEqual(windows.first?.quantity?.remaining, 0)
    }

    func testSub2APIComputesDailyAndWeeklyResets() async throws {
        let data = Data(#"{"subscription":{"daily_limit_usd":10,"weekly_limit_usd":50,"weekly_window_start":"2026-09-01T00:00:00Z"}}"#.utf8)
        let windows = try await QueryScriptRunner(fetch: { _ in data }).run(code: QueryTemplate.sub2api.code,
            variables: ["baseUrl": "https://example.test", "apiKey": "fixture"], timeout: 2)
        XCTAssertNotNil(windows.first { $0.id == "daily" }?.resetsAt)
        XCTAssertEqual(windows.first { $0.id == "weekly" }?.resetsAt,
            QueryResultParser.parseDate("2026-09-08T00:00:00Z"))
        XCTAssertEqual(windows.first?.quantity?.used, 0)
    }

    func testScriptPreservesQuotedCookieWithoutExecutingItsContents() async throws {
        let cookie = "session='\"`\\\n${throw new Error()}{{apiKey}}"
        let runner = QueryScriptRunner(fetch: { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), cookie.replacingOccurrences(of: "\n", with: ""))
            return Data(#"{"balance":12.34}"#.utf8)
        })
        let code = """
        ({request: {url: 'https://example.test/quota', headers: {Cookie: '{{cookie}}'.replace(/\\n/g, '')}},
          extractor: response => ({key: 'balance', remaining: response.balance, unit: 'USD'})})
        """
        let windows = try await runner.run(code: code, variables: ["cookie": cookie, "apiKey": "fixture"], timeout: 2)
        XCTAssertEqual(windows[0].quantity?.remaining, 12.34)
    }

    func testScriptInfiniteLoopTimesOutAndDoesNotPreventNextQuery() async throws {
        do {
            _ = try await QueryScriptRunner().run(code: "while (true) {}", variables: [:], timeout: 0.1)
            XCTFail("Infinite script must time out")
        } catch QueryError.timeout {} catch { XCTFail("Unexpected error: \(error)") }
        let windows = try await QueryScriptRunner(fetch: { _ in Data(#"{"balance":0}"#.utf8) })
            .run(code: QueryTemplate.general.code, variables: ["baseUrl": "https://example.test", "apiKey": "fixture"], timeout: 2)
        XCTAssertEqual(windows[0].quantity?.remaining, 0)
    }
}

private final class MemoryQuerySecrets: QuerySecretStorage {
    var values: [String: QuerySecrets] = [:]
    func load(_ reference: String) throws -> QuerySecrets { values[reference] ?? QuerySecrets() }
    func save(_ secrets: QuerySecrets, reference: String) throws { values[reference] = secrets }
    func remove(_ reference: String) throws { values[reference] = nil }
}

private actor QueryProbe: UsageProvider {
    nonisolated let id: String
    nonisolated var displayName: String { id }
    nonisolated let glyph = ProviderGlyph.third
    var calls = 0
    let delay: Duration
    init(id: String, delay: Duration = .zero) { self.id = id; self.delay = delay }
    func fetchSnapshot() async throws -> ProviderSnapshot {
        calls += 1
        try? await Task.sleep(for: delay)
        return ProviderSnapshot(id: id, displayName: id, glyph: glyph, fidelity: .official, status: .ok,
            windows: [LimitWindow(id: "session", label: "Session", usedFraction: 0.5)])
    }
}
