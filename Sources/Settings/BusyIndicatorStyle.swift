/**
 @name: 忙碌指示样式
 @Descripttion: 定义旋转弧线与呼吸圆盘两种工作指示。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-10-15 16:20:00
 @LastEditTime: 2026-10-15 16:20:00
 @FilePath: Sources/Settings/BusyIndicatorStyle.swift
 */
import SwiftUI

/// How a provider's ring shows that one of its agents is working right now.
///
/// Raw values are persistence keys, not display copy. The default is `.arc` for the same reason
/// `ColorTransitionStyle` defaults to `.hardStep`: a visual change to every existing user's notch
/// must be something they opt into, not something that reaches them unannounced the next time the
/// app updates.
///
/// One switch covers the disc's brand colour, its faster breath while requests are queued and its
/// staying bright over a stale reading. Those are what make the disc readable at a glance; offered
/// as separate settings they would only produce combinations nobody asked for.
enum BusyIndicatorStyle: String, CaseIterable, Identifiable {
    /// The original behaviour: a thin white quarter-arc turning inside the ring, which becomes a
    /// ring of dots while requests are queued.
    case arc
    /// `BusyWave` — a disc in the provider's brand colour breathing under its glyph, faster while
    /// requests are queued, and not dimmed with a stale reading.
    case breath

    var id: String { rawValue }

    var title: String {
        switch self {
        case .arc: return L10n.t("Spinning arc")
        case .breath: return L10n.t("Breathing disc")
        }
    }

    var explanation: String {
        switch self {
        case .arc:
            return L10n.t("A thin white arc turns inside the ring while an agent works; queued requests become a ring of dots.")
        case .breath:
            return L10n.t("A disc in the provider's brand colour breathes under its mark while an agent works, faster when requests are queued.")
        }
    }
}

private struct BusyIndicatorStyleKey: EnvironmentKey {
    static let defaultValue = BusyIndicatorStyle.arc
}

extension EnvironmentValues {
    var busyIndicatorStyle: BusyIndicatorStyle {
        get { self[BusyIndicatorStyleKey.self] }
        set { self[BusyIndicatorStyleKey.self] = newValue }
    }
}
