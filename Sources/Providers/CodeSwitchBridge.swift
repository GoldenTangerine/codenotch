/**
 @name: Code Switch 联动
 @Descripttion: 读取专用展示快照并维护独立于本地查询的动态供应商。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-08 17:00:00
 @LastEditTime: 2026-09-08 17:00:00
 @FilePath: Sources/Providers/CodeSwitchBridge.swift
 */
import Foundation
import Combine
import Darwin

struct CodeSwitchSnapshot: Codable {
    let version: Int
    let session: String
    let sequence: UInt64
    let heartbeatAt: Double
    let platforms: [CodeSwitchPlatform]
    var codenotch: CodeSwitchIntegrationInfo? = nil

    var heartbeat: Date { Date(timeIntervalSince1970: heartbeatAt / 1000) }
}

extension CodeSwitchSnapshot {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        session = try values.decode(String.self, forKey: .session)
        sequence = try values.decode(UInt64.self, forKey: .sequence)
        heartbeatAt = try values.decode(Double.self, forKey: .heartbeatAt)
        platforms = try values.decode([CodeSwitchPlatform].self, forKey: .platforms)
        // Optional protocol extensions must not invalidate a usable tray snapshot.
        codenotch = try? values.decode(CodeSwitchIntegrationInfo.self, forKey: .codenotch)
    }
}

struct CodeSwitchPlatform: Codable, Equatable {
    let platform: String
    let name: String
    let icon: String
    let error: Bool
    let providers: [CodeSwitchProvider]
    var sessionBindings: [CodeSwitchSessionBinding]? = nil
}

struct CodeSwitchSessionBinding: Codable, Equatable {
    let sessionKey: String
    let providerId: String
    let providerName: String
    let icon: String
    let sequence: UInt64
    let updatedAt: Double

    func snapshot(platform: CodeSwitchPlatform, retaining previous: ProviderSnapshot? = nil) -> ProviderSnapshot {
        CodeSwitchProvider(providerId: providerId, providerName: providerName, icon: icon,
                           activeRequests: 0, status: "session", loading: false, updatedAt: updatedAt,
                           quotas: previous?.linked?.provider.quotas ?? [], stats: previous?.linked?.provider.stats,
                           quotaState: previous?.linked?.provider.quotaState,
                           quotaAutoDisabled: previous?.linked?.provider.quotaAutoDisabled).snapshot(platform: platform)
    }
}

struct CodeSwitchSessionLink: Equatable {
    let platform: String
    let binding: CodeSwitchSessionBinding
    let snapshot: ProviderSnapshot
}

struct CodeSwitchProvider: Codable, Equatable {
    let providerId: String
    let providerName: String
    let icon: String
    let activeRequests: Int
    let status: String
    let loading: Bool
    let updatedAt: Double
    let quotas: [CodeSwitchQuota]
    let stats: CodeSwitchStats?
    var quotaState: String? = nil
    var quotaAutoDisabled: Bool? = nil

    var effectiveQuotaState: String {
        if quotaAutoDisabled == true { return "exhausted" }
        if let quotaState, ["available", "exhausted", "unknown"].contains(quotaState) { return quotaState }
        let valid = quotas.filter {
            ["progress", "balance"].contains($0.displayKind) && $0.invalidMessage?.isEmpty != false
                && $0.used.isFinite && $0.total.isFinite && $0.used >= 0 && $0.total >= 0
        }
        if valid.contains(where: { $0.unlimited != true && $0.total - $0.used <= 0 }) { return "exhausted" }
        return valid.isEmpty ? "unknown" : "available"
    }

    func snapshot(platform: CodeSwitchPlatform) -> ProviderSnapshot {
        let windows = quotas.compactMap(\.window)
        return ProviderSnapshot(
            id: "code-switch:\(platform.platform.utf8.count):\(platform.platform):\(providerId)",
            displayName: providerName,
            glyph: ProviderGlyph(rawValue: icon) ?? .third,
            fidelity: .derived,
            status: .ok,
            windows: windows,
            headlineID: windows.first?.id,
            icon: ProviderIcon(kind: .brand, value: CodeSwitchIcon.prefix + icon),
            linked: CodeSwitchDetails(platform: platform.name, provider: self)
        )
    }
}

struct CodeSwitchQuota: Codable, Equatable {
    let key: String
    let label: String?
    let used: Double
    let total: Double
    let unlimited: Bool?
    let nextReset: String?
    let active: Bool
    let valueMode: String?
    let unit: String?
    let extra: String?
    let invalidMessage: String?
    let displayKind: String

