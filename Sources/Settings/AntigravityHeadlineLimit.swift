/**
 @name: 上游同步模块
 @Descripttion: 维护 AntigravityHeadlineLimit.swift 的项目实现与上游兼容。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-11 15:51:14
 @LastEditTime: 2026-09-11 15:51:14
 @FilePath: Sources/Settings/AntigravityHeadlineLimit.swift
 */
import Foundation

enum AntigravityHeadlineLimit: String, CaseIterable, Identifiable {
    case automatic = "automatic"
    case fiveHour = "5h"
    case weekly = "weekly"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return L10n.t("Automatic")
        case .fiveHour: return L10n.t("5-Hour Limit")
        case .weekly: return L10n.t("Weekly Limit")
        }
    }

    var explanation: String { title }
}
