/**
 @name: Hooks 会话监测
 @Descripttion: 接收本地活动事件并按会话归并运行、等待和结束状态。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-09 11:53:00
 @LastEditTime: 2026-09-09 11:53:00
 @FilePath: Sources/Sessions/HookSessionMonitor.swift
 */
import Combine
import Darwin
import Foundation

struct HookSessionState: Equatable {
    struct Record: Equatable {
        var event: HookEvent
        var state: AgentSession.State = .idle
        var waiting: [String: String] = [:]
        var resolvedCalls: Set<String> = []
        var activeTools: [String: String] = [:]
        // Codex approval events omit call IDs. Keep all possible owners until
        // they finish, so one parallel command cannot dismiss another's wait.
        var approvalCandidates: [String: Set<String>] = [:]
        var turn: String?
        var turnStartedAt: Double?
        var retiredTurns: Set<String> = []
        var ended = false
        var interrupted = false
        var notice: SessionCompletionWatcher.Reason?
        var noticeID: String?
        var since: Double

        var sourceID: String {
            guard event.tool == "claude" else { return "codex" }
            let directory = URL(fileURLWithPath: event.configDirectory).standardizedFileURL
            if directory == ClaudeProfile.default().configDirectory { return "claude" }
            let name = directory.lastPathComponent
            if directory.deletingLastPathComponent() == ClaudeProfile.homeDirectory,
               name.hasPrefix(".claude-"), !name.dropFirst(8).isEmpty {
                return "claude-" + name.dropFirst(8)
            }
            return "hook-profile:" + event.configDirectory
        }

        var session: AgentSession {
            AgentSession(id: "hook:" + event.tool + ":" + event.configDirectory + ":" + event.sessionID,
                         name: URL(fileURLWithPath: event.cwd).lastPathComponent.isEmpty
                            ? (event.tool == "claude" ? "Claude Code" : "Codex")
                            : URL(fileURLWithPath: event.cwd).lastPathComponent,
                         detail: event.tool == "claude" ? "Claude Code · CLI" : "Codex · CLI",
                         state: state,
                         waitingFor: waiting.isEmpty ? nil : (waiting.values.contains("question")
                            ? String(localized: "Needs your answer") : String(localized: "Needs your approval")),
                         since: Date(timeIntervalSince1970: since), processID: event.pid,
                         processStartedAt: event.processStartedAt.map(Date.init(timeIntervalSince1970:)),
                         hookSessionKey: event.sessionKey,
                         hookTurnStartedAt: turnStartedAt.map(Date.init(timeIntervalSince1970:)),
                         noticeID: noticeID, notice: notice)
        }
    }

    private(set) var records: [String: Record] = [:]

