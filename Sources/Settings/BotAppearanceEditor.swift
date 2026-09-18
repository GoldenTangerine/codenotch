/**
 @name: 机器人外观与动画
 @Descripttion: 管理机器人显示配置、预览与按可见性运行的动画。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-18 10:21:17
 @LastEditTime: 2026-09-18 10:21:17
 @FilePath: Sources/Settings/BotAppearanceEditor.swift
 */
import SwiftUI

struct BotAppearanceFields: View {
    @Binding var appearance: BotAppearance
    let providerID: String
    let icon: ProviderIcon?
    var glyph: ProviderGlyph = .third

    var body: some View {
        Toggle("Show robot", isOn: $appearance.enabled)
        if appearance.enabled {
            HStack {
                Spacer()
                Group {
                    if BotMarkLibrary.available != nil {
                        BotMarkView(presentation: BotPresentation(
                            id: providerID, brand: icon?.value ?? glyph.rawValue, appearance: appearance))
                    } else {
                        QueryIconView(icon: icon, fallback: glyph, size: 40, onDarkBackground: true)
                    }
                }
                .frame(width: 64, height: 64)
                .padding(8)
                .background(Circle().fill(Color.black))
                .accessibilityLabel(Text("Robot preview"))
                Spacer()
            }
            Picker("Bot personality", selection: Binding(
                get: { appearance.personality ?? "" }, set: { appearance.personality = $0.isEmpty ? nil : $0 })) {
                Text("Automatic").tag("")
                ForEach(BotMarkPersona.allCases) { Text($0.title).tag($0.rawValue) }
            }
            Picker("Bot shape", selection: $appearance.shape) {
                ForEach(BotMarkBody.allCases) { Text($0.title).tag($0.rawValue) }
            }
            Picker("Bot colour", selection: Binding(
                get: { appearance.rgb != nil },
                set: { appearance.rgb = $0 ? BotAppearance.rgbValue(appearance.color(
                    for: providerID, brand: icon?.value ?? glyph.rawValue)) : nil })) {
                Text("Automatic").tag(false)
                Text("Custom colour").tag(true)
            }
            if appearance.rgb != nil {
                ColorPicker("Custom colour", selection: Binding(
                    get: { appearance.color(for: providerID, brand: icon?.value ?? glyph.rawValue) },
                    set: { appearance.rgb = BotAppearance.rgbValue($0) }), supportsOpacity: false)
            }
        }
    }
}

struct BotAppearanceEditor: View {
    @ObservedObject var preferences: Preferences
    let providerID: String
    let name: String
    let icon: ProviderIcon?
    let glyph: ProviderGlyph
    @Environment(\.dismiss) private var dismiss
    @State private var appearance = BotAppearance()

    init(preferences: Preferences, providerID: String, name: String,
         icon: ProviderIcon? = nil, glyph: ProviderGlyph = .third) {
        self.preferences = preferences
        self.providerID = providerID
        self.name = name
        self.icon = icon
        self.glyph = glyph
        _appearance = State(initialValue: preferences.botAppearance(for: providerID))
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(name).font(.headline).padding()
            Form {
                Section("Appearance") {
                    BotAppearanceFields(appearance: $appearance, providerID: providerID, icon: icon, glyph: glyph)
                }
            }.formStyle(.grouped)
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    preferences.setBotAppearance(appearance, for: providerID)
                    dismiss()
                }.keyboardShortcut(.defaultAction)
            }.padding()
        }.frame(width: 420, height: 430)
    }
}
