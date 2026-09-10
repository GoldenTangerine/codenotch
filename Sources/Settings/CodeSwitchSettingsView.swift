/**
 @name: Code Switch 联动设置页
 @Descripttion: 配置联动范围、连接状态和供应商显示偏好。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-10 18:00:00
 @LastEditTime: 2026-09-10 18:00:00
 @FilePath: Sources/Settings/CodeSwitchSettingsView.swift
 */
import SwiftUI

struct CodeSwitchSettingsRow: Identifiable {
    let id: String
    let name: String
    let platform: String
    let snapshot: ProviderSnapshot?
    let reference: String
    let isCurrent: Bool
    var currentSnapshot: ProviderSnapshot? { isCurrent ? snapshot : nil }
    var savedName: String { snapshot == nil ? name : name + " · " + platform }

    static func rows(snapshots: [ProviderSnapshot], bindings: [String: CodeSwitchSessionLink],
                     hidden: Set<String>, names: [String: String], search: String) -> [Self] {
        var live = Dictionary(snapshots.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let currentIDs = Set(live.keys)
        for link in bindings.values where live[link.snapshot.id] == nil { live[link.snapshot.id] = link.snapshot }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return Set(live.keys).union(hidden).map { id in
            let snapshot = live[id]
            return Self(id: id, name: snapshot?.displayName ?? names[id] ?? String(localized: "Unavailable provider"),
                        platform: snapshot?.linked?.platform ?? String(localized: "Not currently synced"), snapshot: snapshot,
                        reference: snapshot?.linked?.provider.providerId ?? providerReference(id),
                        isCurrent: currentIDs.contains(id))
        }.filter {
            query.isEmpty || [$0.name, $0.platform, $0.reference].contains { $0.localizedCaseInsensitiveContains(query) }
        }.sorted {
            if $0.name != $1.name { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            if $0.platform != $1.platform { return $0.platform.localizedStandardCompare($1.platform) == .orderedAscending }
            return $0.id < $1.id
        }
    }

    private static func providerReference(_ id: String) -> String {
        // The platform itself may contain colons or non-ASCII characters.
        let prefix = "code-switch:"
        guard id.hasPrefix(prefix) else { return id }
        let suffix = id.dropFirst(prefix.count)
        guard let colon = suffix.firstIndex(of: ":"), let length = Int(suffix[..<colon]), length >= 0 else { return id }
        let bytes = Array(suffix[suffix.index(after: colon)...].utf8)
        guard length < bytes.count, bytes[length] == 58 else { return id }
        return String(decoding: bytes.dropFirst(length + 1), as: UTF8.self)
    }
}

struct CodeSwitchTableMetrics {
    let stats: CodeSwitchStats?
    private func number(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "—" }
        return QuotaQuantity.format(value, compact: true)
    }
    var success: String {
        guard let stats, stats.successfulRequests + stats.failedRequests > 0, stats.successRate.isFinite else { return "—" }
        return QuotaQuantity.format(min(1, max(0, stats.successRate)) * 100) + "%"
    }
    var requests: String { number(stats?.totalRequests) }
    var tokens: String { number(stats.map { $0.inputTokens + $0.outputTokens + $0.cacheReadTokens }) }
    var cost: String {
        guard let value = stats?.costTotal, value.isFinite, value >= 0 else { return "—" }
        return value.formatted(.currency(code: "USD").precision(.fractionLength(2...4)))
    }
    var firstToken: String {
        guard let value = stats?.avgFirstTokenSec, value.isFinite, value > 0 else { return "—" }
        return value < 1 ? QuotaQuantity.format(value * 1000) + " ms" : QuotaQuantity.format(value) + " s"
    }
    var speed: String {
        guard let value = stats?.avgTokensPerSec, value.isFinite, value > 0 else { return "—" }
        return QuotaQuantity.format(value) + " t/s"
    }
}

struct CodeSwitchSettingsView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var bridge: CodeSwitchBridge
    @State private var search = ""