    mutating func absorb(_ event: HookEvent, now: Date = Date()) {
        guard event.valid, (-5...30).contains(now.timeIntervalSince1970 - event.at) else { return }
        let key = event.tool + ":" + event.configDirectory + ":" + event.sessionID
        var record = records[key] ?? Record(event: event, since: event.at)
        guard event.at >= record.event.at,
              event.id != record.event.id || records[key] == nil else { return }
        if let turn = event.turnID, record.retiredTurns.contains(turn) { return }
        if let turn = event.turnID, let previous = record.turn, turn != previous {
            record.retiredTurns.insert(previous)
            record.waiting.removeAll()
            record.resolvedCalls.removeAll()
            record.activeTools.removeAll()
            record.approvalCandidates.removeAll()
            record.turnStartedAt = nil
            record.state = .idle
            record.ended = false
            record.interrupted = false
            record.notice = nil
            record.noticeID = nil
        }
        if let turn = event.turnID { record.turn = turn }
        let previous = record.state
        let wasEnded = record.ended
        let call = event.callID ?? event.toolName ?? "approval"
        let isQuestion = ["AskUserQuestion", "request_user_input", "request_user_input_async"].contains(event.toolName ?? "")
        switch event.event {
        case "SessionStart":
            guard records[key] == nil || record.ended else { return }
            record.state = .idle
            record.ended = false
            record.interrupted = false
        case "UserPromptSubmit":
            record.waiting.removeAll()
            record.resolvedCalls.removeAll()
            record.activeTools.removeAll()
            record.approvalCandidates.removeAll()
            record.turnStartedAt = event.at
            record.state = .busy
            record.ended = false
            record.interrupted = false
            record.notice = nil
            record.noticeID = nil
        case "PreToolUse", "PermissionRequest":
            guard !record.ended, !record.interrupted else { return }
            if event.event == "PreToolUse", let id = event.callID, let tool = event.toolName,
               !record.resolvedCalls.contains(id) {
                record.activeTools[id] = tool
            }
            if event.event == "PermissionRequest", event.callID == nil {
                let tool = event.toolName ?? "approval"
                record.approvalCandidates[tool, default: []].formUnion(record.activeTools.filter { $0.value == tool }.keys)
                record.waiting["approval:" + tool] = isQuestion ? "question" : "approval"
            } else if (isQuestion || event.event == "PermissionRequest"), event.callID == nil || !record.resolvedCalls.contains(call) {
                record.waiting[call] = isQuestion ? "question" : "approval"
            }
            record.state = record.waiting.isEmpty ? .busy : .waiting
        case "Notification":
            guard !record.ended, !record.interrupted, ["permission_prompt", "elicitation_dialog"].contains(event.notificationType ?? "") else { return }
            // Notification has no call id. Do not add a second blocker when a
            // PermissionRequest/AskUserQuestion already owns this wait.
            if record.waiting.isEmpty { record.waiting["notification"] = "approval" }
            record.state = .waiting
        case "PostToolUse", "PostToolUseFailure":
            guard !record.ended, !record.interrupted else { return }
            record.waiting.removeValue(forKey: call)
            if let tool = event.toolName, var candidates = record.approvalCandidates[tool] {
                if let id = event.callID { candidates.remove(id) }
                if candidates.isEmpty {
                    record.waiting.removeValue(forKey: "approval:" + tool)
                    record.approvalCandidates.removeValue(forKey: tool)
                } else {
                    record.approvalCandidates[tool] = candidates
                }
            }
            if let id = event.callID { record.activeTools.removeValue(forKey: id) }
            record.waiting.removeValue(forKey: "notification")
            if event.callID != nil { record.resolvedCalls.insert(call) }
            record.state = record.waiting.isEmpty ? .busy : .waiting
        case "Stop":
            guard !record.ended, !record.interrupted else { return }
            record.waiting.removeAll()
            record.activeTools.removeAll()
            record.approvalCandidates.removeAll()
            record.state = .idle
        case "Interrupt", "SessionEnd":
            record.waiting.removeAll()
            record.activeTools.removeAll()
            record.approvalCandidates.removeAll()
            record.state = .idle
            record.ended = event.event == "SessionEnd"
            record.interrupted = true
            record.notice = nil
            record.noticeID = nil
        default: return
        }
        record.event = event
        if record.state != previous || wasEnded { record.since = event.at }
        if record.state == .waiting && previous != .waiting {
            record.notice = .blocked
            record.noticeID = event.id
        } else if event.event == "Stop", previous == .busy || previous == .waiting {
            record.notice = .finished
            record.noticeID = event.id
        }
        if record.state == .busy {
            record.notice = nil
            record.noticeID = nil
        }
        records[key] = record
    }

    mutating func prune(now: Date = Date()) {
        for key in records.keys {
            if let record = records[key], record.state == .idle, record.noticeID != nil,
               now.timeIntervalSince1970 - record.since >= 15 {
                records[key]?.noticeID = nil
                records[key]?.notice = nil
            }
        }
        records = records.filter { _, record in
            if let pid = record.event.pid, let started = record.event.processStartedAt {
                guard let actual = HookSocket.process(pid)?.started else { return false }
                return abs(actual - started) < 0.01
            }
            return now.timeIntervalSince1970 - record.event.at < 86_400
        }
    }

    mutating func remove(tool: String, directory: String) {
        records = records.filter { $0.value.event.tool != tool || $0.value.event.configDirectory != directory }
    }

    mutating func reconcile(_ native: [String: [AgentSession]]) {
        records = records.filter { _, record in
            !(native[record.sourceID] ?? []).contains { session in
                Self.supersedes(session, record: record)
            }
        }
    }

    private static func matches(_ session: AgentSession, record: Record) -> Bool {
        guard session.hookSessionKey == nil else { return false }
        if record.event.tool == "codex" { return session.id.contains(record.event.sessionID) }
        return session.processID != nil && session.processID == record.event.pid
    }

