/**
 @name: 上游同步回归测试
 @Descripttion: 维护 TooltipRenderTests.swift 的项目实现与上游兼容。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-11 15:51:14
 @LastEditTime: 2026-09-11 15:51:14
 @FilePath: Tests/TooltipRenderTests.swift
 */
import XCTest
import SwiftUI
@testable import Codenotch

/// Renders the tooltip with a session in every state.
///
/// Partly a smoke test — a card that fails to lay out fails here rather than on
/// someone's screen — and partly a way to actually look at it: set
/// `TOOLTIP_RENDER_PATH` and the frame is written there.
@MainActor
final class TooltipRenderTests: XCTestCase {
    func testStandaloneTooltipsResolveTheirOwnSecondaryInk() throws {
        let provider = CodeSwitchProvider(providerId: "contrast", providerName: "Supplier", icon: "openai",
            activeRequests: 0, status: "enabled", loading: true, updatedAt: 0, quotas: [], stats: nil)
        let linked = provider.snapshot(platform: CodeSwitchPlatform(platform: "codex", name: "Codex",
            icon: "openai", error: false, providers: [provider]))
        let ordinary = ProviderSnapshot(id: "claude", displayName: "Claude", glyph: .claude,
            fidelity: .official, status: .error("Secondary status message"), windows: [])

        for snapshot in [ordinary, linked] {
            func render(_ style: NotchSurfaceStyle, reduced: Bool = false) throws -> NSBitmapImageRep {
                try contrastBitmap(TooltipCard(snapshot: snapshot, now: Date(timeIntervalSince1970: 1_800_000_000))
                    .environment(\.notchSurfaceStyle, style)
                    .environment(\.codenotchReduceTransparency, reduced)
                    // A stale parent value must not override the card's own surface policy.
                    .environment(\.tooltipSecondaryInk, Palette.textSecondary))
            }
            let solid = try render(.solid)
            let glass = try render(.glass)
            XCTAssertEqual(solid.pixelsWide, glass.pixelsWide)
            XCTAssertEqual(solid.pixelsHigh, glass.pixelsHigh)
            XCTAssertGreaterThan(try grayPixels(in: glass, level: 194),
                                 try grayPixels(in: solid, level: 194) + 20,
                                 "\(snapshot.id): secondary copy did not brighten without NotchRootView")
            for preserved in [try render(.darkGlass), try render(.glass, reduced: true)] {
                XCTAssertGreaterThan(try grayPixels(in: glass, level: 194),
                                     try grayPixels(in: preserved, level: 194) + 20)
            }
        }
    }

    func testDailyBudgetLabelsConsumeTheTooltipInk() throws {
        let source = CodeSwitchQuota(key: "weekly", label: nil, used: 80, total: 200, unlimited: false,
            nextReset: nil, active: true, valueMode: "currency", unit: "USD", extra: nil,
            invalidMessage: nil, displayKind: "progress")
        let budget = CodeSwitchDailyBudget.Reading(source: source, todayUsed: 10, available: 24,
            usedFraction: 0.3, sinceObservation: true)
        func render(_ ink: Color) throws -> NSBitmapImageRep {
            try contrastBitmap(CodeSwitchDailyBudgetRow(budget: budget)
                .frame(width: NotchLayout.cardTextWidth)
                .environment(\.tooltipSecondaryInk, ink))
        }
        let original = try render(Palette.textSecondary)
        let readable = try render(Palette.readableTooltipTextSecondary)
        XCTAssertGreaterThan(try grayPixels(in: readable, level: 194),
                             try grayPixels(in: original, level: 194) + 20)
    }

    private func contrastBitmap<V: View>(_ view: V) throws -> NSBitmapImageRep {
        try XCTSkipIf(NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
                      "Glass text contrast requires system Reduce Transparency to be off")
        var bitmap: NSBitmapImageRep?
        // Pin AppKit too: Palette contains dynamic NSColors, not just SwiftUI colors.
        NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance {
            let renderer = ImageRenderer(content: view
                .environment(\.colorScheme, .dark)
                .environment(\.codenotchReduceTransparency, false)
                .environment(\.codenotchHeadlessGlass, true)
                .padding(20)
                .background(Color.black))
            renderer.scale = 3
            bitmap = renderer.cgImage.map { NSBitmapImageRep(cgImage: $0) }
        }
        return try XCTUnwrap(bitmap)
    }

