/**
 @name: 会话供应商关联
 @Descripttion: 将真实会话映射到联动供应商或独立工具入口。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-09 12:03:00
 @LastEditTime: 2026-09-09 12:03:00
 @FilePath: Sources/Sessions/ActivityRouting.swift
 */
import Foundation

struct ActivityRouting {
    var snapshots: [ProviderSnapshot]
    var sessions: [String: [AgentSession]] = [:]

    init(local: [ProviderSnapshot], linked: [ProviderSnapshot], sources: [String: String],
         sessions native: [String: [AgentSession]], bindings: [String: CodeSwitchSessionLink], now: Date = Date()) {
        snapshots = local + linked
        var visible = Set(snapshots.map(\.id))
        for source in native.keys.sorted() {
            let localIDs = local.filter { sources[$0.id] == source }.map(\.id)
            for session in native[source] ?? [] {
                let needsEntrance = session.state != .idle || (session.noticeID != nil && now.timeIntervalSince(session.since) < 15)
                if let key = session.hookSessionKey, let link = bindings[key],
                   session.hookTurnStartedAt.map({ link.binding.updatedAt >= ($0.timeIntervalSince1970 * 1000).rounded(.down) }) ?? false {
                    let id = link.snapshot.id
                    sessions[id, default: []].append(session)
                    if needsEntrance, visible.insert(id).inserted {
                        snapshots.append(link.snapshot)
                    }
                } else if !localIDs.isEmpty {
                    for id in localIDs { sessions[id, default: []].append(session) }
                } else if session.hookSessionKey != nil {
                    let id = "activity:" + source
                    sessions[id, default: []].append(session)
                    if needsEntrance, visible.insert(id).inserted {
                        let claude = source != "codex"
                        snapshots.append(ProviderSnapshot(id: id, displayName: claude ? "Claude Code" : "Codex CLI",
                                                          glyph: claude ? .claude : .openai, fidelity: .derived,
                                                          status: .ok, windows: [], headlineID: nil))
                    }
                }
            }
        }
    }

    func providerID(for session: AgentSession) -> String? {
        snapshots.first { snapshot in sessions[snapshot.id]?.contains(where: { $0.id == session.id }) == true }?.id
    }
}
