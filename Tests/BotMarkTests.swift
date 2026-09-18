/**
 @name: 动态机器人回归测试
 @Descripttion: 验证外观持久化、动作资源与动画暂停恢复。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-18 10:24:07
 @LastEditTime: 2026-09-18 10:24:07
 @FilePath: Tests/BotMarkTests.swift
 */
import AppKit
import XCTest
@testable import Codenotch

@MainActor
final class BotMarkTests: XCTestCase {
    private final class VisibleWindow: NSWindow {
        override var isVisible: Bool { true }
        override var occlusionState: NSWindow.OcclusionState { [.visible] }
    }

    private final class FlippedDocument: NSView {
        override var isFlipped: Bool { true }
    }

    func testScrollAndAncestorVisibilityRestartTheClockWithoutReconfiguration() throws {
        _ = try XCTUnwrap(BotMarkLibrary.available)
        let window = VisibleWindow(contentRect: NSRect(x: 0, y: 0, width: 160, height: 160),
                                   styleMask: .borderless, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 160, height: 160))
        let document = FlippedDocument(frame: NSRect(x: 0, y: 0, width: 160, height: 640))
        scroll.documentView = document
        window.contentView = scroll
        let view = BotDrawingView(frame: NSRect(x: 10, y: 10, width: 50, height: 50))
        view.configure(BotPresentation(id: "test", brand: "claude", appearance: BotAppearance()), reduceMotion: false)
        document.addSubview(view)
        window.contentView?.layoutSubtreeIfNeeded()
        let clock = BotWindowClock.attach(view, to: window)
        XCTAssertTrue(clock.isRunning)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 300))
        scroll.reflectScrolledClipView(scroll.contentView)
        XCTAssertFalse(view.canAnimate)
        XCTAssertFalse(clock.isRunning)
        let frames = view.renderedFrames
        view.advance(to: 10, date: Date(), pointerInWindow: .zero)
        XCTAssertEqual(view.renderedFrames, frames)
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
        XCTAssertTrue(clock.isRunning)
        view.isHidden = true
        XCTAssertFalse(clock.isRunning)
        view.isHidden = false
        XCTAssertTrue(clock.isRunning)
        document.isHidden = true
        XCTAssertFalse(clock.isRunning)
        document.isHidden = false
        XCTAssertTrue(clock.isRunning)
        view.detach()
        XCTAssertFalse(clock.isRunning)
    }

    func testQuietUsesSharedActivityInsteadOfViewLifetime() {
        let now = Date()
        var presentation = BotPresentation(id: "test", brand: "claude", appearance: BotAppearance())
        XCTAssertFalse(presentation.isQuiet(at: now))
        presentation.lastActivity = now.addingTimeInterval(-1201)
        XCTAssertTrue(presentation.isQuiet(at: now))
        presentation.globallyBusy = true
        XCTAssertFalse(presentation.isQuiet(at: now))
        presentation.globallyBusy = false
        presentation.lastActivity = now.addingTimeInterval(-10)
        XCTAssertFalse(presentation.isQuiet(at: now))
    }

    func testDailyPaceDoesNotExhaustRealQuota() throws {
        _ = try XCTUnwrap(BotMarkLibrary.available)
        let now = Date()
        var snapshot = ProviderSnapshot(id: "claude", displayName: "Claude", glyph: .claude,
            fidelity: .official, status: .ok,
            windows: [LimitWindow(id: "session", label: "Session", usedFraction: 0.1),
                      LimitWindow(id: "weekly_all", label: "Week", usedFraction: 0.2,
                                  resetsAt: now.addingTimeInterval(7 * 86400))],
            headlineID: "session")
        let model = NotchViewModel()
        var appearance = BotAppearance()
        appearance.enabled = true
        model.botAppearances["claude"] = appearance
        let paced = DailyPace.apply(to: snapshot, now: now)
        XCTAssertGreaterThan(try XCTUnwrap(paced.usedFraction), 1)
        XCTAssertEqual(model.botPresentation(for: paced)?.mood, .idle)
        snapshot.windows[0] = LimitWindow(id: "session", label: "Session", usedFraction: 1)
        XCTAssertEqual(model.botPresentation(for: DailyPace.apply(to: snapshot, now: now))?.mood, .spent)
    }

    func testAppearanceDefaultsAndUnknownFieldsFallBack() throws {
        let empty = try JSONDecoder().decode(BotAppearance.self, from: Data("{}".utf8))
        XCTAssertFalse(empty.enabled)
        XCTAssertEqual(empty.shape, "blob")
        let future = try JSONDecoder().decode(BotAppearance.self, from: Data(
            #"{"enabled":true,"personality":"future","shape":"future","rgb":4294967295}"#.utf8))
        XCTAssertTrue(future.enabled)
        XCTAssertNil(future.personality)
        XCTAssertNil(future.rgb)
        XCTAssertEqual(future.shape, "blob")
    }

    func testLocalSettingsSurviveRestartAndKeepPlatformsSeparate() throws {
        let domain = "BotMarkTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = Preferences(defaults: defaults)
        var appearance = BotAppearance()
        appearance.enabled = true
        appearance.personality = "playful"
        appearance.shape = "cloud"
        appearance.rgb = 0x123456
        preferences.setBotAppearance(appearance, for: "code-switch:6:claude:shared")
        let restarted = Preferences(defaults: defaults)
        XCTAssertEqual(restarted.botAppearance(for: "code-switch:6:claude:shared"), appearance)
        XCTAssertFalse(restarted.botAppearance(for: "code-switch:5:codex:shared").enabled)
        var draft = appearance
        draft.enabled = false
        XCTAssertTrue(restarted.botAppearance(for: "code-switch:6:claude:shared").enabled)
        restarted.setBotAppearance(draft, for: "code-switch:6:claude:shared")
        XCTAssertEqual(restarted.botAppearance(for: "code-switch:6:claude:shared").rgb, 0x123456)
        XCTAssertEqual(restarted.botAppearance(for: "code-switch:6:claude:shared").shape, "cloud")
    }

    func testAutomaticAppearanceIsIndependentOfOrder() {
        let appearance = BotAppearance()
        let ids = ["one", "two", "code-switch:6:claude:third"]
        let before = Dictionary(uniqueKeysWithValues: ids.map { ($0, appearance.persona(for: $0)) })
        for id in ids.reversed() { XCTAssertEqual(appearance.persona(for: id), before[id]) }
        XCTAssertEqual(BotAppearance.stableIndex("one", count: 8), 7)
    }

    func testPresentationInheritsSourceChoiceAndSurvivesSnapshotReplacement() throws {
        _ = try XCTUnwrap(BotMarkLibrary.available)
        let model = NotchViewModel()
        var snapshot = try XCTUnwrap(Fixtures.snapshots().first)
        snapshot.sourceProviderID = "local-source"
        XCTAssertNil(model.botPresentation(for: snapshot))
        var appearance = BotAppearance()
        appearance.enabled = true
        appearance.shape = "cloud"
        model.botAppearances["local-source"] = appearance
        model.isExpanded = true
        model.refreshing = ["local-source"]
        let first = try XCTUnwrap(model.botPresentation(for: snapshot))
        XCTAssertEqual(first.appearance.shape, "cloud")
        XCTAssertEqual(first.mood, .fetching)
        model.updateSnapshots([snapshot])
        XCTAssertEqual(model.botPresentation(for: snapshot)?.appearance, appearance)
        model.isExpanded = false
        XCTAssertFalse(try XCTUnwrap(model.botPresentation(for: snapshot)).active)
    }

    func testFleetAppliesAppearanceToNewWindows() throws {
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("Requires a display") }
        let fleet = NotchFleet(scope: .allDisplays, edge: .top)
        defer { fleet.stop() }
        let activityAt = Date().addingTimeInterval(-1500)
        fleet.recordBotActivity([AgentSession(id: "cli", name: "CLI", detail: "", state: .success,
                                              waitingFor: nil, since: activityAt)])
        fleet.recordBotActivity([])
        var appearance = BotAppearance()
        appearance.enabled = true
        fleet.apply(botAppearances: ["provider": appearance])
        fleet.show()
        XCTAssertFalse(fleet.controllersForTesting.isEmpty)
        XCTAssertTrue(fleet.controllersForTesting.allSatisfy { $0.model.botAppearances["provider"] == appearance })
        XCTAssertTrue(fleet.controllersForTesting.allSatisfy { $0.model.botLastActivity == activityAt })
        fleet.stop()
        fleet.show()
        XCTAssertTrue(fleet.controllersForTesting.allSatisfy { $0.model.botAppearances["provider"] == appearance })
        XCTAssertTrue(fleet.controllersForTesting.allSatisfy { $0.model.botLastActivity == activityAt })
    }

    func testActivityAndRefreshOverrideQuotaMood() {
        XCTAssertEqual(BotPresentation.mood(activity: .waiting, refreshing: true, spent: true, hasReading: false), .idle)
        XCTAssertEqual(BotPresentation.mood(activity: .working, refreshing: true, spent: true, hasReading: false), .working)
        XCTAssertEqual(BotPresentation.mood(activity: nil, refreshing: true, spent: true, hasReading: false), .fetching)
        XCTAssertEqual(BotPresentation.mood(activity: nil, refreshing: false, spent: true, hasReading: true), .spent)
        XCTAssertEqual(BotPresentation.mood(activity: nil, refreshing: false, spent: false, hasReading: false), .asleep)
    }

    func testGeometryAndPersonalityCatalogAreComplete() throws {
        let library = try XCTUnwrap(BotMarkLibrary.available)
        XCTAssertEqual(library.shapes.count, 18)
        XCTAssertEqual(library.expressions.count, 25)
        for body in BotMarkBody.allCases { XCTAssertNotNil(library.shapes[body.rawValue]) }
        let states = Set(library.states.map(\.id))
        for persona in BotMarkPersona.allCases {
            for mood in BotMarkMood.allCases { XCTAssertTrue(states.contains(persona.state(for: mood))) }
            for state in persona.workingStates(overtime: true) + persona.idleStates(quiet: true, overtime: true) {
                XCTAssertTrue(states.contains(state))
            }
        }
        XCTAssertThrowsError(try BotMarkLibrary(decoding: Data("{}".utf8)))
    }

    func testMalformedPointDataIsRejectedBeforeBuildingPaths() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "bot-data", withExtension: "json"))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        json["circleRing"] = [[0]]
        XCTAssertThrowsError(try BotMarkLibrary(decoding: JSONSerialization.data(withJSONObject: json)))
    }

    func testAnOrderedOutWindowDoesNotRunTheDisplayClock() throws {
        _ = try XCTUnwrap(BotMarkLibrary.available)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 80, height: 80),
                              styleMask: .borderless, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let view = BotDrawingView(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        view.configure(BotPresentation(id: "test", brand: "claude", appearance: BotAppearance()), reduceMotion: false)
        window.contentView?.addSubview(view)
        let clock = BotWindowClock.attach(view, to: window)
        XCTAssertFalse(clock.isRunning)
        XCTAssertFalse(view.clockActive)
        view.detach()
        XCTAssertFalse(clock.isRunning)
    }

    func testHiddenAndReducedMotionViewsDoNotAdvance() throws {
        _ = try XCTUnwrap(BotMarkLibrary.available)
        var presentation = BotPresentation(id: "test", brand: "claude", appearance: BotAppearance())
        let view = BotDrawingView(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        presentation.active = false
        view.configure(presentation, reduceMotion: false)
        XCTAssertFalse(view.canAnimate)
        view.advance(to: 1, date: Date(), pointerInWindow: .zero)
        XCTAssertEqual(view.renderedFrames, 0)
        presentation.active = true
        view.configure(presentation, reduceMotion: true)
        XCTAssertFalse(view.canAnimate)
        view.advance(to: 2, date: Date(), pointerInWindow: .zero)
        XCTAssertEqual(view.renderedFrames, 0)
        XCTAssertNil(view.hitTest(.zero))
    }

    func testClockRestartsWithoutReplayingHiddenTime() throws {
        _ = try XCTUnwrap(BotMarkLibrary.available)
        let engine = BotMarkEngine()
        let programme = BotMarkProgramme(states: ["working"])
        _ = engine.advance(to: 0, programme: programme)
        let before = engine.advance(to: 1.0 / 60, programme: programme)
        engine.resumeClock()
        let after = engine.advance(to: 3600, programme: programme)
        XCTAssertEqual(before.transform.tx, after.transform.tx, accuracy: 0.001)
        XCTAssertEqual(before.transform.ty, after.transform.ty, accuracy: 0.001)
    }

    func testOneShotReturnsToCurrentMood() throws {
        _ = try XCTUnwrap(BotMarkLibrary.available)
        let engine = BotMarkEngine()
        var programme = BotMarkProgramme(states: ["idle"])
        programme.event = .workFinished
        _ = engine.advance(to: 0, programme: programme)
        XCTAssertEqual(engine.state, "excited")
        programme.event = nil
        for step in 1...240 { _ = engine.advance(to: Double(step) / 60, programme: programme) }
        XCTAssertEqual(engine.state, "idle")
    }
}
