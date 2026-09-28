/**
 @name: 上游新增功能兼容测试
 @Descripttion: 验证额度阈值持久化、联动监控与新增外观配置。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-17 12:00:00
 @LastEditTime: 2026-09-17 12:00:00
 @FilePath: Tests/UpstreamFeatureSyncTests.swift
 */
import Combine
import Foundation
import Testing
@testable import Codenotch

@Suite @MainActor struct UpstreamFeatureSyncTests {
    @Test func clampedLimitsSurviveReloadAndResetFromEitherSide() {
        let suite = "UpstreamLimits.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)
        preferences.watchLimit = 0.95
        #expect(abs(preferences.watchLimit - 0.69) < 0.0001)
        #expect(Preferences(defaults: defaults).watchLimit == preferences.watchLimit)
        preferences.criticalLimit = 0.1
        #expect(Preferences(defaults: defaults).criticalLimit == preferences.criticalLimit)
        preferences.criticalLimit = 1
        preferences.watchLimit = 0.95
        preferences.resetUsageLimits()
        #expect(preferences.watchLimit == 0.50)
        #expect(preferences.criticalLimit == 0.70)
        preferences.watchLimit = 0.01
        preferences.criticalLimit = 0.02
        preferences.resetUsageLimits()
        let restored = Preferences(defaults: defaults)
        #expect(restored.watchLimit == 0.50)
        #expect(restored.criticalLimit == 0.70)
        #expect(UsageBand.band(for: 0.6, watchLimit: 0.65, criticalLimit: 0.9) == .ample)
        #expect(UsageBand.band(for: 0.8, watchLimit: 0.65, criticalLimit: 0.9) == .watch)
        #expect(UsageBand.band(for: 1, watchLimit: 0.65, criticalLimit: 0.9) == .exhausted)
    }

    @Test func invalidStoredLimitsAreRepairedAndNewAppearancePersists() {
        let suite = "UpstreamAppearance.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(0.9, forKey: "watchLimit")
        defaults.set(0.1, forKey: "criticalLimit")
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.watchLimit < preferences.criticalLimit)
        preferences.watchLimit = .nan
        preferences.criticalLimit = .infinity
        #expect(preferences.watchLimit.isFinite)
        #expect(preferences.criticalLimit.isFinite)
        preferences.weeklyRingDashed = true
        preferences.notchSurfaceStyle = .darkGlass
        preferences.language = .ukrainian
        let restored = Preferences(defaults: defaults)
        #expect(restored.weeklyRingDashed)
        #expect(restored.notchSurfaceStyle == .darkGlass)
        #expect(restored.language == .ukrainian)
        #expect(defaults.stringArray(forKey: "AppleLanguages") == ["uk"])
    }

    @Test func monitorSelectionUsesEnabledAccountsAndKeepsLinkedCLIProfiles() {
        let monitors: Set<String> = ["claude", "claude-work", "codex", "codex-work", "cursor", "kimi"]
        let sources = ["account-one": "claude-work", "account-two": "cursor"]
        let connected: Set<String> = ["account-one", "codex", "deleted-account"]
        #expect(ActivityCoordinator.enabledIDs(among: monitors, connected: connected,
            sources: sources, codeSwitchEnabled: false) == ["claude-work"])
        #expect(ActivityCoordinator.enabledIDs(among: monitors, connected: connected,
            sources: sources, codeSwitchEnabled: true) == ["claude", "claude-work", "codex", "codex-work"])
    }

    @Test func disablingAMonitorClearsItsSessionsAndBusyState() async throws {
        let monitor = FeatureSyncMonitor()
        var delivered: [[AgentSession]] = []
        let coordinator = ActivityCoordinator(monitors: ["codex": monitor]) { _, sessions in
            delivered.append(sessions)
        }
        coordinator.setEnabled(["codex"])
        coordinator.setEnabled(["codex"])
        #expect(monitor.starts == 1)
        monitor.sessions = [AgentSession(id: "work", name: "Work", detail: "Working",
            state: .busy, waitingFor: nil, since: Date())]
        #expect(coordinator.isBusy)
        coordinator.stop()
        #expect(monitor.stops == 1)
        #expect(!coordinator.isBusy)
        let count = delivered.count
        #expect(delivered.last == [])
        monitor.sessions = []
        try await Task.sleep(for: .milliseconds(30))
        #expect(delivered.count == count)
        coordinator.setEnabled(["codex"])
        #expect(monitor.starts == 2)
        coordinator.stop()
    }

    @Test(arguments: [false, true])
    func reenableUsesFreshBaselineAndStillAnnouncesNewCompletions(asynchronous: Bool) async throws {
        let monitor = FeatureSyncMonitor()
        var watcher = SessionCompletionWatcher()
        var events: [SessionCompletionWatcher.Event] = []
        let coordinator = ActivityCoordinator(monitors: ["cursor": monitor]) { id, sessions in
            events += watcher.absorb([id: sessions])
        }
        defer { coordinator.stop() }
        func session(_ state: AgentSession.State) -> AgentSession {
            AgentSession(id: "same-session", name: "Fixture", detail: "Fixture",
                         state: state, waitingFor: nil, since: Date())
        }
        coordinator.setEnabled(["cursor"])
        monitor.sessions = [session(.busy)]
        try await Task.sleep(for: .milliseconds(40))
        coordinator.stop()
        events = []
        let finished = session(.success)
        monitor.onStart = {
            if asynchronous {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(10))
                    monitor.sessions = [finished]
                }
            } else { monitor.sessions = [finished] }
        }
        coordinator.setEnabled(["cursor"])
        try await Task.sleep(for: .milliseconds(60))
        #expect(events.isEmpty)
        monitor.sessions = [session(.busy)]
        try await Task.sleep(for: .milliseconds(30))
        events = []
        monitor.sessions = [session(.success)]
        try await Task.sleep(for: .milliseconds(30))
        #expect(events.map(\.reason) == [.finished])
    }
}

@MainActor private final class FeatureSyncMonitor: AgentActivityMonitor {
    @Published var sessions: [AgentSession] = []
    var sessionsPublisher: AnyPublisher<[AgentSession], Never> { $sessions.eraseToAnyPublisher() }
    var starts = 0
    var stops = 0
    var onStart: (() -> Void)?
    func start() { starts += 1; onStart?() }
    func stop() { stops += 1 }
}
