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
    static func ago(since: Date, now: Date = Date()) -> String {
        switch span(since: since, now: now) {
        case .justNow:                          return String(localized: "just now")
        case .minutes(let m):                   return String(localized: "\(m) min ago")
        case .hours(let h):                     return String(localized: "\(h) hr ago")
        case .hoursMinutes(let h, let m):       return String(localized: "\(h) hr \(m) min ago")
        }
    }

    static func text(since: Date, now: Date = Date()) -> String {
        switch span(since: since, now: now) {
        case .justNow:                          return String(localized: "just now")
        case .minutes(let m):                   return String(localized: "\(m) min")
        case .hours(let h):                     return String(localized: "\(h) hr")
        case .hoursMinutes(let h, let m):       return String(localized: "\(h) hr \(m) min")
        }
    }
}
