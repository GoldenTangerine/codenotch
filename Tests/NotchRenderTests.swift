/**
 @name: 显示栏渲染测试
 @Descripttion: 验证显示栏绘制、编辑配色和窗口交互行为。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-10 10:05:32
 @LastEditTime: 2026-09-10 10:05:32
 @FilePath: Tests/NotchRenderTests.swift
 */
import SwiftUI
import XCTest
import Combine
@testable import Codenotch

/// The layout maths can be right in every unit and still put nothing on the
/// screen. These render the real view and count the pixels it actually paints,
/// which is the one thing the arithmetic tests cannot tell you.
@MainActor
final class NotchRenderTests: XCTestCase {
    func testPositionGuidesRemainVisibleOnOppositeThemeWallpapers() throws {
        let size = CGSize(width: 640, height: 360)
        for scheme in [ColorScheme.light, .dark] {
            for whiteBackground in [false, true] {
                for scale: CGFloat in [0.75, 1.5] {
                    let length = 140 * scale
                    let depth = 44 * scale
                    let frames: [NotchEdge: CGRect] = [
                        .left: CGRect(x: 0, y: (size.height - length) / 2, width: depth, height: length),
                        .right: CGRect(x: size.width - depth, y: (size.height - length) / 2, width: depth, height: length),
                        .top: CGRect(x: (size.width - length) / 2, y: 0, width: length, height: depth),
                        .bottom: CGRect(x: (size.width - length) / 2, y: size.height - depth, width: length, height: depth)
                    ]
                    let renderer = ImageRenderer(content: EdgeDropZones(target: .bottom, size: size,
                        frames: frames, hardwareNotch: nil, scale: scale, accentColor: .cyan)
                        .background(whiteBackground ? Color.white : Color.black)
                        .environment(\.colorScheme, scheme))
                    renderer.scale = 1
                    let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
                    for edge in NotchEdge.allCases {
                        let frame = try XCTUnwrap(frames[edge])
                        var contrastPixels = 0
                        var accentPixels = 0
                        for x in Int(frame.minX.rounded(.up))..<Int(frame.maxX.rounded(.down)) {
                            for y in Int(frame.minY.rounded(.up))..<Int(frame.maxY.rounded(.down)) {
                                let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                                let low = min(color.redComponent, color.greenComponent, color.blueComponent)
                                let high = max(color.redComponent, color.greenComponent, color.blueComponent)
                                if whiteBackground ? low < 0.6 : high > 0.4 { contrastPixels += 1 }
                                if high - low > 0.3 { accentPixels += 1 }
                            }
                        }
                        XCTAssertGreaterThan(contrastPixels, 10, "Guide must contrast with the wallpaper: \(edge)")
                        if edge == .bottom { XCTAssertGreaterThan(accentPixels, 10) }
                        else { XCTAssertEqual(accentPixels, 0) }
                    }
                }
            }
        }
    }

    private func model(edge: NotchEdge, cells: Int = 4) -> NotchViewModel {
        let model = NotchViewModel()
        model.edge = edge
        model.isExpanded = true
        // A saturated accent, not the default `.system`.
        //
        // `colouredFraction` finds an arc by its saturation, and `.system`
        // resolves to `NSColor.controlAccentColor` — the *Mac's* accent
        // colour. On a machine set to Graphite the arcs render grey and the
        // measurement reads zero whether the ring was drawn or not, so a
        // developer's System Settings decided whether the suite passed.
        model.accentColor = .blue
        // `ImageRenderer` has no desktop behind it to refract; these tests
        // measure the outline, which both styles share.
        model.surfaceStyle = .solid
        model.snapshots = (0..<cells).map { index in
            ProviderSnapshot(
                id: "p\(index)", displayName: "P\(index)", glyph: .claude,
                fidelity: .official, status: .ok,
                windows: [LimitWindow(id: "w", label: "Session", usedFraction: 0.4)],
                headlineID: "w"
            )
        }
        return model
    }

