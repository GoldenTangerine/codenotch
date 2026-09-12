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
import SwiftUI
import XCTest
@testable import Codenotch

private struct PositionScreen: ScreenDescribing {
    var frameValue = CGRect(x: -1600, y: 100, width: 1600, height: 1000)
    var visibleFrameValue = CGRect(x: -1600, y: 160, width: 1600, height: 910)
    var hardwareNotch: HardwareNotch?
}

final class NotchPositionTests: XCTestCase {
    func testGuideSilhouetteMatchesScaledCapsuleOnEveryEdge() {
        for edge in NotchEdge.allCases {
            for scale: CGFloat in [0.75, 1, 1.3, 1.5] {
                for hardware in [nil, HardwareNotch(width: 180, height: 30)] {
                    let shape = SideNotchShape(edge: edge, joining: edge == .top ? hardware : nil)
                    let size = NotchPlacement.panelSize(edge: edge, length: 400, depth: 90)
                    let frame = CGRect(x: 17, y: 29, width: size.width * scale, height: size.height * scale)
                    let expected = shape.path(in: CGRect(origin: .zero, size: size))
                        .applying(CGAffineTransform(scaleX: scale, y: scale))
                        .applying(CGAffineTransform(translationX: frame.minX + edge.outward.x * 2,
                                                   y: frame.minY + edge.outward.y * 2))
                    let guide = shape.renderedPath(in: frame, scale: scale)
                    XCTAssertEqual(guide.boundingRect.minX, expected.boundingRect.minX, accuracy: 0.000001)
                    XCTAssertEqual(guide.boundingRect.minY, expected.boundingRect.minY, accuracy: 0.000001)
                    XCTAssertEqual(guide.boundingRect.width, expected.boundingRect.width, accuracy: 0.000001)
                    XCTAssertEqual(guide.boundingRect.height, expected.boundingRect.height, accuracy: 0.000001)
                    for x in stride(from: frame.minX - 3, through: frame.maxX + 3, by: 3) {
                        for y in stride(from: frame.minY - 3, through: frame.maxY + 3, by: 3) {
                            let point = CGPoint(x: x + 0.37, y: y + 0.61)
                            XCTAssertEqual(guide.contains(point), expected.contains(point))
                        }
                    }
                }
            }
        }
    }

    func testSidePlacementAvoidsSideDock() {
        let screen = PositionScreen(visibleFrameValue: CGRect(x: -1500, y: 160, width: 1400, height: 910))
        for edge in [NotchEdge.left, .right] {
            let layout = NotchPosition(edge: edge).layout(on: screen,
                panelSize: CGSize(width: 340, height: 600), shapeLength: 200, endClearance: 30)
            XCTAssertTrue(screen.visibleFrameValue.contains(layout.frame))
            XCTAssertEqual(edge == .left ? layout.frame.minX : layout.frame.maxX,
                           edge == .left ? screen.visibleFrameValue.minX : screen.visibleFrameValue.maxX)
        }
    }

    func testEveryEdgeSnapsToVisibleCenterWithHysteresis() {
        let screen = PositionScreen()
        for edge in NotchEdge.allCases {
            let old = NotchPosition(edge: edge, fraction: 0.2, displayID: "external")
            func point(_ offset: CGFloat) -> CGPoint {
                CGPoint(x: screen.visibleFrameValue.midX + (edge.isVertical ? 0 : offset),
                        y: screen.visibleFrameValue.midY + (edge.isVertical ? offset : 0))
            }
            let joined = old.movingAlong(to: point(24), on: screen, previous: old)
            XCTAssertEqual(joined.fraction, 0.5)
            XCTAssertEqual(joined.movingAlong(to: point(36), on: screen, previous: joined).fraction, 0.5)
            XCTAssertNotEqual(joined.movingAlong(to: point(37), on: screen, previous: joined).fraction, 0.5)
            XCTAssertNotEqual(old.movingAlong(to: point(25), on: screen, previous: old).fraction, 0.5)
            let otherScreen = NotchPosition(edge: edge, displayID: "other")
            XCTAssertNotEqual(old.movingAlong(to: point(30), on: screen, previous: otherScreen).fraction, 0.5)
            let otherEdge = NotchPosition(edge: edge == .left ? .right : .left, displayID: "external")
            XCTAssertNotEqual(old.movingAlong(to: point(30), on: screen, previous: otherEdge).fraction, 0.5)
        }
    }

