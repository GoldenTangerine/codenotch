/**
 @name: 更新说明测试
 @Descripttion: 验证更新说明展示、已读记录和界面强调色实时刷新。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-10 10:05:32
 @LastEditTime: 2026-09-10 10:05:32
 @FilePath: Tests/WhatsNewTests.swift
 */
import SwiftUI
import XCTest
@testable import Codenotch

/// What the app says it changed, and when it says it.
final class ReleaseNotesTests: XCTestCase {
    private let note = ReleaseNote(
        version: "9.9.9",
        headline: "Something happened",
        changes: [ReleaseNote.Change(title: "A thing", detail: "It is different now.")]
    )

    private func unseen(in version: String, lastSeen: String?) -> ReleaseNote? {
        ReleaseNotes.unseen(in: version, lastSeen: lastSeen, notes: [note])
    }

    func testItIsShownForAVersionThatHasNotBeenSeen() {
        XCTAssertEqual(unseen(in: "9.9.9", lastSeen: "9.9.8"), note)
    }

    /// A fresh install has seen nothing, so the current version is new to it.
    func testNothingSeenYetCountsAsUnseen() {
        XCTAssertEqual(unseen(in: "9.9.9", lastSeen: nil), note)
    }

    func testItIsNotShownTwiceForTheSameVersion() {
        XCTAssertNil(unseen(in: "9.9.9", lastSeen: "9.9.9"))
    }

    /// Bumping the version without writing a note shows nothing. An empty
    /// dialogue is worse than none.
    func testAVersionWithNothingWrittenShowsNothing() {
        XCTAssertNil(unseen(in: "9.9.10", lastSeen: "9.9.8"))
    }

    // MARK: - What ships

    func testEveryShippedNoteSaysSomething() {
        for note in ReleaseNotes.all {
            XCTAssertFalse(note.version.isEmpty, "a note with no version")
            XCTAssertFalse(note.headline.isEmpty, "\(note.version) has no headline")
            XCTAssertFalse(note.changes.isEmpty, "\(note.version) lists no changes")
            for change in note.changes {
                XCTAssertFalse(change.title.isEmpty, "\(note.version) has a blank change")
            }
        }
    }

    func testNoVersionIsListedTwice() {
        let versions = ReleaseNotes.all.map(\.version)
        XCTAssertEqual(Set(versions).count, versions.count,
                       "two notes claim the same version; only one would ever show")
    }

    /// The version the app is actually built as, so a release cannot ship with
    /// its own notes missing without this saying so.
    func testTheCurrentVersionHasANote() {
        let version = Bundle(for: ReleaseNotesTests.self)
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        guard let version, !version.isEmpty else { return }
        XCTAssertNotNil(ReleaseNotes.note(for: version),
                        "version \(version) ships with no What's New entry")
    }
}

/// Remembering what has been shown.
@MainActor
final class WhatsNewMemoryTests: XCTestCase {
    private func preferences() -> Preferences {
        let name = "WhatsNewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return Preferences(defaults: defaults)
    }

    func testNothingHasBeenSeenOnAFreshInstall() {
        XCTAssertNil(preferences().lastSeenVersion)
    }

    func testWhatHasBeenSeenSurvivesARestart() {
        let name = "WhatsNewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)

        Preferences(defaults: defaults).lastSeenVersion = "1.2.3"
        XCTAssertEqual(Preferences(defaults: defaults).lastSeenVersion, "1.2.3")
    }

    /// A version with nothing written for it is still recorded, or it would
    /// surface later — long after it was current — the first time a note
    /// happened to exist.
    func testAVersionWithNothingToSayIsStillRecorded() {
        let preferences = preferences()
        let controller = WhatsNewWindowController(
            preferences: preferences, version: "0.0.0-no-such-release"
        )
        XCTAssertFalse(controller.showIfNeeded(), "it put a window up for nothing")
        XCTAssertEqual(preferences.lastSeenVersion, "0.0.0-no-such-release")
    }

    /// Nothing is recorded until it has actually been read. Recorded on open, a
    /// crash in between would swallow the one launch it was going to appear on.
    func testItRecordsOnlyOnceItHasBeenDismissed() {
        let preferences = preferences()
        let version = ReleaseNotes.all.first!.version
        let controller = WhatsNewWindowController(preferences: preferences, version: version)

        XCTAssertTrue(controller.showIfNeeded())
        XCTAssertNil(preferences.lastSeenVersion, "it counted as read before it was")

        controller.dismiss()
        XCTAssertEqual(preferences.lastSeenVersion, version)
    }

