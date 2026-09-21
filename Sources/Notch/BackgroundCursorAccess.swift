/**
 @name: 后台光标设置
 @Descripttion: 允许非激活显示栏更新系统光标而不抢占前台应用焦点。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-21 11:42:55
 @LastEditTime: 2026-09-21 11:42:55
 @FilePath: Sources/Notch/BackgroundCursorAccess.swift
 */
import AppKit
import Darwin

@MainActor
enum BackgroundCursorAccess {
    // NSCursor.current 仅代表本进程状态；后台进程必须先获得 WindowServer
    // 的光标设置能力，否则 push/set 可以成功改变本地状态却不改变屏幕指针。
    // 此属性属于进程连接，多显示器的浮窗共用一次设置，不改变应用激活状态。
    static let isEnabled: Bool = {
        guard let framework = dlopen(
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY
        ) else { return false }
        defer { dlclose(framework) }

        // 私有接口不做静态链接，系统不再提供时仍可正常启动显示栏。
        guard let connectionSymbol = dlsym(framework, "CGSMainConnectionID"),
              let propertySymbol = dlsym(framework, "CGSSetConnectionProperty") else { return false }
        typealias Connection = @convention(c) () -> Int32
        typealias SetProperty = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32
        let connection = unsafeBitCast(connectionSymbol, to: Connection.self)()
        guard connection != 0 else { return false }
        let setProperty = unsafeBitCast(propertySymbol, to: SetProperty.self)
        return setProperty(connection, connection, "SetsCursorInBackground" as CFString,
                           kCFBooleanTrue) == CGError.success.rawValue
    }()
}
