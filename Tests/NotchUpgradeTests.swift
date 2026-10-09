/**
 @name: 刘海升级兼容回归
 @Descripttion: 验证可选双翼、独立移动入口及沿边过渡保留本地行为。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-10-09 10:32:24
 @LastEditTime: 2026-10-09 10:32:24
 @FilePath: Tests/NotchUpgradeTests.swift
 */
import AppKit
import XCTest
@testable import Codenotch

private struct UpgradeScreen: ScreenDescribing {
    let frameValue = CGRect(x: -1512, y: 0, width: 1512, height: 982)
    let visibleFrameValue = CGRect(x: -1512, y: 40, width: 1512, height: 904)
    let hardwareNotch: HardwareNotch? = HardwareNotch(width: 210, height: 38)
}

@MainActor
final class NotchUpgradeTests: XCTestCase {
    private func prepare(_ model: NotchViewModel, count: Int = 1) {
        model.edge = .top
        model.isExpanded = true
        model.sizeScale = 1.3
        model.topAvoidanceAdjustment = 12
        model.ringEdgeAdjustment = 8
        model.snapshots = (0..<count).map {
            ProviderSnapshot(id: "synthetic-\($0)", displayName: "Test", glyph: .claude,
                             fidelity: .official, status: .ok, windows: [])
        }
        model.adopt(screen: UpgradeScreen())
    }

    func testWingsAreOptInAndRestoreLocalGeometryDuringPreviewsAndEditing() {
        let model = NotchViewModel()
        prepare(model)
        let localDepth = model.notchDepth
        let localInset = model.contentInset
        XCTAssertFalse(model.usesHardwareWings)
        XCTAssertEqual(model.sizeScale, 1.3)
        model.hardwareNotchWings = true
        XCTAssertTrue(model.usesHardwareWings)
        XCTAssertEqual(model.contentInset, 0)
        XCTAssertEqual(model.ringEdgePadding, 0)
        XCTAssertEqual(model.notchDepth * model.sizeScale, 40, accuracy: 0.001)
        for key in [\NotchViewModel.isEditingPosition, \.isPreviewingCollapsedGeometry, \.isPreviewingExpandedGeometry] {
            model[keyPath: key] = true
            XCTAssertFalse(model.usesHardwareWings)
            XCTAssertEqual(model.notchDepth, localDepth)
            XCTAssertEqual(model.contentInset, localInset)
            XCTAssertEqual(model.sizeScale, 1.3)
            model[keyPath: key] = false
            XCTAssertTrue(model.usesHardwareWings)
        }
        model.isExpanded = false
        let resting = model.notchSize
        model.hardwareNotchWings = false
        XCTAssertEqual(model.notchSize, resting, "双翼不得改变折叠机器人和宽高布局")
    }

    func testWingsRequireCenteredHardwareAndTopEdge() {
        let model = NotchViewModel()
        prepare(model)
        model.hardwareNotchWings = true
        model.adopt(screen: UpgradeScreen(), joinsHardware: false)
        XCTAssertFalse(model.usesHardwareWings)
        for edge in [NotchEdge.left, .right, .bottom] {
            model.edge = edge
            model.adopt(screen: UpgradeScreen())
            XCTAssertFalse(model.usesHardwareWings)
        }
    }

    func testWingsHitTheVisibleRingAndTheOppositeReading() {
        let controller = NotchWindowController()
        let model = controller.model
        prepare(model)
        model.hardwareNotchWings = true
        let rect = controller.cellRect(index: 0)
        XCTAssertFalse(rect.isEmpty)
        XCTAssertGreaterThan(rect.minX, model.panelSize.width / 2 + 105)
        XCTAssertEqual(controller.cellIndex(at: CGPoint(x: rect.midX, y: rect.midY)), 0)
        let reading = model.wings.first { !$0.carriesCells }!
        XCTAssertEqual(controller.cellIndex(at: CGPoint(x: reading.lead + reading.length / 2,
                                                        y: reading.depth * model.sizeScale / 2)), 0)
        XCTAssertNil(controller.cellIndex(at: CGPoint(x: model.panelSize.width / 2, y: 10)))
    }

