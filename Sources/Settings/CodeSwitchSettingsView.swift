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
import AppKit

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
                     hidden: Set<String>, names: [String: String], search: String, order: [String] = []) -> [Self] {
        var live = Dictionary(snapshots.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let currentIDs = Set(live.keys)
        for link in bindings.values where live[link.snapshot.id] == nil { live[link.snapshot.id] = link.snapshot }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let items: [Self] = Set(live.keys).union(hidden).map { id -> Self in
            let snapshot = live[id]
            return Self(id: id, name: snapshot?.displayName ?? names[id] ?? String(localized: "Unavailable provider"),
                        platform: snapshot?.linked?.platform ?? String(localized: "Not currently synced"), snapshot: snapshot,
                        reference: snapshot?.linked?.provider.providerId ?? providerReference(id),
                        isCurrent: currentIDs.contains(id))
        }.filter { row in
            query.isEmpty || [row.name, row.platform, row.reference].contains(where: { $0.localizedCaseInsensitiveContains(query) })
        }
        return CodeSwitchProviderOrder.arrange(items, by: order, id: \.id, name: \.name, platform: \.platform)
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
    @StateObject private var drag = CodeSwitchProviderDrag()

    private var rows: [CodeSwitchSettingsRow] {
        CodeSwitchSettingsRow.rows(snapshots: bridge.snapshots, bindings: bridge.bindings,
            hidden: preferences.hiddenCodeSwitchProviders, names: preferences.hiddenCodeSwitchNames,
            search: search, order: preferences.codeSwitchProviderOrder)
    }

    private var canReorder: Bool { search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        let rows = self.rows
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
                            CodeSwitchSettingsProviderRow(row: row, width: width, preferences: preferences,
                                duplicate: duplicates[row.savedName, default: 0] > 1, canReorder: canReorder,
                                drag: drag, acceptDrop: { payload, placement in
                                    guard let id = drag.takeSource(payload), canReorder else { return false }
                                    return preferences.moveCodeSwitchProvider(id, onto: row.id, placement: placement,
                                                                             visible: self.rows.map(\.id))
                                })
                            Divider()
                        }
                    } header: {
                        codeSwitchSummaryColumns(width: width) {
                            Text("Show").frame(maxWidth: .infinity, alignment: .trailing)
                        } identity: {
                            Text("Provider")
                        } today: {
                            Text("Today")
                        } quota: {
                            Text("Quota")
                        } details: {
                            Color.clear.frame(height: 1).accessibilityHidden(true)
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
        .onChange(of: search) { _, _ in drag.reset() }
        .onDisappear { drag.reset() }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Code Switch R integration", isOn: $preferences.codeSwitchEnabled)
                .toggleStyle(.switch).controlSize(.small)
            Picker("Show providers", selection: $preferences.codeSwitchDisplayMode) {
                ForEach(CodeSwitchDisplayMode.allCases) { mode in Text(mode.title).tag(mode) }
            }.disabled(!preferences.codeSwitchEnabled)
            Text("Receive enabled and quota-disabled providers, even without proxy hosting. This list stays complete; the scope controls the notch. Active sessions may appear temporarily; hidden providers stay hidden.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(bridge.connection.title).font(.caption).foregroundStyle(.secondary)
        }
    }

}

@MainActor
final class CodeSwitchProviderDrag: ObservableObject {
    private var source: String?
    private var payload: String?
    @Published private(set) var isActive = false

    func begin(_ id: String) -> String {
        source = id
        let token = UUID().uuidString
        payload = token
        isActive = true
        return token
    }

    func accepts(_ items: [String], target: String) -> Bool {
        isActive && source != target && items.count == 1 && items.first == payload
    }

    func update(_ phase: DragSession.Phase, items: [String]) {
        guard items.count == 1, items.first == payload else { return }
        switch phase {
        case .ended(let operation):
            isActive = false
            // A successful drop can deliver its payload after the pointer session ends.
            if operation != .move && operation != .copy { reset() }
        case .dataTransferCompleted:
            reset()
        default:
            break
        }
    }

    func takeSource(_ items: [String]) -> String? {
        guard items.count == 1, items.first == payload else { return nil }
        defer { reset() }
        return source
    }

    func reset() { source = nil; payload = nil; isActive = false }
}

private func codeSwitchSummaryColumns<Controls: View, Identity: View, Today: View, Quota: View, Details: View>(
    width: CGFloat, @ViewBuilder controls: () -> Controls, @ViewBuilder identity: () -> Identity,
    @ViewBuilder today: () -> Today, @ViewBuilder quota: () -> Quota, @ViewBuilder details: () -> Details
) -> some View {
    let available = max(0, width - 108)
    return HStack(alignment: .center, spacing: 10) {
        controls().frame(width: 48, alignment: .leading)
        identity().frame(width: available * 0.40, alignment: .leading)
        today().frame(width: available * 0.24, alignment: .leading)
        VStack(alignment: .leading) { quota() }.frame(width: available * 0.36, alignment: .leading)
        details().frame(width: 20)
    }
}

struct CodeSwitchSettingsProviderRow: View {
    let row: CodeSwitchSettingsRow
    let width: CGFloat
    @ObservedObject var preferences: Preferences
    let duplicate: Bool
    let canReorder: Bool
    @ObservedObject var drag: CodeSwitchProviderDrag
    let acceptDrop: ([String], CodeSwitchProviderOrder.Placement) -> Bool
    @State var expanded = false
    @State private var insertion: CodeSwitchProviderOrder.Placement?
    @State private var rowHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            summary
            if expanded { detail }
        }
        .font(.caption).monospacedDigit()
        .padding(.vertical, 12)
        .frame(width: width, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowHeight = $0 }
        .overlay(alignment: insertion == .before ? .top : .bottom) {
            if insertion != nil && drag.isActive && canReorder {
                Rectangle().fill(preferences.accentColor.color).frame(height: 2)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .dropDestination(for: String.self, isEnabled: canReorder) { items, session in
            insertion = nil
            if canReorder { _ = acceptDrop(items, .at(y: session.location.y, height: rowHeight)) }
        }
        .dropConfiguration { session in
            DropConfiguration(operation: canReorder && drag.accepts(
                session.localSession?.draggedItemIDs(for: String.self) ?? [], target: row.id) ? .move : .forbidden)
        }
        .onDropSessionUpdated { session in
            switch session.phase {
            case .entering, .active:
                insertion = canReorder && drag.accepts(
                    session.localSession?.draggedItemIDs(for: String.self) ?? [], target: row.id)
                    ? .at(y: session.location.y, height: rowHeight) : nil
            default:
                insertion = nil
            }
        }
        .onChange(of: drag.isActive) { _, active in if !active { insertion = nil } }
        .accessibilityElement(children: .contain)
    }

    private var summary: some View {
        let metrics = CodeSwitchTableMetrics(stats: row.currentSnapshot?.linked?.provider.stats)
        return codeSwitchSummaryColumns(width: width) {
            HStack(spacing: 5) {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.secondary).opacity(canReorder ? 1 : 0.35)
                    .frame(width: 24, height: 32).contentShape(Rectangle())
                    .draggable(String.self, id: \.self) { canReorder ? drag.begin(row.id) : nil }
                    .dragConfiguration(DragConfiguration(
                        operationsWithinApp: .init(allowCopy: false, allowMove: true),
                        operationsOutsideApp: .init(allowCopy: false)))
                    .onDragSessionUpdated { session in
                        drag.update(session.phase, items: session.draggedItemIDs(for: String.self))
                    }
                    .pointerStyle(canReorder ? .grabIdle : nil)
                    .help(canReorder ? String(localized: "Drag to reorder") : String(localized: "Clear search to reorder"))
                Toggle(row.savedName, isOn: Binding(get: { !preferences.hiddenCodeSwitchProviders.contains(row.id) }, set: { visible in
                    if visible {
                        preferences.hiddenCodeSwitchProviders.remove(row.id)
                        preferences.hiddenCodeSwitchNames.removeValue(forKey: row.id)
                    } else {
                        preferences.hiddenCodeSwitchNames[row.id] = row.savedName
                        preferences.hiddenCodeSwitchProviders.insert(row.id)
                    }
                })).labelsHidden().toggleStyle(.checkbox).help(row.savedName)
            }
        } identity: {
            HStack(alignment: .top, spacing: 6) {
                QueryIconView(icon: row.snapshot?.icon, fallback: row.snapshot?.glyph ?? .third, size: 20,
                              isStale: row.snapshot.map { $0.status.isStale || !$0.hasReading } ?? true)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.name).font(.callout.weight(.medium)).lineLimit(2).help(row.name)
                    Text(row.platform).foregroundStyle(.secondary).lineLimit(1).help(row.platform)
                    if let provider = row.currentSnapshot?.linked?.provider {
                        if provider.quotaAutoDisabled == true {
                            Text("Automatically disabled by quota").foregroundStyle(.orange)
                        } else if provider.effectiveQuotaState == "exhausted" {
                            Text("Quota exhausted").foregroundStyle(.orange)
                        }
                    }
                    if !row.isCurrent && row.snapshot != nil { Text("Session provider").foregroundStyle(.secondary) }
                    if duplicate { Text(row.reference).foregroundStyle(.secondary).lineLimit(1).help(row.reference) }
                }
            }
        } today: {
            VStack(alignment: .leading, spacing: 5) {
                Text("\(metrics.requests) requests")
                Text(metrics.cost).foregroundStyle(.secondary)
            }.fixedSize(horizontal: false, vertical: true)
        } quota: {
            CodeSwitchTableQuotaCell(snapshot: row.currentSnapshot, accent: preferences.accentColor.color,
                                     resetTimeFormat: preferences.resetTimeFormat, showsReset: false)
        } details: {
            Button { expanded.toggle() } label: {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .frame(width: 20, height: 32).contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(.secondary)
                .accessibilityLabel(expanded ? String(localized: "Hide details") : String(localized: "Show details"))
                .help(expanded ? String(localized: "Hide details") : String(localized: "Show details"))
        }
    }

    private var detail: some View {
        let metrics = CodeSwitchTableMetrics(stats: row.currentSnapshot?.linked?.provider.stats)
        return VStack(alignment: .leading, spacing: 12) {
            Divider()
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Today").fontWeight(.medium)
                    LabeledContent("Success rate", value: metrics.success)
                    LabeledContent("Tokens", value: metrics.tokens)
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Performance").fontWeight(.medium)
                    LabeledContent("First token", value: metrics.firstToken)
                    LabeledContent("Speed", value: metrics.speed)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("Quota").fontWeight(.medium)
            CodeSwitchTableQuotaCell(snapshot: row.currentSnapshot, accent: preferences.accentColor.color,
                                     resetTimeFormat: preferences.resetTimeFormat, expanded: true)
        }
        .padding(12)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
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
    var expanded = false
    var showsReset = true

    var body: some View {
        if let snapshot, let provider = snapshot.linked?.provider {
            let items = CodeSwitchTableQuota.items(snapshot)
            let visible = expanded ? items : items.max(by: { $0.priority < $1.priority }).map { [$0] } ?? []
            if provider.loading { Text("Loading…").foregroundStyle(.secondary) }
            else if provider.quotas.isEmpty { Text("No reading").foregroundStyle(.secondary) }
            if expanded {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .topLeading)], alignment: .leading, spacing: 12) {
                    ForEach(visible) { item in quotaItem(item) }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(visible) { item in quotaItem(item) }
                }
            }
        } else {
            Text("Not currently synced").foregroundStyle(.secondary)
        }
    }

    private func quotaItem(_ item: CodeSwitchTableQuota) -> some View {
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
                if showsReset, let reset = window.resetsAt {
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
}
