/**
 @name: 刘海触发高度行为测试
 @Descripttion: 验证输入规则与静止鼠标下的触发及事件穿透。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-09 09:50:29
 @LastEditTime: 2026-09-09 09:50:29
 @FilePath: Tests/NotchTriggerHeightTests.swift
 */
import AppKit
import XCTest
@testable import Codenotch

final class NotchTriggerInputTests: XCTestCase {
    func testSignedAndOutOfRangeInput() {
        for (text, expected) in [("-2", -2), ("0", 0), ("+2", 2), (" 6 ", 6), ("100", 20), ("-100", -20)] {
            XCTAssertEqual(NotchTriggerHeight.parse(text), expected)
            XCTAssertEqual(NotchTriggerHeight.committedValue(text, current: 2), expected)
        }
    }

    func testIncompleteAndInvalidInputKeepsLastValidValue() {
        for text in ["", "-", "+", "abc", "1.5", "999999999999999999999999999"] {
            XCTAssertNil(NotchTriggerHeight.parse(text))
            XCTAssertEqual(NotchTriggerHeight.committedValue(text, current: -2), -2)
        }
    }
}

@MainActor
final class NotchTriggerInteractionTests: XCTestCase {
    private final class InteractionClock {
        private var now: TimeInterval = 0
        private var pending: [(deadline: TimeInterval, work: DispatchWorkItem)] = []

        func schedule(_ delay: TimeInterval, _ work: DispatchWorkItem) {
            pending.append((now + delay, work))
        }

        func advance(to time: TimeInterval) {
            precondition(time >= now)
            while let next = pending.indices.min(by: { pending[$0].deadline < pending[$1].deadline }),
                  pending[next].deadline <= time {
                let item = pending.remove(at: next)
                now = item.deadline
                if !item.work.isCancelled { item.work.perform() }
            }
            now = time
        }
    }

    func testHoverDelayOpensWithStationaryCursor() {
        let clock = InteractionClock()
        let (controller, _) = makeController(depth: 20, clock: clock)
        defer { controller.stop() }
        controller.apply(notchHoverDelay: 0.5)
        clock.advance(to: 0.499)
        XCTAssertFalse(controller.model.isExpanded)
        clock.advance(to: 0.5)
        XCTAssertTrue(controller.model.isExpanded)
    }

    func testLeavingCancelsAndReentryStartsNewDelay() {
        let clock = InteractionClock()
        let panel = NotchPanel(contentRect: CGRect(x: 0, y: 0, width: 600, height: 600))
        var depth: CGFloat = 20
        let controller = NotchWindowController(panel: panel, mouseLocation: {
            CGPoint(x: panel.frame.minX + 200, y: panel.frame.maxY - depth)
        }, scheduleInteractionWork: clock.schedule)
        defer { controller.stop() }
        controller.model.edge = .top
        controller.model.hardwareNotch = HardwareNotch(width: 200, height: 32)
        controller.model.positionedLeading = 200 - controller.model.shapeLength / 2
        controller.apply(notchHoverDelay: 0.5)
        clock.advance(to: 0.2)
        depth = 300
        controller.cursorMoved()
        clock.advance(to: 0.25)
        depth = 20
        controller.cursorMoved()
        clock.advance(to: 0.5)
        XCTAssertFalse(controller.model.isExpanded, "The cancelled first entry must not open the notch")
        clock.advance(to: 0.749)
        XCTAssertFalse(controller.model.isExpanded)
        clock.advance(to: 0.75)
        XCTAssertTrue(controller.model.isExpanded)
    }

    func testContinuousMouseEventsDoNotRestartDelay() {
        let clock = InteractionClock()
        let (controller, _) = makeController(depth: 20, clock: clock)
        defer { controller.stop() }
        controller.apply(notchHoverDelay: 0.5)
        for time in [0.1, 0.2, 0.3, 0.4, 0.499] {
            clock.advance(to: time)
            controller.cursorMoved()
            XCTAssertFalse(controller.model.isExpanded)
        }
        clock.advance(to: 0.5)
        XCTAssertTrue(controller.model.isExpanded)
    }