    var title: String {
        switch key {
        case "five_hour": return String(localized: "5 hours")
        case "daily": return String(localized: "Daily")
        case "weekly": return String(localized: "Weekly")
        case "monthly": return String(localized: "Monthly")
        case "total": return String(localized: "Total")
        default: return label?.isEmpty == false ? label! : key
        }
    }

    var reset: Date? {
        guard let nextReset, !nextReset.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: nextReset) { return date }
        iso.formatOptions.insert(.withFractionalSeconds)
        if let date = iso.date(from: nextReset) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: nextReset) { return date }
        }
        return nil
    }

    var hasWindow: Bool {
        active && ["progress", "balance"].contains(displayKind) && invalidMessage?.isEmpty != false
            && used.isFinite && total.isFinite && used >= 0 && total >= 0
    }

    var window: LimitWindow? {
        guard hasWindow else { return nil }
        let balance = displayKind == "balance"
        return LimitWindow(id: key, label: title,
            usedFraction: !balance && total > 0 && unlimited != true ? used / total : nil,
            resetsAt: active ? reset : nil,
            quantity: QuotaQuantity(remaining: max(0, total - used), used: balance ? nil : used,
                total: balance ? nil : total, unit: unit ?? (valueMode == "count" ? "" : "USD"),
                unlimited: unlimited == true))
    }
}

struct CodeSwitchStats: Codable, Equatable {
    let totalRequests: Double
    let successfulRequests: Double
    let failedRequests: Double
    let successRate: Double
    let inputTokens: Double
    let outputTokens: Double
    let cacheReadTokens: Double
    let costTotal: Double
    let avgFirstTokenSec: Double
    let avgTokensPerSec: Double

    enum CodingKeys: String, CodingKey {
        case totalRequests = "total_requests", successfulRequests = "successful_requests"
        case failedRequests = "failed_requests", successRate = "success_rate"
        case inputTokens = "input_tokens", outputTokens = "output_tokens", cacheReadTokens = "cache_read_tokens"
        case costTotal = "cost_total", avgFirstTokenSec = "avg_first_token_sec", avgTokensPerSec = "avg_tokens_per_sec"
    }
}

struct CodeSwitchDetails: Equatable {
    let platform: String
    let provider: CodeSwitchProvider

    var activityText: String {
        if provider.status == "session" { return String(localized: "Session provider") }
        if provider.quotaAutoDisabled == true { return String(localized: "Automatically disabled by quota") }
        if provider.status == "enabled" { return String(localized: "Enabled provider") }
        return provider.status == "active"
            ? String(localized: "Calling · \(provider.activeRequests)")
            : String(localized: "Default provider")
    }
}

struct CodeSwitchSnapshotState {
    private(set) var snapshots: [ProviderSnapshot] = []
    private(set) var bindings: [String: CodeSwitchSessionLink] = [:]
    private var session: String?
    private var sequence: UInt64 = 0
    private var heartbeat: Date?
    private var retiredSessions: [String] = []
    private var lastPlatforms: [CodeSwitchPlatform]?

