/**
 @name: 上游同步模块
 @Descripttion: 维护 ElapsedCopy.swift 的项目实现与上游兼容。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-11 15:51:14
 @LastEditTime: 2026-09-11 15:51:14
 @FilePath: Sources/Model/ElapsedCopy.swift
 */
import Foundation

/// "how long has it been like this" — the second half of answering "is Claude
/// still working".
enum ElapsedCopy {
    /// The size of the gap, in buckets both phrasings share. One ladder in one
    /// place: if the thresholds ever move, "5 min" and "5 min ago" move
    /// together.
    private enum Span: Equatable {
        case justNow
        case minutes(Int)
        case hours(Int)
        case hoursMinutes(Int, Int)
    }

    private static func span(since: Date, now: Date) -> Span {
        let seconds = max(0, now.timeIntervalSince(since))
        if seconds < 45 { return .justNow }

        // Rounding, not truncation — the same rule ResetCopy keeps.
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return .minutes(max(1, minutes)) }

        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? .hours(hours) : .hoursMinutes(hours, rest)
    }

    /// The same span, phrased as a point in the past.
    ///
    /// Each bucket is a whole template rather than `"…" + " ago"`: the words
    /// go in a different order in different languages ("5 min ago" reads
    /// "5 分钟前" in Chinese), and only the translator sees both ends at once.
    static func ago(since: Date, now: Date = Date(), locale: Locale = L10n.locale) -> String {
        switch span(since: since, now: now) {
        case .justNow:                          return L10n.t("just now", locale: locale)
        case .minutes(let m):                   return L10n.t("\(m) min ago", locale: locale)
        case .hours(let h):                     return L10n.t("\(h) hr ago", locale: locale)
        case .hoursMinutes(let h, let m):       return L10n.t("\(h) hr \(m) min ago", locale: locale)
        }
    }

    static func text(since: Date, now: Date = Date(), locale: Locale = L10n.locale) -> String {
        switch span(since: since, now: now) {
        case .justNow:                          return L10n.t("just now", locale: locale)
        case .minutes(let m):                   return L10n.t("\(m) min", locale: locale)
        case .hours(let h):                     return L10n.t("\(h) hr", locale: locale)
        case .hoursMinutes(let h, let m):       return L10n.t("\(h) hr \(m) min", locale: locale)
        }
    }
}
