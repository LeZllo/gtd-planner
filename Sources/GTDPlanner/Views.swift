import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(AppModel.self) private var model: AppModel
    @State private var showTaskEditor = false
    @State private var editingTask: GTDTask?
    @State private var tick = Date()

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            NativeChromeHeader(
                title: currentContextTitle,
                timerElapsed: model.activeTimer.map { _ in model.timerElapsed(at: tick) }
            ) {
                editingTask = nil
                showTaskEditor = true
            }

            HStack(spacing: 0) {
                SmartListsColumn()
                    .frame(width: 224)
                Divider().opacity(0.55)
                WorkspaceRail()
                    .frame(width: 50)
                Divider().opacity(0.55)
                ProjectColumn()
                    .frame(width: 220)
                Divider().opacity(0.55)
                TaskListColumn(editingTask: $editingTask, showTaskEditor: $showTaskEditor)
                    .frame(minWidth: 446, maxWidth: .infinity)
                Divider().opacity(0.55)
                InspectorColumn(editingTask: $editingTask, showTaskEditor: $showTaskEditor)
                    .frame(width: 320)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(AppColors.canvas)
        .sheet(isPresented: $showTaskEditor) {
            TaskEditor(task: editingTask)
                .environment(model)
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { tick = $0 }
        .onChange(of: model.notice) { _, value in
            guard value != nil else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { model.notice = nil }
        }
        .onChange(of: model.showNewTask) { _, value in
            if value {
                showTaskEditor = true
                model.showNewTask = false
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let notice = model.notice {
                Text(notice)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background {
                        Capsule()
                            .fill(.clear)
                            .glassEffect(.regular, in: Capsule())
                    }
                    .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
                    .padding(18)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.snappy(duration: 0.22), value: model.notice)
        .sheet(isPresented: $model.showingSettings) {
            SettingsView()
                .environment(model)
        }
    }

    private var currentContextTitle: String {
        if let project = model.selectedProject { return project.name }
        if model.selection.selectedOrganization == .projects { return "项目" }
        return model.selection.selectedSmartList.title
    }
}

struct NativeChromeHeader: View {
    @Environment(AppModel.self) private var model: AppModel
    let title: String
    let timerElapsed: TimeInterval?
    let onNewTask: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // The hidden title bar leaves the traffic lights over this quiet area,
            // matching Mail's sidebar-first window chrome.
            Color.clear.frame(width: 274)
            HStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.ink)
                    .lineLimit(1)
                Spacer(minLength: 12)
                if let timerElapsed, let active = model.activeTimer {
                    TimerCapsule(timer: active, elapsed: timerElapsed)
                }
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        Button(action: onNewTask) {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(ChromeIconButtonStyle())
                        .keyboardShortcut("n", modifiers: [.command])
                        .help("新建任务")
                        Menu {
                            Button("设置…") { model.showingSettings = true }
                            Divider()
                            Button("导出本地备份…") { model.exportDatabase() }
                            Button("导入本地备份…") { model.importDatabase() }
                            Button("从 Obsidian 资料库导入…") { model.importObsidianVault() }
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(AppColors.ink)
                                .frame(width: 34, height: 34)
                                .glassEffect(.regular.interactive(), in: Circle())
                        }
                        .menuStyle(.borderlessButton)
                        .help("设置与数据")
                    }
                }
            }
            .padding(.horizontal, 18)
        }
        .frame(height: 46)
        .background {
            Rectangle()
                .fill(.clear)
                .glassEffect(.clear, in: Rectangle())
        }
    }
}

struct SmartListsColumn: View {
    @Environment(AppModel.self) private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SidebarSectionTitle("组织")
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(OrganizationItem.allCases) { item in
                            AppleSidebarRow(
                                icon: item.icon,
                                title: item.title,
                                selected: model.selection.selectedOrganization == item,
                                count: organizationCount(for: item)
                            ) {
                                select { model.selectOrganization(item) }
                            }
                        }
                    }

                    SidebarSectionTitle("智能列表")
                        .padding(.top, 26)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach([SmartList.today, .tomorrow, .recent, .fourSquares, .calendar]) { item in
                            AppleSidebarRow(
                                icon: item.icon,
                                title: item.title,
                                selected: model.selection.selectedOrganization == nil && model.selection.selectedSmartList == item,
                                count: model.count(for: item)
                            ) {
                                select { model.selectSmartList(item) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 16)
                .padding(.bottom, 18)
            }
        }
        .background(AppColors.sidebar)
    }

    private func organizationCount(for item: OrganizationItem) -> Int {
        switch item {
        case .inbox:
            return model.currentTasks.filter { $0.status == .inbox }.count
        case .projects:
            return model.currentProjects.count
        case .tags:
            return model.currentTagCount
        case .filters:
            return 0
        }
    }

    private func select(_ action: @escaping () -> Void) {
        if reduceMotion {
            action()
        } else {
            withAnimation(.spring(response: 0.32, dampingFraction: 1), action)
        }
    }
}

