/**
 @name: 上游同步模块
 @Descripttion: 维护 Runtime.swift 的项目实现与上游兼容。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-11 15:51:14
 @LastEditTime: 2026-09-11 15:51:14
 @FilePath: Sources/App/Runtime.swift
 */
import Foundation

/// Whether this process is an `xcodebuild test` host rather than a Codenotch
/// somebody launched.
///
/// The unit bundle is hosted by the app itself, so a test run *is* a running
/// Codenotch — and anything that would reach outside the process has to ask
/// first. Without the check every test run put a live request on the usage
/// endpoint, and every `NotchWindowController` a test constructed ordered a
/// real panel onto the developer's screen: a single `make test` put forty of
/// them up at once, over whatever was being worked on, for the half minute the
/// suite took.
enum Runtime {
    static let isUnderTest: Bool =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
}