    var body: some View {
        let rows = CodeSwitchSettingsRow.rows(snapshots: bridge.snapshots, bindings: bridge.bindings,
            hidden: preferences.hiddenCodeSwitchProviders, names: preferences.hiddenCodeSwitchNames, search: search)
        let duplicates = Dictionary(grouping: rows, by: \.savedName).mapValues(\.count)
        GeometryReader { geometry in
            let width = max(0, geometry.size.width - 40)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    controls.padding(.bottom, 18)
                    HStack {
                        TextField("Search providers", text: $search).textFieldStyle(.roundedBorder)
                        if !preferences.hiddenCodeSwitchProviders.isEmpty {
                            Button("Show all providers") {
                                preferences.hiddenCodeSwitchProviders = []
                                preferences.hiddenCodeSwitchNames = [:]
                            }.controlSize(.small)
                        }
                    }.padding(.bottom, 12)
                    Section {
                        if rows.isEmpty {
                            Text(search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                 ? String(localized: "Providers appear here when received from Code Switch R.")
                                 : String(localized: "No matching providers"))
                                .font(.caption).foregroundStyle(.secondary).padding(.vertical, 24)
                        }
                        ForEach(rows) { row in
                            tableRow(row, width: width, duplicate: duplicates[row.savedName, default: 0] > 1)
                            Divider()
                        }
                    } header: {
                        columns(width: width) {
                            Text("Show")
                        } identity: {
                            Text("Provider")
                        } statistics: {
                            Text("Today")
                        } performance: {
                            Text("Performance")
                        } quota: {
                            Text("Quota")
                        }
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        .padding(.vertical, 10)
                        .background(.regularMaterial)
                    }
                    Text("Hidden providers and their session activity stay out of the notch. This does not change Code Switch R settings.")
                        .font(.caption).foregroundStyle(.secondary).padding(.top, 12)
                }
                .frame(width: width, alignment: .leading)
                .padding(.horizontal, 20).padding(.bottom, 20)
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Code Switch R integration", isOn: $preferences.codeSwitchEnabled)
                .toggleStyle(.switch).controlSize(.small)
            Picker("Show providers", selection: $preferences.codeSwitchDisplayMode) {
                ForEach(CodeSwitchDisplayMode.allCases) { mode in Text(mode.title).tag(mode) }
            }.disabled(!preferences.codeSwitchEnabled)
            Text("Enabled providers have proxy hosting and their provider switch turned on, including hidden platforms.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(bridge.connection.title).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func columns<Show: View, Identity: View, Statistics: View, Performance: View, Quota: View>(
        width: CGFloat, @ViewBuilder show: () -> Show, @ViewBuilder identity: () -> Identity,
        @ViewBuilder statistics: () -> Statistics, @ViewBuilder performance: () -> Performance,
        @ViewBuilder quota: () -> Quota
    ) -> some View {
        let available = max(0, width - 56)
        return HStack(alignment: .top, spacing: 6) {
            show().frame(width: 32, alignment: .leading)
            identity().frame(width: available * 0.26, alignment: .leading)
            statistics().frame(width: available * 0.29, alignment: .leading)
            performance().frame(width: available * 0.19, alignment: .leading)
            VStack(alignment: .leading) { quota() }.frame(width: available * 0.26, alignment: .leading)
        }
    }

    private func tableRow(_ row: CodeSwitchSettingsRow, width: CGFloat, duplicate: Bool) -> some View {
        let metrics = CodeSwitchTableMetrics(stats: row.currentSnapshot?.linked?.provider.stats)
        return columns(width: width) {
            Toggle(row.savedName, isOn: Binding(get: { !preferences.hiddenCodeSwitchProviders.contains(row.id) }, set: { visible in
                if visible {
                    preferences.hiddenCodeSwitchProviders.remove(row.id)
                    preferences.hiddenCodeSwitchNames.removeValue(forKey: row.id)
                } else {
                    preferences.hiddenCodeSwitchNames[row.id] = row.savedName
                    preferences.hiddenCodeSwitchProviders.insert(row.id)
                }
            })).labelsHidden().toggleStyle(.checkbox).help(row.savedName)
        } identity: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 5) {
                    QueryIconView(icon: row.snapshot?.icon, fallback: row.snapshot?.glyph ?? .third, size: 16)
                        .accessibilityHidden(true)
                    Text(row.name).font(.callout.weight(.medium)).lineLimit(2).help(row.name)
                }
                Text(row.platform).foregroundStyle(.secondary)
                if !row.isCurrent && row.snapshot != nil {
                    Text("Session provider").foregroundStyle(.secondary)
                }
                if duplicate { Text(row.reference).foregroundStyle(.secondary).lineLimit(1).help(row.reference) }
            }
        } statistics: {
            ViewThatFits(in: .horizontal) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack { metric("Success rate", metrics.success); metric("Requests", metrics.requests) }
                    HStack { metric("Tokens", metrics.tokens); metric("Cost", metrics.cost) }
                }.fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 5) {
                    metric("Success rate", metrics.success)
                    metric("Requests", metrics.requests)
                    metric("Tokens", metrics.tokens)
                    metric("Cost", metrics.cost)
                }
            }
        } performance: {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("First token").foregroundStyle(.secondary)
                    Text(metrics.firstToken)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Speed").foregroundStyle(.secondary)
                    Text(metrics.speed)
                }
            }
        } quota: {
            CodeSwitchTableQuotaCell(snapshot: row.currentSnapshot, accent: preferences.accentColor.color,
                                     resetTimeFormat: preferences.resetTimeFormat)
        }
        .font(.caption).monospacedDigit()
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }

    private func metric(_ label: LocalizedStringKey, _ value: String) -> some View {
        Text("\(Text(label).foregroundColor(.secondary)) \(Text(verbatim: value))")
            .fixedSize(horizontal: false, vertical: true)
    }

}

