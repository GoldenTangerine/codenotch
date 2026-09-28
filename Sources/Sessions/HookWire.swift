/**
 @name: Hooks 本地通信协议
 @Descripttion: 在命令行辅助程序和应用之间传递不含正文的活动事件。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-09 11:53:00
 @LastEditTime: 2026-09-09 11:53:00
 @FilePath: Sources/Sessions/HookWire.swift
 */
import CryptoKit
import Darwin
import Foundation

struct HookEvent: Codable, Equatable {
    var version = 1
    var id = UUID().uuidString
    var tool: String
    var configDirectory: String
    var sessionID: String
    var turnID: String?
    var event: String
    var toolName: String?
    var callID: String?
    var notificationType: String?
    var cwd: String
    var pid: Int32?
    var processStartedAt: Double?
    var at: Double = Date().timeIntervalSince1970

    var sessionKey: String { Self.sessionKey(tool: tool, id: sessionID) }
    static func sessionKey(tool: String, id: String) -> String {
        SHA256.hash(data: Data((tool + "\n" + id.trimmingCharacters(in: .whitespacesAndNewlines)).utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    var valid: Bool {
        version == 1 && ["claude", "codex"].contains(tool) && !sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && sessionID.utf8.count <= 512
            && !id.isEmpty && at.isFinite && cwd.utf8.count <= 4096
            && configDirectory.hasPrefix("/") && configDirectory.utf8.count <= 4096
            && (processStartedAt == nil || processStartedAt!.isFinite)
            && (pid == nil || pid! > 1)
    }
}

enum HookSocket {
    static var directory: String { "/tmp/codenotch-hooks-\(getuid())" }
    static var path: String { directory + "/events.sock" }
    static let maxBytes = 16_384

    static func address(_ path: String) -> sockaddr_un? {
        var result = sockaddr_un()
        let bytes = Array(path.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: result.sun_path) else { return nil }
        result.sun_family = sa_family_t(AF_UNIX)
        result.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &result.sun_path) { $0.copyBytes(from: bytes) }
        return result
    }

    static func send(_ data: Data, to path: String = path, retryFor: TimeInterval = 0) -> Bool {
        guard data.count <= maxBytes, var address = address(path) else { return false }
        let fd = socket(AF_UNIX, SOCK_DGRAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        _ = fcntl(fd, F_SETFL, O_NONBLOCK)
        let deadline = ProcessInfo.processInfo.systemUptime + retryFor
        repeat {
            let sent = data.withUnsafeBytes { bytes in
                withUnsafePointer(to: &address) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        sendto(fd, bytes.baseAddress, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == bytes.count
                    }
                }
            }
            if sent { return true }
            guard [EAGAIN, ENOBUFS, EINTR].contains(errno),
                  ProcessInfo.processInfo.systemUptime < deadline else { return false }
            // Only the short-lived helper opts into retrying a full queue.
            usleep(5_000)
        } while ProcessInfo.processInfo.systemUptime < deadline
        return false
    }

    static func process(_ pid: Int32) -> (parent: Int32, name: String, started: Double)? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let name = withUnsafeBytes(of: &info.kp_proc.p_comm) { bytes in
            String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        let start = info.kp_proc.p_starttime
        return (info.kp_eproc.e_ppid, name, Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000)
    }

    static func agentProcess(tool: String) -> (Int32, Double)? {
        var pid = getppid()
        for _ in 0..<12 {
            guard pid > 1, let info = process(pid) else { break }
            if info.name == tool || info.name.hasPrefix(tool + "-") {
                return (pid, info.started)
            }
            guard pid != info.parent else { break }
            pid = info.parent
        }
        return nil
    }
}
