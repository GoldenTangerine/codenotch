/**
 @name: 刘海触发高度
 @Descripttion: 统一触发高度范围和数字输入规则。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-09 09:50:29
 @LastEditTime: 2026-09-09 09:50:29
 @FilePath: Sources/Settings/NotchTriggerHeight.swift
 */
import Foundation

enum NotchTriggerHeight {
    static let range = -20...20
    static let defaultValue = 2

    static func clamp(_ value: Int) -> Int {
        min(range.upperBound, max(range.lowerBound, value))
    }

    static func parse(_ text: String) -> Int? {
        Int(text.trimmingCharacters(in: .whitespacesAndNewlines)).map(clamp)
    }

    static func committedValue(_ text: String, current: Int) -> Int {
        parse(text) ?? clamp(current)
    }
}
