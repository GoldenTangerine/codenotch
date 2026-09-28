/**
 @name: 通知声音测试
 @Descripttion: 验证通知音量持久化、静音、试听选择与播放中断。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-09 14:27:26
 @LastEditTime: 2026-09-09 14:27:26
 @FilePath: Tests/NotificationSoundTests.swift
 */
import AVFoundation
import Combine
import XCTest
@testable import Codenotch

@MainActor
final class NotificationSoundTests: XCTestCase {
    func testStartDefaultsPersistIndependentlyOfExistingNotifications() {
        let suite = "NotificationSoundTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "announceSessionEnd")
        defaults.set(false, forKey: "sessionEndSound")
        defaults.set("brief", forKey: "peekDuration")
        defaults.set("Funk", forKey: "sessionEndSoundName")
        let preferences = Preferences(defaults: defaults)
        XCTAssertTrue(preferences.announceSessionStart)
        XCTAssertEqual(preferences.sessionStartPeekDuration, .standard)
        XCTAssertFalse(preferences.sessionStartSound)
        XCTAssertEqual(preferences.sessionStartSoundName, "8bit_start")
        XCTAssertTrue(preferences.announcementSettings(for: .started).expand)
        XCTAssertNil(preferences.announcementSettings(for: .started).sound)
        preferences.announceSessionStart = false
        preferences.sessionStartPeekDuration = .long
        preferences.sessionStartSound = true
        preferences.sessionStartSoundName = "8bit_submit"
        let restored = Preferences(defaults: defaults)
        XCTAssertFalse(restored.announceSessionStart)
        XCTAssertEqual(restored.sessionStartPeekDuration, .long)
        XCTAssertTrue(restored.sessionStartSound)
        XCTAssertEqual(restored.sessionStartSoundName, "8bit_submit")
        XCTAssertFalse(restored.announceSessionEnd)
        XCTAssertFalse(restored.sessionEndSound)
        XCTAssertEqual(restored.peekDuration, .brief)
        XCTAssertEqual(restored.sessionEndSoundName, "Funk")
        XCTAssertEqual(restored.announcementSettings(for: .started).duration, 10)
        XCTAssertEqual(restored.announcementSettings(for: .finished).duration, 3)
        defaults.set("invalid", forKey: "sessionStartPeekDuration")
        XCTAssertEqual(Preferences(defaults: defaults).sessionStartPeekDuration, .standard)
    }

    func testStartAndEndSoundSwitchesAndSharedVolumeRouteIndependently() {
        let suite = "NotificationSoundTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)
        preferences.sessionStartSound = true
        XCTAssertEqual(preferences.announcementSettings(for: .started).sound, "8bit_start")
        preferences.sessionEndSound = false
        XCTAssertNil(preferences.announcementSettings(for: .finished).sound)
        XCTAssertNil(preferences.announcementSettings(for: .blocked).sound)
        XCTAssertEqual(preferences.announcementSettings(for: .started).sound, "8bit_start")
        preferences.sessionStartSound = false
        preferences.sessionEndSound = true
        XCTAssertNil(preferences.announcementSettings(for: .started).sound)
        XCTAssertEqual(preferences.announcementSettings(for: .finished).sound, SessionChime.defaultFinished)
        XCTAssertEqual(preferences.announcementSettings(for: .blocked).sound, SessionChime.defaultBlocked)
        preferences.sessionStartSound = true
        preferences.sessionSoundVolume = 0
        for reason: SessionCompletionWatcher.Reason in [.started, .finished, .blocked] {
            XCTAssertNil(preferences.announcementSettings(for: reason).sound)
        }
        preferences.sessionSoundVolume = 0.4
        preferences.sessionStartSoundName = SessionChime.off
        XCTAssertNil(preferences.announcementSettings(for: .started).sound)
        preferences.sessionStartSoundName = "NotASound"
        XCTAssertNil(preferences.announcementSettings(for: .started).sound)
    }