    private func render(_ model: NotchViewModel, reduceTransparency: Bool = false)
        -> NSBitmapImageRep? {
        let size = model.panelSize
        let renderer = ImageRenderer(
            content: NotchRootView(model: model)
                .frame(width: size.width, height: size.height)
                .environment(\.codenotchReduceTransparency, reduceTransparency)
                // Dark, the scheme the solid style pins its own panel to.
                //
                // `Palette.ringTrack` and its neighbours became translucent
                // and resolve against the scheme they are drawn in. An
                // `ImageRenderer` with none defaults to light, where the track
                // is black at 16% over a black body — invisible — so
                // `greyFraction` read zero whether it was drawn or not.
                .environment(\.colorScheme, .dark)
        )
        renderer.scale = 1
        guard let image = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: image)
    }

    /// Fraction of sampled pixels that are painted at all.
    private func inkedFraction(_ rep: NSBitmapImageRep) -> Double {
        var inked = 0, total = 0
        for x in stride(from: 0, to: rep.pixelsWide, by: 3) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: 3) {
                total += 1
                if let colour = rep.colorAt(x: x, y: y), colour.alphaComponent > 0.5 {
                    inked += 1
                }
            }
        }
        return total == 0 ? 0 : Double(inked) / Double(total)
    }

    func testTheNotchPaintsSomethingOnEveryEdge() {
        for edge in NotchEdge.allCases {
            guard let rep = render(model(edge: edge)) else {
                XCTFail("\(edge): the view produced no image at all")
                continue
            }
            XCTAssertGreaterThan(
                inkedFraction(rep), 0.02,
                "\(edge): the panel came out blank — the notch drew nothing"
            )
        }
    }

    func testCustomPlacementPaintsAtTheHitRegionOnEveryEdge() throws {
        for edge in NotchEdge.allCases {
            for scale: CGFloat in [0.75, 1.25] {
                let model = model(edge: edge)
                model.sizeScale = scale
                let place = NotchPlacement(edge: edge, panelSize: model.panelSize)
                let length = model.shapeLength * scale
                for leading in [CGFloat(0), place.panelLength - length] {
                    model.positionedLeading = leading
                    let rep = try XCTUnwrap(render(model))
                    let painted = (0..<Int(place.panelLength)).filter { along in
                        let point = place.point(along: CGFloat(along),
                                                across: model.notchDepth * scale / 2)
                        return (rep.colorAt(x: Int(point.x), y: Int(point.y))?.alphaComponent ?? 0) > 0.5
                    }
                    let first = CGFloat(try XCTUnwrap(painted.first))
                    let last = CGFloat(try XCTUnwrap(painted.last))
                    // 弧形端部会缩进；校验轮廓中心跟随热区且绘制不越界。
                    XCTAssertEqual((first + last) / 2, leading + length / 2, accuracy: 2,
                                   "\(edge), scale \(scale): painted centre must follow the hit region")
                    XCTAssertGreaterThanOrEqual(first, leading - 1)
                    XCTAssertLessThanOrEqual(last, leading + length + 1)
                }
            }
        }
    }

    func testExpandedBarDoesNotPaintControlsOutsideItsBody() throws {
        for edge in NotchEdge.allCases {
            let model = model(edge: edge)
            let rep = try XCTUnwrap(render(model))
            let place = NotchPlacement(edge: edge, panelSize: model.panelSize)
            for x in 0..<rep.pixelsWide {
                for y in 0..<rep.pixelsHigh {
                    let point = CGPoint(x: x, y: y)
                    guard place.across(of: point) > model.notchDepth * model.sizeScale + 2 else { continue }
                    XCTAssertLessThan(rep.colorAt(x: x, y: y)?.alphaComponent ?? 0, 0.1)
                }
            }
        }
    }

    func testPositionEditingOutlineUsesTheNotchAccent() throws {
        let model = model(edge: .right, cells: 0)
        model.isEditingPosition = true

        func colouredPixels(_ choice: AccentColorChoice, in image: NSBitmapImageRep) throws -> Int {
            let expected = try XCTUnwrap(NSColor(choice.color).usingColorSpace(.deviceRGB))
            var count = 0
            for x in 0..<image.pixelsWide {
                for y in 0..<image.pixelsHigh {
                    guard let colour = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                          colour.alphaComponent > 0.2 else { continue }
                    let hueDistance = abs(colour.hueComponent - expected.hueComponent)
                    if colour.saturationComponent > 0.5,
                       min(hueDistance, 1 - hueDistance) < 0.04 {
                        count += 1
                    }
                }
            }
            return count
        }

        model.accentColor = .pink
        let pink = try XCTUnwrap(render(model))
        XCTAssertGreaterThan(try colouredPixels(.pink, in: pink), 0)

        model.accentColor = .green
        let green = try XCTUnwrap(render(model))
        XCTAssertGreaterThan(try colouredPixels(.green, in: green), 0)
        XCTAssertEqual(try colouredPixels(.pink, in: green), 0)
    }

    /// The weekly ring has to actually appear, and only when asked for.
    ///
    /// Counted by colour rather than by ink: the arcs are drawn on top of the
    /// notch's own black, which is already opaque, so `inkedFraction` cannot
    /// see them at all — it answers the same number to three decimal places
    /// whether the ring is there or not. Saturation is what separates an arc
    /// from the body behind it and the grey track beside it.
    func testTheWeeklyRingPaintsOnlyWhenSwitchedOn() {
        func colour(_ ring: WeeklyRing) -> Double {
            let model = model(edge: .right)
            model.weeklyRing = ring
            model.snapshots = model.snapshots.map { snapshot in
                ProviderSnapshot(
                    id: snapshot.id, displayName: snapshot.displayName,
                    glyph: snapshot.glyph, fidelity: snapshot.fidelity,
                    status: snapshot.status,
                    windows: snapshot.windows + [
                        LimitWindow(id: "weekly_all", label: "All models", usedFraction: 0.9)
                    ],
                    headlineID: snapshot.headlineID,
                    weeklyID: "weekly_all"
                )
            }
            guard let rep = render(model) else { return -1 }
            return colouredFraction(rep)
        }

        let off = colour(.off)
        XCTAssertGreaterThan(off, 0, "the headline arc is missing too — this measures nothing")
        XCTAssertGreaterThan(colour(.inside), off, "inside painted no arc")
        XCTAssertGreaterThan(colour(.outside), off, "outside painted no arc")
    }

    /// Hiding the move handle takes its arc off the notch, and leaves nothing
    /// behind that can still be hovered or pressed — an invisible control that
    /// starts a move is worse than a visible one.
    func testAHiddenMoveHandleIsNeitherDrawnNorPressable() throws {
        let shown = model(edge: .right)
        shown.showsMoveHandle = true
        let point = try XCTUnwrap(shown.moveHandlePoints.first)
        XCTAssertTrue(shown.isOnMoveHandle(along: point.x, across: point.y))

        let hidden = model(edge: .right)
        hidden.showsMoveHandle = false
        XCTAssertTrue(hidden.moveHandlePoints.isEmpty)
        XCTAssertFalse(hidden.isOnMoveHandle(along: point.x, across: point.y),
                       "a hidden handle still took the press")

        let withHandle = inkedFraction(try XCTUnwrap(render(shown)))
        let withoutHandle = inkedFraction(try XCTUnwrap(render(hidden)))
        XCTAssertLessThan(withoutHandle, withHandle, "the handle's arc was still drawn")
    }

    /// A week nobody has spent yet still has to be visible.
    ///
    /// At 0% the arc has no length, so without a track behind it the ring is
    /// indistinguishable from the feature being missing — which is exactly how
    /// Codex read when its week opened empty.
    func testAnEmptyWeeklyRingStillDrawsItsTrack() {
        func ink(_ ring: WeeklyRing) -> Double {
            let model = model(edge: .right)
            model.weeklyRing = ring
            model.snapshots = model.snapshots.map { snapshot in
                ProviderSnapshot(
                    id: snapshot.id, displayName: snapshot.displayName,
                    glyph: snapshot.glyph, fidelity: snapshot.fidelity,
                    status: snapshot.status,
                    // Nothing used yet: the arc is zero length, the track is all
                    // there is to see.
                    windows: snapshot.windows + [
                        LimitWindow(id: "weekly_all", label: "All models", usedFraction: 0)
                    ],
                    headlineID: snapshot.headlineID,
                    weeklyID: "weekly_all"
                )
            }
            guard let rep = render(model) else { return -1 }
            return greyFraction(rep)
        }

        XCTAssertGreaterThan(ink(.outside), ink(.off),
                             "an empty week drew nothing at all")
    }

    /// Fraction of sampled pixels that are the ring track's own grey — the way
    /// to see a track, which carries no hue and so is invisible to
    /// `colouredFraction`.
    private func greyFraction(_ rep: NSBitmapImageRep) -> Double {
        var grey = 0, total = 0
        for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
                total += 1
                guard let colour = rep.colorAt(x: x, y: y), colour.alphaComponent > 0.5,
                      let rgb = colour.usingColorSpace(.sRGB) else { continue }
                let channels = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
                let neutral = (channels.max()! - channels.min()!) < 0.06
                if neutral, channels.max()! > 0.10, channels.max()! < 0.45 { grey += 1 }
            }
        }
        return total == 0 ? 0 : Double(grey) / Double(total)
    }

    /// Fraction of sampled pixels carrying a hue — an arc rather than the black
    /// body, the grey track or white type.
    private func colouredFraction(_ rep: NSBitmapImageRep) -> Double {
        var coloured = 0, total = 0
        for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
                total += 1
                guard let colour = rep.colorAt(x: x, y: y), colour.alphaComponent > 0.5,
                      let rgb = colour.usingColorSpace(.sRGB) else { continue }
                let channels = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
                if (channels.max()! - channels.min()!) > 0.15 { coloured += 1 }
            }
        }
        return total == 0 ? 0 : Double(coloured) / Double(total)
    }

    /// And it paints it against the bezel, not somewhere in the middle of the
    /// transparent panel.
    func testTheNotchPaintsAgainstTheBezelOnEveryEdge() {
        for edge in NotchEdge.allCases {
            let m = model(edge: edge)
            guard let rep = render(m) else {
                XCTFail("\(edge): no image")
                continue
            }
            let place = NotchPlacement(edge: edge, panelSize: m.panelSize)
            // The middle of the stack, one point in from the bezel: solid body.
            let onBezel = place.point(
                along: m.slack + m.shapeLength / 2, across: 1
            )
            let colour = rep.colorAt(
                x: min(rep.pixelsWide - 1, max(0, Int(onBezel.x))),
                y: min(rep.pixelsHigh - 1, max(0, Int(onBezel.y)))
            )
            XCTAssertEqual(
                colour?.alphaComponent ?? 0, 1, accuracy: 0.01,
                "\(edge): nothing painted where the notch meets the bezel"
            )
        }
    }

    /// The orb has to stay attached to the notch at every size.
    ///
    /// `position` hands back a view the size of the whole panel, so a scale
    /// applied *after* it scales that layer about the panel's centre and slides
    /// the orb away by a share of the panel — the arc left floating off the
    /// corner it is drawn to hug. Arithmetic cannot see that: the numbers going
    /// in were right and the modifier order was not, so this looks at the
    /// pixels instead.
    func testNothingIsPaintedBeyondTheNotchAndItsOrbAtAnySize() {
        for size in NotchSize.allCases {
            let m = model(edge: .right)
            m.showsSettingsHandle = true
            m.showsMoveHandle = true
            m.sizeScale = size.scale
            guard let rep = render(m) else {
                XCTFail("\(size.rawValue): no image")
                continue
            }
            let place = NotchPlacement(edge: .right, panelSize: m.panelSize)
            let scale = size.scale
            // What the notch and the orb legitimately reach, derived rather
            // than guessed, plus a point for the stroke's own width.
            let reach = m.orbArcRadius * scale + NotchLayout.orbStroke
            let deepest = max(m.notchDepth * scale, m.orbInset * scale + reach)
            let furthest = m.slack + max(m.shapeLength, m.orbAlong) * scale + reach
            let nearest = m.slack - reach

            var maxAcross = 0.0, maxAlong = -Double.infinity, minAlong = Double.infinity
            for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
                for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
                    guard let colour = rep.colorAt(x: x, y: y),
                          colour.alphaComponent > 0.5 else { continue }
                    let point = CGPoint(x: x, y: y)
                    maxAcross = max(maxAcross, place.across(of: point))
                    maxAlong = max(maxAlong, place.along(of: point))
                    minAlong = min(minAlong, place.along(of: point))
                }
            }

            XCTAssertLessThanOrEqual(maxAcross, deepest + 1,
                                     "\(size.rawValue): something is painted \(maxAcross)pt in "
                                     + "from the bezel, past the \(deepest)pt the notch and orb reach")
            XCTAssertLessThanOrEqual(maxAlong, furthest + 1,
                                     "\(size.rawValue): something is painted past the far end")
            XCTAssertGreaterThanOrEqual(minAlong, nearest - 1,
                                        "\(size.rawValue): something is painted before the near end")
        }
    }

    /// The glass style reaches the notch whether it is open or closed, as requested.
    func testTheFoldedPillIsTransparentInTheGlassStyle() {
        for edge in NotchEdge.allCases {
            let m = model(edge: edge)
            m.surfaceStyle = .glass
            m.isExpanded = false
            guard let rep = render(m) else {
                XCTFail("\(edge): no image")
                continue
            }
            let place = NotchPlacement(edge: edge, panelSize: m.panelSize)
            // The same centre line the expanded body is probed on: folded or
            // open, the shape is centred on it.
            let onBezel = place.point(
                along: m.slack + m.shapeLength / 2, across: 1
            )
            let colour = rep.colorAt(
                x: min(rep.pixelsWide - 1, max(0, Int(onBezel.x))),
                y: min(rep.pixelsHigh - 1, max(0, Int(onBezel.y)))
            )
            XCTAssertEqual(
                colour?.alphaComponent ?? 1, 0, accuracy: 0.01,
                "\(edge): the folded pill is opaque in the glass style"
            )
        }
    }

    /// Reduce transparency wins over the chosen style: the open notch is
    /// painted solid black even when the preference says glass, the way the
    /// Settings window prefers an opaque fill to its own translucent chrome.
    func testReduceTransparencyPaintsTheGlassStyleSolid() {
        for edge in NotchEdge.allCases {
            let m = model(edge: edge)
            m.surfaceStyle = .glass
            guard let rep = render(m, reduceTransparency: true) else {
                XCTFail("\(edge): no image")
                continue
            }
            let place = NotchPlacement(edge: edge, panelSize: m.panelSize)
            let onBezel = place.point(
                along: m.slack + m.shapeLength / 2, across: 1
            )
            let colour = rep.colorAt(
                x: min(rep.pixelsWide - 1, max(0, Int(onBezel.x))),
                y: min(rep.pixelsHigh - 1, max(0, Int(onBezel.y)))
            )
            XCTAssertEqual(
                colour?.alphaComponent ?? 0, 1, accuracy: 0.01,
                "\(edge): the body is see-through with Reduce transparency on"
            )
            XCTAssertLessThan(
                colour?.brightnessComponent ?? 1, 0.05,
                "\(edge): the body is not black with Reduce transparency on"
            )
        }
    }
}

