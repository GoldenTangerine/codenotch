/**
 @name: 后台光标实测
 @Descripttion: 在非激活浮窗中验证系统实际手形光标与焦点保持。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-21 11:42:55
 @LastEditTime: 2026-09-21 11:42:55
 @FilePath: Scripts/test-background-cursor.swift
 */
import AppKit

// 在有桌面会话的 macOS 上运行，无需 Xcode 工程或完整应用依赖：
// swiftc Sources/Notch/BackgroundCursorAccess.swift Sources/Notch/NotchPanel.swift \
//   Scripts/test-background-cursor.swift -o /tmp/codenotch-background-cursor-test
// /tmp/codenotch-background-cursor-test
// 测试会在鼠标处短暂显示浮窗；仅读取系统光标图像，不捕获桌面内容。
@main
struct BackgroundCursorSmokeTest {
    @MainActor
    static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let foreground = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let original = NSCursor.currentSystem
        guard let original, foreground != nil, !app.isActive else {
            throw Failure(message: "Requires an inactive process in a live macOS desktop session")
        }
        let pointer = NSEvent.mouseLocation
        let frame = CGRect(x: pointer.x - 50, y: pointer.y - 35, width: 100, height: 70)
        let baseline = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        baseline.level = .statusBar
        baseline.hidesOnDeactivate = false
        baseline.isReleasedWhenClosed = false
        baseline.contentView = NSView(frame: CGRect(origin: .zero, size: frame.size))
        baseline.orderFrontRegardless()
        settle()
        let before = try systemImage()
        NSCursor.pointingHand.push()
        settle()
        let baselineChanged = try systemImage() != before
        NSCursor.pop()
        baseline.orderOut(nil)
        print("Baseline: local hand was requested; system cursor changed = \(baselineChanged)")

        let panel = NotchPanel(contentRect: frame)
        defer {
            panel.orderOut(nil)
            original.set()
        }
        guard BackgroundCursorAccess.isEnabled else {
            throw Failure(message: "WindowServer background cursor access is unavailable")
        }
        panel.contentView = NSView(frame: CGRect(origin: .zero, size: frame.size))
        panel.orderFrontRegardless()
        settle()
        NSCursor.arrow.set()
        settle()
        let restored = try systemImage()
        NSCursor.pointingHand.push()
        var didPop = false
        defer { if !didPop { NSCursor.pop() } }
        settle()
        guard let target = NSCursor.pointingHand.image.tiffRepresentation,
              try systemImage() == target else {
            throw Failure(message: "System cursor did not become a pointing hand")
        }
        NSCursor.pop()
        didPop = true
        settle()
        guard try systemImage() == restored else {
            throw Failure(message: "System cursor was not restored after leaving")
        }
        guard !app.isActive, !panel.isKeyWindow,
              foreground == NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            throw Failure(message: "Changing the cursor stole foreground focus")
        }
        print("PASS: actual system pointing hand, cursor restoration, inactive panel, unchanged foreground")
    }

    @MainActor
    private static func settle() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.08))
    }

    @MainActor
    private static func systemImage() throws -> Data {
        guard let data = NSCursor.currentSystem?.image.tiffRepresentation else {
            throw Failure(message: "System cursor image is unavailable; local NSCursor.current is not proof")
        }
        return data
    }

    private struct Failure: Error {
        let message: String
    }
}
