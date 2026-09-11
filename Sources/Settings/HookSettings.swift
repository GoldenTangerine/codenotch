/**
 @name: Hooks 设置管理
 @Descripttion: 检测、合并安装及卸载两种 CLI 的通知 hooks。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-09 11:58:00
 @LastEditTime: 2026-09-09 11:58:00
 @FilePath: Sources/Settings/HookSettings.swift
 */
import AppKit
import Combine
import Foundation

struct HookTarget: Identifiable, Equatable {
    let tool: String
    let directory: URL
    var id: String { tool + ":" + directory.path }
    var title: String { tool == "claude" ? "Claude Code" : "Codex CLI" }
    var file: URL { directory.appendingPathComponent(tool == "claude" ? "settings.json" : "hooks.json") }
    var cliDetected: Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + ["/opt/homebrew/bin", "/usr/local/bin", home + "/.local/bin", home + "/.cargo/bin"]
        return paths.contains { FileManager.default.isExecutableFile(atPath: $0 + "/" + tool) }
    }
}

enum HookInstaller {
    enum Failure: LocalizedError {
        case invalidConfig, missingHelper
        var errorDescription: String? {
            switch self {
            case .invalidConfig: return L10n.t("Hook configuration is invalid; the file was not changed")
            case .missingHelper: return L10n.t("Hook helper is missing; reinstall Codenotch")
            }
        }
    }

    static func events(for tool: String) -> [String] {
        let common = ["SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop"]
        return common + (tool == "claude" ? ["PostToolUseFailure", "Notification"] : ["Interrupt"])
    }

    static func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    static func command(target: HookTarget, helper: URL) -> String {
        quote(helper.path) + " --codenotch-hook " + quote(target.tool) + " " + quote(target.directory.path)
    }

    static func owns(_ hook: [String: Any], target: HookTarget) -> Bool {
        guard let command = hook["command"] as? String else { return false }
        return command.hasPrefix("'") && command.contains("/HookHelper' --codenotch-hook " + quote(target.tool) + " ")
            && command.hasSuffix(" " + quote(target.directory.path))
    }

