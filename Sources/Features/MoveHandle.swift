/**
 @name: 上游同步模块
 @Descripttion: 维护 MoveHandle.swift 的项目实现与上游兼容。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-11 15:51:14
 @LastEditTime: 2026-09-11 15:51:14
 @FilePath: Sources/Features/MoveHandle.swift
 */
import SwiftUI

/// The move control, above the notch — the mirror of `SettingsOrb` below it.
///
/// At rest it is the same bare arc the settings orb is, for the same reason:
/// the notch is meant to be glanceable, and a second permanently visible glyph
/// competes with the readings. On hover the arc fills in and takes a hand,
/// which turns as it arrives. Holding it starts a move.
///
/// The hand rather than arrows because the gesture is a carry, not a nudge: you
/// pick the notch up and put it on another edge. Arrows would suggest the
/// ⌥-drag that already exists, which slides it *along* the edge it is on.
struct MoveHandle: View {
    let isHovered: Bool
    /// True once the handle has been held and the notch is waiting to be
    /// dropped. The disc goes dashed and the hand stops turning: it is being
    /// carried now, not offered.
    var isArmed: Bool = false
    var edge: NotchEdge = .right
    /// True when the arc traces the bar's own rounded corner from outside
    /// rather than a flare from inside — see `SettingsOrb.convex`.
    var convex: Bool = false
    var arcRadius: CGFloat = NotchLayout.orbArcRadius
    var arcOffset: CGSize = .zero
    /// How many times the hand has been asked to turn, on the same counter
    /// pattern `SettingsOrb.spins` uses.
    var spins: Int = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.notchSurfaceStyle) private var surfaceStyle
    @Environment(\.codenotchReduceTransparency) private var reduceTransparency

    private var glassy: Bool { surfaceStyle.isGlass && !reduceTransparency }

    /// The resting arc occupies the quarter of the circle facing the notch it
    /// hangs off and the bezel it merges into — the same two directions
    /// `SettingsOrb` faces, with only the first of them reversed: this hangs
    /// off the *near* end of the stack rather than the far one, but it is on
    /// the same screen edge.
    ///
    /// Reflected along the stack, **not** rotated by half a circle. A half turn
    /// reverses both directions at once, which sends the arc away from the
    /// bezel and into the middle of the screen — it curls the wrong way, and on
    /// a side edge it reads as visibly crooked against the flare it is supposed
    /// to parallel. So a vertical edge swaps up for down and keeps its side of
    /// the screen; a horizontal one swaps left for right and keeps its top or
    /// bottom.
    static func restingTrim(for edge: NotchEdge, convex: Bool) -> ClosedRange<CGFloat> {
        let settings = SettingsOrb.restingTrim(for: edge, convex: convex)
        return mirroredAlongStack(settings, isVertical: edge.isVertical)
    }

    /// Reflects a quadrant across the axis that runs *out of* the screen edge,
    /// leaving the other axis — the one that says which edge this is — alone.
    ///
    /// A quadrant is identified by its lower bound, in SwiftUI's trim space:
    /// 0 is three o'clock and it runs clockwise with y growing downward. So
    /// reflecting vertically (up ↔ down) maps 0.75↔0.0 and 0.5↔0.25, and
    /// reflecting horizontally (left ↔ right) maps 0.5↔0.75 and 0.25↔0.0.
    static func mirroredAlongStack(
        _ quadrant: ClosedRange<CGFloat>, isVertical: Bool
    ) -> ClosedRange<CGFloat> {
        // Both reflections are `constant - lower`, taken mod 1: 0.75 for the
        // vertical flip, 1.25 for the horizontal one.
        let constant: CGFloat = isVertical ? 0.75 : 1.25
        let lower = (constant - quadrant.lowerBound).truncatingRemainder(dividingBy: 1)
        return lower...(lower + 0.25)
    }

    private var restingTrim: ClosedRange<CGFloat> { Self.restingTrim(for: edge, convex: convex) }

    /// How far the button dips under a click — the settings orb's depth, so the
    /// two controls on the same notch press the same amount.
    private static let squeezeScale: CGFloat = 0.84

    /// The dashes on the armed disc. Long enough to read as a dashed ring at
    /// 46pt rather than as a dotted blur.
    private static let armedDash: [CGFloat] = [Design.px(14), Design.px(12)]

    @ViewBuilder
    private var restingArc: some View {
        if glassy {
            if #available(macOS 26.0, *) {
                Color.clear
                    .frame(width: 100, height: 100)
                    .glassEffect(surfaceStyle.glass, in: Rectangle())
                    .background { if let dim = surfaceStyle.glassDim { Rectangle().fill(dim) } }
                    .frame(width: arcRadius * 2 + NotchLayout.orbStroke,
                           height: arcRadius * 2 + NotchLayout.orbStroke)
                    .clipShape(ArcBand(trim: restingTrim, lineWidth: NotchLayout.orbStroke))
            }
        } else {
            Circle()
                .trim(from: restingTrim.lowerBound, to: restingTrim.upperBound)
                .stroke(
                    Palette.notch,
                    style: StrokeStyle(lineWidth: NotchLayout.orbStroke, lineCap: .round)
                )
                .frame(width: arcRadius * 2, height: arcRadius * 2)
        }
    }

    @ViewBuilder
    private var hoverDisc: some View {
        if glassy {
            if #available(macOS 26.0, *) {
                Color.clear
                    .frame(width: 100, height: 100)
                    .glassEffect(surfaceStyle.glass.interactive(), in: Rectangle())
                    .background { if let dim = surfaceStyle.glassDim { Rectangle().fill(dim) } }
                    .frame(width: NotchLayout.orbDiameter, height: NotchLayout.orbDiameter)
                    .clipShape(Circle())
            }
        } else {
            Circle()
                .fill(Palette.notch)
                .frame(width: NotchLayout.orbDiameter, height: NotchLayout.orbDiameter)
        }
    }

    /// The dashed ring that says the notch is in hand. Drawn over the disc
    /// rather than instead of it, so arming reads as the same button changing
    /// state rather than as a different button.
    private var armedRing: some View {
        Circle()
            .strokeBorder(
                Palette.textPrimary.opacity(0.9),
                style: StrokeStyle(lineWidth: NotchLayout.orbStroke / 2,
                                   lineCap: .round,
                                   dash: Self.armedDash)
            )
            .frame(width: NotchLayout.orbDiameter, height: NotchLayout.orbDiameter)
    }

    var body: some View {
        ZStack {
            restingArc
                .opacity(isHovered ? 0 : 1)
                .scaleEffect(isHovered ? 0.86 : 1)
                .offset(arcOffset)

            hoverDisc
                .opacity(isHovered ? 1 : 0)
                .scaleEffect(isHovered ? 1 : 1.1)

            armedRing
                .opacity(isArmed ? 1 : 0)
                .scaleEffect(isArmed ? 1 : 0.8)

            Image(systemName: isArmed ? "hand.draw.fill" : "hand.draw")
                .font(.system(size: NotchLayout.orbGlyph, weight: .regular))
                .foregroundStyle(Palette.textPrimary)
                .opacity(isHovered ? 1 : 0)
                .scaleEffect(isHovered ? 1 : 0.5)
                // Two rotations on one glyph, as the gear has: the wake-up
                // from the hover state, and a turn per arm. Summed so arming
                // mid-hover does not fight the -60 the hand is arriving from.
                // A quarter turn, not a full one — the hand is being offered,
                // and a whole revolution reads as a spinner.
                .rotationEffect(.degrees((isHovered ? 0 : -60) + Double(spins) * 90))
                .animation(NotchMotion.respectingReduceMotion(.spring(response: 0.55,
                                                                      dampingFraction: 0.72),
                                                              reduceMotion),
                           value: spins)
        }
        .frame(width: arcRadius * 2 + NotchLayout.orbStroke,
               height: arcRadius * 2 + NotchLayout.orbStroke)
        .animation(
            NotchMotion.respectingReduceMotion(
                .spring(response: 0.36, dampingFraction: 0.7), reduceMotion
            ),
            value: isHovered
        )
        .animation(
            NotchMotion.respectingReduceMotion(
                .spring(response: 0.4, dampingFraction: 0.68), reduceMotion
            ),
            value: isArmed
        )
        .keyframeAnimator(initialValue: CGFloat(1), trigger: spins) { handle, scale in
            handle.scaleEffect(scale)
        } keyframes: { _ in
            SpringKeyframe(reduceMotion ? 1 : Self.squeezeScale,
                           duration: 0.09, spring: .snappy)
            SpringKeyframe(1, duration: 0.34, spring: .bouncy)
        }
    }
}

