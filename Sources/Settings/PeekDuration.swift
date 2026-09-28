/**
 @name: PeekDuration 本地化
 @Descripttion: 提供模块功能及可本地化的用户文案。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-08 22:41:26
 @LastEditTime: 2026-09-08 22:41:26
 @FilePath: Sources/Settings/PeekDuration.swift
 */
import Foundation

/// How long the notch stays open when it opens by itself.
///
/// A fixed set rather than a free number: the useful range is narrow, and the
/// values outside it are worse than they look. Below a second or two the notch
/// is gone before a glance can land on it; much beyond ten it stops reading as
/// an announcement and starts being a thing parked on the screen edge that has
/// to be waited out.
enum PeekDuration: String, CaseIterable, Identifiable {
    case brief
    case standard
    case long

    var id: String { rawValue }

    var seconds: TimeInterval {
        switch self {
        case .brief:    return 3
        case .standard: return 5
        case .long:     return 10
        }
    }

    var title: String {
        switch self {
        case .brief:    return L10n.t("3 seconds")
        case .standard: return L10n.t("5 seconds")
        case .long:     return L10n.t("10 seconds")
        }
    }

    var explanation: String {
        switch self {
        case .brief:
            return L10n.t("Long enough to notice, short enough to ignore.")
        case .standard:
            return L10n.t("Long enough to read the session's name and reach for it.")
        case .long:
            return L10n.t("Stays until you have had a chance to look up.")
        }
    }
}