struct WorkspaceRail: View {
    @Environment(AppModel.self) private var model: AppModel

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 8) {
            Spacer().frame(height: 14)
            ForEach(model.database.workspaces) { workspace in
                Button { model.selectWorkspace(workspace.id) } label: {
                    Image(systemName: workspace.symbolName)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(model.selection.selectedWorkspaceID == workspace.id ? Color(hex: workspace.colorHex) : AppColors.muted)
                        .frame(width: 38, height: 38)
                        .background(model.selection.selectedWorkspaceID == workspace.id ? Color(hex: workspace.colorHex).opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.plain)
                .help(workspace.name)
            }
            Divider().padding(.horizontal, 10).padding(.vertical, 4)
            Button { model.notice = "工作区管理已预留入口" } label: { Image(systemName: "person.2") }
                .buttonStyle(RailIconStyle())
                .help("工作区")
            Button { model.notice = "统计视图已预留入口" } label: { Image(systemName: "chart.pie") }
                .buttonStyle(RailIconStyle())
                .help("统计")
            Spacer()
            Button { model.showingSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                .buttonStyle(RailIconStyle())
                .help("偏好设置")
            Button { model.showNewProject = true } label: { Image(systemName: "plus") }
                .buttonStyle(RailIconStyle())
                .help("新建项目")
                .sheet(isPresented: $model.showNewProject) { NewProjectSheet().environment(model) }
            Spacer().frame(height: 10)
        }
        .frame(maxHeight: .infinity)
        .background(AppColors.sidebar)
    }
}

struct ProjectColumn: View {
    @Environment(AppModel.self) private var model: AppModel
    @State private var collapsedCategories: Set<String> = []
    @State private var projectQuery = ""

    private var grouped: [(String, [Project])] {
        let projects = model.currentProjects.filter { project in
            let needle = projectQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !needle.isEmpty else { return true }
            return project.name.localizedCaseInsensitiveContains(needle) || project.category.localizedCaseInsensitiveContains(needle)
        }
        return Dictionary(grouping: projects, by: { $0.category })
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
    }

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 0) {
            SearchField(text: $projectQuery, placeholder: "搜索项目")
                .padding(.horizontal, 12)
                .padding(.top, 14)
                .padding(.bottom, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ProjectRow(title: "所有项目", icon: "tray.full", count: model.currentProjects.reduce(0) { result, project in result + model.currentTasks.filter { $0.projectID == project.id && !$0.status.isFinished }.count }, color: AppColors.teal, selected: model.selection.selectedOrganization == .projects && model.selection.selectedProjectID == nil) {
                        model.selectProject(nil)
                    }
                    ForEach(grouped, id: \.0) { category, projects in
                        CategoryHeader(category: category, collapsed: collapsedCategories.contains(category)) {
                            if collapsedCategories.contains(category) { collapsedCategories.remove(category) } else { collapsedCategories.insert(category) }
                        }
                        if !collapsedCategories.contains(category) {
                            ForEach(projects) { project in
                                ProjectRow(title: project.name, icon: "folder", count: model.currentTasks.filter { $0.projectID == project.id && !$0.status.isFinished }.count, color: Color(hex: project.colorHex), selected: model.selection.selectedProjectID == project.id) {
                                    model.selectProject(project.id)
                                }
                            }
                        }
                    }
                    if model.currentProjects.isEmpty {
                        EmptyColumnHint(icon: "folder.badge.plus", title: "还没有项目", message: "把需要多个行动完成的成果放进项目")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 20)
            }
            Spacer(minLength: 0)
            HStack {
                Text("\(model.currentProjects.count) 个项目")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.muted)
                Spacer()
                Button { model.showNewProject = true } label: { Image(systemName: "plus") }
                    .buttonStyle(QuietIconButtonStyle())
                    .help("新建项目")
            }
            .padding(14)
            .background(AppColors.panel)
        }
        .background(AppColors.panel)
        .sheet(isPresented: $model.showNewProject) { NewProjectSheet().environment(model) }
    }
}

struct TaskListColumn: View {
    @Environment(AppModel.self) private var model: AppModel
    @Binding var editingTask: GTDTask?
    @Binding var showTaskEditor: Bool
    @State private var expandedTasks: Set<UUID> = []
    @State private var calendarMonth = Date()

    private var visibleRows: [(task: GTDTask, depth: Int)] {
        model.hierarchyRows(for: model.filteredTasks())
    }

