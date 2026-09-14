/**
 @name: MiniMax 网站脚本测试
 @Descripttion: 执行 MiniMax 网页额度与登录脚本以验证业务状态映射。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-14 21:09:00
 @LastEditTime: 2026-09-14 21:09:00
 @FilePath: Tests/MiniMaxSiteScriptTests.swift
 */
import Foundation
import JavaScriptCore
import Testing
@testable import Codenotch

@Suite @MainActor struct MiniMaxSiteScriptTests {
    private struct ScriptResult {
        let response: [String: Any]
        let requestPath: String
        let credentials: String
    }

    private func run(_ script: String, status: Int, body: String) throws -> ScriptResult {
        let context = try #require(JSContext())
        context.setObject(status, forKeyedSubscript: "mockStatus" as NSString)
        context.setObject(body, forKeyedSubscript: "mockBody" as NSString)
        context.evaluateScript("""
        var requestPath = null;
        var requestCredentials = null;
        var scriptResult = null;
        const localStorage = { getItem: () => null };
        const fetch = async (url, options) => {
            requestPath = url;
            requestCredentials = options.credentials;
            return { status: mockStatus, text: async () => mockBody };
        };
        async function execute() {
            \(script)
        }
        execute().then(value => { scriptResult = value; }, error => {
            scriptResult = JSON.stringify({ error: String(error) });
        });
        """)
        #expect(context.exception == nil)

        var result: String?
        for _ in 0..<10 {
            if let value = context.evaluateScript("scriptResult"),
               !value.isNull, !value.isUndefined {
                result = value.toString()
                break
            }
        }
        let data = try #require(result?.data(using: .utf8))
        let response = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return ScriptResult(
            response: response,
            requestPath: try #require(context.evaluateScript("requestPath")?.toString()),
            credentials: try #require(context.evaluateScript("requestCredentials")?.toString())
        )
    }

    @Test(arguments: MiniMaxRegion.allCases)
    func webResponsesAndLoginProbesMapBusinessStatuses(region: MiniMaxRegion) throws {
        let site = Sites.minimax(region: region)
        let probe = try #require(site.authProbeScript)
        let expectedPath = region == .international
            ? region.remainsURL.path : region.remainsURL.absoluteString
        let expectedCredentials = region == .international ? "same-origin" : "include"

        let responses: [(httpStatus: Int, body: String, status: Int, signedIn: Bool)] = [
            (200, #"{"base_resp":{"status_code":0}}"#, 200, true),
            (200, #"{"base_resp":{"status_code":1004}}"#, 401, false),
            (200, #"{"base_resp":{"status_code":0},"data":{"base_resp":{"status_code":1004}}}"#, 401, false),
            (200, #"{"base_resp":{"status_code":2045}}"#, 429, false),
            (200, #"{"base_resp":{"status_code":0},"data":{"base_resp":{"status_code":2045}}}"#, 429, false),
            (200, #"{"base_resp":{"status_code":1004},"data":{"base_resp":{"status_code":2045}}}"#, 429, false),
            (200, #"{"status_code":"401"}"#, 401, false),
            (429, #"{"base_resp":{"status_code":1004}}"#, 429, false),
        ]
        for response in responses {
            let usage = try run(site.script, status: response.httpStatus, body: response.body)
            #expect(usage.response["status"] as? Int == response.status)
            #expect(usage.requestPath == expectedPath)
            #expect(usage.credentials == expectedCredentials)

            let login = try run(probe, status: response.httpStatus, body: response.body)
            #expect(login.response["authenticated"] as? Bool == response.signedIn)
            #expect(login.requestPath == expectedPath)
        }
    }

    @Test func nestedAPIEnvelopeFailuresTakePriorityOverOuterSuccess() {
        let rejected = Data(#"{"base_resp":{"status_code":0},"data":{"base_resp":{"status_code":1004,"status_msg":"invalid API secret key"}}}"#.utf8)
        #expect(MiniMaxProvider.envelopeStatus(in: rejected) == 1004)
        #expect(MiniMaxProvider.isRejectedAPIKey(in: rejected))

        let throttled = Data(#"{"base_resp":{"status_code":1004},"data":{"base_resp":{"status_code":2045}}}"#.utf8)
        #expect(MiniMaxProvider.envelopeStatus(in: throttled) == 2045)
        #expect(MiniMaxProvider.isRateLimited(status: 200, envelope: MiniMaxProvider.envelopeStatus(in: throttled)))
    }
}
