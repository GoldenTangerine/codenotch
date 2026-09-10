/**
 @name: Code Switch 联动订阅
 @Descripttion: 在后台按修订读取供应商快照并维护按需订阅。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-10 18:00:00
 @LastEditTime: 2026-09-10 18:00:00
 @FilePath: Sources/Providers/CodeSwitchIntegration.swift
 */
import Foundation

enum CodeSwitchDisplayMode: String, CaseIterable, Identifiable {
    case tray, enabled
    var id: String { rawValue }
    var title: String {
        switch self {
        case .tray: return String(localized: "Follow tray popup")
        case .enabled: return String(localized: "All enabled providers")
        }
    }
}

struct CodeSwitchIntegrationInfo: Codable {
    let version: Int
    let mode: String
    let consumerSession: String
    let revision: UInt64
    let error: Bool
}

struct CodeSwitchProviderFile: Codable {
    let version: Int
    let session: String
    let revision: UInt64
    let platforms: [CodeSwitchPlatform]
}

struct CodeSwitchSubscription: Codable {
    let version: Int
    let session: String
    let mode: String
    let heartbeatAt: Int64
}

enum CodeSwitchConnection: Equatable {
    case disabled, waiting, connected, loading, legacy, failed, subscriptionFailed, partial
    var title: String {
        switch self {
        case .disabled: return String(localized: "Integration is off")
        case .waiting: return String(localized: "Waiting for Code Switch R")
        case .connected: return String(localized: "Connected to Code Switch R")
        case .loading: return String(localized: "Waiting for enabled providers…")
        case .legacy: return String(localized: "Update Code Switch R to show all enabled providers. Following tray for now.")
        case .failed: return String(localized: "Could not read providers. Retrying automatically…")
        case .subscriptionFailed: return String(localized: "Could not request enabled providers. Check cache folder access.")
        case .partial: return String(localized: "Some platforms could not be read. Retrying automatically…")
        }
    }
}

struct CodeSwitchReadResult {
    let snapshots: [ProviderSnapshot]
    let bindings: [String: CodeSwitchSessionLink]
    let connection: CodeSwitchConnection
}

actor CodeSwitchReader {
    private struct Signature: Equatable {
        let inode: UInt64
        let size: Int
        let modified: Date
    }
    private let file: URL
    private let directory: URL
    private let consumerSession = UUID().uuidString
    private var generation: UInt64 = 0
    private var signature: Signature?
    private var main: CodeSwitchSnapshot?
    private var full: CodeSwitchProviderFile?
    private var state = CodeSwitchSnapshotState()
    private var renewed: Date?
    private(set) var mainDecodes = 0
    private(set) var providerDecodes = 0

    init(file: URL) {
        self.file = file
        directory = file.deletingLastPathComponent()
    }

    func reset(generation next: UInt64) {
        guard next > generation else { return }
        generation = next
        revoke()
        signature = nil
        main = nil
        full = nil
        state = CodeSwitchSnapshotState()
    }

    private func revoke() {
        guard renewed != nil else { return }
        let lease = directory.appendingPathComponent("codenotch-subscription-v1.json")
        if let data = try? boundedData(lease, limit: 4096),
           let current = try? JSONDecoder().decode(CodeSwitchSubscription.self, from: data),
           current.session == consumerSession { try? FileManager.default.removeItem(at: lease) }
        renewed = nil
    }

    private func subscribe(now: Date) throws {
        let lease = directory.appendingPathComponent("codenotch-subscription-v1.json")
        if let renewed, (0..<5).contains(now.timeIntervalSince(renewed)),
           FileManager.default.fileExists(atPath: lease.path) { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let subscription = CodeSwitchSubscription(version: 1, session: consumerSession, mode: "enabled",
                                                   heartbeatAt: Int64((now.timeIntervalSince1970 * 1000).rounded(.down)))
        let temporary = directory.appendingPathComponent(".codenotch-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard FileManager.default.createFile(atPath: temporary.path, contents: try JSONEncoder().encode(subscription),
                                             attributes: [.posixPermissions: 0o600]) else { throw CocoaError(.fileWriteUnknown) }
        guard rename(temporary.path, lease.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
        renewed = now
    }

    private func boundedData(_ url: URL, limit: Int = 2_000_000) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw CocoaError(.fileReadTooLarge) }
        return data
    }

    func read(now: Date, mode: CodeSwitchDisplayMode, generation next: UInt64) -> CodeSwitchReadResult? {
        guard next >= generation else { return nil }
        if next > generation { reset(generation: next) }
        var connection: CodeSwitchConnection = .connected
        if mode == .enabled {
            do { try subscribe(now: now) } catch { connection = .subscriptionFailed }
        } else {
            revoke()
            full = nil
        }
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
            let current = Signature(inode: (attrs[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0,
                                    size: (attrs[.size] as? NSNumber)?.intValue ?? 0,
                                    modified: attrs[.modificationDate] as? Date ?? .distantPast)
            guard current.size <= 2_000_000 else { throw CocoaError(.fileReadTooLarge) }
            if current != signature {
                let decoded = try JSONDecoder().decode(CodeSwitchSnapshot.self, from: boundedData(file))
                mainDecodes += 1
                main = decoded
                signature = current
            }
            guard let main, main.version == 1, !main.session.isEmpty,
                  main.heartbeatAt.isFinite, (-1...3).contains(now.timeIntervalSince(main.heartbeat)) else {
                state.expire(now: now)
                full = nil
                return result(connection == .subscriptionFailed ? connection : .waiting)
            }
            var platforms = main.platforms
            if mode == .enabled, connection != .subscriptionFailed {
                if let info = main.codenotch, info.version == 1 {
                    if info.mode != "enabled" || info.consumerSession != consumerSession {
                        connection = .loading
                        full = nil
                    } else if info.error {
                        connection = .failed
                        full = nil
                    } else {
                        do {
                            if full?.session != main.session || full?.revision != info.revision {
                                let decoded = try JSONDecoder().decode(CodeSwitchProviderFile.self,
                                    from: boundedData(directory.appendingPathComponent("codenotch-providers-v1.json")))
                                providerDecodes += 1
                                guard decoded.version == 1, decoded.session == main.session,
                                      decoded.revision == info.revision else { throw CocoaError(.fileReadCorruptFile) }
                                full = decoded
                            }
                            platforms = full?.platforms ?? main.platforms
                        } catch {
                            connection = .failed
                            // A revision can race an atomic publisher update; retry on the next signal.
                            full = nil
                        }
                    }
                } else { connection = .legacy; full = nil }
            }
            if connection == .connected && platforms.contains(where: \.error) { connection = .partial }
            state.accept(main, now: now, platforms: platforms)
        } catch {
            let code = (error as NSError).code
            let missing = code == NSFileNoSuchFileError || code == NSFileReadNoSuchFileError
            state.expire(now: now, missing: missing)
            if missing { main = nil; full = nil; signature = nil }
            if connection != .subscriptionFailed { connection = missing ? .waiting : .failed }
        }
        return result(connection)
    }

    private func result(_ connection: CodeSwitchConnection) -> CodeSwitchReadResult {
        CodeSwitchReadResult(snapshots: state.snapshots, bindings: state.bindings, connection: connection)
    }
}