/// The panel's size is worked out by `NotchGeometry` and by nobody else.
///
/// It was not. Set an `NSHostingView` as a window's `contentView` and SwiftUI
/// gets a say in the window's frame: it reports the content's *ideal* size, and
/// a `GeometryReader` root — which is what this notch is — has an ideal size of
/// 10x10. On the side edges that never surfaced. Turn the panel horizontal and
/// AppKit began walking the window down toward it in steps of its own choosing,
/// 522pt of height to 266 to 10 to 0, until the window was zero-height, nothing
/// was drawn, and the constraint pass gave up and threw — killing the app.
///
/// The fix is to take the channel away rather than to fight it: a plain
/// container view is the `contentView`, and the hosting view lives inside it
/// held by an autoresizing mask. SwiftUI then has no window to talk to about
/// size, and the frame is only ever the one we computed.
@MainActor
final class PanelSizingIntegrityTests: XCTestCase {
    func testSwiftUIIsNotThePanelsContentView() {
        let controller = NotchWindowController()
        controller.show()
        defer { controller.stop() }

        let content = controller.panelContentViewForTesting
        XCTAssertNotNil(content)
        XCTAssertFalse(
            content is NSHostingView<NotchRootView>,
            "the hosting view is the content view, so SwiftUI can resize the window"
        )
    }

