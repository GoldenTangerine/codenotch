/**
 @name: 机器人外观与动画
 @Descripttion: 管理机器人显示配置、预览与按可见性运行的动画。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-18 10:21:17
 @LastEditTime: 2026-09-18 10:21:17
 @FilePath: Sources/Features/BotMark/BotMarkView.swift
 */
import AppKit
import QuartzCore
import SwiftUI

struct BotMarkView: NSViewRepresentable {
    var presentation: BotPresentation
    var playbackStore: BotPlaybackStore? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeNSView(context: Context) -> BotDrawingView { BotDrawingView() }

    func updateNSView(_ view: BotDrawingView, context: Context) {
        view.configure(presentation, reduceMotion: reduceMotion, playbackStore: playbackStore)
    }

    static func dismantleNSView(_ view: BotDrawingView, coordinator: ()) { view.detach() }
}

// 仅缓存活动供应商的引擎，不保留视图、窗口或计时器；轮播离屏期间不推进动画。
@MainActor
final class BotPlaybackStore {
    private var engines: [String: BotMarkEngine] = [:]
    var count: Int { engines.count }

    func engine(for providerID: String) -> BotMarkEngine {
        if let engine = engines[providerID] {
            engine.resumeClock()
            return engine
        }
        let engine = BotMarkEngine()
        engines[providerID] = engine
        return engine
    }

    func retainProviders(_ ids: Set<String>) {
        engines = engines.filter { ids.contains($0.key) }
    }
}

// 一个窗口只有一个时钟；弱引用机器人，最后一个停止后释放显示链接。
@MainActor
final class BotWindowClock: NSObject {
    private static var clocks: [ObjectIdentifier: BotWindowClock] = [:]
    private weak var window: NSWindow?
    private let views = NSHashTable<BotDrawingView>.weakObjects()
    private var link: CADisplayLink?
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var sleeping = false
    private(set) var tickCount = 0
    var isRunning: Bool { link != nil }

    static func attach(_ view: BotDrawingView, to window: NSWindow) -> BotWindowClock {
        let key = ObjectIdentifier(window)
        let clock = clocks[key] ?? BotWindowClock(window: window)
        clocks[key] = clock
        clock.views.add(view)
        clock.update()
        return clock
    }

    private init(window: NSWindow) {
        self.window = window
        super.init()
        let center = NotificationCenter.default
        for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                     NSWindow.didDeminiaturizeNotification, NSWindow.didChangeScreenNotification] {
            observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.update() }
            })
        }
        observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                for view in self.views.allObjects { view.detach() }
            }
        })
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.willSleepNotification,
                     NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification] {
            workspaceObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.sleeping = name == NSWorkspace.screensDidSleepNotification || name == NSWorkspace.willSleepNotification
                    self?.update()
                }
            })
        }
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    func remove(_ view: BotDrawingView) {
        views.remove(view)
        update()
        if views.allObjects.isEmpty, let window {
            Self.clocks.removeValue(forKey: ObjectIdentifier(window))
        }
    }

    func update() {
        let visible = !sleeping && window?.isVisible == true && window?.occlusionState.contains(.visible) == true
        var running = false
        for view in views.allObjects {
            let eligible = visible && view.canAnimate
            view.setClockActive(eligible)
            running = running || eligible
        }
        guard running, let window else {
            link?.invalidate()
            link = nil
            return
        }
        guard link == nil else { return }
        let displayLink = window.displayLink(target: self, selector: #selector(tick(_:)))
        displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
        displayLink.add(to: .main, forMode: .common)
        link = displayLink
    }

    @objc private func tick(_ link: CADisplayLink) {
        update()
        guard self.link != nil else { return }
        tickCount += 1
        guard let window else { link.invalidate(); self.link = nil; return }
        let pointer = window.mouseLocationOutsideOfEventStream
        let date = Date()
        for view in views.allObjects where view.clockActive {
            view.advance(to: link.timestamp, date: date, pointerInWindow: pointer)
        }
    }
}

