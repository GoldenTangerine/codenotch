/**
 @name: 气泡高度模式
 @Descripttion: 定义详情气泡的显示模式和屏幕高度约束。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-09 15:32:59
 @LastEditTime: 2026-09-09 15:32:59
 @FilePath: Sources/Notch/TooltipHeightMode.swift
 */
import Foundation

enum TooltipHeightMode: String, CaseIterable, Identifiable {
    case standard, full

    var id: String { rawValue }
    var title: String {
        switch self {
        case .standard: return L10n.t("Default")
        case .full: return L10n.t("Show all")
        }
    }
}

enum TooltipSizing {
    static let screenMargin: CGFloat = 8

    static func sidePanelLayout(usable: CGRect, standardFrame: CGRect, standardSlack: CGFloat,
                                size: CGSize, shapeLength: CGFloat) -> (frame: CGRect, leading: CGFloat) {
        let notchTop = standardFrame.maxY - standardSlack
        // 旧沿边偏移允许刘海进入菜单栏或 Dock 区域；窗口必须保留本体及设置按钮热区。
        let bottom = min(usable.minY, notchTop - shapeLength - NotchLayout.orbHotZone / 2).rounded(.down)
        let top = max(usable.maxY, notchTop).rounded(.up)
        let frame = CGRect(x: standardFrame.minX, y: bottom, width: size.width, height: top - bottom)
        return (frame, frame.maxY - notchTop)
    }

    static func height(natural: CGFloat, limit: CGFloat) -> CGFloat {
        let safeLimit = limit.isFinite ? max(1, limit.rounded(.down)) : 1
        guard natural.isFinite, natural > 0 else { return safeLimit }
        return min(safeLimit, natural.rounded(.up))
    }

    static func heightLimit(on screen: ScreenDescribing, edge: NotchEdge, contentInset: CGFloat) -> CGFloat {
        let usable = screen.visibleFrameValue
        if edge.isVertical { return max(1, usable.height - 2 * screenMargin) }
        let topInset = edge == .top
            ? max(0, contentInset - (screen.frameValue.maxY - usable.maxY)) : contentInset
        return max(1, usable.height - topInset - NotchLayout.bodyDepth(for: edge)
                   - NotchLayout.tailLength - NotchLayout.tailGap - screenMargin)
    }
}
