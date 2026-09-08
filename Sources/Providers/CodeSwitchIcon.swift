/**
 @name: 联动品牌图标
 @Descripttion: 从随应用发布的 Lobe 图标资源包中读取托盘品牌图标。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-08 17:38:00
 @LastEditTime: 2026-09-08 17:38:00
 @FilePath: Sources/Providers/CodeSwitchIcon.swift
 */
import AppKit

enum CodeSwitchIcon {
    private static let colorBrands: Set<String> = [
        "claude", "gemini", "deepseek", "mistral", "meta", "cohere", "bedrock",
        "azure", "together", "nvidia", "zhipu", "minimax", "qwen", "fireworks",
        "perplexity", "baichuan", "sensenova", "spark", "hunyuan", "wenxin",
        "gemma", "internlm", "yi", "stepfun", "kimi"
    ]
    private static let images = NSCache<NSString, NSImage>()
    static let prefix = "code-switch:"

    static func resourceKey(_ value: String) -> String? {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty, key.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }) else { return nil }
        if key == "volcengine" { return "doubao-color" }
        return colorBrands.contains(key) ? key + "-color" : key
    }

    static func image(_ value: String, bundle: Bundle = .main) -> NSImage? {
        guard value.hasPrefix(prefix), let key = resourceKey(String(value.dropFirst(prefix.count))),
              let directory = bundle.url(forResource: "CodeSwitchIcons", withExtension: "bundle") else { return nil }
        let url = directory.appendingPathComponent(key).appendingPathExtension("png")
        let cacheKey = url.path as NSString
        if let image = images.object(forKey: cacheKey) { return image }
        guard let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = !key.hasSuffix("-color")
        images.setObject(image, forKey: cacheKey)
        return image
    }
}
