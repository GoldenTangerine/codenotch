/**
 @name: 动态机器人 · BotMarkProgramme
 @Descripttion: 移植 Pulse 机器人动作与几何实现并适配本项目。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-18 10:13:39
 @LastEditTime: 2026-09-18 10:13:39
 @FilePath: Sources/Features/BotMark/BotMarkProgramme.swift
 */
// Adapted from Pulse (Apache-2.0); see Resources/BotMark-NOTICE.txt.
import SwiftUI

/// What a mark should be playing, and how.
///
/// **A playlist rather than one state.** A working mark held in a single
/// upstream state loops every second and a half for as long as the turn
/// lasts, which stops reading as work and starts reading as a screensaver.
/// Three states taken in a random order, a few seconds each, is the same fact
/// told by a character who is busy with different things.
///
/// The engine owns which one is playing, because it owns the clock — and
/// because the per-state table (`expressionPool`, cadences, the morph it
/// carries) has to be rebuilt every time the state changes, which the view
/// cannot do without knowing when that happens.
struct BotMarkProgramme {
    // 生产入口 forMood 使用顺序编排；保留原始随机播放能力供单独动作调用。
    enum Order { case random, sequence }

    /// The states to take in turn. One entry is held; more are rotated.
    var states: [String]
    var order: Order = .random
    var stateHolds: [String: ClosedRange<Double>] = [:]
    var completionState = "excited"
    /// Milliseconds a state is held before another is taken.
    var hold: ClosedRange<Double> = 2500...4500
    /// A one-shot that interrupts the playlist, for something that just
    /// happened rather than something that is going on.
    var event: BotMarkEvent?
    /// The mood behind the playlist, so the engine can tell a change of state
    /// from a change of fact.
    var mood: BotMarkMood = .idle

    var shape: String = BotMarkBody.default.shape
    var tempo = 1.0
    var motionScale = 1.0
    var gazeScale = 1.0
    var eyeScale = 1.0
    var gazeBias = 0.0
    var gaze: BotMarkGaze = .ahead
    var rotationScale = 1.0
    var squashScale = 1.0
    var particlesEnabled = true
    /// Where the pointer is, as a fraction of the mark's own radius from its
    /// centre, or nil when it is nowhere near. The eyes follow it.
    var pointer: CGPoint?
    var viewWidth = 96.0
    var color = Color.white
    var eyeColor = Color(white: 0.06)

    static func forMood(
        _ mood: BotMarkMood,
        persona: BotMarkPersona,
        isQuiet: Bool = false,
        isPointedAt: Bool = false,
        isWaiting: Bool = false,
        at date: Date = Date(),
        calendar: Calendar = .current
    ) -> BotMarkProgramme {
        // 活动和刷新优先；鼠标可唤醒闲置睡眠，无读数仍保留睡眠含义。
        let resting = (mood == .idle || mood == .spent) && isQuiet && !isPointedAt
        let effectiveMood: BotMarkMood = isWaiting ? .idle : resting ? .asleep : mood
        let routine: BotMarkRoutine
        if isWaiting {
            routine = BotMarkRoutine(.init("listening", 3_000...4_000))
        } else {
            routine = switch effectiveMood {
            case .working: persona.workingRoutine(overtime: BotMarkHours.isOvertime(at: date, calendar: calendar))
            case .idle: isPointedAt ? persona.attentionRoutine : persona.routine(for: .idle)
            case .fetching, .spent, .asleep: persona.routine(for: effectiveMood)
            }
        }
        var programme = BotMarkProgramme(states: routine.states)
        programme.order = .sequence
        programme.stateHolds = routine.holds
        programme.completionState = persona.completionState
        programme.mood = effectiveMood
        programme.tempo = persona.tempo * effectiveMood.tempoEmphasis
        programme.motionScale = persona.motionScale
        programme.gazeScale = persona.gazeScale
        programme.eyeScale = persona.eyeScale
        programme.rotationScale = effectiveMood.rotationEmphasis
        programme.squashScale = effectiveMood.squashEmphasis
        return programme
    }

    func state(for event: BotMarkEvent) -> String {
        event == .workFinished ? completionState : event.state
    }

    func holdDuration(for state: String) -> ClosedRange<Double> {
        stateHolds[state] ?? hold
    }

    /// The config for one state of the playlist: the upstream's own table for
    /// that state, with this programme's scales on top.
    func configuration(for state: String, isEvent: Bool = false) -> BotMarkConfig {
        var config = BotMarkConfig.forState(BotMarkLibrary.shared.state(state), shape: shape)
        config.tempo = tempo
        config.motionScale = motionScale
        config.gazeScale = gazeScale
        config.eyeScale = eyeScale
        config.gazeBias = gazeBias
        config.gaze = gaze
        config.rotationScale = rotationScale
        config.squashScale = squashScale
        config.particlesEnabled = particlesEnabled && (mood == .working || mood == .fetching || isEvent)
        config.pointer = pointer != nil
        config.viewWidth = viewWidth
        config.color = color
        config.eyeColor = eyeColor
        return config
    }
}

/// Something that just happened, played once and then dropped.
///
/// **Both of these are facts Pulse witnessed**, not a view noticing its own
/// history: a window that turned over by the same unambiguous test the
/// notifications use, and a CLI whose turn ended, from the activity monitor
/// that already drives the running mark. A mark that celebrated because a
/// SwiftUI body happened to be rebuilt would be the rail inventing news.
enum BotMarkEvent: Equatable, Sendable {
    /// A limit reset: the big one, nine turns and a shower of ribbons.
    case limitReset
    /// A turn just finished. Shorter and quieter — this happens many times an
    /// hour, and a full celebration every time would be exhausting.
    case workFinished

    var state: String {
        switch self {
        case .limitReset: "celebrate"
        case .workFinished: "excited"
        }
    }

    /// How long the one-shot holds the mark before the playlist comes back.
    ///
    /// The celebrate cycle is 6.2s upstream and looks unfinished if it is cut
    /// mid-spin, so a reset gets the whole of it. A finish is a beat.
    var duration: Double {
        switch self {
        case .limitReset: 6400
        case .workFinished: 2600
        }
    }
}