    func testBothHandlesStayInsideSavedAndLegacyLayoutsAtEveryEdge() {
        let screen = PositionScreen()
        for edge in NotchEdge.allCases {
            let size = edge.isVertical ? CGSize(width: 340, height: 600) : CGSize(width: 600, height: 340)
            for fraction in [0.0, 1.0] {
                let layout = NotchPosition(edge: edge, fraction: fraction).layout(
                    on: screen, panelSize: size, shapeLength: 200,
                    endClearance: 45, startClearance: 45)
                let length = edge.isVertical ? layout.frame.height : layout.frame.width
                XCTAssertGreaterThanOrEqual(layout.leading - 45, 0)
                XCTAssertLessThanOrEqual(layout.leading + 245, length)
                let frame = NotchGeometry.panelFrame(for: screen, panelSize: size, edge: edge,
                    alongOffset: fraction == 0 ? -10000 : 10000, slack: 200,
                    trailingExtent: 45, leadingExtent: 45)
                let start = edge.isVertical ? screen.frameValue.maxY - frame.maxY + 200
                    : frame.minX - screen.frameValue.minX + 200
                let available = edge.isVertical ? screen.frameValue.height : screen.frameValue.width
                XCTAssertGreaterThanOrEqual(start - 45, 0)
                XCTAssertLessThanOrEqual(start + 245, available)
            }
        }
    }

    func testFullTooltipPanelRetainsTheLeadingHandleAboveTheUsableArea() {
        let layout = TooltipSizing.sidePanelLayout(
            usable: CGRect(x: 0, y: 60, width: 1600, height: 900),
            standardFrame: CGRect(x: 1260, y: 555, width: 340, height: 600),
            standardSlack: 200, size: CGSize(width: 340, height: 1100),
            shapeLength: 200, leadingExtent: 45, trailingExtent: 0)
        XCTAssertGreaterThanOrEqual(layout.leading, 45)
        XCTAssertEqual(layout.frame.maxY - layout.leading, 955)
    }

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
    func testGuideCacheTracksLayoutChanges() {
        let model = NotchViewModel()
        var screen = PositionScreen()
        let initial = model.centeredGuideFrames(on: screen, cellCount: 3)
        XCTAssertEqual(initial, model.centeredGuideFrames(on: screen, cellCount: 3))
        model.sizeScale = 1.5
        let resized = model.centeredGuideFrames(on: screen, cellCount: 3)
        XCTAssertNotEqual(initial, resized)
        XCTAssertNotEqual(resized, model.centeredGuideFrames(on: screen, cellCount: 1))
        screen.visibleFrameValue.origin.x += 80
        screen.visibleFrameValue.size.width -= 80
        XCTAssertNotEqual(resized[.left], model.centeredGuideFrames(on: screen, cellCount: 3)[.left])
        screen.hardwareNotch = HardwareNotch(width: 180, height: 30)
        XCTAssertNotEqual(resized[.top], model.centeredGuideFrames(on: screen, cellCount: 3)[.top])
    }

    func testEditingCancellationNotificationsRemoveGuidesWithoutSaving() throws {
        let controller = try controller()
        controller.show()
        let original = controller.savedPosition
        var writes = 0
        controller.onPositionCommitted = { _ in writes += 1 }
        for name in [NSApplication.didResignActiveNotification,
                     NSWindow.didResignKeyNotification, NSApplication.didChangeScreenParametersNotification] {
            controller.beginPositionEditing()
            let guide = try XCTUnwrap(controller.positionGuideWindowForTesting)
            XCTAssertTrue(guide.ignoresMouseEvents)
            let panel = try XCTUnwrap(controller.panelContentViewForTesting?.window)
            let point = try XCTUnwrap(NSScreen.screens.first).visibleFrame.origin
            controller.updatePositionDrag(to: point, from: CGPoint(x: point.x + 80, y: point.y + 80))
            NotificationCenter.default.post(name: name, object: name == NSWindow.didResignKeyNotification ? panel : nil)
            XCTAssertFalse(controller.model.isEditingPosition)
            XCTAssertNil(controller.positionGuideWindowForTesting)
            XCTAssertFalse(guide.isVisible)
            XCTAssertEqual(controller.savedPosition, original)
        }
        controller.beginPositionEditing()
        controller.stop()
        XCTAssertNil(controller.positionGuideWindowForTesting)
        XCTAssertEqual(writes, 0)
    }

    func testOnlyCenteredLandingHighlightsAndCommitRemovesGuides() throws {
        let controller = try controller()
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let usable = screen.visibleFrame
        controller.beginPositionEditing()
        let guide = try XCTUnwrap(controller.positionGuideWindowForTesting)
        let center = CGPoint(x: usable.midX, y: usable.minY)
        controller.updatePositionDrag(to: center, from: CGPoint(x: center.x, y: center.y + 80))
        XCTAssertEqual(controller.positionGuideTargetForTesting, .bottom)
        XCTAssertTrue(controller.positionGuideWindowForTesting === guide)
        controller.updatePositionDrag(to: CGPoint(x: center.x + 37, y: center.y), from: .zero)
        XCTAssertNil(controller.positionGuideTargetForTesting)
        controller.finishPositionEditing(commit: true)
        XCTAssertNil(controller.positionGuideWindowForTesting)
        XCTAssertNotEqual(controller.savedPosition?.fraction, 0.5)
    }