    /// And it still fills the panel, however the panel is later re-framed.
    func testTheHostingViewTracksThePanelWhenItIsReFramed() {
        let controller = NotchWindowController()
        controller.show()
        defer { controller.stop() }

        controller.apply(edge: .top)
        controller.relocate(cellCount: 4)

        guard let content = controller.panelContentViewForTesting,
              let hosting = content.subviews.first else {
            return XCTFail("no hosting view inside the container")
        }
        XCTAssertEqual(hosting.frame.size, content.bounds.size,
                       "the hosting view stopped filling the panel after a re-frame")
    }

    /// The solid style is the frame's white-on-black, and a Mac in light mode
    /// must not be able to turn it into black-on-white. Glass is the opposite
    /// bargain: no appearance of ours, so Appearance settings decide.
    func testTheSolidStyleForcesTheDarkAppearance() {
        let controller = NotchWindowController()
        controller.model.surfaceStyle = .solid
        controller.show()
        defer { controller.stop() }

        guard let window = controller.panelContentViewForTesting?.window else {
            return XCTFail("no panel")
        }
        XCTAssertEqual(window.appearance?.name, .darkAqua,
                       "the solid style left the panel following the Mac's appearance")

        controller.model.surfaceStyle = .glass
        // Only where glass is what actually gets painted: below macOS 26, and
        // with Reduce transparency on, the glass style resolves to the solid
        // one and the panel keeps its dark appearance on purpose.
        if NotchSurfaceStyle.glassAvailable,
           !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            XCTAssertNil(window.appearance,
                         "the glass style pinned an appearance instead of inheriting one")
        }
    }

    /// Reduce transparency means "no see-through chrome", and the window has to
    /// know: the light palette resolved against a black surface would be
    /// unreadable. Pure function, so this holds whatever the test Mac's own
    /// accessibility settings are.
    func testReduceTransparencyForcesTheDarkAppearance() {
        XCTAssertEqual(
            NotchSurfaceStyle.glass.panelAppearance(reduceTransparency: true)?.name, .darkAqua,
            "Reduce transparency left the panel following the Mac's appearance"
        )
        if NotchSurfaceStyle.glassAvailable {
            XCTAssertNil(
                NotchSurfaceStyle.glass.panelAppearance(reduceTransparency: false),
                "the glass style pinned an appearance instead of inheriting one"
            )
        }
        XCTAssertEqual(
            NotchSurfaceStyle.solid.panelAppearance(reduceTransparency: false)?.name, .darkAqua,
            "the solid style left the panel following the Mac's appearance"
        )
    }
}

/// The panel is a hole everywhere except its own chrome. That is the whole
/// bargain of a window that sits over everything you are working in.
@MainActor
final class ClickThroughTests: XCTestCase {
    private struct HandleScreen: ScreenDescribing {
        let frameValue = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let visibleFrameValue = CGRect(x: 0, y: 24, width: 1440, height: 838)
        let hardwareNotch: HardwareNotch? = HardwareNotch(width: 220, height: 38)
    }