struct CodeSwitchTableQuota: Identifiable {
    let id: Int
    let quota: CodeSwitchQuota
    let window: LimitWindow?
    var band: UsageBand { UsageBand.band(for: window?.usedFraction ?? 0) }
    var priority: Double {
        if window == nil && (quota.active || quota.displayKind == "error" || quota.invalidMessage?.isEmpty == false) {
            return .infinity
        }
        return window?.usedFraction ?? (window == nil ? -1 : 0)
    }

    static func items(_ snapshot: ProviderSnapshot) -> [Self] {
        // Windows are already parsed when the bridge accepts a snapshot. Consume
        // them in quota order so invalid or duplicate keys cannot shift a reading.
        var windows = snapshot.windows.makeIterator()
        return (snapshot.linked?.provider.quotas ?? []).enumerated().map { index, quota in
            Self(id: index, quota: quota, window: quota.hasWindow ? windows.next() : nil)
        }
    }
}

struct CodeSwitchTableQuotaCell: View {
    let snapshot: ProviderSnapshot?
    let accent: Color
    let resetTimeFormat: ResetTimeFormat
    @State var expanded = false

    var body: some View {
        if let snapshot, let provider = snapshot.linked?.provider {
            let items = CodeSwitchTableQuota.items(snapshot)
            let visible = expanded ? items : items.max(by: { $0.priority < $1.priority }).map { [$0] } ?? []
            if provider.loading { Text("Loading…").foregroundStyle(.secondary) }
            else if provider.quotas.isEmpty { Text("No reading").foregroundStyle(.secondary) }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(visible) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        if let window = item.window {
                            if let fraction = window.usedFraction {
                                Text("\(Text(item.quota.title).foregroundColor(.secondary)) \(Text(QuotaQuantity.format(fraction * 100) + "%"))")
                                    .fixedSize(horizontal: false, vertical: true)
                                ProgressView(value: min(1, max(0, fraction))).progressViewStyle(.linear)
                                    .tint(item.band.color(accent: accent))
                                    .accessibilityLabel(item.quota.title)
                            } else {
                                Text(item.quota.title).foregroundStyle(.secondary)
                                Text(window.quantity?.summary ?? String(localized: "No reading"))
                            }
                            if let reset = window.resetsAt {
                                TimelineView(.periodic(from: .now, by: 60)) { context in
                                    Text(ResetCopy.text(for: reset, now: context.date, format: resetTimeFormat))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } else if !item.quota.active && item.quota.displayKind != "error" && item.quota.invalidMessage?.isEmpty != false {
                            Text(item.quota.title).foregroundStyle(.secondary)
                            Text("Period has not started").foregroundStyle(.secondary)
                        } else {
                            Text(item.quota.title).foregroundStyle(.secondary)
                            Text("Quota unavailable").foregroundStyle(Palette.critical)
                        }
                    }
                }
                if items.count > 1 {
                    Button { expanded.toggle() } label: {
                        if expanded { Text("Fewer quotas") } else { Text("All quotas") }
                    }.buttonStyle(.link).font(.caption)
                }
            }
        } else {
            Text("Not currently synced").foregroundStyle(.secondary)
        }
    }
}
