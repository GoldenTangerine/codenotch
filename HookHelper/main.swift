/**
 @name: Hooks 事件辅助程序
 @Descripttion: 从标准输入提取活动元数据并快速上报，不改变工具执行或审批结果。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-09 11:53:00
 @LastEditTime: 2026-09-09 11:53:00
 @FilePath: HookHelper/main.swift
 */
import Darwin
import Foundation

// Hooks may include entire prompts or tool results. Bound the input, never log
// it, and forward only identifiers and lifecycle metadata.
func forwardHook() {
    let args = CommandLine.arguments
    guard (args.count == 4 || (args.count == 6 && args[4] == "--socket")), args[1] == "--codenotch-hook",
          ["claude", "codex"].contains(args[2]) else { return }
    var data = Data()
    let deadline = Date().addingTimeInterval(0.2)
    var buffer = [UInt8](repeating: 0, count: 8192)
    while Date() < deadline {
        var item = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
        guard poll(&item, 1, 10) >= 0 else { return }
        guard item.revents & Int16(POLLIN | POLLHUP) != 0 else { continue }
        let count = read(STDIN_FILENO, &buffer, buffer.count)
        if count == 0 { break }
        guard count > 0, data.count + count <= 2_000_000 else { return }
        data.append(contentsOf: buffer.prefix(count))
    }
    guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let session = raw["session_id"] as? String,
          let name = raw["hook_event_name"] as? String else { return }
    let process = HookSocket.agentProcess(tool: args[2])
    let event = HookEvent(tool: args[2], configDirectory: args[3], sessionID: session,
                          turnID: raw["turn_id"] as? String, event: name,
                          toolName: raw["tool_name"] as? String,
                          callID: (raw["tool_use_id"] ?? raw["call_id"]) as? String,
                          notificationType: raw["notification_type"] as? String,
                          cwd: raw["cwd"] as? String ?? "",
                          pid: process?.0, processStartedAt: process?.1)
    guard event.valid, let encoded = try? JSONEncoder().encode(event) else { return }
    _ = HookSocket.send(encoded, to: args.count == 6 ? args[5] : HookSocket.path, retryFor: 0.15)
}

forwardHook()
exit(0)