    private func grayPixels(in bitmap: NSBitmapImageRep, level: Double) throws -> Int {
        var count = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                if abs(color.redComponent * 255 - level) < 2,
                   abs(color.greenComponent * 255 - level) < 2,
                   abs(color.blueComponent * 255 - level) < 2 {
                    count += 1
                }
            }
        }
        return count
    }

    private func session(_ name: String, _ state: AgentSession.State,
                         minutes: Int) -> AgentSession {
        AgentSession(id: name, name: name, detail: "Terminal · usage-notch",
                     state: state, waitingFor: state == .waiting ? "your answer" : nil,
                     since: Date().addingTimeInterval(Double(-minutes) * 60))
    }

    func testUsagePaceFitsTheExistingSummaryLine() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let window = LimitWindow(id: "weekly", label: "Weekly limit", usedFraction: 1,
                                 resetsAt: now.addingTimeInterval(604800), duration: 604800)
        let pace = try XCTUnwrap(window.usagePace(now: now))
        let summary = "\(window.summary) · \(pace.summary)"
        XCTAssertEqual(summary, "100% Used · 0% left · 100% deficit")
        let font = NSFont.systemFont(ofSize: Design.fontSize(capPixels: 18))
        let width = (summary as NSString).size(withAttributes: [.font: font]).width
        XCTAssertLessThanOrEqual(width * 0.85, NotchLayout.cardTextWidth)
    }

    func testTheCardLaysOutEverySessionState() throws {
        let snapshot = ProviderSnapshot(
            id: "claude", displayName: "Claude", glyph: .claude,
            fidelity: .official, status: .ok,
            windows: [LimitWindow(id: "session", label: "Session", usedFraction: 0.47)]
        )
        let activity = ActivitySummary(sessions: [
            session("codenotch-6f", .idle, minutes: 0),
            session("hivinz-web-2f", .busy, minutes: 1),
            session("codenotch-18", .waiting, minutes: 3)
        ])

        let view = TooltipCard(snapshot: snapshot, activity: activity, now: Date())
            .padding(20)
            .background(Color.black)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        let image = try XCTUnwrap(renderer.nsImage)

        // Three sessions of two lines each, under the window rows: a card that
        // silently collapsed would still render, just far too short.
        XCTAssertGreaterThan(image.size.height, NotchLayout.cardWidth * 0.5,
                             "the card laid out far shorter than three sessions need")
        XCTAssertGreaterThan(image.size.width, NotchLayout.cardWidth)

        if let path = ProcessInfo.processInfo.environment["TOOLTIP_RENDER_PATH"] {
            let tiff = try XCTUnwrap(image.tiffRepresentation)
            let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?
                .representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: path))
        }
    }

    func testCodexCardRendersAccountActivity() throws {
        let usage = CodexTokenUsage(
            summary: .init(lifetimeTokens: 280_000, peakDailyTokens: 150_000,
                            longestRunningTurnSeconds: 4020,
                            currentStreakDays: 2, longestStreakDays: 11),
            dailyUsageBuckets: [
                .init(startDate: "2026-08-25", tokens: 48_000),
                .init(startDate: "2026-09-03", tokens: 192_000),
                .init(startDate: "2026-09-08", tokens: 40_000)
            ]
        )
        let snapshot = ProviderSnapshot(
            id: "codex", displayName: "Codex", glyph: .openai,
            fidelity: .official, status: .ok,
            windows: [
                LimitWindow(id: "primary", label: "5h limit", usedFraction: 0),
                LimitWindow(id: "secondary", label: "Weekly limit", usedFraction: 0.28)
            ],
            tokenUsage: usage
        )
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 9))!
        let view = TooltipCard(snapshot: snapshot, now: now)
            .padding(20)
            .background(Color.black)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        let image = try XCTUnwrap(renderer.nsImage)
        XCTAssertGreaterThan(
            image.size.height,
            NotchLayout.cardHeight(windowCount: 2) + NotchLayout.codexChartHeight,
            "the account activity section was not included in the rendered card"
        )

        if let path = ProcessInfo.processInfo.environment["CODEX_TOOLTIP_RENDER_PATH"] {
            let tiff = try XCTUnwrap(image.tiffRepresentation)
            let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?
                .representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: path))
        }
    }

    /// The glass is masked by this one outline, so anything it fails to cover
    /// is a piece of the tooltip left unpainted.
    func testTheSilhouetteIsOneShapeCoveringCardAndTail() {
        for direction in [NotchEdge.TooltipDirection.leading, .trailing, .down, .up] {
            let horizontal = direction == .leading || direction == .trailing
            // The tail is long in the direction it points, whichever that is.
            let tailLength = NotchLayout.tailLength
            let rect = horizontal
                ? CGRect(x: 0, y: 0, width: NotchLayout.cardWidth + tailLength, height: 200)
                : CGRect(x: 0, y: 0, width: NotchLayout.cardWidth, height: 200 + tailLength)

            let path = TooltipSilhouette(direction: direction).path(in: rect)
            XCTAssertFalse(path.isEmpty, "\(direction) produced no outline at all")

            let bounds = path.boundingRect
            XCTAssertEqual(bounds.minX, rect.minX, accuracy: 0.5, "\(direction)")
            XCTAssertEqual(bounds.minY, rect.minY, accuracy: 0.5, "\(direction)")
            XCTAssertEqual(bounds.maxX, rect.maxX, accuracy: 0.5, "\(direction)")
            XCTAssertEqual(bounds.maxY, rect.maxY, accuracy: 0.5, "\(direction)")

            // The middle of the card, then a point just past the card's edge on
            // the tail's centre line: one shape has to hold both.
            let cardCentre: CGPoint
            let insideTail: CGPoint
            switch direction {
            case .leading:
                cardCentre = CGPoint(x: (rect.width - tailLength) / 2, y: rect.midY)
                insideTail = CGPoint(x: rect.width - tailLength + 1, y: rect.midY)
            case .trailing:
                cardCentre = CGPoint(x: tailLength + (rect.width - tailLength) / 2, y: rect.midY)
                insideTail = CGPoint(x: tailLength - 1, y: rect.midY)
            case .down:
                cardCentre = CGPoint(x: rect.midX, y: tailLength + (rect.height - tailLength) / 2)
                insideTail = CGPoint(x: rect.midX, y: tailLength - 1)
            case .up:
                cardCentre = CGPoint(x: rect.midX, y: (rect.height - tailLength) / 2)
                insideTail = CGPoint(x: rect.midX, y: rect.height - tailLength + 1)
            }

            XCTAssertTrue(path.contains(cardCentre), "\(direction) missed the card")
            XCTAssertTrue(path.contains(insideTail), "\(direction) missed the tail")
        }
    }

    /// The tail slides along the card to stay on the cell it points at, and the
    /// glass is masked by this outline — a silhouette that ignored the nudge
    /// would leave the tail unpainted where it actually is.
    func testTheSilhouetteFollowsTheTailsOffset() {
        for direction in [NotchEdge.TooltipDirection.leading, .trailing, .down, .up] {
            let horizontal = direction == .leading || direction == .trailing
            let tailLength = NotchLayout.tailLength
            let rect = horizontal
                ? CGRect(x: 0, y: 0, width: NotchLayout.cardWidth + tailLength, height: 200)
                : CGRect(x: 0, y: 0, width: NotchLayout.cardWidth, height: 200 + tailLength)
            // A whole tail's width, so the centre line the tail used to sit on
            // is now clear of it.
            let nudge = NotchLayout.tailHeight

            let path = TooltipSilhouette(direction: direction, tailOffset: nudge).path(in: rect)

            // Just past the card's edge on the unmoved centre line: a point only
            // the tail can ever cover.
            let wasOnCentre: CGPoint
            switch direction {
            case .leading:  wasOnCentre = CGPoint(x: rect.width - tailLength + 1, y: rect.midY)
            case .trailing: wasOnCentre = CGPoint(x: tailLength - 1, y: rect.midY)
            case .down:     wasOnCentre = CGPoint(x: rect.midX, y: tailLength - 1)
            case .up:       wasOnCentre = CGPoint(x: rect.midX, y: rect.height - tailLength + 1)
            }
            // The offset runs along the card: across the tail's own direction.
            let nowOnCentre = horizontal
                ? CGPoint(x: wasOnCentre.x, y: wasOnCentre.y + nudge)
                : CGPoint(x: wasOnCentre.x + nudge, y: wasOnCentre.y)

            XCTAssertTrue(path.contains(nowOnCentre),
                          "\(direction): the outline did not follow the tail's offset")
            XCTAssertFalse(path.contains(wasOnCentre),
                           "\(direction): the outline left a tail behind where the tail no longer is")
        }
    }
}
