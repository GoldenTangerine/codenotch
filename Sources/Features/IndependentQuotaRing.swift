/**
 @name: 独立内圈读数
 @Descripttion: 保留原额度窗口并选择独立内圈显示的每日节奏或周期比例。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-15 10:00:31
 @LastEditTime: 2026-09-15 10:00:31
 @FilePath: Sources/Features/IndependentQuotaRing.swift
 */
import Foundation

enum IndependentQuotaRing {
    static func reading(for snapshot: ProviderSnapshot, enabled: Bool,
                        ratiosEnabled: Bool) -> CodeSwitchQuotaRings.Reading? {
        guard enabled else { return nil }
        return reading(for: snapshot, ratios: CodeSwitchQuotaRings.reading(for: snapshot, enabled: ratiosEnabled))
    }

    static func reading(for snapshot: ProviderSnapshot,
                        ratios: CodeSwitchQuotaRings?) -> CodeSwitchQuotaRings.Reading? {
        guard snapshot.hasReading, snapshot.localModel == nil else { return nil }
        if let ratio = ratios {
            return ratio.main
        }
        guard let pace = snapshot.windows.first(where: { $0.id == DailyPace.windowID }),
              let fraction = pace.usedFraction, fraction.isFinite, fraction >= 0 else { return nil }
        return .init(label: pace.label, fraction: fraction)
    }

    // DailyPace 仍为详情与提醒提供合成窗口；仅在圆环展示时恢复原来的额度顺序。
    static func originalQuotas(in snapshot: ProviderSnapshot) -> ProviderSnapshot {
        guard snapshot.headlineID == DailyPace.windowID else { return snapshot }
        var original = snapshot
        original.windows.removeAll { $0.id == DailyPace.windowID }
        if let ids = snapshot.dailyPaceOriginalQuotaIDs {
            original.headlineID = ids.headline
            original.weeklyID = ids.secondary
        } else {
            // 兼容旧合成快照；Claude 原生来源固定声明会话主环和周环，不按可用数据提升窗口。
            original.headlineID = "session"
            original.weeklyID = "weekly_all"
        }
        original.dailyPaceOriginalQuotaIDs = nil
        return original
    }
}
