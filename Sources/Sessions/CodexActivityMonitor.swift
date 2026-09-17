/**
 @name: 会话与用量展示
 @Descripttion: 读取本地活动并提供本地化展示文案。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-08 23:00:00
 @LastEditTime: 2026-09-08 23:00:00
 @FilePath: Sources/Sessions/CodexActivityMonitor.swift
 */
import AppKit
import Combine
import Foundation

/// The small, stable part of a Codex rollout that is useful for activity.
///
/// `item_completed` is intentionally ignored: commands and other child items
/// emit it too. A turn is complete only after Codex writes `task_complete`.
struct CodexRolloutActivity {
    enum State: Equatable {
        case busy
        case success
    }

    final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var key: String?
        private var value: State?

        func state(from url: URL, read: (URL) -> State? = CodexRolloutActivity.state) -> State? {
            lock.lock()
            defer { lock.unlock() }
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let modified = attributes[.modificationDate] as? Date,
                  let size = attributes[.size] as? NSNumber else { return nil }
            let nextKey = "\(url.path)|\(modified.timeIntervalSince1970)|\(size)|\(attributes[.systemFileNumber] ?? "")"
            if key == nextKey { return value }
            value = read(url)
            key = nextKey
            return value
        }
    }

    /// One window into the end of the rollout. Rollouts run to hundreds of
    /// megabytes, so the file is walked backwards in slices rather than read
    /// whole — the same `tail` trick the Claude and Antigravity readers use.
    private static let windowBytes: UInt64 = 256 * 1024
    /// How far back a lifecycle event may be before the search gives up. A
    /// mid-turn rollout keeps its `task_started` arbitrarily far behind the
    /// writes streaming in — walking to it would read the whole file on every
    /// tick. A fresh file with no lifecycle event in its last megabyte is a
    /// turn in progress in every realistic case, and the caller maps a miss
    /// to `.busy` — the same answer the full scan would give.
    private static let maxWindows = 4

    static func state(from url: URL) -> State? {
        // A rollout can grow for days. Bound each poll and skip a partial first
        // record instead of loading the conversation into the main thread.
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard var windowEnd = try? handle.seekToEnd() else { return nil }

        // The newest lifecycle event wins, so windows are scanned newest
        // first and the first match is the answer. A window's first line is
        // cut in half by the read; the fragment is carried into the earlier
        // window, where the rest of it lives, rather than parsed half a line.
        var carried = Data()
        var windows = 0
        while windowEnd > 0, windows < maxWindows {
            windows += 1
            let windowStart = windowEnd > windowBytes ? windowEnd - windowBytes : 0
            guard (try? handle.seek(toOffset: windowStart)) != nil else { return nil }

            // `read(upToCount:)` may legally deliver fewer bytes than asked
            // for, and a window that came back short would silently lose the
            // lines its tail never reached — and join `carried` to a stretch
            // of file it does not follow. Read until the window is filled.
            // An error still fails the scan; hitting EOF early means the
            // file shrank between the seek and the read (rotation), and what
            // arrived is still contiguous with `windowStart`.
            var window = Data()
            window.reserveCapacity(Int(windowEnd - windowStart))
            while window.count < Int(windowEnd - windowStart) {
                guard let chunk = try? handle.read(
                    upToCount: Int(windowEnd - windowStart) - window.count
                ) else { return nil }
                if chunk.isEmpty { break }
                window.append(chunk)
            }
            // `carried` continues the line this window's start cut — but only
            // when the read reached `windowEnd`, where the fragment begins. A
            // short window ends somewhere else entirely, and joining the two
            // would fabricate a line out of unrelated bytes.
            if window.count == Int(windowEnd - windowStart) {
                window.append(carried)
            }

            // A window that opens on a newline was not cut mid-line: its first
            // line is whole, and the earlier window's last line is the one
            // missing its newline. Carrying anything back would glue the two.
            let startsOnALineBreak = window.first == UInt8(ascii: "\n")
            var lines = window.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
            carried = windowStart > 0 && !startsOnALineBreak && !lines.isEmpty
                ? Data(lines.removeFirst()) : Data()

            for line in lines.reversed() {
                guard let record = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                      record["type"] as? String == "event_msg",
                      let payload = record["payload"] as? [String: Any],
                      let type = payload["type"] as? String else { continue }

                switch type {
                case "task_started":
                    return .busy
                case "task_complete":
                    return .success
                case "turn_aborted":
                    // An aborted turn is not a successful completion. Returning
                    // nil lets the activity monitor drop it without announcing.
                    return nil
                default:
                    continue
                }
            }
            windowEnd = windowStart
        }
        return nil
    }
}

/// Reports whether Codex is mid-turn.
///
/// Codex does not publish a live status field, but its rollout includes
/// lifecycle events. `task_started` and `task_complete` are used when present;
/// the file's recent modification time remains the activity fallback.
///
/// **That is a heuristic, and it is labelled as one.** It cannot tell a turn
/// that is thinking from one that finished a second ago, so it errs short: the
/// ring stops spinning `staleAfter` seconds after the last write rather than
/// claiming activity it cannot see. A stale rollout is deliberately not
/// converted into `.success` or `.idle`, because inactivity is not evidence
/// that a Codex turn completed — a long-running command can be quiet too.
/// If Codex grows a real status field this should be replaced by it.
@MainActor
final class CodexActivityMonitor: ObservableObject, AgentActivityMonitor {
    @Published private(set) var sessions: [AgentSession] = []
    var sessionsPublisher: AnyPublisher<[AgentSession], Never> { $sessions.eraseToAnyPublisher() }