    func testManyProvidersStayInsideTheWingAndRemainScrollable() {
        let model = NotchViewModel()
        prepare(model, count: 50)
        model.hardwareNotchWings = true
        model.showsMoveHandle = true
        model.showsSettingsHandle = true
        XCTAssertLessThan(model.visibleIndices.count, model.snapshots.count)
        XCTAssertGreaterThanOrEqual(model.wings[0].lead, 0)
        XCTAssertLessThanOrEqual(model.cellWing.lead + (model.moveAlong + model.orbHotZone / 2) * model.sizeScale,
                                 model.panelSize.width)
        let first = model.visibleIndices
        model.scroll(by: 1)
        XCTAssertEqual(model.visibleIndices.lowerBound, first.lowerBound + 1)
    }

    func testMoveAndSettingsRemainIndependentAndDoNotStealTheGearClick() {
        let model = NotchViewModel()
        prepare(model)
        model.showsMoveHandle = true
        XCTAssertTrue(model.gripRevealed)
        XCTAssertTrue(model.isOnMoveHandle(along: model.moveAlong, across: model.orbInset))
        XCTAssertFalse(model.isOnOrbHandle(along: model.orbAlong, across: model.orbInset))
        model.showsSettingsHandle = true
        XCTAssertFalse(model.gripRevealed)
        model.isHoveringSettings = true
        XCTAssertTrue(model.gripRevealed)
        XCTAssertTrue(model.isOnMoveHandle(along: model.moveAlong, across: model.orbInset))
        XCTAssertFalse(model.isOnMoveHandle(along: model.orbAlong + NotchLayout.orbDiameter / 2 - 1,
                                          across: model.orbInset))
        model.isHoveringMove = true
        model.isHoveringSettings = false
        XCTAssertTrue(model.gripRevealed)
        model.showsMoveHandle = false
        XCTAssertFalse(model.gripRevealed)
        XCTAssertTrue(model.moveHandlePoints.isEmpty)
        XCTAssertTrue(model.isOnOrbHandle(along: model.orbAlong, across: model.orbInset))
    }

    func testBorderPassageKeepsLengthThroughEveryCornerAndWrapsBothWays() {
        let track = BorderTrack(width: 1512, height: 942)
        for corner in BorderTrack.Corner.allCases {
            let position = track.position(of: corner)
            for offset: CGFloat in [-99, -1, 0, 1, 99] {
                let passage = track.corner(for: position + offset, length: 200)!
                XCTAssertEqual(passage.corner, corner)
                XCTAssertEqual(passage.before + passage.after, 200, accuracy: 0.001)
                XCTAssertGreaterThan(passage.before, 0)
                XCTAssertGreaterThan(passage.after, 0)
            }
        }
        XCTAssertEqual(track.place(at: -1).edge, .left)
        XCTAssertEqual(track.place(at: track.perimeter + 1).edge, .top)
        XCTAssertEqual(track.place(at: track.perimeter + 1).along, 1)
    }

    func testReadingOptionsKeepLocalDefaultAndUseTheDeclaredWeeklyWindow() {
        let model = NotchViewModel()
        prepare(model)
        XCTAssertTrue(model.showsCellReading)
        XCTAssertFalse(model.weeklyReading)
        model.showsNotchReadings = false
        XCTAssertFalse(model.showsCellReading)
        let snapshot = ProviderSnapshot(id: "synthetic-quota", displayName: "Test", glyph: .claude,
            fidelity: .official, status: .ok,
            windows: [LimitWindow(id: "session", label: "Session", usedFraction: 0.3),
                      LimitWindow(id: "week", label: "Week", usedFraction: 0.7)],
            headlineID: "session", weeklyID: "week")
        XCTAssertEqual(ProviderCell(snapshot: snapshot).displayedReadingText, "30%")
        XCTAssertEqual(ProviderCell(snapshot: snapshot, weeklyRing: .inside,
                                   showsWeeklyReading: true).displayedReadingText, "30%/70%")
        XCTAssertEqual(ProviderCell(snapshot: snapshot, weeklyRing: .off,
                                   showsWeeklyReading: true).displayedReadingText, "30%")
    }
}
