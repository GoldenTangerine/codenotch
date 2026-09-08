/**
 @name: 查询条目配置
 @Descripttion: 定义独立供应商条目、凭据引用和刷新策略。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-08 14:56:06
 @LastEditTime: 2026-09-08 14:56:06
 @FilePath: Sources/Providers/QueryEntry.swift
 */
import Foundation
import Combine
import Security

enum QueryMode: String, Codable, CaseIterable {
    case automatic, manual
}

struct QuerySchedule: Codable, Equatable {
    var enabled = true
    var activeSeconds: Double = 60
    var idleSeconds: Double = 300

    func interval(busy: Bool) -> TimeInterval { max(1, busy ? activeSeconds : idleSeconds) }
}

struct ProviderIcon: Codable, Equatable {
    enum Kind: String, Codable, CaseIterable { case brand, symbol, image }
    var kind: Kind = .brand
    var value: String = "claude"
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Codenotch/QueryIcons", isDirectory: true)
    }
}

struct QueryEntry: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var name = "New Provider"
    var icon = ProviderIcon()
    var enabled = true
    var mode: QueryMode = .manual
    var nativeID = "claude"
    var template: QueryTemplate = .native
    var baseURL = ""
    var code = ""
    var timeout: Double = 15
    var headlineID: String?
    var schedule = QuerySchedule()

    var credentialReference: String { "query.\(id)" }
    var usesLocalAccount: Bool { mode == .automatic }

    func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.count <= 120 else { throw QueryError.invalid("Enter a provider name (1–120 characters).") }
        guard timeout.isFinite, (1...120).contains(timeout),
              schedule.activeSeconds.isFinite, (1...86400).contains(schedule.activeSeconds),
              schedule.idleSeconds.isFinite, (1...86400).contains(schedule.idleSeconds)
        else { throw QueryError.invalid("Intervals must be 1–86400 seconds; timeout must be 1–120 seconds.") }
        if mode == .manual, template != .native, code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw QueryError.invalid("Enter a query script.")
        }
    }

    func sameQuery(as other: QueryEntry) -> Bool {
        mode == other.mode && nativeID == other.nativeID && template == other.template
            && baseURL == other.baseURL && code == other.code && timeout == other.timeout
    }
}

struct QuerySecrets: Codable, Equatable {
    var apiKey = ""
    var accessToken = ""
    var cookie = ""
    var accountID = ""
    var userID = ""

    var variables: [String: String] {
        ["apiKey": apiKey, "accessToken": accessToken, "cookie": cookie,
         "accountId": accountID, "userId": userID]
    }
}

enum QueryError: LocalizedError {
    case invalid(String)
    case keychain(OSStatus)
    case script
    case timeout

    var errorDescription: String? {
        switch self {
        case .invalid(let message): return NSLocalizedString(message, comment: "Query validation error")
        case .keychain(let status): return "Keychain error (\(status))."
        case .script: return String(localized: "Script failed. Check request and extractor.")
        case .timeout: return String(localized: "Query timed out.")
        }
    }
}

protocol QuerySecretStorage {
    func load(_ reference: String) throws -> QuerySecrets
    func save(_ secrets: QuerySecrets, reference: String) throws
    func remove(_ reference: String) throws
}

struct QueryKeychain: QuerySecretStorage {
    private let service = "com.vinz.codenotch.query"
    private func query(_ reference: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: reference]
    }

    func load(_ reference: String) throws -> QuerySecrets {
        var query = query(reference)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return QuerySecrets() }
        guard status == errSecSuccess, let data = result as? Data else { throw QueryError.keychain(status) }
        return try JSONDecoder().decode(QuerySecrets.self, from: data)
    }

    func save(_ secrets: QuerySecrets, reference: String) throws {
        let data = try JSONEncoder().encode(secrets)
        let attributes = [kSecValueData as String: data]
        var status = SecItemUpdate(query(reference) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query(reference)
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw QueryError.keychain(status) }
    }

    func remove(_ reference: String) throws {
        let status = SecItemDelete(query(reference) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw QueryError.keychain(status) }
    }

    func removeAll() throws {
        let status = SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw QueryError.keychain(status) }
    }
}

