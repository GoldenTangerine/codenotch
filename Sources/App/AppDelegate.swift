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
    private var ollamaRelay: OllamaActivityRelay?
    private var lmstudioMetrics: LMStudioMetrics?
    private var preferences: Preferences?
    private var settings: SettingsWindowController?
    private var whatsNew: WhatsNewWindowController?
    /// Held for the life of the app: releasing it stops the scheduled checks.
    private var updater: Updater?
    private var thresholdNotifier: ThresholdNotifier?
    private var statusItem: StatusItemController?
    /// Keeps the Claude keychain token from ageing out on a Mac where the CLI
    /// is never run by hand. See `ClaudeTokenRefresher`.
    private var tokenRefresher: ClaudeTokenRefresher?
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
    private var waitingProtection: SessionCompletionWatcher.WaitingProtection?

    /// The unit bundle is hosted by this app, so `xcodebuild test` launches it
    /// for real. Without this guard every test run put a live request on the
    /// usage endpoint — which is both wrong on its own terms and, on an endpoint
    /// that rate-limits, actively harmful.
    private var isRunningTests: Bool { Runtime.isUnderTest }

    /// Quit any copy of Codenotch that was already running.
    ///
    /// Every notch is a window on the screen edge, so a second copy is not a
    /// harmless duplicate the way a second text editor is: it draws a second
    /// notch over the first, and a developer with a build in `DerivedData`, a
    /// staged release and `/Applications` could end up with the screen ringed
    /// by them. They are separate bundles at separate paths, so the system
    /// launches each as its own process rather than activating the one that is
    /// already up.
    ///
    /// The newcomer wins, deliberately. Quitting the *new* copy instead would
    /// be the wrong way round while developing: the whole point of launching a
    /// fresh build is to replace the one already running.
    ///
    /// Only strictly older instances are asked to go, which is what keeps two
    /// simultaneous launches from each terminating the other and leaving none.
    private static func retireOlderInstances() {
        guard let identifier = Bundle.main.bundleIdentifier else { return }
        let mine = ProcessInfo.processInfo.processIdentifier
        let launched = NSRunningApplication.current.launchDate ?? Date()
        for other in NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
        where other.processIdentifier != mine && (other.launchDate ?? .distantPast) < launched {
            Log.usage.info("retiring an older instance (pid \(other.processIdentifier, privacy: .public))")
            if !other.terminate() { other.forceTerminate() }
        }
    }

    /// Every Claude Code configuration directory on this Mac — `~/.claude` and
    /// any `~/.claude-<slug>` — found once at launch. Each gets a usage
    /// provider and a session monitor of its own, keyed by the same id, so a
    /// work login's sessions spin the work ring and nobody else's.
    private let claudeProfiles = ClaudeProfile.discover()
    private let codexProfiles = CodexProfile.discover()
    /// Held as concrete providers, not just handed to the store: the token
    /// refresher needs to ask one of them how long its token has left, and the
    /// protocol has no business carrying that.
    private var claudeProviders: [ClaudeOAuthProvider] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set here, not in the Info.plist: this call is applied at launch and
        // overrides `LSUIElement` either way. Removing the plist key alone left
        // the app registered as a UIElement with no Dock tile, which looked
        // exactly like the icon having failed to install. The user's choice
        // replaces this a moment later, once preferences exist.
        NSApp.setActivationPolicy(.regular)
        guard !isRunningTests else { return }
        Self.retireOlderInstances()

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
            // DeepSeek's Platform usage page is a browser-session provider:
            // login is explicit, stays in Codenotch's own WKWebView store, and
            // the page-local requests are refreshed only after that login.
            let deepSeek = WebSessionProvider(site: Sites.deepSeek)
            let webProviders: [WebSessionProvider] = [deepSeek]
            fleet.signInItems = webProviders.map { provider in
                (title: L10n.t("Sign in to \(provider.displayName)…"),
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
            Log.usage.info("codex profiles: \(self.codexProfiles.map(\.displayPath).joined(separator: ", "), privacy: .public)")
            let claudeProviders = claudeProfiles.map { ClaudeOAuthProvider(profile: $0) }
            self.claudeProviders = claudeProviders
            let nativeProviders: [UsageProvider] = claudeProviders
                    + [CursorLocalProvider()]
                    + codexProfiles.map { CodexLocalProvider(profile: $0) }
                    + [AntigravityProvider(),
                       GLMProvider(), GrokLocalProvider(), DevinLocalProvider(), OpenCodeProvider(),
                       CommandCodeProvider(), GitHubCopilotProvider(),
                       OllamaLocalProvider(endpoint: URL(string: preferences.ollamaEndpoint)!),
                       LMStudioLocalProvider(endpoint: URL(string: preferences.lmstudioEndpoint)!),
                       OllamaProvider(),
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
                disconnected: Set(catalog.entries.filter { !$0.enabled }.map(\.id)).union(preferences.disconnectedProviders), configured: true,
                order: preferences.providerOrder
            )
            let applyCatalog: (Set<String>) -> Void = { [weak self, weak catalog, weak store, weak fleet, weak preferences] invalidated in
                guard let catalog, let store else { return }
                let disconnected = Set(catalog.entries.filter { !$0.enabled }.map(\.id))
                    .union((preferences?.disconnectedProviders ?? []).subtracting(catalog.entries.map(\.id)))
                store.reconfigure(providers: catalog.providers(), disconnected: disconnected, invalidated: invalidated)
                store.order = catalog.entries.map(\.id)
                    + (preferences?.providerOrder ?? []).filter { id in !catalog.entries.contains { $0.id == id } }
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
            preferences.disconnectedProviders.formUnion(catalog.entries.filter { !$0.enabled }.map(\.id))
            deepSeek.onAuthenticated = { [weak store] in
                store?.refresh(providerID: "deepseek")
            }

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
            let codeSwitch = CodeSwitchBridge()
            self.codeSwitch = codeSwitch
            let relay = OllamaActivityRelay()
            self.ollamaRelay = relay
            // A single publisher chain exceeds Swift's type-checking time limit.
            let relayPreferences = Publishers.CombineLatest3(
                preferences.$disconnectedProviders,
                preferences.$ollamaEndpoint,
                preferences.$ollamaMetricsEnabled)
            let relayConfiguration = relayPreferences.map { values in
                (enabled: !values.0.contains("ollama-local") && values.2, endpoint: values.1)
            }.eraseToAnyPublisher()
            relayConfiguration
                .removeDuplicates { $0.enabled == $1.enabled && $0.endpoint == $1.endpoint }
                .receive(on: RunLoop.main)
                .sink { [weak relay, weak fleet] configuration in
                    fleet?.setLocalMetricsEnabled(configuration.enabled)
                    relay?.configure(enabled: configuration.enabled, endpoint: configuration.endpoint)
                }
                .store(in: &cancellables)
            relay.$thinkingModels
                .receive(on: RunLoop.main)
                .sink { [weak fleet, weak store] models in
                    let previous = fleet?.thinkingModels ?? [:]
                    fleet?.setThinkingModels(models)
                    if models.keys.contains(where: { previous[$0] == nil }) { store?.refresh(providerID: "ollama-local") }
                }
                .store(in: &cancellables)

            relay.$performances
                .receive(on: RunLoop.main)
                .sink { [weak fleet, weak store] measurements in
                    fleet?.setPerformances(measurements)
                    if !measurements.isEmpty { store?.refresh(providerID: "ollama-local") }
                }
                .store(in: &cancellables)

            // LM Studio needs no relay: its own socket says what each model is
            // doing and its own log says what every request cost. Monitoring
            // follows the provider's switch, and the address follows Settings.
            let lmstudio = LMStudioMetrics()
            self.lmstudioMetrics = lmstudio
            // Split like the relay's chain above, and for the same reason.
            let lmstudioPreferences = Publishers.CombineLatest(
                preferences.$disconnectedProviders, preferences.$lmstudioEndpoint)
            let lmstudioConfiguration = lmstudioPreferences.map { values in
                (enabled: !values.0.contains(LMStudioMetrics.providerID), endpoint: values.1)
            }.eraseToAnyPublisher()
            lmstudioConfiguration
                .removeDuplicates { $0.enabled == $1.enabled && $0.endpoint == $1.endpoint }
                .receive(on: RunLoop.main)
                .sink { [weak lmstudio] configuration in
                    lmstudio?.configure(enabled: configuration.enabled, endpoint: configuration.endpoint)
                }
                .store(in: &cancellables)
            lmstudio.$activities
                .receive(on: RunLoop.main)
                .sink { [weak fleet] in fleet?.setLocalActivities($0) }
                .store(in: &cancellables)
            lmstudio.$performances
                .receive(on: RunLoop.main)
                .sink { [weak fleet, weak store] measurements in
                    fleet?.setPerformances(measurements, source: LMStudioMetrics.providerID)
                    if !measurements.isEmpty { store?.refresh(providerID: LMStudioMetrics.providerID) }
                }
                .store(in: &cancellables)
            lmstudio.$ledger
                .receive(on: RunLoop.main)
                .sink { [weak fleet] in fleet?.setLedger($0) }
                .store(in: &cancellables)

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
                    store?.openAccountSource(providerID: $0, switching: true) ?? false
                },
                retry: { [weak store] in store?.reauthorize(providerID: $0) },
                // Both halves, because the stored nudge and the live one are
                // kept apart on purpose — clearing only the preference would
                // leave the notch where it is until the next edge change, and
                // moving only the panel would put it back on relaunch.
                resetPosition: { [weak fleet, weak preferences] in
                    preferences?.notchPosition = nil
                    fleet?.restore(position: nil)
                    preferences?.setOffset(0, for: preferences?.notchEdge ?? .right)
                    fleet?.apply(alongOffset: 0)
                },
                catalog: catalog, hooks: hookSettings, codeSwitch: codeSwitch,
                usageStore: store, ollamaRelay: relay, lmstudioMetrics: lmstudio
            )
            // The gear toggles; everything else that opens settings opens it.
            // 两端按钮已隐藏，右键菜单的设置入口始终打开窗口。
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
            // Read when the menu opens, so a model's line is as current as its cell.
            statusItem.cells = { [weak fleet] in fleet?.menuModel.snapshots ?? [] }
            statusItem.activity = { [weak fleet] in fleet?.menuModel.activity(for: $0) }

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

            // Three inputs, one answer: which control is in charge, and the
            // value each of them holds. Any of them changing has to re-ask
            // `notchScale` rather than trust the value it was handed, since
            // the preset and the slider each keep their own.
            //
            // `dropFirst` on each, because `@Published` publishes the value it
            // is given at init — without it every launch would open the notch
            // three times over before anyone had touched anything.
            Publishers.MergeMany(
                preferences.$notchSize.dropFirst().map { _ in () }.eraseToAnyPublisher(),
                preferences.$usesCustomNotchScale.dropFirst().map { _ in () }.eraseToAnyPublisher(),
                preferences.$customNotchScale.dropFirst().map { _ in () }.eraseToAnyPublisher()
            )
            // `DispatchQueue.main`, not `RunLoop.main`, and this is the one
            // subscription where the difference is visible. Combine's RunLoop
            // scheduler delivers in `.default` mode, which AppKit starves for
            // as long as a drag is in progress — the loop is in
            // `NSEventTrackingRunLoopMode` the whole time a slider is held. So
            // the notch sat unchanged until the mouse came up, then jumped.
            // Every `Timer` here is registered `forMode: .common` against the
            // same hazard; the scheduler offers no way to say that, and the
            // dispatch queue is not bound to run loop modes at all.
            .receive(on: DispatchQueue.main)
            .sink { [weak fleet, weak preferences] in
                guard let preferences, let fleet else { return }
                fleet.apply(scale: preferences.notchScale)
                // Resizing something you cannot see is guesswork. On the
                // hover setting the notch is folded away for as long as the
                // pointer is in Settings, which is exactly when the size is
                // being chosen — so it is opened for a moment to show what
                // just changed. Dragging the slider keeps re-arming this, so
                // it simply stays open until the drag stops. `peek` still
                // declines outright when the notch is set to Hide.
                fleet.peek(for: 1.2, focusing: nil)
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

            fleet.onToggleKeepOpen = { [weak preferences] in
                guard let prefs = preferences else { return }
                prefs.notchVisibility = (prefs.notchVisibility == .alwaysShow) ? .onHover : .alwaysShow
            }

            // Writing the preference is the whole of it: `notchEdge` is
            // `@Published` and the fleet already follows it, so the notch
            // relocates by the same path the Settings picker uses.
            fleet.onMoveToEdge = { [weak preferences] edge in
                preferences?.notchEdge = edge
            }

            preferences.$resetTimeFormat
                .receive(on: RunLoop.main)
                .sink { [weak fleet] in fleet?.apply(resetTimeFormat: $0) }
                .store(in: &cancellables)

            preferences.$tooltipHeightMode
                .receive(on: RunLoop.main)
                .sink { [weak fleet] in fleet?.apply(tooltipHeightMode: $0) }
                .store(in: &cancellables)

            preferences.$codeSwitchEnabled.combineLatest(preferences.$codeSwitchDisplayMode)
                .sink { [weak codeSwitch] enabled, mode in codeSwitch?.configure(enabled: enabled, mode: mode) }
                .store(in: &cancellables)
            preferences.$weeklyRing
                .receive(on: RunLoop.main)
                .sink { [weak fleet] in fleet?.apply(weeklyRing: $0) }
                .store(in: &cancellables)

            preferences.$notchSurfaceStyle
                .receive(on: RunLoop.main)
                .sink { [weak fleet] in fleet?.apply(surfaceStyle: $0) }
                .store(in: &cancellables)

            preferences.$disconnectedProviders
                .receive(on: RunLoop.main)
                .sink { [weak store, weak catalog] disconnected in
                    store?.disconnected = disconnected
                    guard let catalog else { return }
                    for entry in catalog.entries where entry.enabled == disconnected.contains(entry.id) {
                        catalog.setEnabled(!disconnected.contains(entry.id), id: entry.id)
                    }
                }
                .store(in: &cancellables)

            preferences.$ollamaEndpoint
                .receive(on: RunLoop.main)
                .sink { [weak store] address in
                    guard let endpoint = try? OllamaEndpoint.parse(address) else { return }
                    store?.updateOllamaEndpoint(endpoint)
                }
                .store(in: &cancellables)

            preferences.$lmstudioEndpoint
                .receive(on: RunLoop.main)
                .sink { [weak store] address in
                    guard let endpoint = try? LMStudioEndpoint.parse(address) else { return }
                    store?.updateLMStudioEndpoint(endpoint)
                }
                .store(in: &cancellables)

            preferences.$providerOrder
                .receive(on: RunLoop.main)
                .sink { [weak store] in store?.order = $0 }
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

            store.$notchSnapshots.combineLatest(codeSwitch.$snapshots)
                .receive(on: RunLoop.main)
                .sink { [weak self] local, linked in
                    let snapshots = local + linked.filter { self?.preferences?.hiddenCodeSwitchProviders.contains($0.id) != true }
                    self?.localSnapshots = local
                    self?.updateActivity()
                    notifier.observe(snapshots)
                }
                .store(in: &cancellables)
            codeSwitch.$displayedSnapshots.dropFirst().receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.updateActivity() }
                .store(in: &cancellables)
            preferences.$hiddenCodeSwitchProviders.dropFirst().receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.updateActivity() }
                .store(in: &cancellables)
            preferences.$codeSwitchProviderOrder.dropFirst().receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.updateActivity() }
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
                else { await store?.refresh(providerID: id)?.value }
            }
            statusItem.onRefreshAll = fleet.onRefresh
            statusItem.onRefreshProvider = { [weak fleet] id in
                Task { await fleet?.onRefreshProvider?(id) }
            }
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
            "gemini": AntigravityActivityMonitor(),
            "grok": GrokActivityMonitor(),
            "gemini-api": GeminiAPIActivityMonitor(),
        ]
        var claudeMonitors: [ClaudeSessionMonitor] = []
        for profile in claudeProfiles {
            let monitor = ClaudeSessionMonitor(
                directory: profile.sessionsDirectory,
                projects: profile.projectsDirectory
            )
            claudeMonitors.append(monitor)
            monitors[profile.id] = monitor
        }
        for profile in codexProfiles {
            monitors[profile.id] = CodexActivityMonitor(profile: profile)
        }

        // Renewing the token runs the Claude command, which registers a session
        // of its own for the second it lives. Every Claude monitor is told to
        // step over that pid, so it never reaches the notch and never counts as
        // work in progress.
        //
        // Only the default profile is renewed. The command writes whichever
        // directory `CLAUDE_CONFIG_DIR` names, so a second profile would need
        // that passed through — behaviour nobody has been able to try on a Mac
        // with two of them, and an unverified guess is worse here than a ring
        // that ages the way it already does.
        if let defaultProvider = claudeProviders.first(where: { $0.profile.slug == nil }) {
            let refresher = ClaudeTokenRefresher(
                expiry: { await defaultProvider.tokenExpiry },
                reload: { await defaultProvider.reloadTokenExpiry() }
            )
            for monitor in claudeMonitors {
                monitor.ignoredPIDs = { [weak refresher] in
                    guard let pid = refresher?.launchedPID else { return [] }
                    return [pid]
                }
            }
            // The one place the failure becomes visible. The store carries the
            // fact; nothing here retries, and the warning clears itself the
            // moment a reading comes back.
            refresher.$outcome
                .receive(on: RunLoop.main)
                .sink { [weak self] outcome in
                    guard case .failed = outcome else { return }
                    self?.store?.reportRenewalFailed(providerID: defaultProvider.id)
                }
                .store(in: &cancellables)

            refresher.start()
            tokenRefresher = refresher
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
                || (self?.lmstudioMetrics?.isBusy ?? false)
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
        fleet.apply(scale: preferences.notchScale)
        fleet.apply(resetTimeFormat: preferences.resetTimeFormat)
        fleet.apply(tooltipHeightMode: preferences.tooltipHeightMode)
        Self.bindNotchAccentColor(preferences, to: fleet)
            .store(in: &cancellables)
        fleet.apply(weeklyRing: preferences.weeklyRing)
        fleet.apply(surfaceStyle: preferences.notchSurfaceStyle)
        fleet.show()
    }

    // Apply the saved colour before any window is shown; subsequent changes
    // use the same binding in normal launches and the demo.
    static func bindNotchAccentColor(_ preferences: Preferences, to fleet: NotchFleet) -> AnyCancellable {
        fleet.apply(accentColor: preferences.notchAccentColor)
        return preferences.$notchAccentColor
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak fleet] in fleet?.apply(accentColor: $0) }
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
        let routing = ActivityRouting(local: localSnapshots, linked: codeSwitch?.displayedSnapshots ?? [],
                                      sources: activitySources, sessions: merged, bindings: codeSwitch?.bindings ?? [:],
                                      hiddenLinked: preferences?.hiddenCodeSwitchProviders ?? [],
                                      linkedOrder: preferences?.codeSwitchProviderOrder ?? [])
        if (activityRouting?.unmatched ?? [:]) != routing.unmatched {
            let summary = ActivityRouting.UnmatchedReason.allCases.map {
                "\($0.rawValue)=\(routing.unmatched[$0, default: 0])"
            }.joined(separator: " ")
            Log.sessions.notice("activity routing: \(summary, privacy: .public)")
        }
        if activityRouting?.sessions != routing.sessions {
            notchFleet?.setSessions(routing.sessions)
        }
        if activityRouting?.snapshots != routing.snapshots {
            notchFleet?.setSnapshots(routing.snapshots)
        }
        statusItem?.snapshots = routing.snapshots.filter { $0.localModel == nil }
            + (store?.snapshots.filter { $0.kind == .localRuntime } ?? [])
        activityRouting = routing
        announceCompletions(sessions: merged)
    }

    private func deliverAnnouncement() {
        announcementWork = nil
        let events = pendingAnnouncements
        pendingAnnouncements.removeAll()
        guard let preferences, let fleet = notchFleet,
              let event = SessionCompletionWatcher.nextAnnouncement(events, sessions: activityRouting?.sessions ?? [:],
                  protecting: waitingProtection, enabled: {
                  let settings = preferences.announcementSettings(for: $0)
                  return settings.expand || settings.sound != nil
              }) else { return }
        Log.usage.info("session \(event.session.name, privacy: .public) \(String(describing: event.reason), privacy: .public)")

        let settings = preferences.announcementSettings(for: event.reason)
        let played = settings.sound.map { SessionChime.play($0, volume: preferences.sessionSoundVolume) } ?? false
        let displayed = settings.expand && fleet.peek(for: settings.duration,
                   focusing: event.session.processID, providerID: activityRouting?.providerID(for: event.session),
                   startedAt: event.session.processStartedAt)
        waitingProtection = .init(event: event, presented: displayed || played, duration: settings.duration)
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
        openSettings()
        return true
    }

    @MainActor func openSettings() { settings?.show() }

    func applicationWillTerminate(_ notification: Notification) {
        announcementWork?.cancel()
        hookMonitor.stop()
        codeSwitch?.stop()
        ollamaRelay?.configure(enabled: false, endpoint: OllamaEndpoint.defaultAddress)
        lmstudioMetrics?.stop()
        tokenRefresher?.stop()
        store?.stop()
        monitors.values.forEach { $0.stop() }
        notchFleet?.stop()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task { @MainActor in
            await codeSwitch?.stopAndWait()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