    func testCrossDisplayPreviewMovesGuidesAndCancelRestoresOriginal() throws {
        guard NSScreen.screens.count >= 2 else { throw XCTSkip("Needs two displays") }
        let first = NSScreen.screens[0]
        let second = NSScreen.screens[1]
        let controller = NotchWindowController()
        let original = NotchPosition(edge: .left, fraction: 0.3, displayID: first.notchDisplayID)
        controller.restore(position: original)
        controller.relocate()
        defer { controller.stop() }
        controller.beginPositionEditing()
        let oldGuide = try XCTUnwrap(controller.positionGuideWindowForTesting)
        let point = CGPoint(x: second.visibleFrame.midX, y: second.visibleFrame.minY + 2)
        controller.updatePositionDrag(to: point, from: CGPoint(x: point.x, y: point.y + 80))
        XCTAssertEqual(controller.currentScreen(), second)
        XCTAssertEqual(controller.positionGuideWindowForTesting?.frame, second.frame)
        XCTAssertFalse(controller.positionGuideWindowForTesting === oldGuide)
        XCTAssertFalse(oldGuide.isVisible)
        controller.finishPositionEditing(commit: false)
        XCTAssertEqual(controller.savedPosition, original)
        XCTAssertEqual(controller.currentScreen(), first)
        XCTAssertNil(controller.positionGuideWindowForTesting)
        controller.beginPositionEditing()
        controller.updatePositionDrag(to: point, from: CGPoint(x: point.x, y: point.y + 80))
        controller.finishPositionEditing(commit: true)
        XCTAssertEqual(controller.savedPosition?.displayID, second.notchDisplayID)
        XCTAssertEqual(controller.savedPosition?.edge, .bottom)
    }

    func testCenteredGuidesMatchActualLandingGeometry() throws {
        for hardware in [nil, HardwareNotch(width: 180, height: 30)] {
            let screen = PositionScreen(hardwareNotch: hardware)
            let model = NotchViewModel()
            model.sizeScale = 1.3
            model.showsMoveHandle = true
            model.showsSettingsHandle = true
            let guides = model.centeredGuideFrames(on: screen, cellCount: 3)
            for edge in NotchEdge.allCases {
                model.edge = edge
                model.adopt(screen: screen)
                let length = model.shapeLength(cellCount: 3) * model.sizeScale
                let layout = NotchPosition(edge: edge).layout(on: screen,
                    panelSize: model.panelSize(cellCount: 3), shapeLength: length,
                    endClearance: model.trailingExtent * model.sizeScale,
                    startClearance: model.leadingExtent * model.sizeScale)
                let guide = try XCTUnwrap(guides[edge])
                let actual = NotchPlacement(edge: edge, panelSize: layout.frame.size).rect(
                    along: layout.leading, across: 0, length: length, depth: model.notchDrawnDepth)
                XCTAssertEqual(guide.minX, layout.frame.minX + actual.minX - screen.frameValue.minX, accuracy: 1)
                XCTAssertEqual(guide.minY, screen.frameValue.maxY - layout.frame.maxY + actual.minY, accuracy: 1)
                XCTAssertEqual(guide.size, actual.size)
            }
        }
    }

    func testHandleClickAndDirectDragSharePositionEditing() throws {
        _ = NSApplication.shared
        guard let screen = NSScreen.screens.first else { throw XCTSkip("Needs a window server") }
        var mouse = CGPoint.zero
        let controller = NotchWindowController(mouseLocation: { mouse })
        controller.assignedScreen = screen
        controller.restore(position: NotchPosition(edge: .left, fraction: 0.3, displayID: screen.notchDisplayID))
        controller.model.isExpanded = true
        controller.model.showsMoveHandle = true
        controller.relocate()
        defer { controller.stop() }
        var writes: [NotchPosition] = []
        controller.onPositionCommitted = { writes.append($0) }
        let panel = try XCTUnwrap(controller.panelContentViewForTesting?.window as? NotchPanel)
        func pressHandle() throws {
            let model = controller.model
            let local = NotchPlacement(edge: model.edge, panelSize: panel.frame.size).point(
                along: model.slack + model.moveAlong * model.sizeScale,
                across: model.orbInset * model.sizeScale)
            mouse = CGPoint(x: panel.frame.minX + local.x, y: panel.frame.maxY - local.y)
            try send(.leftMouseDown)
            XCTAssertTrue(controller.model.isEditingPosition)
        }
        func send(_ type: NSEvent.EventType) throws {
            panel.sendEvent(try XCTUnwrap(NSEvent.mouseEvent(with: type,
                location: CGPoint(x: mouse.x - panel.frame.minX, y: mouse.y - panel.frame.minY),
                modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1)))
        }
        try pressHandle()
        try send(.leftMouseUp)
        XCTAssertTrue(controller.model.isEditingPosition)
        XCTAssertTrue(writes.isEmpty)
        controller.finishPositionEditing(commit: false)
        try pressHandle()
        let before = panel.frame.maxY - controller.model.slack
        mouse.y -= 80
        try send(.leftMouseDragged)
        XCTAssertEqual(panel.frame.maxY - controller.model.slack, before - 80, accuracy: 1)
        try send(.leftMouseUp)
        XCTAssertFalse(controller.model.isEditingPosition)
        XCTAssertFalse(controller.model.isMoving)
        XCTAssertEqual(writes.count, 1)
        XCTAssertNotEqual(writes.first?.fraction, 0.5)
    }

