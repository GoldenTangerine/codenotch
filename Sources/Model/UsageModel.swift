/**
 @name: 额度展示模型
 @Descripttion: 统一表示供应商读数、金额及查询状态。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-08 14:56:06
 @LastEditTime: 2026-09-08 14:56:06
 @FilePath: Sources/Model/UsageModel.swift
 */
import Foundation

struct QuotaQuantity: Codable, Equatable {
    var remaining: Double?
    var used: Double?
    var total: Double?
    var unit = ""
    var unlimited = false

    static func format(_ value: Double, compact: Bool = false) -> String {
        guard value.isFinite else { return "—" }
        let magnitude = abs(value)
        if compact && magnitude >= 1e12 {
            return value.formatted(.number.notation(.scientific).precision(.significantDigits(1...3)))
        }
        let divisor: Double = compact ? (magnitude >= 1e9 ? 1e9 : magnitude >= 1e6 ? 1e6 : magnitude >= 1e3 ? 1e3 : 1) : 1
        let suffix = divisor == 1e9 ? "B" : divisor == 1e6 ? "M" : divisor == 1e3 ? "K" : ""
        return (value / divisor).formatted(.number.precision(.fractionLength(0...2))) + suffix
    }

    var summary: String {
        if unlimited { return String(localized: "Unlimited") }
        let suffix = unit.isEmpty ? "" : " \(unit)"
        if let remaining { return String(localized: "\(Self.format(remaining) + suffix) remaining") }
        if let used { return String(localized: "\(Self.format(used) + suffix) used") }
        if let total { return String(localized: "\(Self.format(total) + suffix) total") }
        return String(localized: "No reading")
    }
}

/// How much to trust a provider's numbers. The UI never presents a derived or
/// manual figure as if a vendor had published it.
enum Fidelity: String, Codable, Equatable {
    case official
    case derived
    case manual

    /// Prefix shown in front of a percentage that we worked out ourselves.
    var qualifier: String { self == .official ? "" : "~" }
}

enum ProviderStatus: Equatable {
    case ok
    case stale(since: Date)
    case needsAuth
    /// macOS was asked for a credential that exists, and refused.
    case accessDenied
    case unsupported(String)
    case error(String)

    var isStale: Bool { if case .stale = self { return true }; return false }

    /// When the reading behind this status was actually taken.
    var staleSince: Date? { if case .stale(let since) = self { return since }; return nil }
}

/// How percentages read.
///
/// Whole percents above one — "12%", "104%" — because decimals there are
/// noise. Below one, whole percents collapse a real reading into "0%", the one
/// number that looks most like "nothing used", so both halves gain a tenth of
/// a percent and still add up: 0.3% used is 99.7% left. A tenth of nothing
/// says so rather than pretending to be zero.
enum Percent {
    /// The two halves of a used-fraction, as display text.
    static func halves(for fraction: Double) -> (used: String, left: String) {
        let value = fraction * 100
        let fractional = (value > 0 && value < 1) || (value > 99 && value < 100)
        guard fractional else {
            // The left half derives from the *rounded* used half, not from the
            // raw value — 9.5% used is "10% Used · 90% left", because that is
            // how the dashboard the user is comparing against does the maths.
            let used = Int(value.rounded())
            return ("\(used)", "\(max(0, 100 - used))")
        }
        let left = max(0, 100 - value)
        // "<0.1" has no number to subtract from a hundred, so the far half
        // makes the same claim from its own end: ">99.9".
        return (small(value), left > 99.9 ? ">99.9" : small(left))
    }

    /// One percentage, as display text — the ring's label.
    static func text(for fraction: Double) -> String {
        let value = fraction * 100
        guard value > 0, value < 1 else { return "\(Int(value.rounded()))" }
        return small(value)
    }

    private static func small(_ value: Double) -> String {
        if value <= 0 { return "0" }
        let tenths = (value * 10).rounded() / 10
        if tenths < 0.1 { return "<0.1" }
        if tenths > 99.9 { return ">99.9" }
        // Fixed locale: the decimal point is not up to the system settings,
        // any more than "%" is.
        return String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), tenths)
    }
}