    private func click(_ point: CGPoint, in panel: NSWindow) throws {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: panel.windowNumber, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1))
            panel.sendEvent(event)
        }
    }

    func testIndependentHandlesLeaveTheHardwareNotchGapTransparent() throws {
        let controller = NotchWindowController()
        controller.model.edge = .top
        controller.model.snapshots = Array(Fixtures.snapshots().prefix(4))
        controller.show()
        defer { controller.stop() }
        let model = controller.model
        model.adopt(screen: HandleScreen())
        let content = try XCTUnwrap(controller.panelContentViewForTesting)
        let panel = try XCTUnwrap(content.window)
        let host = try XCTUnwrap(content.subviews.first as? NotchHostingView<NotchRootView>)
        var opens = 0
        var refreshes = 0
        controller.onOpenSettings = { opens += 1 }
        model.onOpenSettings = { opens += 1 }
        controller.onRefreshProvider = { _ in refreshes += 1 }
        // Keep the synthetic screen fixed: yielding would deliver real screen notifications.
        for settings in [true, false] {
            for move in [true, false] {
                model.showsSettingsHandle = settings
                model.showsMoveHandle = move
                controller.apply(.alwaysShow)
                let placement = NotchPlacement(edge: .top, panelSize: panel.frame.size)
                let gap = placement.point(along: model.slack + model.shapeLength / 2,
                                          across: model.notchDepth + 10)
                let gear = placement.point(along: model.slack + model.orbAlong, across: model.orbInset)
                let mover = placement.point(along: model.slack + model.moveAlong, across: model.orbInset)
                for (point, enabled) in [(gear, settings), (mover, move), (gap, false)] {
                    XCTAssertEqual(host.interactiveRects.contains { $0.contains(point) }, enabled)
                    XCTAssertEqual(content.hitTest(CGPoint(x: point.x, y: panel.frame.height - point.y)) != nil,
                                   enabled)
                }
                let before = opens
                try click(CGPoint(x: gear.x, y: panel.frame.height - gear.y), in: panel)
                XCTAssertEqual(opens - before, settings ? 1 : 0)
                let pinned = model.isPinned
                try click(CGPoint(x: gap.x, y: panel.frame.height - gap.y), in: panel)
                XCTAssertEqual(opens - before, settings ? 1 : 0)
                XCTAssertEqual(model.isPinned, pinned)
                XCTAssertEqual(refreshes, 0)
            }
        }
    }

    func testTransparentHandleGapDoesNotPreventFullScreenFolding() throws {
        var pointer = CGPoint.zero
        let controller = NotchWindowController(mouseLocation: { pointer })
        controller.model.edge = .top
        controller.model.snapshots = Array(Fixtures.snapshots().prefix(4))
        controller.show()
        defer { controller.stop() }
        let model = controller.model
        model.adopt(screen: HandleScreen())
        model.showsSettingsHandle = true
        model.showsMoveHandle = true
        controller.apply(.alwaysShow)
        let frame = try XCTUnwrap(controller.panelFrameForTesting)
        pointer = CGPoint(x: frame.minX + model.slack + model.shapeLength / 2,
                          y: frame.maxY - model.notchDepth - 10)
        controller.isFullScreenActive = { true }
        controller.handleActiveSpaceOrAppChange()
        XCTAssertFalse(model.isExpanded)
    }

    func testSettingsButtonOpensSettingsAndReleasesHiddenHitRegions() throws {
        for edge in NotchEdge.allCases {
            for scale: CGFloat in [0.75, 1, 1.5] {
                let controller = NotchWindowController()
                controller.model.edge = edge
                controller.model.sizeScale = scale
                controller.model.snapshots = Array(Fixtures.snapshots().prefix(2))
                var opens = 0
                var refreshes = 0
                controller.onOpenSettings = { opens += 1 }
                controller.model.onOpenSettings = { opens += 1 }
                controller.onRefreshProvider = { _ in refreshes += 1 }
                controller.show()
                defer { controller.stop() }
                controller.model.isExpanded = true
                controller.apply(showsSettingsHandle: true)
                let model = controller.model
                let frame = try XCTUnwrap(controller.panelFrameForTesting)
                let content = try XCTUnwrap(controller.panelContentViewForTesting)
                let host = try XCTUnwrap(content.subviews.first as? NotchHostingView<NotchRootView>)
                let point = NotchPlacement(edge: edge, panelSize: model.panelSize).point(
                    along: model.slack + model.orbAlong * scale, across: model.orbInset * scale)
                XCTAssertTrue(host.interactiveRects.contains { $0.contains(point) })
                let panel = try XCTUnwrap(content.window)
                try click(CGPoint(x: point.x, y: frame.height - point.y), in: panel)
                XCTAssertEqual(opens, 1)
                XCTAssertEqual(refreshes, 0)
                controller.apply(showsSettingsHandle: false)
                XCTAssertTrue(model.orbHandlePoints.isEmpty)
                XCTAssertFalse(host.interactiveRects.contains { $0.contains(point) })
                try click(CGPoint(x: point.x, y: frame.height - point.y), in: panel)
                XCTAssertEqual(opens, 1)
            }
        }
    }

    func testScaledMoveHandleAcceptsOuterClicksAndReleasesThemWhenHidden() throws {
        for edge in NotchEdge.allCases {
            let controller = NotchWindowController()
            controller.model.edge = edge
            controller.model.sizeScale = 1.5
            controller.model.snapshots = Array(Fixtures.snapshots().prefix(2))
            controller.show()
            defer { controller.stop() }
            controller.model.isExpanded = true
            controller.apply(showsMoveHandle: true)
            let content = try XCTUnwrap(controller.panelContentViewForTesting)
            let host = try XCTUnwrap(content.subviews.first as? NotchHostingView<NotchRootView>)
            let model = controller.model
            let point = NotchPlacement(edge: edge, panelSize: model.panelSize).point(
                along: model.slack + model.moveAlong * model.sizeScale - 32,
                across: model.orbInset * model.sizeScale)
            XCTAssertTrue(host.interactiveRects.contains { $0.contains(point) })
            XCTAssertNotNil(content.hitTest(CGPoint(x: point.x, y: content.bounds.height - point.y)))
            controller.apply(showsMoveHandle: false)
            XCTAssertFalse(host.interactiveRects.contains { $0.contains(point) })
            XCTAssertNil(content.hitTest(CGPoint(x: point.x, y: content.bounds.height - point.y)))
        }
    }

    private func shownController() -> NotchWindowController {
        let controller = NotchWindowController()
        controller.show()
        return controller
    }

    /// Wrapping the hosting view in a container must not reintroduce a target
    /// where there was a hole: a plain `NSView` answers `hitTest` with *itself*
    /// for any point inside its bounds, which would make the entire panel — most
    /// of it empty space reserved for the tooltip — swallow clicks meant for
    /// whatever is underneath.
    func testThePanelIsAHoleAwayFromItsChrome() {
        let controller = shownController()
        defer { controller.stop() }
        guard let content = controller.panelContentViewForTesting else {
            return XCTFail("no content view")
        }
        // The far corner from the notch: reserved for the tooltip, and empty.
        let empty = CGPoint(x: content.bounds.minX + 2, y: content.bounds.midY)
        XCTAssertNil(content.hitTest(empty),
                     "the panel answered a click in its transparent margin")
    }

    /// The container itself is never an answer. Whether a given point is live
    /// is the hosting view's decision, made against `interactiveRects`; the
    /// container only forwards the question, so a point it claimed for itself
    /// would be a target nobody asked for.
    func testTheContainerNeverAnswersForItself() {
        let controller = shownController()
        defer { controller.stop() }
        guard let content = controller.panelContentViewForTesting else {
            return XCTFail("no content view")
        }
        for x in stride(from: content.bounds.minX, to: content.bounds.maxX, by: 40) {
            for y in stride(from: content.bounds.minY, to: content.bounds.maxY, by: 40) {
                XCTAssertFalse(content.hitTest(CGPoint(x: x, y: y)) === content,
                               "the container claimed (\(x), \(y)) for itself")
            }
        }
    }
}

