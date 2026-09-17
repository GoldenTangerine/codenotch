/**
 @name: 联动周期比例环回归
 @Descripttion: 验证周期组合、单位回退、显示开关和真实额度提醒隔离。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-14 22:16:39
 @LastEditTime: 2026-09-14 22:16:39
 @FilePath: Tests/CodeSwitchQuotaRingsTests.swift
 */
import Foundation
import SwiftUI
import Testing
@testable import Codenotch

@Suite @MainActor struct CodeSwitchQuotaRingsTests {
    private struct Screen: ScreenDescribing {
        let frameValue = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let visibleFrameValue = CGRect(x: 0, y: 0, width: 1440, height: 900)
    }

    private func quota(_ key: String, used: Double = 10, total: Double = 20,
                       mode: String? = "currency", unit: String? = nil,
                       active: Bool = true, unlimited: Bool = false,
                       kind: String = "progress", invalid: String? = nil, reset: String? = nil) -> CodeSwitchQuota {
        CodeSwitchQuota(key: key, label: nil, used: used, total: total, unlimited: unlimited,
            nextReset: reset ?? ISO8601DateFormatter().string(from: Date().addingTimeInterval(5 * 86_400)), active: active, valueMode: mode, unit: unit, extra: nil,
            invalidMessage: invalid, displayKind: kind)
    }

    private var weekly: CodeSwitchQuota { quota("weekly", used: 80, total: 200) }
    private var monthly: CodeSwitchQuota { quota("monthly", used: 200, total: 2000) }

    @Test func independentRingKeepsActualQuotasAndUsesDailyBudget() throws {
        let raw = snapshot([quota("daily"), weekly, monthly])
        let now = Date()
        let budget = try #require(CodeSwitchDailyBudget.reading(for: raw, now: now))
        for placement in [WeeklyRing.off, .inside, .outside] {
            let cell = ProviderCell(snapshot: raw, activity: ActivitySummary(state: .working),
                weeklyRing: placement, codeSwitchQuotaRatiosEnabled: true, independentInnerRing: true, now: now)
            #expect(cell.displayedMainFraction == raw.ringFraction)
            #expect(cell.displayedSecondaryFraction == raw.secondaryWindow?.usedFraction)
            #expect(cell.innerReading?.fraction == budget.usedFraction)
            let text = try #require(cell.quotaRingText)
            #expect(text.contains(L10n.t("Daily budget")))
            #expect(text.contains(L10n.t("Secondary quota ring")) == (placement != .off))
        }
        let legacy = ProviderCell(snapshot: raw, codeSwitchQuotaRatiosEnabled: true, now: now)
        #expect(legacy.innerReading == nil)
        #expect(legacy.displayedMainFraction == budget.usedFraction)
    }

    @Test func allProvidersEnlargeEvenWithoutBudget() {
        for raw in [snapshot([]), snapshot([quota("five_hour")]), snapshot([weekly])] {
            let model = NotchViewModel()
            model.snapshots = [raw]
            model.independentInnerRing = true
            #expect(model.ringGrowth == NotchLayout.independentRingGrowth)
            #expect(model.cellRingDiameter == 54)
            model.codeSwitchQuotaRatiosEnabled = true
            #expect(model.cellRingDiameter == 54)
            model.independentInnerRing = false
            #expect(model.ringGrowth == 0)
        }
    }

    @Test func topAvoidanceIsIndependentOfScaleAndOnlyAppliesAtTop() {
        struct NotchedScreen: ScreenDescribing {
            let frameValue = CGRect(x: 0, y: 0, width: 1440, height: 900)
            let visibleFrameValue = CGRect(x: 0, y: 0, width: 1440, height: 868)
            let hardwareNotch: HardwareNotch? = HardwareNotch(width: 200, height: 32)
        }
        let model = NotchViewModel()
        for edge in NotchEdge.allCases {
            model.edge = edge
            for scale: CGFloat in [0.75, 1, 1.5] {
                model.sizeScale = scale
                model.adopt(screen: NotchedScreen())
                for adjustment: CGFloat in [-60, 0, 10, 120] {
                    model.topAvoidanceAdjustment = adjustment
                    let expected: CGFloat = edge == .top ? max(0, 32 + adjustment) : 0
                    #expect(abs(model.contentInset * scale - expected) < 0.000001)
                }
            }
        }
        model.edge = .top
        model.topAvoidanceAdjustment = 12
        model.adopt(screen: Screen())
        #expect(abs(model.contentInset * model.sizeScale - 12) < 0.000001)
    }

    @Test func ringSpacingMovesContentsWithoutChangingAlongPositions() {
        let model = NotchViewModel()
        for edge in NotchEdge.allCases {
            model.edge = edge
            for scale: CGFloat in [0.75, 1, 1.5] {
                model.sizeScale = scale
                model.ringEdgeAdjustment = 0
                let depth = model.notchDrawnDepth
                let center = model.ringCenter(index: 0)
                for adjustment: CGFloat in [-40, -5, 0, 20, 80] {
                    model.ringEdgeAdjustment = adjustment
                    #expect(abs((model.ringEdgePadding + model.ringEdgeOffset) * scale - adjustment) < 0.000001)
                    #expect(abs(model.notchDrawnDepth - depth - max(0, adjustment)) < 0.000001)
                    #expect(model.ringCenter(index: 0) == center)
                    #expect(model.tooltipInset == model.notchDrawnDepth + NotchLayout.tailGap)
                }
            }
        }
    }

    @Test func geometrySettingsPersistAndRejectInvalidValues() throws {
        let domain = "GeometrySettingsTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.topAvoidanceAdjustment == 0 && preferences.ringEdgeAdjustment == 0)
        preferences.topAvoidanceAdjustment = 15
        preferences.ringEdgeAdjustment = -12
        let restored = Preferences(defaults: defaults)
        #expect(restored.topAvoidanceAdjustment == 15 && restored.ringEdgeAdjustment == -12)
        preferences.topAvoidanceAdjustment = .infinity
        preferences.ringEdgeAdjustment = -999
        #expect(preferences.topAvoidanceAdjustment == 0 && preferences.ringEdgeAdjustment == -40)
        let clamped = Preferences(defaults: defaults)
        #expect(clamped.topAvoidanceAdjustment == 0 && clamped.ringEdgeAdjustment == -40)
        preferences.ringEdgeAdjustment = .nan
        #expect(preferences.ringEdgeAdjustment == 0)
    }

    @Test func placementGuidesFollowGeometrySettings() {
        let model = NotchViewModel()
        let original = model.centeredGuideFrames(on: Screen(), cellCount: 1)
        model.topAvoidanceAdjustment = 10
        model.ringEdgeAdjustment = 20
        let changed = model.centeredGuideFrames(on: Screen(), cellCount: 1)
        for edge in NotchEdge.allCases {
            let before = original[edge]!
            let after = changed[edge]!
            let difference = edge.isVertical ? after.width - before.width : after.height - before.height
            #expect(abs(difference - (edge == .top ? 30 : 20)) < 0.000001)
        }
    }

