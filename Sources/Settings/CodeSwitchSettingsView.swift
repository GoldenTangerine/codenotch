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

struct CodeSwitchSettingsView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var bridge: CodeSwitchBridge
    @State private var search = ""

    private struct Row: Identifiable {
        let id: String
        let title: String
        let detail: String?
    }

    private var rows: [Row] {
        var names = preferences.hiddenCodeSwitchNames.filter { preferences.hiddenCodeSwitchProviders.contains($0.key) }
        var providerIDs: [String: String] = [:]
        for id in preferences.hiddenCodeSwitchProviders where names[id] == nil {
            names[id] = String(localized: "Unavailable provider")
        }
        for snapshot in bridge.bindings.values.map(\.snapshot) + bridge.snapshots {
            names[snapshot.id] = snapshot.displayName + " · " + (snapshot.linked?.platform ?? "Code Switch R")
            providerIDs[snapshot.id] = snapshot.linked?.provider.providerId
        }
        let counts = names.values.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        return names.map { Row(id: $0.key, title: $0.value,
                              detail: counts[$0.value, default: 0] > 1 ? providerIDs[$0.key] : nil) }
            .filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }
            .sorted { $0.title == $1.title ? $0.id < $1.id : $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        let displayedRows = rows
        Form {
            Section {
                Toggle("Code Switch R integration", isOn: $preferences.codeSwitchEnabled)
                Picker("Show providers", selection: $preferences.codeSwitchDisplayMode) {
                    ForEach(CodeSwitchDisplayMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                .disabled(!preferences.codeSwitchEnabled)
                Text("Enabled providers have proxy hosting and their provider switch turned on, including hidden platforms.")
                    .font(.caption).foregroundStyle(.secondary)
                Text(bridge.connection.title).font(.caption).foregroundStyle(.secondary)
            }
            Section {
                TextField("Search providers", text: $search)
                if displayedRows.isEmpty {
                    Text("Providers appear here when received from Code Switch R.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(displayedRows) { row in
                            Toggle(isOn: Binding(get: { !preferences.hiddenCodeSwitchProviders.contains(row.id) }, set: { visible in
                                if visible {
                                    preferences.hiddenCodeSwitchProviders.remove(row.id)
                                    preferences.hiddenCodeSwitchNames.removeValue(forKey: row.id)
                                } else {
                                    preferences.hiddenCodeSwitchNames[row.id] = row.title
                                    preferences.hiddenCodeSwitchProviders.insert(row.id)
                                }
                            })) {
                                VStack(alignment: .leading) {
                                    Text(row.title).lineLimit(2).help(row.title)
                                    if let detail = row.detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                        }
                    }
                }
                if !preferences.hiddenCodeSwitchProviders.isEmpty {
                    Button("Show all providers") {
                        preferences.hiddenCodeSwitchProviders = []
                        preferences.hiddenCodeSwitchNames = [:]
                    }
                }
            } header: {
                Text("Provider visibility")
            } footer: {
                Text("Hidden providers and their session activity stay out of the notch. This does not change Code Switch R settings.")
            }
        }
    }
}
