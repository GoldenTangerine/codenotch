/**
 @name: 上游同步模块
 @Descripttion: 维护 DropZoneOverlay.swift 的项目实现与上游兼容。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-11 15:51:14
 @LastEditTime: 2026-09-11 15:51:14
 @FilePath: Sources/Notch/DropZoneOverlay.swift
 */
import AppKit
import SwiftUI

/// The full-screen surface the drop zones are drawn on.
///
/// A window of its own rather than something inside `NotchPanel`: the panel is
/// a thin strip welded to one edge, and the zones have to be visible on all
/// four at once. It is click-through everywhere so either editing entry point
/// can keep receiving drag and cancellation events through the notch panel.
@MainActor
final class DropZoneOverlay {
    private var window: NSWindow?
    private var hosting: NSHostingView<EdgeDropZones>?
    private let screen: NSScreen
    private var presentation: Presentation?
    private struct Presentation: Equatable {
        let target: NotchEdge?
        let frames: [NotchEdge: CGRect]
        let hardware: HardwareNotch?
        let scale: CGFloat
        let accent: AccentColorChoice
    }
    var windowForTesting: NSWindow? { window }
    var targetForTesting: NotchEdge? { presentation?.target }

    init(screen: NSScreen) {
        self.screen = screen
    }

    /// Puts the zones on screen, or updates which one is highlighted.
    func show(target: NotchEdge?, frames: [NotchEdge: CGRect], hardwareNotch: HardwareNotch?,
              scale: CGFloat, accent: AccentColorChoice) {
        let next = Presentation(target: target, frames: frames, hardware: hardwareNotch, scale: scale, accent: accent)
        guard presentation != next else { return }
        presentation = next
        let frame = screen.frame
        let view = EdgeDropZones(
            target: target,
            size: frame.size,
            frames: frames,
            hardwareNotch: hardwareNotch,
            scale: scale,
            accentColor: accent.color
        )

        if let hosting {
            hosting.rootView = view
            return
        }

        let hostingView = NSHostingView(rootView: view)
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // Strictly below the notch, so the thing being carried stays on top of
        // the places it can go. Sharing `.statusBar` is not enough: the
        // overlay is ordered front later, and same-level windows stack by
        // order — the zones would cover the notch and the hand holding it.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.contentView = hostingView
        panel.setFrame(frame, display: false)
        if !Runtime.isUnderTest { panel.orderFront(nil) }

        window = panel
        hosting = hostingView
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
        hosting = nil
        presentation = nil
    }

    /// Converts a screen point into this overlay's own top-left-origin space,
    /// which is what `EdgeDropZones.edge(at:in:)` expects — AppKit's screen
    /// coordinates grow upward, SwiftUI's grow down.
    func localPoint(from screenPoint: CGPoint) -> CGPoint {
        let frame = screen.frame
        return CGPoint(x: screenPoint.x - frame.minX,
                       y: frame.maxY - screenPoint.y)
    }

    var screenSize: CGSize { screen.frame.size }
}