/// One metered window a provider exposes — Claude has two (the rolling session
/// and the longer all-models window), others have one.
struct LimitWindow: Identifiable, Codable, Equatable {
    let id: String
    let label: String
    /// 0...1+, where 1 means the limit is spent. Nil when the provider reports
    /// what is left but never says what the limit was — Perplexity does exactly
    /// this, and a percentage would have to invent the denominator.
    let usedFraction: Double?
    /// How many are left, when that is what the provider reports.
    let remaining: Int?
    /// How many have been spent, when the provider counts up rather than down
    /// and never states the ceiling. Cursor does this.
    let used: Int?
    /// Nil when the provider does not say when the window rolls over.
    let resetsAt: Date?
    let quantity: QuotaQuantity?

    init(id: String, label: String, usedFraction: Double? = nil,
         remaining: Int? = nil, used: Int? = nil, resetsAt: Date? = nil,
         quantity: QuotaQuantity? = nil) {
        self.id = id
        self.label = label
        self.usedFraction = usedFraction
        self.remaining = remaining
        self.used = used
        self.resetsAt = resetsAt
        self.quantity = quantity
    }

    /// A count short enough to sit inside a 44 pt ring.
    ///
    /// Requests and credits are three or four digits and print verbatim; token
    /// counts run to seven, and "651061" under the ring is unreadable at that
    /// width. The threshold is 10 000 so no existing provider's number changes.
    static func compact(_ count: Int) -> String {
        if count < 10_000 { return "\(count)" }
        if count < 1_000_000 { return "\(count / 1_000)k" }
        return String(format: "%.1fM", Double(count) / 1_000_000)
    }

    /// What the tooltip says on the line under the bar.
    var summary: String {
        if let quantity {
            if let used = quantity.used, let total = quantity.total {
                return "\(QuotaQuantity.format(used)) / \(QuotaQuantity.format(total)) \(quantity.unit) · \(quantity.summary)"
            }
            return quantity.summary
        }
        if let usedFraction {
            // Both ends of the same figure. Vendors do not agree on which to
            // show — Codex writes "87% remaining", Claude writes "% used" — so
            // a notch that picks one side leaves the user converting in their
            // head, and "12% Used" beside Codex's "87% remaining" reads as two
            // different numbers rather than one seen from either end. That is
            // what made a correct reading look wrong.
            let halves = Percent.halves(for: usedFraction)
            if let used = Int(halves.used), let left = Int(halves.left) {
                return String(localized: "\(used)% Used · \(left)% left")
            }
            return String(localized: "\(halves.used)% Used · \(halves.left)% left")
        }
        if let remaining {
            if remaining < 10_000 { return String(localized: "\(remaining) left") }
            return String(localized: "\(Self.compact(remaining)) left")
        }
        if let used {
            if used < 10_000 { return String(localized: "\(used) used") }
            return String(localized: "\(Self.compact(used)) used")
        }
        return String(localized: "No reading")
    }
}

/// A limit that has been *reached*, even where the headline still shows room.
///
/// Vendors meter some capabilities separately from the plan's main allowance,
/// so "84% left" and "paused until 4:13 PM" are both true at once. A ring that
/// only knows the headline reports the first and hides the second, which is
/// the reading that actually stops you working.
struct UsageBlock: Equatable {
    /// What is paused, in the vendor's own terms.
    let reason: String
    /// When it lifts, where the vendor says.
    let resetsAt: Date?

    /// The line the tooltip leads with.
    func summary(now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let resetsAt, resetsAt > now else { return reason }
        let formatter = ResetCopy.formatter(for: calendar)
        // The same clock the vendor's own banner uses — "4:13 PM" — rather
        // than a countdown, because that is what you are waiting for.
        ResetCopy.applyClockFormat(to: formatter,
                                   weekday: ResetCopy.daysApart(from: now, to: resetsAt,
                                                                calendar: calendar) >= 1)
        return String(localized: "\(reason) until \(formatter.string(from: resetsAt))")
    }
}

struct ProviderSnapshot: Identifiable, Equatable {
    let id: String
    let displayName: String
    let glyph: ProviderGlyph
    let fidelity: Fidelity
    var status: ProviderStatus
    let windows: [LimitWindow]
    /// Which window the ring means, declared by the provider rather than left to
    /// position. Without it the headline is "whichever window happens to be
    /// first", and a window dropping out of the response silently promotes
    /// another one — the ring keeps its shape and quietly changes its subject.
    var headlineID: String?
    /// Set when something is blocked right now. Deliberately separate from the
    /// windows: it is not a measurement, it is a door being shut.
    var block: UsageBlock?
    var icon: ProviderIcon?
    var manualQuery: Bool = false
    var queryFailure: String?
    var queryRetryAfter: Date?
    var linked: CodeSwitchDetails?

