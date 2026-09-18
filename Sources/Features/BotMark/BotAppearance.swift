/**
 @name: 机器人外观与动画
 @Descripttion: 管理机器人显示配置、预览与按可见性运行的动画。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-18 10:21:17
 @LastEditTime: 2026-09-18 10:21:17
 @FilePath: Sources/Features/BotMark/BotAppearance.swift
 */
import AppKit
import SwiftUI

struct BotAppearance: Codable, Equatable {
    var enabled = false
    var personality: String?
    var shape = BotMarkBody.default.rawValue
    var rgb: UInt32?

    init() {}

    private enum CodingKeys: String, CodingKey { case enabled, personality, shape, rgb }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? values.decode(Bool.self, forKey: .enabled)) ?? false
        personality = (try? values.decode(String.self, forKey: .personality))
            .flatMap(BotMarkPersona.init(rawValue:))?.rawValue
        shape = (try? values.decode(String.self, forKey: .shape))
            .flatMap(BotMarkBody.init(rawValue:))?.rawValue ?? BotMarkBody.default.rawValue
        rgb = (try? values.decode(UInt32.self, forKey: .rgb)).flatMap { $0 <= 0xFFFFFF ? $0 : nil }
    }

    // 不使用 Swift 的进程随机哈希，以保证自动外观在重启和排序后稳定。
    static func stableIndex(_ id: String, count: Int) -> Int {
        let hash = id.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        return Int(hash % UInt64(max(1, count)))
    }

    func persona(for id: String) -> BotMarkPersona {
        personality.flatMap(BotMarkPersona.init(rawValue:))
            ?? BotMarkPersona.allCases[Self.stableIndex(id, count: BotMarkPersona.allCases.count)]
    }

    func color(for id: String, brand: String) -> Color {
        if let rgb { return BotMarkPalette.rgb(rgb) }
        let name = brand.lowercased()
        let brands: [(String, UInt32)] = [
            ("claude", 0xD97757), ("deepseek", 0x4D6BFE), ("gemini", 0x4285F4),
            ("antigravity", 0x4285F4), ("minimax", 0xE8483F), ("kimi", 0x2F6BFF),
            ("glm", 0x3A7BF7), ("volcengine", 0x1664FF)
        ]
        if let color = brands.first(where: { name.contains($0.0) })?.1 { return BotMarkPalette.rgb(color) }
        let palette: [UInt32] = [0x78B6FF, 0xF5BC68, 0xB798EE, 0x6ED8BA, 0xF295B6,
                                 0xA6CD75, 0x77CFDF, 0xECA486]
        return BotMarkPalette.rgb(palette[Self.stableIndex(id, count: palette.count)])
    }

    static func rgbValue(_ color: Color) -> UInt32 {
        guard let value = NSColor(color).usingColorSpace(.sRGB) else { return 0x78B6FF }
        func channel(_ value: CGFloat) -> UInt32 { UInt32((min(1, max(0, value)) * 255).rounded()) }
        return channel(value.redComponent) << 16 | channel(value.greenComponent) << 8 | channel(value.blueComponent)
    }

    static func eyeColor(for color: Color) -> Color {
        let rgb = rgbValue(color)
        let lightness = (Double(rgb >> 16) * 0.2126 + Double((rgb >> 8) & 255) * 0.7152
                         + Double(rgb & 255) * 0.0722) / 255
        return lightness > 0.48 ? Color(white: 0.06) : .white
    }
}

enum BotMarkGaze: Double, CaseIterable {
    case left = -1, ahead = 0, right = 1
}

struct BotPresentation: Equatable {
    var id: String
    var brand: String
    var appearance: BotAppearance
    var mood: BotMarkMood = .idle
    var waiting = false
    var active = true
    var gazeBias = 0.0
    var gaze: BotMarkGaze = .ahead
    var pointerRegion: CGPath?
    var event: BotAnimationEvent?
    var lastActivity: Date?
    var globallyBusy = false

    func isQuiet(at date: Date) -> Bool {
        !globallyBusy && lastActivity.map { date.timeIntervalSince($0) > 1200 } == true
    }

    static func mood(activity: ActivitySummary.State?, refreshing: Bool,
                     spent: Bool, hasReading: Bool) -> BotMarkMood {
        if activity == .waiting { return .idle }
        return BotMarkMood.resolve(isBusy: activity == .working, isRefreshing: refreshing,
                                   isSpent: spent, hasReading: hasReading)
    }
}

struct BotAnimationEvent: Equatable {
    let id: UUID
    let kind: BotMarkEvent
    let occurredAt: Date

    init(kind: BotMarkEvent, now: Date = Date()) {
        id = UUID()
        self.kind = kind
        occurredAt = now
    }
}
