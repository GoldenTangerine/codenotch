/**
 @name: 上游功能兼容模块
 @Descripttion: 实现上游功能及本地兼容行为。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-10-09 09:58:33
 @LastEditTime: 2026-10-09 09:58:33
 @FilePath: Sources/Costs/CostAccounts.swift
 */
import Foundation
import Combine

/// One CLI login as the cost layer sees it: a Codenotch profile (Claude or
/// Codex, default or `~/.claude-<slug>`) plus how it is paid. Billing choices,
/// the detected plan and the credit cap persist in accounts.json.
struct CostAccount: Identifiable, Equatable {
    enum Billing: String, Codable, CaseIterable, Identifiable {
        case subscription, api
        var id: String { rawValue }
        var title: String { self == .subscription ? L10n.t("Monthly plan") : L10n.t("API key (per token)") }
    }

    let id: String                 // the provider id Codenotch uses ("claude", "claude-braspine", "codex", …)
    let provider: String           // "claude" | "codex"
    let name: String               // "Claude (work)": the profile's own name
    let configDirectory: URL
    var billing: Billing = .subscription
    var monthlyPrice: Double = 0   // manual override in the Mac's currency (0 = detected plan)
    var planTier: String?
    var planDetectedAt: Date?
    var creditLimit: Double?

    var isDefault: Bool { !id.contains("-") }

    @MainActor var planName: String? { planTier.map { PlanCatalog.shared.name(for: $0) } }

    /// Monthly price in the Mac's currency: the override, else the catalog.
    @MainActor func monthlyLocal(rate: Double) -> Double {
        if monthlyPrice > 0 { return monthlyPrice }
        guard let tier = planTier else { return 0 }
        return PlanCatalog.shared.monthly(for: tier, currency: PriceTable.shared.currency, rate: rate) ?? 0
    }

    @MainActor func creditLocal(rate: Double) -> Double? {
        let usd = planTier.flatMap { PlanCatalog.shared.creditUSD(for: $0) } ?? 1
        return rate > 0 ? usd * rate : nil
    }

    var transcriptsRoot: URL {
        configDirectory.appendingPathComponent(provider == "codex" ? "sessions" : "projects")
    }
}

@MainActor
final class CostAccountStore: ObservableObject {
    static let shared = CostAccountStore()

    @Published private(set) var accounts: [CostAccount] = []
    @Published private(set) var candidates: [CostAccount] = []

    private struct Stored: Codable {
        var billing: CostAccount.Billing?
        var monthlyPrice: Double?
        var planTier: String?
        var planDetectedAt: Date?
        var creditLimit: Double?
        var nativeOnly: Bool?
    }
    private var stored: [String: Stored] = [:]
    private let storageURL: URL?

