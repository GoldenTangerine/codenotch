/**
 @name: 供应商管理界面
 @Descripttion: 编辑供应商、手动凭据、脚本与独立刷新间隔。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-08 14:56:06
 @LastEditTime: 2026-09-08 14:56:06
 @FilePath: Sources/Settings/QueryManagementView.swift
 */
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct QueryManagementView: View {
    @ObservedObject var catalog: QueryCatalog
    @ObservedObject var store: UsageStore
    @ObservedObject var preferences: Preferences
    @State private var editing: QueryEntry?
    @State private var deleting: QueryEntry?
    @State private var problem: String?
    @State private var drag = DragState()

    var body: some View {
        Section {
            if let problem = problem ?? catalog.problem {
                Text(problem).foregroundStyle(.red).textSelection(.enabled)
            }
            ForEach(catalog.entries) { entry in
                HStack(spacing: 10) {
                    Image(systemName: "line.3.horizontal")
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 28)
                        .contentShape(Rectangle())
                        .onDrag {
                            drag.id = entry.id
                            return NSItemProvider(object: entry.id as NSString)
                        }
                        .help("Drag to reorder")
                    QueryIconView(icon: entry.icon, fallback: .third, size: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.name).lineLimit(1).help(entry.name)
                        Text(detail(entry)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Button {
                        preferences.setAlertsMuted(!preferences.isMutedAlerts(for: entry.id), for: entry.id)
                    } label: {
                        Image(systemName: preferences.isMutedAlerts(for: entry.id) ? "bell.slash" : "bell")
                    }
                    .help(preferences.isMutedAlerts(for: entry.id) ? String(localized: "Unmute alerts") : String(localized: "Mute alerts"))
                    Toggle("Enabled", isOn: Binding(get: { entry.enabled }, set: { catalog.setEnabled($0, id: entry.id) }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                    Button { store.refresh(providerID: entry.id) } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh").disabled(!entry.enabled || store.refreshing.contains(entry.id))
                    Button { editing = entry } label: { Image(systemName: "pencil") }.help("Edit provider")
                    Menu {
                        if entry.usesLocalAccount {
                            Button("Allow access…", systemImage: "key") { store.reauthorize(providerID: entry.id) }
                            Button("Open account source", systemImage: "arrow.up.forward.app") { _ = store.openAccountSource(providerID: entry.id) }
                            Divider()
                        }
                        Button("Delete provider", systemImage: "trash", role: .destructive) { deleting = entry }
                    } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).fixedSize().help("Provider actions")
                }
                .buttonStyle(.borderless)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
                .dropDestination(for: String.self) { ids, _ in
                    defer { drag.id = nil }
                    guard let id = ids.first else { return false }
                    return catalog.move(id, onto: entry.id)
                } isTargeted: { entered in
                    guard entered, let id = drag.id, id != entry.id else { return }
                    withAnimation(.snappy(duration: 0.22)) { _ = catalog.move(id, onto: entry.id) }
                }
            }
            Button("Add provider", systemImage: "plus") { editing = QueryEntry() }
            if catalog.entries.contains(where: { $0.usesLocalAccount && $0.nativeID == "gemini-api" }) {
                TextField("Gemini monthly token budget", value: $preferences.geminiAPIMonthlyTokenBudget,
                          format: .number)
            }
        } header: { Text("Providers") }
        .sheet(item: $editing) { entry in
            QueryEntryEditor(catalog: catalog, initial: entry)
        }
        .alert("Delete provider?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Cancel", role: .cancel) { deleting = nil }
            Button("Delete", role: .destructive) {
                if let deleting {
                    do { try catalog.delete(deleting.id) } catch { problem = error.localizedDescription }
                }
                deleting = nil
            }
        } message: {
            Text("This removes the query, its saved credentials and cached readings.")
        }
    }

    private func detail(_ entry: QueryEntry) -> String {
        if !entry.enabled { return String(localized: "Disabled") }
        if store.refreshing.contains(entry.id) { return String(localized: "Refreshing…") }
        if let snapshot = store.snapshots.first(where: { $0.id == entry.id }) {
            if let failure = snapshot.queryFailure { return failure }
            if snapshot.hasReading { return snapshot.headline?.summary ?? String(localized: "No reading") }
            if let status = snapshot.statusMessage { return status }
        }
        return entry.usesLocalAccount ? String(localized: "Automatic credentials") : String(localized: "Manual credentials")
    }
}