    @Test func geometryDragAppliesFinalWindowSizeAfterCoalescing() async throws {
        let controller = NotchWindowController()
        defer { controller.stop() }
        controller.model.edge = .top
        controller.model.sizeScale = 0.75
        controller.model.isExpanded = true
        controller.apply(topAvoidanceAdjustment: 5, ringEdgeAdjustment: 5)
        _ = try #require(controller.panelFrameForTesting)
        for value in 6...20 {
            controller.apply(topAvoidanceAdjustment: CGFloat(value), ringEdgeAdjustment: CGFloat(value))
        }
        #expect(controller.model.topAvoidanceAdjustment == 20)
        #expect(controller.model.ringEdgeAdjustment == 20)
        try await Task.sleep(for: .milliseconds(250))
        let settled = try #require(controller.panelFrameForTesting)
        controller.relocate()
        #expect(controller.panelFrameForTesting == settled)
    }

    @Test func geometryPreviewStaysOpenWhileHeldAndRestoresHoverAfterRelease() async throws {
        let controller = NotchWindowController(mouseLocation: { CGPoint(x: -100_000, y: -100_000) })
        controller.relocate()
        defer { controller.stop() }
        controller.apply(.onHover)
        #expect(!controller.model.isExpanded)
        controller.previewGeometry(editing: true)
        #expect(controller.model.isExpanded)
        try await Task.sleep(for: .milliseconds(1400))
        #expect(controller.model.isExpanded)
        controller.previewGeometry(editing: false)
        #expect(controller.model.isExpanded)
        try await Task.sleep(for: .milliseconds(1400))
        #expect(!controller.model.isExpanded)
        controller.previewGeometry()
        #expect(controller.model.isExpanded)
    }

    @Test func geometryPreviewRespectsHiddenAndAlwaysVisibleModes() async throws {
        let controller = NotchWindowController(mouseLocation: { CGPoint(x: -100_000, y: -100_000) })
        controller.relocate()
        defer { controller.stop() }
        controller.apply(.hidden)
        controller.previewGeometry(editing: true)
        controller.previewGeometry()
        controller.previewGeometry(editing: false)
        #expect(!controller.model.isExpanded)
        controller.apply(.alwaysShow)
        controller.previewGeometry(editing: true)
        controller.previewGeometry(editing: false)
        try await Task.sleep(for: .milliseconds(1400))
        #expect(controller.model.isExpanded)
    }

    @Test func stoppingControllerCancelsPendingGeometryLayout() async throws {
        let controller = NotchWindowController()
        controller.model.edge = .top
        controller.apply(topAvoidanceAdjustment: 5, ringEdgeAdjustment: 5)
        let initial = try #require(controller.panelFrameForTesting)
        controller.apply(topAvoidanceAdjustment: 30, ringEdgeAdjustment: 30)
        controller.stop()
        try await Task.sleep(for: .milliseconds(250))
        #expect(controller.panelFrameForTesting == initial)
    }

    @Test func renderedRingSpacingMovesInwardOnEveryEdge() throws {
        for edge in NotchEdge.allCases {
            let model = NotchViewModel()
            model.edge = edge
            model.sizeScale = 0.75
            model.isExpanded = true
            model.accentColor = .blue
            model.surfaceStyle = .solid
            model.showsMoveHandle = false
            model.showsSettingsHandle = false
            model.snapshots = [ProviderSnapshot(id: "p", displayName: "P", glyph: .claude,
                fidelity: .official, status: .ok,
                windows: [LimitWindow(id: "w", label: "Session", usedFraction: 0.4)], headlineID: "w")]
            var starts: [CGFloat] = []
            for offset: CGFloat in [0, 10, -5] {
                model.ringEdgeAdjustment = offset
                let size = model.panelSize
                let renderer = ImageRenderer(content: NotchRootView(model: model)
                    .frame(width: size.width, height: size.height)
                    .environment(\.colorScheme, .dark))
                renderer.scale = 2
                let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
                var distances: [CGFloat] = []
                for x in 0..<bitmap.pixelsWide {
                    for y in 0..<bitmap.pixelsHigh {
                        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                              color.blueComponent - color.redComponent > 0.3 else { continue }
                        let distance: Int
                        switch edge {
                        case .top: distance = y
                        case .bottom: distance = bitmap.pixelsHigh - 1 - y
                        case .left: distance = x
                        case .right: distance = bitmap.pixelsWide - 1 - x
                        }
                        distances.append(CGFloat(distance) / 2)
                    }
                }
                starts.append(try #require(distances.min()))
            }
            #expect(abs(starts[1] - starts[0] - 10) <= 1)
            #expect(abs(starts[2] - starts[0] + 5) <= 1)
        }
    }

    @Test func paintedDiameterMatchesVisibleRingLayers() throws {
        for placement in [WeeklyRing.off, .inside, .outside] {
            for secondary: Double? in [nil, 1] {
                let renderer = ImageRenderer(content: ProviderRing(usedFraction: 1, glyph: .claude,
                    weeklyFraction: secondary, weeklyRing: placement, innerFraction: 1, expanded: true)
                    .padding(10).background(Color.black).environment(\.colorScheme, .dark))
                renderer.scale = 4
                let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
                var painted: [Int] = []
                for x in 0..<bitmap.pixelsWide {
                    for y in 0..<bitmap.pixelsHigh {
                        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                        let values = [color.redComponent, color.greenComponent, color.blueComponent]
                        if values.max()! - values.min()! > 0.3 { painted.append(x); break }
                    }
                }
                let width = try #require(painted.max()) - #require(painted.min()) + 1
                let hasThirdRing = secondary != nil && placement != .off
                let diameter = NotchLayout.ringDiameter + NotchLayout.independentRingGrowth
                let paintedDiameter = hasThirdRing ? diameter
                    : diameter - 2 * NotchLayout.expandedSecondaryInsideInset + NotchLayout.weeklyRingStroke
                #expect(abs(CGFloat(width) - paintedDiameter * 4) <= 2)
            }
        }
    }

    @Test func refreshPreservesTodayUsageButDoesNotAccumulateOrCrossDays() throws {
        let now = Date()
        let reset = ISO8601DateFormatter().string(from: now.addingTimeInterval(5 * 86_400))
        let store = CodeSwitchDailyUsage()
        func raw(_ used: Double, loading: Bool = false) -> ProviderSnapshot {
            var item = snapshot([quota("weekly", used: used, total: 700, reset: reset)])
            let old = item.linked!.provider
            item.linked = CodeSwitchDetails(platform: "Codex", provider: CodeSwitchProvider(
                providerId: old.providerId, providerName: old.providerName, icon: old.icon,
                activeRequests: 0, status: "enabled", loading: loading, updatedAt: 0, quotas: old.quotas, stats: nil))
            return item
        }
        _ = store.observe([raw(100)], now: now)
        let ready = store.observe([raw(150)], now: now)[0]
        let loading = store.observe([raw(150, loading: true)], now: now)[0]
        #expect(CodeSwitchDailyBudget.reading(for: loading, now: now) == CodeSwitchDailyBudget.reading(for: ready, now: now))
        #expect(store.observe([raw(200, loading: true)], now: now)[0].codeSwitchDailyUsage?.todayUsed == 50)
        #expect(store.observe([raw(200)], now: now)[0].codeSwitchDailyUsage?.todayUsed == 100)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        #expect(store.observe([raw(200, loading: true)], now: tomorrow)[0].codeSwitchDailyUsage == nil)
    }

    @Test func dailyCounterDoesNotRequireADailyLimit() throws {
        let now = Date()
        for unlimited in [true, false] {
            let raw = snapshot([quota("weekly", used: 150, total: 700),
                                quota("daily", used: 50, total: 0, unlimited: unlimited)])
            let budget = try #require(CodeSwitchDailyBudget.reading(for: raw, now: now))
            #expect(budget.todayUsed == 50 && !budget.sinceObservation)
            #expect(abs(budget.usedFraction - 0.3125) < 0.00001)
        }
        for daily in [quota("daily", used: -1), quota("daily", used: .nan),
                      quota("daily", used: 50, unit: "CNY"), quota("daily", used: 50, active: false),
                      quota("daily", used: 50, reset: "2000-01-01T00:00:00Z")] {
            let budget = try #require(CodeSwitchDailyBudget.reading(for: snapshot([weekly, daily]), now: now))
            #expect(budget.todayUsed == 0 && budget.sinceObservation)
        }
    }

    @Test func cachedResetDatesRemainDistinctAndInvalidDatesStayInvalid() {
        let first = quota("weekly", reset: "2026-10-01T00:00:00Z")
        let equivalent = quota("weekly", reset: "2026-10-01T08:00:00+08:00")
        let changed = quota("weekly", reset: "2026-10-02T00:00:00Z")
        for _ in 0..<3 {
            #expect(first.reset == equivalent.reset)
            #expect(first.reset != changed.reset)
            #expect(quota("weekly", reset: "invalid").reset == nil)
        }
    }

    @Test func enlargedRingsShareDiameterAndInnerStrokeIsStrongest() throws {
        for fraction: Double? in [nil, 0.5] {
            let renderer = ImageRenderer(content: ProviderRing(usedFraction: 0.5, glyph: .claude,
                weeklyFraction: 0.5, weeklyRing: .outside, innerFraction: fraction, expanded: true))
            renderer.scale = 2
            let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
            #expect(bitmap.pixelsWide == 108 && bitmap.pixelsHigh == 108)
        }
        #expect(NotchLayout.independentRingStroke > NotchLayout.weeklyRingStroke)
        let radius = (NotchLayout.ringDiameter + NotchLayout.independentRingGrowth) / 2
        let innerOuterEdge = radius - NotchLayout.independentRingInset + NotchLayout.independentRingStroke / 2
        let middleInnerEdge = radius - NotchLayout.expandedSecondaryInsideInset - NotchLayout.weeklyRingStroke / 2
        #expect(innerOuterEdge < middleInnerEdge)
        #expect(radius - NotchLayout.independentRingInset - NotchLayout.independentRingStroke / 2
            > NotchLayout.glyphSize / 2)
    }

