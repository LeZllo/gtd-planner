import AppKit
import SwiftUI

/// The app menu, Command-comma, and in-app buttons all open the native Settings
/// scene. This view does not present another sheet or own a second preferences
/// instance, so every entry point edits the same persisted values.
struct PlannerSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(PlannerPreferences.self) private var preferences
    @State private var dataStatus: String?

    var body: some View {
        @Bindable var preferences = preferences
        TabView(selection: $preferences.selectedSettingsTab) {
            generalSettings
                .tabItem { Label("通用", systemImage: "gearshape") }
                .tag(PlannerSettingsTab.general)

            appearanceSettings
                .tabItem { Label("外观", systemImage: "circle.lefthalf.filled") }
                .tag(PlannerSettingsTab.appearance)

            dataSettings
                .tabItem { Label("数据", systemImage: "externaldrive") }
                .tag(PlannerSettingsTab.data)

            aboutSettings
                .tabItem { Label("关于", systemImage: "info.circle") }
                .tag(PlannerSettingsTab.about)
        }
        .padding(16)
        .frame(width: 660, height: 520)
        .tint(PlannerTheme.accent)
        .preferredColorScheme(preferences.appearance.colorScheme)
    }

    private var generalSettings: some View {
        @Bindable var preferences = preferences
        return Form {
            Section {
                Picker("默认工作区", selection: Binding(
                    get: { model.defaultWorkspaceID },
                    set: { model.setDefaultWorkspace($0) }
                )) {
                    ForEach(model.manuallyOrderedWorkspaces) { workspace in
                        Label(workspace.name, systemImage: workspace.symbolName)
                            .tag(workspace.id)
                    }
                }
                .help("下次启动时打开此工作区；也可在工作区菜单中更改")

                Picker("今天默认视图", selection: Binding(
                    get: { preferences.defaultTodayViewMode },
                    set: {
                        preferences.defaultTodayViewMode = $0
                        model.selection.todayViewMode = $0
                    }
                )) {
                    ForEach(TodayViewMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .help("立即更新今天视图，并在下次启动时继续使用")
            } header: {
                Text("启动与导航")
            } footer: {
                Text("默认工作区在下次启动时使用。今天默认视图立即生效，并在重新启动后保留。")
            }

            Section {
                Stepper(value: $preferences.defaultPomodoroMinutes,
                        in: PlannerPreferences.pomodoroMinutesRange) {
                    LabeledContent("默认番茄时长") {
                        Text("\(preferences.defaultPomodoroMinutes) 分钟")
                            .monospacedDigit()
                    }
                }
                .accessibilityLabel("默认番茄时长")
                .accessibilityValue("\(preferences.defaultPomodoroMinutes) 分钟")
            } header: {
                Text("专注")
            } footer: {
                Text("可设置为 1–180 分钟，用于新一轮番茄钟。当前正在运行的计时不会改变；开始前仍可单独调整时长。")
            }
        }
        .formStyle(.grouped)
    }

    private var appearanceSettings: some View {
        @Bindable var preferences = preferences
        return Form {
            Section {
                Picker("外观", selection: $preferences.appearance) {
                    ForEach(PlannerAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)

                LabeledContent("交互强调色") {
                    Label("系统蓝色", systemImage: "circle.fill")
                        .foregroundStyle(PlannerTheme.accent)
                }
            } header: {
                Text("显示")
            } footer: {
                Text("外观立即应用到主窗口和设置窗口。主操作、任务完成和选中状态使用一致的系统蓝色；项目与标签保留各自颜色。")
            }
        }
        .formStyle(.grouped)
    }

    private var dataSettings: some View {
        Form {
            Section("本地存储") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("SwiftData 数据库")
                    Text(model.storage.storeURL.path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("在 Finder 中显示", systemImage: "folder") {
                        revealDatabase()
                    }
                }
            }

            Section {
                Button("导出 JSON 备份…", systemImage: "square.and.arrow.up") {
                    performDataAction { model.exportDatabase() }
                }
                Button("从备份恢复（替换全部数据）…", systemImage: "square.and.arrow.down") {
                    performDataAction { model.importDatabase() }
                }
                Button("从 Obsidian 迁移（替换全部数据）…", systemImage: "doc.badge.arrow.up") {
                    performDataAction { model.importObsidianVault() }
                }
            } header: {
                Text("备份与迁移")
            } footer: {
                Text("恢复和迁移会替换当前全部任务数据，继续前需要确认。运行中的计时需要先停止。外观、默认视图与番茄时长保存在本机偏好中，不包含在 JSON 备份内。")
            }

            if let dataStatus {
                Section("操作结果") {
                    Text(dataStatus)
                        .textSelection(.enabled)
                        .accessibilityLabel("数据操作结果：\(dataStatus)")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var aboutSettings: some View {
        Form {
            Section {
                LabeledContent("应用", value: "GTD Planner")
                LabeledContent("版本", value: versionDescription)
                LabeledContent("运行平台", value: "macOS 26 或更高版本")
            }

            Section("使用与快捷键") {
                Text("今天用于执行；明天和未来七天用于安排；四象限按重要性与截止紧急程度分类；日历按日期组织计划。")
                Text("⌘N 新建任务 · ⌘, 设置 · ⌘D 复制选中任务 · ⌘K 完成或重新打开 · ⌘⌫ 移入垃圾箱")
                    .font(.system(size: 11.5))
                Text("任务操作也可通过右键或菜单栏的“任务”菜单访问。日期页不会提前完成未来实例；任务删除需确认，可从垃圾箱恢复，未提供专用⌘Z撤销删除。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }

            Section("关于 GTD Planner") {
                Text("本地优先的 GTD 任务管理工具，连接任务收集、项目拆解、计划安排、专注与复盘。")
                Text("任务数据通过 SwiftData 保存在本机；Obsidian 导入是一次性迁移，JSON 用于备份和恢复。计划时间、截止时间与实际专注记录分别保存。")
                    .foregroundStyle(.secondary)
                Text("设置会自动保存。可使用 ⌘, 随时打开此窗口。")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var versionDescription: String {
        let info = Bundle.main.infoDictionary ?? [:]
        guard let version = info["CFBundleShortVersionString"] as? String else {
            return "开发构建"
        }
        guard let build = info["CFBundleVersion"] as? String else { return version }
        return "\(version)（\(build)）"
    }

    private func performDataAction(_ action: () -> Void) {
        // Panels and replacement confirmation stay in the model's existing
        // entry points. Copy the result here so it remains visible even when
        // the main window dismisses its transient toast behind Settings.
        dataStatus = nil
        model.notice = nil
        action()
        dataStatus = model.notice
    }

    private func revealDatabase() {
        let url = model.storage.storeURL
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else if !NSWorkspace.shared.open(url.deletingLastPathComponent()) {
            dataStatus = "无法打开数据目录。可复制上方路径后在 Finder 中前往该文件夹。"
        }
    }
}