struct QueryEntryEditor: View {
    @ObservedObject var catalog: QueryCatalog
    @Environment(\.dismiss) private var dismiss
    @State private var entry: QueryEntry
    @State private var secrets = QuerySecrets()
    @State private var originalSecrets = QuerySecrets()
    @State private var loadedSecrets = false
    @State private var problem: String?
    @State private var preview: [LimitWindow] = []
    @State private var testing = false
    @State private var testTask: Task<Void, Never>?
    @State private var testVersion = UUID()
    @State private var pendingImage: Data?
    @State private var previewImage: NSImage?

    init(catalog: QueryCatalog, initial: QueryEntry) {
        self.catalog = catalog
        _entry = State(initialValue: initial)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit provider").font(.headline)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }.help("Close")
                    .buttonStyle(.plain)
            }.padding(20)
            Divider()
            Form {
                identity
                query
                Section("Refresh") {
                    Toggle("Automatic refresh", isOn: $entry.schedule.enabled)
                    HStack {
                        TextField("Active (seconds)", value: $entry.schedule.activeSeconds, format: .number)
                        TextField("Idle (seconds)", value: $entry.schedule.idleSeconds, format: .number)
                    }.disabled(!entry.schedule.enabled)
                    TextField("Timeout (seconds)", value: $entry.timeout, format: .number)
                }
                Section("Query result") {
                    if let problem {
                        Text(problem).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                    }
                    Picker("Primary metric", selection: Binding(get: { entry.headlineID ?? "" }, set: { entry.headlineID = $0.isEmpty ? nil : $0 })) {
                        Text("First metric").tag("")
                        if let id = entry.headlineID, !preview.contains(where: { $0.id == id }) { Text(id).tag(id) }
                        ForEach(preview) { Text($0.label).tag($0.id) }
                    }
                    ForEach(preview) { window in
                        LabeledContent(window.label, value: window.summary)
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Button("Test query", systemImage: "play") { test() }.disabled(testing)
                if testing {
                    ProgressView().controlSize(.small)
                    Button { cancelTest() } label: { Image(systemName: "stop.fill") }.help("Cancel query")
                } else if problem != nil {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.red).help(problem ?? "")
                } else if !preview.isEmpty {
                    Image(systemName: "checkmark.circle").foregroundStyle(.green).help("Query succeeded")
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }.keyboardShortcut(.defaultAction)
                    .disabled(entry.mode == .manual && !loadedSecrets)
            }.padding(16)
        }
        .frame(width: 680, height: min(760, (NSScreen.main?.visibleFrame.height ?? 900) - 100))
        .background(Color(nsColor: .windowBackgroundColor))
        .task { loadSecretsIfNeeded() }
        .onChange(of: entry.mode) { _, _ in loadSecretsIfNeeded(); cancelTest() }
        .onChange(of: entry.code) { _, _ in cancelTest() }
        .onChange(of: entry.baseURL) { _, _ in cancelTest() }
        .onChange(of: entry.nativeID) { _, _ in cancelTest() }
        .onChange(of: entry.timeout) { _, _ in cancelTest() }
        .onChange(of: secrets) { _, _ in cancelTest() }
        .onDisappear { cancelTest() }
    }

    private var identity: some View {
        Section("Provider") {
            TextField("Name", text: $entry.name)
            HStack {
                if let previewImage { Image(nsImage: previewImage).resizable().scaledToFit().frame(width: 28, height: 28) }
                else { QueryIconView(icon: entry.icon, fallback: .third, size: 28) }
                Picker("Icon", selection: $entry.icon.kind) {
                    Text("Brand").tag(ProviderIcon.Kind.brand)
                    Text("System symbol").tag(ProviderIcon.Kind.symbol)
                    Text("Local image").tag(ProviderIcon.Kind.image)
                }
                .onChange(of: entry.icon.kind) { _, kind in
                    entry.icon.value = kind == .brand ? "claude" : kind == .symbol ? "server.rack" : ""
                    pendingImage = nil
                    previewImage = nil
                }
            }
            if entry.icon.kind == .brand {
                Picker("Brand icon", selection: $entry.icon.value) {
                    ForEach(ManualNativeQuery.options, id: \.id) { option in
                        let value = option.id == "codex" ? "openai" : option.id
                        HStack { ProviderGlyphView(glyph: ProviderGlyph(rawValue: value) ?? .third, size: 16); Text(option.name) }.tag(value)
                    }
                    Text("Generic").tag("third")
                }
            } else if entry.icon.kind == .symbol {
                Picker("System symbol", selection: $entry.icon.value) {
                    ForEach(QueryIconView.symbols, id: \.self) { symbol in
                        Image(systemName: symbol).tag(symbol)
                    }
                }
            } else {
                Button("Choose image…", systemImage: "photo") { chooseImage() }
            }
        }
    }

    private var query: some View {
        Section("Query") {
            Picker("Credentials", selection: $entry.mode) {
                Text("Automatic").tag(QueryMode.automatic)
                Text("Manual").tag(QueryMode.manual)
            }.pickerStyle(.segmented)
            if entry.mode == .automatic {
                Picker("Local provider", selection: $entry.nativeID) {
                    ForEach(catalog.automaticProviders, id: \.id) { provider in Text(provider.displayName).tag(provider.id) }
                }
                if let provider = catalog.automaticProviders.first(where: { $0.id == entry.nativeID }) {
                    Text(provider.signInRoute.explanation).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Picker("Query method", selection: $entry.template) {
                    ForEach(QueryTemplate.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: entry.template) { _, template in
                    entry.code = template.code
                    if !template.baseURL.isEmpty { entry.baseURL = template.baseURL }
                    preview = []
                    entry.headlineID = nil
                    cancelTest()
                }
                if entry.template == .native {
                    Picker("Built-in provider", selection: $entry.nativeID) {
                        if !ManualNativeQuery.options.contains(where: { $0.id == entry.nativeID }) {
                            Text(entry.nativeID).tag(entry.nativeID)
                        }
                        ForEach(ManualNativeQuery.options, id: \.id) { Text($0.name).tag($0.id) }
                    }
                }
                if entry.template != .native || ManualNativeQuery.kind(entry.nativeID) == "glm" {
                    TextField("Base URL", text: $entry.baseURL)
                }
                credentialFields.disabled(!loadedSecrets)
                if !loadedSecrets { Button("Retry credential access") { loadSecretsIfNeeded() } }
                if entry.template != .native {
                    Text("Query script").font(.subheadline)
                    TextEditor(text: $entry.code)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 160, maxHeight: 240)
                        .border(Color.secondary.opacity(0.25))
                }
            }
        }
    }

    @ViewBuilder private var credentialFields: some View {
        let native = ManualNativeQuery.kind(entry.nativeID)
        let custom = entry.template != .native
        if custom || ["glm", "opencode"].contains(native) { SecureField("API Key", text: $secrets.apiKey) }
        if custom || ["claude", "codex", "gemini", "grok"].contains(native) { SecureField("Access token", text: $secrets.accessToken) }
        if custom || native == "cursor" { SecureField("Cookie", text: $secrets.cookie) }
        if custom || native == "codex" { SecureField("Account ID", text: $secrets.accountID) }
        if custom { SecureField("User ID", text: $secrets.userID) }
    }

    private func loadSecretsIfNeeded() {
        guard entry.mode == .manual, !loadedSecrets else { return }
        do {
            secrets = try catalog.secrets.load(entry.credentialReference)
            originalSecrets = secrets
            loadedSecrets = true
        } catch { problem = error.localizedDescription }
    }

    private func cancelTest() {
        testTask?.cancel()
        testTask = nil
        testVersion = UUID()
        testing = false
        preview = []
    }

    private func test() {
        cancelTest()
        problem = nil
        do { try entry.validate() } catch { problem = error.localizedDescription; return }
        testing = true
        let version = testVersion
        let draft = entry
        let credentials = secrets
        let provider = ConfiguredUsageProvider(entry: draft,
            automatic: catalog.automaticProviders.first { $0.id == draft.nativeID }, secrets: catalog.secrets)
        testTask = Task {
            do {
                let result = draft.mode == .manual
                    ? try await provider.fetchManual(credentials) : try await provider.fetchSnapshot()
                guard !Task.isCancelled, testVersion == version else { return }
                preview = result.windows
            } catch {
                guard !Task.isCancelled, testVersion == version else { return }
                switch error {
                case let error as QueryError: problem = error.localizedDescription
                case UsageProviderError.needsAuth: problem = String(localized: "Check the credentials for this query.")
                case UsageProviderError.rateLimited: problem = String(localized: "Rate limited. Waiting before retrying.")
                case UsageProviderError.badResponse(let status): problem = "HTTP \(status)"
                default: problem = String(localized: "Query failed. Check the credentials, URL and script.")
                }
            }
            testing = false
        }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 5_000_000 else { throw QueryError.invalid("Choose an image smaller than 5 MB.") }
            let data = try Data(contentsOf: url)
            guard let image = NSImage(data: data), image.size.width > 0, image.size.height > 0 else {
                throw QueryError.invalid("The image could not be opened.")
            }
            let rendered = NSImage(size: NSSize(width: 128, height: 128), flipped: false) { rect in
                let scale = min(rect.width / image.size.width, rect.height / image.size.height)
                let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
                image.draw(in: NSRect(x: (rect.width - size.width) / 2, y: (rect.height - size.height) / 2, width: size.width, height: size.height))
                return true
            }
            guard let tiff = rendered.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
                throw QueryError.invalid("The image could not be opened.")
            }
            pendingImage = png
            previewImage = rendered
            problem = nil
        } catch { problem = error.localizedDescription }
    }

    private func save() {
        var writtenImage: URL?
        let oldIcon = entry.icon
        do {
            try entry.validate()
            if let pendingImage {
                let name = UUID().uuidString + ".png"
                try FileManager.default.createDirectory(at: ProviderIcon.directory, withIntermediateDirectories: true)
                let url = ProviderIcon.directory.appendingPathComponent(name)
                try pendingImage.write(to: url, options: .atomic)
                writtenImage = url
                entry.icon.value = name
            }
            try catalog.save(entry, secrets: loadedSecrets && secrets != originalSecrets ? secrets : nil)
            dismiss()
        } catch {
            if let writtenImage { try? FileManager.default.removeItem(at: writtenImage) }
            entry.icon = oldIcon
            problem = error.localizedDescription
        }
    }
}

struct QueryIconView: View {
    let icon: ProviderIcon?
    let fallback: ProviderGlyph
    var size: CGFloat = Design.px(46)
    static let symbols = ["server.rack", "cloud", "cpu", "bolt", "terminal", "creditcard", "building.2", "sparkles"]

    var body: some View {
        Group {
            if let icon, icon.kind == .brand, let image = CodeSwitchIcon.image(icon.value) {
                Image(nsImage: image).resizable().scaledToFit()
            } else if let icon, icon.kind == .symbol {
                Image(systemName: Self.symbols.contains(icon.value) ? icon.value : "server.rack")
                    .resizable().scaledToFit()
            } else if let icon, icon.kind == .image,
                      icon.value == URL(fileURLWithPath: icon.value).lastPathComponent,
                      let image = NSImage(contentsOf: ProviderIcon.directory.appendingPathComponent(icon.value)) {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                ProviderGlyphView(glyph: icon.flatMap { ProviderGlyph(rawValue: $0.value) } ?? fallback, size: size)
            }
        }.frame(width: size, height: size)
    }
}
