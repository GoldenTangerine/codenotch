/**
 @name: 刘海几何布局
 @Descripttion: 计算屏幕位置与收起触发区域。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-09 09:41:19
 @LastEditTime: 2026-09-09 09:41:19
 @FilePath: Sources/Notch/NotchGeometry.swift
 */
import AppKit

/// The display's *own* notch — the camera housing on a MacBook, not ours.
///
/// Worth naming, because it is the one piece of the screen that is not a screen:
/// pixels drawn there are behind a hole, not merely covered.
struct HardwareNotch: Equatable {
    let width: CGFloat
    let height: CGFloat

    /// **How deep the cutout is**, from every signal AppKit offers rather than
    /// the one that seemed obvious.
    ///
    /// `safeAreaInsets.top` was it, and it is not dependable: it describes the
    /// area the system is asking apps to keep clear, so it collapses when the
    /// menu bar is hidden or set to auto-hide. The hole in the display does not
    /// move when that happens, so the bar came out shallower than the cutout it
    /// is supposed to be — a step along the bottom of the notch.
    ///
    /// The strips either side of the notch are the notch's own height and keep
    /// reporting it either way, so the deepest of the three is the cutout.
    static func height(safeAreaTop: CGFloat, beside strips: [CGFloat]) -> CGFloat {
        max(safeAreaTop, strips.max() ?? 0)
    }
}

/// **How close the display's own hole is to the notch, and how deep it is.**
///
/// The notch is one shape on all four edges and knows nothing about the
/// hardware. This is the exception, and it is deliberately the smallest one
/// that will do: two numbers, measured in screen points, that say the hole is
/// within reach and where its trailing wall stands relative to the notch's
/// leading tip. Everything the join needs is derived from them — see
/// `SideNotchShape.Cutout`, which draws it.
struct CutoutProximity: Equatable {
    /// How deep the hole is.
    var depth: CGFloat

    /// How far the notch's own end lies *inside* the hole. Never less than
    /// `NotchGeometry.cutoutOverlap`: short of that there is no join — see
    /// `cutoutProximity`.
    var overlap: CGFloat

    /// **Which end of the notch the hole is at.**
    ///
    /// The notch is placed to the right of the cutout and joins it at its
    /// leading end. Dragged the other way it ends up on the *left* of the
    /// cutout, where the end that meets the hole is its trailing one — the same
    /// join, at the other end of the same shape.
    ///
    /// Only of consequence while the notch is coming off the hole or going back
    /// on to it: joined, it is drawn on *both* sides at once, and a pair that is
    /// symmetric about the hole has no side.
    var atTrailingEnd: Bool = false

    /// How wide the hole is, which is the gap the pair is drawn either side of.
    var width: CGFloat = 0

    /// **Whether the two actually overlap**, which is whether the join is
    /// drawn at all.
    ///
    /// The notch is still *reported* for a way either side of that, and the
    /// difference matters: the window is sized and placed for a notch that has
    /// a hole beside it, joined or not, so that taking the hole and letting go
    /// of it do not move the window. A window frame is set in one step and
    /// cannot be animated — anything inside it that eases while it moves is
    /// easing across the distance it moved.
    var joined: Bool = true
}

/// Everything the geometry maths needs from a screen, so it can be faked in tests.
protocol ScreenDescribing {
    var frameValue: CGRect { get }
    var visibleFrameValue: CGRect { get }
    var hardwareNotch: HardwareNotch? { get }
    var displayIdentifier: String? { get }
}

extension ScreenDescribing {
    /// Most displays have none, and most tests do not care.
    var hardwareNotch: HardwareNotch? { nil }
    var displayIdentifier: String? { nil }
}

extension NSScreen: ScreenDescribing {
    var frameValue: CGRect { frame }
    var visibleFrameValue: CGRect { visibleFrame }

    /// Unlike `CGDirectDisplayID`, this UUID survives display reconfiguration
    /// and restarts, so a saved choice still names the same physical monitor.
    var displayIdentifier: String? {
        let screenNumber = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = deviceDescription[screenNumber] as? NSNumber,
              let unmanaged = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)
        else { return nil }
        let uuid = unmanaged.takeRetainedValue()
        return CFUUIDCreateString(nil, uuid) as String
    }

    /// Measured from the two menu-bar strips *either side* of the notch, which
    /// is the only thing AppKit describes directly. A display without a notch
    /// reports no auxiliary areas.
    var hardwareNotch: HardwareNotch? {
        guard let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea else {
            return nil
        }
        let width = frame.width - left.width - right.width
        let height = HardwareNotch.height(safeAreaTop: safeAreaInsets.top,
                                          beside: [left.height, right.height])
        guard width > 0, height > 0 else { return nil }
        return HardwareNotch(width: width, height: height)
    }
}

enum NotchGeometry {
    static func activationRect(
        placement: NotchPlacement,
        slack: CGFloat,
        shapeLength: CGFloat,
        restingLength: CGFloat,
        restingDepth: CGFloat,
        hardwareNotch: HardwareNotch?,
        triggerHeight: Int,
        activityWidth: CGFloat? = nil
    ) -> CGRect {
        if placement.edge == .top, let hardwareNotch {
            let width = max(hardwareNotch.width, activityWidth ?? hardwareNotch.width)
            return placement.rect(
                along: slack + (shapeLength - width) / 2,
                across: 0,
                length: width,
                depth: max(1, hardwareNotch.height + CGFloat(NotchTriggerHeight.clamp(triggerHeight)))
            )
        }
        let length = max(restingLength, NotchLayout.pillHotZone)
        return placement.rect(
            along: slack + (shapeLength - length) / 2,
            across: 0,
            length: length,
            depth: restingDepth + NotchLayout.pillHotZone
        )
    }

