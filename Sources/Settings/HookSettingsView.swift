/**
 @name: Hooks 通知设置界面
 @Descripttion: 展示 CLI hooks 安装、修复和事件连接状态。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-09 11:58:00
 @LastEditTime: 2026-09-09 11:58:00
 @FilePath: Sources/Settings/HookSettingsView.swift
 */
import SwiftUI

struct HookSettingsView: View {
    @ObservedObject var hooks: HookSettings

    var body: some View {
        Section("Hooks") {
            ForEach(hooks.targets) { target in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(target.title).fontWeight(.medium)
                        Spacer()
                        Text(hooks.installed.contains(target.id) ? String(localized: "Installed") : String(localized: "Not installed"))
                            .foregroundStyle(.secondary)
                    }
                    Text(target.file.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    Text(target.cliDetected ? String(localized: "CLI detected") : String(localized: "CLI not found in standard locations"))
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        if let date = hooks.lastEvents[target.id] {
                            Text("Last event: \(date.formatted(date: .omitted, time: .standard))")
                        } else { Text("No events received yet") }
                        Spacer()
                        Button(hooks.present.contains(target.id) ? String(localized: "Repair hooks") : String(localized: "Install hooks")) {
                            hooks.change(target, installing: true)
                        }
                        if hooks.present.contains(target.id) {
                            Button("Uninstall hooks") { hooks.change(target, installing: false) }
                        }
                    }
                    .font(.caption)
                    if let error = hooks.errors[target.id] {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                    if target.tool == "codex" {
                        Text("After installing or repairing, open /hooks in Codex CLI and review the Codenotch hooks.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            if let error = hooks.listenerError { Text(error).foregroundStyle(.red) }
            HStack {
                Menu("Add configuration directory") {
                    Button("Claude Code") { hooks.addDirectory(tool: "claude") }
                    Button("Codex CLI") { hooks.addDirectory(tool: "codex") }
                }
                Spacer()
                Button("Check hooks") { hooks.refresh() }
            }
            Text("Start a new CLI session after installation. Hooks report activity only; answer questions and approve requests in your CLI.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
