/**
 @name: 供应商额度圆环
 @Descripttion: 展示供应商图标、查询状态与主指标。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-08 14:56:06
 @LastEditTime: 2026-09-08 14:56:06
 @FilePath: Sources/Features/ProviderRing.swift
 */
import AppKit
import SwiftUI

/// The ring around a provider glyph: a grey track with a coloured arc that
/// starts at 12 o'clock and sweeps clockwise by the fraction used.
///
/// When that provider is doing something right now, a second, much thinner arc
/// appears *inside* the ring, in the gap between the glyph and the track. It is
/// deliberately a different radius, a different weight and a neutral colour, so
/// it reads as a separate fact rather than as the usage number moving.
struct ProviderRing: View {
    /// Nil when the provider reports what is left but never says out of what —
    /// there is no arc to draw, and inventing one would be a lie in a shape.
    let usedFraction: Double?
    let glyph: ProviderGlyph
    var isStale: Bool = false
    /// Blocked right now. Shown as spent whatever the arc says, because that is
    /// what it means for you — a ring reading 16% while the account is paused
    /// is technically true and practically a lie.
    var isBlocked: Bool = false
    var activity: ActivitySummary?
    /// A fetch this cell asked for, in flight.
    var isRefreshing: Bool = false
    var bot: BotPresentation?
    var icon: ProviderIcon?
    var localPerformance: LocalModelPerformance?
    /// A local model's arc: how full its context was on the last request. Nil
    /// draws the whole ring, which is what a runtime that does not say gets.
    var localContextFraction: Double?
    /// The weekly limit, when the provider has one. Nil is the ordinary case
    /// for a provider with a single window, and draws nothing.
    var weeklyFraction: Double?
    /// Where the user asked for it, if at all.
    var weeklyRing: WeeklyRing = .off
    var innerFraction: Double?
    var expanded = false

    private var isExpanded: Bool { expanded || innerFraction != nil }
    private var mainTrackStroke: CGFloat { isExpanded ? NotchLayout.weeklyRingStroke : NotchLayout.trackStroke }
    private var mainProgressStroke: CGFloat { isExpanded ? NotchLayout.weeklyRingStroke : NotchLayout.progressStroke }
    private var mainInset: CGFloat {
        let hasSecondary = weeklyRing != .off && weeklyFraction != nil
        return isExpanded && ((weeklyRing == .outside && hasSecondary)
            || (innerFraction != nil && !hasSecondary))
            ? NotchLayout.expandedSecondaryInsideInset - mainTrackStroke / 2 : 0
    }

    private var diameter: CGFloat {
        NotchLayout.ringDiameter + (isExpanded ? NotchLayout.independentRingGrowth : 0)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.codenotchReduceTransparency) private var reduceTransparency
    @Environment(\.usageWatchLimit) private var watchLimit
    @Environment(\.usageCriticalLimit) private var criticalLimit
    @Environment(\.codenotchAccentColor) private var accentColor
    @Environment(\.weeklyRingDashed) private var weeklyRingDashed

    private var refreshReadingOpacity: Double {
        isRefreshing ? (reduceTransparency ? 0.75 : 0.3) : 1
    }

    private var refreshColor: Color {
        if localPerformance != nil || localContextFraction != nil {
            return localPerformance?.band.color ?? Palette.textSecondary
        }
        return usedFraction == nil ? Palette.textSecondary : band.color(accent: accentColor)
    }

    private var band: UsageBand {
        guard !isBlocked else { return .exhausted }
        return UsageBand.band(for: usedFraction ?? 0, watchLimit: watchLimit, criticalLimit: criticalLimit)
    }
    private var sweep: CGFloat { CGFloat(min(max(usedFraction ?? 0, 0), 1)) }
    private var localSweep: CGFloat { CGFloat(min(max(localContextFraction ?? 1, 0), 1)) }
    private var primaryColor: Color {
        isStale ? Palette.textSecondary : band.color(accent: accentColor)
    }

    private var weeklyBand: UsageBand {
        isBlocked ? .exhausted : UsageBand.band(for: weeklyFraction ?? 0, watchLimit: watchLimit, criticalLimit: criticalLimit)
    }
    private var weeklySweep: CGFloat { CGFloat(min(max(weeklyFraction ?? 0, 0), 1)) }

