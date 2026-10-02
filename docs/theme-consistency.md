# 任务主题一致性审计

## 规则

品牌主操作、任务完成态和选中态均由 `PlannerTheme` 提供动态系统蓝色：

- `PlannerTheme.accent`：唯一交互主色来源 `NSColor.systemBlue`
- `ModernPalette.accent` / `ModernPalette.blue`：主操作与兼容别名
- `ModernPalette.completion`：任务完成 checkbox、完成状态和完成进度
- `ModernPalette.selection`：选中内容、选中描边
- `ModernPalette.sidebarSelection`：统一蓝色的 9% 透明度选中底色

使用 `systemBlue` 而非 `selectedContentBackgroundColor`，避免任务主题随系统自定义强调色变成另一套颜色。它仍然是动态系统颜色，不承诺某一固定十六进制值，也不修改用户的系统设置。

颜色不能单独承担状态表达：完成仍用 checkmark，取消使用 minus/slash，标题保留适用的弱化与删除线。选中与完成共享色系，但含义由图形、背景、可访问性标签和状态文字区分。

## 已审计的现有入口

| 文件 / 组件 | 完成 / 选中处理 | 保留的其他语义 |
| --- | --- | --- |
| `TodayViews.swift` / `TodayListTaskRow` | 完成 checkbox 使用 `ModernPalette.completion`；未完成圆圈维持中性底色 | 每日重复、计划意图、实际轨的绿色不是任务完成态；逾期保留红色 |
| `PlanningViews.swift` / `PlanningTaskRow` | 完成图标由原来的绿色改为 `ModernPalette.completion`，覆盖明天和未来七天 | 截止警告红色；日期/任务选中采用同源蓝色 |
| `RedesignViews.swift` / `ModernTaskRow`、任务检查器 | 完成颜色和检查器“已完成”颜色使用 completion；侧栏和项目选中来源统一 | 取消中性灰、项目色、标签色与 deadline 警告保留 |
| `ModernGanttViews.swift` / 任务大纲 | 完成 checkbox 与完成状态 badge 均使用 completion | 进行中蓝色、等待橙色、取消灰色、项目自选颜色保留 |
| `Views.swift` / 旧任务行与共享组件 | 原 teal 完成 checkbox、完成进度、通用操作和选中改为同源蓝色；AppColors 的选中别名与新主题一致 | 正计时 teal、番茄橙色、标签语义色保留，未全局替换 teal |
| `FocusWorkspaceViews.swift` | 原计时结束 checkmark 和任务候选选中本来就是蓝色，无需变更颜色 | 番茄/正计时、补录/实际轨、项目色保留 |
| `TagManagementViews.swift` | 选中强调使用 blue 别名；侧栏选中底色继承统一 palette | 用户自定义标签颜色保留 |
| `WorkspacePopoverViews.swift` | 工作区选中标记、默认标记、焦点描边均为 blue 别名 | 工作区图标色、色板颜色、色板上的白色 checkmark 保留；色板 checkmark 不是完成任务 |

今天、明天、未来七天、四象限与日历已接入同源 completion / selection / accent；未进行原生视觉验收。主画布、面板、侧栏及文字使用 AppKit 动态语义色，随设置中的系统／浅色／深色外观切换，避免固定浅底配动态浅字。

原生 Picker、DatePicker、Toggle 等在主内容容器继承 `.tint(ModernPalette.accent)`。局部显式语义 tint（计时、警告等）仍可覆盖它。

## Liquid Glass 控制层

`ModernTopBar` 中的相邻控件放在一个 `GlassEffectContainer(spacing: 8)` 内，控件使用 regular Liquid Glass；来源侧栏使用单一导航材质层，月历切月与返回今天是一组普通按钮配单层玻璃。任务列表、任务卡片、日期格、详情和设置表单保留动态不透明表面，不整页铺玻璃或叠加 glass-on-glass。共享文本搜索输入改为普通输入框背景，不使用适合媒体背景的 clear Glass。

`PlannerControlSurface` 在减少透明度或增加对比度时回退为不透明语义底色与边框；减少动态效果时禁用交互玻璃动态，相关自定义缩放和通知位移动画也采用降级路径。完成/选中仍使用同源蓝色，玻璃不是新的状态颜色。

官方依据：[自定义视图采用 Liquid Glass](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)、[GlassEffectContainer](https://developer.apple.com/documentation/swiftui/glasseffectcontainer)、[Apple 材质规范](https://developer.apple.com/design/human-interface-guidelines/materials)。项目目标 macOS 26；以上 API 有效不等同于本次编译或视觉已通过。

## 验证记录与边界

2026-10-02，执行环境为 Linux，`command -v swift` 未找到 Swift。因此以下内容是源码审计，不能视为 Swift 编译、测试执行或原生视觉验收通过：

- 已检查所有现有 `*Views.swift` 中的完成态、选中态、主操作色、计时与警告颜色用途
- `git diff --check` 通过
- 额外源码断言检查 token 映射，以及 Today、Planning、通用任务、Gantt 和旧视图的完成色引用
- 新增 `ThemeConsistencyTests.swift` 的 5 项测试：单一主色来源、完成/选中别名、旧/新选中底色一致、警告与非完成绿色不被抹平、主表面与文字使用动态语义色。这些 Swift 测试尚未执行

可重复的源码审计入口：

```sh
rg -n 'completionColor|ModernPalette\.completion|completed.*ModernPalette|case \.done:|case \.completed:' Sources/GTDPlanner/*Views.swift
rg -n 'systemBlue|systemGreen|systemTeal|sidebarSelection|static let selection' Sources/GTDPlanner/{ThemeTokens,RedesignViews,Views}.swift
git diff --check
```

## macOS 原生验收清单（待执行）

1. 执行 `swift test`，确认主题测试和全部既有回归通过，再执行项目原生构建流程
2. 同一普通任务在今天、明天、七天、四象限、日历、任务列表、Gantt 中完成/重新打开时，确认 checkmark 使用同一蓝色色系；取消态不能误显示为完成
3. 每日任务分别完成不同日期的实例，确认只有正确实例更新，颜色不因所处视图变化
4. 鼠标、键盘与切换工作区后检查选中态；检查原生控件继承统一 tint，同时保留焦点环和可读文字
5. 分别检查浅色、深色及增强对比度外观下蓝色、透明底色、文字和关闭/禁用态的可辨识度；动态表面与项目自定义色块仍必须逐页观察，不能从 token 映射推断整套深色外观已通过
6. 确认高优先级/逾期红橙、番茄与休息阶段、项目/标签自定义颜色均未被主题覆盖

尚无本次原生截图、视觉通过记录或 macOS 构建结果。