@MainActor
final class BotDrawingView: NSView {
    private var engine: BotMarkEngine?
    private var presentation: BotPresentation?
    private(set) var programme = BotMarkProgramme(states: ["idle"])
    private(set) var displayFrame: BotMarkFrame?
    private var config = BotMarkConfig()
    private var reduceMotion = false
    private(set) var clockActive = false
    private weak var clock: BotWindowClock?
    private var consumedEvent: UUID?
    private var visibilityObservers: [NSObjectProtocol] = []
    private var lastProgrammeUpdate = Date.distantPast
    private var quietTimer: Timer?
    private var colors: [Color: CGColor] = [:]
    private(set) var renderedFrames = 0
    private struct StillKey: Hashable {
        let state: String
        let shape: String
        let persona: String
        let gaze: Double
        let direction: BotMarkGaze
        let mood: String
        let size: CGFloat
    }
    private static var stills: [StillKey: BotMarkFrame] = [:]
    private static let rgbColorSpace = CGColorSpaceCreateDeviceRGB()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    var canAnimate: Bool {
        presentation?.active == true && !reduceMotion && !isHiddenOrHasHiddenAncestor
            && !visibleRect.intersection(bounds).isEmpty && engine != nil
    }

    func configure(_ next: BotPresentation, reduceMotion: Bool, now: Date = Date(),
                   playbackStore: BotPlaybackStore? = nil) {
        guard BotMarkLibrary.available != nil else { return }
        let quietChanged = presentation?.isQuiet(at: lastProgrammeUpdate) != next.isQuiet(at: now)
        let changed = presentation != next || self.reduceMotion != reduceMotion || quietChanged
        if presentation?.id != next.id {
            engine = playbackStore?.engine(for: next.id) ?? BotMarkEngine()
            displayFrame = nil
            consumedEvent = next.event?.id
        }
        if next.waiting, presentation?.waiting != true { engine?.resumeClock() }
        presentation = next
        self.reduceMotion = reduceMotion
        if changed {
            updateProgramme(date: now, pointed: reduceMotion ? false : pointed)
            if reduceMotion {
                // 状态或外观改变时才求解静态姿态，指针移动不会重复求解。
                var still = programme
                still.states = [programme.states.first ?? "idle"]
                still.particlesEnabled = false
                still.event = nil
                still.pointer = nil
                let state = still.states[0]
                let key = StillKey(state: state, shape: still.shape,
                                   persona: next.appearance.persona(for: next.id).rawValue,
                                   gaze: still.gazeBias, direction: still.gaze,
                                   mood: still.mood.rawValue, size: bounds.width)
                if let cached = Self.stills[key] {
                    displayFrame = cached
                } else {
                    let solver = BotMarkEngine()
                    for step in 0...180 { displayFrame = solver.advance(to: Double(step) / 60, programme: still) }
                    var step = 181
                    while solver.isBlinking && step < 300 {
                        displayFrame = solver.advance(to: Double(step) / 60, programme: still)
                        step += 1
                    }
                    if Self.stills.count >= 128 { Self.stills.removeAll(keepingCapacity: true) }
                    Self.stills[key] = displayFrame
                }
                config = still.configuration(for: state)
            } else if displayFrame == nil, let engine {
                displayFrame = engine.advance(to: CACurrentMediaTime(), programme: programme)
                config = programme.configuration(for: engine.state)
            }
            needsDisplay = true
        }
        if !next.active || reduceMotion {
            setClockActive(false)
            consumedEvent = next.event?.id
        }
        updateQuietTimer(at: now)
        clock?.update()
    }