    var body: some View {
        @Bindable var model = model
        @Bindable var selection = model.selection
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { model.notice = "排序方式：手动顺序" } label: { Image(systemName: "checkmark.square") }
                    .buttonStyle(QuietIconButtonStyle())
                Text(model.selectedProject?.name ?? (model.selection.selectedOrganization == .projects ? "项目" : model.selection.selectedSmartList.title))
                    .font(.system(size: 17, weight: .semibold))
                Text("\(visibleRows.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColors.muted)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(AppColors.subtle, in: Capsule())
                Picker("视图", selection: $selection.plannerView) {
                    ForEach(PlannerView.allCases) { view in
                        Image(systemName: view.icon).tag(view)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 156)
                SearchField(text: $model.query, placeholder: "搜索任务")
                    .frame(width: 156)
                Spacer()
                Button { model.notice = "拖放排序会保留任务层级" } label: { Image(systemName: "line.3.horizontal.decrease") }
                    .buttonStyle(QuietIconButtonStyle())
                Button { model.notice = "快捷键：⌘N 新建，Space 完成" } label: { Image(systemName: "ellipsis") }
                    .buttonStyle(QuietIconButtonStyle())
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background {
                Rectangle()
                    .fill(.clear)
                    .glassEffect(.clear, in: Rectangle())
            }
            Divider()
            if let active = model.activeTimer {
                ActiveTimerBar(timer: active)
            }
            if model.selection.plannerView == .list {
                listContent
            } else if model.selection.plannerView == .calendar {
                MonthCalendarView(month: $calendarMonth)
            } else {
                TimelineView()
            }
        }
        .background(AppColors.canvas)
    }

    @ViewBuilder
    private var listContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                sectionHeader("未完成", count: visibleRows.filter { !$0.task.status.isFinished }.count)
                ForEach(visibleRows.filter { !$0.task.status.isFinished }, id: \.task.id) { row in
                    TaskRow(task: row.task, depth: row.depth, hasChildren: !model.children(of: row.task).isEmpty, isExpanded: expandedTasks.contains(row.task.id), editingTask: $editingTask, showTaskEditor: $showTaskEditor) {
                        if expandedTasks.contains(row.task.id) { expandedTasks.remove(row.task.id) } else { expandedTasks.insert(row.task.id) }
                    }
                }
                sectionHeader("已完成", count: visibleRows.filter { $0.task.status.isFinished }.count)
                    .padding(.top, 18)
                ForEach(visibleRows.filter { $0.task.status.isFinished }, id: \.task.id) { row in
                    TaskRow(task: row.task, depth: row.depth, hasChildren: !model.children(of: row.task).isEmpty, isExpanded: expandedTasks.contains(row.task.id), editingTask: $editingTask, showTaskEditor: $showTaskEditor) {
                        if expandedTasks.contains(row.task.id) { expandedTasks.remove(row.task.id) } else { expandedTasks.insert(row.task.id) }
                    }
                }
                if visibleRows.isEmpty {
                    EmptyColumnHint(icon: "checkmark.circle", title: "这里还很安静", message: "按 ⌘N 收集一个下一步行动")
                        .padding(.top, 100)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 40)
        }
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .bold))
            Text(title).font(.system(size: 13, weight: .semibold))
            Text("\(count)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppColors.muted)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(AppColors.subtle, in: Capsule())
            Spacer()
        }
        .foregroundStyle(AppColors.ink)
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
    }
}

struct MonthCalendarView: View {
    @Environment(AppModel.self) private var model: AppModel
    @Binding var month: Date
    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 1), count: 7)

    private var days: [Date] {
        guard let first = calendar.date(from: calendar.dateComponents([.year, .month], from: month)),
              let range = calendar.range(of: .day, in: .month, for: first) else { return [] }
        let weekday = calendar.component(.weekday, from: first)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let total = Int(ceil(Double(leading + range.count) / 7.0)) * 7
        return (0..<total).compactMap { calendar.date(byAdding: .day, value: $0 - leading, to: first) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { month = calendar.date(byAdding: .month, value: -1, to: month) ?? month } label: { Image(systemName: "chevron.left") }.buttonStyle(QuietIconButtonStyle())
                Text(month.formatted(.dateTime.year().month())).font(.system(size: 14, weight: .semibold))
                Button { month = calendar.date(byAdding: .month, value: 1, to: month) ?? month } label: { Image(systemName: "chevron.right") }.buttonStyle(QuietIconButtonStyle())
                Spacer()
                Button("今天") { month = .now }.buttonStyle(.bordered).controlSize(.small)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            Divider()
            LazyVGrid(columns: columns, spacing: 1) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(AppColors.muted).frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                ForEach(days, id: \.self) { day in CalendarDayCell(day: day) }
            }
            .padding(1)
            Spacer()
        }
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let start = max(0, calendar.firstWeekday - 1)
        return Array(symbols[start...] + symbols[..<start])
    }
}

struct CalendarDayCell: View {
    @Environment(AppModel.self) private var model: AppModel
    let day: Date
    private let calendar = Calendar.current

    private var tasks: [GTDTask] {
        model.filteredTasks(for: .all).filter { task in
            guard let start = task.plannedStart else { return false }
            return calendar.isDate(start, inSameDayAs: day)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(day, format: .dateTime.day())
                .font(.system(size: 11, weight: calendar.isDateInToday(day) ? .bold : .medium))
                .foregroundStyle(calendar.isDateInToday(day) ? AppColors.teal : AppColors.muted)
            ForEach(tasks.prefix(3)) { task in
                Button { model.selectTask(task.id) } label: {
                    HStack(spacing: 4) {
                        Circle().fill(Color(hex: task.priority.color)).frame(width: 5, height: 5)
                        Text(task.title).lineLimit(1)
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(task.status.isFinished ? AppColors.muted : AppColors.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if tasks.count > 3 { Text("+ \(tasks.count - 3) 项").font(.system(size: 9)).foregroundStyle(AppColors.teal) }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
        .padding(8)
        .background(calendar.isDateInToday(day) ? AppColors.teal.opacity(0.06) : AppColors.panel)
        .overlay(Rectangle().stroke(AppColors.line.opacity(0.55), lineWidth: 0.5))
    }
}

struct TimelineView: View {
    @Environment(AppModel.self) private var model: AppModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                let entries = model.database.timeEntries.filter { $0.workspaceID == model.selection.selectedWorkspaceID }.sorted { $0.startedAt > $1.startedAt }
                if entries.isEmpty {
                    EmptyColumnHint(icon: "clock.arrow.circlepath", title: "还没有实际记录", message: "从任务详情启动正计时或番茄钟")
                        .padding(.top, 100)
                } else {
                    ForEach(entries) { entry in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(entry.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 10, weight: .semibold))
                                Text(formatDuration(entry.duration)).font(.system(size: 10, design: .monospaced)).foregroundStyle(AppColors.muted)
                            }
                            Rectangle().fill(entry.source == .pomodoro ? AppColors.coral : AppColors.teal).frame(width: 2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.title).font(.system(size: 13, weight: .medium))
                                Text(entry.source.title).font(.system(size: 10)).foregroundStyle(AppColors.muted)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        Divider().padding(.leading, 100)
                    }
                }
            }
            .padding(.bottom, 30)
        }
    }
}

