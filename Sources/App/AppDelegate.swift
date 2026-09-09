/**
 @name: 应用生命周期
 @Descripttion: 连接应用服务和用户设置。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-08 14:12:37
 @LastEditTime: 2026-09-08 14:12:37
 @FilePath: Sources/App/AppDelegate.swift
 */
import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notchFleet: NotchFleet?
    private var store: UsageStore?
    private var codeSwitch: CodeSwitchBridge?
    private var monitors: [String: any AgentActivityMonitor] = [:]
    private var preferences: Preferences?
    private var settings: SettingsWindowController?
    private var whatsNew: WhatsNewWindowController?
    /// Held for the life of the app: releasing it stops the scheduled checks.
    private var updater: Updater?
    private var thresholdNotifier: ThresholdNotifier?
    private var statusItem: StatusItemController?
    private var cancellables = Set<AnyCancellable>()
    /// Turns the monitors' running commentary into the one event worth
    /// interrupting for: an agent that has just stopped working.
    private var completions = SessionCompletionWatcher()
    private let hookMonitor = HookSessionMonitor()
    private var hookSettings: HookSettings?
    private var nativeSessions: [String: [AgentSession]] = [:]
    private var localSnapshots: [ProviderSnapshot] = []
    private var activitySources: [String: String] = [:]
    private var activityRouting: ActivityRouting?
    private var pendingAnnouncements: [SessionCompletionWatcher.Event] = []
    private var announcementWork: DispatchWorkItem?

    /// The unit bundle is hosted by this app, so `xcodebuild test` launches it
    /// for real. Without this guard every test run put a live request on the
    /// usage endpoint — which is both wrong on its own terms and, on an endpoint
    /// that rate-limits, actively harmful.
    private var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    /// Every Claude Code configuration directory on this Mac — `~/.claude` and
    /// any `~/.claude-<slug>` — found once at launch. Each gets a usage
    /// provider and a session monitor of its own, keyed by the same id, so a
    /// work login's sessions spin the work ring and nobody else's.
    private let claudeProfiles = ClaudeProfile.discover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set here, not in the Info.plist: this call is applied at launch and
        // overrides `LSUIElement` either way. Removing the plist key alone left
        // the app registered as a UIElement with no Dock tile, which looked
        // exactly like the icon having failed to install. The user's choice
        // replaces this a moment later, once preferences exist.
        NSApp.setActivationPolicy(.regular)
        guard !isRunningTests else { return }

        // Before Preferences reads anything, or the first launch flag and
        // every choice would be read from an empty domain.
        Preferences.migrateFromPreviousName()
        let preferences = Preferences()
        self.preferences = preferences

        // One notch per display: the fleet owns a controller for each screen
        // the scope asks for and fans every reading out to all of them. The
        // stored edge goes in up front, before any panel is ever put up — the
        // sink below delivers on the next run loop turn, by which time the
        // notch would already have flashed on the default edge.
        let fleet = NotchFleet(scope: preferences.notchScope, edge: preferences.notchEdge)
        self.notchFleet = fleet

        // `CODENOTCH_DEMO=1` puts the design frame's three providers on screen
        // with its numbers, for screenshots and for eyeballing the layout.
        if ProcessInfo.processInfo.environment["CODENOTCH_DEMO"] == "1" {
            localSnapshots = Fixtures.snapshots()
            activitySources = Dictionary(uniqueKeysWithValues: localSnapshots.map { ($0.id, $0.id) })
            fleet.setSnapshots(localSnapshots)
        } else {
            // Nothing needs a browser session at the moment. `WebSessionProvider`
            // and `Sites.perplexity` are kept: they are the working pattern for a
            // site behind bot management, and re-registering is one line.
            let webProviders: [WebSessionProvider] = []
            fleet.signInItems = webProviders.map { provider in
                (title: String(localized: "Sign in to \(provider.displayName)…"),
                 action: { [weak provider] in provider?.presentSignIn() })
            }

            // Cursor reads the editor's session, or cursor-agent's if the
            // editor is missing — never a browser one: signing into
            // cursor.com separately created a second, empty account.
            //
            // Built *after* preferences and told what is switched off, so the
            // very first list it draws already excludes them. Constructed first,
            // it drew every provider from the archive and only dropped the
            // switched-off ones once the binding below delivered.
            Log.usage.info("claude profiles: \(self.claudeProfiles.map(\.displayPath).joined(separator: ", "), privacy: .public)")
            let nativeProviders: [UsageProvider] = claudeProfiles.map { ClaudeOAuthProvider(profile: $0) }
                    + [CursorLocalProvider(), CodexLocalProvider(), AntigravityProvider(),
                       GLMProvider(), GrokLocalProvider(), OpenCodeProvider(),
                       GitHubCopilotProvider(),
                       // A closure, not the value: the provider is an actor and
                       // re-reads the budget on every fetch, so a ceiling typed
                       // into Settings applies without a restart.
                       GeminiAPIProvider(budget: {
                           Preferences.storedGeminiAPIMonthlyTokenBudget()
                       })]
                    + webProviders
            let catalog = QueryCatalog(providers: nativeProviders, disconnected: preferences.disconnectedProviders)
            let store = UsageStore(
                providers: catalog.providers(),
                disconnected: Set(catalog.entries.filter { !$0.enabled }.map(\.id)), configured: true
            )
            let applyCatalog: (Set<String>) -> Void = { [weak self, weak catalog, weak store, weak fleet, weak preferences] invalidated in
                guard let catalog, let store else { return }
                let disconnected = Set(catalog.entries.filter { !$0.enabled }.map(\.id))
                store.reconfigure(providers: catalog.providers(), disconnected: disconnected, invalidated: invalidated)
                preferences?.disconnectedProviders = disconnected
                fleet?.setActivitySourceIDs(Dictionary(uniqueKeysWithValues:
                    catalog.entries.filter { $0.usesLocalAccount }.map { ($0.id, $0.nativeID) }))
                self?.activitySources = Dictionary(uniqueKeysWithValues:
                    catalog.entries.filter { $0.usesLocalAccount }.map { ($0.id, $0.nativeID) })
                self?.updateActivity()
            }
            catalog.onChange = applyCatalog
            fleet.setActivitySourceIDs(Dictionary(uniqueKeysWithValues:
                catalog.entries.filter { $0.usesLocalAccount }.map { ($0.id, $0.nativeID) }))
            activitySources = Dictionary(uniqueKeysWithValues:
                catalog.entries.filter { $0.usesLocalAccount }.map { ($0.id, $0.nativeID) })
            preferences.disconnectedProviders = Set(catalog.entries.filter { !$0.enabled }.map(\.id))

            // The stored edge goes in before the panel is ever put up. The
            // sink below delivers on the next run loop turn, by which time the
            // notch has already been shown on the default edge — so without
            // this, every launch on any other edge opens with a flash of the
            // right-hand one and then crossfades away from it.
            fleet.apply(edge: preferences.notchEdge)
            fleet.restore(position: preferences.notchPosition)
            fleet.onPositionCommitted = { [weak preferences] position in
                preferences?.notchPosition = position
                preferences?.displayPreference = position.displayID.map(DisplayPreference.display) ?? .followActiveWindow
            }
            let updater = Updater()
            self.updater = updater

            let hookSettings = HookSettings(monitor: hookMonitor)
            self.hookSettings = hookSettings
            let settings = SettingsWindowController(
                preferences: preferences,
                // A closure so the sheet re-reads accounts each time it comes
                // forward; a snapshot here is what made a switched account keep
                // showing the old address until the app restarted.
                providers: { [weak store] in store?.providerSummaries ?? [] },
                updater: updater,
                signOut: { [weak store] in store?.signOut(providerID: $0) },
                signIn: { [weak store] in store?.signIn(providerID: $0) ?? false },
                switchAccount: { [weak store] in
                    store?.openAccountSource(providerID: $0) ?? false
                },
                retry: { [weak store] in store?.reauthorize(providerID: $0) },
                catalog: catalog, usageStore: store, hooks: hookSettings
            )
            fleet.onOpenSettings = { [weak settings] in settings?.show() }
            self.settings = settings

            // What changed, once per version — including on a fresh install,
            // where it is the introduction.
            let whatsNew = WhatsNewWindowController(
                preferences: preferences, version: updater.currentVersion
            )
            self.whatsNew = whatsNew

            // An agent app has no dock icon and no window: installed and
            // launched, it shows four empty rings on a screen edge and no
            // reason to look at them. Once, on the very first run, it opens the
            // one place that explains what to connect.
            //
            // Sequenced behind What's New rather than beside it: two windows
            // arriving together is one to dismiss before you can read either.
            let introduce = { [weak settings] in
                guard preferences.isFirstLaunch else { return }
                settings?.show()
            }
            whatsNew.onDismiss = introduce
            if !whatsNew.showIfNeeded() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: introduce)
            }

            let statusItem = StatusItemController { [weak settings] in settings?.show() }
            self.statusItem = statusItem
            statusItem.onRefreshProvider = { [weak store] id in store?.refresh(providerID: id) }
            statusItem.onRefreshAll = { [weak store] in store?.refreshNow() }

            preferences.$appPresence
                .receive(on: RunLoop.main)
                .sink { presence in
                    NSApp.setActivationPolicy(presence.activationPolicy)
                    if presence.wantsStatusItem { statusItem.show() } else { statusItem.hide() }
                }
                .store(in: &cancellables)

            preferences.$notchVisibility
                .receive(on: RunLoop.main)
                .sink { [weak fleet] in fleet?.apply($0) }
                .store(in: &cancellables)

            preferences.$notchTriggerHeight
                .receive(on: RunLoop.main)
                .sink { [weak fleet] in fleet?.apply(notchTriggerHeight: $0) }
                .store(in: &cancellables)

            preferences.$notchEdge
                .receive(on: RunLoop.main)
                .sink { [weak fleet, weak preferences] edge in
                    // Read before `apply(edge:)` moves the panel, so the new
                    // edge's own remembered nudge is what it lands at rather
                    // than the old edge's carried over onto it.
                    fleet?.apply(alongOffset: preferences?.offset(for: edge) ?? 0)
                    fleet?.apply(edge: edge)
                }
                .store(in: &cancellables)

            preferences.$notchScope
                .receive(on: RunLoop.main)
                .sink { [weak fleet] in fleet?.apply(scope: $0) }
                .store(in: &cancellables)

            preferences.$displayPreference
                .receive(on: RunLoop.main)
                .sink { [weak fleet] in fleet?.apply(displayPreference: $0) }
                .store(in: &cancellables)

            fleet.onReposition = { [weak preferences] offset in
                preferences?.setOffset(offset, for: preferences?.notchEdge ?? .right)
            }

            preferences.$resetTimeFormat
                .receive(on: RunLoop.main)
                .sink { [weak fleet] in fleet?.apply(resetTimeFormat: $0) }
                .store(in: &cancellables)

            preferences.$accentColor
                .receive(on: RunLoop.main)
                .sink { [weak fleet] in fleet?.apply(accentColor: $0) }
                .store(in: &cancellables)

            let codeSwitch = CodeSwitchBridge()
            self.codeSwitch = codeSwitch
            preferences.$codeSwitchEnabled
                .sink { [weak codeSwitch] in codeSwitch?.setEnabled($0) }
                .store(in: &cancellables)
            // Redraw the Gemini API ring against the new ceiling.
            //
            // `dropFirst` because `@Published` publishes the value it is given
            // at init, and a refresh there would race the store's first poll.
            // `receive(on:)` because `@Published` emits in `willSet` — the hop
            // to the next run loop pass is what lets the `didSet` persist the
            // number before the provider's closure goes looking for it.
            preferences.$geminiAPIMonthlyTokenBudget
                .dropFirst()
                .receive(on: RunLoop.main)
                .sink { [weak store, weak catalog] _ in
                    for entry in catalog?.entries ?? [] where entry.usesLocalAccount && entry.nativeID == "gemini-api" {
                        store?.refresh(providerID: entry.id)
                    }
                }
                .store(in: &cancellables)

            // Limit crossings become notifications here rather than inside
            // the store: the store fetches, the notifier decides what is
            // worth interrupting someone for, and neither needs to know the
            // other.
            let notifier = ThresholdNotifier(
                isMuted: { [weak preferences] in preferences?.isMutedAlerts(for: $0) ?? false },
                deliver: { ThresholdAlerts.deliver($0) }
            )
            self.thresholdNotifier = notifier

            store.$snapshots.combineLatest(codeSwitch.$snapshots)
                .receive(on: RunLoop.main)
                .sink { [weak self] local, linked in
                    let snapshots = local + linked
                    self?.localSnapshots = local
                    self?.updateActivity()
                    notifier.observe(snapshots)
                }
                .store(in: &cancellables)
            codeSwitch.$bindings.dropFirst().receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.updateActivity() }
                .store(in: &cancellables)
            store.start()
            fleet.onRefresh = { [weak store, weak codeSwitch] in
                store?.refreshNow()
                codeSwitch?.refresh()
            }
            fleet.onRefreshProvider = { [weak store, weak codeSwitch] id in
                if id.hasPrefix("code-switch:") { codeSwitch?.refresh() }
                else { store?.refresh(providerID: id) }
            }
            statusItem.onRefreshAll = fleet.onRefresh
            statusItem.onRefreshProvider = fleet.onRefreshProvider
            store.$refreshing
                .receive(on: RunLoop.main)
                .sink { [weak fleet] ids in fleet?.setRefreshing(ids) }
                .store(in: &cancellables)

            // CODENOTCH_DISCOVER=<url> loads that page in the signed-in WebView
            // and logs the API calls it makes — for finding an undocumented
            // endpoint by watching the site rather than guessing at path names.
            if let target = ProcessInfo.processInfo.environment["CODENOTCH_DISCOVER"],
               let url = URL(string: target),
               let provider = webProviders.first(where: { url.host?.contains($0.id) == true })
                   ?? webProviders.first {
                Task {
                    let calls = await provider.recordCalls(on: url)
                    Log.usage.notice("discovered: \(calls.joined(separator: "  "), privacy: .public)")
                }
            }
            self.store = store
        }

        // What each agent is doing right now, so the notch can say whether it is
        // still working without you switching to it.
        var monitors: [String: any AgentActivityMonitor] = [
            "cursor": CursorActivityMonitor(),
            "codex": CodexActivityMonitor(),
            "gemini": AntigravityActivityMonitor(),
            "grok": GrokActivityMonitor(),
            "gemini-api": GeminiCLIActivityMonitor()
        ]
        for profile in claudeProfiles {
            monitors[profile.id] = ClaudeSessionMonitor(directory: profile.sessionsDirectory)
        }
        for (id, monitor) in monitors {
            monitor.sessionsPublisher
                .receive(on: RunLoop.main)
                .sink { [weak self] live in
                    guard let self else { return }
                    self.nativeSessions[id] = live
                    // The publisher delivers on the main run loop, but the
                    // closure itself is nonisolated — the same assertion the
                    // notch controller's timers make.
                    MainActor.assumeIsolated { self.updateActivity() }
                }
                .store(in: &cancellables)
            monitor.start()
        }
        // Poll usage hard only while something is actually running.
        store?.isBusy = { [weak self] in
            self?.hookMonitor.state.merging(self?.nativeSessions ?? [:]).values.contains { $0.contains { $0.state == .busy } } ?? false
        }
        self.monitors = monitors
        hookMonitor.$state.dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateActivity() }
            .store(in: &cancellables)
        hookMonitor.start()

        // Applied last, right before the panel goes up: every one of these
        // calls a `NotchFleet.apply(...)` that can trigger `reconcile()` on
        // its own — `displayPreference` always does, being how the very
        // first controller gets created — and `reconcile()` copies the
        // fleet's callbacks (`onOpenSettings`, `onRefreshProvider`, ...) into
        // that controller at creation time, not through a live reference.
        // Calling any of these earlier, before those callbacks were set
        // above, silently built the one controller this app ever has with
        // every action wired to nothing: the panel still opened and rings
        // still drew, so there was nothing to notice except every click
        // doing exactly nothing. `fleet.show()`'s own reconcile only ever
        // repositions an existing controller — it does not re-copy them —
        // so this has to be the very last thing that can create one.
        fleet.apply(displayPreference: preferences.displayPreference)
        fleet.apply(alongOffset: preferences.offset(for: preferences.notchEdge))
        fleet.apply(resetTimeFormat: preferences.resetTimeFormat)
        fleet.apply(accentColor: preferences.accentColor)
        fleet.show()
    }

    /// Open the notch, and make a noise, when something has just finished.
    ///
    /// The watcher is fed on every publication whether or not anything is
    /// switched on, because it is a difference engine: skipping a reading would
    /// leave it comparing against a state two changes old, and the *next*
    /// transition it reported would be one that never happened.
    ///
    /// Several sessions can land in the same reading — one turn ending often
    /// unblocks another — and that gets one peek and one chime rather than a
    /// chord. The newest is the one offered, since it is the one whose window
    /// you were most recently in.
    @MainActor
    private func announceCompletions(sessions: [String: [AgentSession]]) {
        let events = completions.absorb(sessions)
        guard !events.isEmpty else { return }
        pendingAnnouncements.append(contentsOf: events)
        guard announcementWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.deliverAnnouncement() }
        }
        announcementWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func updateActivity() {
        hookMonitor.reconcile(nativeSessions)
        let merged = hookMonitor.state.merging(nativeSessions)
        let routing = ActivityRouting(local: localSnapshots, linked: codeSwitch?.snapshots ?? [],
                                      sources: activitySources, sessions: merged, bindings: codeSwitch?.bindings ?? [:])
        if activityRouting?.sessions != routing.sessions {
            notchFleet?.setSessions(routing.sessions)
        }
        if activityRouting?.snapshots != routing.snapshots {
            notchFleet?.setSnapshots(routing.snapshots)
            statusItem?.snapshots = routing.snapshots
        }
        activityRouting = routing
        announceCompletions(sessions: merged)
    }

    private func deliverAnnouncement() {
        announcementWork = nil
        let events = pendingAnnouncements.sorted {
            if $0.reason != $1.reason { return $0.reason == .blocked }
            return $0.session.since > $1.session.since
        }
        pendingAnnouncements.removeAll()
        guard let event = events.first(where: { event in
            activityRouting?.sessions.values.contains { $0.contains { $0.id == event.session.id && $0.state == event.session.state } } == true
        }), let preferences, let fleet = notchFleet else { return }
        Log.usage.info("session \(event.session.name, privacy: .public) \(String(describing: event.reason), privacy: .public)")

        if preferences.sessionEndSound {
            SessionChime.play(event.reason == .blocked
                              ? preferences.sessionBlockedSoundName
                              : preferences.sessionEndSoundName)
        }
        guard preferences.announceSessionEnd else { return }
        fleet.peek(for: preferences.peekDuration.seconds,
                   focusing: event.session.processID, providerID: activityRouting?.providerID(for: event.session),
                   startedAt: event.session.processStartedAt)
    }

    /// Closing the settings window must not take the app with it.
    ///
    /// The default for a Dock app is to quit once its last window closes, which
    /// here would kill the notch — the part that is actually the product —
    /// every time someone shut the settings they had just opened.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// The way back in when the notch is hidden.
    ///
    /// With no dock icon, no menu bar item and no notch on screen, there is
    /// otherwise nothing left to click — choosing Hide would be a one-way door.
    /// Launching the app again while it is already running lands here, so
    /// opening it from Applications or Spotlight reopens settings.
    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows: Bool) -> Bool {
        settings?.show()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        announcementWork?.cancel()
        hookMonitor.stop()
        codeSwitch?.stop()
        store?.stop()
        monitors.values.forEach { $0.stop() }
        notchFleet?.stop()
    }
}
