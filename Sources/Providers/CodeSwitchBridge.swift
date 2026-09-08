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

    var heartbeat: Date { Date(timeIntervalSince1970: heartbeatAt / 1000) }
}

struct CodeSwitchPlatform: Codable, Equatable {
    let platform: String
    let name: String
    let icon: String
    let error: Bool
    let providers: [CodeSwitchProvider]
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

    var window: LimitWindow? {
        guard active, ["progress", "balance"].contains(displayKind), invalidMessage?.isEmpty != false,
              used.isFinite, total.isFinite, used >= 0, total >= 0 else { return nil }
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
        provider.status == "active"
            ? String(localized: "Calling · \(provider.activeRequests)")
            : String(localized: "Default provider")
    }
}

struct CodeSwitchSnapshotState {
    private(set) var snapshots: [ProviderSnapshot] = []
    private var session: String?
    private var sequence: UInt64 = 0
    private var heartbeat: Date?
    private var retiredSessions: Set<String> = []

    mutating func accept(_ snapshot: CodeSwitchSnapshot, now: Date) {
        guard snapshot.version == 1, !snapshot.session.isEmpty,
              snapshot.heartbeatAt.isFinite,
              (-1...3).contains(now.timeIntervalSince(snapshot.heartbeat)),
              !retiredSessions.contains(snapshot.session) else { expire(now: now); return }
        if session == snapshot.session {
            guard snapshot.sequence > sequence else { expire(now: now); return }
        } else {
            if let heartbeat, snapshot.heartbeat < heartbeat { expire(now: now); return }
            if let session { retiredSessions.insert(session) }
            session = snapshot.session
        }
        sequence = snapshot.sequence
        heartbeat = snapshot.heartbeat
        var seen = Set<String>()
        snapshots = snapshot.platforms.filter { !$0.error }.flatMap { platform in
            platform.providers.compactMap { provider in
                guard !provider.providerId.isEmpty, provider.activeRequests >= 0,
                      ["active", "default"].contains(provider.status) else { return nil }
                let item = provider.snapshot(platform: platform)
                return seen.insert(item.id).inserted ? item : nil
            }
        }
    }

    mutating func expire(now: Date, missing: Bool = false) {
        if missing || heartbeat == nil || !(-1...3).contains(now.timeIntervalSince(heartbeat!)) {
            snapshots = []
        }
    }
}

@MainActor
final class CodeSwitchBridge: ObservableObject {
    @Published private(set) var snapshots: [ProviderSnapshot] = []
    private let file: URL
    private var timer: Timer?
    private var watcher: DispatchSourceFileSystemObject?
    private var state = CodeSwitchSnapshotState()
    private var running = false

    init(file: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Caches/code-switch/tray-snapshot-v1.json")) {
        self.file = file
    }

    func setEnabled(_ enabled: Bool) {
        stop()
        guard enabled else { return }
        running = true
        poll()
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
        state = CodeSwitchSnapshotState()
        if !snapshots.isEmpty { snapshots = [] }
    }

    func refresh() {
        guard running else { return }
        poll()
    }

    func poll(now: Date = Date()) {
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
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            guard let size = attributes[.size] as? NSNumber, size.intValue <= 2_000_000 else {
                state.expire(now: now)
                publish()
                return
            }
            let data = try Data(contentsOf: file)
            let snapshot = try JSONDecoder().decode(CodeSwitchSnapshot.self, from: data)
            state.accept(snapshot, now: now)
        } catch {
            state.expire(now: now, missing: (error as NSError).code == NSFileNoSuchFileError
                || (error as NSError).code == NSFileReadNoSuchFileError)
        }
        publish()
    }

    private func publish() {
        if snapshots != state.snapshots { snapshots = state.snapshots }
    }

    deinit {
        timer?.invalidate()
        watcher?.cancel()
    }
}
