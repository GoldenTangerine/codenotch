/**
 @name: 远程 Codex 凭据
 @Descripttion: 通过 SSH 读取远程服务器上的 Codex 登录信息。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-10-15 16:20:00
 @LastEditTime: 2026-10-15 16:20:00
 @FilePath: Sources/Providers/CodexRemoteCredentials.swift
 */
import Foundation

/// The session of a Codex account on another machine, borrowed over SSH.
///
/// Codex files its token at `~/.codex/auth.json` on every platform, so there
/// is no keychain fallback to attempt — one read, judged by the same reader
/// as the local file.
enum CodexRemoteCredentials {
    /// Reads the remote session, expired or not — judging expiry is the
    /// caller's job, exactly as with the local file.
    static func load(from host: RemoteHost, run: RemoteSSH.Runner = RemoteSSH.run) throws -> CodexCredentials.Credential {
        do {
            let file = try run(host, "cat ~/.codex/auth.json")
            if file.exitCode == 0, !file.stdout.isEmpty {
                return try CodexCredentials.load(from: file.stdout)
            }
            if RemoteSSH.isTransportFailure(file) {
                throw RemoteSSH.transportError(destination: host.destination, result: file)
            }
            Log.usage.error("ssh \(host.destination, privacy: .public): no codex auth.json")
            throw UsageProviderError.needsAuth
        } catch is RemoteSSH.TimeoutError {
            throw UsageProviderError.apiError(L10n.t("ssh to \(host.destination) timed out"))
        }
    }
}
