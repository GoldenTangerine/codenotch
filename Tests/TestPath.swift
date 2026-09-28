/**
 @name: 上游同步回归测试
 @Descripttion: 维护 TestPath.swift 的项目实现与上游兼容。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-11 15:51:14
 @LastEditTime: 2026-09-11 15:51:14
 @FilePath: Tests/TestPath.swift
 */
import XCTest

class TestPath: XCTestCase {
    func testPrintPath() {
        print("PATH IS: \(#filePath)")
        print("URL IS: \(URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../Sources/Localizable.xcstrings").standardizedFileURL.path)")
    }
}