    private static func supersedes(_ session: AgentSession, record: Record) -> Bool {
        // Codex log writes can belong to a parallel tool while a question is
        // still open. Only Claude's explicit status can supersede a wait.
        matches(session, record: record) && session.state != record.state
            && (record.event.tool == "claude" || record.state != .waiting)
            && session.since.timeIntervalSince1970 > record.event.at + 2
    }

    func merging(_ native: [String: [AgentSession]]) -> [String: [AgentSession]] {
        var result = native
        for record in records.values {
            let source = record.sourceID
            let matches: (AgentSession) -> Bool = { session in
                Self.matches(session, record: record)
            }
            // A newer native transition can recover a dropped hook. Mere log
            // silence is not evidence that a user has answered a question.
            if (native[source] ?? []).contains(where: {
                Self.supersedes($0, record: record)
            }) { continue }
            result[source] = (result[source] ?? []).filter { session in
                !matches(session)
            }
            if !record.ended { result[source, default: []].append(record.session) }
        }
        return result.mapValues { $0.sorted { $0.id < $1.id } }
    }
}

@MainActor
final class HookSessionMonitor: ObservableObject {
    @Published private(set) var state = HookSessionState()
    @Published private(set) var lastEvents: [String: Date] = [:]
    @Published private(set) var error: String?
    private var source: DispatchSourceRead?
    private var timer: Timer?
    private let path: String
    private var ownsSocket = false
    private var disabledTargets: Set<String> = []

    func reconcile(_ native: [String: [AgentSession]]) {
        var next = state
        next.reconcile(native)
        if next != state { state = next }
    }

    func setEnabled(_ enabled: Bool, tool: String, directory: String) {
        let key = tool + ":" + directory
        if enabled { disabledTargets.remove(key) }
        else {
            disabledTargets.insert(key)
            var next = state
            next.remove(tool: tool, directory: directory)
            if next != state { state = next }
            lastEvents.removeValue(forKey: key)
        }
    }

    init(path: String = HookSocket.path) { self.path = path }

    func start() {
        guard source == nil else { return }
        do {
            let directory = (path as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            var info = stat()
            guard lstat(directory, &info) == 0, info.st_uid == getuid(),
                  info.st_mode & S_IFMT == S_IFDIR, info.st_mode & 0o077 == 0 else { throw CocoaError(.fileWriteNoPermission) }
            if FileManager.default.fileExists(atPath: path) {
                guard !HookSocket.send(Data(), to: path), [ECONNREFUSED, ENOENT].contains(errno) else {
                    throw CocoaError(.fileWriteFileExists)
                }
                guard lstat(path, &info) == 0, info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFSOCK else {
                    throw CocoaError(.fileWriteNoPermission)
                }
                guard unlink(path) == 0 else { throw CocoaError(.fileWriteUnknown) }
            }
            let fd = socket(AF_UNIX, SOCK_DGRAM, 0)
            guard fd >= 0 else { throw CocoaError(.fileWriteUnknown) }
            guard var address = HookSocket.address(path) else { close(fd); throw CocoaError(.fileWriteInvalidFileName) }
            let bound = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard bound == 0 else { close(fd); throw CocoaError(.fileWriteUnknown) }
            ownsSocket = true
            _ = chmod(path, 0o600)
            _ = fcntl(fd, F_SETFL, O_NONBLOCK)
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.receive(fd) }
            }
            source.setCancelHandler { close(fd) }
            self.source = source
            source.resume()
            error = nil
            let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    var next = self.state
                    next.prune()
                    if self.state != next { self.state = next }
                }
            }
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
        } catch {
            self.error = String(localized: "Could not start hook listener")
        }
    }

    private func receive(_ fd: Int32) {
        var buffer = [UInt8](repeating: 0, count: HookSocket.maxBytes + 1)
        for _ in 0..<128 {
            let size = recv(fd, &buffer, buffer.count, 0)
            if size < 0 { break }
            guard size > 0, size <= HookSocket.maxBytes,
                  let event = try? JSONDecoder().decode(HookEvent.self, from: Data(buffer.prefix(size))), event.valid else { continue }
            guard !disabledTargets.contains(event.tool + ":" + event.configDirectory) else { continue }
            var next = state
            next.absorb(event)
            guard next != state else { continue }
            guard next.records.values.contains(where: { $0.event.id == event.id }) else { continue }
            state = next
            lastEvents[event.tool + ":" + event.configDirectory] = Date(timeIntervalSince1970: event.at)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        source?.cancel()
        source = nil
        if ownsSocket { unlink(path); ownsSocket = false }
    }
}
