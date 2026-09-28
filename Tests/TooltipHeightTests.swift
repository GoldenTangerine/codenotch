/**
 @name: 气泡高度测试
 @Descripttion: 验证高度设置、内容测量、屏幕约束与气泡交互区域。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-09 15:32:59
 @LastEditTime: 2026-09-09 15:32:59
 @FilePath: Tests/TooltipHeightTests.swift
 */
import AppKit
import SwiftUI
import XCTest
@testable import Codenotch

@MainActor
final class TooltipHeightTests: XCTestCase {
    private let screen = TooltipTestScreen(
        frameValue: CGRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrameValue: CGRect(x: 0, y: 48, width: 1440, height: 828))

    private func snapshot(_ id: String = "test", windows: Int = 1) -> ProviderSnapshot {
        ProviderSnapshot(id: id, displayName: id, glyph: .claude, fidelity: .official, status: .ok,
            windows: (0..<windows).map { LimitWindow(id: "window-\($0)", label: "Window \($0)", usedFraction: 0.4) })
    }

    func testPreferenceDefaultsPersistenceAndInvalidValue() {
        let suite = "TooltipHeightTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)
        XCTAssertEqual(preferences.tooltipHeightMode, .standard)
        preferences.tooltipHeightMode = .full
        XCTAssertEqual(Preferences(defaults: defaults).tooltipHeightMode, .full)
        preferences.tooltipHeightMode = .standard
        XCTAssertEqual(Preferences(defaults: defaults).tooltipHeightMode, .standard)
        defaults.set("unknown", forKey: "tooltipHeightMode")
        XCTAssertEqual(Preferences(defaults: defaults).tooltipHeightMode, .standard)
    }

    func testStandardHeightRemainsUnchanged() {
        let model = NotchViewModel()
        let provider = snapshot(windows: 8)
        model.snapshots = [provider]
        model.hoveredIndex = 0
        model.adopt(screen: screen)
        XCTAssertEqual(model.tooltipHeight(for: provider), NotchLayout.cardHeight(windowCount: 8))
        model.recordTooltipHeight(900, for: provider, activity: nil)
        XCTAssertTrue(model.tooltipHeights.isEmpty)
        XCTAssertEqual(model.panelSize, model.standardPanelSize(cellCount: 1))
    }

    func testMeasuredHeightGrowsShrinksAndIsCapped() {
        let model = NotchViewModel()
        let provider = snapshot()
        model.snapshots = [provider]
        model.hoveredIndex = 0
        model.tooltipHeightMode = .full
        model.adopt(screen: screen)
        var updates = 0
        model.onTooltipHeightChange = { updates += 1 }
        model.recordTooltipHeight(450.2, for: provider, activity: nil)
        XCTAssertEqual(model.tooltipHeight(for: provider), 451)
        model.recordTooltipHeight(450.2, for: provider, activity: nil)
        XCTAssertEqual(updates, 1)
        model.recordTooltipHeight(3000, for: provider, activity: nil)
        XCTAssertEqual(model.tooltipHeight(for: provider), model.fullTooltipHeightLimit)
        model.recordTooltipHeight(120, for: provider, activity: nil)
        XCTAssertEqual(model.tooltipHeight(for: provider), 120)
    }

    func testInvalidAndPreviousProviderMeasurementsAreIgnored() {
        let model = NotchViewModel()
        let first = snapshot("first")
        let second = snapshot("second")
        model.snapshots = [first, second]
        model.hoveredIndex = 1
        model.tooltipHeightMode = .full
        model.recordTooltipHeight(450, for: first, activity: nil)
        for value in [CGFloat.nan, .infinity, 0, -1] {
            model.recordTooltipHeight(value, for: second, activity: nil)
        }
        XCTAssertTrue(model.tooltipHeights.isEmpty)
        model.recordTooltipHeight(450, for: second, activity: nil)
        model.replaceSnapshots([first])
        XCTAssertTrue(model.tooltipHeights.isEmpty)
    }

    func testPreviousContentMeasurementIsIgnored() {
        let model = NotchViewModel()
        let provider = snapshot()
        model.snapshots = [provider]
        model.hoveredIndex = 0
        model.tooltipHeightMode = .full
        model.sessions[provider.id] = [AgentSession(id: "session", name: "session", detail: "Terminal",
                                                  state: .busy, waitingFor: nil, since: Date())]
        model.recordTooltipHeight(100, for: provider, activity: nil)
        XCTAssertTrue(model.tooltipHeights.isEmpty)
        model.recordTooltipHeight(200, for: provider, activity: model.activity(for: provider.id))
        XCTAssertEqual(model.tooltipHeights[provider.id], 200)
    }