    func testZeroDelayAppliesImmediatelyWhileWaiting() {
        let (controller, _) = makeController(depth: 20)
        defer { controller.stop() }
        controller.apply(notchHoverDelay: 1)
        XCTAssertFalse(controller.model.isExpanded)
        controller.apply(notchHoverDelay: 0)
        XCTAssertTrue(controller.model.isExpanded)
    }

    func testSnapshotLayoutRefreshPreservesPendingDeadline() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let clock = InteractionClock()
        let panel = NotchPanel(contentRect: CGRect(x: 0, y: 0, width: 600, height: 600))
        var pointer = CGPoint(x: -10000, y: -10000)
        let controller = NotchWindowController(panel: panel, mouseLocation: { pointer },
                                               scheduleInteractionWork: clock.schedule)
        defer { controller.stop() }
        controller.assignedScreen = screen
        controller.model.edge = .top
        controller.model.updateSnapshots([
            ProviderSnapshot(id: "p", displayName: "P", glyph: .claude,
                             fidelity: .official, status: .ok, windows: [])
        ])
        controller.relocate()
        pointer = CGPoint(x: panel.frame.minX + controller.model.slack + controller.model.shapeLength / 2,
                          y: panel.frame.maxY - 1)
        controller.apply(notchHoverDelay: 0.5)
        let originalFrame = panel.frame
        for time in [0.1, 0.2, 0.3, 0.4] {
            clock.advance(to: time)
            controller.model.updateSnapshots([
                ProviderSnapshot(id: "p", displayName: "P \(time)", glyph: .claude,
                                 fidelity: .official, status: .ok, windows: [])
            ])
            // 与快照订阅的布局刷新路径一致，触发区域没有移动。
            controller.relocate()
            XCTAssertEqual(panel.frame, originalFrame)
            XCTAssertFalse(controller.model.isExpanded)
        }
        clock.advance(to: 0.5)
        XCTAssertTrue(controller.model.isExpanded)
    }

    func testLayoutRefreshCancelsWhenPointerIsOutside() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let clock = InteractionClock()
        let panel = NotchPanel(contentRect: CGRect(x: 0, y: 0, width: 600, height: 600))
        var pointer = CGPoint(x: -10000, y: -10000)
        let controller = NotchWindowController(panel: panel, mouseLocation: { pointer },
                                               scheduleInteractionWork: clock.schedule)
        defer { controller.stop() }
        controller.assignedScreen = screen
        controller.model.edge = .top
        controller.relocate()
        let inside = CGPoint(x: panel.frame.minX + controller.model.slack + controller.model.shapeLength / 2,
                             y: panel.frame.maxY - 1)
        pointer = inside
        controller.apply(notchHoverDelay: 0.5)
        clock.advance(to: 0.2)
        pointer = CGPoint(x: -10000, y: -10000)
        controller.relocate()
        pointer = inside
        clock.advance(to: 0.5)
        XCTAssertFalse(controller.model.isExpanded)
        controller.cursorMoved()
        clock.advance(to: 1)
        XCTAssertTrue(controller.model.isExpanded)
    }

    func testExpandedCardsSwitchImmediatelyAndKeepExistingExitDelays() {
        let clock = InteractionClock()
        let panel = NotchPanel(contentRect: CGRect(x: 0, y: 0, width: 600, height: 600))
        var local = CGPoint(x: 200, y: 20)
        let controller = NotchWindowController(panel: panel, mouseLocation: {
            CGPoint(x: panel.frame.minX + local.x, y: panel.frame.maxY - local.y)
        }, scheduleInteractionWork: clock.schedule)
        defer { controller.stop() }
        controller.foldsForFullScreen = false
        controller.model.edge = .top
        controller.model.positionedLeading = 100
        controller.model.updateSnapshots((0..<2).map {
            ProviderSnapshot(id: "p\($0)", displayName: "P", glyph: .claude,
                             fidelity: .official, status: .ok, windows: [])
        })
        controller.apply(notchHoverDelay: 1)
        controller.handleClick(at: .zero)
        for index in 0..<2 {
            local.x = controller.model.slack + controller.model.ringCenter(index: index)
            controller.cursorMoved()
            XCTAssertEqual(controller.model.hoveredIndex, index)
        }
        local = CGPoint(x: -1000, y: -1000)
        controller.cursorMoved()
        clock.advance(to: 0.249)
        XCTAssertEqual(controller.model.hoveredIndex, 1)
        clock.advance(to: 0.25)
        XCTAssertNil(controller.model.hoveredIndex)
        clock.advance(to: 0.449)
        XCTAssertTrue(controller.model.isExpanded)
        clock.advance(to: 0.45)
        XCTAssertFalse(controller.model.isExpanded)
    }

    func testExplicitClickBypassesHoverDelay() {
        let (controller, _) = makeController(depth: 20)
        defer { controller.stop() }
        controller.apply(notchHoverDelay: 1)
        XCTAssertFalse(controller.model.isExpanded)
        controller.handleClick(at: .zero)
        XCTAssertTrue(controller.model.isExpanded)
        XCTAssertFalse(controller.model.isPinned)
    }

    func testHiddenAndStoppedControllersCancelPendingExpansion() {
        for hidden in [false, true] {
            let clock = InteractionClock()
            let (controller, _) = makeController(depth: 20, clock: clock)
            controller.apply(notchHoverDelay: 0.1)
            if hidden { controller.apply(.hidden) }
            else { controller.stop() }
            clock.advance(to: 0.2)
            XCTAssertFalse(controller.model.isExpanded)
            controller.stop()
        }
    }

    private func makeController(depth: CGFloat, clock: InteractionClock = InteractionClock()) -> (NotchWindowController, NotchPanel) {
        let panel = NotchPanel(contentRect: CGRect(x: 0, y: 0, width: 600, height: 600))
        let controller = NotchWindowController(panel: panel, mouseLocation: {
            CGPoint(x: panel.frame.minX + 200, y: panel.frame.maxY - depth)
        }, scheduleInteractionWork: clock.schedule)
        controller.model.edge = .top
        controller.model.hardwareNotch = HardwareNotch(width: 200, height: 32)
        controller.model.positionedLeading = 200 - controller.model.shapeLength / 2
        return (controller, panel)
    }

    func testStationaryCursorStartsActivatingWhenHeightIncreases() {
        let (controller, panel) = makeController(depth: 33)
        defer { controller.stop() }
        controller.apply(notchTriggerHeight: 0)
        XCTAssertFalse(controller.model.isExpanded)
        XCTAssertTrue(panel.ignoresMouseEvents)
        controller.apply(notchTriggerHeight: 2)
        XCTAssertTrue(controller.model.isExpanded)
        XCTAssertFalse(panel.ignoresMouseEvents)
        XCTAssertFalse(panel.isVisible)
    }

    func testNegativeHeightRequiresEnteringFurtherIntoHardware() {
        let (controller, panel) = makeController(depth: 31)
        defer { controller.stop() }
        controller.apply(notchTriggerHeight: -2)
        XCTAssertFalse(controller.model.isExpanded)
        XCTAssertTrue(panel.ignoresMouseEvents)
        controller.apply(notchTriggerHeight: 0)
        XCTAssertTrue(controller.model.isExpanded)
        XCTAssertFalse(panel.ignoresMouseEvents)
    }

    func testShrinkingHeightRefreshesPassThroughWhileEditing() {
        let (controller, panel) = makeController(depth: 33)
        defer { controller.stop() }
        controller.model.isEditingPosition = true
        controller.apply(notchTriggerHeight: 2)
        XCTAssertFalse(panel.ignoresMouseEvents)
        controller.apply(notchTriggerHeight: -2)
        XCTAssertTrue(panel.ignoresMouseEvents)
        XCTAssertFalse(controller.model.isExpanded)
    }

    func testChangingHeightDoesNotShrinkExpandedInteractionArea() {
        let (controller, panel) = makeController(depth: 33)
        defer { controller.stop() }
        controller.apply(notchTriggerHeight: 2)
        controller.apply(notchTriggerHeight: -20)
        XCTAssertTrue(controller.model.isExpanded)
        XCTAssertFalse(panel.ignoresMouseEvents)
    }
}