struct TaskRow: View {
    @Environment(AppModel.self) private var model: AppModel
    let task: GTDTask
    let depth: Int
    let hasChildren: Bool
    let isExpanded: Bool
    @Binding var editingTask: GTDTask?
    @Binding var showTaskEditor: Bool
    let toggleExpanded: () -> Void

    var isSelected: Bool { model.isTaskSelected(task.id) }

    var body: some View {
        HStack(spacing: 8) {
            if depth > 0 {
                Rectangle().fill(AppColors.line).frame(width: 1).padding(.vertical, 5)
            }
            if hasChildren {
                Button(action: toggleExpanded) { Image(systemName: isExpanded ? "chevron.down" : "chevron.right") }
                    .buttonStyle(QuietIconButtonStyle(size: 18))
                    .help(isExpanded ? "折叠下级任务" : "展开下级任务")
            } else {
                Spacer().frame(width: 18)
            }
            Button { model.toggleTask(task) } label: {
                Image(systemName: task.status == .done ? "checkmark.square.fill" : "square")
                    .font(.system(size: 17))
                    .foregroundStyle(task.status == .done ? AppColors.teal : AppColors.muted)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.system(size: 13, weight: task.parentID == nil ? .medium : .regular))
                    .foregroundStyle(task.status.isFinished ? AppColors.muted : AppColors.ink)
                    .strikethrough(task.status == .done, color: AppColors.muted)
                    .lineLimit(2)
                HStack(spacing: 7) {
                    Circle().fill(Color(hex: task.priority.color)).frame(width: 7, height: 7)
                    if let project = model.project(for: task) {
                        Text(project.name).lineLimit(1)
                    }
                    if let start = task.plannedStart {
                        Text(start.formatted(date: .abbreviated, time: .shortened))
                    }
                    if !task.tags.isEmpty { Text(task.tags.map { "#\($0)" }.joined(separator: " ")) }
                }
                .font(.system(size: 10))
                .foregroundStyle(AppColors.muted)
            }
            Spacer(minLength: 4)
            RowActionButton(icon: "play.circle", color: AppColors.teal, title: "开始正计时") { model.startStopwatch(for: task) }
            RowActionButton(icon: "timer", color: AppColors.coral, title: "开始番茄钟") { model.startPomodoro(for: task) }
            RowActionButton(icon: "clock", color: AppColors.muted, title: "查看实际记录") { model.selectTask(task.id) }
        }
        .padding(.leading, CGFloat(depth * 20) + 8)
        .padding(.trailing, 8)
        .padding(.vertical, 11)
        .background(isSelected ? AppColors.mailSelected : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppColors.line.opacity(0.55))
                .frame(height: 0.5)
                .padding(.leading, CGFloat(depth * 20) + 8)
        }
        .contentShape(Rectangle())
        .onTapGesture { model.selectTask(task.id) }
        .contextMenu {
            Button("编辑任务") { editingTask = task; showTaskEditor = true }
            Button(task.status == .done ? "重新打开" : "完成任务") { model.toggleTask(task) }
            Divider()
            Button("删除任务", role: .destructive) { model.deleteTask(task) }
        }
    }
}

struct InspectorColumn: View {
    @Environment(AppModel.self) private var model: AppModel
    @Binding var editingTask: GTDTask?
    @Binding var showTaskEditor: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 22) {
                Image(systemName: "info.circle")
                    .foregroundStyle(AppColors.teal)
                Image(systemName: "list.bullet")
                Image(systemName: "paperclip")
                Image(systemName: "clock.arrow.circlepath")
                Spacer()
                Image(systemName: "ellipsis")
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(AppColors.muted)
            .padding(.horizontal, 20)
            .padding(.vertical, 15)
            Divider()
            if let task = model.selectedTask {
                TaskInspector(task: task, editingTask: $editingTask, showTaskEditor: $showTaskEditor)
            } else {
                EmptyColumnHint(icon: "cursorarrow.click.2", title: "选择一个任务", message: "任务的计划、笔记和实际记录会在这里展开")
                    .padding(.horizontal, 22)
            }
            Spacer()
        }
        .background(AppColors.panel)
    }
}

struct TaskInspector: View {
    @Environment(AppModel.self) private var model: AppModel
    let task: GTDTask
    @Binding var editingTask: GTDTask?
    @Binding var showTaskEditor: Bool
    @State private var note: String

