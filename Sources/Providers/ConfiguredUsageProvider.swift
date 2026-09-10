/**
 @name: 可配置查询供应商
 @Descripttion: 按条目选择自动查询、独立手动凭据或脚本查询。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-08 14:56:06
 @LastEditTime: 2026-09-08 14:56:06
 @FilePath: Sources/Providers/ConfiguredUsageProvider.swift
 */
import Foundation

final class ConfiguredUsageProvider: UsageProvider {
    let entry: QueryEntry
    private let automatic: UsageProvider?
    private let secrets: QuerySecretStorage
    var id: String { entry.id }
    var displayName: String { entry.name }
    var glyph: ProviderGlyph { ProviderGlyph(rawValue: entry.icon.value) ?? .third }

    init(entry: QueryEntry, automatic: UsageProvider?, secrets: QuerySecretStorage) {
        self.entry = entry
        self.automatic = automatic
        self.secrets = secrets
    }

    var signInRoute: SignInRoute {
        entry.usesLocalAccount ? automatic?.signInRoute ?? .guidance(String(localized: "Configure a local provider."))
            : .guidance(String(localized: "Update this provider's credentials in Settings."))
    }

    func account() -> ProviderAccount? { entry.usesLocalAccount ? automatic?.account() : nil }
    func signOut() async { if entry.usesLocalAccount { await automatic?.signOut() } }
    func presentSignIn() { if entry.usesLocalAccount { automatic?.presentSignIn() } }
    func forgetCachedCredential() { if entry.usesLocalAccount { automatic?.forgetCachedCredential() } }

    func decorate(_ snapshot: ProviderSnapshot) -> ProviderSnapshot {
        let nativeHeadline = ["claude": "session", "cursor": CursorUsage.headlineID(in: snapshot.windows), "glm": "session",
                              "grok": "credits", "opencode": "rolling"][ManualNativeQuery.kind(entry.nativeID)]
        let defaultHeadline = entry.usesLocalAccount ? snapshot.headlineID ?? nativeHeadline ?? snapshot.windows.first?.id
            : entry.template == .native ? nativeHeadline ?? snapshot.windows.first?.id : snapshot.windows.first?.id
        return ProviderSnapshot(id: id, displayName: displayName, glyph: glyph, fidelity: snapshot.fidelity,
            status: snapshot.status, windows: snapshot.windows,
            headlineID: entry.headlineID ?? defaultHeadline,
            block: snapshot.block, icon: entry.icon, manualQuery: !entry.usesLocalAccount,
            queryFailure: snapshot.queryFailure, queryRetryAfter: snapshot.queryRetryAfter)
    }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        try entry.validate()
        return try await QueryDeadline.run(seconds: entry.timeout) { [self] in
            try Task.checkCancellation()
            if entry.usesLocalAccount {
                guard let automatic else { throw QueryError.invalid("The local provider is unavailable.") }
                return decorate(try await automatic.fetchSnapshot())
            }
            // Credential APIs may block before any network request starts.
            // Include that time and stop a late read from launching a new query.
            let credentials = try secrets.load(entry.credentialReference)
            try Task.checkCancellation()
            return try await fetchManual(credentials)
        }
    }

    func fetchManual(_ credentials: QuerySecrets) async throws -> ProviderSnapshot {
        let windows: [LimitWindow]
        if entry.template == .native {
            let draft = entry
            windows = try await QueryDeadline.run(seconds: entry.timeout) {
                try await ManualNativeQuery.windows(entry: draft, secrets: credentials)
            }
        } else {
            var variables = credentials.variables
            variables["baseUrl"] = entry.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            windows = try await QueryScriptRunner().run(code: entry.code, variables: variables, timeout: entry.timeout)
        }
        guard !windows.isEmpty else { throw QueryError.invalid("The provider returned no quota items.") }
        let fidelity: Fidelity = entry.template == .native
            || (entry.template != .custom && entry.template != .general && entry.code == entry.template.code)
            ? .official : .derived
        return decorate(ProviderSnapshot(id: id, displayName: displayName, glyph: glyph,
            fidelity: fidelity, status: .ok, windows: windows, headlineID: windows.first?.id))
    }
}