    func testAllSixBundledSoundsAreOfferedAndDecode() throws {
        let names = ["8bit_approval", "8bit_boot", "8bit_complete", "8bit_error", "8bit_start", "8bit_submit"]
        for name in names {
            XCTAssertEqual(SessionChime.available.filter { $0 == name }.count, 1)
            let bundled = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "Sounds"))
            XCTAssertNotNil(SessionChime.url(for: name))
            let player = try AVAudioPlayer(contentsOf: bundled)
            XCTAssertGreaterThan(player.duration, 0)
            let audio = try AVAudioFile(forReading: bundled)
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: AVAudioFrameCount(audio.length)))
            try audio.read(into: buffer)
            XCTAssertGreaterThan(buffer.frameLength, 0)
        }
    }

    func testVolumeAndIndependentOffChoicesSurviveReload() {
        let suite = "NotificationSoundTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)
        XCTAssertEqual(preferences.sessionSoundVolume, 1)
        for (input, expected) in [(0.0, 0.0), (0.37, 0.37), (1.0, 1.0), (-1.0, 0.0), (2.0, 1.0),
                                  (Double.nan, 1.0), (Double.infinity, 1.0)] {
            preferences.sessionSoundVolume = input
            XCTAssertEqual(preferences.sessionSoundVolume, expected)
            XCTAssertEqual(Preferences(defaults: defaults).sessionSoundVolume, expected)
            defaults.set(input, forKey: "sessionSoundVolume")
            XCTAssertEqual(Preferences(defaults: defaults).sessionSoundVolume, expected)
        }
        preferences.sessionEndSoundName = SessionChime.off
        var restored = Preferences(defaults: defaults)
        XCTAssertEqual(restored.sessionEndSoundName, SessionChime.off)
        XCTAssertEqual(restored.sessionBlockedSoundName, SessionChime.defaultBlocked)
        preferences.sessionBlockedSoundName = SessionChime.off
        restored = Preferences(defaults: defaults)
        XCTAssertEqual(restored.sessionBlockedSoundName, SessionChime.off)
        XCTAssertTrue(restored.sessionEndSound)
    }

    func testInvalidVolumeIsSafe() {
        XCTAssertEqual(SessionChime.normalizedVolume(.nan), 1)
        XCTAssertEqual(SessionChime.normalizedVolume(.infinity), 1)
        XCTAssertEqual(SessionChime.normalizedVolume(-.infinity), 1)
    }

    func testValidVolumePublishesOnceWithoutRecursiveAssignment() {
        let suite = "NotificationSoundTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)
        var values: [Double] = []
        let subscription = preferences.$sessionSoundVolume.sink { values.append($0) }
        preferences.sessionSoundVolume = 0.37
        XCTAssertEqual(values, [1, 0.37])
        withExtendedLifetime(subscription) {}
    }

    func testPreviewUsesOnlyCurrentResolvableSelections() {
        let finished = SessionChime.defaultFinished
        let blocked = SessionChime.defaultBlocked
        XCTAssertEqual(SessionChime.previewName(recent: blocked, finished: finished, blocked: blocked), blocked)
        XCTAssertEqual(SessionChime.previewName(recent: nil, finished: finished, blocked: blocked), finished)
        XCTAssertEqual(SessionChime.previewName(recent: finished, finished: "", blocked: blocked), blocked)
        XCTAssertEqual(SessionChime.previewName(recent: "NotASound", finished: "NotASound", blocked: blocked), blocked)
        XCTAssertNil(SessionChime.previewName(recent: finished, finished: "", blocked: ""))
        XCTAssertNil(SessionChime.previewName(recent: nil, finished: "NotASound", blocked: ""))
        XCTAssertEqual(SessionChime.previewName(recent: "8bit_start", finished: finished, blocked: blocked, started: "8bit_start"), "8bit_start")
        XCTAssertEqual(SessionChime.previewName(recent: nil, finished: "", blocked: "", started: "8bit_submit"), "8bit_submit")
        XCTAssertEqual(SessionChime.previewName(recent: "8bit_start", finished: finished, blocked: blocked, started: ""), finished)
    }

    func testOffAndZeroNeverCreateAPlayer() {
        var creations = 0
        let playback = ChimePlayback(resolve: { _ in URL(fileURLWithPath: "/sound") }, makePlayer: { _ in
            creations += 1
            return FakeChimePlayer()
        })
        XCTAssertFalse(playback.play(SessionChime.off))
        XCTAssertFalse(playback.play("Glass", volume: 0))
        XCTAssertEqual(creations, 0)
    }

    func testMutedNotificationDoesNotInterruptAnotherSound() {
        let player = FakeChimePlayer()
        let playback = ChimePlayback(resolve: { _ in URL(fileURLWithPath: "/sound") }, makePlayer: { _ in player })
        XCTAssertTrue(playback.play("Funk"))
        XCTAssertFalse(playback.play(SessionChime.off))
        XCTAssertFalse(playback.play("Glass", volume: 0))
        XCTAssertTrue(player.isPlaying)
        XCTAssertEqual(player.stopCount, 0)
        playback.stop()
        XCTAssertFalse(player.isPlaying)
    }

    func testVolumeReplacementAndImmediateStop() {
        var players: [FakeChimePlayer] = []
        let playback = ChimePlayback(resolve: { _ in URL(fileURLWithPath: "/sound") }, makePlayer: { _ in
            let player = FakeChimePlayer()
            players.append(player)
            return player
        })
        XCTAssertTrue(playback.play("Glass", volume: 0.25))
        let first = players[0]
        XCTAssertEqual(first.volumeAtPlay, 0.25)
        playback.updateVolume(0.6)
        XCTAssertEqual(first.volume, 0.6, accuracy: 0.001)
        XCTAssertTrue(playback.play("Funk", volume: 0.4))
        XCTAssertFalse(first.isPlaying)
        XCTAssertEqual(first.stopCount, 1)
        let second = players[1]
        XCTAssertEqual(second.volumeAtPlay, 0.4)
        playback.updateVolume(0)
        XCTAssertFalse(second.isPlaying)
        XCTAssertEqual(second.stopCount, 1)
    }

    func testFallbackUsesVolumeAndCanBeStoppedAndReplaced() {
        struct UnreadableSound: Error {}
        let fallback = FakeChimePlayer()
        let playback = ChimePlayback(resolve: { _ in URL(fileURLWithPath: "/sound") },
            makePlayer: { _ in throw UnreadableSound() }, makeFallback: { _ in fallback })
        XCTAssertTrue(playback.play("Glass", volume: 0.2))
        XCTAssertEqual(fallback.volumeAtPlay, 0.2)
        playback.updateVolume(0.7)
        XCTAssertEqual(fallback.volume, 0.7, accuracy: 0.001)
        XCTAssertTrue(playback.play("Funk", volume: 0.3))
        XCTAssertEqual(fallback.stopCount, 1)
        XCTAssertEqual(fallback.volumeAtPlay, 0.3)
        playback.updateVolume(0)
        XCTAssertFalse(fallback.isPlaying)
        XCTAssertEqual(fallback.stopCount, 2)
    }

    func testMissingFileDoesNotInterruptPlayback() {
        let player = FakeChimePlayer()
        let playback = ChimePlayback(resolve: { $0 == "missing" ? nil : URL(fileURLWithPath: "/sound") },
                                     makePlayer: { _ in player })
        XCTAssertTrue(playback.play("Glass"))
        XCTAssertFalse(playback.play("missing"))
        XCTAssertTrue(player.isPlaying)
    }

    func testPreviewDebouncesAndRunsLatestActionOnlyOnce() {
        let queue = ManualPreviewQueue()
        let scheduler = SoundPreviewScheduler(enqueue: queue.enqueue)
        var heard: [String] = []
        scheduler.schedule { heard.append("old") }
        scheduler.schedule { heard.append("latest") }
        XCTAssertTrue(heard.isEmpty)
        XCTAssertEqual(queue.delays, [0.3, 0.3])
        XCTAssertEqual(queue.cancelled, [0])
        queue.actions[0]()
        queue.actions[1]()
        queue.actions[1]()
        XCTAssertEqual(heard, ["latest"])
    }

    func testCancelSuppressesPendingPreview() {
        let queue = ManualPreviewQueue()
        let scheduler = SoundPreviewScheduler(enqueue: queue.enqueue)
        var plays = 0
        scheduler.schedule { plays += 1 }
        scheduler.cancel()
        queue.actions[0]()
        XCTAssertEqual(plays, 0)
        scheduler.schedule { plays += 1 }
        queue.actions[1]()
        XCTAssertEqual(plays, 1)
    }
}

private final class FakeChimePlayer: ChimePlayer {
    var volume: Float = 1
    var volumeAtPlay: Float?
    var isPlaying = false
    var stopCount = 0

    func play() -> Bool {
        volumeAtPlay = volume
        isPlaying = true
        return true
    }

    func stopPlayback() {
        stopCount += 1
        isPlaying = false
    }
}

private final class ManualPreviewQueue {
    var actions: [() -> Void] = []
    var delays: [TimeInterval] = []
    var cancelled: [Int] = []

    func enqueue(_ delay: TimeInterval, _ action: @escaping () -> Void) -> (() -> Void) {
        let index = actions.count
        delays.append(delay)
        actions.append(action)
        return { self.cancelled.append(index) }
    }
}
