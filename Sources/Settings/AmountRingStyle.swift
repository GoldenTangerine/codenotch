/**
 @name: 金额圆环样式
 @Descripttion: 定义金额读数的圆环样式和设置选项。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-11-18 14:22:49
 @LastEditTime: 2026-11-18 14:22:49
 @FilePath: Sources/Settings/AmountRingStyle.swift
 */
import Foundation

enum AmountRingStyle: String, CaseIterable, Identifiable {
    case single
    case solidOuter
    case dashedOuter
    case solidAndDashedOuter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .single: return L10n.t("Full ring")
        case .solidOuter: return L10n.t("Full ring + solid outer ring")
        case .dashedOuter: return L10n.t("Full ring + dashed outer ring")
        case .solidAndDashedOuter: return L10n.t("Full ring + solid and dashed outer rings")
        }
    }
}
