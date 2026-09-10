/**
 @name: 查询失败恢复回归
 @Descripttion: 验证刷新失败、超时及迟到响应不会阻止后续查询。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-10 15:55:11
 @LastEditTime: 2026-09-10 15:55:11
 @FilePath: Tests/UsageRefreshRecoveryTests.swift
 */
import Foundation
import Combine
import Darwin
import Testing
@testable import Codenotch

@Suite @MainActor struct UsageRefreshRecoveryTests {
    private func waitUntil(timeout: Duration = .seconds(3),
                           _ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !(await condition()) {
            try #require(ContinuousClock.now < deadline, "Timed out waiting for test state")
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func withStore(hangs: Bool, body: (UsageStore, RecoveryProbe) async throws -> Void) async throws {
        let suite = "UsageRefreshRecoveryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let probe = RecoveryProbe(hangs: hangs)
        var entry = QueryEntry()
        entry.id = probe.id
        entry.mode = .automatic
        entry.timeout = 1
        entry.schedule.enabled = false
        let provider = ConfiguredUsageProvider(entry: entry, automatic: probe, secrets: RecoverySecrets())
        let store = UsageStore(providers: [provider], archive: UsageArchive(defaults: defaults))
        defer { store.stop() }
        try await body(store, probe)
    }

    @Test func networkFailureCanBeRetriedAndRestoresTheReading() async throws {
        try await withStore(hangs: false) { store, probe in
            store.refresh(providerID: probe.id)
            try await waitUntil { store.refreshing.isEmpty }
            #expect(store.snapshots[0].status == .ok)
            store.refresh(providerID: probe.id)
            try await waitUntil { store.refreshing.isEmpty }
            #expect(store.snapshots[0].status.isStale)
            #expect(store.snapshots[0].queryFailure != nil)
            #expect(store.snapshots[0].usedFraction == 0.1)
            #expect(store.refreshing.isEmpty)
            store.refresh(providerID: probe.id)
            try await waitUntil { store.refreshing.isEmpty }
            #expect(await probe.calls == 3)
            #expect(store.snapshots[0].status == .ok)
            #expect(store.snapshots[0].queryFailure == nil)
            #expect(store.snapshots[0].usedFraction == 0.3)
        }
    }

    @Test(arguments: [false, true])
    func slowAutomaticRefreshWaitsForItsIntervalAfterCompletion(failFirst: Bool) async throws {
        let suite = "UsageRefreshRecoveryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let probe = SlowScheduleProbe(failFirst: failFirst)
        var entry = QueryEntry()
        entry.id = probe.id
        entry.mode = .automatic
        entry.timeout = 3
        entry.schedule.activeSeconds = 1
        entry.schedule.idleSeconds = 1
        let provider = ConfiguredUsageProvider(entry: entry, automatic: probe, secrets: RecoverySecrets())
        let store = UsageStore(providers: [provider], archive: UsageArchive(defaults: defaults))
        defer { store.stop() }
        store.refreshDue()
        try await waitUntil { store.refreshing.isEmpty }
        #expect(await probe.calls == 1)
        #expect((store.snapshots[0].queryFailure != nil) == failFirst)
        store.refreshDue()
        #expect(store.refreshing.isEmpty, "Slow completion must not immediately start another automatic request")
        try await Task.sleep(for: .milliseconds(50))
        #expect(await probe.calls == 1)
        store.refreshDue(now: Date().addingTimeInterval(1.1))
        try await waitUntil { await probe.calls == 2 }
        try await waitUntil { store.refreshing.isEmpty }
        store.refresh(providerID: probe.id)
        try await waitUntil { await probe.calls == 3 }
    }

    @Test func credentialReadTimeoutReleasesRefreshAndPreservesRetry() async throws {
        let suite = "UsageRefreshRecoveryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let secrets = DelayedRecoverySecrets()
        var entry = QueryEntry()
        entry.id = "slow-credentials"
        entry.timeout = 1
        entry.schedule.enabled = false
        let provider = ConfiguredUsageProvider(entry: entry, automatic: nil, secrets: secrets)
        let store = UsageStore(providers: [provider], archive: UsageArchive(defaults: defaults))
        defer { store.stop() }
        store.refresh(providerID: entry.id)
        try await waitUntil(timeout: .milliseconds(1800)) { store.refreshing.isEmpty }
        #expect(store.snapshots[0].queryFailure == QueryError.timeout.localizedDescription)
        // A retry must complete even while the previous credential call is blocked.
        store.refresh(providerID: entry.id)
        try await waitUntil { store.refreshing.isEmpty }
        #expect(secrets.calls == 2)
        #expect(store.snapshots[0].queryFailure != QueryError.timeout.localizedDescription)
        let retryFailure = store.snapshots[0].queryFailure
        try await waitUntil { secrets.firstReturned }
        try await Task.sleep(for: .milliseconds(50))
        #expect(store.snapshots[0].queryFailure == retryFailure)
        #expect(store.refreshing.isEmpty)
    }

    @Test func timeoutReleasesRefreshAndLateResponseCannotOverwriteRetry() async throws {
        try await withStore(hangs: true) { store, probe in
            store.refresh(providerID: probe.id)
            try await waitUntil { store.refreshing.isEmpty }
            store.refresh(providerID: probe.id)
            try await waitUntil(timeout: .seconds(2)) { store.refreshing.isEmpty }
            #expect(store.refreshing.isEmpty)
            #expect(store.snapshots[0].queryFailure == QueryError.timeout.localizedDescription)
            #expect(store.snapshots[0].usedFraction == 0.1)
            store.refresh(providerID: probe.id)
            try await waitUntil { store.refreshing.isEmpty }
            #expect(await probe.calls == 3)
            #expect(store.snapshots[0].status == .ok)
            #expect(store.snapshots[0].usedFraction == 0.3)
            try await waitUntil { await probe.lateResponseReturned }
            #expect(store.snapshots[0].queryFailure == nil)
            #expect(store.snapshots[0].usedFraction == 0.3)
            #expect(store.refreshing.isEmpty)
        }
    }

    @Test func deadlineDoesNotWaitForAnOperationThatIgnoresCancellation() async throws {
        let start = ContinuousClock.now
        do {
            _ = try await QueryDeadline.run(seconds: 0.05) {
                await delayedRecoveryValue()
            }
            Issue.record("Query must time out")
        } catch QueryError.timeout {}
        #expect(start.duration(to: .now) < .milliseconds(500))
    }

    @Test func cancellationReleasesCallerWithoutWaitingForIO() async throws {
        let task = Task {
            try await QueryDeadline.run(seconds: 10) { await delayedRecoveryValue() }
        }
        try await Task.sleep(for: .milliseconds(50))
        let start = ContinuousClock.now
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Cancelled query must not succeed")
        } catch is CancellationError {}
        #expect(start.duration(to: .now) < .milliseconds(500))
    }

    @Test func quickCompletionCancelsItsDeadlineWithoutLosingTheResult() async throws {
        for _ in 0..<100 {
            let value = try await QueryDeadline.run(seconds: 1) { 42 }
            #expect(value == 42)
        }
    }

    @Test func persistedRateLimitExplainsSkippedClicksAndAllowsRetryAfterExpiry() async throws {
        let suite = "UsageRefreshRecoveryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let archive = UsageArchive(defaults: defaults)
        let probe = RecoveryProbe(hangs: false)
        var entry = QueryEntry()
        entry.id = probe.id
        entry.mode = .automatic
        entry.schedule.enabled = false
        let until = Date().addingTimeInterval(0.6)
        archive.saveBackoffUntil(until, providerID: probe.id)
        let provider = ConfiguredUsageProvider(entry: entry, automatic: probe, secrets: RecoverySecrets())
        let store = UsageStore(providers: [provider], archive: archive)
        defer { store.stop() }
        var publications = 0
        let subscription = store.$snapshots.sink { _ in publications += 1 }
        defer { subscription.cancel() }
        store.refresh(providerID: probe.id)
        let afterFirstClick = publications
        store.refresh(providerID: probe.id)
        store.refresh(providerID: probe.id)
        #expect(publications == afterFirstClick)
        #expect(await probe.calls == 0)
        #expect(store.refreshing.isEmpty)
        #expect(store.snapshots[0].queryRetryAfter == until)
        #expect(store.snapshots[0].queryFailure != nil)
        #expect(store.snapshots[0].refreshNote(isRefreshing: false, now: until.addingTimeInterval(-1))
            == String(localized: "Retry after \(until.formatted(date: .omitted, time: .standard))"))
        try await waitUntil { Date() >= until }
        store.refresh(providerID: probe.id)
        #expect(store.snapshots[0].refreshNote(isRefreshing: true, now: Date()) == String(localized: "Refreshing…"))
        try await waitUntil { store.refreshing.isEmpty }
        #expect(await probe.calls == 1)
        #expect(store.snapshots[0].status == .ok)
        #expect(store.snapshots[0].queryFailure == nil)
        #expect(store.snapshots[0].queryRetryAfter == nil)
        #expect(archive.loadBackoffUntil(providerID: probe.id) == nil)
    }