    init(task: GTDTask, editingTask: Binding<GTDTask?>, showTaskEditor: Binding<Bool>) {
        self.task = task
        _editingTask = editingTask
        _showTaskEditor = showTaskEditor
        _note = State(initialValue: task.note)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    Text(task.title)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppColors.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button { editingTask = task; showTaskEditor = true } label: { Image(systemName: "square.and.pencil") }
                        .buttonStyle(QuietIconButtonStyle())
                        .help("编辑完整任务")
                }
                HStack(spacing: 8) {
                    Button { model.startStopwatch(for: task) } label: { Label("正计时", systemImage: "play.circle") }
                        .buttonStyle(PillButtonStyle(tint: AppColors.teal))
                    Button { model.startPomodoro(for: task) } label: { Label("番茄钟", systemImage: "timer") }
                        .buttonStyle(PillButtonStyle(tint: AppColors.coral))
                }
                InspectorField(icon: "circle.dotted", title: "状态") {
                    Picker("状态", selection: Binding(get: { task.status }, set: { var t = task; t.status = $0; model.updateTask(t) })) {
                        ForEach(TaskStatus.allCases) { status in Text(status.title).tag(status) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                InspectorField(icon: "calendar", title: "截止") {
                    if let deadline = task.deadline {
                        Text(deadline.formatted(date: .abbreviated, time: task.deadlinePrecision == .minute ? .shortened : .omitted))
                            .foregroundStyle(deadline < .now ? AppColors.coral : AppColors.ink)
                    } else { Text("未设置").foregroundStyle(AppColors.muted) }
                }
                InspectorField(icon: "flag", title: "优先级") {
                    Picker("优先级", selection: Binding(get: { task.priority }, set: { var t = task; t.priority = $0; model.updateTask(t) })) {
                        ForEach(Priority.allCases) { priority in
                            Label(priority.title, systemImage: "flag.fill").tag(priority)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                InspectorField(icon: "tag", title: "标签") {
                    if task.tags.isEmpty { Text("未设置").foregroundStyle(AppColors.muted) }
                    else { Text(task.tags.map { "#\($0)" }.joined(separator: "  ")).foregroundStyle(AppColors.teal) }
                }
                Divider().padding(.vertical, 2)
                Text("备注")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.ink)
                TextEditor(text: $note)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 115)
                    .background(AppColors.subtle, in: RoundedRectangle(cornerRadius: 10))
                    .onChange(of: note) { _, value in var t = task; t.note = value; model.updateTask(t) }
                ChildrenSummary(task: task)
                ActualRecords(task: task)
                Divider().padding(.vertical, 2)
                MetadataRows(task: task)
            }
            .padding(20)
        }
    }
}

struct TaskEditor: View {
    @Environment(AppModel.self) private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let task: GTDTask?
    @State private var title = ""
    @State private var status: TaskStatus = .open
    @State private var priority: Priority = .none
    @State private var actionList: ActionList = .nextAction
    @State private var note = ""
    @State private var tags = ""
    @State private var hasPlan = false
    @State private var hasPlannedEnd = false
    @State private var start = Date()
    @State private var end = Date()
    @State private var plannedPrecision: DeadlinePrecision = .date
    @State private var hasDeadline = false
    @State private var deadline = Date()
    @State private var deadlinePrecision: DeadlinePrecision = .date
    @State private var projectID: UUID?

