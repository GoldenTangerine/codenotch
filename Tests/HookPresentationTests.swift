/**
 @name: Hooks 界面回归测试
 @Descripttion: 验证多供应商等待优先级和各屏幕边缘的静态渲染。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-09 12:30:00
 @LastEditTime: 2026-09-09 12:30:00
 @FilePath: Tests/HookPresentationTests.swift
 */
import SwiftUI
import Testing
@testable import Codenotch

@Suite @MainActor struct HookPresentationTests {
    private func session(_ id: String, _ state: AgentSession.State) -> AgentSession {
        AgentSession(id: id, name: id, detail: "Codex CLI", state: state, waitingFor: nil, since: Date())
    }

    @Test func waitingWinsOverSimultaneousSupplierRequests() {
        let provider = CodeSwitchProvider(providerId: "42", providerName: "Supplier", icon: "openai", activeRequests: 2,
                                          status: "active", loading: false, updatedAt: 0, quotas: [], stats: nil)
        let platform = CodeSwitchPlatform(platform: "codex", name: "Codex", icon: "openai", error: false, providers: [provider])
        let snapshot = provider.snapshot(platform: platform)
        let model = NotchViewModel()
        model.snapshots = [snapshot]
        model.sessions[snapshot.id] = [session("running", .busy), session("question", .waiting)]
        #expect(model.activity(for: snapshot.id)?.state == .waiting)
        model.sessions[snapshot.id] = [session("idle", .idle)]
        #expect(model.activity(for: snapshot.id)?.state == .working)
    }

    @Test func waitingRendersOnEveryEdgeInBothThemes() throws {
        for edge in NotchEdge.allCases {
            for scheme in [ColorScheme.light, .dark] {
                let model = NotchViewModel()
                model.edge = edge
                model.isExpanded = true
                let snapshot = ProviderSnapshot(id: "codex", displayName: "Codex CLI", glyph: .openai, fidelity: .derived,
                                                status: .ok, windows: [], headlineID: nil)
                model.snapshots = [snapshot]
                model.sessions["codex"] = [session("question", .waiting)]
                let size = model.panelSize
                let renderer = ImageRenderer(content: NotchRootView(model: model)
                    .environment(\.colorScheme, scheme)
                    .frame(width: size.width, height: size.height))
                let image = try #require(renderer.cgImage)
                let rep = NSBitmapImageRep(cgImage: image)
                var amberPixels = 0
                for x in 0..<rep.pixelsWide {
                    for y in 0..<rep.pixelsHigh {
                        if let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                           color.alphaComponent > 0.5, color.redComponent > 0.8,
                           (0.4...0.85).contains(color.greenComponent), color.blueComponent < 0.5 {
                            amberPixels += 1
                        }
                    }
                }
                #expect(amberPixels > 5)
            }
        }
    }
}
