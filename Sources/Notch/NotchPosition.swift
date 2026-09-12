/**
 @name: 显示栏位置
 @Descripttion: 保存显示栏锚点并计算跨屏吸附与沿边布局。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-08 14:12:37
 @LastEditTime: 2026-09-08 14:12:37
 @FilePath: Sources/Notch/NotchPosition.swift
 */
import AppKit

struct NotchPosition: Codable, Equatable {
    var edge: NotchEdge
    var fraction: Double = 0.5
    var displayID: String?

    var normalizedFraction: CGFloat {
        fraction.isFinite ? CGFloat(min(1, max(0, fraction))) : 0.5
    }

    var joinsHardware: Bool { edge == .top && normalizedFraction == 0.5 }

    static func snapped(to point: CGPoint, on screen: ScreenDescribing,
                        displayID: String?, previous: NotchPosition) -> NotchPosition {
        let frame = screen.visibleFrameValue
        let distances: [(NotchEdge, CGFloat)] = [
            (.left, abs(point.x - frame.minX)), (.right, abs(point.x - frame.maxX)),
            (.top, abs(point.y - frame.maxY)), (.bottom, abs(point.y - frame.minY))
        ]
        let nearest = distances.min { $0.1 < $1.1 }!
        let current = distances.first { $0.0 == previous.edge }!
        let edge = previous.displayID == displayID && current.1 <= nearest.1 + 12
            ? previous.edge : nearest.0
        return NotchPosition(edge: edge, displayID: displayID)
            .movingAlong(to: point, on: screen, previous: previous)
    }

    func movingAlong(to point: CGPoint, on screen: ScreenDescribing,
                     previous: NotchPosition) -> NotchPosition {
        let frame = screen.visibleFrameValue
        var fraction = edge.isVertical
            ? (frame.maxY - point.y) / max(1, frame.height)
            : (point.x - frame.minX) / max(1, frame.width)
        if edge == .top, screen.hardwareNotch != nil {
            let radius: CGFloat = previous.displayID == displayID && previous.joinsHardware ? 36 : 24
            if abs(point.x - screen.frameValue.midX) <= radius { fraction = 0.5 }
        }
        return NotchPosition(edge: edge, fraction: Double(min(1, max(0, fraction))), displayID: displayID)
    }

    /// Keep the visible bar near the pointer while moving transparent tooltip space inward.
    func layout(on screen: ScreenDescribing, panelSize: CGSize, shapeLength: CGFloat,
                endClearance: CGFloat, startClearance: CGFloat = 0) -> (frame: CGRect, leading: CGFloat) {
        let usable = screen.visibleFrameValue
        let total = edge.isVertical ? usable.height : usable.width
        let panelLength = edge.isVertical ? panelSize.height.rounded(.up) : panelSize.width.rounded(.up)
        let barStart = min(max(0, total - shapeLength - endClearance),
                           max(startClearance, normalizedFraction * total - shapeLength / 2))
        let panelStart = min(max(0, total - panelLength),
                             max(0, barStart - (panelLength - shapeLength) / 2))
        var frame = NotchGeometry.panelFrame(for: screen, panelSize: panelSize, edge: edge)
        if edge.isVertical {
            frame.origin.y = (usable.maxY - panelStart - frame.height).rounded()
            return (frame, (frame.maxY - usable.maxY + barStart).rounded())
        }
        frame.origin.x = (usable.minX + panelStart).rounded()
        if edge == .top {
            frame.origin.y = ((joinsHardware && screen.hardwareNotch != nil
                ? screen.frameValue.maxY : usable.maxY) - frame.height).rounded()
        } else if edge == .bottom {
            frame.origin.y = usable.minY.rounded()
        }
        let center = joinsHardware && screen.hardwareNotch != nil ? screen.frameValue.midX : nil
        return (frame, ((center.map { $0 - shapeLength / 2 } ?? (usable.minX + barStart)) - frame.minX).rounded())
    }
}

extension NSScreen {
    var notchDisplayID: String? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue()
        else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    static func notchScreen(for position: NotchPosition, screens: [NSScreen] = NSScreen.screens) -> NSScreen? {
        screens.first { position.displayID != nil && $0.notchDisplayID == position.displayID }
            ?? screens.first { $0.frame.origin == .zero } ?? screens.first
    }

    static func notchScreen(at point: CGPoint) -> NSScreen? {
        screens.min { lhs, rhs in
            func distance(_ frame: CGRect) -> CGFloat {
                hypot(max(frame.minX - point.x, 0, point.x - frame.maxX),
                      max(frame.minY - point.y, 0, point.y - frame.maxY))
            }
            return distance(lhs.frame) < distance(rhs.frame)
        }
    }
}