    @Test func independentRingsHaveEqualEdgeClearance() {
        let outerInnerEdge = NotchLayout.expandedSecondaryOutsideInset + NotchLayout.weeklyRingStroke / 2
        let middleOuterEdge = NotchLayout.expandedSecondaryInsideInset - NotchLayout.weeklyRingStroke / 2
        let middleInnerEdge = NotchLayout.expandedSecondaryInsideInset + NotchLayout.weeklyRingStroke / 2
        let innerOuterEdge = NotchLayout.independentRingInset - NotchLayout.independentRingStroke / 2
        let outerGap = middleOuterEdge - outerInnerEdge
        let innerGap = innerOuterEdge - middleInnerEdge
        #expect(outerGap > 0)
        #expect(abs(outerGap - innerGap) < 0.000001)
        let ordinaryGap = NotchLayout.weeklyOutsideRadius - NotchLayout.weeklyRingStroke / 2
            - NotchLayout.ringDiameter / 2
        #expect(abs(outerGap - ordinaryGap) < 0.000001)
    }

    @Test func dailyBudgetTooltipRendersAmountAndRemainingProgress() throws {
        let raw = snapshot([weekly, quota("daily", used: 50, total: 100)])
        let budget = try #require(CodeSwitchDailyBudget.reading(for: raw))
        let renderer = ImageRenderer(content: CodeSwitchDailyBudgetRow(budget: budget)
            .frame(width: NotchLayout.cardTextWidth)
            .environment(\.codenotchAccentColor, .blue)
            .background(Color.black))
        renderer.scale = 2
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        #expect(bitmap.pixelsHigh > 60)
        #expect(budget.available > 0 && budget.remainingFraction > 0 && budget.remainingFraction < 1)
        #expect(!budget.amount(budget.available).isEmpty)
    }

