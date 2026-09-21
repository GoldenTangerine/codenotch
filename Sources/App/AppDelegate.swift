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
    var phoneLinkServer: PhoneLinkServer?
    var phoneLinkServerStatus: PhoneLinkServerStatus?
    var phoneLinkPairing: PhoneLinkPairing?
    var phoneLinkRegistry: PhoneLinkRegistry?
    private var activityCoordinator: ActivityCoordinator?
    private var ollamaRelay: OllamaActivityRelay?
    private var lmstudioMetrics: LMStudioMetrics?
    private var preferences: Preferences?
    private var settings: SettingsWindowController?
    private var whatsNew: WhatsNewWindowController?
    /// Held for the life of the app: releasing it stops the scheduled checks.
    private var updater: Updater?
    private var thresholdNotifier: ThresholdNotifier?
    private var resetWatcher: UsageResetWatcher?
    private var limitWatcher: UsageLimitWatcher?
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
    /// MiniMax Platform sign-in sheet. Not a UsageProvider — that is MiniMaxProvider.
    private var miniMaxWeb: WebSessionProvider?

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
            // MiniMax's ring is MiniMaxProvider. The sheet is the same kind of
            // WebView DeepSeek uses, but it must not join `webProviders`:
            // that list is only for standalone browser-backed providers, while
            // MiniMaxProvider owns the one MiniMax usage poll. Region is applied
            // here and again when Settings changes it, because the fetch URLs
            // live on the site.
            let miniMaxWeb = WebSessionProvider(site: Sites.minimax(region: preferences.minimaxRegion))
            self.miniMaxWeb = miniMaxWeb
            let miniMaxProvider = MiniMaxProvider(web: miniMaxWeb)
            let webProviders: [WebSessionProvider] = [deepSeek]
            fleet.signInItems = [deepSeek, miniMaxWeb].map { provider in
                let name = provider.displayName
                return (title: L10n.t("Sign in to \(name)…"),
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
                       GLMProvider(), miniMaxProvider, GrokLocalProvider(), DevinLocalProvider(), OpenCodeProvider(),
                       CommandCodeProvider(), GitHubCopilotProvider(), KimiProvider(), KiroProvider(),
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
            preferences.reconcile(discoveredIDs: nativeProviders.map(\.id))
            let catalog = QueryCatalog(providers: nativeProviders,
                disconnected: preferences.disconnectedIDs(among: nativeProviders.map(\.id)))
            preferences.reconcileCatalog(catalog.entries)
            let store = UsageStore(
                providers: catalog.providers(),
                disconnected: preferences.disconnectedIDs(among: catalog.entries.map(\.id)), configured: true,
                order: preferences.providerOrder
            )
            let applyCatalog: (Set<String>) -> Void = { [weak self, weak catalog, weak store, weak fleet, weak preferences] invalidated in
                guard let catalog, let store, let preferences else { return }
                preferences.reconcileCatalog(catalog.entries)
                let disconnected = preferences.disconnectedIDs(among: catalog.entries.map(\.id) + store.knownIDs)
                store.reconfigure(providers: catalog.providers(), disconnected: disconnected, invalidated: invalidated)
                store.order = catalog.entries.map(\.id)
                    + preferences.providerOrder.filter { id in !catalog.entries.contains { $0.id == id } }
                fleet?.setActivitySourceIDs(Dictionary(uniqueKeysWithValues:
                    catalog.entries.filter { $0.usesLocalAccount }.map { ($0.id, $0.nativeID) }))
                self?.activitySources = Dictionary(uniqueKeysWithValues:
                    catalog.entries.filter { $0.usesLocalAccount }.map { ($0.id, $0.nativeID) })
                self?.updateActivityMonitoring()
                self?.updateActivity()
            }
            catalog.onChange = applyCatalog
            fleet.setActivitySourceIDs(Dictionary(uniqueKeysWithValues:
                catalog.entries.filter { $0.usesLocalAccount }.map { ($0.id, $0.nativeID) }))
            activitySources = Dictionary(uniqueKeysWithValues:
                catalog.entries.filter { $0.usesLocalAccount }.map { ($0.id, $0.nativeID) })
            deepSeek.onAuthenticated = { [weak catalog, weak store] in
                for id in catalog?.automaticEntryIDs(for: "deepseek") ?? [] {
                    store?.providerAuthenticationChanged(providerID: id)
                }
            }
            miniMaxWeb.onAuthenticated = { [weak catalog, weak store] in
                for id in catalog?.automaticEntryIDs(for: "minimax") ?? [] {
                    store?.providerAuthenticationChanged(providerID: id)
                }
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
                preferences.$connectedProviders,
                preferences.$ollamaEndpoint,
                preferences.$ollamaMetricsEnabled)
            let relayConfiguration = relayPreferences.map { values in
                (enabled: values.0.contains("ollama-local") && values.2, endpoint: values.1)
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
                preferences.$connectedProviders, preferences.$lmstudioEndpoint)
            let lmstudioConfiguration = lmstudioPreferences.map { values in
                (enabled: values.0.contains(LMStudioMetrics.providerID), endpoint: values.1)
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

            let dir: URL
            if NSClassFromString("XCTestCase") != nil {
                dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            } else {
                let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                dir = appSupport.appendingPathComponent("Codenotch/phone-link", isDirectory: true)
            }
            let phoneSecretStore: PhoneLinkSecretStore = NSClassFromString("XCTestCase") != nil
                ? InMemoryPhoneLinkSecretStore()
                : PhoneLinkKeychainSecretStore()
            let phoneRegistry = PhoneLinkRegistry(directory: dir, secretStore: phoneSecretStore)
            let phonePairing = PhoneLinkPairing()
            let serverStatus = PhoneLinkServerStatus()
            self.phoneLinkRegistry = phoneRegistry
            self.phoneLinkPairing = phonePairing

            let server = PhoneLinkServer(
                pairing: phonePairing,
                registry: phoneRegistry,
                status: serverStatus,
                getSnapshot: { @Sendable [weak store, weak fleet, weak preferences] in
                    guard let store, let fleet, let preferences else { return nil }
                    let snap = await MainActor.run {
                        PhoneLinkSnapshotBuilder.build(
                            snapshots: DailyPace.apply(to: store.snapshots,
                                                       enabled: preferences.claudeDailyPaceRing),
                            sessions: Array(fleet.sessions.values.flatMap { $0 }),
                            disconnected: store.disconnected,
                            order: preferences.providerOrder,
                            serverName: PhoneLinkNetwork.getComputerName(),
                            serverVersion: (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0",
                            now: Date()
                        )
                    }
                    return try? JSONEncoder().encode(snap)
                },
                refreshAndGetSnapshot: { @Sendable [weak store, weak fleet, weak preferences] in
                    guard let store, let fleet, let preferences else { return nil }
                    await MainActor.run { store.refreshNow() }
                    for _ in 0..<20 {
                        let isRef = await MainActor.run { !store.refreshing.isEmpty }
                        if !isRef { break }
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                    }
                    let snap = await MainActor.run {
                        PhoneLinkSnapshotBuilder.build(
                            snapshots: DailyPace.apply(to: store.snapshots,
                                                       enabled: preferences.claudeDailyPaceRing),
                            sessions: Array(fleet.sessions.values.flatMap { $0 }),
                            disconnected: store.disconnected,
                            order: preferences.providerOrder,
                            serverName: PhoneLinkNetwork.getComputerName(),
                            serverVersion: (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0",
                            now: Date()
                        )
                    }
                    return try? JSONEncoder().encode(snap)
                }
            )
            self.phoneLinkServerStatus = serverStatus
            self.phoneLinkServer = server

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
                quit: { NSApp.terminate(nil) },
                previewResetAlert: { [weak self] in
                    self?.previewUsageResetAlert()
                },
                previewSessionLimitAlert: { [weak self] in
                    self?.previewSessionLimitAlert()
                },
                previewWeeklyLimitAlert: { [weak self] in
                    self?.previewWeeklyLimitAlert()
                },
                usageStore: store, ollamaRelay: relay, lmstudioMetrics: lmstudio,
                phoneLinkPairing: phonePairing, phoneLinkRegistry: phoneRegistry, phoneLinkServerStatus: serverStatus
            )
            // The gear toggles; everything else that opens settings opens it.
            fleet.onOpenSettings = { [weak settings] in settings?.show() }
            // A session row answers where it runs by taking you there.
            fleet.onFocusSession = { pid in
                Task { _ = await SessionFocus.focus(pid: pid) }
            }
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

            preferences.$notchHoverDelay
                .receive(on: RunLoop.main)
                .sink { [weak fleet] in fleet?.apply(notchHoverDelay: $0) }
                .store(in: &cancellables)

            preferences.$notchTriggerHeight
                .receive(on: RunLoop.main)
                .sink { [weak fleet] in fleet?.apply(notchTriggerHeight: $0) }
                .store(in: &cancellables)

            preferences.$topAvoidanceAdjustment.combineLatest(preferences.$ringEdgeAdjustment)
                .dropFirst()
                .receive(on: DispatchQueue.main)
                .sink { [weak fleet] top, ring in
                    fleet?.apply(topAvoidanceAdjustment: CGFloat(top), ringEdgeAdjustment: CGFloat(ring))
                    fleet?.previewGeometry()
                }
                .store(in: &cancellables)

            preferences.$collapsedSideWidth.combineLatest(preferences.$collapsedHeightAdjustment)
                .dropFirst()
                .receive(on: DispatchQueue.main)
                .sink { [weak fleet] width, height in
                    fleet?.apply(collapsedSideWidth: CGFloat(width))
                    fleet?.apply(collapsedHeightAdjustment: CGFloat(height))
                    fleet?.previewCollapsedGeometry()
                }
                .store(in: &cancellables)

            preferences.$isEditingCollapsedGeometry.removeDuplicates().dropFirst()
                .receive(on: DispatchQueue.main)
                .sink { [weak fleet] editing in fleet?.previewCollapsedGeometry(editing: editing) }
                .store(in: &cancellables)

            preferences.$isEditingNotchGeometry.removeDuplicates().dropFirst()
                .receive(on: DispatchQueue.main)
                .sink { [weak fleet] editing in fleet?.previewGeometry(editing: editing) }
                .store(in: &cancellables)

            preferences.$foldsForFullScreen
                .receive(on: RunLoop.main)
                .sink { [weak fleet] in fleet?.apply(foldsForFullScreen: $0) }
                .store(in: &cancellables)

            preferences.$deepSeekPricingEnabled
                .receive(on: RunLoop.main)
                .sink { [weak fleet] in fleet?.apply(deepSeekPricingEnabled: $0) }
                .store(in: &cancellables)

            preferences.$deepSeekPricingSchedule
                .receive(on: RunLoop.main)
                .sink { [weak fleet] in fleet?.apply(deepSeekPricingSchedule: $0) }
                .store(in: &cancellables)

            preferences.$minimaxRegion
                .dropFirst()
                .removeDuplicates()
                .receive(on: RunLoop.main)
                .sink { [weak miniMaxWeb, weak miniMaxProvider, weak catalog, weak store, weak preferences] region in
                    miniMaxWeb?.apply(site: Sites.minimax(region: region))
                    store?.providerAccountChanged()
                    let ids = catalog?.automaticEntryIDs(for: "minimax") ?? []
                    for id in ids { store?.invalidateUsageSource(providerID: id) }
                    Task { [weak miniMaxProvider, weak store, weak preferences] in
                        await miniMaxProvider?.regionDidChange()
                        guard preferences?.minimaxRegion == region else { return }
                        for id in ids { store?.refresh(providerID: id) }
                    }
                }
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
            preferences.$showsMoveHandle
                .receive(on: RunLoop.main)
                .sink { [weak fleet] in fleet?.apply(showsMoveHandle: $0) }
                .store(in: &cancellables)

            preferences.$showsSettingsHandle
                .receive(on: RunLoop.main)
                .sink { [weak fleet] in fleet?.apply(showsSettingsHandle: $0) }
                .store(in: &cancellables)

            preferences.$watchLimit
                .combineLatest(preferences.$criticalLimit)
                .receive(on: RunLoop.main)
                .sink { [weak fleet] watch, critical in
                    fleet?.apply(watchLimit: watch, criticalLimit: critical)
                }
                .store(in: &cancellables)

            preferences.$weeklyRingDashed
                .receive(on: RunLoop.main)
                .sink { [weak fleet] in fleet?.apply(weeklyRingDashed: $0) }
                .store(in: &cancellables)

            preferences.$weeklyRing
                .receive(on: RunLoop.main)
                .sink { [weak fleet] in fleet?.apply(weeklyRing: $0) }
                .store(in: &cancellables)

            preferences.$independentInnerRing.combineLatest(preferences.$codeSwitchQuotaRatiosEnabled)
                .receive(on: RunLoop.main)
                .sink { [weak fleet, weak codeSwitch] independent, ratios in
                    fleet?.apply(independentInnerRing: independent, codeSwitchQuotaRatiosEnabled: ratios)
                    codeSwitch?.setDailyBudgetEnabled(ratios)
                }
                .store(in: &cancellables)

            preferences.$notchSurfaceStyle
                .receive(on: RunLoop.main)
                .sink { [weak fleet] in fleet?.apply(surfaceStyle: $0) }
                .store(in: &cancellables)

            Publishers.CombineLatest(preferences.$connectedProviders, preferences.$disabledModels)
                .receive(on: RunLoop.main)
                .sink { [weak store, weak preferences, weak catalog] _, _ in
                    guard let store, let preferences, let catalog else { return }
                    let disconnected = preferences.disconnectedIDs(among: store.knownIDs)
                    store.disconnected = disconnected
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

            let resetWatcher = UsageResetWatcher(
                isMuted: { [weak preferences] in preferences?.isMutedAlerts(for: $0) ?? false },
                onReset: { [weak fleet] event in
                    MainActor.assumeIsolated { fleet?.animateBot(.limitReset, providerID: event.providerID) }
                },
                deliver: { [weak self] event in
                    MainActor.assumeIsolated {
                        self?.announceUsageReset(event: event)
                    }
                }
            )
            self.resetWatcher = resetWatcher

            let limitWatcher = UsageLimitWatcher(
                isMuted: { [weak preferences] in preferences?.isMutedAlerts(for: $0) ?? false },
                deliver: { [weak self] event in
                    MainActor.assumeIsolated {
                        self?.announceUsageLimit(event: event)
                    }
                }
            )
            self.limitWatcher = limitWatcher

            store.$notchSnapshots.combineLatest(codeSwitch.$snapshots, preferences.$claudeDailyPaceRing)
                .receive(on: RunLoop.main)
                .sink { [weak self] local, linked, paced in
                    let local = DailyPace.apply(to: local, enabled: paced)
                    let snapshots = local + linked.filter { self?.preferences?.hiddenCodeSwitchProviders.contains($0.id) != true }
                    self?.localSnapshots = local
                    self?.updateActivity()
                    notifier.observe(snapshots)
                    resetWatcher.observe(snapshots)
                    limitWatcher.observe(snapshots)
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
            preferences.$botAppearances.receive(on: RunLoop.main)
                .sink { [weak fleet] in fleet?.apply(botAppearances: $0) }
                .store(in: &cancellables)
            preferences.$idleBotAppearance.removeDuplicates().receive(on: DispatchQueue.main)
                .sink { [weak fleet] in fleet?.apply(idleBotAppearance: $0) }
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
                if id.hasPrefix("code-switch:") { await codeSwitch?.refresh()?.value }
                else { await store?.refresh(providerID: id)?.value }
            }
            statusItem.onRefreshAll = fleet.onRefresh
            statusItem.onRefreshProvider = { [weak fleet] id in
                Task { await fleet?.onRefreshProvider?(id) }
            }
            store.$refreshing.combineLatest(codeSwitch.$refreshing)
                .receive(on: RunLoop.main)
                .sink { [weak fleet] local, linked in fleet?.setRefreshing(local.union(linked)) }
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
            "kimi": KimiActivityMonitor(),
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
            monitors[profile.id] = CodexActivityMonitor(profile: profile,
                usesRolloutCompletion: { [weak preferences = self.preferences] in
                    preferences?.codexRolloutCompletionEnabled ?? false
                })
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
        let activity = ActivityCoordinator(monitors: monitors) { [weak self] id, sessions in
            guard let self else { return }
            self.nativeSessions[id] = sessions
            // The publisher delivers on the main run loop, but the
            // closure itself is nonisolated — the same assertion the
            // notch controller's timers make.
            MainActor.assumeIsolated { self.updateActivity() }
        }
        self.activityCoordinator = activity
        updateActivityMonitoring()
        preferences.$connectedProviders.combineLatest(preferences.$codeSwitchEnabled)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateActivityMonitoring() }
            .store(in: &cancellables)
        // Poll usage hard only while something is actually running.
        store?.isBusy = { [weak self] in
            self?.hookMonitor.state.merging(self?.nativeSessions ?? [:]).values.contains { $0.contains { $0.state == .busy } } ?? false
                || (self?.lmstudioMetrics?.isBusy ?? false)
        }
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

        preferences.$phoneLinkEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                guard PhoneLink.isAvailable, let self = self, let srv = self.phoneLinkServer else { return }
                Task { @MainActor in
                    if enabled {
                        self.phoneLinkServerStatus?.state = .starting
                        do {
                            let prefPort = self.preferences?.phoneLinkPort ?? 8788
                            let port = try await srv.start(port: prefPort)
                            self.preferences?.phoneLinkPort = port
                            self.phoneLinkServerStatus?.state = .ready(port: port)
                        } catch {
                            self.phoneLinkServerStatus?.state = .failed(error.localizedDescription)
                        }
                    } else {
                        await srv.stop()
                        self.phoneLinkServerStatus?.state = .off
                    }
                }
            }
            .store(in: &cancellables)
        fleet.apply(displayPreference: preferences.displayPreference)
        fleet.apply(alongOffset: preferences.offset(for: preferences.notchEdge))
        fleet.apply(scale: preferences.notchScale)
        fleet.apply(topAvoidanceAdjustment: CGFloat(preferences.topAvoidanceAdjustment),
                    ringEdgeAdjustment: CGFloat(preferences.ringEdgeAdjustment))
        fleet.apply(collapsedSideWidth: CGFloat(preferences.collapsedSideWidth))
        fleet.apply(collapsedHeightAdjustment: CGFloat(preferences.collapsedHeightAdjustment))
        fleet.apply(resetTimeFormat: preferences.resetTimeFormat)
        fleet.apply(tooltipHeightMode: preferences.tooltipHeightMode)
        Self.bindNotchAccentColor(preferences, to: fleet)
            .store(in: &cancellables)
        fleet.apply(weeklyRing: preferences.weeklyRing)
        fleet.apply(independentInnerRing: preferences.independentInnerRing,
                    codeSwitchQuotaRatiosEnabled: preferences.codeSwitchQuotaRatiosEnabled)
        fleet.apply(watchLimit: preferences.watchLimit, criticalLimit: preferences.criticalLimit)
        fleet.apply(weeklyRingDashed: preferences.weeklyRingDashed)
        fleet.apply(showsMoveHandle: preferences.showsMoveHandle)
        fleet.apply(showsSettingsHandle: preferences.showsSettingsHandle)
        fleet.apply(foldsForFullScreen: preferences.foldsForFullScreen)
        fleet.apply(surfaceStyle: preferences.notchSurfaceStyle)
        fleet.apply(deepSeekPricingEnabled: preferences.deepSeekPricingEnabled)
        fleet.apply(deepSeekPricingSchedule: preferences.deepSeekPricingSchedule)
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
        for event in events where event.reason == .finished {
            let targets = activityRouting?.sessions.filter { _, live in
                live.contains { $0.id == event.session.id }
            }.map(\.key) ?? [event.providerID]
            for id in targets { notchFleet?.animateBot(.workFinished, providerID: id) }
        }
        guard !events.isEmpty else { return }
        pendingAnnouncements.append(contentsOf: events)
        guard announcementWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.deliverAnnouncement() }
        }
        announcementWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func updateActivityMonitoring() {
        guard let preferences, let activityCoordinator else { return }
        activityCoordinator.setConnected(preferences.connectedProviders, sources: activitySources,
                                         codeSwitchEnabled: preferences.codeSwitchEnabled)
    }

    private func updateActivity() {
        hookMonitor.reconcile(nativeSessions)
        let merged = hookMonitor.state.merging(nativeSessions)
        notchFleet?.recordBotActivity(merged.values.flatMap { $0 })
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

    /// Open the notch and show a usage reset notification modal when a limit resets.
    @MainActor
    private func announceUsageReset(event: UsageResetEvent) {
        guard let preferences, let fleet = notchFleet else { return }
        Log.usage.info("usage reset for \(event.providerName, privacy: .public) (\(event.windowLabel, privacy: .public))")

        if preferences.usageResetSound {
            SessionChime.play(preferences.usageResetSoundName, volume: preferences.sessionSoundVolume)
        }
        guard preferences.announceUsageReset else { return }
        if !fleet.showResetAlert(event, duration: 5.0) {
            UsageAlertNotifications.deliver(event)
        }
    }

    @MainActor
    private func previewUsageResetAlert() {
        guard let preferences, let fleet = notchFleet else { return }
        let demo = UsageResetEvent(
            providerID: "claude",
            providerName: "Claude",
            windowLabel: "5-hour limit",
            glyph: .claude,
            previousFraction: 0.95,
            currentFraction: 0.00,
            resetsAt: Date().addingTimeInterval(5 * 3600)
        )
        if preferences.usageResetSound {
            SessionChime.play(preferences.usageResetSoundName, volume: preferences.sessionSoundVolume)
        }
        fleet.showResetAlert(demo, duration: 5.0)
    }

    /// Open the notch and show a usage limit reached notification modal when a limit is exhausted.
    @MainActor
    private func announceUsageLimit(event: UsageAlertEvent) {
        guard let preferences, let fleet = notchFleet else { return }

        let isAnnounceEnabled: Bool
        switch event.kind {
        case .sessionLimitReached:
            isAnnounceEnabled = preferences.announceSessionLimitReached
        case .weeklyLimitReached:
            isAnnounceEnabled = preferences.announceWeeklyLimitReached
        case .reset:
            isAnnounceEnabled = preferences.announceUsageReset
        }

        guard isAnnounceEnabled else { return }

        Log.usage.info("usage limit reached for \(event.providerName, privacy: .public) (\(event.windowLabel, privacy: .public))")

        if preferences.limitReachedSound {
            SessionChime.play(preferences.limitReachedSoundName, volume: preferences.sessionSoundVolume)
        }
        if !fleet.showResetAlert(event, duration: 6.0) {
            UsageAlertNotifications.deliver(event)
        }
    }

    @MainActor
    private func previewSessionLimitAlert() {
        guard let preferences, let fleet = notchFleet else { return }
        let demo = UsageAlertEvent(
            kind: .sessionLimitReached,
            providerID: "claude",
            providerName: "Claude",
            windowLabel: "5-hour",
            glyph: .claude,
            previousFraction: 0.95,
            currentFraction: 1.00,
            resetsAt: Date().addingTimeInterval(45 * 60)
        )
        if preferences.limitReachedSound {
            SessionChime.play(preferences.limitReachedSoundName, volume: preferences.sessionSoundVolume)
        }
        fleet.showResetAlert(demo, duration: 6.0)
    }

    @MainActor
    private func previewWeeklyLimitAlert() {
        guard let preferences, let fleet = notchFleet else { return }
        let demo = UsageAlertEvent(
            kind: .weeklyLimitReached,
            providerID: "claude",
            providerName: "Claude",
            windowLabel: "Weekly",
            glyph: .claude,
            previousFraction: 0.98,
            currentFraction: 1.00,
            resetsAt: Date().addingTimeInterval(3 * 86400)
        )
        if preferences.limitReachedSound {
            SessionChime.play(preferences.limitReachedSoundName, volume: preferences.sessionSoundVolume)
        }
        fleet.showResetAlert(demo, duration: 6.0)
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
    @MainActor func openConnectPhone() {
        guard PhoneLink.isAvailable, let pairing = phoneLinkPairing, let registry = phoneLinkRegistry, let status = phoneLinkServerStatus else { return }
        if preferences?.phoneLinkEnabled == false { preferences?.phoneLinkEnabled = true }
        PhoneLinkWindowController.shared.show(pairing: pairing, registry: registry, port: preferences?.phoneLinkPort ?? 8788, serverStatus: status)
    }

    func applicationWillTerminate(_ notification: Notification) {
        preferences?.flushIdleBotAppearance()
        announcementWork?.cancel()
        hookMonitor.stop()
        codeSwitch?.stop()
        ollamaRelay?.configure(enabled: false, endpoint: OllamaEndpoint.defaultAddress)
        lmstudioMetrics?.stop()
        tokenRefresher?.stop()
        store?.stop()
        activityCoordinator?.stop()
        notchFleet?.stop()
        Task { await phoneLinkServer?.stop() }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task { @MainActor in
            await codeSwitch?.stopAndWait()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