    var isEditing: Bool { task != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(isEditing ? "编辑任务" : "新建任务")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.escape)
                Button(isEditing ? "保存" : "创建任务") { save() }
                    .buttonStyle(.borderedProminent)
                    .tint(AppColors.teal)
                    .keyboardShortcut(.return)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !planIsValid)
            }
            .padding(22)
            Divider()
            Form {
                Section("行动") {
                    TextField("下一步行动标题", text: $title)
                    Picker("项目", selection: $projectID) {
                        Text("无项目").tag(UUID?.none)
                        ForEach(model.currentProjects) { project in Text(project.name).tag(Optional(project.id)) }
                    }
                    if isEditing {
                        Picker("状态", selection: $status) {
                            ForEach(TaskStatus.allCases) { Text($0.title).tag($0) }
                        }
                    } else {
                        LabeledContent("状态", value: TaskStatus.open.title)
                    }
                    Picker("优先级", selection: $priority) { ForEach(Priority.allCases) { Text($0.title).tag($0) } }
                    Picker("行动列表", selection: $actionList) { ForEach(ActionList.allCases) { Text($0.title).tag($0) } }
                }
                Section("计划安排") {
                    Toggle("设置计划时间", isOn: $hasPlan)
                    if hasPlan {
                        Picker("精度", selection: $plannedPrecision) {
                            Text("只设置日期").tag(DeadlinePrecision.date)
                            Text("设置到分钟").tag(DeadlinePrecision.minute)
                        }
                        DatePicker("计划于", selection: $start, displayedComponents: plannedPrecision == .minute ? [.date, .hourAndMinute] : [.date])
                        Toggle("添加结束时间", isOn: $hasPlannedEnd)
                        if hasPlannedEnd {
                            DatePicker("结束", selection: $end, displayedComponents: plannedPrecision == .minute ? [.date, .hourAndMinute] : [.date])
                            if !planIsValid { Text("计划结束必须晚于计划时间").foregroundStyle(AppColors.coral) }
                        }
                    }
                    Toggle("设置截止时间", isOn: $hasDeadline)
                    if hasDeadline {
                        Picker("精度", selection: $deadlinePrecision) {
                            Text("只设置日期").tag(DeadlinePrecision.date)
                            Text("设置到分钟").tag(DeadlinePrecision.minute)
                        }
                        DatePicker("截止", selection: $deadline, displayedComponents: deadlinePrecision == .minute ? [.date, .hourAndMinute] : [.date])
                    }
                }
                Section("标签与笔记") {
                    TextField("标签，用逗号分隔", text: $tags)
                    TextEditor(text: $note).frame(minHeight: 100)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 520, height: 590)
        .onAppear { load() }
    }

    private func load() {
        guard let task else { return }
        title = task.title; status = task.status; priority = task.priority; actionList = task.actionList; note = task.note
        tags = task.tags.joined(separator: ", "); projectID = task.projectID
        if let startDate = task.plannedStart {
            hasPlan = true; start = startDate
            if let endDate = task.plannedEnd {
                hasPlannedEnd = true; end = endDate
            }
            plannedPrecision = task.plannedPrecision == .none ? .minute : task.plannedPrecision
        }
        if let deadlineDate = task.deadline { hasDeadline = true; deadline = deadlineDate; deadlinePrecision = task.deadlinePrecision }
    }

    private func save() {
        let parsedTags = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if var existing = task {
            existing.title = title; existing.status = status; existing.priority = priority; existing.actionList = actionList; existing.note = note; existing.tags = parsedTags; existing.projectID = projectID
            existing.plannedStart = normalizedPlan?.start; existing.plannedEnd = normalizedPlan?.end
            existing.plannedPrecision = hasPlan ? plannedPrecision : .none
            existing.deadline = hasDeadline ? deadline : nil; existing.deadlinePrecision = hasDeadline ? deadlinePrecision : .none
            model.updateTask(existing)
        } else {
            model.addTask(title: title, projectID: projectID, status: .open, priority: priority, actionList: actionList,
                          plannedStart: normalizedPlan?.start, plannedEnd: normalizedPlan?.end,
                          plannedPrecision: hasPlan ? plannedPrecision : .none,
                          deadline: hasDeadline ? deadline : nil,
                          deadlinePrecision: hasDeadline ? deadlinePrecision : .none,
                          tags: parsedTags, note: note)
        }
        dismiss()
    }

    private var planIsValid: Bool {
        guard hasPlan else { return true }
        return TaskDateNormalizer.normalizedPlan(
            start: start,
            end: hasPlannedEnd ? end : nil,
            precision: plannedPrecision
        ) != nil
    }

    private var normalizedPlan: (start: Date, end: Date?)? {
        guard hasPlan, planIsValid else { return nil }
        return TaskDateNormalizer.normalizedPlan(
            start: start,
            end: hasPlannedEnd ? end : nil,
            precision: plannedPrecision
        )
    }
}

struct NewProjectSheet: View {
    @Environment(AppModel.self) private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var category = "个人"

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("新建项目").font(.system(size: 18, weight: .semibold))
            TextField("项目名称", text: $name)
            TextField("项目分类", text: $category)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("创建") { model.addProject(name: name, category: category); dismiss() }.buttonStyle(.borderedProminent).tint(AppColors.teal).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("GTD Planner 设置").font(.system(size: 18, weight: .semibold)); Spacer(); Button("完成") { dismiss() } }
            Form {
                Section("本地数据") {
                    LabeledContent("SwiftData 存储") { Text(model.storage.storeURL.path).font(.system(size: 11, design: .monospaced)).foregroundStyle(AppColors.muted).lineLimit(2) }
                    LabeledContent("工作区") { Text(model.database.workspaces.map(\.name).joined(separator: "、")) }
                }
                Section("关于") {
                    Text("独立版使用本地 SwiftData 持久化与 JSON 备份；计划时间、截止时间与实际时间记录始终分开保存。")
                        .foregroundStyle(AppColors.muted)
                }
            }
            .formStyle(.grouped)
        }
        .padding(22)
        .frame(width: 560, height: 330)
    }
}

struct HeaderMark: View {
    let title: String
    let subtitle: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 21)).foregroundStyle(AppColors.teal)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(subtitle).font(.system(size: 10)).foregroundStyle(AppColors.muted)
            }
        }
    }
}

struct SearchField: View {
    @Binding var text: String
    var placeholder = "搜索"
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").foregroundStyle(AppColors.muted)
            TextField(placeholder, text: $text).textFieldStyle(.plain)
            if !text.isEmpty { Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(AppColors.muted) }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.clear)
                .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }
}

struct SidebarSectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(AppColors.sectionTitle)
            .padding(.horizontal, 4)
            .padding(.top, 8)
            .padding(.bottom, 6)
    }
}

struct AppleSidebarRow: View {
    let icon: String
    let title: String
    let selected: Bool
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected ? AppColors.sidebarSelection : .clear)
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(selected ? AppColors.sidebarSelectedInk : AppColors.sidebarInk)
                        .frame(width: 18)
                    Text(title)
                        .font(.system(size: 13, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? AppColors.sidebarSelectedInk : AppColors.sidebarInk)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text("\(count)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(selected ? AppColors.sidebarSelectedInk : AppColors.muted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(AppColors.sidebarCountBackground, in: Capsule())
                }
                // Keep the selected row's text on the semantic label color.
                // Teal is carried by the quiet selection surface and count.
                .padding(.horizontal, 8)
            }
            .frame(height: 28)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(AppleSidebarButtonStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct AppleSidebarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 1), value: configuration.isPressed)
    }
}

