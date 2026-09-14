<!--
@name: 上游同步记录
@Descripttion: 记录同步基线、功能取舍和验证范围，供后续同步参考。
@version: 1.0.0
@Author: sm
@Date: 2026-09-14 10:03:00
@LastEditTime: 2026-09-14 10:03:00
@FilePath: docs/upstream-sync.md
-->

# 2026-09-14 上游同步

- 来源：<https://github.com/vinzdg/codenotch>，`main`。
- 同步目标：`404f589717d5e6cfa00620cf375e2373770d55b2`。
- 共同祖先：`e8884aa49da9e50f603035b4be349a3d4d9bec9d`。
- 同步前本地：`b85dbd0`，工作区干净。
- 本次以源码同步提交整合上游，随 `v1.6.32` 发布；未建立包含上游历史的合并提交，后续同步需使用本记录的上游目标作为已整合基线。

## 已确认的功能取舍

- 保留本地 Code Switch R 通讯、订阅、供应商过滤/排序、会话绑定、等待状态和断线回退。
- Codex 默认使用 hooks 完成信号。通知设置新增日志辅助识别开关，下一轮活动轮询生效。开启时最多读取 rollout 最后 256 KiB 的完整记录，两种方式均保留数据库线程身份及 Code Switch R 关联。
- 已保存查询目录继续决定已有账户的启停状态；与上游 connected-provider 偏好同步，保留隐藏模型。Kimi/Kiro 仅导入一次，默认关闭；用户开启后保留，删除后不自动重建。
- 保留本地按钮默认隐藏、独立开关、打开设置、自由定位、居中吸附及完整悬浮卡；合入上游拖动时暂停悬浮、全屏折叠开关和终端标签定位。定位会话时保留本地进程启动时间校验。
- 同步时保留本地版本、自动更新地址、发布产物及工作流；发布阶段递增为 `1.6.32` / build `273`。不恢复本地已删除的 `.github/workflows/ci.yml`，上游 `site/Codenotch.dmg` 和 `site/appcast.xml` 未覆盖本地产物；提交前快进纳入远端 `v1.6.31` 自动发布提交。
- Windows 保留本地多语言格式化，同时合入上游模型分组、卡片样式和后端修复。

## 兼容修复

- 额度重置后的立即刷新接入本地独立查询调度，继续遵守自动刷新关闭及限流退避，防止旧重置时间反复触发。
- 通知观察器和 Claude 日用量节奏接入本地联动路由，避免上游快照订阅覆盖 Code Switch R 内容。
- 合并声音选择器、设置窗口参数、语言持久化、手柄布局和悬浮卡尺寸接口。
- 上游手机连接功能沿用其本地账户快照范围，不增加向手机转发 Code Switch R 快照的协议扩展。

## 验证

### 同步后评审修复

- 隐藏模型 ID 始终纳入禁用集合，模型尚未发现时也保留隐藏状态。
- 额度观察器在显示窗口切换时重新建立基线；持续阻塞不再重复触发耗尽提醒，解除后允许再次提醒。
- 额度通知及预览沿用共享音量；多账户快照单独携带原生供应商类型，Claude 每日节奏不依赖账户 ID 格式。
- Windows 俄语接入现有翻译入口，统一语言来源并补齐动态文案。
- Codex 轮询在后台执行，仅为最新且未过期的 rollout 读取尾部；按路径、修改时间、大小及文件身份缓存结果，停止轮询后的旧结果不能发布。默认仍不读取 rollout 内容。
- 新增 `Tests/UpstreamSyncRegressionTests.swift` 和 `node Scripts/test-notch-localization.mjs`，覆盖这些兼容行为。
- 修复后完成应用源码类型检查及临时动态库编译链接，103 项 Swift Testing 回归全部通过（含新增 9 项）；Windows 翻译回归、页面脚本语法和 `git diff --check` 通过。临时链接使用本机 zstd，正式项目仍使用随源码提供的解码器。未重跑需要真实屏幕的 HookPresentation，完整 Xcode/XCTest 与 Windows 运行验证限制仍在。

### 同步时验证记录

- 使用 Command Line Tools、macOS 26.5 SDK、上游锁定版本的 SwiftNIO 和 Sparkle，完成应用源码编译及动态库链接。依赖和运行器均位于 `/tmp/codenotch-sync-check`，未修改项目依赖声明。
- 运行现有 Swift Testing 的 97 项测试：96 项通过，涵盖 ActivityRouting、HookActivity、CodeSwitchIntegration、UsageRefreshRecovery 及部分 HookPresentation。
- 唯一失败为 `HookPresentationTests.peekReportsWhetherAnAlertWasActuallyDisplayed`：环境无可用屏幕，`show()` 无法创建面板；同组的静态渲染及其他联动测试通过。未据此修改应用行为。
- 2 项临时补充测试通过：账户迁移/默认值/开关持久化，以及大日志尾部完成事件识别。持久回归覆盖同时保留在 PreferencesTests、QueryConfigurationTests、CodexUsageTests、ActivityRoutingTests 和 UsageRefreshRecoveryTests。
- 本地化 JSON、plist、Windows 两个页面的 JavaScript 语法、`Scripts/test-signing.sh` 和 `git diff --check` 通过。
- 当前无完整 Xcode/XCTest、XcodeGen 或 Cargo，未完成 `make test`、正式应用打包及 Windows Rust 编译。临时动态库编译和测试不替代这些检查。
