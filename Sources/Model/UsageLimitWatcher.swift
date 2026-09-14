/**
 @name: 上游同步 · UsageLimitWatcher
 @Descripttion: 保留上游功能实现并兼容本地扩展。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-14 09:43:04
 @LastEditTime: 2026-09-14 09:43:04
 @FilePath: Sources/Model/UsageLimitWatcher.swift
 */
import Foundation

/// Watches store snapshots and detects when a provider's session or weekly
/// limit reaches 100% (exhausted) or becomes blocked.
@MainActor
final class UsageLimitWatcher {
    private struct TrackedLimit {
        var windowID: String?
        var isExhausted: Bool = false
        var resetsAt: Date?
        var fraction: Double = 0
    }

    private struct ProviderLimitState {
        var session: TrackedLimit = TrackedLimit()
        var weekly: TrackedLimit = TrackedLimit()
    }

    private var states: [String: ProviderLimitState] = [:]
    private let isMuted: (String) -> Bool
    private let deliver: (UsageAlertEvent) -> Void

    init(
        isMuted: @escaping (String) -> Bool = { _ in false },
        deliver: @escaping (UsageAlertEvent) -> Void = { _ in }
    ) {
        self.isMuted = isMuted
        self.deliver = deliver
    }

    func observe(_ snapshots: [ProviderSnapshot]) {
        for snapshot in snapshots {
            observe(snapshot)
        }
    }

    private func observe(_ snapshot: ProviderSnapshot) {
        var state = states[snapshot.id] ?? ProviderLimitState()
        let isFirstObservation = states[snapshot.id] == nil

        // 1. Session limit (headline window)
        if let headline = snapshot.headline, let fraction = snapshot.usedFraction {
            let changedWindow = state.session.windowID != headline.id
            if changedWindow { state.session = TrackedLimit(windowID: headline.id) }
            let isExhausted = fraction >= 1.0 || snapshot.block != nil

            let dateRolledOver = headline.resetsAt != nil
                && state.session.resetsAt != nil
                && headline.resetsAt != state.session.resetsAt
                && headline.resetsAt! > state.session.resetsAt!

            if snapshot.block == nil && (dateRolledOver || fraction < 0.95) {
                state.session.isExhausted = false
            }

            if isExhausted && !state.session.isExhausted && !isFirstObservation && !changedWindow && !isMuted(snapshot.id) {
                state.session.isExhausted = true
                deliver(UsageAlertEvent(
                    kind: .sessionLimitReached,
                    providerID: snapshot.id,
                    providerName: snapshot.displayName,
                    windowLabel: headline.label,
                    glyph: snapshot.glyph,
                    previousFraction: state.session.fraction,
                    currentFraction: fraction,
                    resetsAt: headline.resetsAt
                ))
            } else if (isFirstObservation || changedWindow) && isExhausted {
                state.session.isExhausted = true
            }

            state.session.fraction = fraction
            state.session.resetsAt = headline.resetsAt
        }

        // 2. Weekly limit (secondary window)
        if let weekly = snapshot.weeklyWindow, let weeklyFraction = snapshot.weeklyFraction {
            let changedWindow = state.weekly.windowID != weekly.id
            if changedWindow { state.weekly = TrackedLimit(windowID: weekly.id) }
            let isWeeklyExhausted = weeklyFraction >= 1.0

            let dateRolledOver = weekly.resetsAt != nil
                && state.weekly.resetsAt != nil
                && weekly.resetsAt != state.weekly.resetsAt
                && weekly.resetsAt! > state.weekly.resetsAt!

            if dateRolledOver || weeklyFraction < 0.95 {
                state.weekly.isExhausted = false
            }

            if isWeeklyExhausted && !state.weekly.isExhausted && !isFirstObservation && !changedWindow && !isMuted(snapshot.id) {
                state.weekly.isExhausted = true
                deliver(UsageAlertEvent(
                    kind: .weeklyLimitReached,
                    providerID: snapshot.id,
                    providerName: snapshot.displayName,
                    windowLabel: weekly.label,
                    glyph: snapshot.glyph,
                    previousFraction: state.weekly.fraction,
                    currentFraction: weeklyFraction,
                    resetsAt: weekly.resetsAt
                ))
            } else if (isFirstObservation || changedWindow) && isWeeklyExhausted {
                state.weekly.isExhausted = true
            }

            state.weekly.fraction = weeklyFraction
            state.weekly.resetsAt = weekly.resetsAt
        }

        states[snapshot.id] = state
    }
}
