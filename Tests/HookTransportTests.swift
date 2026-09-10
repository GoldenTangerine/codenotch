/**
 @name: Hooks 通信回归测试
 @Descripttion: 在隔离目录中验证真实 Unix socket 接收和安装写入。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-09 12:25:00
 @LastEditTime: 2026-09-09 12:25:00
 @FilePath: Tests/HookTransportTests.swift
 */
import Foundation
import Darwin
import Testing
@testable import Codenotch

@Suite struct HookTransportTests {
    @MainActor @Test func receivesDatagramsAndDoesNotStealAnotherListener() async throws {
        let directory = URL(fileURLWithPath: "/tmp/codenotch-test-" + UUID().uuidString)
        let path = directory.appendingPathComponent("events.sock").path
        let monitor = HookSessionMonitor(path: path)
        monitor.start()
        defer { monitor.stop(); try? FileManager.default.removeItem(at: directory) }
        #expect(monitor.error == nil)
        let duplicate = HookSessionMonitor(path: path)
        duplicate.start()
        #expect(duplicate.error != nil)
        duplicate.stop()
        let event = HookEvent(tool: "codex", configDirectory: directory.path, sessionID: "socket-test", event: "PermissionRequest", toolName: "Bash", callID: "approval", cwd: "/tmp/project")
        #expect(HookSocket.send(try JSONEncoder().encode(event), to: path))
        for _ in 0..<30 {
            if !monitor.state.records.isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(monitor.state.merging([:])["codex"]?.first?.state == .waiting)
        #expect(monitor.lastEvents["codex:" + directory.path] != nil)
        monitor.stop()
        #expect(!HookSocket.send(Data("{}".utf8), to: path))
    }

    @Test func installerWritesOnlySelectedProfileAndPreservesPermissions() throws {
        let directory = URL(fileURLWithPath: "/tmp/codenotch-config-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = HookTarget(tool: "codex", directory: directory)
        let helper = directory.appendingPathComponent("HookHelper")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: helper)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        let original: [String: Any] = ["description": "keep", "hooks": ["Stop": [["hooks": [["type": "command", "command": "echo existing"]]]]]]
        try JSONSerialization.data(withJSONObject: original).write(to: target.file)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: target.file.path)
        try HookInstaller.write(target, helper: helper, installing: true)
        #expect(try HookInstaller.isInstalled(target, helper: helper))
        let first = try Data(contentsOf: target.file)
        try HookInstaller.write(target, helper: helper, installing: true)
        #expect(try Data(contentsOf: target.file) == first)
        #expect((try FileManager.default.attributesOfItem(atPath: target.file.path)[.posixPermissions] as? NSNumber)?.intValue == 0o640)
        try HookInstaller.write(target, helper: nil, installing: false)
        #expect(NSDictionary(dictionary: try HookInstaller.read(target)).isEqual(to: original))
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("config.toml").path))
    }

    @MainActor @Test func disabledTargetClearsStateAndRejectsLateEvents() async throws {
        let directory = URL(fileURLWithPath: "/tmp/codenotch-disable-" + UUID().uuidString)
        let path = directory.appendingPathComponent("events.sock").path
        let monitor = HookSessionMonitor(path: path)
        monitor.start()
        defer { monitor.stop(); try? FileManager.default.removeItem(at: directory) }
        func send(_ session: String) throws {
            let event = HookEvent(tool: "codex", configDirectory: directory.path, sessionID: session,
                                  event: "PermissionRequest", toolName: "Bash", cwd: "/tmp")
            #expect(HookSocket.send(try JSONEncoder().encode(event), to: path))
        }
        try send("before")
        for _ in 0..<50 {
            if !monitor.state.records.isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(monitor.state.records.count == 1)
        monitor.setEnabled(false, tool: "codex", directory: directory.path)
        #expect(monitor.state.records.isEmpty)
        #expect(monitor.lastEvents.isEmpty)
        try send("late")
        try await Task.sleep(for: .milliseconds(100))
        #expect(monitor.state.records.isEmpty)
        monitor.setEnabled(true, tool: "codex", directory: directory.path)
        try send("reinstalled")
        for _ in 0..<50 {
            if !monitor.state.records.isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(monitor.state.records.values.first?.event.sessionID == "reinstalled")
    }

    @MainActor @Test func helperForwardsCodexProtocolWithoutInventingApprovalCallID() async throws {
        let directory = URL(fileURLWithPath: "/tmp/codenotch-wire-" + UUID().uuidString)
        let path = directory.appendingPathComponent("events.sock").path
        let monitor = HookSessionMonitor(path: path)
        monitor.start()
        defer { monitor.stop(); try? FileManager.default.removeItem(at: directory) }
        let helper = ProcessInfo.processInfo.environment["CODENOTCH_TEST_HOOK_HELPER"].map(URL.init(fileURLWithPath:))
            ?? Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("HookHelper")
        #expect(FileManager.default.isExecutableFile(atPath: helper.path))
        for name in ["UserPromptSubmit", "PreToolUse", "PermissionRequest", "PostToolUse", "Stop"] {
            var payload: [String: Any] = ["session_id": "wire", "turn_id": "turn", "cwd": "/tmp",
                                          "hook_event_name": name, "permission_mode": "default"]
            if ["PreToolUse", "PermissionRequest", "PostToolUse"].contains(name) {
                payload["tool_name"] = "Bash"
                payload["tool_input"] = ["command": "synthetic-private-input"]
            }
            if ["PreToolUse", "PostToolUse"].contains(name) { payload["tool_use_id"] = "shell" }
            if name == "PostToolUse" {
                payload["tool_use_id"] = NSNull()
                payload["call_id"] = "shell"
            }
            let process = Process()
            process.executableURL = helper
            process.arguments = ["--codenotch-hook", "codex", directory.path, "--socket", path]
            let input = Pipe()
            let output = Pipe()
            process.standardInput = input
            process.standardOutput = output
            process.standardError = output
            try process.run()
            try input.fileHandleForWriting.write(contentsOf: JSONSerialization.data(withJSONObject: payload))
            try input.fileHandleForWriting.close()
            process.waitUntilExit()
            #expect(process.terminationStatus == 0)
            #expect(output.fileHandleForReading.readDataToEndOfFile().isEmpty)
            for _ in 0..<50 {
                if monitor.state.records.values.first?.event.event == name { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            let record = try #require(monitor.state.records.values.first)
            #expect(record.event.event == name)
            if name == "PermissionRequest" {
                #expect(record.event.callID == nil)
                #expect(record.state == .waiting)
            }
            if name == "PostToolUse" { #expect(record.state == .busy) }
            let forwarded = try JSONEncoder().encode(record.event)
            #expect(!String(decoding: forwarded, as: UTF8.self).contains("synthetic-private-input"))
        }
        #expect(monitor.state.records.values.first?.notice == .finished)
    }

    @MainActor @Test func fullSocketQueueCanRecoverWithinHelperRetryBudget() async throws {
        let directory = URL(fileURLWithPath: "/tmp/codenotch-pressure-" + UUID().uuidString)
        let path = directory.appendingPathComponent("events.sock").path
        let monitor = HookSessionMonitor(path: path)
        monitor.start()
        defer { monitor.stop(); try? FileManager.default.removeItem(at: directory) }
        #expect(monitor.error == nil)
        var filled = false
        for _ in 0..<1024 {
            if !HookSocket.send(Data(repeating: 0, count: 1024), to: path) {
                filled = true
                break
            }
        }
        #expect(filled)
        let event = HookEvent(tool: "codex", configDirectory: directory.path, sessionID: "retry",
                              event: "PermissionRequest", toolName: "Bash", cwd: "/tmp")
        let data = try JSONEncoder().encode(event)
        let sender = Task.detached { HookSocket.send(data, to: path, retryFor: 0.15) }
        // Hold the receiver briefly to exercise a full queue, then let its
        // main-queue dispatch source drain while the helper retries.
        usleep(20_000)
        #expect(await sender.value)
        for _ in 0..<50 {
            if !monitor.state.records.isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(monitor.state.records.values.first?.event.id == event.id)
    }
}