/// **The six dots that move the notch**, beside the settings button.
///
/// Not a second button at the other end of the notch: two arcs, one each
/// end, read as two things fighting over the same notch. These come out only
/// with the settings button, beside it, as its companion — hold them and
/// drag, and the notch goes along the screen's edge with the pointer, as
/// ⌥-drag takes it.
///
/// **Out of the settings button like goo**, the way the arcs come out of the
/// notch: one drop pushes out of the button's edge on a neck, runs out to
/// where the dots go, and divides into the six of them as the neck lets go.
/// Hidden, the same backwards — the six run together into one drop and it is
/// drawn back into the button. Drawn centred on the settings button.
struct MoveGrip: View, Animatable {
    /// 0 inside the settings button, 1 out at its place.
    var separation: CGFloat
    /// How much the dots are under the pointer, 0 to 1 — animated, so they
    /// swell to meet it on a spring rather than stepping up a size.
    var hover: CGFloat
    var edge: NotchEdge = .top
    /// From the settings button's middle to the dots', and which way.
    let reach: CGFloat
    let direction: CGPoint

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(separation, hover) }
        set {
            separation = newValue.first
            hover = newValue.second
        }
    }

    /// How much bigger a dot is under the pointer.
    static let hoverGrowth: CGFloat = 0.3

    @Environment(\.notchSurfaceStyle) private var surfaceStyle
    @Environment(\.codenotchReduceTransparency) private var reduceTransparency

    private var glassy: Bool { surfaceStyle.isGlass && !reduceTransparency }

    static func step(_ x: CGFloat) -> CGFloat {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Each dot's place from the middle of the six: two lines of three, each
    /// line running out from the bezel.
    static func offsets(on edge: NotchEdge) -> [CGPoint] {
        let pitch = NotchLayout.gripPitch
        var points: [CGPoint] = []
        for line in [-0.5, 0.5] as [CGFloat] {
            for row in [-1, 0, 1] as [CGFloat] {
                let along = line * pitch, across = row * pitch
                points.append(edge.isVertical ? CGPoint(x: across, y: along)
                                              : CGPoint(x: along, y: across))
            }
        }
        return points
    }

    private var discRadius: CGFloat { NotchLayout.orbDiameter / 2 }

    /// How far out the middle of the six is: from inside the button's edge
    /// to its place, a little past it on the way.
    private var out: CGFloat {
        let t = min(max(separation, 0), 1)
        let start = discRadius * 0.6
        let pull = reach * 0.18 * sin(.pi * min(t / 0.8, 1))
        return start + (reach - start) * Self.step(t / 0.6) + pull
    }

    /// How far each dot has divided off from the drop, 0 to 1 — one a beat
    /// after another, so they come apart rather than burst.
    private func spread(_ index: Int) -> CGFloat {
        Self.step((separation - 0.32 - 0.015 * CGFloat(index)) / 0.4)
    }

    /// The neck at its narrowest, thinning away as the drop divides.
    private var neck: CGFloat {
        NotchLayout.gripWidth * 0.55 * (1 - Self.step((separation - 0.25) / 0.35))
    }

    /// Strong while they come out, gone once they are in place — so the dots
    /// arrive crisp, and apart from each other and from the button.
    /// Softening as they divide, too: at full strength it ate a dot as small
    /// as these away the moment it came off.
    private var goo: CGFloat { 3 * (1 - Self.step((separation - 0.42) / 0.36)) }

    private var side: CGFloat { 2 * (reach * 1.4 + NotchLayout.gripLength) }

    var body: some View {
        let at = CGPoint(x: direction.x * out, y: direction.y * out)
        ZStack {
            if glassy {
                glassDots(at: at)
            } else if separation > 0.01 {
                goo(at: at)
            }
        }
        .frame(width: side, height: side)
        .allowsHitTesting(false)
    }

    /// The button's edge, the neck and the drop that divides into the dots,
    /// run together as one liquid.
    private func goo(at: CGPoint) -> some View {
        Canvas { context, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let d = direction
            let t = separation
            let liquid = goo > 0.3
            if liquid {
                context.addFilter(.alphaThreshold(min: 0.5, color: Palette.notch))
                context.addFilter(.blur(radius: goo))
            }
            let ink: Color = liquid ? .black : Palette.notch
            context.drawLayer { layer in
                func disc(_ p: CGPoint, _ r: CGFloat) {
                    layer.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                               with: .color(ink))
                }
                // A piece of the button, inside its edge on the dots' side, for
                // the neck to swell out of: under the button while it is there,
                // and what the dots go back into as it fades.
                if liquid {
                    let core = discRadius * 0.55 * Self.step(t / 0.15)
                    disc(CGPoint(x: c.x + d.x * (discRadius - core), y: c.y + d.y * (discRadius - core)), core)
                }
                // The six, from one drop: each fat while it is still part of
                // the drop, its own size once divided off.
                let middle = CGPoint(x: c.x + at.x, y: c.y + at.y)
                let dot = NotchLayout.gripDot / 2 * (1 + Self.hoverGrowth * hover)
                for (i, offset) in Self.offsets(on: edge).enumerated() {
                    let s = spread(i)
                    let r = dot * (1 + 1.9 * (1 - s)) * Self.step(t / 0.12)
                    disc(CGPoint(x: middle.x + offset.x * s, y: middle.y + offset.y * s), r)
                }
                // The neck, from the button's edge out to the drop.
                guard liquid, neck > 0.5 else { return }
                let from = CGPoint(x: c.x + d.x * (discRadius - 2), y: c.y + d.y * (discRadius - 2))
                let mid = CGPoint(x: (from.x + middle.x) / 2, y: (from.y + middle.y) / 2)
                let px = -d.y, py = d.x
                func side(_ p: CGPoint, _ half: CGFloat, _ sign: CGFloat) -> CGPoint {
                    CGPoint(x: p.x + px * half * sign, y: p.y + py * half * sign)
                }
                let base = NotchLayout.gripWidth * 0.8, top = NotchLayout.gripWidth * 0.5
                var strand = Path()
                strand.move(to: side(from, base / 2, 1))
                strand.addQuadCurve(to: side(middle, top / 2, 1), control: side(mid, neck / 2, 1))
                strand.addLine(to: side(middle, top / 2, -1))
                strand.addQuadCurve(to: side(from, base / 2, -1), control: side(mid, neck / 2, -1))
                strand.closeSubpath()
                layer.fill(strand, with: .color(.black))
            }
        }
    }

    /// On glass, each dot a bead of it, growing out in turn — no black goo
    /// against a glass notch.
    @ViewBuilder
    private func glassDots(at: CGPoint) -> some View {
        if #available(macOS 26.0, *) {
            let dot = NotchLayout.gripDot * (1 + Self.hoverGrowth * hover)
            ForEach(Array(Self.offsets(on: edge).enumerated()), id: \.offset) { i, offset in
                let s = spread(i)
                Color.clear
                    .frame(width: 20, height: 20)
                    .glassEffect(surfaceStyle.glass, in: Rectangle())
                    .background { if let dim = surfaceStyle.glassDim { Rectangle().fill(dim) } }
                    .frame(width: dot, height: dot)
                    .clipShape(Circle())
                    .scaleEffect(0.3 + 0.7 * s)
                    .opacity(Double(Self.step(separation / 0.3)))
                    .offset(x: at.x + offset.x * s, y: at.y + offset.y * s)
            }
        }
    }
}