    static let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Codenotch/costs/accounts.json")
    }()

    init(storageURL: URL? = nil) {
        self.storageURL = storageURL ?? (Runtime.isUnderTest ? nil : Self.fileURL)
        if let url = self.storageURL, let data = try? Data(contentsOf: url),
           let map = try? JSONDecoder().decode([String: Stored].self, from: data) { stored = map }
    }

    /// Profiles come from Codenotch's own discovery, so an account added there
    /// (a new `~/.claude-<slug>`) shows up here without a second list.
    private var configured: [CostAccount] = []
    private(set) var aliases: [String: String] = [:]
    @Published private(set) var linkedMode = false

    func configure(entries: [QueryEntry], claude: [ClaudeProfile], codex: [CodexProfile],
                   disconnected: Set<String>, linkedMode: Bool, nicknames: [String: String] = [:]) {
        self.linkedMode = linkedMode
        var available: [String: CostAccount] = [:]
        for p in claude {
            available[p.id] = CostAccount(id: p.id, provider: "claude", name: p.displayName, configDirectory: p.configDirectory)
        }
        for p in codex {
            available[p.id] = CostAccount(id: p.id, provider: "codex", name: p.displayName, configDirectory: p.configDirectory)
        }
        var list: [CostAccount] = []
        var mapping: [String: String] = [:]
        // 联动日志没有完整的历史计费来源，不能据此扣到原生订阅。
        for entry in entries where entry.enabled && entry.usesLocalAccount && !disconnected.contains(entry.id) {
            guard let native = available[entry.nativeID] else { continue }
            mapping[entry.id] = native.id
            if !list.contains(where: { $0.id == native.id }) {
                let name = nicknames[entry.id] ?? nicknames[native.id] ?? entry.name
                list.append(CostAccount(id: native.id, provider: native.provider, name: name,
                                        configDirectory: native.configDirectory))
            }
        }
        aliases = mapping
        configured = list
        rediscover()
        if self === Self.shared { CostModels.reconcile() }
    }

    func rediscover() {
        let available = configured.map(apply)
        if available != candidates { candidates = available }
        let list = available.filter { isNativeOnly($0.id) }
        if list != accounts { accounts = list }
    }

    func isNativeOnly(_ id: String) -> Bool { stored[id]?.nativeOnly == true }

    func setNativeOnly(_ enabled: Bool, for id: String) {
        guard configured.contains(where: { $0.id == id }), isNativeOnly(id) != enabled else { return }
        var value = stored[id] ?? Stored()
        value.nativeOnly = enabled
        stored[id] = value
        save()
        rediscover()
        if self === Self.shared { CostModels.reconcile() }
    }

    func nativeID(for id: String) -> String? {
        aliases[id] ?? (accounts.contains { $0.id == id } ? id : nil)
    }

    private func apply(_ a: CostAccount) -> CostAccount {
        var a = a
        if let s = stored[a.id] {
            a.billing = s.billing ?? .subscription
            a.monthlyPrice = s.monthlyPrice ?? 0
            a.planTier = s.planTier.map { PlanCatalog.key(for: a.provider, plan: $0) }
            a.planDetectedAt = s.planDetectedAt
            a.creditLimit = s.creditLimit
        }
        return a
    }

    func account(_ id: String) -> CostAccount? { accounts.first { $0.id == id } }
    func accounts(for provider: String) -> [CostAccount] { accounts.filter { $0.provider == provider } }

    private func mutate(_ id: String, _ change: (inout CostAccount) -> Void) {
        guard let i = accounts.firstIndex(where: { $0.id == id }) else { return }
        var a = accounts[i]
        change(&a)
        guard a != accounts[i] else { return }
        accounts[i] = a
        stored[id] = Stored(billing: a.billing, monthlyPrice: a.monthlyPrice, planTier: a.planTier,
                            planDetectedAt: a.planDetectedAt, creditLimit: a.creditLimit,
                            nativeOnly: stored[id]?.nativeOnly)
        save()
        if self === Self.shared { CostModels.reconcile() }
    }

    func setBilling(_ id: String, _ b: CostAccount.Billing) { mutate(id) { $0.billing = b } }
    func setMonthlyPrice(_ id: String, _ p: Double) { mutate(id) { $0.monthlyPrice = p } }
    func setCreditLimit(_ id: String, _ l: Double) { mutate(id) { if $0.creditLimit != l { $0.creditLimit = l } } }
    func setPlan(_ id: String, tier: String) {
        mutate(id) { a in
            let tier = PlanCatalog.key(for: a.provider, plan: tier)
            if a.planTier == tier, let at = a.planDetectedAt, Date().timeIntervalSince(at) < 3600 { return }
            a.planTier = tier; a.planDetectedAt = Date()
        }
    }
    func planIsFresh(_ id: String) -> Bool {
        guard let a = account(id), let at = a.planDetectedAt else { return false }
        return Date().timeIntervalSince(at) < 24 * 3600
    }

    private func save() {
        guard let storageURL else { return }
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(stored) {
            try? FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: storageURL, options: .atomic)
        }
    }

    // MARK: Plan detection (once a day, from the login the CLI already holds)

    func detectPlanIfDue(_ id: String) {
        // 套餐来自已获准查询的额度快照，不绕过停用或钥匙串拒绝状态额外取凭据。
    }
}