    private func updateQuietTimer(at now: Date) {
        guard reduceMotion, let presentation, presentation.active, !presentation.waiting,
              presentation.mood == .idle || presentation.mood == .spent,
              !isHiddenOrHasHiddenAncestor,
              let deadline = presentation.quietDeadline, deadline >= now else {
            quietTimer?.invalidate()
            quietTimer = nil
            return
        }
        let fireDate = deadline.addingTimeInterval(0.01)
        guard quietTimer?.fireDate != fireDate else { return }
        quietTimer?.invalidate()
        // 仅在睡眠期限到达时重算静态姿态，不恢复逐帧时钟。
        let timer = Timer(fire: fireDate, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.quietTimer = nil
                self.refreshStaticPresentation()
            }
        }
        quietTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func refreshStaticPresentation() {
        if reduceMotion, let presentation { configure(presentation, reduceMotion: true) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        detach()
        if let window { clock = BotWindowClock.attach(self, to: window) }
        observeVisibility()
        if window != nil { refreshStaticPresentation() }
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        observeVisibility()
        clock?.update()
    }

    override func viewDidHide() {
        super.viewDidHide()
        quietTimer?.invalidate()
        quietTimer = nil
        clock?.update()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        refreshStaticPresentation()
        clock?.update()
    }

    private func observeVisibility() {
        for observer in visibilityObservers { NotificationCenter.default.removeObserver(observer) }
        visibilityObservers.removeAll()
        guard window != nil else { return }
        var ancestor: NSView? = self
        while let view = ancestor {
            view.postsBoundsChangedNotifications = true
            view.postsFrameChangedNotifications = true
            for name in [NSView.boundsDidChangeNotification, NSView.frameDidChangeNotification] {
                visibilityObservers.append(NotificationCenter.default.addObserver(
                    forName: name, object: view, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated {
                            self?.refreshStaticPresentation()
                            self?.clock?.update()
                        }
                    })
            }
            ancestor = view.superview
        }
    }

    deinit {
        quietTimer?.invalidate()
        for observer in visibilityObservers { NotificationCenter.default.removeObserver(observer) }
    }

    override func layout() {
        super.layout()
        clock?.update()
    }

    func detach() {
        quietTimer?.invalidate()
        quietTimer = nil
        for observer in visibilityObservers { NotificationCenter.default.removeObserver(observer) }
        visibilityObservers.removeAll()
        setClockActive(false)
        clock?.remove(self)
        clock = nil
    }

    func setClockActive(_ active: Bool) {
        guard active != clockActive else { return }
        clockActive = active
        engine?.resumeClock()
        programme.event = nil
        // 重新显示只反映当前状态，不重放折叠或遮挡期间的庆祝。
        consumedEvent = presentation?.event?.id
    }

    private func updateProgramme(date: Date, pointed: Bool) {
        guard let presentation else { return }
        let persona = presentation.appearance.persona(for: presentation.id)
        programme = BotMarkProgramme.forMood(presentation.mood, persona: persona,
            isQuiet: presentation.isQuiet(at: date), isPointedAt: pointed,
            isWaiting: presentation.waiting, at: date)
        programme.shape = presentation.appearance.shape
        programme.gazeBias = presentation.gazeBias
        programme.gaze = presentation.gaze
        programme.color = presentation.appearance.color(for: presentation.id, brand: presentation.brand)
        programme.eyeColor = BotAppearance.eyeColor(for: programme.color)
        programme.viewWidth = max(1, bounds.width)
        programme.particlesEnabled = !reduceMotion
        lastProgrammeUpdate = date
    }

    private var pointed = false

    func pointer(at pointInWindow: CGPoint) -> CGPoint? {
        let local = convert(pointInWindow, from: nil)
        let inside: Bool
        if let region = presentation?.pointerRegion, let window {
            let point = CGPoint(x: pointInWindow.x, y: window.contentLayoutRect.height - pointInWindow.y)
            inside = region.contains(point)
        } else {
            inside = bounds.contains(local)
        }
        guard inside else { return nil }
        let radius = max(1, bounds.width / 2)
        return CGPoint(x: (local.x - bounds.midX) / (radius * 4),
                       y: (local.y - bounds.midY) / (radius * 4))
    }

    func advance(to timestamp: Double, date: Date, pointerInWindow: CGPoint) {
        guard clockActive, let engine, let presentation else { return }
        let local = convert(pointerInWindow, from: nil)
        let isPointed = bounds.contains(local)
        if pointed != isPointed || date.timeIntervalSince(lastProgrammeUpdate) >= 1 {
            pointed = isPointed
            updateProgramme(date: date, pointed: isPointed)
        }
        programme.pointer = pointer(at: pointerInWindow)
        programme.event = nil
        if let event = presentation.event, event.id != consumedEvent {
            consumedEvent = event.id
            if date.timeIntervalSince(event.occurredAt) < 1, !presentation.waiting {
                programme.event = event.kind
            }
        }
        displayFrame = engine.advance(to: timestamp, programme: programme)
        config = programme.configuration(for: engine.state)
        renderedFrames += 1
        needsDisplay = true
    }

    private func cgColor(_ color: Color) -> CGColor {
        if let cached = colors[color] { return cached }
        let result = NSColor(color).cgColor
        if colors.count >= 256 { colors.removeAll(keepingCapacity: true) }
        colors[color] = result
        return result
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let frame = displayFrame, let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        defer { context.restoreGState() }
        let extent = min(bounds.width, bounds.height)
        let scale = extent / (frame.viewBoxRadius * 2)
        context.translateBy(x: (bounds.width - extent) / 2, y: (bounds.height - extent) / 2)
        if frame.flipX { context.translateBy(x: extent, y: 0); context.scaleBy(x: -1, y: 1) }
        context.scaleBy(x: scale, y: scale)
        let origin = BotMarkFrame.viewBoxCentre - frame.viewBoxRadius
        context.translateBy(x: -origin, y: -origin)

        func paint(_ particles: [BotMarkFrame.Painted]) {
            for particle in particles {
                context.saveGState()
                context.setAlpha(particle.opacity)
                context.addPath(particle.path)
                switch particle.paint {
                case .solid(let color):
                    context.setFillColor(cgColor(color)); context.fillPath()
                case .gradient(let stops, let start, let end):
                    context.clip()
                    if let gradient = CGGradient(colorsSpace: Self.rgbColorSpace,
                                                 colors: stops.map { cgColor($0) } as CFArray, locations: nil) {
                        context.drawLinearGradient(gradient, start: start, end: end, options: [])
                    }
                }
                context.restoreGState()
            }
        }
        paint(frame.backParticles)
        for shape in frame.shapes {
            context.saveGState()
            context.setAlpha(shape.opacity)
            context.addPath(shape.path)
            if let width = shape.strokeWidth {
                context.setStrokeColor(cgColor(config.color)); context.setLineWidth(width)
                context.setLineCap(.round); context.setLineJoin(.round); context.strokePath()
            } else {
                context.setFillColor(cgColor(config.color)); context.fillPath()
            }
            context.restoreGState()
        }
        context.saveGState()
        context.concatenate(frame.transform)
        context.setAlpha(frame.opacity)
        context.setFillColor(cgColor(config.color))
        context.addPath(frame.headPath); context.fillPath()
        context.saveGState()
        context.addPath(frame.headPath); context.clip()
        for eye in frame.eyes where eye.visible {
            context.saveGState()
            context.concatenate(eye.transform)
            context.setFillColor(cgColor(config.eyeColor))
            context.addPath(eye.path); context.fillPath()
            context.restoreGState()
        }
        context.restoreGState()
        context.restoreGState()
        paint(frame.frontParticles)
        if let badge = frame.badge {
            context.saveGState()
            context.concatenate(frame.transform)
            context.setAlpha(frame.opacity)
            let rect = CGRect(x: badge.centre.x - badge.radius, y: badge.centre.y - badge.radius,
                              width: badge.radius * 2, height: badge.radius * 2)
            context.setStrokeColor(cgColor(config.eyeColor)); context.setLineWidth(10)
            context.strokeEllipse(in: rect)
            context.setFillColor(cgColor(config.badgeColor)); context.fillEllipse(in: rect)
            context.restoreGState()
        }
    }
}