/// **The dots standing in for the settings arc while the notch is carried**:
/// the six, where the arc was. Held by them, the notch shows what it is held
/// by; set down, the arc comes back.
struct GripMark: View {
    var edge: NotchEdge = .top
    /// **Squeezed in the hand**, 0 to 1: held, the dots draw in smaller and
    /// closer together, the way something gripped gives; let go, they spring
    /// back.
    var squeeze: CGFloat = 0
    /// The dots' own size over their resting one — a touch bigger under the
    /// pointer, as `MoveGrip` draws them.
    var dotScale: CGFloat = 1

    static let squeezedDot: CGFloat = 0.7
    static let squeezedPitch: CGFloat = 0.82

    var body: some View {
        let dot = NotchLayout.gripDot * (1 - (1 - Self.squeezedDot) * squeeze) * dotScale
        let pitch = 1 - (1 - Self.squeezedPitch) * squeeze
        ZStack {
            ForEach(Array(MoveGrip.offsets(on: edge).enumerated()), id: \.offset) { _, offset in
                Circle()
                    .fill(Palette.notch)
                    .frame(width: dot, height: dot)
                    .offset(x: offset.x * pitch, y: offset.y * pitch)
            }
        }
        .frame(width: NotchLayout.gripLength, height: NotchLayout.gripLength)
        .allowsHitTesting(false)
    }
}

