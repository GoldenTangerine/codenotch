/**
 @name: Hooks 活动回归测试
 @Descripttion: 验证会话状态、安装隔离和供应商关联行为。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-09 12:15:00
 @LastEditTime: 2026-09-09 12:15:00
 @FilePath: Tests/HookActivityTests.swift
 */
import Foundation
import Testing
@testable import Codenotch

@Suite struct HookActivityTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func event(_ name: String, at offset: Double = 0, toolName: String? = nil,
                       call: String? = nil, turn: String? = "turn-1", session: String = "session-1") -> HookEvent {
        HookEvent(tool: "codex", configDirectory: "/tmp/test-codex", sessionID: session,
                  turnID: turn, event: name, toolName: toolName, callID: call, cwd: "/tmp/project", at: now.timeIntervalSince1970 + offset)
    }

    private func absorb(_ event: HookEvent, into state: inout HookSessionState) {
        state.absorb(event, now: Date(timeIntervalSince1970: event.at))
    }

    @Test func testRunningWaitingResumeAndCompletion() {
        var state = HookSessionState()
        var watcher = SessionCompletionWatcher()
        absorb(event("UserPromptSubmit"), into: &state)
        #expect(watcher.absorb(state.merging([:])).isEmpty)
        absorb(event("PreToolUse", at: 1, toolName: "request_user_input", call: "q"), into: &state)
        #expect((watcher.absorb(state.merging([:])).first?.reason) == (.blocked))
        #expect(watcher.absorb(state.merging([:])).isEmpty)
        absorb(event("PostToolUse", at: 2, toolName: "request_user_input", call: "q"), into: &state)
        #expect((state.merging([:])["codex"]?.first?.state) == (.busy))
        #expect(watcher.absorb(state.merging([:])).isEmpty)
        absorb(event("Stop", at: 3), into: &state)
        #expect((watcher.absorb(state.merging([:])).first?.reason) == (.finished))
        #expect(watcher.absorb(state.merging([:])).isEmpty)
    }

    @Test func testFirstExplicitWaitIsAnnouncedButScannedWaitIsNot() {
        var state = HookSessionState()
        var watcher = SessionCompletionWatcher()
        absorb(event("PermissionRequest", toolName: "Bash", call: "approval"), into: &state)
        #expect((watcher.absorb(state.merging([:])).first?.reason) == (.blocked))
        var scanned = SessionCompletionWatcher()
        let native = AgentSession(id: "native", name: "native", detail: "", state: .waiting, waitingFor: nil, since: now)
        #expect(scanned.absorb(["claude": [native]]).isEmpty)
    }

    @Test func testParallelToolCannotClearQuestion() {
        var state = HookSessionState()
        absorb(event("PreToolUse", toolName: "request_user_input", call: "question"), into: &state)
        absorb(event("PostToolUse", at: 1, toolName: "Bash", call: "shell"), into: &state)
        #expect((state.merging([:])["codex"]?.first?.state) == (.waiting))
        absorb(event("PermissionRequest", at: 2, toolName: "Bash", call: "second"), into: &state)
        absorb(event("PostToolUse", at: 3, toolName: "request_user_input", call: "question"), into: &state)
        #expect((state.merging([:])["codex"]?.first?.state) == (.waiting))
        absorb(event("PostToolUse", at: 4, toolName: "Bash", call: "second"), into: &state)
        #expect((state.merging([:])["codex"]?.first?.state) == (.busy))
    }

    @Test func testOutOfOrderDuplicateAndRetiredTurnEvents() {
        var state = HookSessionState()
        let question = event("PreToolUse", at: 1, toolName: "request_user_input", call: "q")
        absorb(question, into: &state)
        absorb(question, into: &state)
        absorb(event("PostToolUse", at: 2, toolName: "request_user_input", call: "q"), into: &state)
        absorb(question, into: &state)
        #expect((state.merging([:])["codex"]?.first?.state) == (.busy))
        absorb(event("UserPromptSubmit", at: 3, turn: "turn-2"), into: &state)
        absorb(event("Stop", at: 4, turn: "turn-1"), into: &state)
        #expect((state.merging([:])["codex"]?.first?.state) == (.busy))
    }

    @Test func testCancelAndExitDoNotAnnounceCompletion() {
        var state = HookSessionState()
        var watcher = SessionCompletionWatcher()
        absorb(event("UserPromptSubmit"), into: &state)
        _ = watcher.absorb(state.merging([:]))
        absorb(event("Interrupt", at: 1), into: &state)
        #expect(watcher.absorb(state.merging([:])).isEmpty)
        absorb(event("PostToolUse", at: 1.5, toolName: "Bash"), into: &state)
        #expect((state.merging([:])["codex"]?.first?.state) == (.idle))
        absorb(event("SessionEnd", at: 2), into: &state)
        #expect(state.merging([:])["codex"]?.isEmpty == true)
        #expect(watcher.absorb(state.merging([:])).isEmpty)
        absorb(event("PostToolUse", at: 3, toolName: "Bash"), into: &state)
        #expect(state.merging([:])["codex"]?.isEmpty == true)
    }

    @Test func testClaudeNativeAndHooksAreMergedByProcess() {
        var state = HookSessionState()
        var hook = event("UserPromptSubmit", turn: nil)
        hook.tool = "claude"
        hook.configDirectory = ClaudeProfile.default().configDirectory.path
        hook.pid = 4242
        absorb(hook, into: &state)
        let native = AgentSession(id: "claude.4242", name: "old", detail: "", state: .busy, waitingFor: nil, since: now, processID: 4242)
        #expect((state.merging(["claude": [native]])["claude"]?.count) == (1))
        #expect((state.merging(["claude": [native]])["claude"]?.first?.hookSessionKey) != nil)
    }

    @Test func testUnknownEventsAndPlainNotificationsCannotCreateWaits() {
        var state = HookSessionState()
        absorb(event("Unknown"), into: &state)
        absorb(event("Notification"), into: &state)
        #expect(state.records.isEmpty)
    }

    @Test func testDeadOrReusedProcessIsPruned() {
        var state = HookSessionState()
        var hook = event("UserPromptSubmit")
        hook.pid = getpid()
        hook.processStartedAt = HookSocket.process(getpid())!.started - 10
        absorb(hook, into: &state)
        state.prune(now: now)
        #expect(state.records.isEmpty)
    }

    @Test func testInstallerPreservesThirdPartyHooksAndIsIdempotent() throws {
        let target = HookTarget(tool: "claude", directory: URL(fileURLWithPath: "/tmp/claude profile"))
        let helper = URL(fileURLWithPath: "/tmp/Codenotch's App.app/Contents/MacOS/HookHelper")
        let original: [String: Any] = ["other": ["keep": true], "hooks": ["Stop": [["matcher": "", "hooks": [["type": "command", "command": "echo keep"]]]]]]
        let installed = try HookInstaller.merged(original, target: target, helper: helper, installing: true)
        let repeated = try HookInstaller.merged(installed, target: target, helper: helper, installing: true)
        #expect(NSDictionary(dictionary: installed).isEqual(to: repeated))
        let removed = try HookInstaller.merged(installed, target: target, helper: nil, installing: false)
        #expect(NSDictionary(dictionary: original).isEqual(to: removed))
        #expect(HookInstaller.command(target: target, helper: helper).contains("'\\''"))
    }

    @Test func testMalformedConfigIsNotRewritten() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = HookTarget(tool: "codex", directory: directory)
        let bad = Data("{broken".utf8)
        try bad.write(to: target.file)
        #expect(throws: (any Error).self) { try HookInstaller.write(target, helper: nil, installing: false) }
        #expect((try Data(contentsOf: target.file)) == (bad))
        #expect(throws: (any Error).self) { try HookInstaller.merged(["hooks": ["Stop": "wrong"]], target: target, helper: nil, installing: false) }
    }

    @Test func testSessionKeyMatchesGoFixture() {
        #expect((HookEvent.sessionKey(tool: "codex", id: "session-1")) == ("d3f691a7763732a761396db8b1f3ca194c77142d6f19bceb567038f2d2c388ac"))
        #expect((HookEvent.sessionKey(tool: "claude", id: "session-1")) == ("b51f4913a4cc284f55d86d9c7dec107dbde637d85c8c94f6d873634b3194200a"))
    }

    @Test func testRoutesWaitToActualSupplierAndFallsBackOnDisconnect() {
        var state = HookSessionState()
        absorb(event("UserPromptSubmit"), into: &state)
        absorb(event("PreToolUse", at: 1, toolName: "request_user_input", call: "q"), into: &state)
        let binding = CodeSwitchSessionBinding(sessionKey: event("x").sessionKey, providerId: "42", providerName: "Supplier", icon: "openai", sequence: 1, updatedAt: now.timeIntervalSince1970 * 1000)
        let platform = CodeSwitchPlatform(platform: "codex", name: "Codex", icon: "openai", error: false, providers: [])
        let link = CodeSwitchSessionLink(platform: "codex", binding: binding, snapshot: binding.snapshot(platform: platform))
        let routing = ActivityRouting(local: [], linked: [], sources: [:], sessions: state.merging([:]), bindings: [binding.sessionKey: link])
        #expect((routing.snapshots.map(\.id)) == ([link.snapshot.id]))
        #expect((routing.sessions[link.snapshot.id]?.first?.state) == (.waiting))
        let offline = ActivityRouting(local: [], linked: [], sources: [:], sessions: state.merging([:]), bindings: [:])
        #expect((offline.snapshots.map(\.id)) == (["activity:codex"]))
        #expect((offline.sessions["activity:codex"]?.first?.state) == (.waiting))
    }

    @Test func testRepeatedQuestionWithoutCallIDCanWaitAgain() {
        var state = HookSessionState()
        absorb(event("PreToolUse", toolName: "request_user_input"), into: &state)
        absorb(event("PostToolUse", at: 1, toolName: "request_user_input"), into: &state)
        absorb(event("PreToolUse", at: 2, toolName: "request_user_input"), into: &state)
        #expect(state.merging([:])["codex"]?.first?.state == .waiting)
    }

    @Test func testCompletionEntranceExpiresAndDoesNotRepeatAfterRerouting() {
        var state = HookSessionState()
        var watcher = SessionCompletionWatcher()
        absorb(event("UserPromptSubmit"), into: &state)
        _ = watcher.absorb(state.merging([:]))
        absorb(event("Stop", at: 1), into: &state)
        #expect(watcher.absorb(state.merging([:])).count == 1)
        let initial = ActivityRouting(local: [], linked: [], sources: [:], sessions: state.merging([:]), bindings: [:], now: now.addingTimeInterval(2))
        #expect(initial.snapshots.count == 1)
        let later = ActivityRouting(local: [], linked: [], sources: [:], sessions: state.merging([:]), bindings: [:], now: now.addingTimeInterval(17))
        #expect(later.snapshots.isEmpty)
        #expect(watcher.absorb(state.merging([:])).isEmpty)
    }

    @Test func testBridgeAcceptsBindingsAndClearsThemWithHeartbeat() {
        let binding = CodeSwitchSessionBinding(sessionKey: event("x").sessionKey, providerId: "42", providerName: "Supplier", icon: "openai", sequence: 1, updatedAt: now.timeIntervalSince1970 * 1000)
        let platform = CodeSwitchPlatform(platform: "codex", name: "Codex", icon: "openai", error: false, providers: [], sessionBindings: [binding])
        var bridge = CodeSwitchSnapshotState()
        bridge.accept(CodeSwitchSnapshot(version: 1, session: "bridge", sequence: 1, heartbeatAt: now.timeIntervalSince1970 * 1000, platforms: [platform]), now: now)
        #expect((bridge.bindings.count) == (1))
        bridge.expire(now: now.addingTimeInterval(4))
        #expect(bridge.bindings.isEmpty)
    }

    @Test func approvalWithoutCallIDClearsAfterToolCompletes() {
        var state = HookSessionState()
        var watcher = SessionCompletionWatcher()
        absorb(event("PreToolUse", toolName: "Bash", call: "shell"), into: &state)
        absorb(event("PermissionRequest", at: 1, toolName: "Bash"), into: &state)
        #expect(watcher.absorb(state.merging([:])).first?.reason == .blocked)
        absorb(event("PostToolUse", at: 2, toolName: "Bash", call: "shell"), into: &state)
        #expect(state.records.values.first?.state == .busy)
        absorb(event("PreToolUse", at: 3, toolName: "Bash", call: "again"), into: &state)
        absorb(event("PermissionRequest", at: 4, toolName: "Bash"), into: &state)
        #expect(watcher.absorb(state.merging([:])).first?.reason == .blocked)
    }

    @Test func anonymousApprovalDoesNotClearOtherParallelWaits() {
        var state = HookSessionState()
        absorb(event("PreToolUse", toolName: "Bash", call: "a"), into: &state)
        absorb(event("PreToolUse", at: 1, toolName: "Bash", call: "b"), into: &state)
        absorb(event("PermissionRequest", at: 2, toolName: "Bash"), into: &state)
        absorb(event("PostToolUse", at: 3, toolName: "Bash", call: "a"), into: &state)
        #expect(state.records.values.first?.state == .waiting)
        absorb(event("PreToolUse", at: 4, toolName: "request_user_input", call: "q"), into: &state)
        absorb(event("PostToolUse", at: 5, toolName: "Bash", call: "b"), into: &state)
        #expect(state.records.values.first?.waiting == ["q": "question"])
        absorb(event("PostToolUse", at: 6, toolName: "request_user_input", call: "q"), into: &state)
        #expect(state.records.values.first?.state == .busy)
    }

    @Test func approvalRecoversWhenPreToolUseWasMissed() {
        var state = HookSessionState()
        absorb(event("PermissionRequest", toolName: "Bash"), into: &state)
        absorb(event("PostToolUse", at: 1, toolName: "Bash", call: "unseen"), into: &state)
        #expect(state.records.values.first?.state == .busy)
    }

    @Test func newTurnRecoversAfterMissingPromptHook() {
        var state = HookSessionState()
        absorb(event("PreToolUse", toolName: "request_user_input", call: "old"), into: &state)
        absorb(event("PreToolUse", at: 1, toolName: "Bash", call: "new", turn: "turn-2"), into: &state)
        #expect(state.records.values.first?.state == .busy)
        absorb(event("Stop", at: 2, turn: "turn-1"), into: &state)
        #expect(state.records.values.first?.state == .busy)
        #expect(state.records.values.first?.turnStartedAt == nil)
    }

    @Test func newerClaudeStatusRecoversWithoutReplayingOldWait() {
        var state = HookSessionState()
        var hook = event("PermissionRequest", toolName: "Bash")
        hook.tool = "claude"
        hook.configDirectory = ClaudeProfile.default().configDirectory.path
        hook.pid = 4242
        absorb(hook, into: &state)
        let native = AgentSession(id: "claude.4242", name: "native", detail: "", state: .idle,
                                  waitingFor: nil, since: now.addingTimeInterval(5), processID: 4242)
        #expect(state.merging(["claude": [native]])["claude"] == [native])
        state.reconcile(["claude": [native]])
        #expect(state.records.isEmpty)
        #expect(state.merging([:]).isEmpty)
    }

    @Test func codexParallelLogsAndSilenceDoNotDismissQuestion() {
        var state = HookSessionState()
        absorb(event("PreToolUse", toolName: "request_user_input", call: "q"), into: &state)
        let native = AgentSession(id: "codex.session-1", name: "native", detail: "", state: .busy,
                                  waitingFor: nil, since: now.addingTimeInterval(10))
        state.reconcile(["codex": [native]])
        state.prune(now: now.addingTimeInterval(3600))
        #expect(state.merging(["codex": [native]])["codex"]?.first?.state == .waiting)
    }

    @Test func oldSupplierCannotOwnNewTurnOrUnknownTurn() {
        var state = HookSessionState()
        let binding = CodeSwitchSessionBinding(sessionKey: event("x").sessionKey, providerId: "42", providerName: "Old",
                                               icon: "openai", sequence: 1, updatedAt: now.timeIntervalSince1970 * 1000)
        let platform = CodeSwitchPlatform(platform: "codex", name: "Codex", icon: "openai", error: false, providers: [])
        let link = CodeSwitchSessionLink(platform: "codex", binding: binding, snapshot: binding.snapshot(platform: platform))
        absorb(event("UserPromptSubmit", at: 10), into: &state)
        absorb(event("PreToolUse", at: 11, toolName: "request_user_input", call: "q"), into: &state)
        let route = ActivityRouting(local: [], linked: [], sources: [:], sessions: state.merging([:]), bindings: [binding.sessionKey: link])
        #expect(route.snapshots.map(\.id) == ["activity:codex"])
        let updated = CodeSwitchSessionBinding(sessionKey: binding.sessionKey, providerId: "43", providerName: "New",
                                               icon: "openai", sequence: 2, updatedAt: now.addingTimeInterval(10.5).timeIntervalSince1970 * 1000)
        let newLink = CodeSwitchSessionLink(platform: "codex", binding: updated, snapshot: updated.snapshot(platform: platform))
        let current = ActivityRouting(local: [], linked: [], sources: [:], sessions: state.merging([:]), bindings: [binding.sessionKey: newLink])
        #expect(current.snapshots.map(\.id) == [newLink.snapshot.id])
        absorb(event("PreToolUse", at: 12, toolName: "Bash", call: "b", turn: "unknown-start"), into: &state)
        let unknown = ActivityRouting(local: [], linked: [], sources: [:], sessions: state.merging([:]), bindings: [binding.sessionKey: newLink])
        #expect(unknown.snapshots.map(\.id) == ["activity:codex"])
    }

    @Test func completionExpiryChangesStateOnlyOnce() {
        var state = HookSessionState()
        absorb(event("UserPromptSubmit"), into: &state)
        absorb(event("Stop", at: 1), into: &state)
        let before = state
        state.prune(now: now.addingTimeInterval(5))
        #expect(state == before)
        state.prune(now: now.addingTimeInterval(17))
        #expect(state.records.values.first?.noticeID == nil)
        let expired = state
        state.prune(now: now.addingTimeInterval(20))
        #expect(state == expired)
    }

    @Test func nativeRecoveryStillAnnouncesMissedClaudeCompletion() {
        var state = HookSessionState()
        var watcher = SessionCompletionWatcher()
        var hook = event("UserPromptSubmit")
        hook.tool = "claude"
        hook.configDirectory = ClaudeProfile.default().configDirectory.path
        hook.pid = 4242
        absorb(hook, into: &state)
        #expect(watcher.absorb(state.merging([:])).isEmpty)
        let native = AgentSession(id: "claude.4242", name: "native", detail: "", state: .idle,
                                  waitingFor: nil, since: now.addingTimeInterval(5), processID: 4242)
        state.reconcile(["claude": [native]])
        #expect(watcher.absorb(state.merging(["claude": [native]])).first?.reason == .finished)
        #expect(watcher.absorb(state.merging(["claude": [native]])).isEmpty)
    }
}