    @Test func scriptFailureAndTimeoutDoNotPreventTheNextQuery() async throws {
        do {
            _ = try await QueryScriptRunner(fetch: { _ in throw URLError(.notConnectedToInternet) })
                .run(code: QueryTemplate.general.code,
                     variables: ["baseUrl": "https://example.test", "apiKey": "fixture"], timeout: 1)
            Issue.record("Network failure must be reported")
        } catch is URLError {}
        do {
            _ = try await QueryScriptRunner().run(code: "while (true) {}", variables: [:], timeout: 0.1)
            Issue.record("Infinite script must time out")
        } catch QueryError.timeout {}
        let windows = try await QueryScriptRunner(fetch: { _ in Data(#"{"balance":12}"#.utf8) })
            .run(code: QueryTemplate.general.code,
                 variables: ["baseUrl": "https://example.test", "apiKey": "fixture"], timeout: 2)
        #expect(windows.first?.quantity?.remaining == 12)
    }

    @Test(arguments: [true, false])
    func cancelledScriptDoesNotLeaveHelperRunning(cancelBeforeStart: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pidFile = directory.appendingPathComponent("helper.pid")
        let executable = directory.appendingPathComponent("helper")
        let quotedPIDPath = "'" + pidFile.path.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
        let script = """
        #!/bin/sh
        # @name: 取消回归辅助进程
        # @Descripttion: 记录测试进程并模拟等待请求的辅助程序。
        # @version: 1.0.0
        # @Author: sm
        # @Date: 2026-09-10 16:10:00
        # @LastEditTime: 2026-09-10 16:10:00
        # @FilePath: helper
        echo $$ > \(quotedPIDPath)
        exec /bin/sleep 30
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let runner = QueryScriptRunner(executableURL: executable)
        defer { runner.stop() }
        let task = Task {
            if cancelBeforeStart { withUnsafeCurrentTask { $0?.cancel() } }
            return try await runner.run(code: "while (true) {}", variables: [:], timeout: 10)
        }
        if !cancelBeforeStart {
            try await waitUntil { (try? String(contentsOf: pidFile, encoding: .utf8))?.isEmpty == false }
            task.cancel()
        }
        do {
            _ = try await task.value
            Issue.record("Cancelled query must not succeed")
        } catch is CancellationError {}
        if cancelBeforeStart {
            // Observe a quiet interval: the regression returned before launching
            // its detached helper, so checking only at return misses the leak.
            try await Task.sleep(for: .milliseconds(200))
            #expect(!FileManager.default.fileExists(atPath: pidFile.path))
        } else {
            let text = try String(contentsOf: pidFile, encoding: .utf8)
            let pid = try #require(Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)))
            try await waitUntil { kill(pid, 0) != 0 }
        }
    }
}

private func delayedRecoveryValue() async -> Double {
    // A continuation models callback-based I/O that has not acknowledged cancellation.
    await withCheckedContinuation { continuation in
        DispatchQueue.global().asyncAfter(deadline: .now() + 2.5) {
            continuation.resume(returning: 0.9)
        }
    }
}

private actor RecoveryProbe: UsageProvider {
    nonisolated let id = "recovery-fixture"
    nonisolated let displayName = "Recovery fixture"
    nonisolated let glyph = ProviderGlyph.third
    let hangs: Bool
    var calls = 0
    var lateResponseReturned = false
    init(hangs: Bool) { self.hangs = hangs }
    func fetchSnapshot() async throws -> ProviderSnapshot {
        calls += 1
        var value = calls == 1 ? 0.1 : 0.3
        if calls == 2 {
            if hangs {
                value = await delayedRecoveryValue()
                lateResponseReturned = true
            }
            else { throw URLError(.notConnectedToInternet) }
        }
        return ProviderSnapshot(id: id, displayName: displayName, glyph: glyph,
                                fidelity: .official, status: .ok,
                                windows: [LimitWindow(id: "session", label: "Session", usedFraction: value)])
    }
}

private final class RecoverySecrets: QuerySecretStorage {
    func load(_ reference: String) throws -> QuerySecrets { QuerySecrets() }
    func save(_ secrets: QuerySecrets, reference: String) throws {}
    func remove(_ reference: String) throws {}
}

private actor SlowScheduleProbe: UsageProvider {
    nonisolated let id = "slow-schedule"
    nonisolated let displayName = "Slow schedule"
    nonisolated let glyph = ProviderGlyph.third
    let failFirst: Bool
    var calls = 0
    init(failFirst: Bool) { self.failFirst = failFirst }
    func fetchSnapshot() async throws -> ProviderSnapshot {
        calls += 1
        if calls == 1 {
            try await Task.sleep(for: .milliseconds(1100))
            if failFirst { throw URLError(.notConnectedToInternet) }
        }
        return ProviderSnapshot(id: id, displayName: displayName, glyph: glyph, fidelity: .derived,
                                status: .ok, windows: [LimitWindow(id: "daily", label: "Daily", usedFraction: 0.2)])
    }
}

private final class DelayedRecoverySecrets: QuerySecretStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var returned = false
    var calls: Int { lock.lock(); defer { lock.unlock() }; return count }
    var firstReturned: Bool { lock.lock(); defer { lock.unlock() }; return returned }
    func load(_ reference: String) throws -> QuerySecrets {
        lock.lock()
        count += 1
        let first = count == 1
        lock.unlock()
        if first {
            // Model a synchronous credential API that does not acknowledge cancellation.
            Thread.sleep(forTimeInterval: 2.5)
            lock.lock()
            returned = true
            lock.unlock()
        }
        return QuerySecrets()
    }
    func save(_ secrets: QuerySecrets, reference: String) throws {}
    func remove(_ reference: String) throws {}
}
