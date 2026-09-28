/**
 @name: 联动读取性能测量
 @Descripttion: 使用隔离快照测量重复解码、修订复用与模式切换的 CPU 和内存。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-10 18:00:00
 @LastEditTime: 2026-09-10 18:00:00
 @FilePath: Scripts/benchmark-code-switch.swift
 */
import Foundation
import Darwin
@testable import Codenotch

@main struct BridgeBenchmark {
    static func usage() -> (Double, Int64) {
        var value = rusage()
        getrusage(RUSAGE_SELF, &value)
        let cpu = Double(value.ru_utime.tv_sec + value.ru_stime.tv_sec)
            + Double(value.ru_utime.tv_usec + value.ru_stime.tv_usec) / 1_000_000
        return (cpu, Int64(value.ru_maxrss))
    }

    static func residentBytes() -> UInt64 {
        var value = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: value) / MemoryLayout<natural_t>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? value.resident_size : 0
    }

    static func main() async throws {
        let mode = CommandLine.arguments[1]
        let count = Int(CommandLine.arguments[2])!
        let iterations = 1000
        let now = Date()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("tray-snapshot-v1.json")
        let quota = CodeSwitchQuota(key: "daily", label: nil, used: 3, total: 10, unlimited: false,
                                   nextReset: nil, active: true, valueMode: "currency", unit: "USD",
                                   extra: nil, invalidMessage: nil, displayKind: "progress")
        let providers = (0..<count).map { n in
            CodeSwitchProvider(providerId: String(n), providerName: "Fixture \(n)", icon: "openai",
                               activeRequests: 1, status: "active", loading: false, updatedAt: 0, quotas: [quota], stats: nil)
        }
        var platforms = [CodeSwitchPlatform(platform: "codex", name: "Codex", icon: "openai", error: false, providers: providers)]
        let reader = CodeSwitchReader(file: file)
        let source = CodeSwitchSnapshot(version: 1, session: "benchmark", sequence: 1,
                                        heartbeatAt: now.timeIntervalSince1970 * 1000, platforms: platforms)
        try JSONEncoder().encode(source).write(to: file, options: .atomic)
        var consumerSession = ""
        if ["full", "churn", "heartbeat", "dynamic"].contains(mode) {
            _ = await reader.read(now: now, mode: .enabled, generation: 0)
            let lease = try JSONDecoder().decode(CodeSwitchSubscription.self,
                from: Data(contentsOf: dir.appendingPathComponent("codenotch-subscription-v1.json")))
            consumerSession = lease.session
            let full = CodeSwitchProviderFile(version: 1, session: source.session, revision: 1, platforms: platforms)
            try JSONEncoder().encode(full).write(to: dir.appendingPathComponent("codenotch-providers-v1.json"), options: .atomic)
            let tray = CodeSwitchSnapshot(version: 1, session: source.session, sequence: 2, heartbeatAt: source.heartbeatAt,
                platforms: [CodeSwitchPlatform(platform: "codex", name: "Codex", icon: "openai", error: false,
                                                providers: Array(providers.prefix(1)))],
                codenotch: CodeSwitchIntegrationInfo(version: 1, mode: "enabled", consumerSession: lease.session, revision: 1, error: false))
            try JSONEncoder().encode(tray).write(to: file, options: .atomic)
        }
        var legacyState = CodeSwitchSnapshotState()
        let decodesBefore = await reader.mainDecodes
        let before = usage()
        let start = ContinuousClock.now
        if mode == "decode" {
            for _ in 0..<iterations {
                _ = try FileManager.default.attributesOfItem(atPath: file.path)
                let decoded = try JSONDecoder().decode(CodeSwitchSnapshot.self, from: Data(contentsOf: file))
                legacyState.accept(decoded, now: now)
            }
        } else if mode == "cached" {
            for _ in 0..<iterations { _ = await reader.read(now: now, mode: .tray, generation: 1) }
        } else if mode == "full" {
            for _ in 0..<iterations { _ = await reader.read(now: now, mode: .enabled, generation: 1) }
        } else if mode == "heartbeat" || mode == "dynamic" {
            var revision: UInt64 = 1
            for n in 0..<iterations {
                if mode == "dynamic" && n % 10 == 0 {
                    revision += 1
                    let index = n % count
                    var changed = providers
                    changed[index] = CodeSwitchProvider(providerId: String(index), providerName: "Edited \(n)", icon: "openai",
                        activeRequests: n % 2 + 1, status: "active", loading: false, updatedAt: Double(n), quotas: [quota], stats: nil)
                    platforms = [CodeSwitchPlatform(platform: "codex", name: "Codex", icon: "openai", error: false, providers: changed,
                        sessionBindings: [CodeSwitchSessionBinding(sessionKey: HookEvent.sessionKey(tool: "codex", id: "benchmark"), providerId: String(index),
                            providerName: changed[index].providerName, icon: "openai", sequence: UInt64(n + 1), updatedAt: source.heartbeatAt)])]
                    try JSONEncoder().encode(CodeSwitchProviderFile(version: 1, session: source.session, revision: revision, platforms: platforms))
                        .write(to: dir.appendingPathComponent("codenotch-providers-v1.json"), options: .atomic)
                }
                let tray = CodeSwitchSnapshot(version: 1, session: source.session, sequence: UInt64(n + 3), heartbeatAt: source.heartbeatAt,
                    platforms: [CodeSwitchPlatform(platform: "codex", name: "Codex", icon: "openai", error: false, providers: Array(providers.prefix(1)))],
                    codenotch: CodeSwitchIntegrationInfo(version: 1, mode: "enabled", consumerSession: consumerSession, revision: revision, error: false))
                try JSONEncoder().encode(tray).write(to: file, options: .atomic)
                _ = await reader.read(now: now, mode: .enabled, generation: 1)
            }
        } else {
            for n in 1...iterations {
                _ = await reader.read(now: now, mode: .enabled, generation: UInt64(n * 2))
                await reader.reset(generation: UInt64(n * 2 + 1))
            }
        }
        let duration = start.duration(to: .now)
        let elapsed = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        let after = usage()
        let residentBeforeStop = residentBytes()
        await reader.reset(generation: UInt64.max)
        let output: [String: Any] = ["mode": mode, "providers": count, "iterations": iterations,
            "wall_ms": elapsed * 1000, "cpu_ms": (after.0 - before.0) * 1000,
            "peak_rss_bytes": after.1, "resident_before_stop_bytes": residentBeforeStop,
            "resident_after_stop_bytes": residentBytes(),
            "main_decodes": mode == "decode" ? iterations : await reader.mainDecodes - decodesBefore,
            "provider_decodes": await reader.providerDecodes]
        print(String(decoding: try JSONSerialization.data(withJSONObject: output, options: .sortedKeys), as: UTF8.self))
    }
}
