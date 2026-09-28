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
    // Fixed palettes also occur without a "-color" suffix, including grayscale artwork.
    private static let originalColorIcons: Set<String> = [
        "adobe-color", "adobefirefly-color", "ai21-brand-color", "ai302-color", "ai360-color",
        "aihubmix-color", "aimass-color", "aionlabs-color", "akashchat-color", "alibaba-brand-color",
        "alibaba-color", "alibabacloud-color", "antgroup-brand-color", "antgroup-color", "anyscale-color",
        "assemblyai-color", "automatic-color", "aws-brand-color", "aws-color", "aya-color",
        "azure-color", "azureai-color", "baichuan-color", "baidu-brand-color", "baidu-color",
        "baiducloud-color", "bailian-color", "bedrock-color", "bilibili-color", "bing-color",
        "burncloud-color", "bytedance-brand-color", "bytedance-color", "centml-brand-color", "centml-color",
        "cerebras-brand-color", "cerebras-color", "chatglm-color", "civitai-color", "civitai-text-color",
        "claude-color", "cloudflare-color", "codegeex-color", "cogvideo-color",
        "cogview-color", "cohere-color", "colab-color", "cometapi-color",
        "comfyui-color", "commanda-color", "copilot-color", "copilotkit-color", "coqui-color",
        "crewai-brand-color", "crewai-color", "crusoe-color", "dalle-color",
        "dbrx-brand-color", "dbrx-color", "deepinfra-color", "deepl-color", "deepmind-color",
        "deepseek-color", "dify-color", "doc2x-color", "docsearch-color", "doubao-color",
        "exa-color", "fal-color", "fastgpt-color", "featherless-color", "figma-color",
        "fireworks-color", "gemini-color", "gemma-color", "glmv-color", "google-brand-color",
        "google-color", "googlecloud-brand-color", "googlecloud-color", "gradio-color", "greptile-color",
        "hailuo-color", "higress-color", "huawei-color", "huaweicloud-color", "huggingface-color",
        "hunyuan-color", "hyperbolic-color", "iflytekcloud-color", "infermatic-color", "infinigence-color",
        "internlm-color", "jimeng-color", "kimi-color", "kling-color", "kluster-color",
        "kolors-color", "kwaipilot-color", "langchain-color", "langfuse-color", "langgraph-color",
        "langsmith-color", "leptonai-color", "lg-color", "livekit-color", "llamaindex-color",
        "llava-color", "lobehub-color", "lobehub", "longcat-color", "lovable-color",
        "luma-color", "make-color", "mcpso-color", "meta-brand-color", "meta-color",
        "metaai-color", "microsoft-color", "minimax-color", "mistral-color", "modelscope-color",
        "monica-color", "myshell-color", "n8n-color", "newapi-color", "nova-color",
        "novita-color", "nplcloud-color", "nvidia-color", "openchat-color", "palm-color",
        "perplexity-color", "phidata-color", "pixverse-color", "player2-color", "poe-color",
        "ppio-color", "pydanticai-color", "qingyan-color", "qiniu-color", "qwen-color",
        "replit-color", "rsshub-color", "rwkv-color", "sambanova-color",
        "search1api-color", "sensenova-brand-color", "sensenova-color", "siliconcloud-color", "skywork-color",
        "smithery-color", "snowflake-color", "sophnet-color", "sora-color", "spark-color",
        "stability-brand-color", "stability-color", "statecloud-color", "stepfun-color", "straico-color",
        "submodel-color", "targon-color", "tavily-color", "tencent-brand-color", "tencent-color",
        "tencentcloud-color", "tiangong-color", "tii-color", "together-brand-color", "together-color",
        "trae-color", "tripo-color", "udio-color", "unstructured-color", "upstage-color",
        "vertexai-color", "vidu-color", "vllm-color", "volcengine-color", "voyage-color",
        "wenxin-color", "workersai-color", "xinference-color", "xuanyuan-color", "yi-color",
        "yuanbao-color", "zapier-color", "zeabur-color", "zhipu-color",
    ]
    private static let images = NSCache<NSString, NSImage>()
    static let prefix = "code-switch:"
    static let libraryPrefix = "lobe:"
    static let libraryIcons = libraryIconNames()

    static func libraryIconNames(bundle: Bundle = .main) -> [String] {
        guard let directory = bundle.url(forResource: "CodeSwitchIcons", withExtension: "bundle")?
            .appendingPathComponent("SVG"),
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == "svg" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private static func imageKey(_ value: String) -> String? {
        if value.hasPrefix(prefix) { return resourceKey(String(value.dropFirst(prefix.count))) }
        guard value.hasPrefix(libraryPrefix) else { return nil }
        let key = String(value.dropFirst(libraryPrefix.count))
        guard !key.isEmpty, key.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }) else { return nil }
        return key
    }

    static func resourceKey(_ value: String) -> String? {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty, key.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }) else { return nil }
        if key == "volcengine" { return "doubao-color" }
        return colorBrands.contains(key) ? key + "-color" : key
    }

    static func isKimi(_ value: String) -> Bool {
        imageKey(value) == "kimi-color"
    }

    static func image(_ value: String, bundle: Bundle = .main, useLightVariant: Bool = false) -> NSImage? {
        guard let key = imageKey(value),
              let directory = bundle.url(forResource: "CodeSwitchIcons", withExtension: "bundle") else { return nil }
        let resource = key == "kimi-color" && useLightVariant ? "kimi-color-light" : key
        // Keep runtime rendering on the existing PNG path; SVGs are library sources.
        // Every bundled SVG has a matching PNG for display.
        let url = directory.appendingPathComponent(resource).appendingPathExtension("png")
        let cacheKey = url.path as NSString
        if let image = images.object(forKey: cacheKey) { return image }
        guard let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = !originalColorIcons.contains(key)
        images.setObject(image, forKey: cacheKey)
        return image
    }
}
