// @name: 更新包签名验证
// @Descripttion: 使用应用内嵌公钥验证更新包的 Ed25519 签名，阻止错误密钥发布。
// @version: 1.0.0
// @Author: sm
// @Date: 2026-09-11 15:24:24
// @LastEditTime: 2026-09-11 15:24:24
// @FilePath: Scripts/verify-update.swift
import CryptoKit
import Foundation

do {
    guard CommandLine.arguments.count == 4,
          let signature = Data(base64Encoded: CommandLine.arguments[2]),
          let publicKey = Data(base64Encoded: CommandLine.arguments[3]) else {
        throw NSError(domain: "UpdateSignature", code: 1)
    }
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
    let archive = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]), options: .mappedIfSafe)
    guard key.isValidSignature(signature, for: archive) else {
        throw NSError(domain: "UpdateSignature", code: 2)
    }
    print("Update signature matches the app's SUPublicEDKey.")
} catch {
    FileHandle.standardError.write(Data("Update signature verification failed. Check SPARKLE_EDDSA_KEY against SUPublicEDKey and regenerate the appcast.\n".utf8))
    exit(1)
}
