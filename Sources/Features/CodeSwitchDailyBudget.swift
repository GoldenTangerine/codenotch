/**
 @name: 联动每日动态预算
 @Descripttion: 按剩余额度与重置时间计算每日可用额度及今日进度。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-15 11:04:18
 @LastEditTime: 2026-09-15 11:04:18
 @FilePath: Sources/Features/CodeSwitchDailyBudget.swift
 */
import Foundation

enum CodeSwitchDailyBudget {
    struct Reading: Equatable {
        let source: CodeSwitchQuota
        let todayUsed: Double
        let available: Double
        let usedFraction: Double
        let sinceObservation: Bool

        var remainingFraction: Double { max(0, 1 - usedFraction) }
        var title: String { L10n.t("Daily budget") }
        var unit: String { CodeSwitchDailyBudget.unit(source) }
        func amount(_ value: Double) -> String {
            let prefix = (source.valueMode ?? "currency") == "currency"
                ? (["USD": "$", "CNY": "¥", "EUR": "€", "GBP": "£"][unit] ?? unit + " ") : ""
            let suffix = prefix.isEmpty && !unit.isEmpty ? " " + unit : ""
            return prefix + QuotaQuantity.format(value) + suffix
        }
    }

    static func unit(_ quota: CodeSwitchQuota) -> String {
        let value = quota.unit?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        return value.isEmpty && (quota.valueMode ?? "currency") == "currency" ? "USD" : value
    }

    static func quota(_ key: String, in snapshot: ProviderSnapshot, now: Date) -> CodeSwitchQuota? {
        guard snapshot.kind == .usage, let quotas = snapshot.linked?.provider.quotas else { return nil }
        let matches = quotas.filter { $0.key == key }
        guard matches.count == 1, let value = matches.first,
              value.hasWindow, value.displayKind == "progress", value.unlimited != true,
              value.total > 0, ["currency", "count"].contains(value.valueMode ?? "currency"),
              !["%", "PERCENT", "PERCENTAGE"].contains(unit(value)),
              let reset = value.reset, reset.timeIntervalSince1970.isFinite, reset > now else { return nil }
        return value
    }

    static func source(in snapshot: ProviderSnapshot, now: Date) -> CodeSwitchQuota? {
        for key in ["weekly", "monthly", "daily"] {
            if let value = quota(key, in: snapshot, now: now) { return value }
        }
        return nil
    }

    // 今日计数无需日额度上限；仍须确保来源唯一、单位可比且未进入下个周期。
    static func dailyUsage(in snapshot: ProviderSnapshot, source: CodeSwitchQuota, now: Date) -> Double? {
        let matches = snapshot.linked?.provider.quotas.filter { $0.key == "daily" } ?? []
        guard matches.count == 1, let daily = matches.first,
              daily.active, daily.displayKind == "progress", daily.invalidMessage?.isEmpty != false,
              daily.used.isFinite, daily.used >= 0,
              let reset = daily.reset, reset.timeIntervalSince1970.isFinite, reset > now,
              unit(daily) == unit(source), (daily.valueMode ?? "currency") == (source.valueMode ?? "currency") else { return nil }
        return daily.used
    }

    static func dailyCost(in snapshot: ProviderSnapshot, source: CodeSwitchQuota) -> Double? {
        // 联动协议的今日费用以美元计价，不能用于次数或其他币种的额度。
        guard (source.valueMode ?? "currency") == "currency", unit(source) == "USD",
              let cost = snapshot.linked?.provider.stats?.costTotal,
              cost.isFinite, cost >= 0 else { return nil }
        return cost
    }

    static func reading(for snapshot: ProviderSnapshot, now: Date = Date(),
                        calendar: Calendar = .current) -> Reading? {
        guard let source = source(in: snapshot, now: now), let reset = source.reset else { return nil }
        let today: Double
        let estimated: Bool
        if let daily = dailyUsage(in: snapshot, source: source, now: now) {
            today = daily
            estimated = false
        } else if let sample = snapshot.codeSwitchDailyUsage,
                  sample.matches(source, now: now, calendar: calendar) {
            today = sample.todayUsed
            estimated = sample.costIsCurrent != true
        } else { return nil }
        let remaining = max(0, source.total - source.used)
        let days = max(1, reset.timeIntervalSince(now) / 86_400)
        let available = remaining / days
        guard today.isFinite, today >= 0, available.isFinite else { return nil }
        // 分段相除避免超大额度在相加时溢出；耗尽且今日尚未观测到用量时仍显示满环。
        let fraction: Double
        if available == 0 { fraction = 1 }
        else if today > available { fraction = 1 / (1 + available / today) }
        else { let ratio = today / available; fraction = ratio / (1 + ratio) }
        return Reading(source: source, todayUsed: today, available: available,
                       usedFraction: fraction, sinceObservation: estimated)
    }
}