struct SmartListRow: View {
    let item: SmartList
    let count: Int
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: item.icon).frame(width: 18)
                Text(item.title)
                Spacer()
                Text("\(count)").font(.system(size: 11, weight: .semibold)).foregroundStyle(AppColors.muted).padding(.horizontal, 7).padding(.vertical, 4).background(AppColors.subtle, in: Capsule())
            }
            .font(.system(size: 12, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? AppColors.teal : AppColors.ink)
            .padding(.horizontal, 11).padding(.vertical, 8)
            .background(selected ? AppColors.teal.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain)
    }
}

struct WorkflowRow: View {
    let icon: String; let title: String; let action: () -> Void
    var body: some View { Button(action: action) { Label(title, systemImage: icon).font(.system(size: 12)).foregroundStyle(AppColors.ink).padding(.horizontal, 11).padding(.vertical, 8) }.buttonStyle(.plain) }
}

struct CategoryHeader: View {
    let category: String; let collapsed: Bool; let action: () -> Void
    var body: some View { Button(action: action) { HStack(spacing: 7) { Image(systemName: collapsed ? "chevron.right" : "chevron.down").font(.system(size: 9, weight: .bold)); Text(category).font(.system(size: 11, weight: .semibold)); Spacer() }.foregroundStyle(AppColors.muted).padding(.horizontal, 8).padding(.top, 13).padding(.bottom, 4) }.buttonStyle(.plain) }
}

struct ProjectRow: View {
    let title: String; let icon: String; let count: Int; let color: Color; let selected: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .foregroundStyle(selected ? AppColors.selectionInk : AppColors.muted)
                    .frame(width: 18)
                Text(title).lineLimit(1)
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(selected ? AppColors.selectionInk.opacity(0.9) : AppColors.muted)
                }
            }
            .font(.system(size: 13, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? AppColors.selectionInk : AppColors.ink)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(selected ? AppColors.selection : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct EmptyColumnHint: View {
    let icon: String
    let title: String
    let message: String
    let iconColor: Color

    init(
        icon: String,
        title: String,
        message: String,
        iconColor: Color = AppColors.teal.opacity(0.65)
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.iconColor = iconColor
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 29, weight: .light))
                .foregroundStyle(iconColor)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(AppColors.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
    }
}

struct RowActionButton: View {
    let icon: String; let color: Color; let title: String; let action: () -> Void
    var body: some View { Button(action: action) { Image(systemName: icon).font(.system(size: 13)).foregroundStyle(color) }.buttonStyle(.plain).help(title) }
}

struct InspectorField<Content: View>: View {
    let icon: String; let title: String; @ViewBuilder let content: () -> Content
    var body: some View { HStack { Image(systemName: icon).frame(width: 18).foregroundStyle(AppColors.muted); Text(title).font(.system(size: 12)); Spacer(); content() }.foregroundStyle(AppColors.ink) }
}

struct ChildrenSummary: View {
    @Environment(AppModel.self) private var model: AppModel
    let task: GTDTask
    var body: some View {
        let children = model.children(of: task)
        if !children.isEmpty { VStack(alignment: .leading, spacing: 7) { Text("子任务").font(.system(size: 12, weight: .semibold)); Text("已完成 \(children.filter { $0.status == .done }.count) / \(children.count)").font(.system(size: 11)).foregroundStyle(AppColors.muted); ProgressView(value: Double(children.filter { $0.status == .done }.count), total: Double(children.count)).tint(AppColors.teal) } }
    }
}

struct ActualRecords: View {
    @Environment(AppModel.self) private var model: AppModel
    let task: GTDTask
    var body: some View {
        let entries = model.entries(for: task)
        VStack(alignment: .leading, spacing: 7) {
            HStack { Text("实际记录").font(.system(size: 12, weight: .semibold)); Spacer(); Text(totalDuration(entries)).font(.system(size: 11)).foregroundStyle(AppColors.muted) }
            if entries.isEmpty { Text("还没有时间记录").font(.system(size: 11)).foregroundStyle(AppColors.muted) }
            ForEach(entries.prefix(3)) { entry in HStack { Image(systemName: entry.source.icon).foregroundStyle(entry.source == .pomodoro ? AppColors.coral : AppColors.teal); Text(entry.startedAt.formatted(date: .abbreviated, time: .shortened)); Spacer(); Text(formatDuration(entry.duration)).foregroundStyle(AppColors.muted) }.font(.system(size: 10)) }
        }
    }
    private func totalDuration(_ entries: [TimeEntry]) -> String { formatDuration(entries.reduce(0) { $0 + $1.duration }) }
}

struct MetadataRows: View {
    let task: GTDTask
    var body: some View { VStack(spacing: 8) { meta("创建时间", task.createdAt); meta("更新时间", task.updatedAt); if let plannedStart = task.plannedStart { meta("计划时间", plannedStart); if let plannedEnd = task.plannedEnd { meta("计划结束", plannedEnd) } } } }
    private func meta(_ label: String, _ date: Date) -> some View { HStack { Text(label); Spacer(); Text(date.formatted(date: .numeric, time: .shortened)) }.font(.system(size: 10)).foregroundStyle(AppColors.muted) }
}

struct ActiveTimerBar: View {
    @Environment(AppModel.self) private var model: AppModel
    let timer: ActiveTimer
    var body: some View { HStack(spacing: 10) { Image(systemName: timer.mode == .pomodoro ? "timer" : "stopwatch").foregroundStyle(timer.mode == .pomodoro ? AppColors.coral : AppColors.teal); Text(timer.title).lineLimit(1); Spacer(); Text(formatDuration(model.timerElapsed())).font(.system(size: 12, weight: .semibold, design: .monospaced)); Button { timer.pausedAt == nil ? model.pauseTimer() : model.resumeTimer() } label: { Image(systemName: timer.pausedAt == nil ? "pause.fill" : "play.fill") }.buttonStyle(.plain); Button { model.stopTimer() } label: { Image(systemName: "stop.fill") }.buttonStyle(.plain) }.font(.system(size: 12)).padding(.horizontal, 16).padding(.vertical, 10).background(timer.mode == .pomodoro ? AppColors.coral.opacity(0.08) : AppColors.teal.opacity(0.08)) }
}

struct TimerCapsule: View {
    let timer: ActiveTimer; let elapsed: TimeInterval
    var body: some View {
        let tint = timer.mode == .pomodoro ? AppColors.coral : AppColors.teal
        return HStack(spacing: 6) {
            Image(systemName: timer.mode == .pomodoro ? "timer" : "stopwatch")
            Text(formatDuration(elapsed))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background {
            Capsule()
                .fill(.clear)
                .glassEffect(.clear.tint(tint.opacity(0.13)).interactive(false), in: Capsule())
        }
    }
}

struct QuietIconButtonStyle: ButtonStyle {
    var size: CGFloat = 28
    func makeBody(configuration: Configuration) -> some View { configuration.label.font(.system(size: 13, weight: .medium)).foregroundStyle(AppColors.muted).frame(width: size, height: size).background(configuration.isPressed ? AppColors.subtle : .clear, in: RoundedRectangle(cornerRadius: 7)).scaleEffect(configuration.isPressed ? 0.94 : 1) }
}

struct ChromeIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(AppColors.ink)
            .frame(width: 34, height: 34)
            .glassEffect(.regular.interactive(), in: Circle())
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 1), value: configuration.isPressed)
    }
}