    func testContextMenuActuallyEntersTheSharedEditor() async throws {
        let controller = try controller()
        let panel = try XCTUnwrap(controller.panelContentViewForTesting?.window as? NotchPanel)
        let menu = try XCTUnwrap(panel.contextMenuProvider?())
        let index = try XCTUnwrap(menu.items.firstIndex { $0.action == #selector(MenuActions.editPosition(_:)) })
        menu.performActionForItem(at: index)
        let dispatched = expectation(description: "Menu action dispatched")
        DispatchQueue.main.async { dispatched.fulfill() }
        await fulfillment(of: [dispatched], timeout: 1)
        XCTAssertTrue(controller.model.isEditingPosition)
        XCTAssertTrue(controller.model.isMoving)
        controller.finishPositionEditing(commit: false)
        XCTAssertFalse(controller.model.isMoving)
    }

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

    func testLegacyDraggingReachesTrailingEdgeWithoutHiddenControlClearance() throws {
        let controller = try controller()
        let screen = try XCTUnwrap(NSScreen.screens.first)
        controller.assignedScreen = screen
        controller.restore(position: nil)
        for edge in NotchEdge.allCases {
            controller.model.edge = edge
            controller.model.alongOffset = 100_000
            controller.relocate()
            let frame = try XCTUnwrap(controller.panelFrameForTesting)
            let end = controller.model.slack + controller.model.shapeLength * controller.model.sizeScale
            if edge.isVertical {
                XCTAssertEqual(frame.maxY - end, screen.frame.minY, accuracy: 2)
            } else {
                XCTAssertEqual(frame.minX + end, screen.frame.maxX, accuracy: 2)
            }
        }
    }

    func testContextMenuOpensSettingsAndRetainsPositionEditing() async throws {
        let controller = try controller()
        let opened = expectation(description: "Settings opened from context menu")
        controller.onOpenSettings = { opened.fulfill() }
        let panel = try XCTUnwrap(controller.panelContentViewForTesting?.window as? NotchPanel)
        let menu = try XCTUnwrap(panel.contextMenuProvider?())
        XCTAssertNotNil(menu.items.first { $0.action == #selector(MenuActions.editPosition(_:)) })
        let index = try XCTUnwrap(menu.items.firstIndex { $0.action == #selector(MenuActions.openSettings(_:)) })
        XCTAssertTrue(menu.items[index].isEnabled)
        menu.performActionForItem(at: index)
        await fulfillment(of: [opened], timeout: 1)
    }

    func testFleetKeepsSavedPositionAndActivityMappingAcrossScopes() throws {
        let fleet = NotchFleet(scope: .mainDisplay, edge: .right)
        let position = NotchPosition(edge: .bottom, fraction: 0.25, displayID: "detached-display")
        fleet.restore(position: position)
        fleet.setActivitySourceIDs(["work": "claude"])
        fleet.show()
        defer { fleet.stop() }
        for scope in [NotchScreenScope.mainDisplay, .allDisplays, .mainDisplay] {
            fleet.apply(scope: scope)
            for controller in fleet.controllersForTesting {
                XCTAssertEqual(controller.savedPosition, position)
                XCTAssertEqual(controller.model.activitySourceIDs, ["work": "claude"])
                XCTAssertEqual(controller.model.edge, .bottom)
            }
        }
    }

    func testChangingFleetDisplayPreservesAlongEdgePosition() throws {
        let fleet = NotchFleet(scope: .mainDisplay, edge: .right)
        fleet.restore(position: NotchPosition(edge: .bottom, fraction: 0.25, displayID: "old-display"))
        var committed: NotchPosition?
        fleet.onPositionCommitted = { committed = $0 }
        fleet.apply(displayPreference: .display("new-display"))
        XCTAssertEqual(committed?.fraction, 0.25)
        XCTAssertEqual(committed?.displayID, "new-display")
        fleet.apply(displayPreference: .followActiveWindow)
        XCTAssertEqual(committed?.fraction, 0.25)
        XCTAssertNil(committed?.displayID)
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