/// **A notch being carried, and set down**: when it was taken hold of, let
/// go of, and landed — what the settings handle's end of it shows, worked out
/// from these times alone.
struct Carry: Equatable {
    var at: Date
    /// Taken hold of by its dots, out beside the settings button — rather
    /// than by ⌥-drag, with nothing out.
    var fromHover: Bool
    var releasedAt: Date?
    var landedAt: Date?

    /// Long enough after landing for everything it shows to have settled.
    static let settles: TimeInterval = 0.5
}

/// **The settings handle's end of a carried notch**: the button going back
/// into the notch like goo and the dots in the hand sliding in to where its
/// arc was, squeezed; let go, the dots spring back; landed, the same run
/// backwards — the dots out beside the button again and the button out of
/// the notch, just as they were when it was taken hold of. Taken by ⌥-drag
/// instead, with nothing out, it lands back to its arc.
///
/// A function of the clock and `Carry`'s times, not of animations started
/// here: the notch draws this, and so does the drawing that stands in for it
/// while it moves, and the two hand over at any moment of it — so both have
/// to show exactly the same frame. Two animations, each started when its own
/// view came up, were what made it jump as one took over from the other.
struct CarriedHandle: View {
    let carry: Carry
    let edge: NotchEdge
    let trim: ClosedRange<CGFloat>
    /// The resting arc's radius — see `SettingsOrb.arcRadius`.
    let arcRadius: CGFloat
    /// From the settings button to where the dots were beside it.
    let gripShift: CGSize

