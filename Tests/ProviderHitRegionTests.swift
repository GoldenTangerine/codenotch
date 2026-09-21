/**
 @name: 供应商命中区域测试
 @Descripttion: 验证供应商悬停边界、气泡保持与手形状态。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-21 10:27:39
 @LastEditTime: 2026-09-21 10:27:39
 @FilePath: Tests/ProviderHitRegionTests.swift
 */
import AppKit
import SwiftUI
import XCTest
@testable import Codenotch

@MainActor
final class ProviderHitRegionTests: XCTestCase {
    private func populate(_ model: NotchViewModel, count: Int = 3, weekly: Bool = false) {
        model.updateSnapshots((0..<count).map {
            ProviderSnapshot(id: "provider-\($0)", displayName: "Provider \($0)",
                glyph: .openai, fidelity: .official, status: .ok,
                windows: [LimitWindow(id: "session", label: "Session", usedFraction: 0.4, duration: 18_000)]
                    + (weekly ? [LimitWindow(id: "weekly", label: "Week", usedFraction: 0.5, duration: 604_800)] : []))
        })
        model.isExpanded = true
        model.showsSettingsHandle = false
        model.showsMoveHandle = false
    }

    func testRingAndLabelHitButMarginsAndGapsDoNotOnEveryEdge() {
        let controller = NotchWindowController()
        let model = controller.model
        populate(model)
        for edge in NotchEdge.allCases {
            for scale: CGFloat in [0.75, 1, 1.5] {
                for expanded in [false, true] {
                    for adjustment: CGFloat in [-3, 20] {
                        model.edge = edge
                        model.sizeScale = scale
                        model.independentInnerRing = expanded
                        model.ringEdgeAdjustment = adjustment
                        model.hardwareNotch = HardwareNotch(width: 200, height: 32)
                        let place = NotchPlacement(edge: edge, panelSize: model.panelSize)
                        let diameter = model.cellRingDiameter
                        let extent = diameter + NotchLayout.ringLabelGap + NotchLayout.percentLineHeight
                        let centre = place.point(
                            along: model.slack + (model.ringCenter(index: 0)
                                + (edge.isVertical ? (extent - diameter) / 2 : 0)) * scale,
                            across: (model.contentInset + model.baseBodyDepth / 2) * scale + adjustment)
                        let ring = CGPoint(x: centre.x, y: centre.y - (extent - diameter) * scale / 2)
                        let label = CGPoint(x: centre.x, y: centre.y + (extent - NotchLayout.percentLineHeight) * scale / 2)
                        XCTAssertEqual(controller.cellIndex(at: ring), 0)
                        XCTAssertEqual(controller.cellIndex(at: label), 0)
                        let margin = place.point(along: place.along(of: centre), across: 1)
                        XCTAssertNil(controller.cellIndex(at: margin))
                        let gap = place.point(
                            along: model.slack + (model.ringCenter(index: 0) + diameter / 2
                                + (edge.isVertical ? extent - diameter : 0)
                                + model.cellSpacing / 2) * scale,
                            across: place.across(of: centre))
                        XCTAssertNil(controller.cellIndex(at: gap))
                    }
                }
            }
        }
    }

    func testRenderedCellUsesSharedLayoutSize() {
        let model = NotchViewModel()
        populate(model)
        for expanded in [false, true] {
            model.independentInnerRing = expanded
            let view = NSHostingView(rootView: ProviderCell(snapshot: model.snapshots[0],
                independentInnerRing: expanded, cellRingDiameter: model.cellRingDiameter))
            let actual = view.fittingSize
            let expected = NotchLayout.cellSize(ringDiameter: model.cellRingDiameter, isLocal: false)
            XCTAssertEqual(actual.width, expected.width, accuracy: 0.01)
            XCTAssertEqual(actual.height, expected.height, accuracy: 0.01)
        }
    }

    func testScrollingReturnsVisibleProviderIndex() {
        let controller = NotchWindowController()
        let model = controller.model
        populate(model, count: 30)
        model.screenUsableSize = CGSize(width: 1000, height: 800)
        for edge in NotchEdge.allCases {
            model.edge = edge
            model.scrollStart = 4
            XCTAssertEqual(model.visibleStart, 4)
            let rect = controller.cellRect(index: 4)
            XCTAssertEqual(controller.cellIndex(at: CGPoint(x: rect.midX, y: rect.midY)), 4)
        }
    }