    func testSidePanelKeepsNotchPositionWhileReservingUsableHeight() {
        for edge in [NotchEdge.left, .right] {
            let model = NotchViewModel()
            model.edge = edge
            model.snapshots = [snapshot()]
            model.adopt(screen: screen)
            let size = model.standardPanelSize(cellCount: 1)
            let slack = (size.height - model.shapeLength) / 2
            for offset: CGFloat in [-100, 0, 100] {
                let old = NotchGeometry.panelFrame(for: screen, panelSize: size, edge: edge,
                                                   alongOffset: offset, slack: slack)
                model.tooltipHeightMode = .full
                let layout = TooltipSizing.sidePanelLayout(usable: screen.visibleFrameValue,
                    standardFrame: old, standardSlack: slack, size: model.panelSize, shapeLength: model.shapeLength)
                XCTAssertEqual(layout.frame.height, screen.visibleFrameValue.height)
                XCTAssertEqual(layout.frame.maxY - layout.leading, old.maxY - slack, accuracy: 0.001)
            }
        }
    }

    func testSavedPositionKeepsNotchAnchorForEveryEdge() {
        for edge in NotchEdge.allCases {
            for fraction in [0.0, 0.5, 1.0] {
                let model = NotchViewModel()
                model.edge = edge
                model.snapshots = [snapshot()]
                model.adopt(screen: screen)
                let position = NotchPosition(edge: edge, fraction: fraction)
                let before = position.layout(on: screen, panelSize: model.panelSize,
                    shapeLength: model.shapeLength, endClearance: NotchLayout.orbHotZone)
                model.tooltipHeightMode = .full
                let after = position.layout(on: screen, panelSize: model.panelSize,
                    shapeLength: model.shapeLength, endClearance: NotchLayout.orbHotZone)
                let oldAnchor = edge.isVertical ? before.frame.maxY - before.leading : before.frame.minX + before.leading
                let newAnchor = edge.isVertical ? after.frame.maxY - after.leading : after.frame.minX + after.leading
                XCTAssertEqual(newAnchor, oldAnchor, accuracy: 1)
            }
        }
    }

    func testLegacyOffsetsKeepNotchAndHandleInsideFullPanel() {
        for edge in [NotchEdge.left, .right] {
            let model = NotchViewModel()
            model.edge = edge
            model.snapshots = [snapshot()]
            model.adopt(screen: screen)
            let standardSize = model.standardPanelSize(cellCount: 1)
            let slack = (standardSize.height - model.shapeLength) / 2
            model.tooltipHeightMode = .full
            for offset: CGFloat in [-1000, 1000] {
                let original = NotchGeometry.panelFrame(for: screen, panelSize: standardSize,
                    edge: edge, alongOffset: offset, slack: slack)
                let layout = TooltipSizing.sidePanelLayout(usable: screen.visibleFrameValue,
                    standardFrame: original, standardSlack: slack, size: model.panelSize, shapeLength: model.shapeLength)
                XCTAssertEqual(layout.frame.maxY - layout.leading, original.maxY - slack, accuracy: 0.001)
                XCTAssertGreaterThanOrEqual(layout.leading, 0)
                XCTAssertLessThanOrEqual(layout.leading + model.shapeLength + NotchLayout.orbHotZone / 2,
                                         layout.frame.height)
                XCTAssertLessThanOrEqual(layout.frame.minY, screen.visibleFrameValue.minY)
                XCTAssertGreaterThanOrEqual(layout.frame.maxY, screen.visibleFrameValue.maxY)
                model.positionedLeading = layout.leading
                let usable = screen.visibleFrameValue.insetBy(dx: 8, dy: 8)
                model.tooltipAlongBounds = (layout.frame.maxY - usable.maxY)...(layout.frame.maxY - usable.minY)
                model.hoveredIndex = 0
                model.recordTooltipHeight(3000, for: model.snapshots[0], activity: nil)
                let height = model.tooltipHeight(for: model.snapshots[0])
                let centre = model.tooltipAlong(index: 0, length: height)
                XCTAssertGreaterThanOrEqual(layout.frame.maxY - centre - height / 2, usable.minY)
                XCTAssertLessThanOrEqual(layout.frame.maxY - centre + height / 2, usable.maxY)
            }
        }
    }