    /// The panel hugs the chosen edge and is centred along it.
    ///
    /// **Which edge it hugs is `visibleFrame`'s, not `frame`'s.** That is what
    /// keeps a bottom notch resting on top of the Dock and a top one below the
    /// menu bar rather than behind them, and it is why the notch moves when the
    /// Dock hides — `visibleFrame` gives the space back and the notch takes it.
    ///
    /// **Centring, though, stays on `frame`.** A Dock at the bottom is nowhere
    /// near a right-edge notch, and centring on the visible area would shift
    /// that notch up and down the screen every time the Dock hid itself, for no
    /// reason anyone could see.
    /// Anchor to the physical display edge, even when the Dock or menu bar
    /// reserves part of the desktop. Showing or hiding either must not move
    /// a position the user chose.
    ///
    /// The rect is rounded out to whole points on purpose. AppKit rounds window
    /// frames anyway, and if it does the rounding the panel ends up a fraction
    /// larger than asked for — which leaves the content, laid out at its exact
    /// size, stopping short of the screen edge. A hairline of wallpaper along
    /// that edge is all it takes for the notch to read as floating rather than
    /// welded to the bezel.
    static func panelFrame(
        for screen: ScreenDescribing,
        panelSize: CGSize,
        edge: NotchEdge = .right,
        // A user-chosen nudge along the edge, from `NotchViewModel.alongOffset`
        // — zero is the centred default this file always drew before the nudge
        // existed. Vertical edges read it as AppKit's y running *down* the
        // screen (dragging the pill down increases it); horizontal edges read
        // it as x running right, which needs no such flip.
        alongOffset: CGFloat = 0,
        // The padding `panelSize` carries on *each* end beyond the visible
        // pill, reserved for a hover card that is not there right now —
        // `NotchViewModel.slack`. Clamping the offset by the padded size
        // would have left the pill only a sliver of room to move in on most
        // screens, since that padding is sized for the tallest possible card
        // and can be most of the panel. Clamping by the pill's own extent
        // instead — `panelSize` shrunk by this on each end — lets it travel
        // almost the full edge; the padding is free to run past the bezel,
        // since nothing is drawn there until a card actually opens.
        slack: CGFloat = 0,
        // The settings handle hangs past the body's trailing end. That part
        // of the padding must stay on screen even when the hover card may not.
        trailingExtent: CGFloat = 0,
        leadingExtent: CGFloat = 0
    ) -> CGRect {
        let full = screen.frameValue
        let width = panelSize.width.rounded(.up)
        let height = panelSize.height.rounded(.up)

        let origin: CGPoint
        switch edge {
        case .right:
            let y = clamp(full.midY - height / 2 - alongOffset,
                          min: full.minY - slack + trailingExtent, max: full.maxY - height + slack - leadingExtent)
            origin = CGPoint(x: full.maxX - width, y: y)
        case .left:
            let y = clamp(full.midY - height / 2 - alongOffset,
                          min: full.minY - slack + trailingExtent, max: full.maxY - height + slack - leadingExtent)
            origin = CGPoint(x: full.minX, y: y)
        case .top:
            let x = clamp(full.midX - width / 2 + alongOffset,
                          min: full.minX - slack + leadingExtent, max: full.maxX - width + slack - trailingExtent)
            origin = CGPoint(x: x, y: full.maxY - height)
        case .bottom:
            let x = clamp(full.midX - width / 2 + alongOffset,
                          min: full.minX - slack + leadingExtent, max: full.maxX - width + slack - trailingExtent)
            origin = CGPoint(x: x, y: full.minY)
        }

        return CGRect(
            x: origin.x.rounded(),
            y: origin.y.rounded(),
            width: width,
            height: height
        )
    }

    static func preferredScreen(
        from screens: [NSScreen],
        preference: DisplayPreference = .followActiveWindow
    ) -> NSScreen? {
        preferredScreen(from: screens, preference: preference, activeScreen: NSScreen.main)
    }

    /// Kept generic so display selection can be proved without relying on the
    /// monitors attached to the machine running the tests.
    static func preferredScreen<Screen: ScreenDescribing>(
        from screens: [Screen],
        preference: DisplayPreference,
        activeScreen: Screen?
    ) -> Screen? {
        if case .display(let id) = preference,
           let selected = screens.first(where: { $0.displayIdentifier == id }) {
            return selected
        }
        return activeScreen ?? screens.first
    }

    /// Keeps a dragged offset from pushing the visible pill off the screen it
    /// is on. A plain `ClosedRange` clamp would trap if the pill were ever
    /// taller or wider than the screen, which a very small display could
    /// make true.
    private static func clamp(_ value: CGFloat, min lo: CGFloat, max hi: CGFloat) -> CGFloat {
        guard lo <= hi else { return lo }
        return Swift.min(Swift.max(value, lo), hi)
    }
}
