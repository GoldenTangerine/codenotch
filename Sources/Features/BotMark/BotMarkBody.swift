/**
 @name: 动态机器人 · BotMarkBody
 @Descripttion: 移植 Pulse 机器人动作与几何实现并适配本项目。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-18 10:13:39
 @LastEditTime: 2026-09-18 10:13:39
 @FilePath: Sources/Features/BotMark/BotMarkBody.swift
 */
// Adapted from Pulse (Apache-2.0); see Resources/BotMark-NOTICE.txt.
import Foundation

/// The body a mark wears.
///
/// The upstream carries eighteen of these, all sampled to the same 96-point
/// ring so any one blends into any other. Which one a ring uses is the
/// reader's choice and nothing else's: it is not a reading, and it is not
/// dealt out — **every mark is round until somebody changes it**, because a
/// rail whose shapes were assigned by the app would be saying something with
/// them, and there is nothing to say.
///
/// A raw-value enum rather than the bare strings the engine takes, so a
/// stored choice that no longer exists falls back rather than drawing nothing.
enum BotMarkBody: String, CaseIterable, Identifiable, Sendable {
    case blob
    case pebble
    case bean
    case egg
    case squircle
    case tablet
    case capsule
    case cylinder
    case hex
    case gem
    case crystal
    case wedge
    case shield
    case dome
    case arch
    case cloud
    case teardrop
    case leaf

    static let `default` = BotMarkBody.blob

    var id: String { rawValue }

    /// The id the engine's shape table is keyed by.
    var shape: String { rawValue }

    /// The name in the settings picker. Localized like the other settings
    /// enums, and rendered with `Text(body.title)`.
    var title: String {
        switch self {
        case .blob: L10n.t("Blob")
        case .pebble: L10n.t("Pebble")
        case .bean: L10n.t("Bean")
        case .egg: L10n.t("Egg")
        case .squircle: L10n.t("Squircle")
        case .tablet: L10n.t("Tablet")
        case .capsule: L10n.t("Capsule")
        case .cylinder: L10n.t("Cylinder")
        case .hex: L10n.t("Hexagon")
        case .gem: L10n.t("Gem")
        case .crystal: L10n.t("Crystal")
        case .wedge: L10n.t("Wedge")
        case .shield: L10n.t("Shield")
        case .dome: L10n.t("Dome")
        case .arch: L10n.t("Arch")
        case .cloud: L10n.t("Cloud")
        case .teardrop: L10n.t("Teardrop")
        case .leaf: L10n.t("Leaf")
        }
    }
}