    func testDenseOutsideRingsPreferTheProviderDrawnOnTop() async {
        let panel = NotchPanel(contentRect: CGRect(x: 0, y: 0, width: 1000, height: 800))
        var local = CGPoint.zero
        let controller = NotchWindowController(panel: panel, mouseLocation: {
            CGPoint(x: panel.frame.minX + local.x, y: panel.frame.maxY - local.y)
        })
        defer { controller.stop() }
        let model = controller.model
        populate(model, count: 30, weekly: true)
        model.weeklyRing = .outside
        model.screenSize = CGSize(width: 1000, height: 800)
        model.screenUsableSize = model.screenSize
        for edge in [NotchEdge.left, .right] {
            for scale: CGFloat in [0.75, 1, 1.5] {
                model.edge = edge
                model.sizeScale = scale
                model.scrollStart = 4
                XCTAssertEqual(model.cellSpacing, 0)
                let index = model.visibleStart + 1
                XCTAssertTrue(model.visibleIndices.contains(index))
                XCTAssertNotNil(model.snapshots[index].secondaryWindow)
                let place = NotchPlacement(edge: edge, panelSize: panel.frame.size)
                let ring = place.point(
                    along: model.slack + model.ringCenter(index: index) * scale,
                    across: model.baseBodyDepth * scale / 2 - SideNotchShape.bezelBleed)
                // 直接取可见外周环顶部线条上的点，避免由被测矩形反推测试坐标。
                let point = CGPoint(x: ring.x, y: ring.y - NotchLayout.weeklyOutsideRadius * scale)
                XCTAssertTrue(controller.cellRect(index: index - 1).contains(point))
                XCTAssertEqual(controller.cellIndex(at: point), index)
                XCTAssertEqual(controller.cellIndex(at: ring), index)
                local = point
                controller.cursorMoved()
                XCTAssertEqual(model.hoveredIndex, index)
                let refreshed = expectation(description: "Overlapping outer ring refreshes its own provider")
                controller.onRefreshProvider = { id in
                    XCTAssertEqual(id, "provider-\(index)")
                    refreshed.fulfill()
                }
                controller.handleClick(at: CGPoint(x: point.x, y: panel.frame.height - point.y))
                await fulfillment(of: [refreshed], timeout: 1)
            }
        }
    }

    func testTopBlankDoesNotOpenTooltipAndLeavingProviderRestoresCursor() throws {
        let panel = NotchPanel(contentRect: CGRect(x: 0, y: 0, width: 1200, height: 900))
        var local = CGPoint.zero
        var pending: [DispatchWorkItem] = []
        let controller = NotchWindowController(panel: panel, mouseLocation: {
            CGPoint(x: panel.frame.minX + local.x, y: panel.frame.maxY - local.y)
        }, scheduleInteractionWork: { _, work in pending.append(work) })
        NSCursor.crosshair.push()
        defer {
            controller.stop()
            NSCursor.pop()
        }
        let model = controller.model
        populate(model)
        model.edge = .top
        model.hardwareNotch = HardwareNotch(width: 200, height: 32)
        let rect = controller.cellRect(index: 0)
        let blank = CGPoint(x: rect.midX, y: 10)
        local = blank
        controller.cursorMoved()
        XCTAssertNil(model.hoveredIndex)
        XCTAssertFalse(controller.isPointing)

        local = CGPoint(x: rect.midX, y: rect.midY)
        controller.cursorMoved()
        XCTAssertEqual(model.hoveredIndex, 0)
        XCTAssertTrue(controller.isPointing)
        XCTAssertEqual(NSCursor.current, NSCursor.pointingHand)

        for index in [1, 2, 0] {
            local = CGPoint(x: model.slack + model.ringCenter(index: index) * model.sizeScale,
                            y: rect.midY)
            controller.cursorMoved()
            XCTAssertEqual(model.hoveredIndex, index)
            XCTAssertEqual(NSCursor.current, NSCursor.pointingHand)
        }

        let card = try XCTUnwrap(controller.tooltipRect(index: 0))
        local = CGPoint(x: card.midX, y: card.midY)
        controller.cursorMoved()
        XCTAssertEqual(model.hoveredIndex, 0)
        XCTAssertFalse(controller.isPointing)
        XCTAssertEqual(NSCursor.current, NSCursor.crosshair)

        local = blank
        controller.cursorMoved()
        XCTAssertFalse(controller.isPointing)
        XCTAssertEqual(NSCursor.current, NSCursor.crosshair)
        for work in pending where !work.isCancelled { work.perform() }
        XCTAssertNil(model.hoveredIndex)
    }

    func testOnlyProviderClickRefreshes() async {
        let panel = NotchPanel(contentRect: CGRect(x: 0, y: 0, width: 1200, height: 900))
        let controller = NotchWindowController(panel: panel)
        defer { controller.stop() }
        populate(controller.model)
        controller.model.edge = .top
        controller.model.hardwareNotch = HardwareNotch(width: 200, height: 32)
        let rect = controller.cellRect(index: 0)
        let noRefresh = expectation(description: "Blank space must not refresh a provider")
        noRefresh.isInverted = true
        controller.onRefreshProvider = { _ in noRefresh.fulfill() }
        controller.handleClick(at: CGPoint(x: rect.midX, y: panel.frame.height - 10))
        await fulfillment(of: [noRefresh], timeout: 0.1)

        let refreshed = expectation(description: "Clicking the label refreshes its provider")
        controller.onRefreshProvider = { id in
            XCTAssertEqual(id, "provider-0")
            refreshed.fulfill()
        }
        controller.handleClick(at: CGPoint(x: rect.midX, y: panel.frame.height - rect.maxY + 1))
        await fulfillment(of: [refreshed], timeout: 1)
    }
}
