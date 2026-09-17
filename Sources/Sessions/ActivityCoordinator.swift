/**
 @name: 上游功能同步模块
 @Descripttion: 维护 ActivityCoordinator.swift 的上游功能与本地兼容。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-17 11:04:24
 @LastEditTime: 2026-09-17 11:04:24
 @FilePath: Sources/Sessions/ActivityCoordinator.swift
 */
import Combine
import Foundation

/// Owns session-monitor lifetimes so disconnected providers neither scan for
/// sessions nor keep usage refreshes in the fast, busy cadence.
@MainActor
final class ActivityCoordinator {
    private let monitors: [String: any AgentActivityMonitor]
    private let onSessions: (String, [AgentSession]) -> Void
    private var subscriptions: [String: AnyCancellable] = [:]
    private(set) var activeIDs: Set<String> = []

    init(monitors: [String: any AgentActivityMonitor],
         onSessions: @escaping (String, [AgentSession]) -> Void) {
        self.monitors = monitors
        self.onSessions = onSessions
    }

    var isBusy: Bool {
        activeIDs.contains { id in
            monitors[id]?.sessions.contains { $0.state == .busy } == true
        }
    }

    // 本地账户使用查询条目 ID；联动仍需要 Claude/Codex 的原生会话身份。
    static func enabledIDs(among monitorIDs: Set<String>, connected: Set<String>,
                           sources: [String: String], codeSwitchEnabled: Bool) -> Set<String> {
        let nativeIDs = Set(connected.compactMap { sources[$0] })
        return monitorIDs.filter { id in
            nativeIDs.contains(id) || (codeSwitchEnabled &&
                (id == "claude" || id.hasPrefix("claude-") ||
                 id == "codex" || id.hasPrefix("codex-")))
        }
    }

    func setConnected(_ connected: Set<String>, sources: [String: String], codeSwitchEnabled: Bool) {
        setEnabled(Self.enabledIDs(among: Set(monitors.keys), connected: connected,
                                   sources: sources, codeSwitchEnabled: codeSwitchEnabled))
    }

    func setEnabled(_ enabled: Set<String>) {
        let wanted = enabled.intersection(monitors.keys)
        for id in activeIDs.subtracting(wanted) {
            activeIDs.remove(id)
            subscriptions.removeValue(forKey: id)?.cancel()
            monitors[id]?.stop()
            onSessions(id, [])
        }
        for id in wanted.subtracting(activeIDs) {
            guard let monitor = monitors[id] else { continue }
            activeIDs.insert(id)
            subscriptions[id] = monitor.sessionsPublisher
                // 订阅时重放的缓存不代表本次启用后的状态；首次扫描建立通知基线。
                .dropFirst()
                .receive(on: RunLoop.main)
                .sink { [weak self] sessions in
                    guard let self, self.activeIDs.contains(id) else { return }
                    self.onSessions(id, sessions)
                }
            monitor.start()
        }
    }

    func stop() { setEnabled([]) }
}