    private static func clamp(_ x: CGFloat) -> CGFloat { min(max(x, 0), 1) }
    private static func step(_ x: CGFloat) -> CGFloat { GooArc.step(x) }
    private static func easeOut(_ x: CGFloat) -> CGFloat {
        let u = 1 - clamp(x)
        return 1 - u * u * u
    }
    /// Past 1 and back: a spring's give, without a spring.
    private static func easeOutBack(_ x: CGFloat) -> CGFloat {
        let t = clamp(x) - 1, c1: CGFloat = 1.5
        return 1 + (c1 + 1) * t * t * t + c1 * t * t
    }

    var body: some View {
        TimelineView(.animation) { context in
            frame(at: context.date)
        }
        .frame(width: arcRadius * 2 + NotchLayout.orbStroke,
               height: arcRadius * 2 + NotchLayout.orbStroke)
        .allowsHitTesting(false)
    }

    private func frame(at now: Date) -> some View {
        let t = CGFloat(now.timeIntervalSince(carry.at))
        // Taken hold of: the button into the notch, the dots in and squeezed.
        // The button first, so the dots — black, as it is — come in to its
        // place once it has gone rather than disappearing across it.
        let merge = Self.step(t / 0.3)
        let slide = Self.easeOutBack((t - 0.12) / 0.36)
        var squeeze = Self.easeOut(t / 0.26)
        // Let go: the dots spring back to their size.
        if let released = carry.releasedAt {
            squeeze *= 1 - Self.easeOutBack(CGFloat(now.timeIntervalSince(released)) / 0.34)
        }
        var merged = merge, held = slide
        var dots: CGFloat = 1, arc: CGFloat = 0, button: CGFloat = 1
        var gear = 1 - Self.step(t / 0.1), grow: CGFloat = 0
        if let landed = carry.landedAt {
            let v = CGFloat(now.timeIntervalSince(landed))
            if carry.fromHover {
                // Landed: back as it was taken — the dots out beside the
                // button, the button out of the notch, its gear on it.
                merged *= 1 - Self.step(v / 0.32)
                held *= 1 - Self.easeOutBack(v / 0.36)
                gear = max(gear, Self.step((v - 0.16) / 0.16))
                grow = Self.step(v / 0.3)
            } else {
                // Landed from ⌥-drag: the dots fade and the arc comes back.
                dots = 1 - Self.step(v / 0.24)
                arc = Self.easeOutBack((v - 0.06) / 0.34)
                button = 1 - Self.step(v / 0.15)
            }
        }
        return ZStack {
            if carry.fromHover {
                DiscMerge(merge: merged, trim: trim, edge: edge, radius: arcRadius)
                    .opacity(button)
                Image(systemName: "gearshape.fill")
                    .font(.system(size: NotchLayout.orbGlyph, weight: .regular))
                    .foregroundStyle(Palette.textPrimary)
                    .opacity(gear)
            } else {
                // Taken by ⌥-drag: the arc itself gives way to the dots.
                GooArc(trim: trim, edge: edge, convex: false, radius: arcRadius, separation: 1)
                    .opacity(1 - Self.step(t / 0.2))
                    .scaleEffect(1 - 0.4 * Self.step(t / 0.25))
            }
            if carry.landedAt != nil {
                GooArc(trim: trim, edge: edge, convex: false, radius: arcRadius, separation: 1)
                    .opacity(Self.clamp(arc))
                    .scaleEffect(0.6 + 0.4 * arc)
            }
            // The dots, drawn over the button: they cross it only once it has
            // gone, and come back across it before it is back.
            GripMark(edge: edge, squeeze: squeeze, dotScale: 1 + MoveGrip.hoverGrowth * grow)
                .scaleEffect(carry.fromHover ? 1 : 0.4 + 0.6 * slide)
                .offset(x: carry.fromHover ? gripShift.width * (1 - held) : 0,
                        y: carry.fromHover ? gripShift.height * (1 - held) : 0)
                .opacity(Self.clamp(carry.fromHover ? 1 : slide) * dots)
        }
    }
}
