/**
 @name: 显示栏定位测试
 @Descripttion: 验证边缘吸附、位置恢复与编辑提交取消行为。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-08 14:12:37
 @LastEditTime: 2026-09-08 14:12:37
 @FilePath: Tests/NotchPositionTests.swift
 */
import AppKit
import XCTest
@testable import Codenotch

private struct PositionScreen: ScreenDescribing {
    var frameValue = CGRect(x: -1600, y: 100, width: 1600, height: 1000)
    var visibleFrameValue = CGRect(x: -1600, y: 160, width: 1600, height: 910)
    var hardwareNotch: HardwareNotch?
}

final class NotchPositionTests: XCTestCase {
    func testSnapsToAllEdgesOnANegativeOriginDisplay() {
        let screen = PositionScreen()
        let points: [(NotchEdge, CGPoint)] = [
            (.left, CGPoint(x: -1599, y: 800)), (.right, CGPoint(x: -1, y: 400)),
            (.top, CGPoint(x: -1000, y: 1069)), (.bottom, CGPoint(x: -400, y: 161))
        ]
        for (edge, point) in points {
            let position = NotchPosition.snapped(to: point, on: screen, displayID: "external",
                                                 previous: NotchPosition(edge: .right, displayID: "main"))
            XCTAssertEqual(position.edge, edge)
            XCTAssertEqual(position.displayID, "external")
            XCTAssertNotEqual(position.fraction, 0.5)
        }
    }

    func testCornerHysteresisKeepsEdgeUntilDifferenceExceedsTwelvePoints() {
        let screen = PositionScreen()
        let old = NotchPosition(edge: .left, displayID: "external")
        XCTAssertEqual(NotchPosition.snapped(to: CGPoint(x: -1590, y: 1069), on: screen,
            displayID: "external", previous: old).edge, .left)
        XCTAssertEqual(NotchPosition.snapped(to: CGPoint(x: -1580, y: 1069), on: screen,
            displayID: "external", previous: old).edge, .top)
    }

    func testHardwareCenterHasSeparateEnterAndLeaveThresholds() {
        let screen = PositionScreen(hardwareNotch: HardwareNotch(width: 180, height: 30))
        let old = NotchPosition(edge: .top, fraction: 0.2, displayID: "external")
        let joined = old.movingAlong(to: CGPoint(x: -780, y: 1099), on: screen, previous: old)
        XCTAssertTrue(joined.joinsHardware)
        XCTAssertTrue(joined.movingAlong(to: CGPoint(x: -765, y: 1099), on: screen, previous: joined).joinsHardware)
        XCTAssertFalse(joined.movingAlong(to: CGPoint(x: -763, y: 1099), on: screen, previous: joined).joinsHardware)
        XCTAssertFalse(old.movingAlong(to: CGPoint(x: -775, y: 1099), on: screen, previous: old).joinsHardware)
    }

    func testVisibleBarCanReachCornersWithoutMovingTooltipSpaceOffscreen() {
        let screen = PositionScreen()
        for edge in NotchEdge.allCases {
            for fraction in [0.0, 1.0] {
                let position = NotchPosition(edge: edge, fraction: fraction)
                let size = edge.isVertical ? CGSize(width: 340, height: 600) : CGSize(width: 600, height: 340)
                let layout = position.layout(on: screen, panelSize: size, shapeLength: 200, endClearance: 30)
                XCTAssertTrue(screen.visibleFrameValue.contains(layout.frame))
                let length = edge.isVertical ? layout.frame.height : layout.frame.width
                XCTAssertGreaterThanOrEqual(layout.leading, 0)
                XCTAssertLessThanOrEqual(layout.leading + 230, length)
                if fraction == 0 { XCTAssertEqual(layout.leading, 0, accuracy: 0.5) }
                else { XCTAssertEqual(layout.leading + 230, length, accuracy: 0.5) }
            }
        }
    }

    func testHardwareJoinAndFreeTopPlacementUseDifferentHeights() {
        let screen = PositionScreen(hardwareNotch: HardwareNotch(width: 180, height: 30))
        let size = CGSize(width: 600, height: 340)
        let joined = NotchPosition(edge: .top).layout(on: screen, panelSize: size, shapeLength: 200, endClearance: 30)
        XCTAssertEqual(joined.frame.maxY, screen.frameValue.maxY)
        XCTAssertEqual(joined.frame.minX + joined.leading + 100, screen.frameValue.midX)
        let free = NotchPosition(edge: .top, fraction: 0.2).layout(on: screen, panelSize: size, shapeLength: 200, endClearance: 30)
        XCTAssertEqual(free.frame.maxY, screen.visibleFrameValue.maxY)
    }