    /// The number on the cell: the provider's declared primary window — for
    /// Claude, the current session.
    ///
    /// Not the most-constrained window, which is what the design spec asks for.
    /// Picking whichever limit is highest means the headline silently changes
    /// meaning — session one minute, weekly the next — and disagrees with
    /// Claude's own panel, which always leads with the session.
    ///
    /// If the declared window is missing from the response the cell shows no
    /// reading rather than promoting a different one. A blank is honest; a
    /// weekly percentage wearing the session's place is not.
    var headline: LimitWindow? {
        guard let headlineID else { return windows.first }
        return windows.first { $0.id == headlineID }
    }

    var usedFraction: Double? { headline?.usedFraction }

    /// What the cell prints under the ring.
    var headlineText: String {
        if headline?.quantity?.unlimited == true { return "∞" }
        if let usedFraction { return Percent.text(for: usedFraction) + "%" }
        if let quantity = headline?.quantity {
            if let value = quantity.remaining ?? quantity.used ?? quantity.total {
                let symbol = ["USD": "$", "CNY": "¥", "EUR": "€", "GBP": "£"][quantity.unit.uppercased()] ?? ""
                return symbol + QuotaQuantity.format(value, compact: true)
            }
        }
        if let remaining = headline?.remaining { return LimitWindow.compact(remaining) }
        if let used = headline?.used { return LimitWindow.compact(used) }
        return "—"
    }

    /// True when there is no reading to show — the cell draws an empty ring and
    /// a dash rather than an authoritative-looking 0%.
    var hasReading: Bool { !windows.isEmpty }

    /// A ring can only be drawn when the provider said what the limit was.
    var ringFraction: Double? { usedFraction }

    /// Signing in means something different per provider, so the prompt has to
    /// say which door to knock on.
    private var authPrompt: String {
        if manualQuery { return String(localized: "Update this provider's credentials in Settings.") }
        switch id {
        case "claude":     return String(localized: "Sign in to Claude Code to read your usage")
        // A profile is signed in by running Claude Code against its directory,
        // which is worth saying: plain `claude` signs the default one in.
        case _ where ClaudeProfile.isClaude(providerID: id):
            let slug = ClaudeProfile.slug(fromProviderID: id) ?? ""
            return String(localized: "Sign in to Claude Code in ~/.claude-\(slug) to read your usage")
        case "cursor":     return String(localized: "Sign in to Cursor in the editor")
        case "codex":      return String(localized: "Sign in to Codex to read your usage")
        case "gemini":     return String(localized: "Sign in to Antigravity to read your usage")
        case "glm":        return String(localized: "Set up a GLM Coding Plan key for a coding tool to read your usage")
        case "copilot": return String(localized: "Sign in with GitHub CLI to read your Copilot usage")
        case "opencode":   return String(localized: "Connect the Go plan in OpenCode to read your usage")
        default:           return String(localized: "Sign in to \(displayName) to read your usage")
        }
    }

    var isActivityOnly: Bool { id.hasPrefix("activity:") }

    var tooltipTitle: String {
        isActivityOnly ? displayName : String(localized: "\(displayName) Usage")
    }

    func refreshNote(isRefreshing: Bool, now: Date) -> String? {
        if isRefreshing { return String(localized: "Refreshing…") }
        if let until = queryRetryAfter, until > now {
            return String(localized: "Retry after \(until.formatted(date: .omitted, time: .standard))")
        }
        if queryFailure != nil { return String(localized: "Refresh failed") }
        guard hasReading, let since = status.staleSince, since != .distantPast else { return nil }
        return ElapsedCopy.ago(since: since, now: now)
    }

    /// What the tooltip says instead of limit rows when there is nothing to show.
    var statusMessage: String? {
        if isActivityOnly { return String(localized: "Provider not linked yet") }
        if hasReading { return nil }
        switch status {
        case .needsAuth:      return authPrompt
        case .accessDenied:
            // Says what happened and what fixes it. "Sign in to Claude Code"
            // would send someone who *is* signed in to fix the wrong thing.
            // One long literal rather than wrapped with +: concatenation would
            // pick the non-localising overload and never reach the catalog.
            return String(localized: "Codenotch was refused access to \(displayName)'s saved login. Click this ring to ask again, and choose Always Allow.")
        case .unsupported(let why): return why
        case .error(let why): return String(localized: "Couldn't read usage — \(why)")
        case .stale, .ok:     return String(localized: "Waiting for the first reading…")
        }
    }
}
