/**
 @name: 联动周期比例环
 @Descripttion: 将动态每日预算映射为圆环读数，同时保留真实的第二额度。
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
    let secondary: Reading?

    // 仅供显示使用；不替换原始窗口，提醒与详情仍依据供应商真实额度。
    static func reading(for snapshot: ProviderSnapshot, enabled: Bool, now: Date = Date()) -> Self? {
        guard enabled, let budget = CodeSwitchDailyBudget.reading(for: snapshot, now: now) else { return nil }
        let secondary = snapshot.secondaryWindow.flatMap { window in
            window.usedFraction.map { Reading(label: window.label, fraction: $0) }
        }
        return Self(main: Reading(label: budget.title, fraction: budget.usedFraction),
                    secondary: secondary)
    }

    // 百分比没有实际用量尺度；不同币种或计量单位也不能直接相除。
}
