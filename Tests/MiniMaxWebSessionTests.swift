/**
 @name: MiniMax WebSession 测试
 @Descripttion: 验证 MiniMax 区域站点、登录探针与会话数据清理。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-14 17:40:57
 @LastEditTime: 2026-09-14 17:40:57
 @FilePath: Tests/MiniMaxWebSessionTests.swift
 */
import XCTest
@testable import Codenotch

/// MiniMax is signed into from Codenotch's own WKWebView, the same way
/// DeepSeek is. These pin the regional platform origin, the absolute www
/// remains fetch, and the extra host that sign-out has to clear.
@MainActor
final class MiniMaxWebSessionTests: XCTestCase {
    private let signedInKey = "minimax.platform.minimax.io.signedIn"
    private let chinaSignedInKey = "minimax.platform.minimaxi.com.signedIn"
    private let deepSeekSignedInKey = "deepseek.signedIn"
    private var savedSignedIn: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        for key in [signedInKey, chinaSignedInKey, deepSeekSignedInKey] {
            savedSignedIn[key] = UserDefaults.standard.object(forKey: key)
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        for key in [signedInKey, chinaSignedInKey, deepSeekSignedInKey] {
            if let value = savedSignedIn[key] {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        super.tearDown()
    }

    func testInternationalSiteFetchesRemainsFromWwwOrigin() {
        let site = Sites.minimax(region: .international)
        XCTAssertEqual(site.id, "minimax")
        XCTAssertEqual(site.displayName, "MiniMax")
        XCTAssertEqual(site.glyph, .minimax)
        XCTAssertEqual(site.origin, MiniMaxRegion.international.platformOrigin)
        XCTAssertEqual(site.requestOrigin, MiniMaxRegion.international.websiteOrigin)
        XCTAssertEqual(site.fidelity, .derived)
        XCTAssertEqual(site.associatedHosts, ["www.minimax.io"])
        XCTAssertTrue(site.script.contains("fetch('/v1/api/openplatform/coding_plan/remains'"))
        XCTAssertFalse(site.script.contains("fetch(\"/v1/api"))
        XCTAssertFalse(site.script.contains("https://platform.minimax.io/v1/"))
        XCTAssertFalse(site.script.contains("https://api.minimax.io/"))
        XCTAssertFalse(site.script.contains("https://www.minimax.io/v1/"))
        XCTAssertTrue(site.script.contains("credentials: 'same-origin'"))
        let probe = try! XCTUnwrap(site.authProbeScript)
        XCTAssertTrue(probe.contains("fetch('/v1/api/openplatform/coding_plan/remains'"))
        XCTAssertTrue(probe.contains("credentials: 'same-origin'"))
        XCTAssertTrue(site.authFingerprintScript?.contains("localStorage.getItem('access_token')") == true)
    }

    func testChinaSiteFetchesWwwMinimaxiComRemains() {
        let site = Sites.minimax(region: .china)
        XCTAssertEqual(site.id, "minimax")
        XCTAssertEqual(site.origin, MiniMaxRegion.china.platformOrigin)
        XCTAssertNil(site.requestOrigin)
        XCTAssertNil(site.authFingerprintScript)
        XCTAssertEqual(site.fidelity, .derived)
        XCTAssertEqual(site.associatedHosts, ["www.minimaxi.com"])
        XCTAssertTrue(site.script.contains("https://www.minimaxi.com/v1/api/openplatform/coding_plan/remains"))
        XCTAssertFalse(site.script.contains("https://www.minimax.io/"))
        XCTAssertFalse(site.script.contains("https://platform.minimaxi.com/v1/"))
        XCTAssertFalse(site.script.contains("https://api.minimaxi.com/"))
        XCTAssertTrue(site.script.contains("credentials: 'include'"))
        let probe = try! XCTUnwrap(site.authProbeScript)
        XCTAssertTrue(probe.contains("https://www.minimaxi.com/v1/api/openplatform/coding_plan/remains"))
    }

    func testAProbeMeansOpeningTheSheetIsNotYetASignIn() {
        WebSessionProvider(site: Sites.minimax(region: .international)).signInSheetDidOpen()
        XCTAssertFalse(UserDefaults.standard.bool(forKey: signedInKey),
                       "opening the sheet is not a sign-in for a site that can confirm one")
    }

    func testParseUsesTheRemainsWindows() throws {
        let json = """
        { "base_resp": { "status_code": 0 },
          "current_subscribe_title": "Max",
          "model_remains": [
            { "model_name": "general",
              "current_interval_total_count": 1000,
              "current_interval_usage_count": 250,
              "start_time": 1700000000000, "end_time": 1700018000000 } ] }
        """
        let windows = try Sites.minimax(region: .international).parse(json)
        let expected = try MiniMaxUsage.windows(fromJSON: json)
        XCTAssertEqual(windows.map(\.id), expected.map(\.id))
        XCTAssertEqual(windows.first?.usedFraction ?? -1, 0.75, accuracy: 0.0001)
    }

    func testInternationalOriginValidationRejectsContainingHostnames() {
        let origin = Sites.minimax(region: .international).origin
        XCTAssertTrue(WebSessionProvider.matchesOrigin(origin, expected: origin))
        XCTAssertTrue(WebSessionProvider.matchesOrigin(
            URL(string: "HTTPS://PLATFORM.MINIMAX.IO:443/usage"), expected: origin
        ))
        XCTAssertFalse(WebSessionProvider.matchesOrigin(
            MiniMaxRegion.china.platformOrigin, expected: origin
        ))

        for value in [
            "https://platform.minimax.io.attacker.example/",
            "https://attacker-platform.minimax.io/",
            "http://platform.minimax.io/",
            "https://www.minimax.io/",
            "https://platform.minimax.io:444/",
            "https://[::1]/",
            "https:/usage"
        ] {
            let url = URL(string: value)
            XCTAssertNotNil(url, value)
            XCTAssertFalse(WebSessionProvider.matchesOrigin(url, expected: origin), value)
        }
    }

    func testSignedInSessionAppearsAsAnAccountInSettings() {
        UserDefaults.standard.set(true, forKey: signedInKey)
        let international = WebSessionProvider(site: Sites.minimax(region: .international))
        XCTAssertEqual(international.account()?.source, "MiniMax")
        XCTAssertEqual(international.account()?.manageURL?.host, "platform.minimax.io")

        let china = WebSessionProvider(site: Sites.minimax(region: .china))
        XCTAssertNil(china.account(), "the international session is not a China login")
        UserDefaults.standard.set(true, forKey: chinaSignedInKey)
        XCTAssertEqual(china.account()?.manageURL?.host, "platform.minimaxi.com")
    }

    func testApplySwitchesTheRegionalOriginWithoutChangingIdentity() {
        UserDefaults.standard.set(true, forKey: signedInKey)
        let provider = WebSessionProvider(site: Sites.minimax(region: .international))
        XCTAssertEqual(provider.id, "minimax")
        XCTAssertEqual(provider.displayName, "MiniMax")
        XCTAssertEqual(provider.account()?.manageURL?.host, "platform.minimax.io")

        provider.apply(site: Sites.minimax(region: .china))
        XCTAssertEqual(provider.id, "minimax")
        XCTAssertEqual(provider.displayName, "MiniMax")
        XCTAssertNil(provider.account(), "changing regions must not reuse the previous login")
        UserDefaults.standard.set(true, forKey: chinaSignedInKey)
        XCTAssertEqual(provider.account()?.manageURL?.host, "platform.minimaxi.com")
        provider.apply(site: Sites.deepSeek)
        XCTAssertEqual(provider.id, "minimax")
        XCTAssertEqual(provider.displayName, "MiniMax")
        XCTAssertNotNil(provider.account(),
                        "MiniMax's signed-in flag must not follow DeepSeek's site id")
        XCTAssertEqual(provider.account()?.manageURL?.host, "platform.minimaxi.com",
                       "a different site id must not replace MiniMax")
        XCTAssertFalse(UserDefaults.standard.bool(forKey: deepSeekSignedInKey))
        XCTAssertTrue(UserDefaults.standard.bool(forKey: signedInKey))
        provider.apply(site: Sites.minimax(region: .international))
        XCTAssertEqual(provider.account()?.manageURL?.host, "platform.minimax.io",
                       "the previous region remains signed in when switching back")
    }

    func testDeepSeekAndPerplexityDoNotPickUpMiniMaxHosts() {
        XCTAssertTrue(Sites.deepSeek.associatedHosts.isEmpty)
        XCTAssertTrue(Sites.perplexity.associatedHosts.isEmpty)
        XCTAssertNil(Sites.perplexity.authProbeScript)
        XCTAssertNotNil(Sites.deepSeek.authProbeScript)
        XCTAssertNil(Sites.deepSeek.requestOrigin)
        XCTAssertEqual(WebSessionProvider.websiteDataHosts(for: Sites.deepSeek),
                       ["platform.deepseek.com"])
        XCTAssertEqual(WebSessionProvider.websiteDataHosts(for: Sites.perplexity),
                       ["www.perplexity.ai"])
        XCTAssertFalse(WebSessionProvider.websiteDataHosts(for: Sites.deepSeek)
            .contains("www.minimax.io"))
    }

    func testDeepSeekOriginCheckDoesNotAcceptMiniMaxOrContainingHosts() {
        let origin = Sites.deepSeek.origin
        XCTAssertTrue(WebSessionProvider.matchesOrigin(origin, expected: origin))
        XCTAssertTrue(WebSessionProvider.matchesOrigin(
            URL(string: "HTTPS://PLATFORM.DEEPSEEK.COM:443/usage"), expected: origin
        ))
        for value in [
            "https://www.minimax.io/",
            "https://platform.minimax.io/",
            "https://platform.deepseek.com.attacker.example/",
            "https://attacker-platform.deepseek.com/",
            "http://platform.deepseek.com/",
            "https://platform.deepseek.com:444/"
        ] {
            let url = URL(string: value)
            XCTAssertNotNil(url, value)
            XCTAssertFalse(WebSessionProvider.matchesOrigin(url, expected: origin), value)
        }
    }

    func testSignOutClearsPlatformAndWwwHosts() {
        XCTAssertEqual(
            WebSessionProvider.websiteDataHosts(for: Sites.minimax(region: .international)),
            ["platform.minimax.io", "www.minimax.io"]
        )
        XCTAssertEqual(
            WebSessionProvider.websiteDataHosts(for: Sites.minimax(region: .china)),
            ["platform.minimaxi.com", "www.minimaxi.com"]
        )
    }

    func testAuthenticationFailureStatusesIncludeMiniMaxCookieCode() {
        XCTAssertTrue(WebSessionProvider.isAuthenticationFailureStatus(401))
        XCTAssertTrue(WebSessionProvider.isAuthenticationFailureStatus(403))
        XCTAssertTrue(WebSessionProvider.isAuthenticationFailureStatus(1004),
                      "MiniMax 1004 is a missing cookie, not a transport error")
        XCTAssertFalse(WebSessionProvider.isAuthenticationFailureStatus(200))
        XCTAssertFalse(WebSessionProvider.isAuthenticationFailureStatus(2045))
    }

    func testRejectedKeyFallsBackToValidCookie() async throws {
        let suite = "MiniMaxCredentialFallback.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MiniMaxCredentialEndpoint.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let provider = MiniMaxProvider(session: session, region: .china,
            archive: UsageArchive(defaults: defaults),
            loadAPIKey: { "dead" }, loadCookieHeader: { "session=valid" })

        let snapshot = try await provider.fetchSnapshot()
        XCTAssertEqual(snapshot.fidelity, .derived)
        XCTAssertEqual(snapshot.windows.first?.usedFraction, 0.5)
    }

    func testRateLimitDoesNotFallThroughToCookie() async {
        let suite = "MiniMaxRateLimitFallback.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MiniMaxCredentialEndpoint.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let provider = MiniMaxProvider(session: session, region: .china,
            archive: UsageArchive(defaults: defaults),
            loadAPIKey: { "throttled" }, loadCookieHeader: { "session=valid" })

        do {
            _ = try await provider.fetchSnapshot()
            XCTFail("a throttled key must not silently switch to a cookie")
        } catch UsageProviderError.rateLimited {
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}

private final class MiniMaxCredentialEndpoint: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host?.contains("minimax") == true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let bearer = request.value(forHTTPHeaderField: "Authorization")
        let throttled = bearer?.contains("throttled") == true
        let body: String
        if throttled {
            body = #"{"base_resp":{"status_code":429}}"#
        } else if bearer != nil {
            body = #"{"base_resp":{"status_code":1004,"status_msg":"login fail: Please carry the API secret key in the Authorization field"}}"#
        } else if request.value(forHTTPHeaderField: "Cookie") == "session=valid" {
            body = #"{"base_resp":{"status_code":0},"model_remains":[{"model_name":"general","current_interval_total_count":100,"current_interval_usage_count":50}]}"#
        } else {
            body = #"{"base_resp":{"status_code":1004,"status_msg":"cookie is missing"}}"#
        }
        let response = HTTPURLResponse(url: url, statusCode: throttled ? 429 : 200,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
