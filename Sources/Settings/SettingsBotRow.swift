/**
 @name: 设置列表机器人
 @Descripttion: 在账号和供应商列表中展示实时机器人与外观设置入口。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-22 15:36:49
 @LastEditTime: 2026-09-22 15:36:49
 @FilePath: Sources/Settings/SettingsBotRow.swift
 */
import SwiftUI

struct SettingsBotContext {
    let model: NotchViewModel
    let store: UsageStore
}

private struct SettingsBotContextKey: EnvironmentKey {
    static let defaultValue: SettingsBotContext? = nil
}

extension EnvironmentValues {
    var settingsBotContext: SettingsBotContext? {
        get { self[SettingsBotContextKey.self] }
        set { self[SettingsBotContextKey.self] = newValue }
    }
}

enum SettingsBotSource {
    case account
    case linked(ProviderSnapshot?)

    func snapshot(for id: String, in snapshots: @autoclosure () -> [ProviderSnapshot],
                  fallback: @autoclosure () -> [ProviderSnapshot] = []) -> ProviderSnapshot? {
        switch self {
        case .account: return snapshots().first { $0.id == id } ?? fallback().first { $0.id == id }
        // 已失去同步的行不能从缓存中恢复过期的工作或额度状态。
        case .linked(let snapshot): return snapshot
        }
    }
}

struct SettingsBotRow: View {
    @ObservedObject var preferences: Preferences
    let providerID: String
    var appearanceID: String? = nil
    let name: String
    var icon: ProviderIcon? = nil
    var glyph: ProviderGlyph = .third
    var source: SettingsBotSource = .account
    var compact = false
    @Environment(\.settingsBotContext) private var context
    @State private var editingAppearance = false

    private var configurationID: String { appearanceID ?? providerID }

    var body: some View {
        let appearance = preferences.botAppearance(for: configurationID)
        HStack(spacing: 8) {
            if appearance.enabled {
                Group {
                    if BotMarkLibrary.available == nil {
                        QueryIconView(icon: icon, fallback: glyph, size: 24)
                    } else if let context {
                        SettingsBotLivePreview(model: context.model, store: context.store,
                            providerID: providerID, configurationID: configurationID,
                            brand: icon?.value ?? glyph.rawValue, appearance: appearance, source: source)
                    } else {
                        BotMarkView(presentation: BotPresentation(id: configurationID,
                            brand: icon?.value ?? glyph.rawValue, appearance: appearance))
                    }
                }
                .frame(width: 24, height: 24)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            } else if compact {
                Color.clear.frame(width: 24, height: 24).accessibilityHidden(true)
            }
            Button { editingAppearance = true } label: {
                if compact {
                    Image(systemName: "paintpalette").frame(width: 24, height: 28)
                } else {
                    Label("Appearance", systemImage: "paintpalette")
                }
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .help("Appearance")
            .accessibilityLabel(Text("Appearance"))
        }
        .sheet(isPresented: $editingAppearance) {
            BotAppearanceEditor(preferences: preferences, providerID: configurationID,
                                name: name, icon: icon, glyph: glyph)
        }
    }

    @MainActor
    static func presentation(model: NotchViewModel, snapshot: ProviderSnapshot?,
                             configurationID: String, brand: String,
                             appearance: BotAppearance, providerID: String? = nil) -> BotPresentation? {
        guard appearance.enabled else { return nil }
        guard let snapshot else {
            let id = providerID ?? configurationID
            let direct = model.sessions[id] ?? []
            let sourceID = model.activitySourceIDs?[id] ?? id
            let activity = ActivitySummary(sessions: direct.isEmpty ? model.sessions[sourceID] ?? [] : direct)?.state
            // 无额度快照不推断耗尽或无读数睡眠，仍采用真实会话和刷新状态。
            return BotPresentation(id: configurationID, brand: brand, appearance: appearance,
                mood: BotPresentation.mood(activity: activity,
                    refreshing: model.refreshing.contains(id) || model.refreshing.contains(configurationID),
                    spent: false, hasReading: true),
                waiting: activity == .waiting,
                event: model.botEvents[id] ?? model.botEvents[configurationID],
                lastActivity: model.botLastActivity, globallyBusy: model.botGloballyBusy)
        }
        guard var result = model.botPresentation(for: snapshot, active: true,
                                                appearanceOverride: appearance) else { return nil }
        // 列表使用独立动画实例和本地鼠标范围，不继承悬浮窗的朝向或展开状态。
        result.id = configurationID
        result.gaze = .ahead
        result.gazeBias = 0
        result.pointerRegion = nil
        return result
    }
}

private struct SettingsBotLivePreview: View {
    @ObservedObject var model: NotchViewModel
    let store: UsageStore
    let providerID: String
    let configurationID: String
    let brand: String
    let appearance: BotAppearance
    let source: SettingsBotSource

    var body: some View {
        switch source {
        case .account:
            SettingsBotAccountSnapshot(store: store, providerID: providerID) { snapshot in
                preview(snapshot: snapshot)
            }
        case .linked(let snapshot):
            preview(snapshot: snapshot)
        }
    }

    @ViewBuilder private func preview(snapshot: ProviderSnapshot?) -> some View {
        if let presentation = SettingsBotRow.presentation(model: model,
            snapshot: snapshot, configurationID: configurationID, brand: brand,
            appearance: appearance, providerID: providerID) {
            BotMarkView(presentation: presentation)
        }
    }
}

// 只有本地账号需要订阅 UsageStore；联动行直接接收页面传入的当前快照。
private struct SettingsBotAccountSnapshot<Content: View>: View {
    @ObservedObject var store: UsageStore
    let providerID: String
    let content: (ProviderSnapshot?) -> Content

    var body: some View {
        content(SettingsBotSource.account.snapshot(for: providerID,
            in: store.snapshots, fallback: store.notchSnapshots))
    }
}
