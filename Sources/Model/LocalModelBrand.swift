/**
 @name: 上游同步模块
 @Descripttion: 维护 LocalModelBrand.swift 的项目实现与上游兼容。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-11 15:51:14
 @LastEditTime: 2026-09-11 15:51:14
 @FilePath: Sources/Model/LocalModelBrand.swift
 */
import Foundation

enum LocalModelBrand: String, CaseIterable {
    case qwen, gemma, llama, deepseek, mistral

    var displayName: String {
        switch self {
        case .qwen: return "Qwen"
        case .gemma: return "Gemma"
        case .llama: return "Llama"
        case .deepseek: return "DeepSeek"
        case .mistral: return "Mistral"
        }
    }

    var glyph: ProviderGlyph {
        switch self {
        case .qwen: return .qwen
        case .gemma: return .gemma
        case .llama: return .meta
        case .deepseek: return .deepseek
        case .mistral: return .mistral
        }
    }

    static func detect(modelName: String) -> Self? {
        let name = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased().split(separator: "/").last?
            .split(separator: ":", maxSplits: 1).first.map(String.init) ?? ""
        // Match the model's own name, not an architecture or a word anywhere
        // inside it: DeepSeek's Qwen-based distills still belong to DeepSeek.
        let names: [(Self, [String])] = [
            (.deepseek, ["deepseek"]),
            (.qwen, ["qwen", "qwq", "qvq"]),
            (.gemma, ["gemma", "codegemma", "paligemma", "recurrentgemma",
                      "shieldgemma", "embeddinggemma", "functiongemma", "medgemma"]),
            (.llama, ["llama", "meta-llama", "codellama"]),
            (.mistral, ["mistral", "ministral", "mixtral", "codestral", "devstral", "magistral"])
        ]
        return names.first { _, prefixes in
            prefixes.contains { prefix in
                guard name.hasPrefix(prefix) else { return false }
                guard let next = name.dropFirst(prefix.count).first else { return true }
                return next.isASCII && (next.isNumber || next == "-" || next == "_")
            }
        }?.0
    }
}