    mutating func accept(_ snapshot: CodeSwitchSnapshot, now: Date, platforms selected: [CodeSwitchPlatform]? = nil) {
        guard snapshot.version == 1, !snapshot.session.isEmpty,
              snapshot.heartbeatAt.isFinite,
              (-1...3).contains(now.timeIntervalSince(snapshot.heartbeat)),
              !retiredSessions.contains(snapshot.session) else { expire(now: now); return }
        if session == snapshot.session {
            guard snapshot.sequence >= sequence else { expire(now: now); return }
        } else {
            if let heartbeat, snapshot.heartbeat < heartbeat { expire(now: now); return }
            if let session {
                retiredSessions.append(session)
                if retiredSessions.count > 16 { retiredSessions.removeFirst() }
            }
            session = snapshot.session
        }
        sequence = snapshot.sequence
        heartbeat = snapshot.heartbeat
        let platforms = selected ?? snapshot.platforms
        guard lastPlatforms != platforms else { return }
        lastPlatforms = platforms
        let previousBindings = bindings
        let previousSnapshots = snapshots
        let previousByID = Dictionary(previousSnapshots.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        bindings.removeAll()
        for platform in platforms where !platform.error && ["claude", "codex"].contains(platform.platform) {
            let providers = Dictionary(platform.providers.map { ($0.providerId, $0) }, uniquingKeysWith: { first, _ in first })
            for binding in platform.sessionBindings ?? [] {
                guard binding.sessionKey.count == 64, binding.sessionKey.allSatisfy({ $0.isHexDigit }),
                      !binding.providerId.isEmpty, binding.updatedAt.isFinite,
                      binding.sequence > (bindings[binding.sessionKey]?.binding.sequence ?? 0) else { continue }
                let id = binding.snapshot(platform: platform).id
                let previous = providers[binding.providerId]?.snapshot(platform: platform)
                    ?? previousByID[id]
                    ?? previousBindings[binding.sessionKey].flatMap { $0.snapshot.id == id ? $0.snapshot : nil }
                bindings[binding.sessionKey] = CodeSwitchSessionLink(platform: platform.platform, binding: binding,
                                                                     snapshot: binding.snapshot(platform: platform, retaining: previous))
            }
        }
        var seen = Set<String>()
        snapshots = platforms.filter { !$0.error }.flatMap { platform in
            platform.providers.compactMap { provider in
                guard !provider.providerId.isEmpty, provider.activeRequests >= 0,
                      ["active", "default", "enabled"].contains(provider.status) else { return nil }
                let item = provider.snapshot(platform: platform)
                return seen.insert(item.id).inserted ? item : nil
            }
        }
    }

    mutating func expire(now: Date, missing: Bool = false) {
        if missing || heartbeat == nil || !(-1...3).contains(now.timeIntervalSince(heartbeat!)) {
            snapshots = []
            bindings = [:]
            lastPlatforms = nil
        }
    }
}

@MainActor
final class CodeSwitchBridge: ObservableObject {
    @Published private(set) var snapshots: [ProviderSnapshot] = []
    @Published private(set) var displayedSnapshots: [ProviderSnapshot] = []
    private var trayIDs = Set<String>()
    @Published private(set) var bindings: [String: CodeSwitchSessionLink] = [:]
    private let file: URL
    private var timer: Timer?
    private var watcher: DispatchSourceFileSystemObject?
    @Published private(set) var connection: CodeSwitchConnection = .disabled
    private let reader: CodeSwitchReader
    private var running = false
    private var mode: CodeSwitchDisplayMode = .tray
    private var generation: UInt64 = 0
    private var readTask: Task<Void, Never>?
    private var pending = false

    init(file: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Caches/code-switch/tray-snapshot-v1.json")) {
        self.file = file
        reader = CodeSwitchReader(file: file)
    }

    func setEnabled(_ enabled: Bool) { configure(enabled: enabled, mode: mode) }

    func configure(enabled: Bool, mode: CodeSwitchDisplayMode) {
        guard enabled != running || mode != self.mode else { return }
        if enabled && running {
            self.mode = mode
            updateDisplayedSnapshots()
            return
        }
        stop()
        self.mode = mode
        guard enabled else { return }
        running = true
        connection = .waiting
        refresh()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        running = false
        timer?.invalidate()
        timer = nil
        watcher?.cancel()
        watcher = nil
        generation &+= 1
        let next = generation
        Task { await reader.reset(generation: next) }
        pending = false
        connection = .disabled
        if !snapshots.isEmpty { snapshots = [] }
        trayIDs = []
        if !displayedSnapshots.isEmpty { displayedSnapshots = [] }
        if !bindings.isEmpty { bindings = [:] }
    }

    func refresh() {
        guard running else { return }
        if readTask != nil { pending = true; return }
        readTask = Task { [weak self] in
            guard let self else { return }
            while self.running {
                self.pending = false
                await self.poll()
                if !self.pending { break }
            }
            self.readTask = nil
        }
    }

    func stopAndWait() async {
        stop()
        await reader.reset(generation: generation)
    }

    func poll(now: Date = Date()) async {
        if running && watcher == nil {
            let descriptor = open(file.deletingLastPathComponent().path, O_EVTONLY)
            if descriptor >= 0 {
                let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
                    eventMask: [.write, .rename, .delete], queue: .main)
                source.setEventHandler { [weak self] in
                    Task { @MainActor in
                        guard self?.running == true else { return }
                        if self?.watcher?.data.contains(.delete) == true || self?.watcher?.data.contains(.rename) == true {
                            self?.watcher?.cancel()
                            self?.watcher = nil
                        }
                        self?.refresh()
                    }
                }
                source.setCancelHandler { close(descriptor) }
                watcher = source
                source.resume()
            }
        }
        let current = generation
        guard let result = await reader.read(now: now, mode: mode, generation: current),
              current == generation else { return }
        if bindings != result.bindings { bindings = result.bindings }
        if snapshots != result.snapshots { snapshots = result.snapshots }
        trayIDs = result.trayIDs
        updateDisplayedSnapshots()
        if connection != result.connection { connection = result.connection }
    }

    private func updateDisplayedSnapshots() {
        let selected = snapshots.filter { mode.includes($0, trayIDs: trayIDs) }
        if displayedSnapshots != selected { displayedSnapshots = selected }
    }

    deinit {
        timer?.invalidate()
        watcher?.cancel()
    }
}