    func testFractionSurvivesResolutionAndDockChanges() {
        let position = NotchPosition(edge: .right, fraction: 0.25)
        for height: CGFloat in [1000, 1400] {
            let screen = PositionScreen(frameValue: CGRect(x: 0, y: 0, width: 1800, height: height),
                                        visibleFrameValue: CGRect(x: 0, y: 60, width: 1800, height: height - 90))
            let layout = position.layout(on: screen, panelSize: CGSize(width: 340, height: 600),
                                         shapeLength: 200, endClearance: 30)
            let center = layout.frame.maxY - layout.leading - 100
            XCTAssertEqual((screen.visibleFrameValue.maxY - center) / screen.visibleFrameValue.height, 0.25, accuracy: 0.001)
            XCTAssertEqual(layout.frame.maxX, screen.visibleFrameValue.maxX)
        }
    }
}

@MainActor
final class NotchPositionEditingTests: XCTestCase {
    private func preferences() -> Preferences {
        let name = "NotchPositionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return Preferences(defaults: defaults, domainName: name)
    }

    func testLegacyPreferencesRemainCenteredAndPositionRoundTrips() throws {
        let preferences = preferences()
        XCTAssertNil(preferences.notchPosition)
        XCTAssertEqual(preferences.notchEdge, .right)
        let position = NotchPosition(edge: .bottom, fraction: 0.73, displayID: "detached-display")
        preferences.notchPosition = position
        XCTAssertEqual(preferences.notchPosition, position)
        XCTAssertEqual(preferences.notchEdge, .bottom)
        XCTAssertEqual(try JSONDecoder().decode(NotchPosition.self, from: JSONEncoder().encode(position)), position)
    }

    private func controller() throws -> NotchWindowController {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("Needs a window server") }
        let controller = NotchWindowController()
        controller.restore(position: NotchPosition(edge: .left, fraction: 0.3, displayID: "detached-display"))
        controller.relocate()
        addTeardownBlock { MainActor.assumeIsolated { controller.stop() } }
        return controller
    }

    func testCancelRestoresPositionAndExpansionWithoutWriting() throws {
        let controller = try controller()
        let original = controller.savedPosition
        var writes = 0
        controller.onPositionCommitted = { _ in writes += 1 }
        controller.beginPositionEditing()
        let point = try XCTUnwrap(NSScreen.screens.first).visibleFrame.origin
        controller.updatePositionDrag(to: point, from: CGPoint(x: point.x + 100, y: point.y + 100))
        let panel = try XCTUnwrap(controller.panelContentViewForTesting?.window as? NotchPanel)
        XCTAssertTrue(panel.canBecomeKey)
        let escape = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber,
            context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false, keyCode: 53))
        panel.sendEvent(escape)
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertEqual(controller.savedPosition, original)
        XCTAssertEqual(controller.model.edge, .left)
        XCTAssertFalse(controller.model.isExpanded)
        XCTAssertFalse(controller.model.isEditingPosition)
        XCTAssertEqual(writes, 0)
    }

    func testSubThresholdMovementDoesNotSave() throws {
        let controller = try controller()
        let original = controller.savedPosition
        controller.beginPositionEditing()
        controller.updatePositionDrag(to: CGPoint(x: 2, y: 2), from: .zero)
        controller.finishPositionEditing(commit: true)
        XCTAssertEqual(controller.savedPosition, original)
    }

    func testDragSavesOnceAndRefreshDoesNotResetPreview() throws {
        let controller = try controller()
        var writes: [NotchPosition] = []
        controller.onPositionCommitted = { writes.append($0) }
        controller.beginPositionEditing()
        let frame = try XCTUnwrap(NSScreen.screens.first).visibleFrame
        let point = CGPoint(x: frame.midX, y: frame.minY)
        controller.updatePositionDrag(to: point, from: CGPoint(x: point.x, y: point.y + 100))
        controller.relocate(cellCount: 2)
        XCTAssertTrue(controller.model.isEditingPosition)
        XCTAssertTrue(writes.isEmpty)
        controller.finishPositionEditing(commit: true)
        controller.finishPositionEditing(commit: true)
        XCTAssertEqual(writes.count, 1)
        XCTAssertEqual(controller.savedPosition?.edge, .bottom)
        XCTAssertNotEqual(controller.savedPosition?.displayID, "detached-display")
    }

    func testMissingDisplayFallbackDoesNotOverwritePreference() throws {
        let controller = try controller()
        controller.relocate()
        XCTAssertEqual(controller.savedPosition?.displayID, "detached-display")
    }

    func testTooltipMovesInsideBoundsAndTailTracksItsCell() {
        let model = NotchViewModel()
        model.positionedLeading = 0
        model.tooltipAlongBounds = 0...800
        let center = model.tooltipAlong(index: 0, length: 400)
        XCTAssertGreaterThanOrEqual(center - 200, 0)
        XCTAssertLessThanOrEqual(center + 200, 800)
        model.positionedLeading = 650
        XCTAssertEqual(model.tooltipAlong(index: 0, length: 400), 600)
    }
}
