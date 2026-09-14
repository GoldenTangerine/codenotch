/**
 @name: 上游同步 · SettingsQuitButtonTests
 @Descripttion: 保留上游功能实现并兼容本地扩展。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-14 09:43:04
 @LastEditTime: 2026-09-14 09:43:04
 @FilePath: Tests/SettingsQuitButtonTests.swift
 */
import SwiftUI
import XCTest
@testable import Codenotch

@MainActor
final class SettingsQuitButtonTests: XCTestCase {
    func testSettingsRendersWithQuitAction() throws {
        let name = "SettingsQuitButtonTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var didQuit = false
        let settings = SettingsView(
            preferences: Preferences(defaults: defaults),
            providers: { [] },
            signOut: { _ in },
            signIn: { _ in false },
            switchAccount: { _ in false },
            retry: { _ in },
            resetPosition: {},
            quit: { didQuit = true },
            updater: Updater()
        )
        let view = settings.frame(width: SettingsView.width, height: SettingsView.height)

        let image = try XCTUnwrap(ImageRenderer(content: view).nsImage)
        XCTAssertEqual(image.size, CGSize(width: SettingsView.width, height: SettingsView.height))

        settings.quit()
        XCTAssertTrue(didQuit)
    }
}
