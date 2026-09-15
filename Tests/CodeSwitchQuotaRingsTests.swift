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
            #expect(model.cellRingDiameter == 64)
            model.codeSwitchQuotaRatiosEnabled = true
            #expect(model.cellRingDiameter == 64)
            model.independentInnerRing = false
            #expect(model.ringGrowth == 0)
        }
    }

    @Test func outsideSecondaryKeepsTheSamePaintedDiameter() throws {
        var widths: [Int] = []
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
                widths.append(try #require(painted.max()) - #require(painted.min()) + 1)
            }
        }
        #expect(try #require(widths.max()) - #require(widths.min()) <= 2)
        #expect(widths.allSatisfy { abs($0 - 256) <= 2 })
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
            #expect(bitmap.pixelsWide == 128 && bitmap.pixelsHigh == 128)
        }
        #expect(NotchLayout.independentRingStroke > NotchLayout.weeklyRingStroke)
        let innerOuterEdge = 32 - NotchLayout.independentRingInset + NotchLayout.independentRingStroke / 2
        let middleInnerEdge = 32 - NotchLayout.expandedSecondaryInsideInset - NotchLayout.weeklyRingStroke / 2
        #expect(innerOuterEdge < middleInnerEdge)
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

    private func snapshot(_ quotas: [CodeSwitchQuota], platform: String = "codex") -> ProviderSnapshot {
        let provider = CodeSwitchProvider(providerId: "supplier", providerName: "Supplier", icon: "openai",
            activeRequests: 0, status: "enabled", loading: false, updatedAt: 0, quotas: quotas, stats: nil)
        let raw = provider.snapshot(platform: CodeSwitchPlatform(platform: platform, name: platform,
            icon: "openai", error: false, providers: [provider]))
        return CodeSwitchDailyUsage().observe([raw], now: Date())[0]
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
