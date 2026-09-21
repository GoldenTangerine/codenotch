/**
 @name: 收起刘海活动提示测试
 @Descripttion: 验证供应商聚合、轮播、收起几何与提示绘制。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-21 16:37:12
 @LastEditTime: 2026-09-21 16:37:12
 @FilePath: Tests/CollapsedNotchActivityTests.swift
 */
import SwiftUI
import XCTest
@testable import Codenotch

@MainActor
final class CollapsedNotchActivityTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_000)

    private func session(_ id: String, _ state: AgentSession.State) -> AgentSession {
        AgentSession(id: id, name: id, detail: "", state: state, waitingFor: nil, since: epoch)
    }

    private func model() -> NotchViewModel {
        let model = NotchViewModel()
        model.edge = .top
        model.hardwareNotch = HardwareNotch(width: 220, height: 38)
        model.screenSize = CGSize(width: 1440, height: 900)
        model.surfaceStyle = .solid
        model.snapshots = ["a", "b", "c"].map {
            ProviderSnapshot(id: $0, displayName: $0, glyph: .claude,
                             fidelity: .official, status: .ok, windows: [])
        }
        model.sessions = ["a": [session("a1", .busy)], "b": [session("b1", .waiting)]]
        model.isExpanded = false
        return model
    }

    func testCountsProvidersRatherThanSessionsAndIgnoresRefreshAndCompletion() {
        let model = model()
        model.sessions["a"] = [session("a1", .busy), session("a2", .busy), session("a3", .waiting)]
        model.sessions["c"] = [session("c1", .success)]
        model.refreshing = ["c"]
        XCTAssertEqual(model.collapsedProviders.map { $0.snapshot.providerID }, ["a", "b"])
        XCTAssertEqual(model.collapsedProviders.first?.activity.state, .waiting)
        model.sessions = ["a": [session("a1", .idle)]]
        XCTAssertFalse(model.showsCollapsedActivity)
        XCTAssertEqual(model.restingLength, 220)
    }

    func testCompletedSessionDoesNotHideAnActiveLinkedRequest() {
        let model = model()
        model.snapshots = [model.snapshots[0]]
        model.snapshots[0].linked = CodeSwitchDetails(platform: "Codex", provider: CodeSwitchProvider(
            providerId: "a", providerName: "A", icon: "openai", activeRequests: 1,
            status: "active", loading: false, updatedAt: 0, quotas: [], stats: nil))
        model.sessions = ["a": [session("done", .success)]]
        XCTAssertEqual(model.collapsedProviders.count, 1)
        XCTAssertEqual(model.collapsedProvider?.activity.state, .working)
        model.sessions["a"] = [session("waiting", .waiting)]
        XCTAssertEqual(model.collapsedProvider?.activity.state, .waiting)
        model.sessions = ["a": [session("done", .success)]]
        model.snapshots[0].linked = nil
        XCTAssertTrue(model.collapsedProviders.isEmpty)
    }

    func testRepeatedLayoutAndRotationReadsReuseActivityAggregation() {
        let model = model()
        _ = model.collapsedProviders
        let initial = model.collapsedAggregationCount
        for index in 0..<100 {
            _ = model.notchSize
            _ = model.collapsedProviders.count
            model.updateCollapsedRotation(at: epoch.addingTimeInterval(Double(index)), visible: true)
        }
        XCTAssertEqual(model.collapsedAggregationCount, initial)
        model.now = epoch
        model.collapsedSideWidth = 100
        _ = model.collapsedProviders
        XCTAssertEqual(model.collapsedAggregationCount, initial)
        model.sessions = [:]
        XCTAssertTrue(model.collapsedProviders.isEmpty)
        XCTAssertEqual(model.collapsedAggregationCount, initial + 1)
    }

    func testCarouselRetainsEngineProgressAndReleasesInactiveProviders() {
        let model = model()
        let store = model.collapsedPlayback
        let programme = BotMarkProgramme.forMood(.working, persona: .calm)
        weak var released: BotMarkEngine?
        var visited = Set<String>()
        for appearance in 0..<8 {
            let engine = store.engine(for: "a")
            if appearance == 0 { released = engine }
            XCTAssertTrue(engine === released)
            for frame in 0..<180 {
                _ = engine.advance(to: Double(appearance * 600 + frame) / 60, programme: programme)
                visited.insert(engine.state)
            }
        }
        XCTAssertGreaterThan(visited.count, 1, "Three-second appearances must progress beyond the first routine beat")
        XCTAssertEqual(store.count, 1)
        model.sessions = [:]
        _ = model.collapsedProviders
        XCTAssertEqual(store.count, 0)
        XCTAssertNil(released)
    }

    func testDeduplicatesSourceProvidersAndHonorsActivityRouting() {
        let model = model()
        model.snapshots[1].sourceProviderID = "a"
        XCTAssertEqual(model.collapsedProviders.map { $0.snapshot.providerID }, ["a"])
        model.sessions = ["routed": [session("r1", .busy)]]
        model.activitySourceIDs = ["a": "routed"]
        XCTAssertEqual(model.collapsedProviders.map { $0.snapshot.providerID }, ["a"])
        model.activitySourceIDs = [:]
        XCTAssertTrue(model.collapsedProviders.isEmpty)
    }

    func testMultipleLocalModelsCountAsOneProvider() {
        let model = model()
        model.sessions = [:]
        for index in 0..<2 {
            model.snapshots[index].sourceProviderID = "local"
            model.snapshots[index].localModel = LocalRuntimeReading.Model(
                name: "model\(index)", memoryBytes: nil, contextLength: nil, quantizationLevel: nil)
        }
        model.thinkingModels = ["model0:latest": epoch, "model1:latest": epoch]
        XCTAssertEqual(model.collapsedProviders.map { $0.snapshot.providerID }, ["local"])
        model.thinkingModels = [:]
        XCTAssertTrue(model.collapsedProviders.isEmpty)
    }

    func testRotationKeepsOrderAndImmediatelyReplacesRemovedProvider() {
        let model = model()
        model.updateCollapsedRotation(at: epoch, visible: true)
        XCTAssertEqual(model.collapsedProviderID, "a")
        model.updateCollapsedRotation(at: epoch.addingTimeInterval(2.9), visible: true)
        XCTAssertEqual(model.collapsedProviderID, "a")
        model.updateCollapsedRotation(at: epoch.addingTimeInterval(3), visible: true)
        XCTAssertEqual(model.collapsedProviderID, "b")
        model.updateCollapsedRotation(at: epoch.addingTimeInterval(6), visible: true)
        XCTAssertEqual(model.collapsedProviderID, "a")
        model.sessions["a"] = nil
        XCTAssertEqual(model.collapsedProvider?.snapshot.providerID, "b")
        model.updateCollapsedRotation(at: epoch.addingTimeInterval(7), visible: true)
        model.updateCollapsedRotation(at: epoch.addingTimeInterval(70), visible: true)
        XCTAssertEqual(model.collapsedProviderID, "b")
        model.snapshots = []
        model.updateCollapsedRotation(at: epoch.addingTimeInterval(71), visible: true)
        XCTAssertNil(model.collapsedProviderID)
        XCTAssertFalse(model.showsCollapsedActivity)
    }

    func testExpansionAndWindowVisibilityPauseRotationWithoutLosingSelection() {
        let model = model()
        model.updateCollapsedRotation(at: epoch, visible: true)
        model.updateCollapsedRotation(at: epoch.addingTimeInterval(3), visible: true)
        model.isExpanded = true
        model.updateCollapsedRotation(at: epoch.addingTimeInterval(4), visible: true)
        XCTAssertFalse(model.showsCollapsedActivity)
        model.isExpanded = false
        model.updateCollapsedRotation(at: epoch.addingTimeInterval(40), visible: true)
        XCTAssertEqual(model.collapsedProviderID, "b")
        model.updateCollapsedRotation(at: epoch.addingTimeInterval(41), visible: false)
        model.updateCollapsedRotation(at: epoch.addingTimeInterval(80), visible: true)
        model.updateCollapsedRotation(at: epoch.addingTimeInterval(82), visible: true)
        XCTAssertEqual(model.collapsedProviderID, "b")
        model.updateCollapsedRotation(at: epoch.addingTimeInterval(83), visible: true)
        XCTAssertEqual(model.collapsedProviderID, "a")
    }

    func testHardwareGeometryAndActivationStayInScreenPointsAtEveryScale() {
        let model = model()
        for scale: CGFloat in [0.75, 1, 1.5] {
            model.sizeScale = scale
            for width: CGFloat in [40, 64, 160] {
                model.collapsedSideWidth = width
                let length = 220 + 2 * width
                XCTAssertEqual(model.notchLength * scale, length, accuracy: 0.001)
                XCTAssertEqual(model.notchDepth * scale, 38, accuracy: 0.001)
                let start = model.slack + (model.shapeLength * scale - length) / 2
                XCTAssertGreaterThanOrEqual(start, 0)
                XCTAssertLessThanOrEqual(start + length, model.panelSize.width)
                let rect = NotchGeometry.activationRect(
                    placement: model.placement, slack: model.slack,
                    shapeLength: model.shapeLength * scale, restingLength: length,
                    restingDepth: 38, hardwareNotch: model.hardwareNotch,
                    triggerHeight: 0, activityWidth: length)
                XCTAssertEqual(rect.width, length, accuracy: 0.001)
                XCTAssertEqual(rect.height, 38, accuracy: 0.001)
                XCTAssertTrue(rect.contains(CGPoint(x: start + width / 2, y: 18)))
                XCTAssertTrue(rect.contains(CGPoint(x: start + length - width / 2, y: 18)))
                XCTAssertFalse(rect.contains(CGPoint(x: rect.midX, y: 39)))
            }
        }
        model.screenSize.width = 280
        XCTAssertEqual(model.resolvedCollapsedSideWidth, 30)
        model.sessions = [:]
        XCTAssertEqual(model.notchLength * model.sizeScale, 220, accuracy: 0.001)
    }

    func testOtherPlacementsAndExpandedWidthRemainUnchanged() {
        let model = model()
        model.isExpanded = true
        let expanded = model.notchSize
        model.collapsedSideWidth = 160
        XCTAssertEqual(model.notchSize, expanded)
        model.isExpanded = false
        model.hardwareNotch = nil
        XCTAssertFalse(model.showsCollapsedActivity)
        XCTAssertEqual(model.notchLength, NotchLayout.pillHeight)
        for edge in [NotchEdge.left, .right, .bottom] {
            model.edge = edge
            XCTAssertFalse(model.showsCollapsedActivity)
        }
    }

    func testBothSideIndicatorsOpenAndKeepThePanelOpenUnderAStationaryPointer() {
        for direction: CGFloat in [-1, 1] {
            let panel = NotchPanel(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600))
            var scheduled: [DispatchWorkItem] = []
            var pointer = CGPoint.zero
            let controller = NotchWindowController(panel: panel, mouseLocation: { pointer },
                scheduleInteractionWork: { _, work in scheduled.append(work) })
            defer { controller.stop() }
            controller.isFullScreenActive = { false }
            let model = controller.model
            model.edge = .top
            model.hardwareNotch = HardwareNotch(width: 220, height: 38)
            model.notchTriggerHeight = -20
            model.collapsedSideWidth = 160
            model.snapshots = [ProviderSnapshot(id: "a", displayName: "A", glyph: .claude,
                                               fidelity: .official, status: .ok, windows: [])]
            model.sessions = ["a": [session("a1", .busy)]]
            model.positionedLeading = 400 - model.shapeLength / 2
            pointer = CGPoint(x: panel.frame.minX + 400 + direction * 190, y: panel.frame.maxY - 18)
            controller.cursorMoved()
            XCTAssertTrue(model.isExpanded)
            controller.cursorMoved()
            for work in scheduled where !work.isCancelled { work.perform() }
            XCTAssertTrue(model.isExpanded, "Opening must not move the live region away from the pointer")
            pointer.x = panel.frame.minX + 20
            controller.cursorMoved()
            for work in scheduled where !work.isCancelled { work.perform() }
            XCTAssertFalse(model.isExpanded)
        }
    }

    func testRobotSettingAndActivityMatchExpandedPresentation() throws {
        let model = model()
        let provider = try XCTUnwrap(model.collapsedProvider)
        XCTAssertNil(model.botPresentation(for: provider.snapshot, activityOverride: provider.activity, active: true))
        var appearance = BotAppearance()
        appearance.enabled = true
        model.botAppearances["a"] = appearance
        let compact = try XCTUnwrap(model.botPresentation(for: provider.snapshot,
                                                          activityOverride: provider.activity, active: true))
        XCTAssertTrue(compact.active)
        model.isExpanded = true
        let expanded = try XCTUnwrap(model.botPresentation(for: provider.snapshot))
        XCTAssertEqual(compact.appearance, expanded.appearance)
        XCTAssertEqual(compact.mood, expanded.mood)
        XCTAssertEqual(compact.waiting, expanded.waiting)
    }

    func testCollapsedRenderingShowsBothSidesAndLeavesHardwareBlack() throws {
        let model = model()
        for scale: CGFloat in [0.75, 1.5] {
            model.sizeScale = scale
            let size = model.panelSize
            let renderer = ImageRenderer(content: NotchRootView(model: model)
                .frame(width: size.width, height: size.height)
                .environment(\.colorScheme, .dark))
            renderer.scale = 1
            let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
            let center = model.slack + model.shapeLength * scale / 2
            func brightPixels(from lower: Int, to upper: Int) -> Int {
                var count = 0
                for x in lower..<upper {
                    for y in 4..<30 {
                        if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                           color.alphaComponent > 0.5,
                           max(color.redComponent, color.greenComponent, color.blueComponent) > 0.5 {
                            count += 1
                        }
                    }
                }
                return count
            }
            XCTAssertGreaterThan(brightPixels(from: Int(center - 174), to: Int(center - 110)), 10)
            XCTAssertGreaterThan(brightPixels(from: Int(center + 110), to: Int(center + 174)), 10)
            XCTAssertEqual(brightPixels(from: Int(center - 100), to: Int(center + 100)), 0)
        }
    }
}
