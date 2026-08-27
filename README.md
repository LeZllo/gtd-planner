# GTD Planner

GTD Planner 是一个面向 macOS 的原生 GTD 任务管理工具，将任务收集、项目拆解、计划安排、实际专注和复盘放在同一个工作流中。

项目目前正在准备首次公开，版本仍处于早期阶段。

## 功能

- 原生 SwiftUI macOS 界面：组织栏、工作区、项目树、任务列表和检查器
- 工作区、项目、分区、子任务和任务层级
- 收集箱，以及今日、近期、下一步、等待中、某天和已完成列表
- 任务状态、优先级、标签、任务笔记、计划时间和截止时间
- 正计时、番茄钟、暂停、继续和停止
- 计划时间与实际专注时间分开记录，支持实际时间记录的补录、编辑和删除
- 甘特图与任务树保持一致的项目规划视图
- JSON 备份导入与导出
- 从 Obsidian 资料库导入 GTD 任务、项目层级、任务笔记和实际时间记录

## 系统要求

- macOS 26（Tahoe）或更高版本
- Swift 6.2 工具链；也可以使用支持该工具链的 Xcode 版本
- 当前版本不依赖网络包或远程服务

## 构建和运行

在项目根目录执行：

```sh
swift test
./build-app.sh
open "GTD Planner.app"
```

`build-app.sh` 会在项目根目录生成 `GTD Planner.app`。构建脚本使用本地签名，应用目前没有 Apple Developer ID 签名和公证；首次运行时 macOS 可能显示安全确认。

## 数据与隐私

应用数据默认保存在：

```text
~/Library/Application Support/GTD Planner/GTD Planner.store
```

数据保存在本机。首次启动只创建空的默认工作区，不会自动写入演示任务或上传用户资料。

从 Obsidian 导入是一次性迁移操作：应用读取 `type: gtd-task` 任务、项目层级、任务笔记和 `gtd-time-entry` 实际记录，运行时数据由 SwiftData 管理。

请不要把个人数据库、JSON 备份或包含真实任务的资料库提交到 GitHub。

## 项目结构

```text
Sources/GTDPlanner/    应用源码
Tests/GTDPlannerTests/ 回归测试
Package.swift          Swift Package 配置
Info.plist             macOS 应用配置
build-app.sh           本地构建脚本
design-qa.md           公开的质量验证记录
```

## 图标与字体

项目没有内置自定义字体、图标文件或第三方图标库。

- 界面图标通过 SwiftUI 的 `Image(systemName:)`、`Label(..., systemImage:)` 和 SF Symbols 名称调用。
- 文字通过 SwiftUI 的系统字体接口（例如 `.font(.system(...))`）渲染。
- 项目不重新分发 SF Symbols 或 macOS 系统字体；相关内容仍受 Apple 的许可条款约束。

## 当前限制

- 当前仅支持 macOS 26 及以上版本。
- 暂未提供签名、公证和预编译下载包，使用者需要本地构建。
- 当前持久化、计时和日志服务仍由应用协调器统一管理，后续会继续拆分和完善。
- 自动化测试主要覆盖数据层和交互回归；完整的视觉与系统窗口验证仍需要在 macOS 上进行。

## 参与贡献

欢迎通过 GitHub Issues 报告问题或提出建议。提交问题时，请尽量附上：

- macOS 版本和 Swift/Xcode 版本
- 复现步骤
- 预期结果与实际结果
- 与问题相关的脱敏日志或截图

请不要上传个人数据库、真实任务内容或其他敏感信息。

## 开发说明

本项目由作者负责产品设计、技术决策、代码审阅和发布内容维护。开发过程中辅助使用了 OpenAI Codex 等 AI 工具，用于代码讨论、实现辅助、测试分析和文档整理。项目中的代码和功能仍以作者的审阅、修改和验证结果为准。

## 许可证

本项目代码采用 [MIT License](LICENSE) 发布。

MIT License 只适用于本项目代码及项目作者拥有版权的内容，不改变 Apple 系统字体和 SF Symbols 的许可条件。项目中如果今后加入从其他项目继承或参考的代码、图标或素材，会在许可证和归属说明中明确标注。