    static func read(_ target: HookTarget) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: target.file.path) else { return [:] }
        let attributes = try FileManager.default.attributesOfItem(atPath: target.file.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= 2_000_000,
              let object = try JSONSerialization.jsonObject(with: Data(contentsOf: target.file)) as? [String: Any]
        else { throw Failure.invalidConfig }
        return object
    }

    static func merged(_ original: [String: Any], target: HookTarget, helper: URL?, installing: Bool) throws -> [String: Any] {
        var root = original
        if let value = root["hooks"], !(value is [String: Any]) { throw Failure.invalidConfig }
        var events = root["hooks"] as? [String: Any] ?? [:]
        for (name, value) in events {
            guard let groups = value as? [[String: Any]] else { throw Failure.invalidConfig }
            var retained: [[String: Any]] = []
            for var group in groups {
                guard let hooks = group["hooks"] as? [[String: Any]] else { throw Failure.invalidConfig }
                let keep = hooks.filter { !owns($0, target: target) }
                if keep.count == hooks.count { retained.append(group) }
                else if !keep.isEmpty { group["hooks"] = keep; retained.append(group) }
            }
            if retained.isEmpty { events.removeValue(forKey: name) }
            else { events[name] = retained }
        }
        if installing {
            guard let helper else { throw Failure.missingHelper }
            for name in self.events(for: target.tool) {
                var groups = events[name] as? [[String: Any]] ?? []
                groups.append(["hooks": [["type": "command", "command": command(target: target, helper: helper), "timeout": 1]]])
                events[name] = groups
            }
        }
        if events.isEmpty { root.removeValue(forKey: "hooks") }
        else { root["hooks"] = events }
        return root
    }

    static func isInstalled(_ target: HookTarget, helper: URL) throws -> Bool {
        let original = try read(target)
        let wanted = try merged(original, target: target, helper: helper, installing: true)
        return NSDictionary(dictionary: original).isEqual(to: wanted)
    }

    static func hasEntries(_ target: HookTarget) throws -> Bool {
        let root = try read(target)
        let stripped = try merged(root, target: target, helper: nil, installing: false)
        return !NSDictionary(dictionary: root).isEqual(to: stripped)
    }

    static func write(_ target: HookTarget, helper: URL?, installing: Bool) throws {
        if installing, helper == nil || !FileManager.default.isExecutableFile(atPath: helper!.path) { throw Failure.missingHelper }
        let original = try read(target)
        let next = try merged(original, target: target, helper: helper, installing: installing)
        guard !NSDictionary(dictionary: original).isEqual(to: next) else { return }
        let data = try JSONSerialization.data(withJSONObject: next, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try FileManager.default.createDirectory(at: target.directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        // Re-read immediately before replacement rather than overwriting a
        // tool's concurrent configuration update with our earlier snapshot.
        guard NSDictionary(dictionary: try read(target)).isEqual(to: original) else { throw Failure.invalidConfig }
        let permissions = (try? FileManager.default.attributesOfItem(atPath: target.file.path))?[.posixPermissions] ?? 0o600
        try (data + Data("\n".utf8)).write(to: target.file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: target.file.path)
    }
}

@MainActor
final class HookSettings: ObservableObject {
    @Published private(set) var targets: [HookTarget] = []
    @Published private(set) var installed: Set<String> = []
    @Published private(set) var present: Set<String> = []
    @Published private(set) var errors: [String: String] = [:]
    @Published private(set) var lastEvents: [String: Date] = [:]
    @Published private(set) var listenerError: String?
    private let defaults: UserDefaults
    private let monitor: HookSessionMonitor
    let helper: URL
    private var cancellables = Set<AnyCancellable>()

    init(monitor: HookSessionMonitor, defaults: UserDefaults = .standard,
         helper: URL = Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("HookHelper")) {
        self.defaults = defaults
        self.monitor = monitor
        self.helper = helper
        monitor.$lastEvents.assign(to: &$lastEvents)
        monitor.$error.assign(to: &$listenerError)
        refresh()
    }

    func refresh() {
        var found = ClaudeProfile.discover().map { HookTarget(tool: "claude", directory: $0.configDirectory.standardizedFileURL) }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let codex = ProcessInfo.processInfo.environment["CODEX_HOME"].flatMap { $0.isEmpty ? nil : $0 }
        found.append(HookTarget(tool: "codex", directory: URL(fileURLWithPath: codex.map { ($0 as NSString).expandingTildeInPath } ?? home.appendingPathComponent(".codex").path).standardizedFileURL))
        for tool in ["claude", "codex"] {
            for path in defaults.stringArray(forKey: "hookDirectories." + tool) ?? [] {
                found.append(HookTarget(tool: tool, directory: URL(fileURLWithPath: path).standardizedFileURL))
            }
        }
        var seen = Set<String>()
        targets = found.filter { seen.insert($0.id).inserted }
        installed.removeAll(); present.removeAll(); errors.removeAll()
        for target in targets {
            do {
                if try HookInstaller.hasEntries(target) { present.insert(target.id) }
                if try HookInstaller.isInstalled(target, helper: helper) { installed.insert(target.id) }
            } catch { errors[target.id] = L10n.t("Hook configuration could not be read") }
        }
    }

    func change(_ target: HookTarget, installing: Bool) {
        do {
            try HookInstaller.write(target, helper: helper, installing: installing)
            monitor.setEnabled(installing, tool: target.tool, directory: target.directory.path)
            if installing { monitor.start() }
            refresh()
        } catch { errors[target.id] = (error as? HookInstaller.Failure)?.errorDescription ?? L10n.t("Hook configuration could not be saved") }
    }

    func addDirectory(tool: String) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.showsHiddenFiles = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let directory = panel.url?.standardizedFileURL else { return }
        let key = "hookDirectories." + tool
        var paths = defaults.stringArray(forKey: key) ?? []
        if !paths.contains(directory.path) { paths.append(directory.path) }
        defaults.set(paths, forKey: key)
        refresh()
    }
}
