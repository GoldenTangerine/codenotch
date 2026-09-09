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
    private func makeController(depth: CGFloat) -> (NotchWindowController, NotchPanel) {
        let panel = NotchPanel(contentRect: CGRect(x: 0, y: 0, width: 600, height: 600))
        let controller = NotchWindowController(panel: panel, mouseLocation: {
            CGPoint(x: panel.frame.minX + 200, y: panel.frame.maxY - depth)
        })
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