    func testHeightLimitAdaptsToScreensAndHardwareNotch() {
        let smaller = TooltipTestScreen(frameValue: CGRect(x: -1024, y: 0, width: 1024, height: 768),
            visibleFrameValue: CGRect(x: -1024, y: 40, width: 1024, height: 700))
        for edge in NotchEdge.allCases {
            XCTAssertLessThan(TooltipSizing.heightLimit(on: smaller, edge: edge, contentInset: 0),
                              TooltipSizing.heightLimit(on: screen, edge: edge, contentInset: 0))
        }
        let height = TooltipSizing.heightLimit(on: screen, edge: .top, contentInset: 32)
        let bottom = screen.frameValue.maxY - 32 - NotchLayout.bodyDepth(for: .top)
            - NotchLayout.tailLength - NotchLayout.tailGap - height
        XCTAssertGreaterThanOrEqual(bottom, screen.visibleFrameValue.minY + TooltipSizing.screenMargin)
    }

    func testExpandedTooltipHitRegionUsesMeasuredHeight() throws {
        for edge in NotchEdge.allCases {
            let controller = NotchWindowController()
            let model = controller.model
            let provider = snapshot()
            model.edge = edge
            model.snapshots = [provider]
            model.hoveredIndex = 0
            model.tooltipHeightMode = .full
            model.adopt(screen: screen)
            model.positionedLeading = 100
            model.tooltipAlongBounds = 8...(edge.isVertical ? model.panelSize.height - 8 : model.panelSize.width - 8)
            model.recordTooltipHeight(600, for: provider, activity: nil)
            let rect = try XCTUnwrap(controller.tooltipRect(index: 0))
            let extra = edge.isVertical ? 0 : NotchLayout.tailLength + NotchLayout.tailGap
            XCTAssertEqual(rect.height, 600 + extra, accuracy: 0.001)
            if edge.isVertical {
                XCTAssertGreaterThanOrEqual(rect.minY, 8)
                XCTAssertLessThanOrEqual(rect.maxY, model.panelSize.height - 8)
            }
        }
    }

    func testFullContentMeasuresEveryWindowAndSession() {
        let now = Date()
        let activity = ActivitySummary(sessions: (0..<20).map {
            AgentSession(id: "session-\($0)", name: "Session \($0)", detail: "Terminal",
                         state: .busy, waitingFor: nil, since: now)
        })
        let measured = measuredHeight(for: snapshot(windows: 8), activity: activity)
        XCTAssertGreaterThan(measured, 20 * NotchLayout.cardBodyLineHeight)
        XCTAssertGreaterThan(measured, NotchLayout.cardHeight(windowCount: 8, sessionCount: 20, sessionCap: 2))
    }