struct RailIconStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label.font(.system(size: 17)).foregroundStyle(AppColors.muted).frame(width: 38, height: 38).background(configuration.isPressed ? AppColors.subtle : .clear, in: RoundedRectangle(cornerRadius: 11)).scaleEffect(configuration.isPressed ? 0.95 : 1) }
}

struct PillButtonStyle: ButtonStyle {
    let tint: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                Capsule()
                    .fill(.clear)
                    .glassEffect(
                        .clear
                            .tint(tint.opacity(configuration.isPressed ? 0.20 : 0.12))
                            .interactive(),
                        in: Capsule()
                    )
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

enum AppColors {
    // Use AppKit's dynamic semantic colors so light/dark mode and contrast
    // settings follow the macOS appearance instead of a fixed beige palette.
    static let canvas = Color(nsColor: NSColor.textBackgroundColor)
    static let panel = Color(nsColor: NSColor.textBackgroundColor)
    static let sidebar = Color(nsColor: NSColor.windowBackgroundColor)
    static let sidebarRow = Color(nsColor: NSColor.controlBackgroundColor)
    static let sidebarSelected = Color(nsColor: NSColor.unemphasizedSelectedContentBackgroundColor)
    static let sidebarStroke = Color(nsColor: NSColor.separatorColor)
    static let sidebarInk = Color(nsColor: NSColor.labelColor)
    static let sidebarSelection = Color(red: 0.86, green: 0.95, blue: 0.93)
    static let sidebarSelectedInk = Color(red: 0.04, green: 0.32, blue: 0.29)
    // Sidebar selection follows the app's restrained teal accent. The main
    // content selection remains the native macOS blue, like Mail.
    static let sidebarAccent = Color(nsColor: NSColor.systemTeal)
    static let sidebarCountBackground = Color(nsColor: NSColor.quaternaryLabelColor).opacity(0.14)
    static let selection = Color(nsColor: NSColor.selectedContentBackgroundColor)
    static let selectionInk = Color(nsColor: NSColor.alternateSelectedControlTextColor)
    static let mailSelected = Color(nsColor: NSColor.unemphasizedSelectedContentBackgroundColor)
    static let sectionTitle = Color(nsColor: NSColor.secondaryLabelColor)
    static let row = Color(nsColor: NSColor.controlBackgroundColor)
    static let subtle = Color(nsColor: NSColor.controlBackgroundColor)
    static let line = Color(nsColor: NSColor.separatorColor)
    static let ink = Color(nsColor: NSColor.labelColor)
    static let muted = Color(nsColor: NSColor.secondaryLabelColor)
    static let teal = Color(nsColor: NSColor.systemTeal)
    static let coral = Color(nsColor: NSColor.systemOrange)
}

extension Color {
    init(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var integer: UInt64 = 0
        Scanner(string: value).scanHexInt64(&integer)
        let red = Double((integer >> 16) & 0xFF) / 255
        let green = Double((integer >> 8) & 0xFF) / 255
        let blue = Double(integer & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}

private func formatDuration(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds.rounded()))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secs = total % 60
    return hours > 0 ? String(format: "%02d:%02d:%02d", hours, minutes, secs) : String(format: "%02d:%02d", minutes, secs)
}