/// Changing the placement moves the panel, turns the shape on its side and
/// relays the whole stack — all at once. Done in view that is a jump no
/// animation can smooth over, so it goes out where it was, crosses while there
/// is nothing to see, and comes back where it now is.
@MainActor
final class EdgeCrossfadeTests: XCTestCase {
    private func pump(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    func testTheNotchFadesOutBeforeItMoves() {
        let controller = NotchWindowController()
        controller.show()
        defer { controller.stop() }

        let before = controller.panelFrameForTesting
        controller.apply(edge: .top)
        pump(0.08)

        XCTAssertLessThan(controller.panelAlphaForTesting, 1,
                          "the notch was still on screen while it moved")
        XCTAssertEqual(controller.panelFrameForTesting, before,
                       "the panel jumped before it had faded")
    }

    func testItComesBackOnTheNewEdgeAtFullStrength() {
        let controller = NotchWindowController()
        controller.show()
        defer { controller.stop() }

        controller.apply(edge: .bottom)
        pump(1.0)

        XCTAssertEqual(controller.model.edge, .bottom)
        XCTAssertEqual(controller.panelAlphaForTesting, 1, accuracy: 0.01,
                       "the notch never came back")
        guard let screen = NotchGeometry.preferredScreen(from: NSScreen.screens) else { return }
        XCTAssertEqual(controller.panelFrameForTesting?.minY ?? -1,
                       screen.frame.minY, accuracy: 1,
                       "it did not end up on the edge it was sent to")
    }

    /// Clicking through the picker quickly must not let an earlier move land
    /// after a later one.
    func testOnlyTheLastEdgeAskedForWins() {
        let controller = NotchWindowController()
        controller.show()
        defer { controller.stop() }

        controller.apply(edge: .top)
        pump(0.04)
        controller.apply(edge: .left)
        pump(1.0)

        XCTAssertEqual(controller.model.edge, .left)
        XCTAssertEqual(controller.panelAlphaForTesting, 1, accuracy: 0.01)
    }

    /// Asking for the edge it is already on is not a move.
    func testAskingForTheSameEdgeDoesNothing() {
        let controller = NotchWindowController()
        controller.show()
        defer { controller.stop() }

        controller.apply(edge: controller.model.edge)
        pump(0.08)
        XCTAssertEqual(controller.panelAlphaForTesting, 1,
                       "it faded for a move it was not making")
    }
}

/// Arriving at the new edge should look like the notch opening, not like a bar
/// appearing at full size.
@MainActor
final class EdgeArrivalTests: XCTestCase {
    private func pump(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func openController() -> NotchWindowController {
        // Keep the runner's real pointer from opening or folding the notch during arrival.
        let controller = NotchWindowController(mouseLocation: { CGPoint(x: -1_000_000, y: -1_000_000) })
        controller.show()
        controller.model.snapshots = (0..<3).map { index in
            ProviderSnapshot(id: "p\(index)", displayName: "P", glyph: .claude,
                             fidelity: .official, status: .ok, windows: [])
        }
        controller.model.isExpanded = true
        return controller
    }

    /// Waits for something to become true rather than for a length of time —
    /// the crossing's timings are AppKit's to keep, not ours to predict.
    @discardableResult
    private func wait(upTo seconds: TimeInterval = 3,
                      for condition: () -> Bool) -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + seconds
        while !condition(), ProcessInfo.processInfo.systemUptime < deadline {
            pump(0.02)
        }
        return condition()
    }

