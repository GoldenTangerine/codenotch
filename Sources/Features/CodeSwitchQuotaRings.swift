/**
 @name: 联动周期比例环
 @Descripttion: 根据相邻周期的实际用量与总额度生成独立的圆环读数。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-14 22:16:39
 @LastEditTime: 2026-09-14 22:16:39
 @FilePath: Sources/Features/CodeSwitchQuotaRings.swift
 */
import Foundation

struct CodeSwitchQuotaRings: Equatable {
    struct Reading: Equatable {
        let label: String
        let fraction: Double

        var summary: String { "\(label), \(Percent.text(for: fraction))%" }
    }

    let main: Reading
    let secondary: Reading

    // 仅供显示使用；不替换原始窗口，提醒与详情仍依据供应商真实额度。
    static func reading(for snapshot: ProviderSnapshot, enabled: Bool) -> Self? {
        guard enabled, snapshot.kind == .usage, let quotas = snapshot.linked?.provider.quotas else { return nil }

        func quota(_ key: String) -> CodeSwitchQuota? {
            let matches = quotas.filter { $0.key == key }
            guard matches.count == 1, let quota = matches.first,
                  quota.hasWindow, quota.displayKind == "progress",
                  quota.unlimited != true, quota.total > 0,
                  Percent.roundedValue(for: quota.used / quota.total) != nil else { return nil }
            return quota
        }

        guard let weekly = quota("weekly") else { return nil }
        let monthly = quota("monthly")
        let weeklyShare = monthly.flatMap {
            share(weekly, of: $0, label: L10n.t("Weekly used / Monthly limit"))
        }
        if let daily = quota("daily"),
           let dailyShare = share(daily, of: weekly, label: L10n.t("Daily used / Weekly limit")) {
            return Self(main: dailyShare, secondary: weeklyShare
                ?? Reading(label: weekly.title, fraction: weekly.used / weekly.total))
        }
        if let weeklyShare, let monthly {
            return Self(main: weeklyShare, secondary: Reading(label: monthly.title,
                fraction: monthly.used / monthly.total))
        }
        return nil
    }

    private static func share(_ used: CodeSwitchQuota, of limit: CodeSwitchQuota,
                              label: String) -> Reading? {
        let usedMode = used.valueMode ?? "currency"
        let limitMode = limit.valueMode ?? "currency"
        guard ["currency", "count"].contains(usedMode), usedMode == limitMode else { return nil }
        func unit(_ quota: CodeSwitchQuota) -> String {
            let value = quota.unit?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
            return value.isEmpty && usedMode == "currency" ? "USD" : value
        }
        let usedUnit = unit(used)
        // 百分比没有实际用量尺度；不同币种或计量单位也不能直接相除。
        guard usedUnit == unit(limit), !["%", "PERCENT", "PERCENTAGE"].contains(usedUnit) else { return nil }
        let fraction = used.used / limit.total
        guard Percent.roundedValue(for: fraction) != nil else { return nil }
        return Reading(label: label, fraction: fraction)
    }
}