@MainActor
final class QueryCatalog: ObservableObject {
    @Published private(set) var entries: [QueryEntry]
    @Published private(set) var problem: String?
    let automaticProviders: [UsageProvider]
    let secrets: QuerySecretStorage
    var onChange: ((Set<String>) -> Void)?
    private let defaults: UserDefaults
    private let storageKey = "queryEntries.v1"

    init(providers: [UsageProvider], disconnected: Set<String>, defaults: UserDefaults = .standard,
         secrets: QuerySecretStorage = QueryKeychain()) {
        self.defaults = defaults
        self.secrets = secrets
        automaticProviders = providers
        if let data = defaults.data(forKey: storageKey) {
            do {
                entries = try JSONDecoder().decode([QueryEntry].self, from: data)
            } catch {
                entries = []
                problem = String(localized: "Saved provider configuration could not be read.")
            }
        } else {
            entries = providers.map { provider in
                var entry = QueryEntry()
                entry.id = provider.id
                entry.name = provider.displayName
                entry.icon.value = provider.glyph.rawValue
                entry.enabled = !disconnected.contains(provider.id)
                entry.mode = .automatic
                entry.nativeID = provider.id
                return entry
            }
            defaults.set(try? JSONEncoder().encode(entries), forKey: storageKey)
        }
    }

    func providers() -> [UsageProvider] {
        entries.map { entry in
            ConfiguredUsageProvider(entry: entry,
                automatic: automaticProviders.first { $0.id == entry.nativeID }, secrets: secrets)
        }
    }

    func save(_ entry: QueryEntry, secrets newSecrets: QuerySecrets?) throws {
        guard problem == nil else { throw QueryError.invalid(problem!) }
        try entry.validate()
        let oldIcon = entries.first { $0.id == entry.id }?.icon
        var invalidated = Set<String>()
        if let old = entries.first(where: { $0.id == entry.id }), !old.sameQuery(as: entry) {
            invalidated.insert(entry.id)
        }
        if let newSecrets {
            try secrets.save(newSecrets, reference: entry.credentialReference)
            invalidated.insert(entry.id)
        }
        if let index = entries.firstIndex(where: { $0.id == entry.id }) { entries[index] = entry }
        else { entries.append(entry) }
        persist(invalidated)
        removeUnusedIcon(oldIcon)
    }

    func setEnabled(_ enabled: Bool, id: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].enabled = enabled
        persist([])
    }

    func move(_ id: String, by offset: Int) {
        guard let index = entries.firstIndex(where: { $0.id == id }),
              entries.indices.contains(index + offset) else { return }
        entries.swapAt(index, index + offset)
        persist([])
    }

    @discardableResult
    func move(_ id: String, onto targetID: String) -> Bool {
        guard let from = entries.firstIndex(where: { $0.id == id }),
              let to = entries.firstIndex(where: { $0.id == targetID }) else { return false }
        guard from != to else { return true }
        entries.insert(entries.remove(at: from), at: to)
        persist([])
        return true
    }

    func delete(_ id: String) throws {
        guard let entry = entries.first(where: { $0.id == id }) else { return }
        try secrets.remove(entry.credentialReference)
        entries.removeAll { $0.id == id }
        persist([id])
        removeUnusedIcon(entry.icon)
    }

    private func persist(_ invalidated: Set<String>) {
        defaults.set(try? JSONEncoder().encode(entries), forKey: storageKey)
        onChange?(invalidated)
    }

    private func removeUnusedIcon(_ icon: ProviderIcon?) {
        guard let icon, icon.kind == .image, !icon.value.isEmpty,
              !entries.contains(where: { $0.icon == icon }),
              icon.value == URL(fileURLWithPath: icon.value).lastPathComponent else { return }
        try? FileManager.default.removeItem(at: ProviderIcon.directory.appendingPathComponent(icon.value))
    }
}