    /// Dismissing is idempotent.
    ///
    /// Closing by the red button arrives through `windowWillClose`, which calls
    /// this, which closes the window — so a version that did not guard against
    /// re-entry called itself until the stack ran out.
    func testDismissingTwiceIsHarmless() {
        let preferences = preferences()
        let version = ReleaseNotes.all.first!.version
        let controller = WhatsNewWindowController(preferences: preferences, version: version)

        XCTAssertTrue(controller.showIfNeeded())
        controller.dismiss()
        controller.dismiss()
        XCTAssertEqual(preferences.lastSeenVersion, version)
    }

    /// And it does not come back on the next launch.
    func testItDoesNotReturnOnTheNextLaunch() {
        let preferences = preferences()
        let version = ReleaseNotes.all.first!.version

        let first = WhatsNewWindowController(preferences: preferences, version: version)
        XCTAssertTrue(first.showIfNeeded())
        first.dismiss()

        let second = WhatsNewWindowController(preferences: preferences, version: version)
        XCTAssertFalse(second.showIfNeeded(), "it showed the same release twice")
    }
}

@MainActor
final class WhatsNewAccentTests: XCTestCase {
    private func accentPixels(_ choice: AccentColorChoice, in content: NSView) throws -> Int {
        content.layoutSubtreeIfNeeded()
        content.displayIfNeeded()
        let image = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
        content.cacheDisplay(in: content.bounds, to: image)
        let expected = try XCTUnwrap(NSColor(choice.color).usingColorSpace(.deviceRGB))
        let scale = CGFloat(image.pixelsWide) / content.bounds.width
        var count = 0
        // Only the list's bullet gutter: the app icon can contain either colour.
        for x in Int(28 * scale)..<Int(40 * scale) {
            for y in 0..<image.pixelsHigh {
                guard let colour = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      colour.alphaComponent > 0.2 else { continue }
                // AppKit can adjust brightness when compositing the window.
                // Hue distinguishes these accents without depending on that adjustment.
                let hueDistance = abs(colour.hueComponent - expected.hueComponent)
                if colour.saturationComponent > 0.5,
                   min(hueDistance, 1 - hueDistance) < 0.04 {
                    count += 1
                }
            }
        }
        return count
    }

    private func waitForAccent(_ choice: AccentColorChoice, in content: NSView) throws {
        let deadline = Date().addingTimeInterval(1)
        repeat {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            if try accentPixels(choice, in: content) > 0 { return }
        } while Date() < deadline
        XCTFail("The open What's New window did not render \(choice)")
    }

    func testOpenWindowTracksInterfaceAccentAndIgnoresNotchAccent() throws {
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("Requires a display") }
        let name = "WhatsNewAccentTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = Preferences(defaults: defaults)
        preferences.accentColor = .green
        preferences.notchAccentColor = .blue
        let controller = WhatsNewWindowController(
            preferences: preferences, version: try XCTUnwrap(ReleaseNotes.all.first).version
        )
        defer { controller.dismiss() }
        XCTAssertTrue(controller.showIfNeeded())
        let content = try XCTUnwrap(controller.contentViewForTesting)
        content.appearance = NSAppearance(named: .aqua)
        try waitForAccent(.green, in: content)

        preferences.accentColor = .pink
        try waitForAccent(.pink, in: content)
        XCTAssertEqual(try accentPixels(.green, in: content), 0)

        preferences.notchAccentColor = .green
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertTrue(controller.contentViewForTesting === content)
        XCTAssertGreaterThan(try accentPixels(.pink, in: content), 0)
        XCTAssertEqual(try accentPixels(.green, in: content), 0)
    }
}

/// The dialogue itself.
@MainActor
final class WhatsNewRenderTests: XCTestCase {
    private func render(_ note: ReleaseNote) -> NSBitmapImageRep? {
        let view = WhatsNewView(note: note, onContinue: {})
            .frame(width: WhatsNewView.width, height: WhatsNewView.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let image = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: image)
    }