    private let stateStore: URL
    private let desktopStore: URL
    private let profile: CodexProfile
    private let interval: TimeInterval
    /// How long after the last write a turn is still considered in flight.
    private let staleAfter: TimeInterval
    private let usesRolloutCompletion: () -> Bool
    private var timer: Timer?
    private let storeCache = CodexStoreCache()
    private let rolloutCache = CodexRolloutActivity.Cache()
    private var scanTask: Task<Void, Never>?
    private var scanGeneration = 0

    init(
        profile: CodexProfile = .default(),
        stateStore: URL? = nil,
        desktopStore: URL? = nil,
        interval: TimeInterval = 2,
        staleAfter: TimeInterval = 8,
        usesRolloutCompletion: @escaping () -> Bool = { false }
    ) {
        self.profile = profile
        self.stateStore = stateStore ?? profile.stateURL
        self.desktopStore = desktopStore ?? profile.desktopStoreURL
        self.interval = interval
        self.staleAfter = staleAfter
        self.usesRolloutCompletion = usesRolloutCompletion
    }

    func start() {
        stop()
        rescan()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.rescan() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        scanGeneration += 1
        scanTask?.cancel()
        scanTask = nil
        sessions = []
    }

    private func rescan() {
        guard scanTask == nil else { return }
        let generation = scanGeneration
        let enabled = usesRolloutCompletion()
        let stateStore = stateStore, desktopStore = desktopStore, profile = profile
        let staleAfter = staleAfter, cache = rolloutCache, storeCache = storeCache
        scanTask = Task { [weak self] in
            let found = await Task.detached(priority: .utility) {
                Self.read(stateStore: stateStore, desktopStore: desktopStore,
                          staleAfter: staleAfter, profile: profile,
                          usesRolloutCompletion: enabled, rolloutCache: cache, storeCache: storeCache)
            }.value
            guard let self, self.scanGeneration == generation else { return }
            self.scanTask = nil
            guard !Task.isCancelled, self.usesRolloutCompletion() == enabled else { return }
            if found != self.sessions { self.sessions = found }
        }
    }

    nonisolated static func read(stateStore: URL, desktopStore: URL,
                     staleAfter: TimeInterval, now: Date = Date(),
                     profile: CodexProfile = .default(),
                     usesRolloutCompletion: Bool = false,
                     rolloutCache: CodexRolloutActivity.Cache? = nil,
                     storeCache: CodexStoreCache = CodexStoreCache()) -> [AgentSession] {
        // Both surfaces, because "Codex" is two programs that record their work
        // in different places: the CLI and the VS Code extension append to a
        // rollout, and the desktop app writes to its own catalogue. Whichever
        // moved last is the one that is working.
        var candidates: [(id: String, threadID: String, name: String, at: Date, rolloutURL: URL?)] = []

        if let rollout = storeCache.newestRollout(in: stateStore),
           let modified = (try? FileManager.default
               .attributesOfItem(atPath: rollout.url.path))?[.modificationDate] as? Date {
            candidates.append((id: "\(profile.id).\(rollout.url.lastPathComponent)", threadID: rollout.id,
                               name: profile.displayName, at: modified,
                               rolloutURL: rollout.url))
        }
        if let desktop = storeCache.newestDesktopThread(in: desktopStore) {
            candidates.append((id: "\(profile.id).desktop:\(desktop.id)", threadID: desktop.id, name: desktop.title,
                               at: desktop.updatedAt, rolloutURL: nil))
        }

        guard let newest = candidates.max(by: { $0.at < $1.at }),
              now.timeIntervalSince(newest.at) <= staleAfter else { return [] }
        var state: AgentSession.State = .busy
        if usesRolloutCompletion, let url = newest.rolloutURL {
            let activity = rolloutCache.map { $0.state(from: url) } ?? CodexRolloutActivity.state(from: url)
            if activity == .success { state = .success }
        }
        guard let session = session(id: newest.id, name: newest.name,
                                    modified: newest.at, state: state,
                                    staleAfter: staleAfter, now: now, threadID: newest.threadID)
        else { return [] }
        return [session]
    }

    /// Only work recorded within the window counts. Anything older is a
    /// finished turn, and reporting it as work in progress would be a guess
    /// dressed as a fact.
    nonisolated static func session(
        id: String, name: String, modified: Date,
        state: AgentSession.State = .busy,
        staleAfter: TimeInterval, now: Date, threadID: String? = nil
    ) -> AgentSession? {
        guard now.timeIntervalSince(modified) <= staleAfter else { return nil }

        return AgentSession(
            id: id,
            name: name,
            detail: state == .success ? L10n.t("Complete") : L10n.t("Working"),
            state: state,
            waitingFor: nil,
            since: modified,
            nativeSessionKey: threadID.flatMap {
                let id = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                return id.isEmpty || id.utf8.count > 512 ? nil : HookEvent.sessionKey(tool: "codex", id: id)
            }
        )
    }
}
