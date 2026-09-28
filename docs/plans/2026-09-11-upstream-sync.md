<!--
@name: 上游同步记录
@Descripttion: 记录本次上游来源、冲突取舍和验证边界。
@version: 1.0.0
@Author: sm
@Date: 2026-09-11 16:00:00
@LastEditTime: 2026-09-11 16:00:00
@FilePath: docs/plans/2026-09-11-upstream-sync.md
-->

# 上游同步：2026-09-11

- 上游：`vinzdg/codenotch`，`main`，`e8884aa49da9e50f603035b4be349a3d4d9bec9d`。
- 本地起点：`e5263858b1a1a5e043a2f8f9825fef9de39003b6`。
- 共同祖先：`892c6d66f012dc0689a9f205c108c02434899bbf`；上游新增 195 个提交，涉及 241 个文件。
- 用户已授权提交与发布 v1.6.20；采用双亲合并提交记录上游来源，推送 tag 触发 GitHub Actions 完整测试与打包。
- 原有 6 个未提交文件的备份：`/private/tmp/codenotch-sync-20260911-153230/local-changes.tar`，另有 `local.patch` 和 `head.txt`。

## 合并结果

保留 Code Switch R、多账号和手动查询、品牌图标、查询退避、通知音量、独立强调色、完整气泡以及拖拽定位。整合上游新增供应商、本地模型运行状态、周额度、Codex 用量明细、语言选择、玻璃效果和移动手柄；Windows 源码一并同步。

查询包装层传递新增的快照字段、供应商类型和账号切换方法。旧配置只补充一次新增供应商，之后删除不会被重新添加。调度沿用上游的请求代次管理，并保留本地独立间隔、退避与配置失效逻辑。旧 `AppleLanguages` 选择迁移到上游语言设置。

发布版本升级为 `1.6.20 / 255`，保留本仓库的、Sparkle 更新源、公钥、已发布的 DMG/appcast 和原有发布流程。上游 Package 工作流保留其仓库限制，在本 fork 不执行打包发布。Code Switch R 的拖拽表格依赖 macOS 26，故继续要求 macOS 26，没有降为上游的 macOS 15。

## 验证

- Command Line Tools 的 macOS 26.5 SDK、Swift 5 模式：全部应用 Swift 源码、SwiftNIO/Sparkle 依赖和 Zstandard C 解码器完成补充编译链接。临时 SwiftPM 工程位于上述备份目录的 `build-check`，不属于本仓库构建配置。
- 249 个 Swift 文件按应用、测试、两个 Helper 目标分别完成语法检查。
- `python3 -m unittest discover -s Scripts -p 'test_*.py'`：14 项通过（包含 Latest 回读不一致时阻止发布成功的回归测试）。
- `bash Scripts/test-signing.sh`：4 组模拟签名配置通过，不读取真实钥匙串。
- `python3 Scripts/check-localization.py`：791 个条目的简体中文和格式参数通过。
- 隔离偏好域和模拟供应商的运行检查：供应商迁移与删除保留、新旧缓存、字段传递、语言及本地偏好、独立调度、过期响应丢弃、滚动缩放与气泡边界均通过。验证入口及日志保留在备份目录的 `RegressionMain.swift`、`regression.log`。
- 新增迁移及快照字段的 XCTest 回归用例，位于 `Tests/QueryConfigurationTests.swift`。

本机没有完整 Xcode、XcodeGen 和 XCTest，也没有 Rust 工具链，因此未运行正式 `make test`、Xcode 应用打包、界面渲染单测和 Windows 构建。补充编译不验证资源打包、应用签名或真实供应商登录；本次未启动应用连接用户账户。
