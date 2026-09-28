/**
 @name: 上游同步模块
 @Descripttion: 维护 AntigravityHeadlineModel.swift 的项目实现与上游兼容。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-11 15:51:14
 @LastEditTime: 2026-09-11 15:51:14
 @FilePath: Sources/Settings/AntigravityHeadlineModel.swift
 */
import Foundation

enum AntigravityHeadlineModel: String, CaseIterable, Identifiable {
    case gemini = "gemini"
    case thirdParty = "3p"

    var id: String { rawValue }

    var explanation: String {
        switch self {
        case .gemini: return L10n.t("Gemini Models")
        case .thirdParty: return L10n.t("Claude and GPT models")
        }
    }
}
