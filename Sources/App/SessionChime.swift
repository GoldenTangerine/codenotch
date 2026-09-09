/**
 @name: 会话提示音
 @Descripttion: 管理通知与试听的声音解析、音量和播放生命周期。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-09 14:27:26
 @LastEditTime: 2026-09-09 14:27:26
 @FilePath: Sources/App/SessionChime.swift
 */
import AVFoundation
import AppKit

/// The sound a finished session makes.
///
/// Plays the audio file itself rather than handing a name to `NSSound`.
/// `NSSound(named:)` resolves a system alert, and a system alert is routed
/// through the interface-sound-effects channel — which System Settings → Sound
/// can switch off, and which a good number of people have switched off, since
/// it is also what makes the Mac click and swoosh at them all day. On such a
/// machine `NSSound.play()` returns true and nothing is heard. Reading the same
/// file into an `AVAudioPlayer` puts it on the ordinary output path, where the
/// only thing that silences it is the volume control.
enum SessionChime {
    static let off = ""

    static func normalizedVolume(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : 1
    }

    static func previewName(recent: String?, finished: String, blocked: String) -> String? {
        let selected = [finished, blocked]
        let candidates = recent.map { selected.contains($0) ? [$0] + selected : selected } ?? selected
        return candidates.first { $0 != off && url(for: $0) != nil }
    }

    static func stop() {
        playback.stop()
    }

    static func updateVolume(_ value: Double) {
        playback.updateVolume(value)
    }

    /// A turn ended. Short and unremarkable — this fires whenever any window
    /// finishes, which on a busy afternoon is often.
    static let defaultFinished = "Glass"
    /// A session is blocked on you. Two-toned, so it reads as different from
    /// the ordinary one without being an alarm.
    static let defaultBlocked = "Funk"

    /// Where macOS keeps alert sounds, most specific first, so a user's own
    /// file shadows a system one of the same name.
    private static let directories = [
        "\(NSHomeDirectory())/Library/Sounds",
        "/Library/Sounds",
        "/System/Library/Sounds"
    ]

    private static let extensions = ["aiff", "aif", "m4a", "wav", "caf"]

    /// Every sound the picker can offer, by name, in the order macOS lists them.
    static var available: [String] {
        var seen = Set<String>()
        var names: [String] = []
        for directory in directories {
            let files = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
            for file in files.sorted() {
                let url = URL(fileURLWithPath: file)
                guard extensions.contains(url.pathExtension.lowercased()) else { continue }
                let name = url.deletingPathExtension().lastPathComponent
                if seen.insert(name).inserted { names.append(name) }
            }
        }
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static func url(for name: String) -> URL? {
        guard name != off else { return nil }
        for directory in directories {
            for ext in extensions {
                let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).\(ext)")
                if FileManager.default.fileExists(atPath: url.path) { return url }
            }
        }
        return nil
    }

    @discardableResult
    static func play(_ name: String, volume: Double = 1) -> Bool {
        playback.play(name, volume: volume)
    }

    private static let playback = ChimePlayback()
}

protocol ChimePlayer: AnyObject {
    var volume: Float { get set }
    func play() -> Bool
    func stopPlayback()
}

extension AVAudioPlayer: ChimePlayer {
    func stopPlayback() { stop() }
}

extension NSSound: ChimePlayer {
    func stopPlayback() { stop() }
}

final class ChimePlayback {
    private var playing: ChimePlayer?
    private let resolve: (String) -> URL?
    private let makePlayer: (URL) throws -> ChimePlayer
    private let makeFallback: (String) -> ChimePlayer?

    init(resolve: @escaping (String) -> URL? = SessionChime.url,
         makePlayer: @escaping (URL) throws -> ChimePlayer = { url in
             let player = try AVAudioPlayer(contentsOf: url)
             player.prepareToPlay()
             return player
         },
         makeFallback: @escaping (String) -> ChimePlayer? = { NSSound(named: $0) }) {
        self.resolve = resolve
        self.makePlayer = makePlayer
        self.makeFallback = makeFallback
    }

    func stop() {
        playing?.stopPlayback()
        playing = nil
    }

    func updateVolume(_ value: Double) {
        let volume = Float(SessionChime.normalizedVolume(value))
        if volume == 0 { stop(); return }
        playing?.volume = volume
    }

    /// Plays the named sound, if it is still there. Returns whether it started.
    ///
    /// The player is held for the length of the sound: a stack local is
    /// deallocated on the way out of this function and stops mid-note.
    ///
    /// The return value is not decoration — it is what a test can assert on,
    /// and asserting on it is what keeps `play()` out of the log interpolation
    /// below. See the comment there.
    @discardableResult
    func play(_ name: String, volume: Double = 1) -> Bool {
        let volume = Float(SessionChime.normalizedVolume(volume))
        guard name != SessionChime.off, volume > 0 else { return false }
        guard let url = resolve(name) else {
            Log.usage.error("no sound file named \(name, privacy: .public)")
            return false
        }
        stop()
        do {
            let player = try makePlayer(url)
            player.volume = volume
            playing = player
            // On its own line, and never inside the log interpolation below.
            // Logger's interpolations are autoclosures evaluated only when the
            // level is enabled, so a `play()` written into one does not happen
            // at all on an ordinary run — the app logs nothing and plays
            // nothing, and every part of it looks correct.
            let started = player.play()
            Log.usage.debug("chime \(name, privacy: .public): \(started, privacy: .public)")
            return started
        } catch {
            // Worth falling back for rather than going silent: whatever stops
            // AVFoundation reading the file — an unreadable custom sound, a
            // format it will not open — has nothing to do with NSSound.
            Log.usage.error("chime \(name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            playing = makeFallback(name)
            playing?.volume = volume
            return playing?.play() ?? false
        }
    }

}

final class SoundPreviewScheduler {
    typealias Enqueue = (TimeInterval, @escaping () -> Void) -> (() -> Void)
    private let enqueue: Enqueue
    private var cancelPending: (() -> Void)?
    private var generation = 0

    init(enqueue: @escaping Enqueue = { delay, action in
        let work = DispatchWorkItem(block: action)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        return { work.cancel() }
    }) {
        self.enqueue = enqueue
    }

    func cancel() {
        generation += 1
        cancelPending?()
        cancelPending = nil
    }

    func schedule(_ action: @escaping () -> Void) {
        cancel()
        let scheduledGeneration = generation
        cancelPending = enqueue(0.3) { [weak self] in
            guard let self, self.generation == scheduledGeneration else { return }
            self.cancelPending = nil
            self.generation += 1
            action()
        }
    }

    deinit { cancelPending?() }
}
