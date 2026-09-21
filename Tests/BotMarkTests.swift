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
    func testSleepClockUsesThirtyFramesAndActiveViewsRestoreSixty() throws {
        _ = try XCTUnwrap(BotMarkLibrary.available)
        let window = VisibleWindow(contentRect: NSRect(x: 0, y: 0, width: 160, height: 160),
                                   styleMask: .borderless, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 160, height: 160))
        window.contentView = container
        let sleeper = BotDrawingView(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
        var sleeping = BotPresentation(id: "sleep", brand: "kimi", appearance: BotAppearance(), mood: .asleep)
        sleeper.configure(sleeping, reduceMotion: false)
        container.addSubview(sleeper)
        let clock = BotWindowClock.attach(sleeper, to: window)
        XCTAssertEqual(clock.preferredFrameRate, 30)
        let worker = BotDrawingView(frame: NSRect(x: 60, y: 0, width: 40, height: 40))
        worker.configure(BotPresentation(id: "work", brand: "kimi", appearance: BotAppearance(), mood: .working),
                         reduceMotion: false)
        container.addSubview(worker)
        clock.update()
        XCTAssertEqual(clock.preferredFrameRate, 60)
        worker.isHidden = true
        clock.update()
        XCTAssertEqual(clock.preferredFrameRate, 30)
        sleeping.mood = .working
        sleeper.configure(sleeping, reduceMotion: false)
        XCTAssertEqual(clock.preferredFrameRate, 60)
        sleeper.configure(sleeping, reduceMotion: true)
        XCTAssertEqual(clock.preferredFrameRate, 0)
        XCTAssertFalse(clock.isRunning)
        sleeper.detach()
        worker.detach()
        XCTAssertFalse(clock.isRunning)
    }

    func testQuietSleepAndPointerWakeKeepTheirAnimationRates() {
        let view = BotDrawingView(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
        let date = Date()
        var presentation = BotPresentation(id: "quiet", brand: "kimi", appearance: BotAppearance())
        presentation.lastActivity = date.addingTimeInterval(-1_300)
        view.configure(presentation, reduceMotion: false, now: date)
        XCTAssertEqual(view.preferredAnimationFrameRate, 30)
        view.setClockActive(true)
        view.advance(to: 1, date: date, pointerInWindow: CGPoint(x: 20, y: 20))
        XCTAssertEqual(view.preferredAnimationFrameRate, 60)
        presentation.waiting = true
        view.configure(presentation, reduceMotion: false, now: date)
        XCTAssertEqual(view.preferredAnimationFrameRate, 60)
        view.detach()
    }

    private func assertEyesSeparated(_ frame: BotMarkFrame, file: StaticString = #filePath, line: UInt = #line) {
        guard frame.eyes.count == 2, frame.eyes.allSatisfy(\.visible) else { return }
        let boxes = frame.eyes.map { eye -> CGRect in
            var transform = eye.transform
            return eye.path.copy(using: &transform)!.boundingBoxOfPath
        }
        let gap = max(boxes[1].minX - boxes[0].maxX, boxes[0].minX - boxes[1].maxX)
        XCTAssertGreaterThanOrEqual(gap, 2.99, "Visible eyes must retain their separation", file: file, line: line)
    }

    func testCapsulePointerPathIsSharedUntilLayoutChanges() throws {
        let model = NotchViewModel()
        let snapshot = try XCTUnwrap(Fixtures.snapshots().first)
        var appearance = BotAppearance()
        appearance.enabled = true
        model.botAppearances[snapshot.providerID] = appearance
        model.isExpanded = true
        let first = try XCTUnwrap(model.botPresentation(for: snapshot)?.pointerRegion)
        model.botLastActivity = Date()
        let same = try XCTUnwrap(model.botPresentation(for: snapshot)?.pointerRegion)
        XCTAssertTrue(first === same)
        model.sizeScale = 1.25
        let scaled = try XCTUnwrap(model.botPresentation(for: snapshot)?.pointerRegion)
        XCTAssertFalse(first === scaled)
        XCTAssertTrue(scaled === (try XCTUnwrap(model.botPresentation(for: snapshot)?.pointerRegion)))
        model.edge = model.edge == .left ? .right : .left
        XCTAssertFalse(scaled === (try XCTUnwrap(model.botPresentation(for: snapshot)?.pointerRegion)))
    }
    func testAllEdgesChooseTheInwardGaze() throws {
        let model = NotchViewModel()
        let snapshot = try XCTUnwrap(Fixtures.snapshots().first)
        var appearance = BotAppearance()
        appearance.enabled = true
        model.botAppearances[snapshot.providerID] = appearance
        for (edge, gaze) in [(NotchEdge.top, BotMarkGaze.ahead), (.bottom, .ahead),
                             (.left, .right), (.right, .left)] {
            model.edge = edge
            XCTAssertEqual(model.botPresentation(for: snapshot)?.gaze, gaze)
        }
    }

    func testGazeCrossesSmoothlyWithoutMirroringTheBody() {
        let engine = BotMarkEngine()
        var programme = BotMarkProgramme(states: ["idle"])
        programme.gaze = .left
        var frame = engine.advance(to: 0, programme: programme)
        XCTAssertEqual(frame.facing, -1)
        programme.gaze = .right
        frame = engine.advance(to: 1.0 / 60, programme: programme)
        XCTAssertGreaterThan(frame.facing, -1)
        XCTAssertLessThan(frame.facing, 0)
        for i in 2...90 { frame = engine.advance(to: Double(i) / 60, programme: programme) }
        XCTAssertEqual(frame.facing, 1, accuracy: 0.001)
        XCTAssertFalse(frame.flipX)
        programme.gaze = .ahead
        frame = engine.advance(to: 91.0 / 60, programme: programme)
        XCTAssertGreaterThan(frame.facing, 0.5)
        for i in 92...180 { frame = engine.advance(to: Double(i) / 60, programme: programme) }
        XCTAssertEqual(frame.facing, 0, accuracy: 0.001)
        XCTAssertFalse(frame.flipX)
    }

    func testEveryExpressionStaysInsideEveryBody() throws {
        let library = try XCTUnwrap(BotMarkLibrary.available)
        for body in BotMarkBody.allCases {
            for expression in library.expressions.indices {
                for gaze in BotMarkGaze.allCases {
                    let engine = BotMarkEngine()
                    var config = BotMarkConfig()
                    config.expressionPool = [expression]
                    config.expressionCadence = (100_000, 100_000)
                    engine.setState("expression-test", config: config)
                    var programme = BotMarkProgramme(states: ["expression-test"])
                    programme.shape = body.rawValue
                    programme.gaze = gaze
                    programme.gazeBias = 7
                    for step in 0...60 {
                        if step == 30 { programme.pointer = CGPoint(x: -0.6, y: 0.6) }
                        let frame = engine.advance(to: Double(step) / 60, programme: programme)
                        assertEyesSeparated(frame)
                        for eye in frame.eyes where eye.visible {
                            eye.path.applyWithBlock { element in
                                let element = element.pointee
                                guard element.type == .moveToPoint || element.type == .addLineToPoint else { return }
                                XCTAssertTrue(frame.headPath.contains(element.points[0].applying(eye.transform)),
                                              "\(body.rawValue), expression \(expression), \(gaze), frame \(step)")
                            }
                        }
                    }
                }
            }
        }
    }

    func testPointerOverridesBothSideDirectionsAndAheadRemainsCentred() {
        func offset(_ frame: BotMarkFrame) -> Double {
            let centres = frame.eyes.map { eye -> Double in
                var points: [CGPoint] = []
                eye.path.applyWithBlock { element in
                    let element = element.pointee
                    if element.type == .moveToPoint || element.type == .addLineToPoint {
                        points.append(element.points[0].applying(eye.transform))
                    }
                }
                return points.map(\.x).reduce(0, +) / Double(points.count)
            }
            return centres.reduce(0, +) / Double(centres.count) - BotMarkLibrary.shared.headCentre
        }
        let combinations = BotMarkBody.allCases.flatMap { body in BotMarkGaze.allCases.map { (body, $0) } }
        for (body, gaze) in combinations {
            let engine = BotMarkEngine()
            var config = BotMarkConfig()
            config.expressionPool = [19]
            config.expressionCadence = (100_000, 100_000)
            engine.setState("expression-test", config: config)
            var programme = BotMarkProgramme(states: ["expression-test"])
            programme.shape = body.rawValue
            programme.gaze = gaze
            programme.gazeBias = 7
            var frame = engine.advance(to: 0, programme: programme)
            for step in 1...90 { frame = engine.advance(to: Double(step) / 60, programme: programme) }
            if gaze == .ahead { XCTAssertLessThan(abs(offset(frame)), 8) }
            else { XCTAssertGreaterThan(offset(frame) * gaze.rawValue, 0) }
            programme.pointer = CGPoint(x: -0.6, y: 0)
            for step in 91...180 { frame = engine.advance(to: Double(step) / 60, programme: programme) }
            XCTAssertLessThan(offset(frame), 0)
            programme.pointer = CGPoint(x: 0.6, y: 0)
            for step in 181...270 { frame = engine.advance(to: Double(step) / 60, programme: programme) }
            XCTAssertGreaterThan(offset(frame), 0)
            var step = 271
            for x in [-0.05, 0.0, 0.05, -0.005, 0.005] {
                programme.pointer = CGPoint(x: x, y: 0)
                for i in step..<(step + 90) { frame = engine.advance(to: Double(i) / 60, programme: programme) }
                XCTAssertEqual(offset(frame), 22 * x * BotMarkLibrary.shared.shape(body.rawValue).face.sx, accuracy: 0.02,
                               "The cursor must own the gaze near the centre, including when it crosses zero")
                step += 90
            }
            programme.pointer = nil
            for i in step..<(step + 90) { frame = engine.advance(to: Double(i) / 60, programme: programme) }
            if gaze == .ahead { XCTAssertLessThan(abs(offset(frame)), 8) }
            else { XCTAssertGreaterThan(offset(frame) * gaze.rawValue, 0) }
        }
    }

    func testAnimatedStatesKeepVisibleEyesInsideDuringTurnsAndMorphs() {
        for body in BotMarkBody.allCases {
            for state in BotMarkLibrary.shared.states {
                let engine = BotMarkEngine()
                var programme = BotMarkProgramme(states: [state.id])
                programme.shape = body.rawValue
                programme.gaze = .left
                programme.gazeBias = 7
                for step in 0..<120 {
                    if step == 30 { programme.gaze = .right }
                    if step == 60 { programme.gaze = .ahead }
                    if step == 90 { programme.pointer = CGPoint(x: 0.6, y: -0.6) }
                    let frame = engine.advance(to: Double(step) / 60, programme: programme)
                    assertEyesSeparated(frame)
                    for eye in frame.eyes where eye.visible {
                        eye.path.applyWithBlock { element in
                            let element = element.pointee
                            guard element.type == .moveToPoint || element.type == .addLineToPoint else { return }
                            XCTAssertTrue(frame.headPath.contains(element.points[0].applying(eye.transform)),
                                          "\(body.rawValue), \(state.id), frame \(step)")
                        }
                    }
                }
            }
        }
    }

    func testPointerUsesTheCapsulePathAndPreviewBounds() {
        let window = VisibleWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                                   styleMask: .borderless, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let view = BotDrawingView(frame: NSRect(x: 80, y: 80, width: 40, height: 40))
        window.contentView?.addSubview(view)
        var presentation = BotPresentation(id: "test", brand: "claude", appearance: BotAppearance())
        presentation.pointerRegion = CGPath(roundedRect: CGRect(x: 20, y: 60, width: 160, height: 80),
                                             cornerWidth: 30, cornerHeight: 30, transform: nil)
        view.configure(presentation, reduceMotion: false)
        XCTAssertNotNil(view.pointer(at: CGPoint(x: 30, y: 100)))
        XCTAssertNil(view.pointer(at: CGPoint(x: 21, y: 139)))
        XCTAssertNil(view.pointer(at: CGPoint(x: 10, y: 100)))
        presentation.pointerRegion = nil
        view.configure(presentation, reduceMotion: false)
        XCTAssertNil(view.pointer(at: CGPoint(x: 30, y: 100)))
        XCTAssertNotNil(view.pointer(at: CGPoint(x: 100, y: 100)))
        view.detach()
    }

    func testReducedMotionCacheKeepsDirectionsSeparate() throws {
        let view = BotDrawingView(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
        var presentation = BotPresentation(id: "test", brand: "claude", appearance: BotAppearance())
        for gaze in [BotMarkGaze.left, .right, .ahead, .left] {
            presentation.gaze = gaze
            view.configure(presentation, reduceMotion: true)
            XCTAssertEqual(try XCTUnwrap(view.displayFrame).facing, gaze.rawValue, accuracy: 0.001)
            XCTAssertFalse(view.canAnimate)
        }
        XCTAssertEqual(view.renderedFrames, 0)
    }

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

    func testFleetStartsQuietBaselineFromAnEmptyMonitor() {
        let fleet = NotchFleet(scope: .allDisplays, edge: .top)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        fleet.recordBotActivity([], now: start)
        fleet.recordBotActivity([], now: start.addingTimeInterval(600))
        fleet.setSnapshots([], now: start.addingTimeInterval(1201))
        XCTAssertEqual(fleet.menuModel.botLastActivity, start)
        XCTAssertFalse(fleet.menuModel.botGloballyBusy)
        var presentation = BotPresentation(id: "test", brand: "kimi", appearance: BotAppearance())
        presentation.lastActivity = fleet.menuModel.botLastActivity
        XCTAssertTrue(presentation.isQuiet(at: start.addingTimeInterval(1201)))
    }

    func testFleetTracksOverlappingCLIModelsAndLinkedRequests() {
        let fleet = NotchFleet(scope: .allDisplays, edge: .top)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        fleet.recordBotActivity([], now: start.addingTimeInterval(-3600))
        fleet.recordBotActivity([AgentSession(id: "cli", name: "CLI", detail: "", state: .busy,
                                             waitingFor: nil, since: start)], now: start)
        fleet.setThinkingModels(["model": start], now: start)
        fleet.setLocalActivities(["local": LocalModelActivity(phase: .generating, queued: 0, since: start)], now: start)
        let platform = CodeSwitchPlatform(platform: "claude", name: "Claude", icon: "claude",
                                          error: false, providers: [])
        let provider = CodeSwitchProvider(providerId: "linked", providerName: "Linked", icon: "openai",
            activeRequests: 1, status: "active", loading: false, updatedAt: 0, quotas: [], stats: nil)
        fleet.setSnapshots([provider.snapshot(platform: platform)], now: start)
        XCTAssertTrue(fleet.menuModel.botGloballyBusy)
        fleet.recordBotActivity([], now: start.addingTimeInterval(1))
        XCTAssertTrue(fleet.menuModel.botGloballyBusy)
        XCTAssertEqual(fleet.menuModel.botLastActivity, start.addingTimeInterval(1))
        fleet.setThinkingModels([:], now: start.addingTimeInterval(2))
        XCTAssertTrue(fleet.menuModel.botGloballyBusy)
        XCTAssertEqual(fleet.menuModel.botLastActivity, start.addingTimeInterval(2))
        fleet.setLocalActivities([:], now: start.addingTimeInterval(3))
        XCTAssertTrue(fleet.menuModel.botGloballyBusy)
        XCTAssertEqual(fleet.menuModel.botLastActivity, start.addingTimeInterval(3))
        fleet.setSnapshots([], now: start.addingTimeInterval(4))
        XCTAssertFalse(fleet.menuModel.botGloballyBusy)
        XCTAssertEqual(fleet.menuModel.botLastActivity, start.addingTimeInterval(4))
        fleet.setSnapshots([], now: start.addingTimeInterval(500))
        XCTAssertEqual(fleet.menuModel.botLastActivity, start.addingTimeInterval(4))
        fleet.setThinkingModels(["model": start.addingTimeInterval(600)], now: start.addingTimeInterval(600))
        fleet.setLocalMetricsEnabled(false, now: start.addingTimeInterval(601))
        XCTAssertFalse(fleet.menuModel.botGloballyBusy)
        XCTAssertEqual(fleet.menuModel.botLastActivity, start.addingTimeInterval(601))
    }

    func testGeometryAndPersonalityCatalogAreComplete() throws {
        let library = try XCTUnwrap(BotMarkLibrary.available)
        XCTAssertEqual(library.shapes.count, 18)
        XCTAssertEqual(library.expressions.count, 25)
        for body in BotMarkBody.allCases { XCTAssertNotNil(library.shapes[body.rawValue]) }
        let states = Set(library.states.map(\.id))
        for persona in BotMarkPersona.allCases {
            for mood in BotMarkMood.allCases { XCTAssertTrue(states.contains(persona.state(for: mood))) }
            for state in persona.workingStates(overtime: true) + persona.idleStates() {
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
