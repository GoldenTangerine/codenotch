/**
 @name: 额度单元测试
 @Descripttion: 验证剩余模式与耗尽双环的显示。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-10-15 16:20:00
 @LastEditTime: 2026-10-15 16:20:00
 @FilePath: Tests/ProviderCellTests.swift
 */
import XCTest
@testable import Codenotch

/// The figure under the ring reads grey only when a window is actually
/// spent — the 5-hour or the weekly — and only in remaining mode. Grey means
/// "nothing usable", and neither staleness, nor a missing reading, nor an
/// unmeasured speed says that.
final class ProviderCellTests: XCTestCase {
    private let spentWeek = [
        LimitWindow(id: "session", label: "Session", usedFraction: 0.5),
        LimitWindow(id: "weekly_all", label: "Weekly", usedFraction: 1.0),
    ]
    private let spentSession = [
        LimitWindow(id: "session", label: "Session", usedFraction: 1.0),
        LimitWindow(id: "weekly_all", label: "Weekly", usedFraction: 0.3),
    ]

    private func snapshot(status: ProviderStatus = .ok,
                          windows: [LimitWindow]? = nil,
                          weeklyID: String? = nil) -> ProviderSnapshot {
        ProviderSnapshot(id: "claude", displayName: "Claude", glyph: .claude,
                         fidelity: .official, status: status,
                         windows: windows ?? [LimitWindow(id: "session", label: "Session", usedFraction: 0.5)],
                         headlineID: "session", weeklyID: weeklyID)
    }

    func testFreshReadingIsWhite() {
        XCTAssertFalse(ProviderReading(snapshot: snapshot()).isDimmed)
    }

    func testStaleReadingWithRoomStaysWhite() {
        // Staleness no longer dims the figure: a grey 27% beside full quota
        // reads as "spent", and the reading is merely old.
        let stale = snapshot(status: .stale(since: Date()), windows: [
            LimitWindow(id: "session", label: "Session", usedFraction: 0.5),
        ])
        XCTAssertFalse(ProviderReading(snapshot: stale, showsRemaining: true).isDimmed)
    }

    func testNoReadingStaysWhite() {
        XCTAssertFalse(ProviderReading(snapshot: snapshot(windows: []), showsRemaining: true).isDimmed)
    }

    func testLocalSpeedWithNothingMeasuredStaysWhite() {
        var local = snapshot(windows: [])
        local.showsLocalPerformance = true
        local.localPerformance = nil
        XCTAssertFalse(ProviderReading(snapshot: local, showsRemaining: true).isDimmed)
    }

    func testWeekShutCellIsGreyEvenWithHeadlineRoom() {
        // Freshly confirmed room on the 5-hour beside a spent week: the room
        // is unusable, so in remaining mode the figure reads grey. Judged off
        // the fractions, not the block the store attached.
        let shut = snapshot(windows: spentWeek, weeklyID: "weekly_all")
        let reading = ProviderReading(snapshot: shut, showsRemaining: true)
        XCTAssertTrue(reading.isDimmed)
    }

    func testHeadlineSpentCellIsGreyInRemainingMode() {
        // The other half of the rule: a spent 5-hour with a healthy week —
        // Codex at 0% left — greys the figure too.
        let shut = snapshot(windows: spentSession, weeklyID: "weekly_all")
        let reading = ProviderReading(snapshot: shut, showsRemaining: true)
        XCTAssertTrue(reading.isDimmed)
    }

    func testSpentWindowsKeepColoursInUsedMode() {
        // The grey is a remaining-mode reading. Where the figure says what
        // was spent, spent windows are 100% like anything else spent — red,
        // not grey — so the figure stays white even with both spent.
        let shut = snapshot(windows: [
            LimitWindow(id: "session", label: "Session", usedFraction: 1.0),
            LimitWindow(id: "weekly_all", label: "Weekly", usedFraction: 1.0),
        ], weeklyID: "weekly_all")
        let reading = ProviderReading(snapshot: shut)
        XCTAssertFalse(reading.isDimmed)
    }

    func testProviderPauseKeepsItsColours() {
        // A pause the provider reported itself — rate limited, not week-shut —
        // keeps the red ring and the white figure.
        var paused = snapshot()
        paused.block = UsageBlock(reason: "Rate limited", resetsAt: nil)
        let cell = ProviderCell(snapshot: paused)
        XCTAssertFalse(cell.isWeeklyExhausted)
        XCTAssertFalse(ProviderReading(snapshot: paused).isDimmed)
    }

    func testShutRingsNeedTheSettingAndASpentWindow() {
        // 本地默认关闭：未开启时任何耗尽都保持各自的颜色。
        XCTAssertFalse(ProviderRing(usedFraction: 1.0, glyph: .claude, weeklyExhausted: true).showsShutRings)
        // A spent week shuts once the setting is on.
        let weekShut = ProviderRing(usedFraction: 0.3, glyph: .claude, weeklyExhausted: true,
                                    shutRingsWhenSpent: true)
        XCTAssertTrue(weekShut.showsShutRings)
        // A spent 5-hour with no block: the headline fraction alone shuts.
        let sessionShut = ProviderRing(usedFraction: 1.0, glyph: .claude, shutRingsWhenSpent: true)
        XCTAssertTrue(sessionShut.showsShutRings)
        // The setting off keeps every ring its own colour, however spent.
        let off = ProviderRing(usedFraction: 1.0, glyph: .claude,
                               weeklyExhausted: true, shutRingsWhenSpent: false)
        XCTAssertFalse(off.showsShutRings)
        // Nothing spent, nothing shut.
        let healthy = ProviderRing(usedFraction: 0.3, glyph: .claude, shutRingsWhenSpent: true)
        XCTAssertFalse(healthy.showsShutRings)
    }
}