    /// It lands folded and *then* opens — the same unfold hovering uses.
    ///
    /// The two have to happen in separate turns or SwiftUI coalesces them: the
    /// value goes shut-to-open inside one update, nothing interpolates, and the
    /// notch simply appears at full size having animated nothing.
    func testItLandsFoldedAndThenOpens() throws {
        try XCTSkipIf(NSUserName() == "runner", "Animation timing is flaky on headless CI environments")
        let controller = openController()
        defer { controller.stop() }

        let landed = expectation(description: "landed folded at full strength on a later turn")
        let opened = expectation(description: "opened after landing")
        var sawFold = false
        var landedOnLaterTurn = false
        // Record the transition itself: polling can miss the 50 ms arrival beat on a busy runner.
        let observation = controller.model.$isExpanded.dropFirst().sink { expanded in
            guard controller.model.edge == .top else { return }
            if !expanded, !sawFold {
                sawFold = true
                XCTAssertLessThan(controller.panelAlphaForTesting, 1, "it never went away")
                // Published emits in willSet; inspect the completed landing on the next queue turn.
                DispatchQueue.main.async {
                    XCTAssertFalse(controller.model.isExpanded,
                                   "it arrived at full size instead of opening into place")
                    XCTAssertEqual(controller.panelAlphaForTesting, 1, accuracy: 0.01, "it never came back")
                    landedOnLaterTurn = true
                    landed.fulfill()
                }
            } else if expanded, sawFold {
                XCTAssertTrue(landedOnLaterTurn, "it folded and opened in the same turn")
                opened.fulfill()
            }
        }
        defer { observation.cancel() }
        controller.apply(edge: .top)
        wait(for: [landed, opened], timeout: 5, enforceOrder: true)
    }

    /// And it is on screen while it opens, not still fading in underneath.
    func testItIsFullyVisibleBeforeItOpens() throws {
        try XCTSkipIf(NSUserName() == "runner", "Animation timing is flaky on headless CI environments")
        let controller = openController()
        defer { controller.stop() }

        let opened = expectation(description: "opened on the destination edge at full strength")
        let observation = controller.model.$isExpanded.dropFirst().sink { expanded in
            guard expanded, controller.model.edge == .bottom else { return }
            XCTAssertEqual(controller.panelAlphaForTesting, 1, accuracy: 0.01,
                           "it is still fading while it opens — two animations over each other")
            opened.fulfill()
        }
        defer { observation.cancel() }
        controller.apply(edge: .bottom)
        wait(for: [opened], timeout: 5)
    }

    /// A notch that was folded stays folded: moving it is not a reason to open.
    func testAFoldedNotchArrivesFolded() {
        let controller = openController()
        defer { controller.stop() }
        controller.model.isExpanded = false

        controller.apply(edge: .left)
        XCTAssertTrue(wait { controller.model.edge == .left && controller.panelAlphaForTesting == 1 },
                      "it never landed on the destination edge")
        XCTAssertFalse(controller.model.isExpanded, "moving it opened it uninvited")
        XCTAssertEqual(controller.model.edge, .left)
    }
}

/// "Always show" is a standing choice, and clicking the notch must not quietly
/// undo it.
///
/// It was held in `isPinned` — the same flag a click on the notch toggles. So
/// clicking anywhere on the bar that was not a ring or the settings orb turned
/// the flag off, the notch started folding on the way out, and Settings went on
/// saying "Always show". Reported as: it sometimes reverts to show-on-hover.
@MainActor
final class AlwaysShowTests: XCTestCase {
    func testClickingTheNotchDoesNotUndoAlwaysShow() {
        let controller = NotchWindowController()
        controller.apply(.alwaysShow)
        XCTAssertTrue(controller.model.staysOpen)

        controller.togglePinned()   // a click on the bar
        XCTAssertTrue(controller.model.staysOpen,
                      "a click downgraded Always show to hover")
        XCTAssertTrue(controller.model.isExpanded)
    }

    /// However many times. The report said "sometimes", which is what a toggle
    /// looks like from outside.
    func testItSurvivesRepeatedClicks() {
        let controller = NotchWindowController()
        controller.apply(.alwaysShow)
        for _ in 0..<5 { controller.togglePinned() }
        XCTAssertTrue(controller.model.staysOpen)
    }

    /// The transient pin still works where it is the only thing holding the
    /// notch open — that is what clicking is *for* in hover mode.
    func testAPinInHoverModeIsStillATogggle() {
        let controller = NotchWindowController()
        controller.apply(.onHover)
        XCTAssertFalse(controller.model.staysOpen)

        controller.togglePinned()
        XCTAssertTrue(controller.model.staysOpen, "clicking no longer pins")
        controller.togglePinned()
        XCTAssertFalse(controller.model.staysOpen, "clicking no longer unpins")
    }

    /// Switching to hover has to clear a pin left over from before, or the
    /// notch stays open and the new choice looks ignored.
    func testSwitchingToHoverClearsAStalePin() {
        let controller = NotchWindowController()
        controller.apply(.onHover)
        controller.togglePinned()
        controller.apply(.onHover)
        XCTAssertFalse(controller.model.staysOpen)
    }

    /// And so does hiding — a pinned notch that is ordered out still counts as
    /// held open, and would refuse to fold if it came back.
    func testHidingClearsBothHolds() {
        let controller = NotchWindowController()
        controller.apply(.alwaysShow)
        controller.apply(.hidden)
        XCTAssertFalse(controller.model.staysOpen)
        XCTAssertFalse(controller.model.isExpanded)
    }

    /// Coming back from hover to always-on, with a stale pin in between.
    func testAlwaysShowOutlastsAPinAndAnUnpin() {
        let controller = NotchWindowController()
        controller.apply(.onHover)
        controller.togglePinned()      // pinned by hand
        controller.apply(.alwaysShow)  // then chosen in Settings
        controller.togglePinned()      // and clicked again
        XCTAssertTrue(controller.model.staysOpen)
    }
}

/// A click that arrives while the notch is still folded used to pin it —
/// permanently, via `togglePinned()` — even though nobody had seen it open.
/// The pill's own hot zone is deliberately generous, since it is a small
/// target on a screen edge, which made it easy to trip by accident: reported
/// as "hover mode sticks open after a stray click".
///
/// Pinning stays exactly what a click on a notch that is *already* open does
/// — that part is documented and unchanged. What changes is the other guard:
/// a click that arrives before the notch has opened now just opens it, the
/// same as the pointer arriving would, so it folds back on its own once the
/// pointer leaves.
@MainActor
final class StrayClickPinTests: XCTestCase {
    func testAClickOnAFoldedNotchOpensWithoutPinning() {
        let controller = NotchWindowController()
        XCTAssertFalse(controller.model.isExpanded)
        XCTAssertFalse(controller.model.isPinned)

        controller.handleClick(at: .zero)

        XCTAssertTrue(controller.model.isExpanded, "the click did not open it at all")
        XCTAssertFalse(controller.model.isPinned, "a click before it ever opened pinned it")
    }

