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
        #expect(watcher.absorb(state.merging([:])).first?.reason == .started)
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

    @Test func oldSupplierCannotOwnKnownNewTurnButMissingStartUsesLatestAssociation() {
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
        #expect(unknown.snapshots.map(\.id) == [newLink.snapshot.id])
    }

    @Test(arguments: ["request_user_input", "request_user_input_async", "AskUserQuestion"])
    func questionCompletionRecoversOneMissingCallID(_ tool: String) {
        for (before, after) in [(Optional("q"), nil), (nil, Optional("q")), (nil, nil)] {
            var state = HookSessionState()
            absorb(event("PreToolUse", toolName: tool, call: before), into: &state)
            absorb(event("PostToolUse", at: 1, toolName: tool, call: after), into: &state)
            #expect(state.records.values.first?.state == .busy)
            #expect(state.records.values.first?.waiting.isEmpty == true)
            #expect(state.records.values.first?.waitingCalls.isEmpty == true)
            #expect(state.records.values.first?.noticeID == nil)
        }
    }

    @Test func missingCompletionIDDoesNotGuessBetweenParallelQuestions() {
        var state = HookSessionState()
        for id in ["a", "b"] { absorb(event("PreToolUse", toolName: "request_user_input", call: id), into: &state) }
        absorb(event("PostToolUse", at: 1, toolName: "request_user_input"), into: &state)
        #expect(state.records.values.first?.waiting.count == 2)
        #expect(state.records.values.first?.completionMismatch == .ambiguousCall)
        absorb(event("PostToolUse", at: 2, toolName: "request_user_input", call: "a"), into: &state)
        #expect(state.records.values.first?.waiting.keys.sorted() == ["b"])
        absorb(event("PostToolUse", at: 3, toolName: "request_user_input"), into: &state)
        #expect(state.records.values.first?.state == .busy)
        #expect(state.records.values.first?.completionMismatch == nil)
    }

    @Test func conflictingCallIDsAndUnrelatedToolsCannotAnswerQuestion() {
        var state = HookSessionState()
        absorb(event("PreToolUse", toolName: "request_user_input", call: "q"), into: &state)
        absorb(event("PostToolUse", at: 1, toolName: "request_user_input", call: "other"), into: &state)
        #expect(state.records.values.first?.completionMismatch == .conflictingCall)
        absorb(event("PostToolUse", at: 2, toolName: "Bash"), into: &state)
        #expect(state.records.values.first?.waiting.keys.sorted() == ["q"])
        absorb(event("PostToolUse", at: 3, toolName: "request_user_input", call: "q"), into: &state)
        #expect(state.records.values.first?.state == .busy)
    }

    @Test func duplicateCompletionCannotAnswerNewAnonymousQuestion() {
        var state = HookSessionState()
        absorb(event("PreToolUse", toolName: "request_user_input", call: "old"), into: &state)
        absorb(event("PostToolUse", at: 1, toolName: "request_user_input", call: "old"), into: &state)
        absorb(event("PreToolUse", at: 2, toolName: "request_user_input"), into: &state)
        absorb(event("PostToolUse", at: 3, toolName: "request_user_input", call: "old"), into: &state)
        #expect(state.records.values.first?.state == .waiting)
        absorb(event("PostToolUse", at: 4, toolName: "request_user_input", call: "new"), into: &state)
        #expect(state.records.values.first?.state == .busy)
    }

    @Test func anonymousQuestionDoesNotBorrowAnotherActiveInvocation() {
        var state = HookSessionState()
        absorb(event("PreToolUse", toolName: "request_user_input"), into: &state)
        absorb(event("PreToolUse", at: 1, toolName: "request_user_input", call: "other"), into: &state)
        absorb(event("PostToolUse", at: 2, toolName: "request_user_input", call: "other"), into: &state)
        #expect(state.records.values.first?.waitingCalls.count == 1)
        #expect(state.records.values.first?.waitingCalls.values.first?.id == nil)
        absorb(event("PostToolUse", at: 3, toolName: "request_user_input"), into: &state)
        #expect(state.records.values.first?.state == .busy)
    }

    @Test(arguments: ["request_user_input", "request_user_input_async", "AskUserQuestion"])
    func permissionEnrichesTheOnlyAnonymousQuestion(_ tool: String) {
        var state = HookSessionState()
        absorb(event("PreToolUse", toolName: tool), into: &state)
        absorb(event("PermissionRequest", at: 1, toolName: tool, call: "q"), into: &state)
        #expect(state.records.values.first?.waiting.keys.sorted() == ["q"])
        absorb(event("PostToolUse", at: 2, toolName: tool, call: "q"), into: &state)
        #expect(state.records.values.first?.state == .busy)
        #expect(state.records.values.first?.waitingCalls.isEmpty == true)
    }

    @Test func permissionForKnownParallelCallDoesNotMergeAnonymousQuestion() {
        var state = HookSessionState()
        absorb(event("PreToolUse", toolName: "request_user_input"), into: &state)
        absorb(event("PreToolUse", at: 1, toolName: "request_user_input", call: "q"), into: &state)
        absorb(event("PermissionRequest", at: 2, toolName: "request_user_input", call: "q"), into: &state)
        #expect(state.records.values.first?.waiting.count == 2)
        absorb(event("PostToolUse", at: 3, toolName: "request_user_input", call: "q"), into: &state)
        #expect(state.records.values.first?.state == .waiting)
        #expect(state.records.values.first?.waiting.count == 1)
    }

    @Test func anonymousParallelQuestionsRemainAmbiguousUntilTurnEnds() {
        var state = HookSessionState()
        let first = event("PreToolUse", toolName: "request_user_input")
        let second = event("PreToolUse", toolName: "request_user_input")
        absorb(first, into: &state)
        absorb(second, into: &state)
        absorb(first, into: &state)
        #expect(state.records.values.first?.waiting.count == 2)
        absorb(event("PostToolUse", at: 1, toolName: "request_user_input"), into: &state)
        #expect(state.records.values.first?.state == .waiting)
        #expect(state.records.values.first?.completionMismatch == .ambiguousCall)
        absorb(event("PermissionRequest", at: 2, toolName: "request_user_input", call: "q"), into: &state)
        absorb(event("PostToolUse", at: 3, toolName: "request_user_input", call: "q"), into: &state)
        #expect(state.records.values.first?.waiting.count == 2)
        absorb(event("Stop", at: 4), into: &state)
        #expect(state.records.values.first?.waiting.isEmpty == true)
        #expect(state.records.values.first?.waitingCalls.isEmpty == true)
        #expect(state.records.values.first?.completionMismatch == nil)
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
        #expect(watcher.absorb(state.merging([:])).first?.reason == .started)
        let native = AgentSession(id: "claude.4242", name: "native", detail: "", state: .idle,
                                  waitingFor: nil, since: now.addingTimeInterval(5), processID: 4242)
        state.reconcile(["claude": [native]])
        #expect(watcher.absorb(state.merging(["claude": [native]])).first?.reason == .finished)
        #expect(watcher.absorb(state.merging(["claude": [native]])).isEmpty)
    }

    @Test(arguments: ["claude", "codex"])
    func startsOnlyOnSubmissionAndSurvivesToolEvents(tool: String) {
        var state = HookSessionState()
        var watcher = SessionCompletionWatcher()
        func hook(_ name: String, at: Double, turn: String = "turn-1") -> HookEvent {
            var value = event(name, at: at, toolName: "Bash", call: at >= 4 ? "approval" : "shell",
                              turn: tool == "claude" ? nil : turn)
            value.tool = tool
            return value
        }
        absorb(hook("SessionStart", at: 0), into: &state)
        #expect(watcher.absorb(state.merging([:])).isEmpty)
        let submission = hook("UserPromptSubmit", at: 1)
        absorb(submission, into: &state)
        absorb(hook("PreToolUse", at: 2), into: &state)
        #expect(watcher.absorb(state.merging([:])).first?.reason == .started)
        #expect(watcher.absorb(state.merging([:])).isEmpty)
        absorb(submission, into: &state)
        absorb(hook("PostToolUse", at: 3), into: &state)
        #expect(watcher.absorb(state.merging([:])).isEmpty)
        absorb(hook("PermissionRequest", at: 4), into: &state)
        #expect(watcher.absorb(state.merging([:])).first?.reason == .blocked)
        absorb(hook("PostToolUse", at: 5), into: &state)
        #expect(watcher.absorb(state.merging([:])).isEmpty)
        absorb(hook("Stop", at: 6), into: &state)
        #expect(watcher.absorb(state.merging([:])).first?.reason == .finished)
        absorb(hook("UserPromptSubmit", at: 7, turn: "turn-2"), into: &state)
        #expect(watcher.absorb(state.merging([:])).first?.reason == .started)
    }

    @Test func sameTurnSubmissionCannotResetAWaitOrRestartCompletedWork() {
        var state = HookSessionState()
        var watcher = SessionCompletionWatcher()
        absorb(event("UserPromptSubmit"), into: &state)
        #expect(watcher.absorb(state.merging([:])).first?.reason == .started)
        absorb(event("PermissionRequest", at: 1), into: &state)
        #expect(watcher.absorb(state.merging([:])).first?.reason == .blocked)
        absorb(event("UserPromptSubmit", at: 2), into: &state)
        #expect(state.records.values.first?.state == .waiting)
        #expect(watcher.absorb(state.merging([:])).isEmpty)
        absorb(event("Stop", at: 3), into: &state)
        #expect(watcher.absorb(state.merging([:])).first?.reason == .finished)
        absorb(event("UserPromptSubmit", at: 4), into: &state)
        #expect(state.records.values.first?.state == .idle)
        #expect(watcher.absorb(state.merging([:])).isEmpty)
        absorb(event("UserPromptSubmit", at: 5, turn: "turn-2"), into: &state)
        #expect(watcher.absorb(state.merging([:])).first?.reason == .started)
        absorb(event("UserPromptSubmit", at: 6), into: &state)
        #expect(watcher.absorb(state.merging([:])).isEmpty)
    }

    @Test func expiredAndReplayedSubmissionsWithoutTurnIDsAreSilent() {
        var state = HookSessionState()
        var watcher = SessionCompletionWatcher()
        let expired = event("UserPromptSubmit", at: -31, turn: nil)
        state.absorb(expired, now: now)
        #expect(state.records.isEmpty)
        let submission = event("UserPromptSubmit", turn: nil)
        absorb(submission, into: &state)
        #expect(watcher.absorb(state.merging([:])).first?.reason == .started)
        absorb(event("PreToolUse", toolName: "Bash", turn: nil), into: &state)
        absorb(submission, into: &state)
        #expect(watcher.absorb(state.merging([:])).isEmpty)
        absorb(event("UserPromptSubmit", at: 1, turn: nil), into: &state)
        #expect(watcher.absorb(state.merging([:])).first?.reason == .started)
    }

    @Test func nativeActivityDoesNotInferStartsOnLaunchOrWhenBecomingBusy() {
        var watcher = SessionCompletionWatcher()
        let idle = AgentSession(id: "native", name: "native", detail: "", state: .idle,
                                waitingFor: nil, since: now)
        let busy = AgentSession(id: "native", name: "native", detail: "", state: .busy,
                                waitingFor: nil, since: now.addingTimeInterval(1))
        #expect(watcher.absorb(["codex": [busy]]).isEmpty)
        _ = watcher.absorb(["codex": [idle]])
        #expect(watcher.absorb(["codex": [busy]]).isEmpty)
    }

    @Test func queuedStartIsReplacedByCurrentTurnCompletionOrWait() {
        for followup in ["Stop", "PermissionRequest", "Interrupt", "SessionEnd", "UserPromptSubmit"] {
            var state = HookSessionState()
            var watcher = SessionCompletionWatcher()
            absorb(event("UserPromptSubmit"), into: &state)
            var pending = watcher.absorb(state.merging([:]))
            #expect(pending.first?.reason == .started)
            absorb(event(followup, at: 0.05, turn: followup == "UserPromptSubmit" ? "turn-2" : "turn-1"), into: &state)
            #expect(SessionCompletionWatcher.nextAnnouncement(pending, sessions: state.merging([:]), enabled: { _ in true }) == nil)
            pending += watcher.absorb(state.merging([:]))
            let selected = SessionCompletionWatcher.nextAnnouncement(pending, sessions: state.merging([:]), enabled: { _ in true })
            switch followup {
            case "Stop": #expect(selected?.reason == .finished)
            case "PermissionRequest": #expect(selected?.reason == .blocked)
            case "UserPromptSubmit":
                #expect(selected?.reason == .started)
                #expect(selected?.session.noticeID != pending.first?.session.noticeID)
            default: #expect(selected == nil)
            }
        }
    }

    @Test(arguments: ["claude", "codex"])
    func lateTurnIDPreservesPendingStartAndRejectsOldTurn(tool: String) throws {
        var state = HookSessionState()
        var watcher = SessionCompletionWatcher()
        func send(_ name: String, at: Double, turn: String?) {
            var hook = event(name, at: at, toolName: "Bash", call: "shell", turn: turn)
            hook.tool = tool
            absorb(hook, into: &state)
        }
        send("UserPromptSubmit", at: 0, turn: "turn-1")
        _ = watcher.absorb(state.merging([:]))
        send("Stop", at: 1, turn: "turn-1")
        _ = watcher.absorb(state.merging([:]))
        send("UserPromptSubmit", at: 2, turn: nil)
        let pending = watcher.absorb(state.merging([:]))
        #expect(pending.first?.reason == .started)
        send("Stop", at: 2.01, turn: "turn-1")
        #expect(state.records.values.first?.state == .busy)
        send("PreToolUse", at: 2.05, turn: "turn-2")
        let current = try #require(state.records.values.first)
        #expect(current.turn == "turn-2")
        #expect(current.turnStartedAt == now.timeIntervalSince1970 + 2)
        #expect(current.noticeID == pending.first?.session.noticeID)
        #expect(watcher.absorb(state.merging([:])).isEmpty)
        #expect(SessionCompletionWatcher.nextAnnouncement(pending, sessions: state.merging([:]), enabled: { _ in true })?.reason == .started)
        send("UserPromptSubmit", at: 2.1, turn: "turn-2")
        #expect(watcher.absorb(state.merging([:])).isEmpty)
        #expect(state.records.values.first?.activeTools["shell"] == "Bash")
    }

    @Test func bindingTurnDoesNotClearAnEarlierUntaggedWait() {
        var state = HookSessionState()
        var watcher = SessionCompletionWatcher()
        absorb(event("UserPromptSubmit"), into: &state)
        absorb(event("UserPromptSubmit", at: 1, turn: nil), into: &state)
        _ = watcher.absorb(state.merging([:]))
        absorb(event("PermissionRequest", at: 1.01, toolName: "Bash", call: "approval", turn: nil), into: &state)
        let waiting = watcher.absorb(state.merging([:]))
        absorb(event("PreToolUse", at: 1.02, toolName: "Read", call: "other", turn: "turn-2"), into: &state)
        #expect(state.records.values.first?.state == .waiting)
        #expect(state.records.values.first?.waiting["approval"] != nil)
        #expect(state.records.values.first?.noticeID == waiting.first?.session.noticeID)
        #expect(watcher.absorb(state.merging([:])).isEmpty)
    }

    @Test func taggedSubmissionAfterAnUnboundTurnStartsNewWork() {
        var state = HookSessionState()
        var watcher = SessionCompletionWatcher()
        absorb(event("UserPromptSubmit", turn: nil), into: &state)
        let first = watcher.absorb(state.merging([:]))
        absorb(event("Stop", at: 1, turn: nil), into: &state)
        _ = watcher.absorb(state.merging([:]))
        absorb(event("UserPromptSubmit", at: 2, turn: "turn-2"), into: &state)
        let second = watcher.absorb(state.merging([:]))
        #expect(second.first?.reason == .started)
        #expect(second.first?.session.noticeID != first.first?.session.noticeID)
    }

    @Test func displayedWaitProtectsAcrossBatchesWithoutReplayingSuppressedStarts() throws {
        var state = HookSessionState()
        var watcher = SessionCompletionWatcher()
        absorb(event("PermissionRequest", session: "waiting"), into: &state)
        let waiting = try #require(watcher.absorb(state.merging([:])).first)
        let protection = try #require(SessionCompletionWatcher.WaitingProtection(event: waiting, presented: true, duration: 5, now: now))
        absorb(event("UserPromptSubmit", at: 0.2, session: "other"), into: &state)
        let starts = watcher.absorb(state.merging([:]))
        let live = state.merging([:])
        #expect(SessionCompletionWatcher.nextAnnouncement(starts, sessions: live, protecting: protection, now: now.addingTimeInterval(0.2), enabled: { _ in true }) == nil)
        #expect(SessionCompletionWatcher.nextAnnouncement(starts, sessions: live, protecting: protection, now: now.addingTimeInterval(5), enabled: { _ in true })?.reason == .started)
        #expect(watcher.absorb(live).isEmpty)
        #expect(SessionCompletionWatcher.WaitingProtection(event: waiting, presented: false, duration: 5, now: now) == nil)
        absorb(event("Stop", at: 1, session: "other"), into: &state)
        let completion = watcher.absorb(state.merging([:]))
        let selected = try #require(SessionCompletionWatcher.nextAnnouncement(completion, sessions: state.merging([:]), protecting: protection, now: now.addingTimeInterval(1), enabled: { _ in true }))
        #expect(selected.reason == .finished)
        #expect(SessionCompletionWatcher.WaitingProtection(event: selected, presented: true, duration: 5, now: now) == nil)
        absorb(event("PermissionRequest", at: 1.1, session: "third"), into: &state)
        let newWait = watcher.absorb(state.merging([:]))
        #expect(SessionCompletionWatcher.nextAnnouncement(newWait, sessions: state.merging([:]), protecting: protection, now: now.addingTimeInterval(1.1), enabled: { _ in true })?.reason == .blocked)
    }

    @Test(arguments: ["PostToolUse", "Stop", "Interrupt", "SessionEnd"])
    func resolvedOrClosedWaitReleasesProtectionImmediately(followup: String) throws {
        var state = HookSessionState()
        var watcher = SessionCompletionWatcher()
        absorb(event("PermissionRequest", toolName: "Bash", call: "approval", session: "waiting"), into: &state)
        let waiting = try #require(watcher.absorb(state.merging([:])).first)
        let protection = try #require(SessionCompletionWatcher.WaitingProtection(event: waiting, presented: true, duration: 10, now: now))
        absorb(event(followup, at: 0.1, toolName: "Bash", call: "approval", session: "waiting"), into: &state)
        _ = watcher.absorb(state.merging([:]))
        absorb(event("UserPromptSubmit", at: 0.2, session: "other"), into: &state)
        let starts = watcher.absorb(state.merging([:]))
        #expect(SessionCompletionWatcher.nextAnnouncement(starts, sessions: state.merging([:]), protecting: protection, now: now.addingTimeInterval(0.2), enabled: { _ in true })?.reason == .started)
    }

    @Test func announcementsPrioritizeWaitingThenFinishedThenStartedAndSkipDisabledEvents() {
        var state = HookSessionState()
        var watcher = SessionCompletionWatcher()
        absorb(event("PermissionRequest", at: 0, session: "waiting"), into: &state)
        absorb(event("UserPromptSubmit", at: 1, session: "finished"), into: &state)
        absorb(event("Stop", at: 2, session: "finished"), into: &state)
        absorb(event("UserPromptSubmit", at: 3, session: "started"), into: &state)
        absorb(event("UserPromptSubmit", at: 4, session: "newest"), into: &state)
        let live = state.merging([:])
        let pending = watcher.absorb(live)
        #expect(SessionCompletionWatcher.nextAnnouncement(pending, sessions: live, enabled: { _ in true })?.reason == .blocked)
        #expect(SessionCompletionWatcher.nextAnnouncement(pending, sessions: live, enabled: { $0 != .blocked })?.reason == .finished)
        let start = SessionCompletionWatcher.nextAnnouncement(pending, sessions: live, enabled: { $0 == .started })
        #expect(start?.session.id.hasSuffix(":newest") == true)
        #expect(SessionCompletionWatcher.nextAnnouncement(pending, sessions: live, enabled: { _ in false }) == nil)
        #expect(SessionCompletionWatcher.nextAnnouncement(pending, sessions: [:], enabled: { _ in true }) == nil)
    }
}