    /// Inside, the weekly ring and the working indicator want the same band —
    /// 1.03pt apart, one of them spinning. Rather than shave both until neither
    /// is legible, the transient one wins: while a provider is working that is
    /// the more urgent fact, and the week is still a hover away. Outside there
    /// is no contest, so nothing is given up there.
    private var isWorking: Bool {
        !isExpanded && weeklyRing == .inside && activity != nil && activity?.state != .idle
    }

    var body: some View {
        ZStack {
            // Dimming applies to the usage reading only. Whether Claude is
            // working right now is known first-hand and stays at full strength
            // even when the percentage behind it has gone stale.
            ZStack {
                Circle()
                    .inset(by: mainInset)
                    .strokeBorder(Palette.ringTrack, lineWidth: mainTrackStroke)

                if localPerformance != nil || localContextFraction != nil {
                    // Two facts on one ring: the arc is the context filling up,
                    // the colour is the last response's speed. Inset by half the
                    // stroke so a full arc lands exactly where the solid
                    // `strokeBorder` ring used to, and a runtime with no context
                    // reading looks as it always did. Grey until a speed exists:
                    // the quota colours would say something a local model has
                    // no quota to mean.
                    Circle()
                        .inset(by: mainInset + mainTrackStroke / 2)
                        .trim(from: 0, to: localSweep)
                        .stroke(
                            localPerformance?.band.color ?? Palette.textSecondary,
                            style: StrokeStyle(lineWidth: mainProgressStroke, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .opacity(refreshReadingOpacity)
                        .animation(.easeOut(duration: 0.2), value: isRefreshing)
                        .animation(NotchMotion.reading, value: localSweep)
                        .animation(NotchMotion.reading, value: localPerformance?.band)
                } else if usedFraction != nil {
                    Circle()
                        .inset(by: mainInset + mainTrackStroke / 2)
                        .trim(from: 0, to: sweep)
                        .stroke(
                            band.color(accent: accentColor),
                            style: StrokeStyle(lineWidth: mainProgressStroke, lineCap: .round)
                        )
                        // 以下保留旧版旋转读数的设计说明；现已由独立刷新短弧替代。
                        // Refreshing spins the reading itself rather than
                        // overlaying a separate spinner: the thing being
                        // refetched is the thing that should move, and a second
                        // arc on the same track only competes with it.
                        .rotationEffect(.degrees(-90))
                        .opacity(refreshReadingOpacity)
                        .animation(.easeOut(duration: 0.2), value: isRefreshing)
                        // A ring that snaps to a new value reads as a glitch; one
                        // that sweeps reads as a measurement being taken.
                        .animation(NotchMotion.reading, value: sweep)
                        .animation(NotchMotion.reading, value: band)
                }

                // The weekly limit, when there is one and it has been asked
                // for. Same start and direction as the headline arc, so the
                // two are read the same way round; thinner and at its own
                // radius, so which is which never has to be worked out.
                //
                // It carries its own band colour rather than borrowing the
                // headline's: a session at 12% beside a week at 91% is exactly
                // the case this exists for, and painting them the same colour
                // would hide it. Held slightly back in opacity so the headline
                // stays the one the eye lands on first.
                if let radius = weeklyRing.radius, weeklyFraction != nil, !isWorking {
                    let inset = !isExpanded
                        ? NotchLayout.ringDiameter / 2 - radius
                        : (weeklyRing == .inside ? NotchLayout.expandedSecondaryInsideInset
                            : NotchLayout.expandedSecondaryOutsideInset)

                    // A track of its own, for the same reason the headline has
                    // one: a week nobody has spent yet draws an arc of zero
                    // length, and without something behind it that is
                    // indistinguishable from the feature being broken. Codex
                    // opened its week at 0% and read as missing.
                    Circle()
                        .inset(by: inset)
                        .stroke(Palette.ringTrack,
                                style: StrokeStyle(lineWidth: NotchLayout.weeklyRingStroke,
                                                   dash: weeklyRingDashed ? [4, 2] : []))
                        .opacity(reduceTransparency ? 1 : 0.7)

                    Circle()
                        .inset(by: inset)
                        .trim(from: 0, to: weeklySweep)
                        .stroke(
                            weeklyBand.color(accent: accentColor),
                            style: StrokeStyle(lineWidth: NotchLayout.weeklyRingStroke,
                                               lineCap: weeklyRingDashed ? .butt : .round,
                                               dash: weeklyRingDashed ? [4, 2] : [])
                        )
                        .opacity((reduceTransparency ? 1 : 0.8) * refreshReadingOpacity)
                        .animation(.easeOut(duration: 0.2), value: isRefreshing)
                        .rotationEffect(.degrees(-90))
                        .animation(NotchMotion.reading, value: weeklySweep)
                        .animation(NotchMotion.reading, value: weeklyBand)
                }

                if let innerFraction {
                    Circle()
                        .inset(by: NotchLayout.independentRingInset)
                        .stroke(Palette.ringTrack, lineWidth: NotchLayout.independentRingStroke)
                    Circle()
                        .inset(by: NotchLayout.independentRingInset)
                        .trim(from: 0, to: CGFloat(min(max(innerFraction, 0), 1)))
                        .stroke(UsageBand.band(for: innerFraction, watchLimit: watchLimit, criticalLimit: criticalLimit).color(accent: accentColor),
                                style: StrokeStyle(lineWidth: NotchLayout.independentRingStroke, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .opacity(refreshReadingOpacity)
                        .animation(.easeOut(duration: 0.2), value: isRefreshing)
                        .animation(NotchMotion.reading, value: innerFraction)
                }

                if bot == nil {
                    QueryIconView(icon: icon, fallback: glyph, isStale: isStale,
                                  onDarkBackground: true, dimsStaleIcon: false)
                        .foregroundStyle(Palette.textPrimary)
                        // A spent limit dims its glyph so the ring reads as "waiting".
                        // Under reduce-transparency, boost opacity so it stays legible without low alpha.
                        .opacity(band == .exhausted ? (reduceTransparency ? 0.7 : 0.35) : 1)
                }
            }
            .opacity(isStale ? (reduceTransparency ? 0.75 : 0.45) : 1)

            if let bot {
                BotMarkView(presentation: bot)
                    .frame(width: NotchLayout.glyphSize * 1.4, height: NotchLayout.glyphSize * 1.4)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            if isRefreshing {
                SpinningArc(color: refreshColor, arcFraction: 0.16, dashed: false,
                            inset: mainInset + mainTrackStroke / 2, turns: !reduceMotion,
                            lineWidth: mainProgressStroke, duration: 0.85, startAngle: .pi / 2)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            if let activity, activity.state != .idle {
                ActivityArc(summary: activity)
            }
            if activity?.state == .waiting {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Palette.activityWaiting)
                    .background(Circle().fill(Palette.notch))
                    .offset(x: diameter / 2 - 4, y: -diameter / 2 + 4)
                    .accessibilityLabel(Text("Needs your answer"))
            }
        }
        .frame(width: diameter, height: diameter)
        // Pressed in while it works, and released when the answer lands. The
        // ring is the button, so the ring is what should feel pressed.
        .scaleEffect(isRefreshing && !reduceMotion ? 0.93 : 1)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.62), value: isRefreshing)
            // 以下保留旧版有限旋转的说明；现在通过移除动画层结束刷新动画。
            // Exactly one turn, and it stops by itself.
            //
            // The obvious spelling is a `repeatForever` linear spin started on
            // the way in and cancelled on the way out — but `repeatForever` does
            // not stop when you set the value back, and if the value you set is
            // the one it is already animating toward, nothing changes and it
            // simply keeps going. The ring then spins for ever after a refresh
            // that finished half a second in.
            //
            // A single finite turn has no cancellation problem at all: 360° is
            // the same angle as 0°, so it lands exactly where the reading
            // belongs. It eases out, so it settles rather than stopping dead.
    }
}

/// The inner indicator: a short arc that spins while work is happening, and a
/// full pulsing ring when something is blocked waiting on you.
private struct ActivityArc: View {
    let summary: ActivitySummary

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.codenotchReduceTransparency) private var reduceTransparency
    @State private var pulsing = false

    /// How much of the circle the moving arc covers.
    private let arcFraction: CGFloat = 0.25

    private var inset: CGFloat {
        (NotchLayout.ringDiameter - NotchLayout.activityDiameter) / 2
    }

    var body: some View {
        Group {
            switch summary.state {
            case .working: spinner
            case .waiting, .success: pulse
            case .idle:    EmptyView()
            }
        }
        .frame(width: NotchLayout.ringDiameter, height: NotchLayout.ringDiameter)
    }

    /// Dots are a line of things: with requests queued behind the running one
    /// the arc becomes a ring of them, still turning, so a backed-up model is
    /// told apart from a busy one at a glance.
    private var queued: Bool { summary.queued > 0 }

    /// Turned by Core Animation, not by SwiftUI.
    ///
    /// A `repeatForever` rotation re-runs the hosting view's layout on every
    /// frame, and the notch is one hosting view: while any session was working
    /// that alone kept the app near 4% of a core, which is most of the time
    /// for anyone who leaves Claude Code running. A layer animation is carried
    /// out by the render server and costs the app nothing between frames.
    private var spinner: some View {
        SpinningArc(
            color: summary.color,
            arcFraction: queued ? 1 : arcFraction,
            dashed: queued,
            inset: inset,
            turns: !reduceMotion
        )
    }

    private var pulse: some View {
        Circle()
            .inset(by: inset)
            .stroke(summary.color, lineWidth: NotchLayout.activityStroke)
            .opacity(pulsing ? (reduceTransparency ? 0.65 : 0.3) : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
            .onDisappear { pulsing = false }
    }
}

struct ProviderCell: View {
    let snapshot: ProviderSnapshot
    var activity: ActivitySummary?
    var isRefreshing: Bool = false
    var bot: BotPresentation?
    var weeklyRing: WeeklyRing = .off
    var codeSwitchQuotaRatiosEnabled: Bool = false
    var independentInnerRing: Bool = false
    var cellRingDiameter: CGFloat = NotchLayout.ringDiameter
    var now: Date = Date()

    private struct QuotaReading {
        let snapshot: ProviderSnapshot
        let ratios: CodeSwitchQuotaRings?
        let inner: CodeSwitchQuotaRings.Reading?

        var mainFraction: Double? { ratios?.main.fraction ?? snapshot.ringFraction }
        var secondaryFraction: Double? { snapshot.secondaryWindow?.usedFraction }
    }

    private var quotaReading: QuotaReading {
        let ratios = CodeSwitchQuotaRings.reading(for: snapshot, enabled: codeSwitchQuotaRatiosEnabled, now: now)
        return QuotaReading(
            snapshot: independentInnerRing ? IndependentQuotaRing.originalQuotas(in: snapshot) : snapshot,
            ratios: independentInnerRing ? nil : ratios,
            inner: independentInnerRing ? IndependentQuotaRing.reading(for: snapshot, ratios: ratios) : nil)
    }

    var innerReading: CodeSwitchQuotaRings.Reading? { quotaReading.inner }
    var displayedMainFraction: Double? { quotaReading.mainFraction }
    var displayedSecondaryFraction: Double? { quotaReading.secondaryFraction }

    /// A dash, not "0%": nothing read is not the same as nothing used.
    private func makeReadingText(_ reading: QuotaReading) -> String {
        if snapshot.hasReading, let fraction = reading.inner?.fraction ?? reading.ratios?.main.fraction {
            return Percent.text(for: fraction) + "%"
        }
        return snapshot.hasReading ? reading.snapshot.headlineText : "—"
    }

    var body: some View {
        let reading = quotaReading
        let cellDiameter = max(cellRingDiameter, NotchLayout.ringDiameter
            + (independentInnerRing ? NotchLayout.independentRingGrowth : 0))
        let isLocal = snapshot.localModel != nil
        let cellSize = NotchLayout.cellSize(ringDiameter: cellDiameter, isLocal: isLocal)
        let readingText = makeReadingText(reading)
        let ringText = makeRingText(reading)
        VStack(spacing: NotchLayout.ringLabelGap) {
            ProviderRing(
                usedFraction: snapshot.localModel == nil && snapshot.hasReading
                    ? reading.mainFraction : nil,
                glyph: snapshot.glyph,
                isStale: snapshot.status.isStale || !snapshot.hasReading,
                isBlocked: snapshot.block != nil,
                activity: activity,
                isRefreshing: isRefreshing, bot: bot, icon: snapshot.icon,
                localPerformance: snapshot.localPerformance,
                localContextFraction: snapshot.localContextFraction,
                weeklyFraction: snapshot.hasReading
                    ? reading.secondaryFraction : nil,
                weeklyRing: weeklyRing,
                innerFraction: reading.inner?.fraction,
                expanded: independentInnerRing
            )
            .frame(width: cellDiameter, height: cellDiameter)
            Text(readingText)
                .font(Typography.percent)
                .foregroundStyle(snapshot.showsLocalPerformance && snapshot.localPerformance == nil
                                 ? Palette.textSecondary : Palette.textPrimary)
                // Keep local speeds inside the ring's column so longer units
                // cannot consume the notch's existing side margins.
                .lineLimit(1)
                .minimumScaleFactor(snapshot.localModel == nil ? 0.65 : 0.5)
                .fixedSize(horizontal: false, vertical: false)
                .frame(width: NotchLayout.cellLabelWidth(isLocal: isLocal),
                       height: NotchLayout.percentLineHeight)
                .contentTransition(.numericText())
                .animation(NotchMotion.reading, value: readingText)
        }
        .frame(width: cellSize.width, height: cellSize.height)
        .help(ringText ?? snapshot.headline?.summary ?? snapshot.statusMessage ?? snapshot.displayName)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(makeAccessibilityText(ringText: ringText, readingText: readingText))
    }

    /// Everything the cell says, as one sentence for VoiceOver and the tests.
    var accessibilityText: String {
        let reading = quotaReading
        return makeAccessibilityText(ringText: makeRingText(reading), readingText: makeReadingText(reading))
    }

    private func makeAccessibilityText(ringText: String?, readingText: String) -> String {
        snapshot.localModel.map {
            "\($0.brand.map { "\($0.displayName), " } ?? "")\($0.name), \(snapshot.displayName) local, \(snapshot.showsLocalPerformance ? (snapshot.localPerformance.map { "Last generation speed \($0.speedText), \($0.band.label)" } ?? "Speed not measured") : "Loaded"), \($0.detail)\(localActivityText)\(localLedgerText)"
        } ?? "\(snapshot.displayName), \(ringText ?? readingText)"
    }

    var quotaRingText: String? {
        makeRingText(quotaReading)
    }

    private func makeRingText(_ reading: QuotaReading) -> String? {
        if independentInnerRing {
            let original = reading.snapshot
            var parts = original.headline.map { ["\(L10n.t("Main ring")): \($0.label), \($0.summary)"] } ?? []
            if weeklyRing != .off, let secondary = original.secondaryWindow {
                parts.append("\(L10n.t("Secondary quota ring")): \(secondary.label), \(secondary.summary)")
            }
            if let innerReading = reading.inner {
                parts.append("\(L10n.t("Independent inner ring")): \(innerReading.summary)")
            }
            return snapshot.hasReading ? parts.joined(separator: "; ") : nil
        }
        if let ratios = reading.ratios, snapshot.hasReading {
            let main = "\(L10n.t("Main ring")): \(ratios.main.summary)"
            guard weeklyRing != .off,
                  let secondary = ratios.secondary,
                  !(weeklyRing == .inside && activity != nil && activity?.state != .idle) else { return main }
            let position = weeklyRing == .inside ? L10n.t("Inner ring") : L10n.t("Outer ring")
            return "\(main); \(position): \(secondary.summary)"
        }
        guard weeklyRing != .off, snapshot.hasReading,
              let secondary = snapshot.secondaryWindow else { return nil }
        if weeklyRing == .inside, let activity, activity.state != .idle { return nil }
        let main = snapshot.headline.map { "\(L10n.t("Main ring")): \($0.label), \($0.summary)" }
        let position = weeklyRing == .inside ? L10n.t("Inner ring") : L10n.t("Outer ring")
        return [main, "\(position): \(secondary.label), \(secondary.summary)"]
            .compactMap { $0 }.joined(separator: "; ")
    }

    /// What the model is doing, the way the tooltip's header says it.
    private var localActivityText: String {
        guard let activity, activity.state == .working else { return "" }
        let phase = activity.sessions.first?.name ?? "Working"
        return activity.queued > 0 ? ", \(phase), \(activity.queued) queued" : ", \(phase)"
    }

    private var localLedgerText: String {
        guard let ledger = snapshot.localLedger else { return "" }
        let context = snapshot.localContextFraction.map { ", Context \(Percent.text(for: $0))% full" } ?? ""
        return "\(context), Tokens today \(ledger.tokensTodayText), \(ledger.requestsTodayText) requests"
    }
}

private struct WeeklyRingDashedKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var weeklyRingDashed: Bool {
        get { self[WeeklyRingDashedKey.self] }
        set { self[WeeklyRingDashedKey.self] = newValue }
    }
}

/// The working arc as a shape layer: a quarter of the activity circle from
/// 3 o'clock clockwise, or the whole circle as dots while requests are queued,
/// turning clockwise once every 1.1 seconds.
private struct SpinningArc: NSViewRepresentable {
    let color: Color
    let arcFraction: CGFloat
    let dashed: Bool
    let inset: CGFloat
    let turns: Bool
    var lineWidth: CGFloat = NotchLayout.activityStroke
    var duration: CFTimeInterval = SpinningArcView.turnDuration
    var startAngle: CGFloat = 0

    func makeNSView(context: Context) -> SpinningArcView { SpinningArcView() }

    func updateNSView(_ view: SpinningArcView, context: Context) {
        view.configure(color: NSColor(color), arcFraction: arcFraction,
                       dashed: dashed, inset: inset, turns: turns,
                       lineWidth: lineWidth, duration: duration, startAngle: startAngle)
    }

    static func dismantleNSView(_ view: SpinningArcView, coordinator: ()) {
        view.arc.removeAnimation(forKey: SpinningArcView.animationKey)
    }
}

final class SpinningArcView: NSView {
    static let turnDuration: CFTimeInterval = 1.1
    static let animationKey = "turn"

    let arc = CAShapeLayer()
    private var color: NSColor = .white
    private var inset: CGFloat = 0
    private var turns = true
    private var duration: CFTimeInterval = SpinningArcView.turnDuration
    private var startAngle: CGFloat = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        arc.fillColor = nil
        arc.lineCap = .round
        arc.lineWidth = NotchLayout.activityStroke
        arc.strokeStart = 0
        layer?.addSublayer(arc)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Decoration only: clicks belong to the ring and the notch beneath it.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(color: NSColor, arcFraction: CGFloat, dashed: Bool, inset: CGFloat, turns: Bool,
                   lineWidth: CGFloat = NotchLayout.activityStroke,
                   duration: CFTimeInterval = SpinningArcView.turnDuration, startAngle: CGFloat = 0) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.color = color
        self.inset = inset
        self.turns = turns
        if self.duration != duration {
            arc.removeAnimation(forKey: Self.animationKey)
        }
        self.duration = duration
        self.startAngle = startAngle
        arc.lineWidth = lineWidth
        arc.strokeEnd = arcFraction
        arc.lineDashPattern = dashed
            ? [0.01, NSNumber(value: Double(NotchLayout.activityStroke * 2.2))]
            : nil
        applyColor()
        rebuildPath()
        CATransaction.commit()
        updateAnimation()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rebuildPath()
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAnimation()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColor()
    }

    private func applyColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            arc.strokeColor = color.cgColor
        }
    }

    /// The layer's own coordinates run y-up, so a visually clockwise circle
    /// starting at 3 o'clock is drawn with decreasing angles — the same start
    /// and direction as SwiftUI's `Circle().trim(from: 0, …)`.
    private func rebuildPath() {
        arc.frame = bounds
        let radius = max(0, min(bounds.width, bounds.height) / 2 - inset)
        let path = CGMutablePath()
        path.addArc(center: CGPoint(x: bounds.midX, y: bounds.midY), radius: radius,
                    startAngle: startAngle, endAngle: startAngle - 2 * .pi, clockwise: true)
        arc.path = path
    }

    /// Re-added whenever it has gone missing: AppKit drops layer animations
    /// when a window leaves the screen, and the notch's panel does.
    private func updateAnimation() {
        guard turns, window != nil else {
            arc.removeAnimation(forKey: Self.animationKey)
            return
        }
        guard arc.animation(forKey: Self.animationKey) == nil else { return }
        let turn = CABasicAnimation(keyPath: "transform.rotation.z")
        turn.fromValue = 0
        turn.toValue = -2 * Double.pi
        turn.duration = duration
        turn.timingFunction = CAMediaTimingFunction(name: .linear)
        turn.repeatCount = .infinity
        turn.isRemovedOnCompletion = false
        arc.add(turn, forKey: Self.animationKey)
    }
}
