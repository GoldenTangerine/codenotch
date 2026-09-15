/**
 @name: 联动今日用量记录
 @Descripttion: 持久化供应商额度观测增量，隔离跨日、单位变化和周期重置。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-15 11:04:18
 @LastEditTime: 2026-09-15 11:04:18
 @FilePath: Sources/Model/CodeSwitchDailyUsage.swift
 */
import Foundation

final class CodeSwitchDailyUsage {
    struct Sample: Codable, Equatable {
        let day: Date
        let timeZone: String
        let sourceKey: String
        let reset: Date
        let unit: String
        let mode: String
        var lastUsed: Double
        var todayUsed: Double

        func matches(_ quota: CodeSwitchQuota, now: Date, calendar: Calendar) -> Bool {
            day == calendar.startOfDay(for: now) && timeZone == calendar.timeZone.identifier
                && sourceKey == quota.key && reset == quota.reset
                && unit == CodeSwitchDailyBudget.unit(quota) && mode == (quota.valueMode ?? "currency")
                && lastUsed.isFinite && lastUsed >= 0 && todayUsed.isFinite && todayUsed >= 0
        }
    }

    static let defaultsKey = "codeSwitchDailyUsage.v1"
    private let defaults: UserDefaults?
    private var records: [String: Sample]

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
        records = defaults?.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode([String: Sample].self, from: $0) } ?? [:]
    }

    func observe(_ snapshots: [ProviderSnapshot], now: Date, calendar: Calendar = .current) -> [ProviderSnapshot] {
        let before = records
        let result = snapshots.map { snapshot -> ProviderSnapshot in
            var decorated = snapshot
            decorated.codeSwitchDailyUsage = nil
            guard let source = CodeSwitchDailyBudget.source(in: snapshot, now: now),
                  let reset = source.reset else { return decorated }
            let key = snapshot.id + ":" + source.key
            var sample = records[key]
            if snapshot.status.isStale || snapshot.linked?.provider.loading == true {
                if sample?.matches(source, now: now, calendar: calendar) == true {
                    decorated.codeSwitchDailyUsage = sample
                }
                return decorated
            }
            if sample?.matches(source, now: now, calendar: calendar) != true || source.used < (sample?.lastUsed ?? 0) {
                sample = Sample(day: calendar.startOfDay(for: now), timeZone: calendar.timeZone.identifier,
                    sourceKey: source.key, reset: reset, unit: CodeSwitchDailyBudget.unit(source),
                    mode: source.valueMode ?? "currency", lastUsed: source.used, todayUsed: 0)
            } else if var current = sample {
                let total = current.todayUsed + max(0, source.used - current.lastUsed)
                guard total.isFinite else { return decorated }
                current.todayUsed = total
                current.lastUsed = source.used
                sample = current
            }
            records[key] = sample
            decorated.codeSwitchDailyUsage = sample
            return decorated
        }
        records = records.filter { now.timeIntervalSince($0.value.day) < 32 * 86_400 }
        // 心跳与相同用量不会重复写入；UserDefaults 合并磁盘写入，保留同日重启所需基线。
        if records != before, let data = try? JSONEncoder().encode(records) {
            defaults?.set(data, forKey: Self.defaultsKey)
        }
        return result
    }
}
