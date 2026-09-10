/**
 @name: 会话归属与备用入口回归
 @Descripttion: 使用发送端快照验证供应商去重、等待迁移和备用入口语义。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-10 15:25:00
 @LastEditTime: 2026-09-10 15:25:00
 @FilePath: Tests/ActivityRoutingTests.swift
 */
import Foundation
import Testing
import SQLite3
@testable import Codenotch

@Suite @MainActor struct ActivityRoutingTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func fixture() throws -> CodeSwitchSnapshot {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/code-switch-session-routing.json")
        return try JSONDecoder().decode(CodeSwitchSnapshot.self, from: Data(contentsOf: file))
    }

    private func bridge() throws -> CodeSwitchSnapshotState {
        var state = CodeSwitchSnapshotState()
        state.accept(try fixture(), now: now)
        return state
    }

    private func session(_ number: Int, start: Date? = nil, state: AgentSession.State = .waiting) -> AgentSession {
        AgentSession(id: "fixture-\(number)", name: "Fixture", detail: "Codex · CLI", state: state,
                     waitingFor: state == .waiting ? "answer" : nil, since: now,
                     hookSessionKey: HookEvent.sessionKey(tool: "codex", id: "session-\(number)"),
                     hookTurnStartedAt: start)
    }

    @Test func senderFixtureRoutesThreeSessionsToOneSupplierWithoutStartEvents() throws {
        let state = try bridge()
        let native = [session(1), session(2, state: .busy), session(3, state: .busy)]
        let routing = ActivityRouting(local: [], linked: state.snapshots, sources: [:], sessions: ["codex": native],
                                      bindings: state.bindings, now: now)
        #expect(state.bindings.count == 3)
        #expect(routing.snapshots.map(\.id) == ["code-switch:5:codex:42"])
        #expect(routing.sessions.values.flatMap { $0 }.count == 3)
        #expect(routing.unmatched.isEmpty)
        let model = NotchViewModel()
        model.snapshots = routing.snapshots
        model.sessions = routing.sessions
        #expect(model.activity(for: "code-switch:5:codex:42")?.state == .waiting)
    }

    @Test func lateAssociationRemovesOnlyTheResolvedFallbackSessions() throws {
        let state = try bridge()
        let first = session(1), second = session(2)
        let initial = ActivityRouting(local: [], linked: state.snapshots, sources: [:],
                                      sessions: ["codex": [first, second]], bindings: [:], now: now)
        #expect(initial.snapshots.count == 2)
        #expect(initial.unmatched[.missingBinding] == 2)
        let key = try #require(first.hookSessionKey)
        let link = try #require(state.bindings[key])
        let partial = ActivityRouting(local: [], linked: state.snapshots, sources: [:],
                                      sessions: ["codex": [first, second]], bindings: [key: link], now: now)
        #expect(partial.sessions["activity:codex"]?.map(\.id) == [second.id])
        #expect(partial.sessions[link.snapshot.id]?.map(\.id) == [first.id])
        let resolved = ActivityRouting(local: [], linked: state.snapshots, sources: [:],
                                       sessions: ["codex": [first, second]], bindings: state.bindings, now: now)
        #expect(resolved.snapshots.count == 1)
        #expect(resolved.sessions["activity:codex"] == nil)
        #expect(resolved.unmatched.isEmpty)
    }

    @Test func supplierSwitchMovesOnlyItsSessionAndDoesNotMergeNames() throws {
        let state = try bridge()
        let first = session(1), second = session(2)
        let key = try #require(first.hookSessionKey)
        let binding = CodeSwitchSessionBinding(sessionKey: key, providerId: "84", providerName: "Fixture supplier",
                                              icon: "openai", sequence: 4, updatedAt: now.timeIntervalSince1970 * 1000 + 1)
        let platform = CodeSwitchPlatform(platform: "codex", name: "Codex", icon: "openai", error: false, providers: [])
        let link = CodeSwitchSessionLink(platform: "codex", binding: binding, snapshot: binding.snapshot(platform: platform))
        var bindings = state.bindings
        bindings[key] = link
        let routing = ActivityRouting(local: [], linked: state.snapshots, sources: [:],
                                      sessions: ["codex": [first, second]], bindings: bindings, now: now)
        #expect(routing.snapshots.count == 2)
        #expect(routing.snapshots.allSatisfy { !$0.isActivityOnly })
        #expect(routing.sessions[link.snapshot.id]?.map(\.id) == [first.id])
        #expect(routing.sessions["code-switch:5:codex:42"]?.map(\.id) == [second.id])
    }

    @Test func knownNewTurnAndWrongPlatformStillRejectAssociation() throws {
        let state = try bridge()
        let current = session(1, start: now.addingTimeInterval(1))
        let stale = ActivityRouting(local: [], linked: state.snapshots, sources: [:],
                                    sessions: ["codex": [current]], bindings: state.bindings, now: now)
        #expect(stale.unmatched[.staleBinding] == 1)
        #expect(stale.sessions["activity:codex"]?.count == 1)
        let key = try #require(current.hookSessionKey)
        let original = try #require(state.bindings[key])
        let wrong = CodeSwitchSessionLink(platform: "claude", binding: original.binding, snapshot: original.snapshot)
        let crossed = ActivityRouting(local: [], linked: state.snapshots, sources: [:],
                                      sessions: ["codex": [session(1)]], bindings: [key: wrong], now: now)
        #expect(crossed.unmatched[.platformMismatch] == 1)
        #expect(crossed.sessions["activity:codex"]?.count == 1)
    }

    @Test func disconnectPreservesWaitAndReconnectRestoresSingleSupplier() throws {
        var state = try bridge()
        state.expire(now: now.addingTimeInterval(4))
        let offline = ActivityRouting(local: [], linked: state.snapshots, sources: [:],
                                      sessions: ["codex": [session(1)]], bindings: state.bindings, now: now)
        #expect(offline.snapshots.map(\.id) == ["activity:codex"])
        #expect(offline.sessions["activity:codex"]?.first?.state == .waiting)
        let original = try fixture()
        state.accept(CodeSwitchSnapshot(version: 1, session: original.session, sequence: 2,
                                        heartbeatAt: now.timeIntervalSince1970 * 1000 + 5000,
                                        platforms: original.platforms), now: now.addingTimeInterval(5))
        let recovered = ActivityRouting(local: [], linked: state.snapshots, sources: [:],
                                        sessions: ["codex": [session(1)]], bindings: state.bindings, now: now)
        #expect(recovered.snapshots.map(\.id) == ["code-switch:5:codex:42"])
        #expect(recovered.sessions["activity:codex"] == nil)
    }

    @Test func duplicateSupplierRowsDoNotCreateAdditionalEntrances() throws {
        let original = try fixture()
        var platform = try #require(original.platforms.first)
        platform = CodeSwitchPlatform(platform: platform.platform, name: platform.name, icon: platform.icon,
                                      error: false, providers: platform.providers + platform.providers,
                                      sessionBindings: platform.sessionBindings)
        var state = CodeSwitchSnapshotState()
        state.accept(CodeSwitchSnapshot(version: 1, session: original.session, sequence: 1,
                                        heartbeatAt: original.heartbeatAt, platforms: [platform]), now: now)
        let routing = ActivityRouting(local: [], linked: state.snapshots, sources: [:],
                                      sessions: ["codex": [session(1)]], bindings: state.bindings, now: now)
        #expect(routing.snapshots.count == 1)
        #expect(routing.sessions.values.flatMap { $0 }.count == 1)
    }

    @Test func answerResumesTheLinkedSupplierWithoutLeavingAWaitingEntrance() throws {
        let state = try bridge()
        var hooks = HookSessionState()
        var watcher = SessionCompletionWatcher()
        let question = HookEvent(tool: "codex", configDirectory: "/tmp/routing-fixture", sessionID: "session-1",
                                 turnID: "turn-1", event: "PreToolUse", toolName: "request_user_input",
                                 callID: "question", cwd: "/tmp/fixture", at: now.timeIntervalSince1970)
        hooks.absorb(question, now: now)
        let waiting = hooks.merging([:])
        #expect(watcher.absorb(waiting).count == 1)
        let first = ActivityRouting(local: [], linked: state.snapshots, sources: [:], sessions: waiting,
                                    bindings: state.bindings, now: now)
        let supplierID = "code-switch:5:codex:42"
        #expect(first.snapshots.map(\.id) == [supplierID])
        #expect(first.sessions[supplierID]?.first?.state == .waiting)
        #expect(watcher.absorb(waiting).isEmpty)
        var answer = question
        answer.id = UUID().uuidString
        answer.at += 1
        answer.event = "PostToolUse"
        answer.callID = nil
        hooks.absorb(answer, now: now.addingTimeInterval(1))
        let resumed = ActivityRouting(local: [], linked: state.snapshots, sources: [:], sessions: hooks.merging([:]),
                                      bindings: state.bindings, now: now.addingTimeInterval(1))
        #expect(resumed.snapshots.map(\.id) == [supplierID])
        #expect(resumed.sessions[supplierID]?.first?.state == .busy)
        let model = NotchViewModel()
        model.snapshots = resumed.snapshots
        model.sessions = resumed.sessions
        #expect(model.activity(for: supplierID)?.state == .working)
        #expect(watcher.absorb(hooks.merging([:])).isEmpty)
    }

    @Test func fallbackDescribesActivityInsteadOfPromisingUsage() {
        let fallback = ActivityRouting(local: [], linked: [], sources: [:],
                                       sessions: ["codex": [session(1)]], bindings: [:], now: now)
        #expect(fallback.snapshots.first?.tooltipTitle == "Codex CLI")
        #expect(fallback.snapshots.first?.statusMessage == String(localized: "Provider not linked yet"))
        let ordinary = ProviderSnapshot(id: "codex", displayName: "Codex", glyph: .openai, fidelity: .derived,
                                        status: .ok, windows: [])
        #expect(ordinary.tooltipTitle == String(localized: "Codex Usage"))
        #expect(ordinary.statusMessage == String(localized: "Waiting for the first reading…"))
    }

    @Test func unansweredQuestionKeepsAttentionButAnswerRemovesEmptyCodexEntrance() throws {
        let state = try bridge()
        var hooks = HookSessionState()
        var event = HookEvent(tool: "codex", configDirectory: "/tmp/routing-fixture", sessionID: "unlinked",
                              event: "PreToolUse", toolName: "request_user_input", callID: "question",
                              cwd: "/tmp/fixture", at: now.timeIntervalSince1970)
        hooks.absorb(event, now: now)
        let waiting = ActivityRouting(local: [], linked: state.snapshots, sources: [:], sessions: hooks.merging([:]),
                                      bindings: state.bindings, now: now)
        #expect(waiting.snapshots.count == 2)
        #expect(waiting.sessions["activity:codex"]?.first?.waitingFor == String(localized: "Needs your answer"))
        #expect(waiting.snapshots.last?.isActivityOnly == true)
        #expect(waiting.snapshots.last?.statusMessage != String(localized: "Waiting for the first reading…"))
        // A lone visible supplier still does not prove ownership of an unknown session.
        #expect(waiting.sessions[state.snapshots[0].id] == nil)
        event.id = UUID().uuidString
        event.event = "PostToolUse"
        event.at += 1
        hooks.absorb(event, now: now.addingTimeInterval(1))
        let answered = ActivityRouting(local: [], linked: state.snapshots, sources: [:], sessions: hooks.merging([:]),
                                       bindings: state.bindings, now: now.addingTimeInterval(1))
        #expect(answered.snapshots == state.snapshots)
        #expect(hooks.merging([:])["codex"]?.first?.state == .busy)
        let longAfter = ActivityRouting(local: [], linked: state.snapshots, sources: [:], sessions: hooks.merging([:]),
                                        bindings: state.bindings, now: now.addingTimeInterval(21 * 60))
        #expect(longAfter.snapshots == state.snapshots)
    }

    @Test func emptyLocalCodexIsSuppressedBesideLinkedUsageButErrorsAndReadingsRemain() throws {
        let state = try bridge()
        let placeholder = ProviderSnapshot(id: "local-codex", displayName: "Codex CLI", glyph: .openai,
                                           fidelity: .derived, status: .stale(since: .distantPast), windows: [])
        let sources = [placeholder.id: "codex"]
        let hidden = ActivityRouting(local: [placeholder], linked: state.snapshots, sources: sources,
                                     sessions: ["codex": [session(1)]], bindings: state.bindings, now: now)
        #expect(hidden.snapshots == state.snapshots)
        #expect(hidden.sessions[state.snapshots[0].id]?.first?.state == .waiting)
        let standalone = ActivityRouting(local: [placeholder], linked: [], sources: sources,
                                         sessions: [:], bindings: [:], now: now)
        #expect(standalone.snapshots == [placeholder])
        let allLinkedHidden = ActivityRouting(local: [placeholder], linked: state.snapshots, sources: sources,
                                              sessions: ["codex": [session(1)]], bindings: state.bindings,
                                              hiddenLinked: Set(state.snapshots.map(\.id)), now: now)
        #expect(allLinkedHidden.snapshots == [placeholder])
        #expect(allLinkedHidden.sessions.isEmpty)
        for status in [ProviderStatus.needsAuth, .error("offline"), .accessDenied] {
            let error = ProviderSnapshot(id: placeholder.id, displayName: "Codex", glyph: .openai,
                                         fidelity: .derived, status: status, windows: [])
            let visible = ActivityRouting(local: [error], linked: state.snapshots, sources: sources,
                                          sessions: [:], bindings: [:], now: now)
            #expect(visible.snapshots.count == 2)
        }
        let reading = ProviderSnapshot(id: placeholder.id, displayName: "Codex", glyph: .openai,
                                       fidelity: .derived, status: .ok,
                                       windows: [LimitWindow(id: "daily", label: "Daily", usedFraction: 0.27)])
        #expect(reading.hasReading)
        #expect(ActivityRouting(local: [reading], linked: state.snapshots, sources: sources,
                                sessions: [:], bindings: [:], now: now).snapshots.count == 2)
    }

    @Test func nativeCodexIdentityAndHooksShareOneSupplierThroughQuestionAndAnswer() throws {
        let state = try bridge()
        let native = try #require(CodexActivityMonitor.session(id: "codex.rollout", name: "Fixture", modified: now,
                                                              staleAfter: 8, now: now, threadID: "session-1"))
        #expect(native.hookSessionKey == nil)
        #expect(native.nativeSessionKey == HookEvent.sessionKey(tool: "codex", id: "session-1"))
        let initial = ActivityRouting(local: [], linked: state.snapshots, sources: [:], sessions: ["codex": [native]],
                                      bindings: state.bindings, now: now)
        #expect(initial.sessions[state.snapshots[0].id]?.count == 1)
        var hooks = HookSessionState()
        var question = HookEvent(tool: "codex", configDirectory: "/tmp/routing-fixture", sessionID: "session-1",
                                 event: "PreToolUse", toolName: "request_user_input", callID: "q",
                                 cwd: "/tmp/fixture", at: now.timeIntervalSince1970)
        hooks.absorb(question, now: now)
        let another = try #require(CodexActivityMonitor.session(id: "codex.other", name: "Fixture", modified: now,
                                                               staleAfter: 8, now: now, threadID: "session-2"))
        let combined = hooks.merging(["codex": [native, another]])
        #expect(combined["codex"]?.count == 2)
        let waiting = ActivityRouting(local: [], linked: state.snapshots, sources: [:], sessions: combined,
                                      bindings: state.bindings, now: now)
        #expect(waiting.snapshots == state.snapshots)
        #expect(waiting.sessions[state.snapshots[0].id]?.count == 2)
        #expect(waiting.sessions[state.snapshots[0].id]?.filter { $0.state == .waiting }.count == 1)
        question.id = UUID().uuidString
        question.at += 1
        question.event = "PostToolUse"
        hooks.absorb(question, now: now.addingTimeInterval(1))
        let answered = ActivityRouting(local: [], linked: state.snapshots, sources: [:],
                                       sessions: hooks.merging(["codex": [native]]), bindings: state.bindings, now: now)
        #expect(answered.snapshots == state.snapshots)
        #expect(answered.sessions[state.snapshots[0].id]?.count == 1)
        #expect(answered.sessions[state.snapshots[0].id]?.first?.state == .busy)
        hooks.remove(tool: "codex", directory: question.configDirectory)
        let recovered = ActivityRouting(local: [], linked: state.snapshots, sources: [:],
                                        sessions: hooks.merging(["codex": [native]]), bindings: state.bindings, now: now)
        #expect(recovered.sessions[state.snapshots[0].id] == [native])
    }

    @Test func nativeDatabaseReadersPreserveThreadIdentityWithoutReadingRolloutContents() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let rollout = dir.appendingPathComponent("opaque-filename.jsonl")
        try Data().write(to: rollout)
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: rollout.path)
        let store = dir.appendingPathComponent("state.sqlite")
        var db: OpaquePointer?
        #expect(sqlite3_open(store.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        let sql = """
        CREATE TABLE threads (id TEXT, rollout_path TEXT, archived INTEGER, updated_at_ms INTEGER);
        INSERT INTO threads VALUES ('session-1', '\(rollout.path)', 0, 1);
        CREATE TABLE local_thread_catalog (thread_id TEXT, display_title TEXT, source_updated_at REAL);
        INSERT INTO local_thread_catalog VALUES ('session-2', 'Same folder', \(now.timeIntervalSince1970 + 1));
        """
        #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
        let absent = dir.appendingPathComponent("absent.sqlite")
        let cli = CodexActivityMonitor.read(stateStore: store, desktopStore: absent, staleAfter: 8, now: now)
        #expect(cli.first?.nativeSessionKey == HookEvent.sessionKey(tool: "codex", id: "session-1"))
        let desktop = CodexActivityMonitor.read(stateStore: absent, desktopStore: store, staleAfter: 8,
                                               now: now.addingTimeInterval(1))
        #expect(desktop.first?.nativeSessionKey == HookEvent.sessionKey(tool: "codex", id: "session-2"))
        #expect(desktop.first?.id == "codex.desktop:session-2")
    }
}
