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
            nextReset: reset, active: active, valueMode: mode, unit: unit, extra: nil,
            invalidMessage: invalid, displayKind: kind)
    }

    private var weekly: CodeSwitchQuota { quota("weekly", used: 80, total: 200) }
    private var monthly: CodeSwitchQuota { quota("monthly", used: 200, total: 2000) }

    @Test func independentRingKeepsActualQuotasAndPrefersDailyRatio() throws {
        let raw = snapshot([quota("daily"), weekly, monthly])
        for placement in [WeeklyRing.off, .inside, .outside] {
            let cell = ProviderCell(snapshot: raw, activity: ActivitySummary(state: .working),
                weeklyRing: placement, codeSwitchQuotaRatiosEnabled: true, independentInnerRing: true)
            #expect(cell.displayedMainFraction == raw.ringFraction)
            #expect(cell.displayedSecondaryFraction == raw.secondaryWindow?.usedFraction)
            #expect(cell.innerReading?.fraction == 0.05)
            let text = try #require(cell.quotaRingText)
            #expect(text.contains(L10n.t("Daily used / Weekly limit")))
            #expect(!text.contains(L10n.t("Weekly used / Monthly limit")))
            #expect(text.contains(L10n.t("Secondary quota ring")) == (placement != .off))
            #expect(cell.accessibilityText.contains(", 5%"))
        }
        let legacy = ProviderCell(snapshot: raw, codeSwitchQuotaRatiosEnabled: true)
        #expect(legacy.innerReading == nil)
        #expect(legacy.displayedMainFraction == 0.05)
        let weeklyOnly = ProviderCell(snapshot: snapshot([weekly, monthly]),
            codeSwitchQuotaRatiosEnabled: true, independentInnerRing: true)
        #expect(weeklyOnly.innerReading?.fraction == 0.04)
    }

    @Test func unavailableInnerRingFallsBackWithoutEnlarging() {
        for raw in [snapshot([weekly]), snapshot([quota("daily", unit: "CNY"), weekly])] {
            let cell = ProviderCell(snapshot: raw, codeSwitchQuotaRatiosEnabled: true, independentInnerRing: true)
            #expect(cell.innerReading == nil)
            #expect(cell.displayedMainFraction == raw.ringFraction)
            let model = NotchViewModel()
            model.snapshots = [raw]
            model.independentInnerRing = true
            model.codeSwitchQuotaRatiosEnabled = true
            #expect(model.ringGrowth == 0)
        }
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
        for radius in [diameter / 2 - NotchLayout.trackStroke / 2,
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
        return provider.snapshot(platform: CodeSwitchPlatform(platform: platform, name: platform,
            icon: "openai", error: false, providers: [provider]))
    }

    @Test(arguments: ["claude", "codex", "gemini", "custom:工具"])
    func threePeriodsUseActualAmountsAcrossPlatforms(platform: String) throws {
        let raw = snapshot([monthly, quota("five_hour"), weekly, quota("daily")], platform: platform)
        let before = raw
        let rings = try #require(CodeSwitchQuotaRings.reading(for: raw, enabled: true))
        #expect(rings.main.fraction == 0.05)
        #expect(rings.secondary.fraction == 0.04)
        #expect(rings.main.label == L10n.t("Daily used / Weekly limit"))
        #expect(rings.secondary.label == L10n.t("Weekly used / Monthly limit"))
        #expect(raw == before)
        #expect(raw.headline?.id == "monthly")
        #expect(raw.windows.count == 4)
    }

    @Test func twoPeriodsKeepTheLongerPeriodsActualRate() throws {
        let daily = try #require(CodeSwitchQuotaRings.reading(
            for: snapshot([quota("daily"), weekly]), enabled: true))
        #expect(daily.main.fraction == 0.05)
        #expect(daily.secondary.fraction == 0.4)
        #expect(daily.secondary.label == weekly.title)
        let week = try #require(CodeSwitchQuotaRings.reading(for: snapshot([weekly, monthly]), enabled: true))
        #expect(week.main.fraction == 0.04)
        #expect(week.secondary.fraction == 0.1)
        #expect(week.secondary.label == monthly.title)
    }

    @Test func disabledNativeAndMissingAdjacentPeriodsKeepOriginalDisplay() {
        let raw = snapshot([quota("daily"), weekly, monthly])
        #expect(CodeSwitchQuotaRings.reading(for: raw, enabled: false) == nil)
        var native = raw
        native.linked = nil
        #expect(CodeSwitchQuotaRings.reading(for: native, enabled: true) == nil)
        for quotas in [[], [weekly], [quota("daily"), monthly], [quota("five_hour"), weekly]] {
            #expect(CodeSwitchQuotaRings.reading(for: snapshot(quotas), enabled: true) == nil)
        }
    }

    @Test func invalidWeeklyAmountsNeverProduceRatios() {
        let invalid = [
            quota("weekly", total: 0), quota("weekly", total: -1),
            quota("weekly", total: .infinity), quota("weekly", total: .nan),
            quota("weekly", used: -1), quota("weekly", used: .infinity), quota("weekly", used: .nan),
            quota("weekly", active: false), quota("weekly", unlimited: true),
            quota("weekly", kind: "balance"), quota("weekly", invalid: "Unavailable"),
            quota("weekly", used: .greatestFiniteMagnitude, total: .leastNonzeroMagnitude)
        ]
        for week in invalid {
            #expect(CodeSwitchQuotaRings.reading(for: snapshot([quota("daily"), week, monthly]), enabled: true) == nil)
        }
        #expect(CodeSwitchQuotaRings.reading(
            for: snapshot([quota("daily"), weekly, weekly, monthly]), enabled: true) == nil)
    }

    @Test func invalidOptionalPeriodsFallBackToTheUsablePair() throws {
        let noMonth = try #require(CodeSwitchQuotaRings.reading(for: snapshot([
            quota("daily"), weekly, quota("monthly", unlimited: true)
        ]), enabled: true))
        #expect(noMonth.main.fraction == 0.05)
        #expect(noMonth.secondary.fraction == 0.4)
        let noDay = try #require(CodeSwitchQuotaRings.reading(for: snapshot([
            quota("daily", active: false), weekly, monthly
        ]), enabled: true))
        #expect(noDay.main.fraction == 0.04)
        #expect(noDay.secondary.fraction == 0.1)
    }

    @Test func unitsAndValueModesMustBeComparable() throws {
        let mismatches: [(CodeSwitchQuota, CodeSwitchQuota)] = [
            (quota("daily", unit: "USD"), quota("weekly", unit: "CNY")),
            (quota("daily", mode: "count"), weekly),
            (quota("daily", mode: "count", unit: "tokens"), quota("weekly", mode: "count", unit: "requests")),
            (quota("daily", mode: "count", unit: "%"), quota("weekly", mode: "count", unit: "%")),
            (quota("daily", mode: "unknown"), quota("weekly", mode: "unknown"))
        ]
        for (day, week) in mismatches {
            #expect(CodeSwitchQuotaRings.reading(for: snapshot([day, week]), enabled: true) == nil)
        }
        let money = try #require(CodeSwitchQuotaRings.reading(for: snapshot([
            quota("daily", mode: nil), quota("weekly", used: 80, total: 200, unit: " usd ")
        ]), enabled: true))
        #expect(money.main.fraction == 0.05)
        let counts = try #require(CodeSwitchQuotaRings.reading(for: snapshot([
            quota("daily", mode: "count", unit: "tokens"),
            quota("weekly", used: 80, total: 200, mode: "count", unit: "tokens")
        ]), enabled: true))
        #expect(counts.main.fraction == 0.05)
        let mixedMonth = try #require(CodeSwitchQuotaRings.reading(for: snapshot([
            quota("daily"), weekly, quota("monthly", unit: "CNY")
        ]), enabled: true))
        #expect(mixedMonth.secondary.fraction == 0.4)
    }

    @Test func zeroAndOverBudgetValuesRemainMeasured() throws {
        for used in [0.0, 400.0] {
            let rings = try #require(CodeSwitchQuotaRings.reading(
                for: snapshot([quota("daily", used: used), weekly]), enabled: true))
            #expect(rings.main.fraction == used / 200)
        }
        let overflow = snapshot([
            quota("daily", used: .greatestFiniteMagnitude, total: .greatestFiniteMagnitude),
            quota("weekly", used: 0, total: .leastNonzeroMagnitude)
        ])
        #expect(CodeSwitchQuotaRings.reading(for: overflow, enabled: true) == nil)
        let oversizedPercentage = snapshot([
            quota("daily", used: 1e20, total: 1e20), quota("weekly", used: 0, total: 1)
        ])
        #expect(CodeSwitchQuotaRings.reading(for: oversizedPercentage, enabled: true) == nil)
    }

    @Test func descriptionsFollowVisibleRingsWithoutInventingRemainingBudget() throws {
        let raw = snapshot([quota("daily"), weekly, monthly])
        let rings = try #require(CodeSwitchQuotaRings.reading(for: raw, enabled: true))
        for placement in [WeeklyRing.off, .inside, .outside] {
            let cell = ProviderCell(snapshot: raw, weeklyRing: placement, codeSwitchQuotaRatiosEnabled: true)
            let text = try #require(cell.quotaRingText)
            #expect(text.contains(rings.main.summary))
            #expect(text.contains(rings.secondary.summary) == (placement != .off))
            #expect(!text.contains("95%"))
            #expect(cell.accessibilityText.contains(text))
        }
        let working = ProviderCell(snapshot: raw, activity: ActivitySummary(state: .working),
            weeklyRing: .inside, codeSwitchQuotaRatiosEnabled: true)
        #expect(try #require(working.quotaRingText).contains(rings.main.summary))
        #expect(working.quotaRingText?.contains(rings.secondary.summary) == false)
        #expect(ProviderCell(snapshot: raw, weeklyRing: .off).quotaRingText == nil)
    }

    @Test func dailyExhaustionStillAlertsWhenTheDisplayReadsFivePercent() throws {
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
        #expect(rings.main.fraction == 0.05)
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
        #expect(try #require(cell.quotaRingText).contains(L10n.t("Weekly used / Monthly limit")))
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
        #expect(CodeSwitchQuotaRings.reading(for: spent, enabled: true)?.main.fraction == 0.08)
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
            #expect(CodeSwitchQuotaRings.reading(for: raw, enabled: true) == nil)
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
