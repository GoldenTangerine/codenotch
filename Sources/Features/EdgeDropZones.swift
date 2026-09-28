/**
 @name: 上游同步模块
 @Descripttion: 维护 EdgeDropZones.swift 的项目实现与上游兼容。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-11 15:51:14
 @LastEditTime: 2026-09-11 15:51:14
 @FilePath: Sources/Features/EdgeDropZones.swift
 */
import SwiftUI

/// The four places the notch can land, shown while one is being carried.
///
/// Drawn as the notch's own outline rather than as a generic rectangle: the
/// shape differs per edge — a side edge is a tall pill, a horizontal one is a
/// wide bar — and showing the real silhouette is what makes the choice legible
/// before you commit to it.
///
/// All four are always visible while carrying, and the one under the pointer
/// highlights only when the bar is centered. Showing only the nearest would mean discovering the
/// other three by sweeping the pointer around, which is the thing a preview is
/// supposed to save you from.
struct EdgeDropZones: View {
    /// The edge whose center currently holds the bar, if any.
    let target: NotchEdge?
    /// The screen this is covering, in its own local coordinates.
    let size: CGSize
    /// Actual centered landing frames in screen-local, top-left coordinates.
    let frames: [NotchEdge: CGRect]
    let hardwareNotch: HardwareNotch?
    let scale: CGFloat
    let accentColor: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Short dashes outline the actual bar footprint.
    private static let dash: [CGFloat] = [6, 5]
    /// A thin stroke keeps all four guides unobtrusive.
    private static let stroke: CGFloat = 2
    /// Unsnapped centers stay quiet while the snapped center is highlighted.
    private static let restingOpacity: CGFloat = 0.8

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(NotchEdge.allCases) { edge in
                zone(edge)
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }

    private func zone(_ edge: NotchEdge) -> some View {
        let isTarget = edge == target
        let frame = frames[edge] ?? .zero
        let path = SideNotchShape(edge: edge, joining: edge == .top ? hardwareNotch : nil)
            .renderedPath(in: CGRect(origin: .zero, size: frame.size), scale: scale)
        return ZStack {
            // A dark wash inside every zone, deeper on the target. It is what
            // separates a dashed outline from the wallpaper behind it — a
            // stroke alone disappears over a light or busy desktop, which is
            // exactly where you most need to see where the notch can go.
            path.fill(Color.black.opacity(isTarget ? 0.18 : 0.06))
            // Black backing and white ink remain readable independently of the wallpaper and theme.
            path.stroke(Color.black.opacity(0.85),
                        style: StrokeStyle(lineWidth: Self.stroke + 3, lineCap: .round, dash: Self.dash))
            path.stroke(
                Color.white.opacity(isTarget ? 1 : Self.restingOpacity),
                style: StrokeStyle(lineWidth: Self.stroke, lineCap: .round, dash: Self.dash)
            )
            if isTarget {
                path.stroke(accentColor, style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: Self.dash))
            }
        }
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
            .animation(
                NotchMotion.respectingReduceMotion(
                    .spring(response: 0.3, dampingFraction: 0.75), reduceMotion
                ),
                value: isTarget
            )
    }

    /// The edge whose zone contains `point`, or the nearest one within reach.
    ///
    /// Nearest-edge rather than strict hit testing: the zones are thin, and
    /// requiring the pointer to land inside a 40pt strip would make dropping
    /// feel like threading a needle. The screen is split into four triangles
    /// about its centre, so every point on it belongs to exactly one edge.
    static func edge(at point: CGPoint, in size: CGSize) -> NotchEdge {
        let dxLeft = point.x
        let dxRight = size.width - point.x
        let dyTop = point.y
        let dyBottom = size.height - point.y
        let nearest = min(dxLeft, dxRight, dyTop, dyBottom)
        if nearest == dxRight { return .right }
        if nearest == dxLeft { return .left }
        if nearest == dyTop { return .top }
        return .bottom
    }
}