enum ManualNativeQuery {
    static let options: [(id: String, name: String)] = [
        ("claude", "Claude"), ("codex", "Codex"), ("cursor", "Cursor"),
        ("gemini", "Antigravity"), ("glm", "GLM"), ("grok", "Grok"), ("opencode", "OpenCode")
    ]

    static func kind(_ id: String) -> String { ClaudeProfile.isClaude(providerID: id) ? "claude" : id }

    static func request(entry: QueryEntry, secrets: QuerySecrets) throws -> URLRequest {
        let kind = kind(entry.nativeID)
        let endpoint: String
        var headers: [String: String] = [:]
        var method = "GET"
        var body: Any?
        func require(_ value: String) throws -> String {
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw UsageProviderError.needsAuth }
            return value
        }
        switch kind {
        case "claude":
            endpoint = "https://api.anthropic.com/api/oauth/usage"
            headers["Authorization"] = "Bearer \(try require(secrets.accessToken))"
            headers["anthropic-beta"] = "oauth-2025-04-20"
        case "codex":
            endpoint = "https://chatgpt.com/backend-api/wham/usage"
            headers["Authorization"] = "Bearer \(try require(secrets.accessToken))"
            if !secrets.accountID.isEmpty { headers["ChatGPT-Account-Id"] = secrets.accountID }
        case "cursor":
            endpoint = "https://cursor.com/api/usage-summary"
            headers["Cookie"] = try require(secrets.cookie)
        case "gemini":
            endpoint = "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary"
            headers["Authorization"] = "Bearer \(try require(secrets.accessToken))"
            method = "POST"
            body = [String: String]()
        case "glm":
            let base = entry.baseURL.isEmpty ? "https://open.bigmodel.cn" : entry.baseURL
            endpoint = base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/monitor/usage/quota/limit"
            headers["Authorization"] = try require(secrets.apiKey)
        case "grok":
            endpoint = "https://cli-chat-proxy.grok.com/v1/billing?format=credits"
            headers["Authorization"] = "Bearer \(try require(secrets.accessToken))"
            headers["X-XAI-Token-Auth"] = "xai-grok-cli"
        case "opencode":
            endpoint = OpenCodeUsage.endpoint.absoluteString
            headers["Authorization"] = "Bearer \(try require(secrets.apiKey))"
        default: throw QueryError.invalid("This provider requires a custom query script.")
        }
        var object: [String: Any] = ["url": endpoint, "method": method, "headers": headers]
        object["body"] = body
        return try QueryHTTPClient.request(object, timeout: entry.timeout)
    }

    static func windows(entry: QueryEntry, secrets: QuerySecrets) async throws -> [LimitWindow] {
        let data = try await QueryHTTPClient.shared.data(for: request(entry: entry, secrets: secrets))
        return try parse(data, nativeID: entry.nativeID)
    }

    static func parse(_ data: Data, nativeID: String) throws -> [LimitWindow] {
        let text = String(data: data, encoding: .utf8) ?? ""
        switch kind(nativeID) {
        case "claude":
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            decoder.dateDecodingStrategy = .custom { decoder in
                let text = try decoder.singleValueContainer().decode(String.self)
                guard let date = QueryResultParser.parseDate(text) else { throw QueryError.invalid("Invalid reset date.") }
                return date
            }
            return try decoder.decode(UsageResponse.self, from: data).limitWindows()
        case "codex": return try CodexUsage.windows(from: data)
        case "cursor": return try CursorUsage.windows(fromJSON: text)
        case "glm": return try GLMUsage.parse(data).windows
        case "grok": return try GrokUsage.windows(creditsJSON: text)
        case "opencode": return try OpenCodeUsage.windows(fromJSON: text)
        case "gemini": return AntigravityProvider.windows(in: data)
        default: throw QueryError.invalid("Unsupported built-in query.")
        }
    }
}