    private func measuredHeight(for provider: ProviderSnapshot, activity: ActivitySummary? = nil) -> CGFloat {
        var measured: CGFloat = 0
        let host = NSHostingView(rootView: TooltipCard(snapshot: provider, activity: activity,
            now: Date(), heightMode: .full, resolvedHeight: 600, onHeightChange: { measured = $0 }))
        host.frame = CGRect(x: 0, y: 0, width: NotchLayout.cardWidth + NotchLayout.tailLength, height: 600)
        host.layoutSubtreeIfNeeded()
        let deadline = Date().addingTimeInterval(0.3)
        while measured == 0 && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            host.layoutSubtreeIfNeeded()
        }
        XCTAssertGreaterThan(measured, 0)
        return measured
    }

    func testLinkedStatisticsContributeTheirFullHeight() {
        let stats = CodeSwitchStats(totalRequests: 10, successfulRequests: 9, failedRequests: 1,
            successRate: 0.9, inputTokens: 1000, outputTokens: 500, cacheReadTokens: 100,
            costTotal: 2, avgFirstTokenSec: 1, avgTokensPerSec: 30)
        let platform = CodeSwitchPlatform(platform: "codex", name: "Codex", icon: "openai", error: false, providers: [])
        func provider(_ stats: CodeSwitchStats?) -> ProviderSnapshot {
            CodeSwitchProvider(providerId: "test", providerName: "Test", icon: "openai", activeRequests: 1,
                status: "active", loading: false, updatedAt: 0, quotas: [], stats: stats).snapshot(platform: platform)
        }
        let without = measuredHeight(for: provider(nil))
        let withStats = measuredHeight(for: provider(stats))
        XCTAssertGreaterThanOrEqual(withStats - without, 6 * NotchLayout.cardBodyLineHeight)
    }

    func testLongStatusTextWrapsAndIncreasesHeight() {
        var provider = snapshot(windows: 0)
        provider.status = .error("Unavailable")
        let short = measuredHeight(for: provider)
        provider.status = .error(String(repeating: "供应商暂时不可用，请检查连接后重试。 ", count: 20))
        XCTAssertGreaterThan(measuredHeight(for: provider), short)
    }

    func testSwitchingProviderResetsScrollButRefreshingDoesNot() throws {
        let host = NSHostingView(rootView: TooltipCard(snapshot: snapshot("A", windows: 20), now: Date(),
            heightMode: .full, resolvedHeight: 300))
        host.frame = CGRect(x: 0, y: 0, width: NotchLayout.cardWidth + NotchLayout.tailLength, height: 300)
        settle(host)
        let initial = try XCTUnwrap(findScrollView(in: host))
        initial.contentView.scroll(to: CGPoint(x: 0, y: 400))
        initial.reflectScrolledClipView(initial.contentView)
        XCTAssertEqual(initial.contentView.bounds.minY, 400, accuracy: 0.001)

        host.rootView = TooltipCard(snapshot: snapshot("A", windows: 21), now: Date(),
            heightMode: .full, resolvedHeight: 300)
        settle(host)
        let refreshed = try XCTUnwrap(findScrollView(in: host))
        XCTAssertTrue(initial === refreshed)
        XCTAssertEqual(refreshed.contentView.bounds.minY, 400, accuracy: 0.001)

        host.rootView = TooltipCard(snapshot: snapshot("B", windows: 21), now: Date(),
            heightMode: .full, resolvedHeight: 300)
        settle(host)
        let switched = try XCTUnwrap(findScrollView(in: host))
        XCTAssertFalse(refreshed === switched)
        XCTAssertEqual(switched.contentView.bounds.minY, 0, accuracy: 0.001)
    }

    func testMeasurementUpdatesRenderedHeightAndInteractionRegion() throws {
        let controller = NotchWindowController()
        let model = controller.model
        model.snapshots = [snapshot()]
        model.hoveredIndex = 0
        model.isExpanded = true
        model.tooltipHeightMode = .full
        model.adopt(screen: screen)
        model.positionedLeading = 200
        model.tooltipAlongBounds = 8...(model.panelSize.height - 8)
        var rectAtUpdate: CGRect?
        model.onTooltipHeightChange = { rectAtUpdate = controller.tooltipRect(index: 0) }
        defer { model.onTooltipHeightChange = nil }
        let host = NSHostingView(rootView: NotchRootView(model: model))
        host.frame = CGRect(origin: .zero, size: model.panelSize)
        settle(host)
        let shortHeight = try XCTUnwrap(model.tooltipHeights["test"])
        XCTAssertEqual(try XCTUnwrap(rectAtUpdate).height, shortHeight, accuracy: 0.001)

        model.replaceSnapshots([snapshot(windows: 30)])
        settle(host)
        XCTAssertGreaterThan(try XCTUnwrap(model.tooltipHeights["test"]), model.fullTooltipHeightLimit)
        XCTAssertEqual(try XCTUnwrap(rectAtUpdate).height, model.fullTooltipHeightLimit.rounded(.down), accuracy: 0.001)
        let fullHeight = model.tooltipHeight(for: model.snapshots[0])
        XCTAssertEqual(fullHeight, try XCTUnwrap(rectAtUpdate).height)

        model.replaceSnapshots([snapshot()])
        settle(host)
        XCTAssertEqual(model.tooltipHeight(for: model.snapshots[0]), shortHeight)
        XCTAssertEqual(try XCTUnwrap(rectAtUpdate).height, shortHeight, accuracy: 0.001)
    }

    private func settle(_ host: NSView) {
        for _ in 0..<10 {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
    }

    private func findScrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        return view.subviews.lazy.compactMap { self.findScrollView(in: $0) }.first
    }

    func testFleetAppliesModeToExistingAndNewWindows() throws {
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("Requires a display") }
        let fleet = NotchFleet(scope: .allDisplays, edge: .right)
        defer { fleet.stop() }
        fleet.apply(.hidden)
        fleet.apply(tooltipHeightMode: .full)
        fleet.show()
        XCTAssertFalse(fleet.controllersForTesting.isEmpty)
        XCTAssertTrue(fleet.controllersForTesting.allSatisfy { $0.model.tooltipHeightMode == .full })
        fleet.apply(tooltipHeightMode: .standard)
        XCTAssertTrue(fleet.controllersForTesting.allSatisfy { $0.model.tooltipHeightMode == .standard })
        fleet.stop()
        fleet.apply(tooltipHeightMode: .full)
        fleet.show()
        XCTAssertFalse(fleet.controllersForTesting.isEmpty)
        XCTAssertTrue(fleet.controllersForTesting.allSatisfy { $0.model.tooltipHeightMode == .full })
    }
}

private struct TooltipTestScreen: ScreenDescribing {
    let frameValue: CGRect
    let visibleFrameValue: CGRect
}