    @Test func bridgePublishesObservedUsageAndPreservesSessionIdentity() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("tray-snapshot-v1.json")
        let bridge = CodeSwitchBridge(file: file, dailyUsage: CodeSwitchDailyUsage())
        bridge.setDailyBudgetEnabled(true)
        let now = Date()
        let sessionKey = String(repeating: "a", count: 64)
        let reset = ISO8601DateFormatter().string(from: now.addingTimeInterval(5 * 86_400))
        func publish(_ used: Double, sequence: Int) throws {
            let value: [String: Any] = ["version": 1, "session": "budget-test", "sequence": sequence,
                "heartbeatAt": now.timeIntervalSince1970 * 1000,
                "platforms": [["platform": "codex", "name": "Codex", "icon": "openai", "error": false,
                    "providers": [["providerId": "budget", "providerName": "Budget", "icon": "openai",
                        "activeRequests": 0, "status": "enabled", "loading": false, "updatedAt": 0,
                        "quotas": [["key": "weekly", "used": used, "total": 700,
                            "nextReset": reset, "active": true, "displayKind": "progress"]]]],
                    "sessionBindings": [["sessionKey": sessionKey, "providerId": "budget", "providerName": "Budget",
                        "icon": "openai", "sequence": sequence, "updatedAt": now.timeIntervalSince1970 * 1000]]]]]
            try JSONSerialization.data(withJSONObject: value).write(to: file, options: .atomic)
        }
        try publish(150, sequence: 1)
        await bridge.poll(now: now)
        #expect(bridge.snapshots.first?.codeSwitchDailyUsage?.todayUsed == 0)
        try publish(180, sequence: 2)
        await bridge.poll(now: now)
        #expect(bridge.snapshots.first?.codeSwitchDailyUsage?.todayUsed == 30)
        #expect(bridge.bindings[sessionKey]?.snapshot.codeSwitchDailyUsage?.todayUsed == 30)
        #expect(bridge.bindings[sessionKey]?.snapshot.linked?.provider.status == "session")
        bridge.setDailyBudgetEnabled(false)
        await bridge.poll(now: now)
        #expect(bridge.snapshots.first?.codeSwitchDailyUsage == nil)
        #expect(bridge.snapshots.first?.headline?.usedFraction == 180.0 / 700)
    }

    @Test func claudeIndependentPaceRestoresSessionAndWeekWithoutChangingSnapshot() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let raw = ProviderSnapshot(id: "claude", displayName: "Claude", glyph: .claude,
            fidelity: .official, status: .ok,
            windows: [LimitWindow(id: "session", label: "Session", usedFraction: 0.42),
                      LimitWindow(id: "weekly_all", label: "Week", usedFraction: 0.3,
                                  resetsAt: now.addingTimeInterval(5 * 86_400))],
            headlineID: "session", weeklyID: "weekly_all")
        let paced = DailyPace.apply(to: raw, now: now)
        let cell = ProviderCell(snapshot: paced, weeklyRing: .inside, independentInnerRing: true)
        #expect(cell.displayedMainFraction == 0.42)
        #expect(cell.displayedSecondaryFraction == 0.3)
        #expect(abs(try #require(cell.innerReading).fraction - 0.7) < 0.000001)
        #expect(IndependentQuotaRing.originalQuotas(in: paced) == raw)
        #expect(paced.headlineID == DailyPace.windowID)
        #expect(ProviderCell(snapshot: raw, independentInnerRing: true).innerReading == nil)
    }

    @Test func expandedGeometryKeepsCentersAndCapacityConsistent() {
        for edge in NotchEdge.allCases {
            let model = NotchViewModel()
            model.edge = edge
            model.snapshots = [snapshot([quota("daily"), weekly, monthly])]
            let originalDepth = model.bodyDepth
            let originalCenter = model.ringCenter(index: 0)
            let originalLength = model.bodyLength
            model.independentInnerRing = true
            model.codeSwitchQuotaRatiosEnabled = true
            #expect(model.bodyDepth == originalDepth + NotchLayout.independentRingGrowth)
            #expect(abs(model.bodyLength - originalLength - NotchLayout.independentRingGrowth) < 0.000001)
            #expect(model.ringCenter(index: 0) == originalCenter + NotchLayout.independentRingGrowth / 2)
            #expect(abs(model.ringCenter(index: 1) - model.ringCenter(index: 0) - model.cellPitch) < 0.000001)
            model.codeSwitchQuotaRatiosEnabled = false
            #expect(model.bodyDepth == originalDepth + NotchLayout.independentRingGrowth)
            model.independentInnerRing = false
            #expect(model.bodyDepth == originalDepth)
        }
    }

    @Test func independentRingPreservesProviderPitch() {
        for edge in NotchEdge.allCases {
            let model = NotchViewModel()
            model.edge = edge
            model.snapshots = (0..<11).map { _ in snapshot([weekly, monthly]) }
            let originalPitch = model.cellPitch
            let originalLength = model.bodyLength
            let originalSpacing = model.cellSpacing
            model.independentInnerRing = true
            #expect(abs(model.cellPitch - originalPitch) < 0.000001)
            #expect(abs(model.cellSpacing - originalSpacing + model.ringGrowth) < 0.000001)
            #expect(abs(model.bodyLength - originalLength - model.ringGrowth) < 0.000001)
            #expect(model.cellSpacing > 0)
            model.independentInnerRing = false
            #expect(model.cellSpacing == originalSpacing)
        }
    }

    @Test func missingClaudeSessionKeepsOriginalQuotaDeclarations() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let ids: [(String?, String?)] = [("session", "weekly_all"), ("missing", nil), (nil, nil)]
        for (headline, secondary) in ids {
            let raw = ProviderSnapshot(id: "claude", displayName: "Claude", glyph: .claude,
                fidelity: .official, status: .ok,
                windows: [LimitWindow(id: "weekly_all", label: "Week", usedFraction: 0.3,
                                      resetsAt: now.addingTimeInterval(5 * 86_400))],
                headlineID: headline, weeklyID: secondary)
            let paced = DailyPace.apply(to: raw, now: now)
            #expect(IndependentQuotaRing.originalQuotas(in: paced) == raw)
            #expect(DailyPace.apply(to: paced, now: now) == paced)
            let cell = ProviderCell(snapshot: paced, weeklyRing: .inside, independentInnerRing: true)
            #expect(cell.displayedMainFraction == raw.ringFraction)
            #expect(cell.displayedSecondaryFraction == raw.secondaryWindow?.usedFraction)
            #expect(cell.innerReading != nil)
            if headline == "session" {
                #expect(cell.displayedMainFraction == nil)
                #expect(cell.displayedSecondaryFraction == 0.3)
                var legacy = paced
                legacy.dailyPaceOriginalQuotaIDs = nil
                #expect(IndependentQuotaRing.originalQuotas(in: legacy) == raw)
            }
        }
    }

    @Test func fullTooltipFitsAfterInnerRingAndScaleChanges() {
        for edge in NotchEdge.allCases {
            for scale: CGFloat in [0.75, 1, 1.5] {
                let model = NotchViewModel()
                model.edge = edge
                model.sizeScale = scale
                model.tooltipHeightMode = .full
                model.snapshots = [snapshot([quota("daily"), weekly, monthly])]
                model.codeSwitchQuotaRatiosEnabled = true
                model.adopt(screen: Screen())
                let originalLimit = model.fullTooltipHeightLimit
                model.independentInnerRing = true
                model.adopt(screen: Screen())
                let expectedReduction = edge.isVertical ? 0 : NotchLayout.independentRingGrowth * scale
                #expect(abs(originalLimit - model.fullTooltipHeightLimit - expectedReduction) < 0.000001)
                model.hoveredIndex = 0
                model.recordTooltipHeight(10_000, for: model.snapshots[0], activity: nil)
                let cardHeight = model.tooltipHeight(for: model.snapshots[0])
                if !edge.isVertical {
                    let total = model.notchDrawnDepth + NotchLayout.tailLength + NotchLayout.tailGap + cardHeight
                    #expect(total <= Screen().visibleFrameValue.height - TooltipSizing.screenMargin + 0.000001)
                }
                model.independentInnerRing = false
                model.adopt(screen: Screen())
                #expect(model.fullTooltipHeightLimit == originalLimit)
            }
        }
    }

    @Test func threeQuotaRingsRemainVisibleWhileWorking() throws {
        let renderer = ImageRenderer(content: ProviderRing(usedFraction: 1, glyph: .claude,
            activity: ActivitySummary(state: .working), weeklyFraction: 1,
            weeklyRing: .inside, innerFraction: 1)
            .environment(\.codenotchAccentColor, .blue)
            .background(Color.black))
        renderer.scale = 3
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        let diameter = NotchLayout.ringDiameter + NotchLayout.independentRingGrowth
        #expect(abs(CGFloat(bitmap.pixelsWide) / 3 - diameter) < 1)
        for radius in [diameter / 2 - NotchLayout.weeklyRingStroke / 2,
                       diameter / 2 - NotchLayout.expandedSecondaryInsideInset,
                       diameter / 2 - NotchLayout.independentRingInset] {
            let color = try #require(bitmap.colorAt(x: Int((diameter / 2 + radius) * 3),
                y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB))
            let channels = [color.redComponent, color.greenComponent, color.blueComponent]
            #expect(try #require(channels.max()) - #require(channels.min()) > 0.25)
        }
    }

    @Test func twoQuotaRingsUseInnerAndMiddleLayers() throws {
        for placement: WeeklyRing in [.inside, .outside, .off] {
            for secondary: Double? in [nil, 1] {
                let renderer = ImageRenderer(content: ProviderRing(usedFraction: 1, glyph: .claude,
                    weeklyFraction: secondary, weeklyRing: placement, innerFraction: 1, expanded: true)
                    .environment(\.codenotchAccentColor, .blue)
                    .background(Color.black))
                renderer.scale = 3
                let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
                #expect(bitmap.pixelsWide == 162 && bitmap.pixelsHigh == 162)
                let center = (NotchLayout.ringDiameter + NotchLayout.independentRingGrowth) / 2
                let hasThirdRing = secondary != nil && placement != .off
                for (radius, visible) in [(center - NotchLayout.weeklyRingStroke / 2, hasThirdRing),
                                          (center - NotchLayout.expandedSecondaryInsideInset, true),
                                          (center - NotchLayout.independentRingInset, true)] {
                    let color = try #require(bitmap.colorAt(x: Int((center + radius) * 3),
                        y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB))
                    let channels = [color.redComponent, color.greenComponent, color.blueComponent]
                    let maximum = try #require(channels.max())
                    if visible {
                        #expect(maximum - (try #require(channels.min())) > 0.25)
                    } else {
                        #expect(maximum < 0.05)
                    }
                }
            }
        }
    }

    private func snapshot(_ quotas: [CodeSwitchQuota], platform: String = "codex", cost: Double? = nil) -> ProviderSnapshot {
        let stats = cost.map { CodeSwitchStats(totalRequests: 1, successfulRequests: 1, failedRequests: 0,
            successRate: 1, inputTokens: 0, outputTokens: 0, cacheReadTokens: 0, costTotal: $0,
            avgFirstTokenSec: 0, avgTokensPerSec: 0) }
        let provider = CodeSwitchProvider(providerId: "supplier", providerName: "Supplier", icon: "openai",
            activeRequests: 0, status: "enabled", loading: false, updatedAt: 0, quotas: quotas, stats: stats)
        let raw = provider.snapshot(platform: CodeSwitchPlatform(platform: platform, name: platform,
            icon: "openai", error: false, providers: [provider]))
        return CodeSwitchDailyUsage().observe([raw], now: Date())[0]
    }

    @Test func dailyCostFillsMissingCounterOnFirstObservation() throws {
        let now = Date()
        for key in ["weekly", "monthly"] {
            let raw = snapshot([quota(key)], cost: 25.41)
            let budget = try #require(CodeSwitchDailyBudget.reading(for: raw, now: now))
            #expect(budget.todayUsed == 25.41)
            #expect(!budget.sinceObservation)
            #expect(abs(budget.usedFraction - 25.41 / (25.41 + budget.available)) < 0.000001)
            #expect(abs(budget.remainingFraction + budget.usedFraction - 1) < 0.000001)
        }
        let preferred = snapshot([weekly, quota("daily", used: 50)], cost: 25.41)
        #expect(CodeSwitchDailyBudget.reading(for: preferred, now: now)?.todayUsed == 50)
        let invalidDaily = snapshot([weekly, quota("daily", used: -1)], cost: 25.41)
        #expect(CodeSwitchDailyBudget.reading(for: invalidDaily, now: now)?.todayUsed == 25.41)
    }

    @Test func dailyCostRejectsInvalidValuesAndIncompatibleUnits() throws {
        let now = Date()
        for cost: Double? in [nil, -1, .nan, .infinity] {
            let budget = try #require(CodeSwitchDailyBudget.reading(for: snapshot([weekly], cost: cost), now: now))
            #expect(budget.todayUsed == 0)
            #expect(budget.sinceObservation)
        }
        for source in [quota("weekly", unit: "CNY"), quota("weekly", mode: "count", unit: "USD")] {
            let budget = try #require(CodeSwitchDailyBudget.reading(for: snapshot([source], cost: 25.41), now: now))
            #expect(budget.todayUsed == 0)
            #expect(budget.sinceObservation)
        }
        let zero = try #require(CodeSwitchDailyBudget.reading(for: snapshot([weekly], cost: 0), now: now))
        #expect(zero.todayUsed == 0)
        #expect(!zero.sinceObservation)
        #expect(zero.usedFraction == 0)
    }

    @Test func dailyCostRefreshAndMissingStatsPreserveFallback() throws {
        let now = Date()
        let resetAt = ISO8601DateFormatter().string(from: now.addingTimeInterval(7 * 86_400))
        let store = CodeSwitchDailyUsage()
        _ = store.observe([snapshot([quota("weekly", used: 10, total: 700, reset: resetAt)], cost: 25.41)], now: now)
        let observed = store.observe([snapshot([quota("weekly", used: 30, total: 700, reset: resetAt)], cost: 40)], now: now)[0]
        let budget = try #require(CodeSwitchDailyBudget.reading(for: observed, now: now))
        #expect(budget.todayUsed == 40)
        #expect(!budget.sinceObservation)
        let missing = store.observe([snapshot([quota("weekly", used: 30, total: 700, reset: resetAt)])], now: now)[0]
        let fallback = try #require(CodeSwitchDailyBudget.reading(for: missing, now: now))
        #expect(fallback.todayUsed == 40)
        #expect(fallback.sinceObservation)
        let reset = store.observe([snapshot([quota("weekly", used: 30, total: 700, reset: resetAt)], cost: 0)], now: now)[0]
        #expect(CodeSwitchDailyBudget.reading(for: reset, now: now)?.todayUsed == 0)
        #expect(CodeSwitchDailyBudget.reading(for: reset, now: now)?.sinceObservation == false)
    }

    @Test func dailyCostAnchorSurvivesRestartAndRepeatedStats() throws {
        let now = Date()
        let reset = ISO8601DateFormatter().string(from: now.addingTimeInterval(7 * 86_400))
        let domain = "DailyCostTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        func raw(_ used: Double, cost: Double?) -> ProviderSnapshot {
            snapshot([quota("weekly", used: used, total: 700, reset: reset)], cost: cost)
        }
        let store = CodeSwitchDailyUsage(defaults: defaults)
        _ = store.observe([raw(100, cost: 40)], now: now)
        let restarted = CodeSwitchDailyUsage(defaults: defaults)
        let missing = restarted.observe([raw(110, cost: nil)], now: now)[0]
        #expect(CodeSwitchDailyBudget.reading(for: missing, now: now)?.todayUsed == 50)
        let repeated = restarted.observe([raw(110, cost: 40)], now: now)[0]
        #expect(CodeSwitchDailyBudget.reading(for: repeated, now: now)?.todayUsed == 50)
        #expect(CodeSwitchDailyBudget.reading(for: repeated, now: now)?.sinceObservation == true)
        let updated = restarted.observe([raw(110, cost: 50)], now: now)[0]
        #expect(CodeSwitchDailyBudget.reading(for: updated, now: now)?.todayUsed == 50)
        #expect(CodeSwitchDailyBudget.reading(for: updated, now: now)?.sinceObservation == false)
    }

    @Test func dailyCostExpiresAcrossDaysAndPersistsBlockedValue() throws {
        let now = Date()
        let tomorrow = now.addingTimeInterval(86_400)
        let reset = ISO8601DateFormatter().string(from: now.addingTimeInterval(7 * 86_400))
        let domain = "DailyCostRolloverTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        func raw(_ cost: Double?) -> ProviderSnapshot {
            snapshot([quota("weekly", used: 100, total: 700, reset: reset)], cost: cost)
        }
        let store = CodeSwitchDailyUsage(defaults: defaults)
        let yesterday = store.observe([raw(25.41)], now: now)[0]
        #expect(CodeSwitchDailyBudget.reading(for: yesterday, now: tomorrow) == nil)
        let stale = store.observe([raw(25.41)], now: tomorrow)[0]
        #expect(CodeSwitchDailyBudget.reading(for: stale, now: tomorrow)?.todayUsed == 0)
        #expect(CodeSwitchDailyBudget.reading(for: stale, now: tomorrow)?.sinceObservation == true)
        let restarted = CodeSwitchDailyUsage(defaults: defaults)
        _ = restarted.observe([raw(nil)], now: tomorrow)
        let stillStale = restarted.observe([raw(25.41)], now: tomorrow)[0]
        #expect(CodeSwitchDailyBudget.reading(for: stillStale, now: tomorrow)?.todayUsed == 0)
        let monthly = snapshot([quota("monthly", used: 100, total: 700, reset: reset)], cost: 25.41)
        let changedSource = restarted.observe([monthly], now: tomorrow)[0]
        #expect(CodeSwitchDailyBudget.reading(for: changedSource, now: tomorrow)?.sinceObservation == true)
        #expect(CodeSwitchDailyBudget.reading(for: changedSource, now: tomorrow)?.todayUsed == 0)
        let refreshed = restarted.observe([raw(0)], now: tomorrow)[0]
        #expect(CodeSwitchDailyBudget.reading(for: refreshed, now: tomorrow)?.todayUsed == 0)
        #expect(CodeSwitchDailyBudget.reading(for: refreshed, now: tomorrow)?.sinceObservation == false)
        var changedZone = Calendar.current
        changedZone.timeZone = TimeZone(secondsFromGMT: Calendar.current.timeZone.secondsFromGMT() == 0 ? 3600 : 0)!
        #expect(CodeSwitchDailyBudget.reading(for: refreshed, now: tomorrow, calendar: changedZone) == nil)
        let moved = restarted.observe([raw(0)], now: tomorrow, calendar: changedZone)[0]
        #expect(CodeSwitchDailyBudget.reading(for: moved, now: tomorrow, calendar: changedZone)?.sinceObservation == true)
    }

    @Test func dailyCostLoadingDoesNotReplaceConfirmedUsage() throws {
        let now = Date()
        let store = CodeSwitchDailyUsage()
        let ready = snapshot([weekly], cost: 40)
        _ = store.observe([ready], now: now)
        var loading = snapshot(try #require(ready.linked).provider.quotas, cost: 0)
        let details = try #require(loading.linked)
        let provider = details.provider
        loading.linked = CodeSwitchDetails(platform: details.platform,
            provider: CodeSwitchProvider(providerId: provider.providerId, providerName: provider.providerName,
                icon: provider.icon, activeRequests: 0, status: "enabled", loading: true,
                updatedAt: 0, quotas: provider.quotas, stats: provider.stats))
        let refreshing = store.observe([loading], now: now)[0]
        #expect(CodeSwitchDailyBudget.reading(for: refreshing, now: now)?.todayUsed == 40)
        let tomorrow = now.addingTimeInterval(86_400)
        let expired = store.observe([loading], now: tomorrow)[0]
        #expect(CodeSwitchDailyBudget.reading(for: expired, now: tomorrow) == nil)
    }

    @Test(arguments: ["claude", "codex", "gemini", "custom:工具"])
    func singleWeeklyOrMonthlyAndShorterPeriodWork(platform: String) throws {
        let now = Date()
        for key in ["weekly", "monthly"] {
            let raw = snapshot([quota(key)], platform: platform)
            let budget = try #require(CodeSwitchDailyBudget.reading(for: raw, now: now))
            #expect(budget.source.key == key)
            #expect(budget.todayUsed == 0)
            #expect(budget.available > 0)
            #expect(budget.sinceObservation)
            #expect(CodeSwitchQuotaRings.reading(for: raw, enabled: false) == nil)
        }
        let raw = snapshot([monthly, weekly], platform: platform)
        #expect(CodeSwitchDailyBudget.reading(for: raw, now: now)?.source.key == "weekly")
    }

    @Test func dynamicBudgetUsesFractionalDaysAndOneDayMinimum() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let iso = ISO8601DateFormatter()
        for days in [5.0, 2.5, 0.25] {
            let raw = snapshot([
                quota("weekly", used: 150, total: 700, reset: iso.string(from: now.addingTimeInterval(days * 86_400))),
                quota("daily", used: 50, total: 200, reset: iso.string(from: now.addingTimeInterval(3600)))])
            let budget = try #require(CodeSwitchDailyBudget.reading(for: raw, now: now))
            let available = 550 / max(1, days)
            #expect(abs(budget.available - available) < 0.000001)
            #expect(abs(budget.usedFraction - 50 / (50 + available)) < 0.000001)
            #expect(abs(budget.remainingFraction - available / (50 + available)) < 0.000001)
            #expect(!budget.sinceObservation)
            #expect(budget.amount(110) == "$110")
        }
    }

    @Test func expiredInvalidAndUnlimitedPeriodsFallBackSafely() throws {
        let now = Date()
        let expired = ISO8601DateFormatter().string(from: now.addingTimeInterval(-1))
        for bad in [quota("weekly", reset: expired), quota("weekly", reset: "invalid"),
                    quota("weekly", unlimited: true), quota("weekly", total: 0),
                    quota("weekly", used: .nan), quota("weekly", used: -1),
                    quota("weekly", unit: "%"), quota("weekly", active: false)] {
            let raw = snapshot([bad])
            #expect(CodeSwitchDailyBudget.reading(for: raw, now: now) == nil)
            let fallback = snapshot([bad, monthly])
            #expect(CodeSwitchDailyBudget.reading(for: fallback, now: now)?.source.key == "monthly")
        }
        let empty = snapshot([quota("weekly", used: 20, total: 20)])
        let exhausted = try #require(CodeSwitchDailyBudget.reading(for: empty, now: now))
        #expect(exhausted.available == 0 && exhausted.usedFraction == 1 && exhausted.remainingFraction == 0)
    }

    @Test func observationPersistsWithoutDoubleCountingAndResetsItsBaseline() throws {
        let domain = "DailyUsageTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let now = Date()
        let reset = ISO8601DateFormatter().string(from: now.addingTimeInterval(5 * 86_400))
        func raw(_ used: Double, unit: String = "USD", resetAt: String? = nil) -> ProviderSnapshot {
            snapshot([quota("weekly", used: used, total: 700, unit: unit, reset: resetAt ?? reset)])
        }
        let store = CodeSwitchDailyUsage(defaults: defaults)
        #expect(store.observe([raw(150)], now: now)[0].codeSwitchDailyUsage?.todayUsed == 0)
        #expect(store.observe([raw(180)], now: now)[0].codeSwitchDailyUsage?.todayUsed == 30)
        #expect(store.observe([raw(180)], now: now)[0].codeSwitchDailyUsage?.todayUsed == 30)
        let restarted = CodeSwitchDailyUsage(defaults: defaults)
        let current = restarted.observe([raw(200)], now: now)[0]
        #expect(current.codeSwitchDailyUsage?.todayUsed == 50)
        #expect(CodeSwitchDailyBudget.reading(for: current, now: now)?.todayUsed == 50)
        #expect(restarted.observe([raw(10)], now: now)[0].codeSwitchDailyUsage?.todayUsed == 0)
        #expect(restarted.observe([raw(20)], now: now)[0].codeSwitchDailyUsage?.todayUsed == 10)
        #expect(restarted.observe([raw(30, unit: "CNY")], now: now)[0].codeSwitchDailyUsage?.todayUsed == 0)
        let nextDay = Calendar.current.startOfDay(for: now).addingTimeInterval(86_400 + 60)
        #expect(CodeSwitchDailyBudget.reading(for: current, now: nextDay) == nil)
        #expect(restarted.observe([raw(250)], now: nextDay)[0].codeSwitchDailyUsage?.todayUsed == 0)
        let changedReset = ISO8601DateFormatter().string(from: nextDay.addingTimeInterval(7 * 86_400))
        #expect(restarted.observe([raw(5, resetAt: changedReset)], now: nextDay)[0].codeSwitchDailyUsage?.todayUsed == 0)
    }

    @Test func providerAndUnitBoundariesDoNotMixObservation() throws {
        let now = Date()
        let store = CodeSwitchDailyUsage()
        let first = snapshot([weekly])
        let other = snapshot([weekly], platform: "claude")
        _ = store.observe([first, other], now: now)
        let changed = snapshot([quota("weekly", used: 100, total: 200)])
        let readings = store.observe([changed, other], now: now)
        #expect(readings[0].codeSwitchDailyUsage?.todayUsed == 20)
        #expect(readings[1].codeSwitchDailyUsage?.todayUsed == 0)
        let mismatch = snapshot([weekly, quota("daily", used: 50, unit: "CNY")])
        let budget = try #require(CodeSwitchDailyBudget.reading(for: mismatch, now: now))
        #expect(budget.todayUsed == 0 && budget.sinceObservation)
    }

    @Test func dailyExhaustionStillAlertsIndependentlyOfBudget() throws {
        var alerts: [ThresholdAlert] = []
        var limits: [UsageAlertEvent] = []
        let notifier = ThresholdNotifier(deliver: { alerts.append($0) })
        let watcher = UsageLimitWatcher(deliver: { limits.append($0) })
        let before = snapshot([quota("daily", used: 4, total: 10), weekly, monthly])
        notifier.observe([before])
        watcher.observe([before])
        for enabled in [true, false, true] {
            _ = ProviderCell(snapshot: before, codeSwitchQuotaRatiosEnabled: enabled).quotaRingText
            notifier.observe([before])
            watcher.observe([before])
        }
        #expect(alerts.isEmpty && limits.isEmpty)
        let spent = snapshot([quota("daily", used: 10, total: 10), weekly, monthly])
        let rings = try #require(CodeSwitchQuotaRings.reading(for: spent, enabled: true))
        #expect(rings.main.fraction > 0 && rings.main.fraction < 1)
        #expect(spent.usedFraction == 1)
        notifier.observe([spent])
        watcher.observe([spent])
        notifier.observe([spent])
        watcher.observe([spent])
        #expect(alerts.map(\.threshold) == [80, 100])
        #expect(alerts.allSatisfy { $0.windowLabel == quota("daily").title && $0.usedPercent == 100 })
        #expect(limits.count == 1)
        #expect(limits.first?.currentFraction == 1)
        #expect(limits.first?.providerID == spent.id)
    }

    @Test func sessionRestoredSuppliersUseTheSameDisplayWithoutChangingRouting() throws {
        let raw = snapshot([weekly, monthly])
        let now = Date()
        let key = HookEvent.sessionKey(tool: "codex", id: "ratio-session")
        let session = AgentSession(id: "ratio-session", name: "Session", detail: "Codex", state: .busy,
            waitingFor: nil, since: now, hookSessionKey: key)
        let binding = CodeSwitchSessionBinding(sessionKey: key, providerId: "supplier", providerName: "Supplier",
            icon: "openai", sequence: 1, updatedAt: now.timeIntervalSince1970 * 1000)
        let routing = ActivityRouting(local: [], linked: [], sources: [:], sessions: ["codex": [session]],
            bindings: [key: CodeSwitchSessionLink(platform: "codex", binding: binding, snapshot: raw)], now: now)
        let restored = try #require(routing.snapshots.first)
        #expect(restored == raw)
        #expect(routing.providerID(for: session) == raw.id)
        let cell = ProviderCell(snapshot: restored, weeklyRing: .outside, codeSwitchQuotaRatiosEnabled: true)
        #expect(try #require(cell.quotaRingText).contains(L10n.t("Daily budget")))
    }

    @Test func preferenceIsIndependentAndPersistsOptIn() throws {
        let domain = "CodeSwitchQuotaRingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = Preferences(defaults: defaults)
        #expect(!preferences.independentInnerRing)
        preferences.independentInnerRing = true
        #expect(Preferences(defaults: defaults).independentInnerRing)
        #expect(!preferences.codeSwitchQuotaRatiosEnabled)
        preferences.claudeDailyPaceRing = true
        #expect(!preferences.codeSwitchQuotaRatiosEnabled)
        preferences.codeSwitchQuotaRatiosEnabled = true
        #expect(defaults.bool(forKey: Preferences.codeSwitchQuotaRatiosKey))
        #expect(Preferences(defaults: defaults).codeSwitchQuotaRatiosEnabled)
        preferences.codeSwitchQuotaRatiosEnabled = false
        #expect(!Preferences(defaults: defaults).codeSwitchQuotaRatiosEnabled)
        #expect(preferences.claudeDailyPaceRing)
    }

    @Test(arguments: ["five_hour", "daily", "weekly", "monthly", "total"])
    func everyRealQuotaAlertsIndependentlyOfTheHeadline(target: String) {
        var alerts: [ThresholdAlert] = []
        var limits: [UsageAlertEvent] = []
        let notifier = ThresholdNotifier(deliver: { alerts.append($0) })
        let watcher = UsageLimitWatcher(deliver: { limits.append($0) })
        let keys = ["five_hour", "daily", "weekly", "monthly", "total"]
        let before = snapshot(keys.map { quota($0, used: 4, total: 10) })
        notifier.observe([before]); watcher.observe([before])
        let spent = snapshot(keys.map { quota($0, used: $0 == target ? 10 : 4, total: 10) })
        notifier.observe([spent]); watcher.observe([spent])
        #expect(alerts.map(\.threshold) == [80, 100])
        #expect(alerts.allSatisfy { $0.windowID == target && $0.usedPercent == 100 })
        #expect(limits.count == 1)
        #expect(limits.first?.windowID == target)
        #expect(limits.first?.kind == (target == "weekly" ? .weeklyLimitReached : .sessionLimitReached))
        #expect(limits.first?.providerID == spent.id)
    }

    @Test func monthlyExhaustionWithOnlyWeeklyAndMonthlyStillAlerts() {
        var alerts: [ThresholdAlert] = []
        var limits: [UsageAlertEvent] = []
        let notifier = ThresholdNotifier(deliver: { alerts.append($0) })
        let watcher = UsageLimitWatcher(deliver: { limits.append($0) })
        let before = snapshot([weekly, quota("monthly", used: 700, total: 1000)])
        notifier.observe([before]); watcher.observe([before])
        let spent = snapshot([weekly, quota("monthly", used: 1000, total: 1000)])
        notifier.observe([spent]); watcher.observe([spent])
        #expect(alerts.map(\.windowID) == ["monthly", "monthly"])
        #expect(limits.map(\.windowID) == ["monthly"])
        #expect(CodeSwitchQuotaRings.reading(for: spent, enabled: true)?.main.fraction == 0)
    }

    @Test func simultaneousPeriodsDoNotMaskEachOtherOrReplayAfterReordering() {
        var alerts: [ThresholdAlert] = []
        var limits: [UsageAlertEvent] = []
        let notifier = ThresholdNotifier(deliver: { alerts.append($0) })
        let watcher = UsageLimitWatcher(deliver: { limits.append($0) })
        let keys = ["daily", "weekly", "monthly"]
        let before = snapshot(keys.map { quota($0, used: 4, total: 10) })
        notifier.observe([before]); watcher.observe([before])
        let spent = snapshot(keys.map { quota($0, used: 10, total: 10) })
        notifier.observe([spent]); watcher.observe([spent])
        #expect(alerts.count == 6)
        #expect(limits.map(\.windowID) == keys.map(Optional.some))
        let missing = snapshot([quota("daily", used: .nan), quota("weekly", used: 10, total: 10)])
        notifier.observe([missing]); watcher.observe([missing])
        let reordered = snapshot(keys.reversed().map { quota($0, used: 10, total: 10) })
        notifier.observe([reordered]); watcher.observe([reordered])
        #expect(alerts.count == 6)
        #expect(limits.count == 3)
    }

    @Test func linkedMuteAndRecoveryRememberEachPeriod() {
        var muted = false
        var alerts: [ThresholdAlert] = []
        var limits: [UsageAlertEvent] = []
        let notifier = ThresholdNotifier(isMuted: { _ in muted }, deliver: { alerts.append($0) })
        let watcher = UsageLimitWatcher(isMuted: { _ in muted }, deliver: { limits.append($0) })
        let before = snapshot([weekly, quota("monthly", used: 4, total: 10)])
        let spent = snapshot([weekly, quota("monthly", used: 10, total: 10)])
        notifier.observe([before]); watcher.observe([before])
        muted = true
        notifier.observe([spent]); watcher.observe([spent])
        muted = false
        notifier.observe([spent]); watcher.observe([spent])
        #expect(alerts.isEmpty && limits.isEmpty)
        notifier.observe([before]); watcher.observe([before])
        notifier.observe([spent]); watcher.observe([spent])
        #expect(alerts.map(\.threshold) == [80, 100])
        #expect(limits.map(\.windowID) == ["monthly"])
    }

    @Test func linkedCycleRolloverRearmsOnlyThatPeriod() {
        var alerts: [ThresholdAlert] = []
        var limits: [UsageAlertEvent] = []
        let notifier = ThresholdNotifier(deliver: { alerts.append($0) })
        let watcher = UsageLimitWatcher(deliver: { limits.append($0) })
        let before = snapshot([weekly, quota("monthly", used: 4, total: 10, reset: "2026-10-01T00:00:00Z")])
        let spent = snapshot([weekly, quota("monthly", used: 10, total: 10, reset: "2026-10-01T00:00:00Z")])
        let next = snapshot([weekly, quota("monthly", used: 10, total: 10, reset: "2026-11-01T00:00:00Z")])
        for raw in [before, spent, next, next] {
            notifier.observe([raw]); watcher.observe([raw])
        }
        #expect(alerts.map(\.threshold) == [80, 100, 80, 100])
        #expect(limits.map(\.windowID) == ["monthly", "monthly"])
    }

    @Test func linkedSuppliersHaveSeparateQuotaBaselines() {
        var limits: [UsageAlertEvent] = []
        let watcher = UsageLimitWatcher(deliver: { limits.append($0) })
        let low = [quota("daily", used: 4, total: 10), weekly]
        let high = [quota("daily", used: 10, total: 10), weekly]
        let codex = snapshot(high, platform: "codex")
        let claude = snapshot(high, platform: "claude")
        watcher.observe([snapshot(low, platform: "codex"), snapshot(low, platform: "claude")])
        watcher.observe([codex, snapshot(low, platform: "claude")])
        watcher.observe([codex, claude])
        #expect(limits.map(\.providerID) == [codex.id, claude.id])
        var baseline: [UsageAlertEvent] = []
        let first = UsageLimitWatcher(deliver: { baseline.append($0) })
        first.observe([codex, claude])
        #expect(baseline.isEmpty)
    }

    @Test func malformedRatiosRemainSafeThroughFallbackAndAccessibility() {
        for used in [1e20, .greatestFiniteMagnitude, .infinity, .nan, -1] {
            let raw = snapshot([quota("weekly", used: used, total: 1), monthly])
            #expect(raw.windows.map(\.id) == ["monthly"])
            #expect(CodeSwitchDailyBudget.reading(for: raw)?.source.key == "monthly")
            for enabled in [false, true] {
                let cell = ProviderCell(snapshot: raw, weeklyRing: .outside, codeSwitchQuotaRatiosEnabled: enabled)
                #expect(!cell.accessibilityText.isEmpty)
                _ = cell.body
            }
            #expect(Percent.text(for: used) == "—")
            let halves = Percent.halves(for: used)
            #expect(halves.used == "—" && halves.left == "—")
        }
        #expect(Percent.text(for: 0.003) == "0.3")
        #expect(Percent.text(for: 1.04) == "104")
        #expect(Percent.halves(for: 1.04).left == "0")
    }

    @Test func nativeExtraWindowsStillDoNotTriggerQuotaAlerts() {
        var alerts: [ThresholdAlert] = []
        var limits: [UsageAlertEvent] = []
        let notifier = ThresholdNotifier(deliver: { alerts.append($0) })
        let watcher = UsageLimitWatcher(deliver: { limits.append($0) })
        var raw = ProviderSnapshot(id: "codex", displayName: "Codex", glyph: .openai,
            fidelity: .official, status: .ok, windows: [
                LimitWindow(id: "primary", label: "Session", usedFraction: 0.5),
                LimitWindow(id: "spark", label: "Spark", usedFraction: 0.5)
            ], headlineID: "primary")
        notifier.observe([raw]); watcher.observe([raw])
        raw.windows[1] = LimitWindow(id: "spark", label: "Spark", usedFraction: 1)
        notifier.observe([raw]); watcher.observe([raw])
        #expect(alerts.isEmpty && limits.isEmpty)
        raw.windows[0] = LimitWindow(id: "primary", label: "Session", usedFraction: 1)
        notifier.observe([raw]); watcher.observe([raw])
        #expect(alerts.map(\.threshold) == [80, 100])
        #expect(limits.count == 1)
        raw.windows[0] = LimitWindow(id: "primary", label: "Session", usedFraction: 1e20)
        notifier.observe([raw])
        #expect(alerts.count == 2)
    }
}