    /// However many times it arrives before the notch is actually open — the
    /// pill's hot zone is large enough that more than one could land.
    func testRepeatedClicksBeforeOpeningNeverPin() {
        let controller = NotchWindowController()
        for _ in 0..<3 { controller.handleClick(at: .zero) }
        XCTAssertFalse(controller.model.isPinned)
        XCTAssertTrue(controller.model.isExpanded)
    }
}

/// A ring dimmed the instant the very first idle refresh attempt failed,
/// because `staleAfter` and `idleRefreshInterval` were the same value — so a
/// reading was *guaranteed* to reach the dimming threshold before an idle
/// schedule could even try to refresh it once. Reported as "rings dim to
/// invisibility on every idle cycle".
final class StaleAfterMarginTests: XCTestCase {
    private final class FailingProvider: UsageProvider, @unchecked Sendable {
        let id = "x"
        let displayName = "X"
        let glyph = ProviderGlyph.claude
        private var succeedOnce = true

        func fetchSnapshot() async throws -> ProviderSnapshot {
            defer { succeedOnce = false }
            if succeedOnce {
                return ProviderSnapshot(id: id, displayName: displayName, glyph: glyph,
                                        fidelity: .official, status: .ok,
                                        windows: [LimitWindow(id: "w", label: "W",
                                                              usedFraction: 0.1)])
            }
            throw UsageProviderError.badResponse(status: 500)
        }
        nonisolated func account() -> ProviderAccount? { nil }
        nonisolated var signInRoute: SignInRoute { .guidance("") }
        func signOut() async {}
        func presentSignIn() {}
        nonisolated func forgetCachedCredential() {}
    }

    private func defaults() -> UserDefaults {
        let name = "StaleAfterMarginTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    /// One failed attempt, well inside the margin, must not dim the ring —
    /// that is the ordinary shape of an idle afternoon, not a fault.
    @MainActor
    func testOneFailedIdleAttemptDoesNotDimTheRing() async throws {
        let store = UsageStore(
            providers: [FailingProvider()],
            refreshInterval: 0.05, idleRefreshInterval: 0.15, staleAfter: 0.45,
            archive: UsageArchive(defaults: defaults())
        )
        await store.refresh()
        XCTAssertEqual(store.snapshots.first?.status, .ok)

        try await Task.sleep(nanoseconds: 200_000_000)   // > idleRefreshInterval
        await store.refresh()                            // the attempt that fails

        let status = try XCTUnwrap(store.snapshots.first?.status)
        XCTAssertFalse(status.isStale,
                       "the ring dimmed after a single failed attempt, well inside the margin")
    }

    /// Once genuinely stale for longer than the margin, it does dim — the
    /// mechanism still works, it just no longer fires prematurely.
    @MainActor
    func testItStillDimsOnceGenuinelyStale() async throws {
        let store = UsageStore(
            providers: [FailingProvider()],
            refreshInterval: 0.05, idleRefreshInterval: 0.05, staleAfter: 0.2,
            archive: UsageArchive(defaults: defaults())
        )
        await store.refresh()
        try await Task.sleep(nanoseconds: 300_000_000)   // > staleAfter
        await store.refresh()

        let status = try XCTUnwrap(store.snapshots.first?.status)
        XCTAssertTrue(status.isStale, "the mechanism no longer dims a genuinely old reading")
    }

    /// The shipped defaults keep the same three-to-one margin verified above,
    /// not just some values that happen to satisfy it.
    @MainActor
    func testTheShippedDefaultsKeepTheSameMargin() {
        let store = UsageStore(providers: [])
        XCTAssertGreaterThan(store.staleAfterForTesting, store.idleRefreshIntervalForTesting)
    }
}

@MainActor
final class PhysicalPanelIntegrationTests: XCTestCase {
    func testActualPanelsStayOnTheBezelAndKeepCornerCardsVisible() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        for size in NotchSize.allCases {
            for edge in NotchEdge.allCases {
                let controller = NotchWindowController()
                controller.assignedScreen = screen
                controller.model.edge = edge
                controller.model.sizeScale = size.scale
                controller.model.snapshots = Array(Fixtures.snapshots().prefix(2))
                controller.show()
                defer { controller.stop() }
                for offset: CGFloat in [-10000, 0, 10000] {
                    controller.model.alongOffset = offset
                    controller.relocate()
                    let frame = try XCTUnwrap(controller.panelFrameForTesting)
                    switch edge {
                    case .left: XCTAssertEqual(frame.minX, screen.frame.minX, accuracy: 1)
                    case .right: XCTAssertEqual(frame.maxX, screen.frame.maxX, accuracy: 1)
                    case .top: XCTAssertEqual(frame.maxY, screen.frame.maxY, accuracy: 1)
                    case .bottom: XCTAssertEqual(frame.minY, screen.frame.minY, accuracy: 1)
                    }
                    let range = try XCTUnwrap(controller.model.visibleAlongRange)
                    let length: CGFloat = edge.isVertical ? 260 : NotchLayout.cardWidth
                    for index in 0..<2 {
                        let centre = controller.model.tooltipAlong(index: index, length: length)
                        XCTAssertGreaterThanOrEqual(centre - length / 2, range.lowerBound)
                        XCTAssertLessThanOrEqual(centre + length / 2, range.upperBound)
                    }
                }
            }
        }
    }
}
