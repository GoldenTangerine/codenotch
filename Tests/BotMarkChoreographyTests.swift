/**
 @name: 机器人编排与睡眠回归测试
 @Descripttion: 验证顺序动作、睡眠优先级、粒子隔离与小尺寸眼睛边界。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-20 10:28:47
 @LastEditTime: 2026-09-20 10:28:47
 @FilePath: Tests/BotMarkChoreographyTests.swift
 */
import AppKit
import XCTest
@testable import Codenotch

@MainActor
final class BotMarkChoreographyTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private func date(day: Int = 14, hour: Int = 14) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
    }

    func testCompleteScenesPlayInOrderAndKeepDistinctPersonalities() {
        for mood in BotMarkMood.allCases {
            var signatures: Set<Set<String>> = []
            for persona in BotMarkPersona.allCases {
                let programme = BotMarkProgramme.forMood(mood, persona: persona, at: date(), calendar: calendar)
                XCTAssertEqual(programme.order, .sequence)
                signatures.insert(Set(programme.states))
                for state in programme.states {
                    XCTAssertEqual(BotMarkLibrary.shared.state(state).id, state)
                }
                let duration = programme.states.reduce(0.0) { $0 + programme.holdDuration(for: $1).upperBound } / 1000 + 2
                let engine = BotMarkEngine()
                var seen: [String] = []
                for index in 0...Int(duration * 10) {
                    _ = engine.advance(to: Double(index) / 10, programme: programme)
                    if seen.last != engine.state { seen.append(engine.state) }
                }
                XCTAssertEqual(Array(seen.prefix(programme.states.count)), programme.states)
            }
            if mood != .asleep { XCTAssertEqual(signatures.count, 8) }
        }
        XCTAssertEqual(Set(BotMarkPersona.allCases.map(\.completionState)).count, 8)
        XCTAssertEqual(Set(BotMarkPersona.allCases.map { Set($0.attentionRoutine.states) }).count, 8)
    }

    func testSleepForNoReadingAndLongInactivityAtAnyTime() {
        for persona in BotMarkPersona.allCases {
            for hour in [7, 14, 23] {
                for day in [14, 19] {
                    for mood in [BotMarkMood.idle, .spent, .asleep] {
                        let programme = BotMarkProgramme.forMood(mood, persona: persona, isQuiet: true,
                            at: date(day: day, hour: hour), calendar: calendar)
                        XCTAssertEqual(programme.states, ["sleeping"])
                        XCTAssertEqual(programme.mood, .asleep)
                    }
                }
            }
            for pointed in [false, true] {
                let missing = BotMarkProgramme.forMood(.asleep, persona: persona, isPointedAt: pointed)
                XCTAssertEqual(missing.states, ["sleeping"])
                for mood in [BotMarkMood.working, .fetching] {
                    let active = BotMarkProgramme.forMood(mood, persona: persona,
                        isQuiet: true, isPointedAt: pointed)
                    XCTAssertEqual(active.mood, mood)
                    XCTAssertFalse(active.states.contains("sleeping"))
                }
            }
            let waiting = BotMarkProgramme.forMood(.idle, persona: persona, isQuiet: true, isWaiting: true)
            XCTAssertEqual(waiting.states, ["listening"])
            let awake = BotMarkProgramme.forMood(.idle, persona: persona, isQuiet: true, isPointedAt: true)
            XCTAssertEqual(awake.states, persona.attentionRoutine.states)
            let engine = BotMarkEngine()
            let asleep = BotMarkProgramme.forMood(.idle, persona: persona, isQuiet: true)
            for tick in 0...60 { _ = engine.advance(to: Double(tick) / 10, programme: asleep) }
            XCTAssertEqual(engine.state, "sleeping")
            XCTAssertEqual(engine.expressionIndex, 13)
            _ = engine.advance(to: 6.1, programme: awake)
            XCTAssertEqual(engine.state, persona.attentionRoutine.states[0])
            _ = engine.advance(to: 6.2, programme: asleep)
            XCTAssertEqual(engine.state, "sleeping")
        }
        var presentation = BotPresentation(id: "test", brand: "kimi", appearance: BotAppearance())
        XCTAssertFalse(presentation.isQuiet(at: date()))
        presentation.lastActivity = date().addingTimeInterval(-1200)
        XCTAssertFalse(presentation.isQuiet(at: date()))
        XCTAssertTrue(presentation.isQuiet(at: date().addingTimeInterval(1)))
        presentation.globallyBusy = true
        XCTAssertFalse(presentation.isQuiet(at: date().addingTimeInterval(1)))
    }

    func testEverydayScenesHaveNoWorkStatesOrRibbons() {
        var everyday: Set<String> = []
        for persona in BotMarkPersona.allCases {
            everyday.formUnion(persona.routine(for: .idle).states)
            everyday.formUnion(persona.attentionRoutine.states)
            for pointed in [false, true] {
                let programme = BotMarkProgramme.forMood(.idle, persona: persona, isPointedAt: pointed)
                let engine = BotMarkEngine()
                for tick in 0...450 {
                    let frame = engine.advance(to: Double(tick) / 10, programme: programme)
                    XCTAssertTrue(frame.frontParticles.isEmpty && frame.backParticles.isEmpty)
                }
            }
        }
        for persona in BotMarkPersona.allCases {
            XCTAssertTrue(Set(persona.workingStates(overtime: true)).isDisjoint(with: everyday))
        }
        let engine = BotMarkEngine()
        let working = BotMarkProgramme.forMood(.working, persona: .eager)
        var seenParticles = false
        for tick in 0...120 {
            let frame = engine.advance(to: Double(tick) / 10, programme: working)
            seenParticles = seenParticles || !frame.frontParticles.isEmpty || !frame.backParticles.isEmpty
        }
        XCTAssertTrue(seenParticles)
        let idle = BotMarkProgramme.forMood(.idle, persona: .steady)
        for tick in 121...150 {
            let frame = engine.advance(to: Double(tick) / 10, programme: idle)
            XCTAssertTrue(frame.frontParticles.isEmpty && frame.backParticles.isEmpty)
        }
    }

    func testCompletionReturnsToSceneAndStopsEventParticles() {
        for persona in BotMarkPersona.allCases {
            for event in [BotMarkEvent.workFinished, .limitReset] {
                let engine = BotMarkEngine()
                var programme = BotMarkProgramme.forMood(.idle, persona: persona)
                programme.event = event
                let expected = event == .limitReset ? "celebrate" : persona.completionState
                for tick in 0...Int((event.duration / 1000 + 5) * 10) {
                    let time = Double(tick) / 10
                    let frame = engine.advance(to: time, programme: programme)
                    if time < event.duration / 1000 - 0.1 { XCTAssertEqual(engine.state, expected) }
                    if time > event.duration / 1000 + 0.2 {
                        XCTAssertTrue(programme.states.contains(engine.state))
                        XCTAssertTrue(frame.frontParticles.isEmpty && frame.backParticles.isEmpty)
                    }
                }
                programme.particlesEnabled = false
                XCTAssertFalse(programme.configuration(for: expected, isEvent: true).particlesEnabled)
            }
        }
    }

    func testReturningPosesUseTheirWholeExpressionPool() {
        var programme = BotMarkProgramme.forMood(.idle, persona: .curious)
        programme.stateHolds = Dictionary(uniqueKeysWithValues: programme.states.map { ($0, 500.0...500.0) })
        let pool = BotMarkLibrary.shared.state("curious").expressionPool
        let engine = BotMarkEngine()
        var previous = ""
        var seen: Set<Int> = []
        for tick in 0..<(pool.count * programme.states.count * 8) {
            _ = engine.advance(to: Double(tick) / 10, programme: programme)
            if engine.state != previous, engine.state == "curious" { seen.insert(engine.expressionIndex) }
            previous = engine.state
        }
        XCTAssertEqual(seen, Set(pool))
    }

    func testWorkingEyesKeepClearanceDuringCompleteScenes() {
        for body in BotMarkBody.allCases {
            for persona in BotMarkPersona.allCases {
                let engine = BotMarkEngine()
                var programme = BotMarkProgramme.forMood(.working, persona: persona, at: date(), calendar: calendar)
                programme.shape = body.rawValue
                programme.viewWidth = 25
                programme.gazeBias = 7
                for tick in 0...2700 {
                    programme.gaze = BotMarkGaze.allCases[(tick / 300) % 3]
                    programme.pointer = tick % 600 >= 450 ? CGPoint(x: 0.6, y: -0.6) : nil
                    let frame = engine.advance(to: Double(tick) / 60, programme: programme)
                    let clearance = max(2, frame.headPath.boundingBoxOfPath.width * 0.025) - 0.01
                    for eye in frame.eyes where eye.visible {
                        eye.path.applyWithBlock { element in
                            let element = element.pointee
                            guard element.type == .moveToPoint || element.type == .addLineToPoint else { return }
                            let point = element.points[0].applying(eye.transform)
                            for inset in [-clearance, 0, clearance] {
                                XCTAssertTrue(frame.headPath.contains(CGPoint(x: point.x + inset, y: point.y)),
                                              "\(body)/\(persona)/\(engine.state)/\(tick)")
                            }
                        }
                    }
                    if frame.eyes.count == 2, frame.eyes.allSatisfy(\.visible) {
                        let boxes = frame.eyes.map { eye -> CGRect in
                            var transform = eye.transform
                            return eye.path.copy(using: &transform)!.boundingBoxOfPath
                        }
                        XCTAssertGreaterThanOrEqual(max(boxes[1].minX - boxes[0].maxX,
                                                       boxes[0].minX - boxes[1].maxX), 2.99)
                    }
                }
            }
        }
    }

    func testKimiDefaultIsBrighterAndCustomColourIsPreserved() {
        var appearance = BotAppearance()
        XCTAssertEqual(BotAppearance.rgbValue(appearance.color(for: "kimi", brand: "Kimi Code")), 0x7AA5FF)
        appearance.rgb = 0x123456
        XCTAssertEqual(BotAppearance.rgbValue(appearance.color(for: "kimi", brand: "Kimi Code")), 0x123456)
    }

    func testFirstEmptyObservationStartsInactivityWithoutResettingOnPolls() {
        let start = date()
        var timeline = BotActivityTimeline()
        XCTAssertNil(timeline.lastActivity)
        timeline.record(.cli, busy: false, now: start)
        timeline.record(.cli, busy: false, now: start.addingTimeInterval(1190))
        timeline.record(.codeSwitch, busy: false, now: start.addingTimeInterval(1199))
        XCTAssertEqual(timeline.lastActivity, start)
        var presentation = BotPresentation(id: "test", brand: "kimi", appearance: BotAppearance())
        presentation.lastActivity = timeline.lastActivity
        XCTAssertFalse(presentation.isQuiet(at: start.addingTimeInterval(1200)))
        XCTAssertTrue(presentation.isQuiet(at: start.addingTimeInterval(1201)))
    }

    func testEveryActivitySourceRestartsInactivityWhenItFinishes() {
        let start = date()
        for source in BotActivityTimeline.Source.allCases {
            var timeline = BotActivityTimeline()
            timeline.record(.cli, busy: false, now: start.addingTimeInterval(-3600))
            timeline.record(source, busy: true, now: start)
            XCTAssertTrue(timeline.isBusy)
            let finish = start.addingTimeInterval(60)
            timeline.record(source, busy: false, now: finish)
            XCTAssertFalse(timeline.isBusy)
            XCTAssertEqual(timeline.lastActivity, finish)
            timeline.record(source, busy: false, latest: start, now: finish.addingTimeInterval(900))
            XCTAssertEqual(timeline.lastActivity, finish)
        }
    }

    func testOverlappingSourcesStayBusyUntilTheLastSourceFinishes() {
        let start = date()
        var timeline = BotActivityTimeline()
        for source in BotActivityTimeline.Source.allCases { timeline.record(source, busy: true, now: start) }
        for (index, source) in BotActivityTimeline.Source.allCases.enumerated() {
            timeline.record(source, busy: false, now: start.addingTimeInterval(Double(index + 1)))
            XCTAssertEqual(timeline.isBusy, index < BotActivityTimeline.Source.allCases.count - 1)
        }
        XCTAssertEqual(timeline.lastActivity, start.addingTimeInterval(4))
    }

    private func runLoop(until condition: () -> Bool, timeout: TimeInterval = 2) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        XCTAssertTrue(condition(), "The one-shot sleep update did not arrive")
    }

    func testReducedMotionSleepsAtDeadlineWithoutReconfigurationOrAnimation() {
        let view = BotDrawingView(frame: NSRect(x: 0, y: 0, width: 25, height: 25))
        defer { view.detach() }
        var presentation = BotPresentation(id: "sleep-timer", brand: "kimi", appearance: BotAppearance())
        presentation.lastActivity = Date().addingTimeInterval(-1199.7)
        view.configure(presentation, reduceMotion: true)
        XCTAssertEqual(view.programme.mood, .idle)
        runLoop(until: { view.programme.mood == .asleep })
        XCTAssertEqual(view.programme.states, ["sleeping"])
        XCTAssertEqual(view.renderedFrames, 0)
        XCTAssertFalse(view.clockActive)
        XCTAssertFalse(view.canAnimate)
        presentation.lastActivity = Date()
        view.configure(presentation, reduceMotion: true)
        XCTAssertEqual(view.programme.mood, .idle)
    }

    func testReducedMotionReschedulesDeadlineAfterActivity() {
        let view = BotDrawingView(frame: NSRect(x: 0, y: 0, width: 25, height: 25))
        defer { view.detach() }
        var presentation = BotPresentation(id: "reschedule", brand: "kimi", appearance: BotAppearance())
        let start = Date()
        presentation.lastActivity = start.addingTimeInterval(-1199.7)
        view.configure(presentation, reduceMotion: true)
        presentation.lastActivity = start.addingTimeInterval(-1198.8)
        view.configure(presentation, reduceMotion: true)
        runLoop(until: { Date().timeIntervalSince(start) > 0.6 })
        XCTAssertEqual(view.programme.mood, .idle)
        runLoop(until: { view.programme.mood == .asleep })
        XCTAssertEqual(view.renderedFrames, 0)
    }

    func testReducedMotionCancelsDeadlineWhenDetachedOrWaiting() {
        for waiting in [false, true] {
            let view = BotDrawingView(frame: NSRect(x: 0, y: 0, width: 25, height: 25))
            var presentation = BotPresentation(id: "cancel", brand: "kimi", appearance: BotAppearance())
            let start = Date()
            presentation.lastActivity = start.addingTimeInterval(-1199.7)
            view.configure(presentation, reduceMotion: true)
            if waiting {
                presentation.waiting = true
                view.configure(presentation, reduceMotion: true)
            } else {
                view.detach()
            }
            runLoop(until: { Date().timeIntervalSince(start) > 0.6 })
            XCTAssertEqual(view.programme.mood, .idle)
            XCTAssertEqual(view.renderedFrames, 0)
            view.detach()
        }
    }

    func testReducedMotionRechecksSleepAfterAncestorBecomesVisible() {
        let parent = NSView(frame: NSRect(x: 0, y: 0, width: 50, height: 50))
        let view = BotDrawingView(frame: NSRect(x: 0, y: 0, width: 25, height: 25))
        parent.addSubview(view)
        defer { view.detach() }
        var presentation = BotPresentation(id: "hidden-timer", brand: "kimi", appearance: BotAppearance())
        let start = Date()
        presentation.lastActivity = start.addingTimeInterval(-1199.7)
        view.configure(presentation, reduceMotion: true)
        parent.isHidden = true
        runLoop(until: { Date().timeIntervalSince(start) > 0.6 })
        XCTAssertEqual(view.programme.mood, .idle)
        parent.isHidden = false
        XCTAssertEqual(view.programme.mood, .asleep)
        XCTAssertEqual(view.renderedFrames, 0)
    }

    func testSleepDeadlineDoesNotRetainTheView() {
        weak var released: BotDrawingView?
        autoreleasepool {
            let view = BotDrawingView(frame: NSRect(x: 0, y: 0, width: 25, height: 25))
            var presentation = BotPresentation(id: "release-timer", brand: "kimi", appearance: BotAppearance())
            presentation.lastActivity = Date()
            view.configure(presentation, reduceMotion: true)
            released = view
        }
        XCTAssertNil(released)
    }
}