    /// How much of a horizontal band is drawn on.
    ///
    /// Measured in bands rather than over the whole image because the view has
    /// no background of its own — the window supplies that — so most of it is
    /// legitimately transparent, and a total would say nothing.
    private func inked(_ rep: NSBitmapImageRep, from top: CGFloat, to bottom: CGFloat) -> Double {
        var inked = 0, total = 0
        for y in stride(from: Int(top), to: Int(bottom), by: 2) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
                total += 1
                if let colour = rep.colorAt(x: x, y: y), colour.alphaComponent > 0.3 {
                    inked += 1
                }
            }
        }
        return total == 0 ? 0 : Double(inked) / Double(total)
    }

    private func note(changes: Int) -> ReleaseNote {
        ReleaseNote(
            version: "1.0.0",
            headline: "A headline that runs to about the width of the window",
            changes: (0..<changes).map {
                ReleaseNote.Change(
                    title: "Change number \($0)",
                    detail: "A sentence of explanation that is long enough to wrap onto "
                          + "a second line inside a 420pt window."
                )
            }
        )
    }

    func testItDrawsItsHeader() {
        guard let rep = render(note(changes: 2)) else { return XCTFail("nothing rendered") }
        XCTAssertGreaterThan(inked(rep, from: 0, to: 200), 0.02,
                             "the header came out empty")
    }

    /// The list is rendered on its own: a `ScrollView` draws nothing under
    /// `ImageRenderer`, so looking for it inside the dialogue would only ever
    /// prove the renderer's limits.
    func testItDrawsEveryChange() {
        let renderer = ImageRenderer(
            content: WhatsNewChanges(changes: note(changes: 3).changes)
                .frame(width: WhatsNewView.width)
        )
        renderer.scale = 1
        guard let image = renderer.cgImage else { return XCTFail("nothing rendered") }
        let rep = NSBitmapImageRep(cgImage: image)
        XCTAssertGreaterThan(inked(rep, from: 0, to: CGFloat(rep.pixelsHigh)), 0.05,
                             "the changes came out empty")
    }

    /// A longer release makes a taller list — which is what the dialogue has to
    /// scroll.
    func testTheListGrowsWithTheRelease() {
        func height(_ count: Int) -> Int {
            let renderer = ImageRenderer(
                content: WhatsNewChanges(changes: note(changes: count).changes)
                    .frame(width: WhatsNewView.width)
            )
            renderer.scale = 1
            return renderer.cgImage.map { NSBitmapImageRep(cgImage: $0).pixelsHigh } ?? 0
        }
        XCTAssertGreaterThan(height(6), height(2))
    }

    /// **A long release must not push the button off the bottom.**
    ///
    /// The window cannot grow, so a release with a dozen entries has to scroll
    /// inside it. Without that the list runs past the foot of the window and
    /// takes Continue with it — leaving a dialogue with no way out but the red
    /// button.
    func testALongReleaseKeepsItsButton() {
        guard let short = render(note(changes: 2)),
              let long = render(note(changes: 12)) else { return XCTFail("nothing rendered") }

        let foot = WhatsNewView.height - 56
        XCTAssertGreaterThan(inked(short, from: foot, to: WhatsNewView.height), 0.02,
                             "no button on a short release")
        XCTAssertGreaterThan(inked(long, from: foot, to: WhatsNewView.height), 0.02,
                             "a long release pushed Continue off the window")
    }

    /// And neither one grows the window.
    func testTheWindowIsTheSameSizeWhateverTheRelease() {
        guard let short = render(note(changes: 2)),
              let long = render(note(changes: 12)) else { return XCTFail("nothing rendered") }
        XCTAssertEqual(short.pixelsWide, long.pixelsWide)
        XCTAssertEqual(short.pixelsHigh, long.pixelsHigh)
        XCTAssertEqual(short.pixelsHigh, Int(WhatsNewView.height))
    }

    /// A change with no detail is a one-liner, not a blank second line.
    func testAChangeCanBeATitleOnLy() {
        let bare = ReleaseNote(
            version: "1.0.0", headline: "Short",
            changes: [ReleaseNote.Change(title: "One line, nothing more")]
        )
        XCTAssertNotNil(render(bare))
        XCTAssertEqual(bare.changes[0].detail, "")
    }
}
