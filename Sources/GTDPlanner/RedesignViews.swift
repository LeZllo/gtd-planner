import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The selected visual direction: a native macOS workspace with a compact
/// source sidebar, fast workspace shelf, project browser, task outline, and
/// task inspector. The existing data model remains the source of truth.
struct ModernContentView: View {
    @Environment(AppModel.self) private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showNewTaskEditor = false
    @State private var projectSearchActivated = false
    @FocusState private var projectSearchFocused: Bool
    @State private var projectSearchFrame: CGRect = .zero
    @State private var taskSearchExpanded = false
    @State private var projectTaskQuery = ""
    @State private var taskSearchFrame: CGRect = .zero
    @FocusState private var quickTaskFocused: Bool
    @State private var quickTaskFrame: CGRect = .zero
    @State private var quickTaskDraft = ModernQuickTaskDraft()
    @FocusState private var taskTitleFocusedID: UUID?
    @State private var editingTaskTitleID: UUID?
    @State private var taskTitleFrame: CGRect = .zero
    @FocusState private var inspectorNoteFocused: Bool
    @State private var inspectorNoteFrame: CGRect = .zero
    @State private var noticeDismissTask: Task<Void, Never>?

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 0) {
            ModernSourceSidebar()
                .frame(width: 78)
            Divider()

            if let focusMode = model.selection.focusMode {
                VStack(spacing: 0) {
                    ModernTopBar(
                        onNewTask: {
                            showNewTaskEditor = true
                        }
                    )
                    C234FocusWorkspaceView(mode: focusMode)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else if let archive = model.selection.selectedArchive {
                VStack(spacing: 0) {
                    ModernTopBar(
                        onNewTask: {
                            showNewTaskEditor = true
                        }
                    )
                    ModernArchivePane(item: archive)
                        .frame(maxWidth: .infinity)
                }
            } else if model.selection.selectedOrganization == .inbox {
                VStack(spacing: 0) {
                    ModernTopBar(
                        onNewTask: {
                            showNewTaskEditor = true
                        }
                    )
                    ModernInboxWorkspace(
                        taskSearchExpanded: $taskSearchExpanded,
                        taskSearchQuery: $projectTaskQuery,
                        quickTaskDraft: $quickTaskDraft,
                        quickTaskFocused: $quickTaskFocused,
                        editingTaskTitleID: $editingTaskTitleID,
                        taskTitleFocusedID: $taskTitleFocusedID,
                        inspectorNoteFocused: $inspectorNoteFocused
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else if model.selection.selectedOrganization == nil,
                      model.selection.selectedSmartList == .today {
                VStack(spacing: 0) {
                    ModernTopBar(
                        onNewTask: {
                            showNewTaskEditor = true
                        }
                    )

                    SwiftUI.TimelineView(.periodic(from: .now, by: 60)) { context in
                        HStack(spacing: 0) {
                            TodayExecutionPane(
                                quickTaskDraft: $quickTaskDraft,
                                quickTaskFocused: $quickTaskFocused,
                                day: Calendar.current.startOfDay(for: context.date)
                            )
                            .frame(minWidth: 650, maxWidth: .infinity, maxHeight: .infinity)
                            Divider()
                            TodayContextPane(inspectorNoteFocused: $inspectorNoteFocused)
                                .frame(width: 390)
                        }
                        .id("today-\(model.selection.selectedWorkspaceID)-\(Calendar.current.startOfDay(for: context.date))")
                    }
                }
            } else if isUpcomingPlanning {
                VStack(spacing: 0) {
                    ModernTopBar(onNewTask: { showNewTaskEditor = true })
                    SwiftUI.TimelineView(.periodic(from: .now, by: 60)) { context in
                        UpcomingPlanningWorkspace(
                            horizon: model.selection.selectedSmartList == .tomorrow ? .tomorrow : .nextSevenDays,
                            now: context.date,
                            quickTaskDraft: $quickTaskDraft,
                            quickTaskFocused: $quickTaskFocused,
                            inspectorNoteFocused: $inspectorNoteFocused
                        )
                        .id("future-\(model.selection.selectedWorkspaceID)-\(model.selection.selectedSmartList.rawValue)-\(Calendar.current.startOfDay(for: context.date))")
                    }
                }
            } else if model.selection.selectedOrganization == nil,
                      model.selection.selectedSmartList == .fourSquares {
                VStack(spacing: 0) {
                    ModernTopBar(onNewTask: { showNewTaskEditor = true })
                    SwiftUI.TimelineView(.periodic(from: .now, by: 60)) { context in
                        QuadrantWorkspace(now: context.date, inspectorNoteFocused: $inspectorNoteFocused)
                            .id("quadrants-\(model.selection.selectedWorkspaceID)")
                    }
                }
            } else if model.selection.selectedOrganization == nil,
                      model.selection.selectedSmartList == .calendar {
                VStack(spacing: 0) {
                    ModernTopBar(onNewTask: { showNewTaskEditor = true })
                    SwiftUI.TimelineView(.periodic(from: .now, by: 60)) { context in
                        CalendarPlanningWorkspace(now: context.date, inspectorNoteFocused: $inspectorNoteFocused)
                            .id("calendar-\(model.selection.selectedWorkspaceID)")
                    }
                }
            } else if model.selection.selectedOrganization == .tags {
                ModernTagPane()
                    .frame(width: 300)
                Divider()

                VStack(spacing: 0) {
                    ModernTopBar(
                        onNewTask: {
                            showNewTaskEditor = true
                        }
                    )

                    HStack(spacing: 0) {
                        ModernTagTaskPane(
                            taskSearchExpanded: $taskSearchExpanded,
                            taskSearchQuery: $projectTaskQuery,
                            quickTaskDraft: $quickTaskDraft,
                            quickTaskFocused: $quickTaskFocused,
                            editingTaskTitleID: $editingTaskTitleID,
                            taskTitleFocusedID: $taskTitleFocusedID
                        )
                        .frame(minWidth: 480, maxWidth: .infinity)
                        Divider()
                        ModernTagInspectorPane(inspectorNoteFocused: $inspectorNoteFocused)
                            .frame(width: 390)
                    }
                }
            } else {
                ModernProjectPane(
                    projectSearchActivated: $projectSearchActivated,
                    projectSearchFocused: $projectSearchFocused
                )
                    .frame(width: 300)
                Divider()

                VStack(spacing: 0) {
                    ModernTopBar(
                        onNewTask: {
                            showNewTaskEditor = true
                        }
                    )

                    if model.selection.plannerView == .timeline,
                       model.selection.selectedProjectID != nil {
                        ModernGanttPane()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        HStack(spacing: 0) {
                            ModernTaskPane(
                                taskSearchExpanded: $taskSearchExpanded,
                                projectTaskQuery: $projectTaskQuery,
                                quickTaskDraft: $quickTaskDraft,
                                quickTaskFocused: $quickTaskFocused,
                                editingTaskTitleID: $editingTaskTitleID,
                                taskTitleFocusedID: $taskTitleFocusedID
                            )
                                .frame(minWidth: 480, maxWidth: .infinity)
                            Divider()
                            ModernInspectorPane(inspectorNoteFocused: $inspectorNoteFocused)
                                .frame(width: 390)
                        }
                    }
                }
            }
        }
        // Give the root a concrete hit-test shape so the outside-tap gesture
        // also receives clicks in blank regions and alongside child controls.
        .contentShape(Rectangle())
        .frame(minWidth: 1180, minHeight: 680)
        .background(ModernPalette.canvas)
        .tint(ModernPalette.accent)
        .preferredColorScheme(model.preferences.appearance.colorScheme)
        .focusedSceneValue(\.plannerTaskModel, model)
        .focusedSceneValue(\.plannerNewTaskAction, { showNewTaskEditor = true })
        .ignoresSafeArea(.container, edges: .top)
        .coordinateSpace(.named("content-root"))
        .onPreferenceChange(ProjectSearchFramePreferenceKey.self) { frame in
            projectSearchFrame = frame
        }
        .onPreferenceChange(TaskSearchFramePreferenceKey.self) { frame in
            taskSearchFrame = frame
        }
        .onPreferenceChange(QuickTaskFramePreferenceKey.self) { frame in
            quickTaskFrame = frame
        }
        .onPreferenceChange(TaskTitleFramePreferenceKey.self) { frame in
            taskTitleFrame = frame
        }
        .onPreferenceChange(InspectorNoteFramePreferenceKey.self) { frame in
            inspectorNoteFrame = frame
        }
        .simultaneousGesture(
            SpatialTapGesture()
                .onEnded { value in
                    if projectSearchFocused && !projectSearchFrame.contains(value.location) {
                        projectSearchFocused = false
                    }
                    if taskSearchExpanded && !taskSearchFrame.contains(value.location) {
                        withAnimation(reduceMotion ? .easeOut(duration: 0.10) : .snappy(duration: 0.22)) {
                            taskSearchExpanded = false
                            projectTaskQuery = ""
                        }
                    }
                    if !quickTaskFrame.contains(value.location) {
                        quickTaskFocused = false
                        if quickTaskDraft.hasStagedContent && !isUpcomingPlanning {
                            quickTaskDraft.reset()
                        }
                    }
                    if taskTitleFocusedID != nil && !taskTitleFrame.contains(value.location) {
                        taskTitleFocusedID = nil
                    }
                    if inspectorNoteFocused && !inspectorNoteFrame.contains(value.location) {
                        inspectorNoteFocused = false
                    }
                }
        )
        .sheet(isPresented: $showNewTaskEditor) {
            TaskEditor(task: nil, initialPlannedDay: model.defaultTaskPlanningDay())
                .environment(model)
        }
        .onChange(of: model.showNewTask) { _, value in
            guard value else { return }
            showNewTaskEditor = true
            model.showNewTask = false
        }
        .onChange(of: model.currentTaskSelectionContext) { _, _ in
            showNewTaskEditor = false
            quickTaskDraft.reset()
            if let day = model.defaultTaskPlanningDay() {
                quickTaskDraft.plannedStart = day
                quickTaskDraft.plannedEnd = day
            }
            quickTaskFocused = false
            projectTaskQuery = ""
            taskSearchExpanded = false
        }
        .onChange(of: model.selection.focusMode) { _, _ in
            showNewTaskEditor = false
            quickTaskDraft.reset()
            quickTaskFocused = false
        }
        .onChange(of: model.selection.selectedProjectID) { _, _ in
            taskTitleFocusedID = nil
            editingTaskTitleID = nil
        }
        .onChange(of: model.selection.selectedTag) { _, _ in
            taskTitleFocusedID = nil
            editingTaskTitleID = nil
            projectTaskQuery = ""
            taskSearchExpanded = false
        }
        .onChange(of: model.selection.taskSelection?.taskID) { _, _ in
            inspectorNoteFocused = false
        }
        .onChange(of: model.notice) { _, value in
            noticeDismissTask?.cancel()
            guard value != nil else { return }
            noticeDismissTask = Task {
                try? await Task.sleep(for: .seconds(2.4))
                guard !Task.isCancelled else { return }
                model.notice = nil
            }
        }
        .onDisappear { noticeDismissTask?.cancel() }
        .alert(
            model.pendingDeletion?.title ?? "",
            isPresented: Binding(
                get: { model.pendingDeletion != nil },
                set: { if !$0 { model.pendingDeletion = nil } }
            )
        ) {
            if let request = model.pendingDeletion {
                Button(request.confirmTitle, role: .destructive) {
                    model.performDeletion(request)
                }
            }
            Button("取消", role: .cancel) { model.pendingDeletion = nil }
        } message: {
            Text(model.pendingDeletion?.message ?? "")
        }
        .overlay(alignment: .bottomTrailing) {
            ZStack(alignment: .bottomTrailing) {
                if let notice = model.notice {
                    Text(notice)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ModernPalette.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.clear, in: Capsule())
                        .plannerControlSurface(in: Capsule())
                        .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
                        .padding(18)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .animation(
                reduceMotion ? .easeOut(duration: 0.08) : .snappy(duration: 0.22),
                value: model.notice
            )
        }
    }

    private var isUpcomingPlanning: Bool {
        model.selection.selectedOrganization == nil && model.selection.focusMode == nil
            && model.selection.selectedArchive == nil
            && (model.selection.selectedSmartList == .tomorrow || model.selection.selectedSmartList == .recent)
    }
}

struct ModernTopBar: View {
    @Environment(\.openSettings) private var openSettings
    @Environment(AppModel.self) private var model: AppModel
    let onNewTask: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                Spacer(minLength: 24)

                Button { openFocusWorkspace(.stopwatch) } label: {
                    Label("正计时", systemImage: "stopwatch")
                }
                .buttonStyle(ModernToolbarButtonStyle(
                    tint: ModernPalette.blue,
                    selected: model.selection.focusMode == .stopwatch
                ))
                .help("打开正计时页面")

                Button { openFocusWorkspace(.pomodoro) } label: {
                    Label("番茄钟", systemImage: "timer")
                }
                .buttonStyle(ModernToolbarButtonStyle(
                    tint: ModernPalette.red,
                    selected: model.selection.focusMode == .pomodoro
                ))
                .help("打开番茄钟页面")

                HStack(spacing: 4) {
                    Button {
                        model.selection.focusMode = nil
                        model.selection.plannerView = .list
                    } label: {
                        Label("任务", systemImage: "checklist")
                    }
                    .buttonStyle(ModernToolbarButtonStyle(tint: ModernPalette.blue, selected: model.selection.plannerView == .list))

                    Button {
                        guard model.selection.selectedProjectID != nil else {
                            model.notice = "请先在项目栏选择一个项目"
                            return
                        }
                        model.selection.focusMode = nil
                        model.selection.plannerView = .timeline
                    } label: {
                        Label("甘特图", systemImage: "chart.bar.xaxis")
                    }
                    .buttonStyle(ModernToolbarButtonStyle(tint: ModernPalette.ink, selected: model.selection.plannerView == .timeline))
                    .disabled(model.selection.selectedProjectID == nil)
                    .opacity(model.selection.selectedProjectID == nil ? 0.42 : 1)
                    .help(model.selection.selectedProjectID == nil ? "请先选择一个项目" : "打开项目甘特图")
                }

                Menu {
                    Button("新建任务", systemImage: "checkmark.circle", action: onNewTask)
                    Button("设置…", systemImage: "gearshape") { openSettings() }
                    Button("导出本地备份…", systemImage: "square.and.arrow.up") { model.exportDatabase() }
                    Button("恢复备份（替换全部数据）…", systemImage: "square.and.arrow.down") { model.importDatabase() }
                    Button("从 Obsidian 迁移（替换全部数据）…", systemImage: "doc.badge.arrow.up") { model.importObsidianVault() }
                } label: {
                    Label("新建", systemImage: "plus")
                        .padding(.trailing, 2)
                }
                .menuStyle(.borderlessButton)
                .buttonStyle(ModernToolbarButtonStyle(tint: ModernPalette.ink))
            }
        }
        .font(.system(size: 13, weight: .semibold))
        .padding(.horizontal, 22)
        .frame(height: 78)
        .background(ModernPalette.canvas)
    }

    private func openFocusWorkspace(_ mode: TimerMode) {
        if let activeTimer = model.activeTimer, activeTimer.mode != mode {
            model.selection.focusMode = activeTimer.mode
            model.notice = activeTimer.mode == .stopwatch
                ? "请先停止当前正计时，再切换到番茄钟"
                : "请先停止当前番茄钟，再切换到正计时"
            return
        }
        model.selection.focusMode = mode
    }
}

struct ModernToolbarButtonStyle: ButtonStyle {
    let tint: Color
    var selected = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(selected ? tint : ModernPalette.ink)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .plannerControlSurface(in: Capsule(), tint: selected ? tint.opacity(0.20) : nil, interactive: true, selected: selected)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct ModernWorkspaceShelf: View {
    @Environment(AppModel.self) private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showWorkspacePopover = false
    @State private var showWorkspaceManager = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(model.quickWorkspaceItems) { workspace in
                Button {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
                        model.selectWorkspace(workspace.id)
                    }
                } label: {
                    Image(systemName: workspace.symbolName)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(model.selection.selectedWorkspaceID == workspace.id ? ModernPalette.blue : ModernPalette.ink)
                        .frame(width: 38, height: 38)
                        .background(
                            model.selection.selectedWorkspaceID == workspace.id
                                ? ModernPalette.blue.opacity(0.10)
                                : .clear,
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(workspace.name)
                .accessibilityHint("切换到此工作区")
                .help(workspace.name)
                .contextMenu {
                    Button(model.isWorkspacePinned(workspace.id) ? "取消固定" : "固定到快捷切换") {
                        model.togglePinnedWorkspace(workspace.id)
                    }
                    Button("删除工作区", role: .destructive) {
                        model.requestDeleteWorkspace(workspace)
                    }
                }
            }

            Divider()
                .frame(height: 18)
                .padding(.horizontal, 2)

            Button {
                model.showNewWorkspace = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(ModernPalette.muted)
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("新建工作区")
            .help("新建工作区")

            Button {
                showWorkspacePopover.toggle()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ModernPalette.muted)
                    .frame(width: 24, height: 38)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("全部工作区")
            .accessibilityHint("搜索、切换或管理工作区")
            .help("全部工作区")
            .popover(isPresented: $showWorkspacePopover, arrowEdge: .top) {
                WorkspaceChooserPopover(
                    onManage: {
                        showWorkspacePopover = false
                        showWorkspaceManager = true
                    },
                    onSelect: {
                        showWorkspacePopover = false
                    }
                )
                    .environment(model)
            }
        }
        .padding(5)
        .background(.clear, in: Capsule())
        .plannerControlSurface(in: Capsule())
        .sheet(isPresented: $showWorkspaceManager) {
            WorkspaceManagerPane {
                showWorkspaceManager = false
            }
            .environment(model)
        }
    }
}

struct WorkspaceChooserPopover: View {
    @Environment(AppModel.self) private var model: AppModel
    let onManage: () -> Void
    let onSelect: () -> Void
    @State private var query = ""

    private var filteredWorkspaces: [Workspace] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return model.orderedWorkspaces }
        return model.orderedWorkspaces.filter { workspace in
            workspace.name.localizedCaseInsensitiveContains(needle)
        }
    }

    private var quickItems: [Workspace] {
        let ids = Set(model.quickWorkspaceItems.map(\.id))
        return filteredWorkspaces.filter { ids.contains($0.id) }
    }

    private var otherItems: [Workspace] {
        let ids = Set(model.quickWorkspaceItems.map(\.id))
        return filteredWorkspaces.filter { !ids.contains($0.id) }
    }

    var body: some View {
        chooserBody
        .frame(width: 350, height: 500)
    }

    private var chooserBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("工作区")
                        .font(.system(size: 17, weight: .semibold))
                    Text("快速切换当前工作环境")
                        .font(.system(size: 11))
                        .foregroundStyle(ModernPalette.muted)
                }
                Spacer()
                Button("管理") {
                    onManage()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ModernPalette.blue)
            }

            SearchField(text: $query, placeholder: "搜索工作区")

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if !quickItems.isEmpty {
                        WorkspacePopoverSectionTitle(title: "快捷切换")
                        ForEach(quickItems) { workspace in
                            WorkspaceChooserRow(workspace: workspace) {
                                // Selecting a workspace completes the popover's
                                // primary action, so the content columns can
                                // immediately become the user's new context.
                                onSelect()
                            }
                        }
                    }

                    if !otherItems.isEmpty {
                        WorkspacePopoverSectionTitle(title: "全部工作区")
                            .padding(.top, quickItems.isEmpty ? 0 : 6)
                        ForEach(otherItems) { workspace in
                            WorkspaceChooserRow(workspace: workspace) {
                                onSelect()
                            }
                        }
                    }

                    if filteredWorkspaces.isEmpty {
                        EmptyColumnHint(icon: "magnifyingglass", title: "没有匹配的工作区", message: "尝试搜索其他名称")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 30)
                    }
                }
            }

            Divider()

            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(ModernPalette.muted)
                Text("快捷切换最多固定三个工作区")
                    .font(.system(size: 11))
                    .foregroundStyle(ModernPalette.muted)
                Spacer()
                Button("管理顺序…") {
                    onManage()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ModernPalette.blue)
            }
        }
        .padding(16)
    }
}

struct WorkspacePopoverSectionTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(ModernPalette.muted)
            .textCase(.uppercase)
    }
}

struct WorkspaceChooserRow: View {
    @Environment(AppModel.self) private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let workspace: Workspace
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
                    model.selectWorkspace(workspace.id)
                }
                onSelect()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: workspace.symbolName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color(hex: workspace.colorHex))
                        .frame(width: 24, height: 24)
                        .background(Color(hex: workspace.colorHex).opacity(0.10), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(workspace.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(ModernPalette.ink)
                            .lineLimit(1)
                        Text("\(model.projectCount(for: workspace.id)) 个项目")
                            .font(.system(size: 10))
                            .foregroundStyle(ModernPalette.muted)
                    }

                    Spacer(minLength: 6)

                    if model.selection.selectedWorkspaceID == workspace.id {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(ModernPalette.blue)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                model.togglePinnedWorkspace(workspace.id)
            } label: {
                Image(systemName: model.isWorkspacePinned(workspace.id) ? "pin.fill" : "pin")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(model.isWorkspacePinned(workspace.id) ? ModernPalette.blue : ModernPalette.muted)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help(model.isWorkspacePinned(workspace.id) ? "取消固定" : "固定到快捷切换")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            model.selection.selectedWorkspaceID == workspace.id ? ModernPalette.blue.opacity(0.10) : .clear,
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
    }
}

struct WorkspaceManagerPane: View {
    @Environment(AppModel.self) private var model: AppModel
    let onDone: () -> Void
    @State private var query = ""
    @State private var dragState: WorkspaceDragState?
    @State private var workspaceFrames: [UUID: CGRect] = [:]

    private var workspaces: [Workspace] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return model.orderedWorkspaces }
        return model.orderedWorkspaces.filter { $0.name.localizedCaseInsensitiveContains(needle) }
    }

    private var isReorderingEnabled: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button(action: onDone) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(ModernPalette.blue)
                .help("返回工作区")

                Text("管理工作区")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Button {
                    model.showNewWorkspace = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .foregroundStyle(ModernPalette.blue)
                .help("新建工作区")
            }

            SearchField(text: $query, placeholder: "搜索工作区")

            HStack(spacing: 8) {
                Label("排序", systemImage: "arrow.up.arrow.down")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ModernPalette.muted)
                Spacer()
                Picker("排序", selection: Binding(
                    get: { model.database.workspaceSortMode },
                    set: { model.setWorkspaceSortMode($0) }
                )) {
                    ForEach(WorkspaceSortMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .font(.system(size: 11))
            }

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(workspaces) { workspace in
                        WorkspaceManagerRow(
                            workspace: workspace,
                            reorderingEnabled: isReorderingEnabled,
                            isBeingDragged: dragState?.sourceID == workspace.id,
                            isDropTargeted: dragState?.beforeID == workspace.id,
                            isEndDropTargeted: dragState != nil &&
                                dragState?.beforeID == nil &&
                                workspace.id == workspaces.last?.id,
                            onDragChanged: isReorderingEnabled
                                ? { location in updateWorkspaceDrag(workspace, location: location) }
                                : nil,
                            onDragEnded: isReorderingEnabled
                                ? { location in finishWorkspaceDrag(workspace, location: location) }
                                : nil,
                            onMoveUp: { if isReorderingEnabled { moveWorkspaceUp(workspace.id) } },
                            onMoveDown: { if isReorderingEnabled { moveWorkspaceDown(workspace.id) } }
                        )
                    }
                }
                .padding(.vertical, 4)
            }

            HStack(spacing: 7) {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(ModernPalette.muted)
                Text(isReorderingEnabled
                     ? "拖动左侧手柄调整顺序；固定项会出现在顶部快捷切换"
                     : "清空搜索后可以调整工作区顺序")
                    .font(.system(size: 10))
                    .foregroundStyle(ModernPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .coordinateSpace(.named("workspace-manager"))
        .onPreferenceChange(WorkspaceRowFramesPreferenceKey.self) { frames in
            if frames != workspaceFrames { workspaceFrames = frames }
        }
        .onChange(of: model.workspaceRevision) { _, _ in dragState = nil }
        .onChange(of: query) { _, _ in dragState = nil }
        .overlay {
            GeometryReader { proxy in
                if let dragState {
                    WorkspaceDragPreview(title: dragState.title)
                        .position(
                            x: min(max(dragState.location.x + 78, 112), max(112, proxy.size.width - 112)),
                            y: min(max(dragState.location.y, 24), max(24, proxy.size.height - 24))
                        )
                        .allowsHitTesting(false)
                        .zIndex(20)
                }
            }
        }
    }

    private func updateWorkspaceDrag(_ workspace: Workspace, location: CGPoint) {
        let beforeID = workspaceBeforeID(at: location, moving: workspace.id)
        let nextState = WorkspaceDragState(
            sourceID: workspace.id,
            title: workspace.name,
            location: location,
            beforeID: beforeID
        )
        if dragState != nextState { dragState = nextState }
    }

    private func finishWorkspaceDrag(_ workspace: Workspace, location: CGPoint) {
        let beforeID = workspaceBeforeID(at: location, moving: workspace.id)
        dragState = nil
        guard beforeID != workspace.id else { return }
        model.moveWorkspace(workspace.id, before: beforeID)
    }

    private func workspaceBeforeID(at location: CGPoint, moving sourceID: UUID) -> UUID? {
        for workspace in workspaces where workspace.id != sourceID {
            guard let frame = workspaceFrames[workspace.id] else { continue }
            if location.y < frame.midY { return workspace.id }
        }
        return nil
    }

    private func moveWorkspaceUp(_ id: UUID) {
        guard let index = workspaces.firstIndex(where: { $0.id == id }), index > 0 else { return }
        model.moveWorkspace(id, before: workspaces[index - 1].id)
    }

    private func moveWorkspaceDown(_ id: UUID) {
        guard let index = workspaces.firstIndex(where: { $0.id == id }), index < workspaces.count - 1 else { return }
        let beforeID = index + 2 < workspaces.count ? workspaces[index + 2].id : nil
        model.moveWorkspace(id, before: beforeID)
    }
}

private struct WorkspaceDragState: Equatable {
    let sourceID: UUID
    let title: String
    let location: CGPoint
    let beforeID: UUID?
}

private struct WorkspaceRowFramesPreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private struct WorkspaceDragPreview: View {
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(ModernPalette.muted)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 12)
        .frame(width: 210, height: 36)
        .background(.clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .plannerControlSurface(in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
    }
}

struct WorkspaceManagerRow: View {
    @Environment(AppModel.self) private var model: AppModel
    let workspace: Workspace
    let reorderingEnabled: Bool
    let isBeingDragged: Bool
    let isDropTargeted: Bool
    let isEndDropTargeted: Bool
    let onDragChanged: ((CGPoint) -> Void)?
    let onDragEnded: ((CGPoint) -> Void)?
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ModernPalette.muted.opacity(reorderingEnabled ? 0.75 : 0.34))
                .frame(width: 28, height: 32)
                .contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 4, coordinateSpace: .named("workspace-manager"))
                        .onChanged { value in onDragChanged?(value.location) }
                        .onEnded { value in onDragEnded?(value.location) }
                )
                .allowsHitTesting(reorderingEnabled)
                .help(reorderingEnabled ? "拖动调整工作区顺序" : "清空搜索后可以调整顺序")
                .accessibilityLabel("拖动“\(workspace.name)”调整顺序")
                .accessibilityAction(named: "上移") { onMoveUp() }
                .accessibilityAction(named: "下移") { onMoveDown() }

            Image(systemName: workspace.symbolName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color(hex: workspace.colorHex))
                .frame(width: 25, height: 25)
                .background(Color(hex: workspace.colorHex).opacity(0.10), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(workspace.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text("\(model.projectCount(for: workspace.id)) 个项目")
                    .font(.system(size: 10))
                    .foregroundStyle(ModernPalette.muted)
            }

            Spacer()

            Button {
                model.togglePinnedWorkspace(workspace.id)
            } label: {
                Image(systemName: model.isWorkspacePinned(workspace.id) ? "pin.fill" : "pin")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(model.isWorkspacePinned(workspace.id) ? ModernPalette.blue : ModernPalette.muted)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help(model.isWorkspacePinned(workspace.id) ? "取消固定" : "固定到快捷切换")
        }
        .padding(.vertical, 3)
        .opacity(isBeingDragged ? 0.32 : 1)
        .overlay(alignment: .top) {
            if isDropTargeted {
                Capsule()
                    .fill(ModernPalette.blue)
                    .frame(height: 2)
                    .padding(.horizontal, 4)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if isEndDropTargeted {
                Capsule()
                    .fill(ModernPalette.blue)
                    .frame(height: 2)
                    .padding(.horizontal, 4)
                    .transition(.opacity)
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: WorkspaceRowFramesPreferenceKey.self,
                    value: [workspace.id: proxy.frame(in: .named("workspace-manager"))]
                )
            }
        }
        .contextMenu {
            if model.selection.selectedWorkspaceID != workspace.id {
                Button("切换到此工作区") { model.selectWorkspace(workspace.id) }
            }
            Button(model.isWorkspacePinned(workspace.id) ? "取消固定" : "固定到快捷切换") {
                model.togglePinnedWorkspace(workspace.id)
            }
            Divider()
            Button("删除工作区", role: .destructive) {
                model.requestDeleteWorkspace(workspace)
            }
        }
    }
}

struct NewWorkspaceSheet: View {
    @Environment(AppModel.self) private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var symbolName = "square.grid.2x2"

    private let symbols = [
        "square.grid.2x2", "briefcase", "person.2", "house",
        "graduationcap", "camera", "heart", "book.closed"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("新建工作区")
                .font(.system(size: 20, weight: .semibold))

            TextField("工作区名称", text: $name)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 8) {
                Text("选择图标")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ModernPalette.muted)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(symbols, id: \.self) { symbol in
                        Button {
                            symbolName = symbol
                        } label: {
                            Image(systemName: symbol)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(symbolName == symbol ? ModernPalette.blue : ModernPalette.ink)
                                .frame(maxWidth: .infinity)
                                .frame(height: 38)
                                .background(symbolName == symbol ? ModernPalette.blue.opacity(0.12) : ModernPalette.subtle, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("创建") {
                    let fallback = "工作区\(model.database.workspaces.count)"
                    model.addWorkspace(name: name.isEmpty ? fallback : name, symbolName: symbolName)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 360)
        .onAppear {
            if name.isEmpty { name = "工作区\(model.database.workspaces.count)" }
        }
    }
}

struct ModernTimeControls: View {
    @Environment(AppModel.self) private var model: AppModel
    let now: Date

    var body: some View {
        HStack(spacing: 8) {
            ModernStopwatchControl(now: now)
            ModernPomodoroControl(now: now)
        }
    }
}

struct ModernStopwatchControl: View {
    @Environment(AppModel.self) private var model: AppModel
    let now: Date

    var body: some View {
        if let timer = model.activeTimer, timer.mode == .stopwatch {
            HStack(spacing: 8) {
                Image(systemName: "stopwatch")
                    .foregroundStyle(ModernPalette.blue)
                Text("正计时")
                Text(modernFormatDuration(model.timerElapsed(at: now)))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                Button {
                    timer.pausedAt == nil ? model.pauseTimer() : model.resumeTimer()
                } label: {
                    Image(systemName: timer.pausedAt == nil ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.plain)
                Button { model.stopTimer() } label: {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(ModernPalette.ink)
            .frame(height: 42)
            .padding(.horizontal, 13)
            .background(.clear, in: Capsule())
            .plannerControlSurface(in: Capsule(), tint: ModernPalette.accent.opacity(0.10), interactive: true)
        } else if model.activeTimer == nil {
            Button { model.startStopwatch(for: model.selectedTask) } label: {
                Label("正计时", systemImage: "stopwatch")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ModernPalette.ink)
                    .padding(.horizontal, 14)
                    .frame(height: 42)
            }
            .buttonStyle(.plain)
            .background(.clear, in: Capsule())
            .plannerControlSurface(in: Capsule(), interactive: true)
            .help("开始正计时")
        }
    }
}

struct ModernPomodoroControl: View {
    @Environment(AppModel.self) private var model: AppModel
    let now: Date

    var body: some View {
        if let timer = model.activeTimer, timer.mode == .pomodoro {
            let clock = pomodoroDisplay(timer: timer, now: now)
            HStack(spacing: 8) {
                Image(systemName: "timer")
                    .foregroundStyle(ModernPalette.red)
                Text("番茄钟")
                Text(clock.text)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(clock.phase == .overtime ? ModernPalette.red : ModernPalette.ink)
                Button {
                    timer.pausedAt == nil ? model.pauseTimer() : model.resumeTimer()
                } label: {
                    Image(systemName: timer.pausedAt == nil ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.plain)
                Button { model.stopTimer() } label: {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(ModernPalette.ink)
            .frame(height: 42)
            .padding(.horizontal, 13)
            .background(.clear, in: Capsule())
            .plannerControlSurface(in: Capsule(), tint: ModernPalette.red.opacity(0.10), interactive: true)
        } else if model.activeTimer == nil {
            Button { model.startPomodoro(for: model.selectedTask) } label: {
                Label("番茄钟 \(model.preferences.defaultPomodoroMinutes):00", systemImage: "timer")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ModernPalette.ink)
                    .padding(.horizontal, 14)
                    .frame(height: 42)
            }
            .buttonStyle(.plain)
            .background(.clear, in: Capsule())
            .plannerControlSurface(in: Capsule(), interactive: true)
            .help("开始番茄钟")
        }
    }

    private func pomodoroDisplay(timer: ActiveTimer, now: Date) -> PomodoroClockState {
        PomodoroClockState.make(
            targetSeconds: timer.targetSeconds ?? 25 * 60,
            elapsed: model.timerElapsed(at: now)
        )
    }
}

struct ModernSourceSidebar: View {
    @Environment(\.openSettings) private var openSettings
    @Environment(AppModel.self) private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 80)

            VStack(spacing: 4) {
                ForEach(OrganizationItem.allCases) { item in
                    ModernRailButton(
                        icon: item.icon,
                        title: item.title,
                        count: organizationCount(for: item),
                        selected: model.selection.selectedOrganization == item && model.selection.selectedArchive == nil
                    ) {
                        withAnimation(reduceMotion ? nil : .snappy(duration: 0.20)) {
                            model.selectOrganization(item)
                        }
                    }
                }
            }

            railDivider

            SwiftUI.TimelineView(.periodic(from: .now, by: 60)) { context in
                VStack(spacing: 4) {
                    ForEach([SmartList.today, .tomorrow, .recent, .fourSquares, .calendar]) { item in
                        ModernRailButton(
                            icon: item.icon,
                            title: item.title,
                            count: model.count(for: item, now: context.date),
                            selected: model.selection.selectedOrganization == nil && model.selection.selectedArchive == nil && model.selection.selectedSmartList == item
                        ) {
                            withAnimation(reduceMotion ? nil : .snappy(duration: 0.20)) {
                                model.selectSmartList(item)
                            }
                        }
                    }
                }
            }

            railDivider

            VStack(spacing: 4) {
                ForEach(ArchiveItem.allCases) { item in
                    ModernRailButton(
                        icon: item.icon,
                        title: item.title,
                        count: archiveCount(for: item),
                        selected: model.selection.selectedArchive == item
                    ) {
                        withAnimation(reduceMotion ? nil : .snappy(duration: 0.20)) {
                            model.selectArchive(item)
                        }
                    }
                    .contextMenu {
                        if item == .trash {
                            Button("倾倒垃圾箱", role: .destructive) { model.requestEmptyTrash() }
                                .disabled(model.trashItems.isEmpty)
                        }
                    }
                }
            }

            Spacer(minLength: 12)
            railDivider

            ModernRailButton(icon: "gearshape", title: "设置", count: 0, selected: false) {
                openSettings()
            }
            ModernRailButton(icon: "questionmark.circle", title: "帮助", count: 0, selected: false) {
                model.preferences.selectedSettingsTab = .about
                openSettings()
            }
            .padding(.top, 4)
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 8)
        .plannerControlSurface(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.vertical, 8)
    }

    private var railDivider: some View {
        Rectangle()
            .fill(ModernPalette.line.opacity(0.42))
            .frame(height: 0.5)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
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

    private func archiveCount(for item: ArchiveItem) -> Int {
        switch item {
        case .logs: return model.activityLog.count
        case .trash: return model.trashItems.count
        }
    }
}

struct ModernRailButton: View {
    let icon: String
    let title: String
    let count: Int
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(selected ? ModernPalette.blue : ModernPalette.railInk)
                    .frame(width: 44, height: 36)
                    .background(
                        selected ? ModernPalette.blue.opacity(0.095) : .clear,
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )

                if count > 0 {
                    Text(count > 99 ? "99+" : "\(count)")
                        .font(.system(size: 7.5, weight: .bold, design: .rounded))
                        .foregroundStyle(selected ? ModernPalette.blue : ModernPalette.muted)
                        .padding(.horizontal, 3)
                        .frame(minWidth: 14, minHeight: 12)
                        .background(ModernPalette.panel, in: Capsule())
                        .offset(x: 2, y: -2)
                }
            }
            .frame(width: 48, height: 38)
            .frame(maxWidth: .infinity, minHeight: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, minHeight: 42)
        .contentShape(Rectangle())
        .help(title)
        .accessibilityLabel(title)
        .accessibilityValue(count > 0 ? "\(count) 项" : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct ModernArchivePane: View {
    @Environment(AppModel.self) private var model: AppModel
    let item: ArchiveItem

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: item.icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(ModernPalette.blue)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.system(size: 18, weight: .semibold))
                    Text(item == .trash ? "最近删除的内容可在这里恢复" : "记录重要的整理与删除操作")
                        .font(.system(size: 11))
                        .foregroundStyle(ModernPalette.muted)
                }
                Spacer()
                if item == .trash {
                    Button {
                        model.requestEmptyTrash()
                    } label: {
                        Label("倾倒", systemImage: "trash")
                    }
                    .buttonStyle(ModernInspectorActionStyle(tint: ModernPalette.red))
                    .disabled(model.trashItems.isEmpty)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if item == .logs {
                        if model.activityLog.isEmpty {
                            EmptyColumnHint(icon: "clock.arrow.circlepath", title: "还没有日志", message: "删除、恢复和编辑项目等操作会显示在这里")
                                .padding(.top, 120)
                        } else {
                            ForEach(model.activityLog) { entry in
                                ModernActivityLogRow(entry: entry)
                            }
                        }
                    } else if model.trashItems.isEmpty {
                        EmptyColumnHint(icon: "trash", title: "垃圾箱是空的", message: "右键工作区、项目或任务即可移入垃圾箱")
                            .padding(.top, 120)
                    } else {
                        ForEach(model.trashItems) { item in
                            ModernTrashRow(item: item) {
                                model.restoreTrashItem(item.id)
                            }
                        }
                    }
                }
                .padding(.bottom, 30)
            }
        }
        .background(ModernPalette.canvas)
    }
}

struct ModernActivityLogRow: View {
    let entry: ActivityLogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(ModernPalette.muted)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(entry.action)
                        .font(.system(size: 13, weight: .semibold))
                    Text(entry.target)
                        .font(.system(size: 13))
                        .foregroundStyle(ModernPalette.ink)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(ModernPalette.muted)
                }
                if !entry.detail.isEmpty {
                    Text(entry.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(ModernPalette.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ModernPalette.line.opacity(0.55))
                .frame(height: 0.5)
                .padding(.leading, 56)
        }
    }
}

struct ModernTrashRow: View {
    let item: TrashItem
    let onRestore: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.kind.icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(ModernPalette.red)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ModernPalette.ink)
                    .lineLimit(1)
                Text("\(item.kind.title) · \(item.summary) · \(item.deletedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 11))
                    .foregroundStyle(ModernPalette.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            Button("恢复", action: onRestore)
                .buttonStyle(ModernInspectorActionStyle(tint: ModernPalette.blue))
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
        .contextMenu {
            Button("恢复", action: onRestore)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ModernPalette.line.opacity(0.55))
                .frame(height: 0.5)
                .padding(.leading, 58)
        }
    }
}

struct ModernSidebarRow: View {
    let icon: String
    let title: String
    let count: Int
    let selected: Bool
    let selectionNamespace: Namespace.ID
    var contextMenuTitle: String? = nil
    var contextMenuAction: (() -> Void)? = nil
    var contextMenuDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 14, weight: selected ? .semibold : .regular))
                Spacer(minLength: 8)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(selected ? ModernPalette.blue : ModernPalette.muted)
                }
            }
            .foregroundStyle(selected ? ModernPalette.blue : ModernPalette.ink)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(ModernPalette.sidebarSelection)
                        .matchedGeometryEffect(id: "sidebar-selection", in: selectionNamespace)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(ModernSidebarButtonStyle())
        .contextMenu {
            if let contextMenuTitle, let contextMenuAction {
                Button(contextMenuTitle, role: .destructive, action: contextMenuAction)
                    .disabled(contextMenuDisabled)
            }
        }
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct ModernSidebarButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.86 : 1)
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.985 : 1))
            .animation(
                reduceMotion ? .easeOut(duration: 0.08) : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
    }
}

struct ModernProjectPane: View {
    @Environment(AppModel.self) private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var projectSearchActivated: Bool
    @FocusState.Binding var projectSearchFocused: Bool
    @State private var projectQuery = ""
    @State private var collapsedCategories: Set<String> = []
    @State private var creationMode: ProjectCreationMode?
    @State private var creationDraft = ""
    @State private var showWorkspacePopover = false
    @FocusState private var creationFieldFocused: Bool

    private enum ProjectCreationMode: Hashable {
        case category
        case project

        var icon: String {
            switch self {
            case .category: "folder.badge.plus"
            case .project: "plus"
            }
        }

        var placeholder: String {
            switch self {
            case .category: "新建项目分类"
            case .project: "新建项目"
            }
        }
    }

    private var groupedProjects: [(String, [Project])] {
        let needle = projectQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let projects = model.currentProjects.filter { project in
            needle.isEmpty || project.name.localizedCaseInsensitiveContains(needle) || project.category.localizedCaseInsensitiveContains(needle)
        }
        var groups = Dictionary(grouping: projects, by: \.category)
        if needle.isEmpty {
            for category in model.currentProjectCategories where groups[category.name] == nil {
                groups[category.name] = []
            }
        } else {
            for category in model.currentProjectCategories where category.name.localizedCaseInsensitiveContains(needle) {
                if groups[category.name] == nil { groups[category.name] = [] }
            }
        }
        let categoryOrder = Dictionary(
            uniqueKeysWithValues: model.currentProjectCategories.enumerated().map { ($0.element.name.localizedLowercase, $0.offset) }
        )
        return groups.sorted { lhs, rhs in
            let leftOrder = categoryOrder[lhs.key.localizedLowercase] ?? Int.max
            let rightOrder = categoryOrder[rhs.key.localizedLowercase] ?? Int.max
            if leftOrder != rightOrder { return leftOrder < rightOrder }
            return lhs.key.localizedStandardCompare(rhs.key) == .orderedAscending
        }.map { category, projects in
            (category, projects.sorted {
                if $0.order != $1.order { return $0.order < $1.order }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            })
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                showWorkspacePopover.toggle()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: model.currentWorkspace.symbolName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(hex: model.currentWorkspace.colorHex))
                        .frame(width: 24)
                    Text(model.currentWorkspace.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(ModernPalette.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(ModernPalette.muted)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
            .frame(height: 74)
            .popover(isPresented: $showWorkspacePopover, arrowEdge: .top) {
                WorkspaceCenterPopover(onClose: { showWorkspacePopover = false })
                    .environment(model)
            }
            .accessibilityLabel("工作区：\(model.currentWorkspace.name)")
            .accessibilityHint("切换、创建或管理工作区")

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(ModernPalette.muted)
                if projectSearchActivated {
                    TextField("搜索项目", text: $projectQuery)
                        .textFieldStyle(.plain)
                        .focused($projectSearchFocused)
                        .task {
                            await Task.yield()
                            projectSearchFocused = true
                        }
                } else {
                    Button {
                        projectSearchActivated = true
                    } label: {
                        Text(projectQuery.isEmpty ? "搜索项目" : projectQuery)
                            .foregroundStyle(projectQuery.isEmpty ? ModernPalette.muted : ModernPalette.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("搜索项目")
                }
                if !projectQuery.isEmpty {
                    Button { projectQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(ModernPalette.muted)
                }
            }
            .font(.system(size: 12))
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(ModernPalette.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(ModernPalette.line.opacity(0.58), lineWidth: 0.75)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 5)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ProjectSearchFramePreferenceKey.self,
                        value: proxy.frame(in: .named("content-root"))
                    )
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if let creationMode {
                        inlineCreationRow(for: creationMode)
                            .padding(.top, 2)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    ForEach(groupedProjects, id: \.0) { category, projects in
                        let categoryRecord = model.currentProjectCategories.first {
                            $0.name.localizedCaseInsensitiveCompare(category) == .orderedSame
                        }
                        ModernProjectCategoryRow(
                            categoryID: categoryRecord?.id,
                            title: category,
                            count: projects.count,
                            color: Color(hex: categoryRecord?.colorHex ?? ProjectCategory.defaultColorHex(for: category)),
                            collapsed: collapsedCategories.contains(category),
                            onToggle: {
                                if collapsedCategories.contains(category) {
                                    collapsedCategories.remove(category)
                                } else {
                                    collapsedCategories.insert(category)
                                }
                            },
                            onDropProject: { projectID in
                                var moved = false
                                withAnimation(projectMoveAnimation) {
                                    moved = model.moveProject(projectID, toCategory: category)
                                }
                                return moved
                            },
                            onDropCategory: { categoryID in
                                var moved = false
                                withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.24)) {
                                    moved = model.moveProjectCategory(categoryID, beforeCategoryID: categoryRecord?.id)
                                }
                                return moved
                            },
                            onColorChange: { color in
                                guard let categoryID = categoryRecord?.id else { return }
                                model.updateProjectCategoryColor(categoryID, colorHex: hexString(from: color))
                            }
                        )

                        if !collapsedCategories.contains(category) {
                            ForEach(projects) { project in
                                ModernProjectRow(
                                    title: project.name,
                                    icon: project.symbolName,
                                    iconColor: Color(hex: project.colorHex),
                                    count: taskCount(for: project),
                                    selected: model.selection.selectedProjectID == project.id,
                                    leadingPadding: 10,
                                    draggableID: project.id,
                                    onDropProject: { projectID, beforeProjectID in
                                        var moved = false
                                        withAnimation(projectMoveAnimation) {
                                            moved = model.moveProject(
                                                projectID,
                                                toCategory: category,
                                                beforeProjectID: beforeProjectID
                                            )
                                        }
                                        return moved
                                    },
                                    onDelete: {
                                        model.requestDeleteProject(project)
                                    }
                                ) {
                                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
                                        model.selectProject(project.id)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 3)
                .padding(.bottom, 18)
            }

            Spacer(minLength: 0)
            Divider()
            HStack(spacing: 8) {
                Button { beginCreation(.category) } label: {
                    Label("新建分类", systemImage: ProjectCreationMode.category.icon)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ModernProjectCreationButtonStyle())
                .help("新建项目分类")
                .accessibilityLabel("新建项目分类")

                Button { beginCreation(.project) } label: {
                    Label("新建项目", systemImage: ProjectCreationMode.project.icon)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ModernProjectCreationButtonStyle())
                .help("新建项目")
                .accessibilityLabel("新建项目")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(ModernPalette.projectPanel)
        .onChange(of: creationMode) { _, newMode in
            creationFieldFocused = newMode != nil
        }
    }

    private var projectMoveAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.24)
    }

    @ViewBuilder
    private func inlineCreationRow(for mode: ProjectCreationMode) -> some View {
        HStack(spacing: 9) {
            Image(systemName: mode.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(ModernPalette.blue)
                .frame(width: 18)
            TextField(mode.placeholder, text: $creationDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($creationFieldFocused)
                .onSubmit { commitCreation() }
                .onExitCommand { cancelCreation() }
                .task {
                    await Task.yield()
                    creationFieldFocused = true
                }
            Button { cancelCreation() } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(ModernPalette.muted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("取消")
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        .background(ModernPalette.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(ModernPalette.blue.opacity(0.22), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(mode.placeholder)
    }

    private var creationAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.22)
    }

    private func beginCreation(_ mode: ProjectCreationMode) {
        projectQuery = ""
        withAnimation(creationAnimation) {
            creationDraft = ""
            creationMode = mode
        }
        creationFieldFocused = true
    }

    private func commitCreation() {
        guard let creationMode else { return }
        let name = creationDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            creationFieldFocused = true
            return
        }

        switch creationMode {
        case .category:
            model.addProjectCategory(name: name)
        case .project:
            model.addProject(name: name, category: model.selectedProject?.category ?? "未分组")
        }

        withAnimation(creationAnimation) {
            self.creationMode = nil
            creationDraft = ""
        }
    }

    private func cancelCreation() {
        withAnimation(creationAnimation) {
            creationMode = nil
            creationDraft = ""
        }
        creationFieldFocused = false
    }

    private func taskCount(for project: Project) -> Int {
        model.taskCount(for: project.id, includeFinished: false)
    }
}

struct ModernProjectCreationButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(ModernPalette.ink)
            .frame(height: 36)
            .background(
                ModernPalette.panel.opacity(configuration.isPressed ? 0.62 : 0.92),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(ModernPalette.line.opacity(0.6), lineWidth: 0.75)
            }
    }
}

struct ModernProjectRow: View {
    let title: String
    let icon: String
    var iconColor: Color? = nil
    let count: Int
    let selected: Bool
    var leadingPadding: CGFloat = 0
    var draggableID: UUID? = nil
    var onDropProject: ((UUID, UUID?) -> Bool)? = nil
    var onDelete: (() -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isNativeDropTarget = false

    private var isDropTargeted: Bool { isNativeDropTarget }

    let action: () -> Void

    var body: some View {
        if let draggableID {
            ZStack {
                rowContent
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onDrag {
                NSItemProvider(object: NSString(string: draggableID.uuidString))
            }
            .onDrop(
                of: [UTType.text.identifier, UTType.utf8PlainText.identifier, UTType.plainText.identifier],
                isTargeted: $isNativeDropTarget
            ) { providers in
                guard let provider = providers.first else { return false }
                provider.loadObject(ofClass: NSString.self) { object, _ in
                    guard let string = object as? NSString,
                          let projectID = UUID(uuidString: string as String) else {
                        return
                    }
                    Task { @MainActor in
                        _ = onDropProject?(projectID, draggableID)
                    }
                }
                return true
            }
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(iconColor ?? (selected ? ModernPalette.blue : ModernPalette.ink))
                Text(title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(selected ? ModernPalette.blue : ModernPalette.muted)
                }
            }
            .foregroundStyle(selected ? ModernPalette.blue : ModernPalette.ink)
            .padding(.horizontal, 10)
            .padding(.leading, leadingPadding)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .background(
                isDropTargeted
                    ? ModernPalette.blue.opacity(0.13)
                    : (selected ? ModernPalette.selection.opacity(0.12) : .clear),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(alignment: .top) {
                if isDropTargeted {
                    Capsule()
                        .fill(ModernPalette.blue.opacity(0.70))
                        .frame(height: 2)
                        .padding(.horizontal, 10)
                        .offset(y: -1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let onDelete {
                Button("删除项目", role: .destructive, action: onDelete)
            }
        }
        .accessibilityLabel(title)
        .accessibilityHint(draggableID == nil ? "选择此列表" : "选择此项目；可拖拽到其他项目分类或调整顺序")
    }
}

struct ModernProjectCategoryRow: View {
    let categoryID: UUID?
    let title: String
    let count: Int
    let color: Color
    let collapsed: Bool
    let onToggle: () -> Void
    let onDropProject: (UUID) -> Bool
    let onDropCategory: (UUID) -> Bool
    let onColorChange: (Color) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isTargeted = false
    @State private var showColorPopover = false
    @State private var draftColor = Color.gray

    private var dropHighlighted: Bool {
        isTargeted
    }

    var body: some View {
        HStack(spacing: 0) {
            Button {
                draftColor = color
                showColorPopover = true
            } label: {
                Circle()
                    .fill(color)
                    // Keep the visible marker delicate while the surrounding
                    // frame remains a comfortable 26 pt hit target.
                    .frame(width: 6, height: 6)
                    .frame(width: 26, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("设置“\(title)”颜色")
            .accessibilityLabel("设置“\(title)”颜色")
            .popover(isPresented: $showColorPopover, arrowEdge: .leading) {
                ModernCategoryColorPopover(
                    color: $draftColor,
                    onChange: onColorChange
                )
            }

            Button(action: onToggle) {
                HStack(spacing: 7) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text("\(count)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(dropHighlighted ? ModernPalette.blue : ModernPalette.muted)
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(ModernPalette.muted)
                }
                        .foregroundStyle(dropHighlighted ? ModernPalette.blue : ModernPalette.muted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    if dropHighlighted {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(ModernPalette.blue.opacity(0.12))
                    }
                }
                .overlay {
                    if dropHighlighted {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(ModernPalette.blue.opacity(0.35), lineWidth: 1)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 4)
        .padding(.trailing, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onDrag {
            NSItemProvider(object: NSString(string: categoryID.map { "category:\($0.uuidString)" } ?? ""))
        }
        .onDrop(
            of: [UTType.text.identifier, UTType.utf8PlainText.identifier, UTType.plainText.identifier],
            isTargeted: $isTargeted
        ) { providers in
            guard let provider = providers.first else { return false }
            provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let string = object as? NSString else { return }
                let value = String(string)
                Task { @MainActor in
                    withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.24)) {
                        if let categoryID = UUID(uuidString: String(value.dropFirst(9))), value.hasPrefix("category:") {
                            _ = onDropCategory(categoryID)
                        } else if let projectID = UUID(uuidString: value) {
                            _ = onDropProject(projectID)
                        }
                    }
                }
            }
            return true
        }
        .accessibilityLabel(title)
        .accessibilityHint("点击展开或收起；可拖拽调整分类顺序，也可将项目拖到此分类")
    }
}

private struct ModernCategoryColorPopover: View {
    @Binding var color: Color
    let onChange: (Color) -> Void

    private let palette = [
        "#64748B", "#2F6FD0", "#0AA58F", "#C47A16",
        "#8256D0", "#C65374", "#2B8A3E", "#A54E2A"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("分类颜色")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ModernPalette.ink)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(palette, id: \.self) { hex in
                    Button {
                        let selected = Color(hex: hex)
                        color = selected
                        onChange(selected)
                    } label: {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 22, height: 22)
                            .overlay {
                                if hexString(from: color).localizedCaseInsensitiveCompare(hex) == .orderedSame {
                                    Circle()
                                        .stroke(ModernPalette.ink, lineWidth: 2)
                                        .padding(-3)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("颜色 \(hex)")
                }
            }

            ColorPicker("自定义颜色", selection: $color, supportsOpacity: false)
                .font(.system(size: 11.5, weight: .medium))
                .onChange(of: color) { _, newColor in
                    onChange(newColor)
                }
        }
        .padding(14)
        .frame(width: 210)
    }
}

private struct ProjectSearchFramePreferenceKey: PreferenceKey {
    static let defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

struct TaskSearchFramePreferenceKey: PreferenceKey {
    static let defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct QuickTaskFramePreferenceKey: PreferenceKey {
    static let defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct TaskTitleFramePreferenceKey: PreferenceKey {
    static let defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if !next.isEmpty {
            value = next
        }
    }
}

private struct InspectorNoteFramePreferenceKey: PreferenceKey {
    static let defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

struct ModernTaskPane: View {
    @Environment(AppModel.self) private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var taskSearchExpanded: Bool
    @Binding var projectTaskQuery: String
    @Binding var quickTaskDraft: ModernQuickTaskDraft
    @FocusState.Binding var quickTaskFocused: Bool
    @Binding var editingTaskTitleID: UUID?
    @FocusState.Binding var taskTitleFocusedID: UUID?
    @State private var calendarMonth = Date()
    @State private var sectionCreationActive = false
    @State private var sectionDraft = ""

    var body: some View {
        let filteredTasks = ProjectTaskSearch.filter(
            model.filteredTasks(),
            query: projectTaskQuery
        )
        let displays = TaskSectionDisplayBuilder.displays(
            projectID: model.selection.selectedProjectID,
            sections: model.selectedProjectSections,
            tasks: filteredTasks
        )

        VStack(spacing: 0) {
            ModernTaskHeader(
                sectionCreationActive: $sectionCreationActive,
                sectionDraft: $sectionDraft,
                taskSearchExpanded: $taskSearchExpanded,
                taskSearchQuery: $projectTaskQuery,
                onRequestNewSection: beginSectionCreation,
                onCommitSection: commitSectionCreation,
                onCancelSection: cancelSectionCreation
            )
            if model.selection.plannerView == .timeline {
                ModernTimelineCanvas(tasks: filteredTasks)
            } else if model.selection.plannerView == .calendar {
                MonthCalendarView(month: $calendarMonth)
            } else {
                ModernTaskListView(
                    visibleTasks: filteredTasks,
                    sectionDisplays: displays,
                    editingTaskTitleID: $editingTaskTitleID,
                    taskTitleFocusedID: $taskTitleFocusedID,
                    projectSearchQuery: projectTaskQuery,
                    onTaskSearchOutsideTap: collapseTaskSearch
                )
                .id(TaskListContextIdentity(
                    workspaceID: model.selection.selectedWorkspaceID,
                    projectID: model.selection.selectedProjectID,
                    smartList: model.selection.selectedSmartList
                ))
            }

            if model.selection.plannerView == .list {
                ModernQuickTaskComposer(
                    draft: $quickTaskDraft,
                    isFocused: $quickTaskFocused,
                    onSubmit: createQuickTask
                )
            }
        }
        .background(ModernPalette.canvas)
        .onChange(of: model.selection.selectedProjectID) { _, _ in
            projectTaskQuery = ""
            taskSearchExpanded = false
        }
    }

    private func createQuickTask() {
        let title = quickTaskDraft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        let normalizedPlan: (start: Date, end: Date?)?
        if quickTaskDraft.hasPlan {
            guard let plan = TaskDateNormalizer.normalizedPlan(
                start: quickTaskDraft.plannedStart,
                end: quickTaskDraft.hasPlannedEnd ? quickTaskDraft.plannedEnd : nil,
                precision: quickTaskDraft.plannedPrecision
            ) else {
                model.notice = "计划结束必须晚于计划时间"
                return
            }
            normalizedPlan = plan
        } else {
            normalizedPlan = nil
        }

        let normalizedDeadline = quickTaskDraft.hasDeadline
            ? TaskDateNormalizer.normalizedDeadline(
                quickTaskDraft.deadline,
                precision: quickTaskDraft.deadlinePrecision
            )
            : nil

        model.addTask(
            title: title,
            projectID: model.selection.selectedProjectID,
            status: .open,
            priority: quickTaskDraft.priority,
            actionList: quickTaskDraft.actionList,
            plannedStart: normalizedPlan?.start,
            plannedEnd: normalizedPlan?.end,
            plannedPrecision: quickTaskDraft.hasPlan ? quickTaskDraft.plannedPrecision : .none,
            deadline: normalizedDeadline,
            deadlinePrecision: quickTaskDraft.hasDeadline ? quickTaskDraft.deadlinePrecision : .none,
            tags: quickTaskDraft.tags
        )
        quickTaskDraft.reset()
    }

    private func collapseTaskSearch() {
        guard taskSearchExpanded else { return }
        withAnimation(reduceMotion ? .easeOut(duration: 0.10) : .snappy(duration: 0.22)) {
            taskSearchExpanded = false
            projectTaskQuery = ""
        }
    }

    private func beginSectionCreation() {
        guard model.selection.selectedProjectID != nil else { return }
        sectionDraft = ""
        sectionCreationActive = true
    }

    private func commitSectionCreation() {
        let cleanName = sectionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        model.addProjectSection(name: cleanName, projectID: model.selection.selectedProjectID)
        sectionDraft = ""
        sectionCreationActive = false
    }

    private func cancelSectionCreation() {
        sectionDraft = ""
        sectionCreationActive = false
    }

}

struct InboxTaskSection: Identifiable, Equatable {
    enum Kind: String, Hashable {
        case recentlyCollected
        case today
        case earlier

        var title: String {
            switch self {
            case .recentlyCollected: "刚刚收集"
            case .today: "今天"
            case .earlier: "更早"
            }
        }
    }

    let id: Kind
    let tasks: [GTDTask]
}

enum InboxTaskGrouping {
    static func sections(
        for tasks: [GTDTask],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [InboxTaskSection] {
        let recentBoundary = now.addingTimeInterval(-45 * 60)
        let ordered = tasks.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        let recent = ordered.filter { $0.createdAt >= recentBoundary }
        let today = ordered.filter {
            $0.createdAt < recentBoundary && calendar.isDate($0.createdAt, inSameDayAs: now)
        }
        let earlier = ordered.filter { !calendar.isDate($0.createdAt, inSameDayAs: now) }

        return [
            InboxTaskSection(id: .recentlyCollected, tasks: recent),
            InboxTaskSection(id: .today, tasks: today),
            InboxTaskSection(id: .earlier, tasks: earlier)
        ]
        .filter { !$0.tasks.isEmpty }
    }
}

private struct ModernInboxWorkspace: View {
    @Environment(AppModel.self) private var model: AppModel
    @Binding var taskSearchExpanded: Bool
    @Binding var taskSearchQuery: String
    @Binding var quickTaskDraft: ModernQuickTaskDraft
    @FocusState.Binding var quickTaskFocused: Bool
    @Binding var editingTaskTitleID: UUID?
    @FocusState.Binding var taskTitleFocusedID: UUID?
    @FocusState.Binding var inspectorNoteFocused: Bool
    @State private var processedCount = 0

    private var inboxTasks: [GTDTask] {
        model.filteredTasks(for: .inbox, includeSearch: false)
    }

    private var visibleTasks: [GTDTask] {
        ProjectTaskSearch.filter(inboxTasks, query: taskSearchQuery)
    }

    private var visibleTaskIDs: [UUID] {
        visibleTasks.map(\.id)
    }

    private var selectedTask: GTDTask? {
        guard let taskID = model.selection.taskSelection?.taskID,
              visibleTaskIDs.contains(taskID) else { return nil }
        return model.task(withID: taskID)
    }

    var body: some View {
        HStack(spacing: 0) {
            ModernInboxListPane(
                tasks: visibleTasks,
                sections: InboxTaskGrouping.sections(for: visibleTasks),
                totalInboxCount: inboxTasks.count,
                processedCount: processedCount,
                taskSearchExpanded: $taskSearchExpanded,
                taskSearchQuery: $taskSearchQuery,
                quickTaskDraft: $quickTaskDraft,
                quickTaskFocused: $quickTaskFocused,
                editingTaskTitleID: $editingTaskTitleID,
                taskTitleFocusedID: $taskTitleFocusedID,
                onCreateTask: createInboxTask,
                onSelectFirst: ensureSelection
            )
            .frame(minWidth: 450, maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            if let selectedTask {
                ModernInboxClarificationPane(
                    task: selectedTask,
                    position: selectedPosition,
                    total: visibleTasks.count,
                    noteFocused: $inspectorNoteFocused,
                    onPrevious: { selectAdjacent(offset: -1) },
                    onNext: { selectAdjacent(offset: 1) },
                    onSkip: skipSelectedTask,
                    onClassified: classifySelectedTask
                )
                .id(selectedTask.id)
                .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyColumnHint(
                    icon: inboxTasks.isEmpty ? "checkmark.circle" : "tray",
                    title: inboxTasks.isEmpty ? "收集箱已清空" : "选择一项开始澄清",
                    message: inboxTasks.isEmpty
                        ? "新的想法仍可从左侧输入栏快速收集"
                        : "选择中间列表中的任务，决定下一步行动和归属",
                    iconColor: ModernPalette.accent
                )
                .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 28)
            }
        }
        .background(ModernPalette.canvas)
        .onAppear(perform: ensureSelection)
        .onChange(of: visibleTaskIDs) { _, _ in
            ensureSelection()
        }
        .onChange(of: model.selection.selectedWorkspaceID) { _, _ in
            processedCount = 0
            taskSearchQuery = ""
            taskSearchExpanded = false
            ensureSelection()
        }
    }

    private var selectedPosition: Int {
        guard let selectedID = selectedTask?.id,
              let index = visibleTaskIDs.firstIndex(of: selectedID) else { return 0 }
        return index + 1
    }

    private func ensureSelection() {
        guard !visibleTasks.isEmpty else {
            model.clearSelectedTask()
            return
        }
        if let selectedID = model.selection.taskSelection?.taskID,
           visibleTaskIDs.contains(selectedID) {
            return
        }
        model.selectTask(visibleTasks[0].id)
    }

    private func selectAdjacent(offset: Int) {
        guard let selectedID = selectedTask?.id,
              let index = visibleTaskIDs.firstIndex(of: selectedID) else {
            ensureSelection()
            return
        }
        let targetIndex = index + offset
        guard visibleTasks.indices.contains(targetIndex) else { return }
        model.selectTask(visibleTasks[targetIndex].id)
    }

    private func skipSelectedTask() {
        guard let selectedID = selectedTask?.id,
              let index = visibleTaskIDs.firstIndex(of: selectedID),
              visibleTasks.count > 1 else { return }
        let nextIndex = (index + 1) % visibleTasks.count
        model.selectTask(visibleTasks[nextIndex].id)
    }

    private func classifySelectedTask(_ clarification: InboxTaskClarification) {
        guard let selectedID = selectedTask?.id else { return }
        let nextID = nextTaskID(afterRemoving: selectedID)
        guard model.clarifyInboxTask(selectedID, with: clarification) else { return }
        processedCount += 1
        if let nextID {
            model.selectTask(nextID)
        } else {
            model.clearSelectedTask()
        }
    }

    private func nextTaskID(afterRemoving taskID: UUID) -> UUID? {
        guard let index = visibleTaskIDs.firstIndex(of: taskID) else { return visibleTaskIDs.first }
        if visibleTaskIDs.indices.contains(index + 1) { return visibleTaskIDs[index + 1] }
        if index > 0 { return visibleTaskIDs[index - 1] }
        return nil
    }

    private func createInboxTask() {
        let title = quickTaskDraft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        let normalizedPlan: (start: Date, end: Date?)?
        if quickTaskDraft.hasPlan {
            guard let plan = TaskDateNormalizer.normalizedPlan(
                start: quickTaskDraft.plannedStart,
                end: quickTaskDraft.hasPlannedEnd ? quickTaskDraft.plannedEnd : nil,
                precision: quickTaskDraft.plannedPrecision
            ) else {
                model.notice = "计划结束必须晚于计划时间"
                return
            }
            normalizedPlan = plan
        } else {
            normalizedPlan = nil
        }

        let normalizedDeadline = quickTaskDraft.hasDeadline
            ? TaskDateNormalizer.normalizedDeadline(
                quickTaskDraft.deadline,
                precision: quickTaskDraft.deadlinePrecision
            )
            : nil
        model.addTask(
            title: title,
            status: .inbox,
            priority: quickTaskDraft.priority,
            actionList: quickTaskDraft.actionList,
            plannedStart: normalizedPlan?.start,
            plannedEnd: normalizedPlan?.end,
            plannedPrecision: quickTaskDraft.hasPlan ? quickTaskDraft.plannedPrecision : .none,
            deadline: normalizedDeadline,
            deadlinePrecision: quickTaskDraft.hasDeadline ? quickTaskDraft.deadlinePrecision : .none,
            tags: quickTaskDraft.tags
        )
        quickTaskDraft.reset()
    }
}

private struct ModernInboxListPane: View {
    @Environment(AppModel.self) private var model: AppModel
    let tasks: [GTDTask]
    let sections: [InboxTaskSection]
    let totalInboxCount: Int
    let processedCount: Int
    @Binding var taskSearchExpanded: Bool
    @Binding var taskSearchQuery: String
    @Binding var quickTaskDraft: ModernQuickTaskDraft
    @FocusState.Binding var quickTaskFocused: Bool
    @Binding var editingTaskTitleID: UUID?
    @FocusState.Binding var taskTitleFocusedID: UUID?
    let onCreateTask: () -> Void
    let onSelectFirst: () -> Void

    private var progress: Double {
        let sessionTotal = processedCount + totalInboxCount
        guard sessionTotal > 0 else { return 1 }
        return Double(processedCount) / Double(sessionTotal)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("收集箱")
                        .font(.system(size: 23, weight: .bold))
                        .foregroundStyle(ModernPalette.ink)
                    Text("\(totalInboxCount) 项待澄清")
                        .font(.system(size: 12))
                        .foregroundStyle(ModernPalette.muted)
                    Spacer()
                }

                HStack(spacing: 10) {
                    Text("本次已处理 \(processedCount) 项")
                        .font(.system(size: 11.5))
                        .foregroundStyle(ModernPalette.muted)
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(ModernPalette.accent)
                        .frame(width: 84)
                    Spacer(minLength: 12)

                    if taskSearchExpanded {
                        TextField("搜索收集箱", text: $taskSearchQuery)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .padding(.horizontal, 10)
                            .frame(width: 170, height: 30)
                            .background(ModernPalette.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(ModernPalette.line.opacity(0.75), lineWidth: 1)
                            }
                            .background {
                                GeometryReader { proxy in
                                    Color.clear.preference(
                                        key: TaskSearchFramePreferenceKey.self,
                                        value: proxy.frame(in: .named("content-root"))
                                    )
                                }
                            }
                    }

                    Button {
                        withAnimation(.snappy(duration: 0.18)) {
                            taskSearchExpanded.toggle()
                            if !taskSearchExpanded { taskSearchQuery = "" }
                        }
                    } label: {
                        Image(systemName: taskSearchExpanded ? "xmark" : "magnifyingglass")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(ModernQuietButtonStyle())
                    .accessibilityLabel(taskSearchExpanded ? "关闭收集箱搜索" : "搜索收集箱")

                    Button("选择", action: onSelectFirst)
                        .buttonStyle(ModernQuietButtonStyle())
                        .disabled(tasks.isEmpty)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 16)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(ModernPalette.line.opacity(0.68))
                    .frame(height: 0.5)
            }

            if sections.isEmpty {
                EmptyColumnHint(
                    icon: taskSearchQuery.isEmpty ? "checkmark.circle" : "magnifyingglass",
                    title: taskSearchQuery.isEmpty ? "没有待澄清任务" : "没有匹配结果",
                    message: taskSearchQuery.isEmpty ? "从下方输入栏收集新的任务" : "尝试更换关键词",
                    iconColor: ModernPalette.accent
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 28)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(sections) { section in
                            Text(section.id.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(ModernPalette.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 24)
                                .padding(.top, 12)
                                .padding(.bottom, 7)

                            ForEach(section.tasks) { task in
                                ModernTaskRow(
                                    task: task,
                                    depth: 0,
                                    hasChildren: false,
                                    isExpanded: false,
                                    selected: model.isTaskSelected(task.id),
                                    isBeingDragged: false,
                                    isDropTargeted: false,
                                    isParentDropTargeted: false,
                                    reportsFrame: false,
                                    secondaryText: inboxCollectedText(task),
                                    showsMetadata: false,
                                    allowsAddingChildren: false,
                                    editingTaskTitleID: $editingTaskTitleID,
                                    taskTitleFocusedID: $taskTitleFocusedID,
                                    onToggleExpanded: {},
                                    onAddChild: {},
                                    onSelect: { model.selectTask(task.id) },
                                    onToggle: { model.toggleTask(task.id) },
                                    onDelete: { model.requestDeleteTask(task) },
                                    onRename: { model.updateTask($0) },
                                    onDragChanged: nil,
                                    onDragEnded: nil
                                )
                                .padding(.bottom, 1)
                                .overlay(alignment: .bottom) {
                                    Rectangle()
                                        .fill(ModernPalette.line.opacity(0.45))
                                        .frame(height: 0.5)
                                        .padding(.horizontal, 24)
                                }
                            }
                        }
                        Color.clear.frame(height: 8)
                    }
                }
                .coordinateSpace(.named(taskListContentCoordinateSpace))
                .background(TaskThemedScrollerConfigurator().allowsHitTesting(false))
            }

            ModernQuickTaskComposer(
                draft: $quickTaskDraft,
                isFocused: $quickTaskFocused,
                onSubmit: onCreateTask
            )
        }
        .background(ModernPalette.canvas)
    }

    private func inboxCollectedText(_ task: GTDTask) -> String {
        if Calendar.current.isDateInToday(task.createdAt) {
            return "收集于 \(task.createdAt.formatted(date: .omitted, time: .shortened))"
        }
        return "收集于 \(task.createdAt.formatted(date: .abbreviated, time: .shortened))"
    }
}

private struct ModernInboxClarificationPane: View {
    @Environment(AppModel.self) private var model: AppModel
    let task: GTDTask
    let position: Int
    let total: Int
    @FocusState.Binding var noteFocused: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onSkip: () -> Void
    let onClassified: (InboxTaskClarification) -> Void

    @State private var workspaceID: UUID
    @State private var projectID: UUID?
    @State private var sectionID: UUID?
    @State private var actionList: ActionList
    @State private var priority: Priority
    @State private var tags: [String]
    @State private var note: String
    @State private var hasPlan: Bool
    @State private var hasPlannedEnd: Bool
    @State private var plannedStart: Date
    @State private var plannedEnd: Date
    @State private var plannedPrecision: DeadlinePrecision
    @State private var hasDeadline: Bool
    @State private var deadline: Date
    @State private var deadlinePrecision: DeadlinePrecision

    init(
        task: GTDTask,
        position: Int,
        total: Int,
        noteFocused: FocusState<Bool>.Binding,
        onPrevious: @escaping () -> Void,
        onNext: @escaping () -> Void,
        onSkip: @escaping () -> Void,
        onClassified: @escaping (InboxTaskClarification) -> Void
    ) {
        self.task = task
        self.position = position
        self.total = total
        self._noteFocused = noteFocused
        self.onPrevious = onPrevious
        self.onNext = onNext
        self.onSkip = onSkip
        self.onClassified = onClassified
        _workspaceID = State(initialValue: task.workspaceID)
        _projectID = State(initialValue: task.projectID)
        _sectionID = State(initialValue: task.sectionID)
        _actionList = State(initialValue: task.actionList)
        _priority = State(initialValue: task.priority)
        _tags = State(initialValue: task.tags)
        _note = State(initialValue: task.note)
        _hasPlan = State(initialValue: task.plannedStart != nil)
        _hasPlannedEnd = State(initialValue: task.plannedEnd != nil)
        _plannedStart = State(initialValue: task.plannedStart ?? .now)
        _plannedEnd = State(initialValue: task.plannedEnd ?? task.plannedStart ?? .now)
        _plannedPrecision = State(initialValue: task.plannedPrecision == .none ? .date : task.plannedPrecision)
        _hasDeadline = State(initialValue: task.deadline != nil)
        _deadline = State(initialValue: task.deadline ?? .now)
        _deadlinePrecision = State(initialValue: task.deadlinePrecision == .none ? .date : task.deadlinePrecision)
    }

    private var availableProjects: [Project] {
        model.projects(in: workspaceID)
    }

    private var availableSections: [ProjectSection] {
        guard let projectID else { return [] }
        return model.projectSections(for: projectID)
    }

    private var workspaceName: String {
        model.workspace(withID: workspaceID)?.name ?? "选择工作区"
    }

    private var projectName: String {
        availableProjects.first(where: { $0.id == projectID })?.name ?? "选择项目"
    }

    private var sectionName: String {
        guard projectID != nil else { return "选择项目后可选" }
        return availableSections.first(where: { $0.id == sectionID })?.name ?? "未分组"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("澄清处理")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ModernPalette.ink)
                Text("\(position)/\(total)")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(ModernPalette.muted)
                Spacer()
                Button(action: onPrevious) {
                    Label("上一条", systemImage: "arrow.left")
                }
                .buttonStyle(ModernQuietButtonStyle())
                .disabled(position <= 1)
                Button(action: onNext) {
                    Label("下一条", systemImage: "arrow.right")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(ModernQuietButtonStyle())
                .disabled(position >= total)
            }
            .padding(.horizontal, 24)
            .frame(height: 56)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(ModernPalette.line.opacity(0.68))
                    .frame(height: 0.5)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 12) {
                        Text(task.title)
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(ModernPalette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 12)
                        Button {
                            model.requestDeleteTask(task)
                        } label: {
                            Image(systemName: "trash")
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(ModernPalette.railInk)
                        .help("删除任务")
                        .accessibilityLabel("删除任务")
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 14)

                    TextEditor(text: $note)
                        .font(.system(size: 12.5))
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .frame(minHeight: 96, maxHeight: 128)
                        .background(ModernPalette.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(ModernPalette.line.opacity(0.8), lineWidth: 1)
                        }
                        .overlay(alignment: .topLeading) {
                            if note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("添加备注…")
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(ModernPalette.muted.opacity(0.8))
                                    .padding(.horizontal, 15)
                                    .padding(.vertical, 17)
                                    .allowsHitTesting(false)
                            }
                        }
                        .focused($noteFocused)
                        .background {
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: InspectorNoteFramePreferenceKey.self,
                                    value: proxy.frame(in: .named("content-root"))
                                )
                            }
                        }

                    Text("\(collectionContext)  ·  \(model.workspace(withID: task.workspaceID)?.name ?? "未知工作区")")
                        .font(.system(size: 11))
                        .foregroundStyle(ModernPalette.muted)
                        .padding(.top, 9)
                        .padding(.bottom, 24)

                    Text("下一步怎么处理？")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ModernPalette.ink)
                        .padding(.bottom, 9)

                    InboxActionListPicker(selection: $actionList)
                        .padding(.bottom, 12)

                    InboxClarificationMenuRow(
                        icon: "square.grid.2x2",
                        title: "所属工作区",
                        value: workspaceName
                    ) {
                        ForEach(model.orderedWorkspaces) { workspace in
                            Button(workspace.name) {
                                guard workspaceID != workspace.id else { return }
                                workspaceID = workspace.id
                                projectID = nil
                                sectionID = nil
                            }
                        }
                    }

                    InboxClarificationMenuRow(
                        icon: "folder",
                        title: "所属项目",
                        value: projectName
                    ) {
                        Button("无项目") {
                            projectID = nil
                            sectionID = nil
                        }
                        if availableProjects.isEmpty {
                            Text("此工作区暂无项目")
                        } else {
                            ForEach(availableProjects) { project in
                                Button(project.name) {
                                    guard projectID != project.id else { return }
                                    projectID = project.id
                                    sectionID = nil
                                }
                            }
                        }
                    }

                    InboxClarificationMenuRow(
                        icon: "rectangle.3.group",
                        title: "分组",
                        value: sectionName,
                        isEnabled: projectID != nil
                    ) {
                        Button("未分组") { sectionID = nil }
                        ForEach(availableSections) { section in
                            Button(section.name) { sectionID = section.id }
                        }
                    }

                    ModernTaskDateSection(
                        hasPlan: $hasPlan,
                        hasPlannedEnd: $hasPlannedEnd,
                        plannedStart: $plannedStart,
                        plannedEnd: $plannedEnd,
                        plannedPrecision: $plannedPrecision,
                        hasDeadline: $hasDeadline,
                        deadline: $deadline,
                        deadlinePrecision: $deadlinePrecision
                    )

                    InboxClarificationMenuRow(
                        icon: priority == .none ? "flag" : "flag.fill",
                        title: "优先级",
                        value: priority.title,
                        valueColor: priority == .none ? ModernPalette.muted : Color(hex: priority.color)
                    ) {
                        ForEach(Priority.allCases) { item in
                            Button(item.title) { priority = item }
                        }
                    }

                    ModernTaskTagsRow(tags: $tags, onChange: {})
                    Color.clear.frame(height: 18)
                }
                .padding(.horizontal, 24)
            }
            .background(TaskThemedScrollerConfigurator().allowsHitTesting(false))

            HStack(spacing: 12) {
                Spacer()
                Button("跳过", action: onSkip)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                Button(action: commitClarification) {
                    HStack(spacing: 8) {
                        Text("归类并继续")
                        Text("⌘↩")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .opacity(0.82)
                    }
                }
                .buttonStyle(ModernInboxPrimaryActionStyle())
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .background(ModernPalette.panel)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(ModernPalette.line.opacity(0.68))
                    .frame(height: 0.5)
            }
        }
        .background(ModernPalette.panel)
    }

    private func commitClarification() {
        onClassified(InboxTaskClarification(
            workspaceID: workspaceID,
            projectID: projectID,
            sectionID: sectionID,
            actionList: actionList,
            priority: priority,
            tags: tags,
            note: note,
            plannedStart: hasPlan ? plannedStart : nil,
            plannedEnd: hasPlan && hasPlannedEnd ? plannedEnd : nil,
            plannedPrecision: hasPlan ? plannedPrecision : .none,
            deadline: hasDeadline ? deadline : nil,
            deadlinePrecision: hasDeadline ? deadlinePrecision : .none
        ))
    }

    private var collectionContext: String {
        if Calendar.current.isDateInToday(task.createdAt) {
            return "收集于 \(task.createdAt.formatted(date: .omitted, time: .shortened))"
        }
        return "收集于 \(task.createdAt.formatted(date: .abbreviated, time: .shortened))"
    }
}

private struct ModernInboxPrimaryActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.72))
            .padding(.horizontal, 16)
            .frame(minWidth: 126, minHeight: 32)
            .background(
                ModernPalette.accent.opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.48),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.985 : 1))
            .animation(
                reduceMotion ? .easeOut(duration: 0.08) : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
    }
}

private struct InboxActionListPicker: View {
    @Binding var selection: ActionList

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ActionList.allCases) { item in
                Button {
                    selection = item
                } label: {
                    Label(item.title, systemImage: item.icon)
                        .font(.system(size: 11.5, weight: .medium))
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .foregroundStyle(selection == item ? ModernPalette.accent : ModernPalette.railInk)
                        .background(selection == item ? ModernPalette.accent.opacity(0.08) : .clear)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == item ? .isSelected : [])
                if item != ActionList.allCases.last {
                    Rectangle()
                        .fill(ModernPalette.line.opacity(0.7))
                        .frame(width: 0.5, height: 32)
                }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(ModernPalette.line.opacity(0.85), lineWidth: 1)
        }
        .clipShape(.rect(cornerRadius: 7))
    }
}

private struct InboxClarificationMenuRow<MenuContent: View>: View {
    let icon: String
    let title: String
    let value: String
    var valueColor: Color = ModernPalette.ink
    var isEnabled = true
    @ViewBuilder let menuContent: () -> MenuContent

    init(
        icon: String,
        title: String,
        value: String,
        valueColor: Color = ModernPalette.ink,
        isEnabled: Bool = true,
        @ViewBuilder menuContent: @escaping () -> MenuContent
    ) {
        self.icon = icon
        self.title = title
        self.value = value
        self.valueColor = valueColor
        self.isEnabled = isEnabled
        self.menuContent = menuContent
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ModernPalette.railInk)
                .frame(width: 18)
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(ModernPalette.railInk)
                .frame(width: 76, alignment: .leading)
            Menu {
                menuContent()
            } label: {
                HStack(spacing: 8) {
                    Text(value)
                        .font(.system(size: 12))
                        .foregroundStyle(isEnabled ? valueColor : ModernPalette.muted.opacity(0.72))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(ModernPalette.muted.opacity(isEnabled ? 1 : 0.45))
                }
                .padding(.horizontal, 11)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(
                    ModernPalette.subtle.opacity(isEnabled ? 0.48 : 0.78),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(ModernPalette.line.opacity(isEnabled ? 0.72 : 0.38), lineWidth: 1)
                }
            }
            .menuStyle(.borderlessButton)
            .disabled(!isEnabled)
        }
        .padding(.vertical, 4)
    }
}

struct TaskSectionDisplay: Identifiable {
    let id: String
    let section: ProjectSection?
    let tasks: [GTDTask]
}

enum ProjectTaskSearch {
    static func filter(_ tasks: [GTDTask], query: String) -> [GTDTask] {
        let tokens = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedLowercase
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard !tokens.isEmpty else { return tasks }

        return tasks.filter { task in
            let haystack = [
                task.title,
                task.note,
                task.tags.joined(separator: " "),
                task.contexts.joined(separator: " ")
            ]
            .joined(separator: " ")
            .localizedLowercase
            return tokens.allSatisfy(haystack.contains)
        }
    }
}

enum TaskSectionDisplayBuilder {
    static func displays(
        projectID: UUID?,
        sections: [ProjectSection],
        tasks: [GTDTask]
    ) -> [TaskSectionDisplay] {
        guard let projectID else {
            return [TaskSectionDisplay(id: "all-tasks", section: nil, tasks: tasks)]
        }

        let tasksBySection = Dictionary(grouping: tasks, by: { $0.sectionID })
        let sectionIDs = Set(sections.map(\.id))
        let unassigned = tasks.filter { task in
            guard let sectionID = task.sectionID else { return true }
            return !sectionIDs.contains(sectionID)
        }
        var result: [TaskSectionDisplay] = []
        if !unassigned.isEmpty || sections.isEmpty {
            result.append(TaskSectionDisplay(
                id: "unassigned-\(projectID.uuidString)",
                section: nil,
                tasks: unassigned
            ))
        }
        result.append(contentsOf: sections.map { section in
            TaskSectionDisplay(
                id: section.id.uuidString,
                section: section,
                tasks: tasksBySection[section.id] ?? []
            )
        })
        return result
    }
}

private struct TaskListContextIdentity: Hashable {
    let workspaceID: UUID
    let projectID: UUID?
    let smartList: SmartList
}

struct TaskDropTarget: Equatable {
    let sectionID: UUID?
    let parentID: UUID?
    let beforeTaskID: UUID?

    init(sectionID: UUID?, parentID: UUID? = nil, beforeTaskID: UUID? = nil) {
        self.sectionID = sectionID
        self.parentID = parentID
        self.beforeTaskID = beforeTaskID
    }
}

private struct TaskDragState: Equatable {
    let sourceTaskID: UUID
    let sourceTitle: String
    let sourceSectionID: UUID?
    let sourceParentID: UUID?
    var location: CGPoint
    var target: TaskDropTarget
}

struct TaskRowFramesPreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private struct TaskSectionFramesPreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { current, next in current.union(next) })
    }
}

struct InlineChildTaskFramePreferenceKey: PreferenceKey {
    static let defaultValue = CGRect.zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

/// C3 uses AppKit's overlay scroller lifecycle so scrolling stays on the
/// native rendering path. Only the knob drawing is customized to match the
/// app theme; AppKit remains responsible for showing, fading, and positioning
/// it without feeding per-frame offsets back through SwiftUI state.
private struct TaskThemedScrollerConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.configureEnclosingScrollView()
        return view
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        nsView.configureEnclosingScrollView()
    }

    final class ProbeView: NSView {
        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            configureEnclosingScrollView()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureEnclosingScrollView()
        }

        func configureEnclosingScrollView() {
            guard let scrollView = enclosingScrollView else {
                DispatchQueue.main.async { [weak self] in
                    self?.configureEnclosingScrollView()
                }
                return
            }
            if !(scrollView.verticalScroller is TaskThemedScroller) {
                let scroller = TaskThemedScroller()
                scroller.controlSize = .small
                scrollView.verticalScroller = scroller
            }
            scrollView.scrollerStyle = .overlay
            scrollView.autohidesScrollers = true
            scrollView.hasVerticalScroller = true
        }
    }
}

private final class TaskThemedScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool {
        self == TaskThemedScroller.self
    }

    override func drawKnob() {
        guard knobProportion < 1 else { return }
        let systemRect = rect(for: .knob)
        guard !systemRect.isEmpty else { return }
        let width: CGFloat = 4
        let knobRect = NSRect(
            x: max(systemRect.minX, systemRect.maxX - width - 4),
            y: systemRect.minY,
            width: width,
            height: systemRect.height
        )
        NSColor.systemBlue.withAlphaComponent(0.34).setFill()
        NSBezierPath(roundedRect: knobRect, xRadius: 2, yRadius: 2).fill()
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}
}

private let unassignedTaskSectionKey = "__unassigned__"
private let taskListContentCoordinateSpace = "task-list-content"

enum TaskSectionTarget: Hashable {
    case assigned(UUID)
    case unassigned

    var sectionID: UUID? {
        switch self {
        case .assigned(let id): id
        case .unassigned: nil
        }
    }

    var frameKey: String {
        switch self {
        case .assigned(let id): id.uuidString
        case .unassigned: unassignedTaskSectionKey
        }
    }
}

enum TaskCanvasHitTest {
    static func containsInteractiveContent(
        at location: CGPoint,
        taskFrames: [UUID: CGRect],
        sectionFrames: [String: CGRect],
        inlineEditorFrame: CGRect
    ) -> Bool {
        taskFrames.values.contains(where: { $0.contains(location) })
            || sectionFrames.values.contains(where: { $0.contains(location) })
            || (!inlineEditorFrame.isEmpty && inlineEditorFrame.contains(location))
    }
}

private struct ModernTaskListView: View {
    @Environment(AppModel.self) private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let visibleTasks: [GTDTask]
    let sectionDisplays: [TaskSectionDisplay]
    @Binding var editingTaskTitleID: UUID?
    @FocusState.Binding var taskTitleFocusedID: UUID?
    let projectSearchQuery: String
    let onTaskSearchOutsideTap: () -> Void
    @State private var dragState: TaskDragState?
    /// Geometry is required by the custom reorder gesture, but not by the
    /// normal task-list render. Keeping the reporters dormant outside a drag
    /// avoids rebuilding one preference value per row during unrelated updates.
    @State private var isTaskDragActive = false
    @State private var taskFrames: [UUID: CGRect] = [:]
    @State private var sectionFrames: [String: CGRect] = [:]
    @State private var expandedTaskIDs: Set<UUID> = []
    @State private var didInitializeExpansion = false
    @State private var selectedSectionTarget: TaskSectionTarget?
    @State private var collapsedSectionTargets: Set<TaskSectionTarget> = []
    @State private var addingChildToTaskID: UUID?
    @State private var childTaskDraft = ""
    @State private var childTaskFrame = CGRect.zero
    @State private var addingTaskToSectionTarget: TaskSectionTarget?
    @State private var sectionTaskDraft = ""
    @FocusState private var childTaskFocused: Bool
    @FocusState private var sectionTaskFocused: Bool

    private var canReorderTasks: Bool {
        model.selection.selectedProjectID != nil
            && projectSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: 5)

                        ForEach(sectionDisplays) { display in
                            let sectionTarget = display.section.map { TaskSectionTarget.assigned($0.id) } ?? .unassigned
                            let sectionIsCollapsed = collapsedSectionTargets.contains(sectionTarget)

                            VStack(alignment: .leading, spacing: 0) {
                                if let section = display.section {
                                    ModernTaskSectionRow(
                                        section: section,
                                        taskCount: display.tasks.count,
                                        selected: selectedSectionTarget == sectionTarget,
                                        collapsed: sectionIsCollapsed,
                                        reportsFrame: isTaskDragActive,
                                        allowsNativeDrop: dragState == nil,
                                        customDropHighlighted: dragState?.target.sectionID == section.id && dragState?.target.parentID == nil && dragState?.target.beforeTaskID == nil,
                                        onSelect: {
                                            onTaskSearchOutsideTap()
                                            selectSection(sectionTarget)
                                        },
                                        onToggleCollapsed: {
                                            onTaskSearchOutsideTap()
                                            toggleSectionCollapsed(sectionTarget)
                                        },
                                        onAddTask: {
                                            onTaskSearchOutsideTap()
                                            beginAddingTask(to: sectionTarget)
                                        },
                                        onDropTask: { taskID in
                                            model.moveTask(taskID, toSectionID: section.id)
                                        },
                                        onDropSection: { sectionID in
                                            model.moveProjectSection(sectionID, beforeSectionID: section.id)
                                        },
                                        onRename: { updatedSection in
                                            model.updateProjectSection(updatedSection)
                                        },
                                        onDelete: {
                                            model.requestDeleteProjectSection(section)
                                        }
                                    )
                                } else if model.selection.selectedProjectID != nil {
                                    ModernUnassignedTaskSectionRow(
                                        taskCount: display.tasks.count,
                                        selected: selectedSectionTarget == sectionTarget,
                                        collapsed: sectionIsCollapsed,
                                        reportsFrame: isTaskDragActive,
                                        customDropHighlighted: dragState != nil && dragState?.target.sectionID == nil && dragState?.target.parentID == nil && dragState?.target.beforeTaskID == nil,
                                        onSelect: {
                                            onTaskSearchOutsideTap()
                                            selectSection(sectionTarget)
                                        },
                                        onToggleCollapsed: {
                                            onTaskSearchOutsideTap()
                                            toggleSectionCollapsed(sectionTarget)
                                        },
                                        onAddTask: {
                                            onTaskSearchOutsideTap()
                                            beginAddingTask(to: sectionTarget)
                                        }
                                    )
                                }

                                if !sectionIsCollapsed {
                                    if addingTaskToSectionTarget == sectionTarget {
                                        ModernInlineSectionTaskEditor(
                                            draft: $sectionTaskDraft,
                                            isFocused: $sectionTaskFocused,
                                            onCommit: commitAddingTaskToSection,
                                            onCancel: cancelAddingTaskToSection
                                        )
                                    } else if display.tasks.isEmpty, let sectionID = display.section?.id {
                                        ModernEmptyTaskDropRow(
                                            sectionID: sectionID,
                                            reportsFrame: isTaskDragActive,
                                            highlighted: dragState?.target.sectionID == sectionID && dragState?.target.parentID == nil && dragState?.target.beforeTaskID == nil
                                        )
                                    }

                                    ForEach(TaskOutlineBuilder.rows(for: display.tasks, expandedTaskIDs: expandedTaskIDs)) { outlineRow in
                                        // Keep one stable root view per outline ID while still
                                        // resolving the newest canonical task value for rendering.
                                        let task = model.task(withID: outlineRow.task.id) ?? outlineRow.task
                                        VStack(alignment: .leading, spacing: 0) {
                                            ModernTaskRow(
                                                task: task,
                                                depth: outlineRow.depth,
                                                hasChildren: outlineRow.hasChildren,
                                                isExpanded: expandedTaskIDs.contains(task.id),
                                                selected: model.isTaskSelected(task.id),
                                                isBeingDragged: dragState?.sourceTaskID == task.id,
                                                isDropTargeted: dragState?.target.beforeTaskID == task.id,
                                                isParentDropTargeted: dragState?.target.parentID == task.id && dragState?.target.beforeTaskID == nil,
                                                reportsFrame: isTaskDragActive,
                                                editingTaskTitleID: $editingTaskTitleID,
                                                taskTitleFocusedID: $taskTitleFocusedID,
                                                onToggleExpanded: {
                                                    onTaskSearchOutsideTap()
                                                    toggleExpanded(task.id)
                                                },
                                                onAddChild: {
                                                    onTaskSearchOutsideTap()
                                                    beginAddingChild(to: task.id)
                                                },
                                                onSelect: {
                                                    onTaskSearchOutsideTap()
                                                    selectedSectionTarget = nil
                                                    model.selectTask(task.id)
                                                },
                                                onToggle: {
                                                    onTaskSearchOutsideTap()
                                                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.18)) {
                                                        model.toggleTask(task.id)
                                                    }
                                                },
                                                onDelete: {
                                                    onTaskSearchOutsideTap()
                                                    model.requestDeleteTask(task)
                                                },
                                                onRename: { updatedTask in
                                                    onTaskSearchOutsideTap()
                                                    model.updateTask(updatedTask)
                                                },
                                                onDragChanged: canReorderTasks ? { taskID, location, horizontalTranslation in
                                                    updateDrag(
                                                        taskID: taskID,
                                                        location: location,
                                                        horizontalTranslation: horizontalTranslation
                                                    )
                                                } : nil,
                                                onDragEnded: canReorderTasks ? { taskID, location, horizontalTranslation in
                                                    finishDrag(
                                                        taskID: taskID,
                                                        location: location,
                                                        horizontalTranslation: horizontalTranslation
                                                    )
                                                } : nil
                                            )

                                            if addingChildToTaskID == task.id {
                                                ModernInlineChildTaskEditor(
                                                    depth: outlineRow.depth + 1,
                                                    draft: $childTaskDraft,
                                                    isFocused: $childTaskFocused,
                                                    onCommit: commitAddingChild,
                                                    onCancel: cancelAddingChild
                                                )
                                            }
                                        }
                                    }
                                }
                            }
                            .id(display.id)
                        }

                        if visibleTasks.isEmpty {
                            EmptyColumnHint(
                                icon: projectSearchQuery.isEmpty ? "checkmark.circle" : "magnifyingglass",
                                title: projectSearchQuery.isEmpty ? "这里还很安静" : "没有匹配的任务",
                                message: projectSearchQuery.isEmpty ? "按 ⌘N 收集一个下一步行动" : "请尝试其他关键词"
                            )
                                .padding(.top, 110)
                        }
                    }
                    .padding(.bottom, 32)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .top)
                    .coordinateSpace(.named(taskListContentCoordinateSpace))
                    .background(TaskThemedScrollerConfigurator())
                    .overlay(alignment: .topLeading) {
                        if let dragState {
                            GeometryReader { contentProxy in
                                TaskDragPreview(title: dragState.sourceTitle)
                                    .position(previewPosition(for: dragState, in: contentProxy.size))
                                    .allowsHitTesting(false)
                            }
                            .zIndex(10)
                        }
                    }
                    .simultaneousGesture(
                        SpatialTapGesture(coordinateSpace: .named(taskListContentCoordinateSpace))
                            .onEnded(handleCanvasTap),
                        including: .gesture
                    )
                }
            }
            .onPreferenceChange(TaskRowFramesPreferenceKey.self) { frames in
                if frames != taskFrames { taskFrames = frames }
            }
            .onPreferenceChange(TaskSectionFramesPreferenceKey.self) { frames in
                if frames != sectionFrames { sectionFrames = frames }
            }
            .onPreferenceChange(InlineChildTaskFramePreferenceKey.self) { frame in
                if frame != childTaskFrame { childTaskFrame = frame }
            }
            .onChange(of: childTaskFocused) { wasFocused, isFocused in
                guard wasFocused, !isFocused, addingChildToTaskID != nil else { return }
                cancelAddingChild()
            }
            .onChange(of: sectionTaskFocused) { wasFocused, isFocused in
                guard wasFocused, !isFocused, addingTaskToSectionTarget != nil else { return }
                cancelAddingTaskToSection()
            }
            .onChange(of: model.selection.taskSelection?.taskID) { _, taskID in
                if taskID != nil { selectedSectionTarget = nil }
            }
            // Cancel an in-flight gesture when its data domain changes, but
            // keep the last valid geometry. Clearing it here can leave the
            // drag system permanently empty when the next layout produces
            // identical preference values and SwiftUI correctly emits no
            // new onPreferenceChange callback.
            .onChange(of: model.taskRevision) { _, _ in
                cancelDrag()
            }
            .onChange(of: model.projectRevision) { _, _ in
                cancelDrag()
            }
            .onChange(of: model.selection.selectedProjectID) { _, _ in
                cancelDrag()
                selectedSectionTarget = nil
                collapsedSectionTargets.removeAll()
                cancelAddingChild()
                cancelAddingTaskToSection()
            }
            .onChange(of: model.selection.selectedSmartList) { _, _ in
                cancelDrag()
            }
            .onChange(of: model.query) { _, _ in
                cancelDrag()
            }
            .onAppear(perform: initializeExpansionIfNeeded)
        }
        .background(ModernPalette.subtle.opacity(0.18))
    }

    private func cancelDrag() {
        dragState = nil
        isTaskDragActive = false
    }

    private func previewPosition(for state: TaskDragState, in size: CGSize) -> CGPoint {
        return CGPoint(
            x: min(max(state.location.x + 90, 120), max(120, size.width - 120)),
            y: min(max(state.location.y, 24), max(24, size.height - 24))
        )
    }

    private func handleCanvasTap(_ value: SpatialTapGesture.Value) {
        if childTaskFocused, !childTaskFrame.contains(value.location) {
            childTaskFocused = false
        }
        if sectionTaskFocused, !childTaskFrame.contains(value.location) {
            sectionTaskFocused = false
        }
        taskTitleFocusedID = nil
        editingTaskTitleID = nil
        selectedSectionTarget = nil
        model.clearSelectedTask()
    }

    private func updateDrag(taskID: UUID, location: CGPoint, horizontalTranslation: CGFloat) {
        guard let sourceTask = model.task(withID: taskID) else { return }
        isTaskDragActive = true
        let target = TaskDragCoordinator.resolveTarget(
            location: location,
            movingTaskID: taskID,
            sourceSectionID: sourceTask.sectionID,
            sectionDisplays: sectionDisplays,
            taskFrames: taskFrames,
            sectionFrames: sectionFrames,
            sourceParentID: sourceTask.parentID,
            sourceIsFinished: sourceTask.status.isFinished,
            horizontalTranslation: horizontalTranslation,
            invalidParentIDs: model.invalidParentTaskIDs(for: taskID)
        )
        let nextState = TaskDragState(
            sourceTaskID: taskID,
            sourceTitle: sourceTask.title,
            sourceSectionID: sourceTask.sectionID,
            sourceParentID: sourceTask.parentID,
            location: location,
            target: target
        )
        if dragState != nextState { dragState = nextState }
    }

    private func finishDrag(taskID: UUID, location: CGPoint, horizontalTranslation: CGFloat) {
        guard let sourceTask = model.task(withID: taskID) else {
            cancelDrag()
            return
        }
        // Resolve once more from the actual release point. Fast pointer
        // movement can skip an onChanged sample immediately before onEnded.
        let target = TaskDragCoordinator.resolveTarget(
            location: location,
            movingTaskID: taskID,
            sourceSectionID: sourceTask.sectionID,
            sectionDisplays: sectionDisplays,
            taskFrames: taskFrames,
            sectionFrames: sectionFrames,
            sourceParentID: sourceTask.parentID,
            sourceIsFinished: sourceTask.status.isFinished,
            horizontalTranslation: horizontalTranslation,
            invalidParentIDs: model.invalidParentTaskIDs(for: taskID)
        )
        defer {
            dragState = nil
            isTaskDragActive = false
        }
        guard target.beforeTaskID != taskID else { return }
        if let parentID = target.parentID {
            // Keep the result visible after a successful reparent. Hiding the
            // moved row under a newly created collapsed disclosure makes a
            // correct drop look as if the task disappeared.
            expandedTaskIDs.insert(parentID)
        }
        model.moveTask(
            taskID,
            toSectionID: target.sectionID,
            toParentID: target.parentID,
            beforeTaskID: target.beforeTaskID
        )
    }

    private func initializeExpansionIfNeeded() {
        guard !didInitializeExpansion else { return }
        let visibleIDs = Set(visibleTasks.map(\.id))
        expandedTaskIDs = Set(visibleTasks.compactMap { task in
            guard let parentID = task.parentID, visibleIDs.contains(parentID) else { return nil }
            return parentID
        })
        didInitializeExpansion = true
    }

    private func selectSection(_ target: TaskSectionTarget) {
        selectedSectionTarget = target
        taskTitleFocusedID = nil
        editingTaskTitleID = nil
        model.clearSelectedTask()
    }

    private func toggleSectionCollapsed(_ target: TaskSectionTarget) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.18)) {
            if collapsedSectionTargets.contains(target) {
                collapsedSectionTargets.remove(target)
            } else {
                collapsedSectionTargets.insert(target)
                if addingTaskToSectionTarget == target {
                    cancelAddingTaskToSection()
                }
            }
        }
    }

    private func beginAddingTask(to target: TaskSectionTarget) {
        cancelAddingChild()
        selectSection(target)
        collapsedSectionTargets.remove(target)
        addingTaskToSectionTarget = target
        sectionTaskDraft = ""
        Task { @MainActor in
            await Task.yield()
            sectionTaskFocused = true
        }
    }

    private func commitAddingTaskToSection() {
        guard let target = addingTaskToSectionTarget,
              let projectID = model.selection.selectedProjectID else {
            cancelAddingTaskToSection()
            return
        }
        let title = sectionTaskDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            cancelAddingTaskToSection()
            return
        }
        model.addTask(
            title: title,
            projectID: projectID,
            sectionID: target.sectionID,
            status: .open,
            insertionPlacement: .beginning
        )
        sectionTaskFocused = false
        sectionTaskDraft = ""
        addingTaskToSectionTarget = nil
    }

    private func cancelAddingTaskToSection() {
        sectionTaskFocused = false
        sectionTaskDraft = ""
        addingTaskToSectionTarget = nil
    }

    private func toggleExpanded(_ taskID: UUID) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.18)) {
            if expandedTaskIDs.contains(taskID) {
                expandedTaskIDs.remove(taskID)
            } else {
                expandedTaskIDs.insert(taskID)
            }
        }
    }

    private func beginAddingChild(to taskID: UUID) {
        cancelAddingTaskToSection()
        selectedSectionTarget = nil
        expandedTaskIDs.insert(taskID)
        addingChildToTaskID = taskID
        childTaskDraft = ""
        Task { @MainActor in
            await Task.yield()
            childTaskFocused = true
        }
    }

    private func commitAddingChild() {
        guard let parentID = addingChildToTaskID,
              let parent = model.task(withID: parentID) else {
            cancelAddingChild()
            return
        }
        let title = childTaskDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            cancelAddingChild()
            return
        }
        model.addSubtask(title: title, to: parent.id)
        childTaskFocused = false
        childTaskDraft = ""
        addingChildToTaskID = nil
    }

    private func cancelAddingChild() {
        childTaskFocused = false
        childTaskDraft = ""
        addingChildToTaskID = nil
    }

}

private struct TaskDragPreview: View {
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(ModernPalette.muted)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 14)
        .frame(width: 280, height: 36)
        .background(.clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .plannerControlSurface(in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
    }
}

struct ModernTaskHeader: View {
    @Environment(AppModel.self) private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var sectionCreationActive: Bool
    @Binding var sectionDraft: String
    @Binding var taskSearchExpanded: Bool
    @Binding var taskSearchQuery: String
    let onRequestNewSection: () -> Void
    let onCommitSection: () -> Void
    let onCancelSection: () -> Void
    @FocusState private var sectionCreationFocused: Bool
    @FocusState private var taskSearchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(model.selectedProject?.name ?? model.currentWorkspace.name)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(ModernPalette.ink)
                    .lineLimit(1)
                Spacer()
                Button(action: onRequestNewSection) {
                    Image(systemName: "folder.badge.plus")
                }
                .buttonStyle(ModernQuietButtonStyle())
                .disabled(model.selection.selectedProjectID == nil || sectionCreationActive)
                .help(model.selection.selectedProjectID == nil ? "请先选择一个项目" : "新建任务分区")
                .accessibilityLabel("新建任务分区")

                taskSearchControl
            }
            .padding(.horizontal, 24)
            .frame(height: 50)

            Divider()

            if sectionCreationActive {
                HStack(spacing: 8) {
                    TextField("新建分区", text: $sectionDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(ModernPalette.accent)
                        .focused($sectionCreationFocused)
                        .task {
                            await Task.yield()
                            sectionCreationFocused = true
                        }
                        .onSubmit {
                            onCommitSection()
                            sectionCreationFocused = false
                        }
                    Button {
                        sectionCreationFocused = false
                        onCancelSection()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(ModernPalette.muted)
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(ModernPalette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.22),
            value: sectionCreationActive
        )
    }

    private var taskSearchControl: some View {
        HStack(spacing: taskSearchExpanded ? 6 : 0) {
            Button(action: toggleTaskSearch) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(taskSearchExpanded ? ModernPalette.blue : ModernPalette.ink)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help(taskSearchExpanded ? "关闭项目内搜索" : "搜索此项目的任务")
            .accessibilityLabel(taskSearchExpanded ? "关闭项目内搜索" : "搜索此项目的任务")

            if taskSearchExpanded {
                TextField("搜索任务", text: $taskSearchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($taskSearchFocused)
                    .onExitCommand(perform: handleSearchExit)
                    .transition(.opacity)

                if !taskSearchQuery.isEmpty {
                    Button {
                        taskSearchQuery = ""
                        taskSearchFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11.5))
                            .foregroundStyle(ModernPalette.muted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清空项目内搜索")
                }
            }
        }
        .padding(.horizontal, taskSearchExpanded ? 6 : 3)
        .frame(width: taskSearchExpanded ? 188 : 30, height: 30, alignment: .leading)
        .background(
            taskSearchExpanded ? ModernPalette.panel : Color.clear,
            in: Capsule()
        )
        .overlay {
            if taskSearchExpanded {
                Capsule()
                    .stroke(
                        taskSearchFocused ? ModernPalette.blue.opacity(0.38) : ModernPalette.line.opacity(0.64),
                        lineWidth: 0.75
                    )
            }
        }
        .disabled(model.selection.selectedProjectID == nil)
        .opacity(model.selection.selectedProjectID == nil ? 0.38 : 1)
        .animation(
            reduceMotion ? .easeOut(duration: 0.10) : .snappy(duration: 0.22),
            value: taskSearchExpanded
        )
        .task(id: taskSearchExpanded) {
            guard taskSearchExpanded else {
                taskSearchFocused = false
                return
            }
            await Task.yield()
            taskSearchFocused = true
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: TaskSearchFramePreferenceKey.self,
                    value: proxy.frame(in: .named("content-root"))
                )
            }
        }
    }

    private func toggleTaskSearch() {
        guard model.selection.selectedProjectID != nil else { return }
        withAnimation(reduceMotion ? .easeOut(duration: 0.10) : .snappy(duration: 0.22)) {
            taskSearchExpanded.toggle()
            if !taskSearchExpanded {
                taskSearchQuery = ""
                taskSearchFocused = false
            }
        }
    }

    private func handleSearchExit() {
        if taskSearchQuery.isEmpty {
            toggleTaskSearch()
        } else {
            taskSearchQuery = ""
        }
    }
}

struct ModernQuickTaskDraft: Equatable {
    var title = ""
    var hasPlan = false
    var hasPlannedEnd = false
    var plannedStart = Date.now
    var plannedEnd = Date.now
    var plannedPrecision = DeadlinePrecision.date
    var hasDeadline = false
    var deadline = Date.now
    var deadlinePrecision = DeadlinePrecision.date
    var priority = Priority.none
    var actionList = ActionList.nextAction
    var tags: [String] = []

    var hasStagedContent: Bool {
        !title.isEmpty
            || hasPlan
            || hasPlannedEnd
            || plannedPrecision != .date
            || hasDeadline
            || deadlinePrecision != .date
            || priority != .none
            || actionList != .nextAction
            || !tags.isEmpty
    }

    mutating func reset() {
        self = ModernQuickTaskDraft()
    }
}

struct ModernQuickTaskComposer: View {
    @Binding var draft: ModernQuickTaskDraft
    @FocusState.Binding var isFocused: Bool
    var placeholder = "添加任务，按 Enter 创建"
    let onSubmit: () -> Void
    @State private var showPlanEditor = false
    @State private var showDeadlineEditor = false
    @State private var showTagEditor = false

    var body: some View {
        HStack(spacing: 9) {
            Button { isFocused = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(ModernPalette.muted)
            .accessibilityLabel("聚焦快速创建任务")

            TextField(placeholder, text: $draft.title)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused($isFocused)
                .onSubmit(onSubmit)

            if !draft.title.isEmpty {
                Button { draft.title = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(ModernPalette.muted)
                    .accessibilityLabel("清空任务标题")
            }

            Spacer(minLength: 4)

            Button {
                showPlanEditor = true
            } label: {
                Image(systemName: "calendar")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(draft.hasPlan ? ModernPalette.blue : ModernPalette.railInk)
            .help("设置计划时间")
            .accessibilityLabel("设置计划时间")
            .accessibilityValue(draft.hasPlan ? "已设置" : "未设置")
            .popover(isPresented: $showPlanEditor, arrowEdge: .bottom) {
                ModernPlanDateEditor(
                    hasValue: $draft.hasPlan,
                    hasEnd: $draft.hasPlannedEnd,
                    start: $draft.plannedStart,
                    end: $draft.plannedEnd,
                    precision: $draft.plannedPrecision
                )
            }

            Button {
                showDeadlineEditor = true
            } label: {
                Image(systemName: "calendar.badge.exclamationmark")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(draft.hasDeadline ? ModernPalette.red : ModernPalette.railInk)
            .help("设置截止时间")
            .accessibilityLabel("设置截止时间")
            .accessibilityValue(draft.hasDeadline ? "已设置" : "未设置")
            .popover(isPresented: $showDeadlineEditor, arrowEdge: .bottom) {
                ModernDeadlineDateEditor(
                    hasValue: $draft.hasDeadline,
                    deadline: $draft.deadline,
                    precision: $draft.deadlinePrecision
                )
            }

            Menu {
                ForEach(Priority.allCases) { priority in
                    Button {
                        draft.priority = priority
                    } label: {
                        Label(priority.title, systemImage: priority == .none ? "flag" : "flag.fill")
                    }
                }
            } label: {
                Image(systemName: draft.priority == .none ? "flag" : "flag.fill")
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .foregroundStyle(draft.priority == .none ? ModernPalette.railInk : Color(hex: draft.priority.color))
            .help("设置优先级")
            .accessibilityLabel("设置优先级")
            .accessibilityValue(draft.priority.title)

            Menu {
                ForEach(ActionList.allCases) { actionList in
                    Button {
                        draft.actionList = actionList
                    } label: {
                        Label(actionList.title, systemImage: actionList.icon)
                    }
                }
            } label: {
                Image(systemName: draft.actionList.icon)
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .foregroundStyle(draft.actionList == .nextAction ? ModernPalette.railInk : ModernPalette.blue)
            .help("设置行动列表")
            .accessibilityLabel("设置行动列表")
            .accessibilityValue(draft.actionList.title)

            Button {
                showTagEditor = true
            } label: {
                Image(systemName: draft.tags.isEmpty ? "tag" : "tag.fill")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(draft.tags.isEmpty ? ModernPalette.railInk : ModernPalette.blue)
            .help("设置标签")
            .accessibilityLabel("设置标签")
            .accessibilityValue(draft.tags.isEmpty ? "未设置" : draft.tags.joined(separator: "、"))
            .popover(isPresented: $showTagEditor, arrowEdge: .bottom) {
                ModernTaskTagEditor(tags: $draft.tags, onChange: {})
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(ModernPalette.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isFocused ? ModernPalette.blue.opacity(0.40) : ModernPalette.line.opacity(0.55), lineWidth: 0.75)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: QuickTaskFramePreferenceKey.self,
                    value: proxy.frame(in: .named("content-root"))
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("快速创建任务")
    }
}

struct ModernTaskSectionRow: View {
    let section: ProjectSection
    let taskCount: Int
    let selected: Bool
    let collapsed: Bool
    let reportsFrame: Bool
    let allowsNativeDrop: Bool
    let customDropHighlighted: Bool
    let onSelect: () -> Void
    let onToggleCollapsed: () -> Void
    let onAddTask: () -> Void
    let onDropTask: @MainActor @Sendable (UUID) -> Bool
    let onDropSection: @MainActor @Sendable (UUID) -> Bool
    let onRename: (ProjectSection) -> Void
    let onDelete: () -> Void
    @State private var isDropTargeted = false
    @State private var isRenaming = false
    @State private var draftName = ""
    @FocusState private var renameFocused: Bool

    @ViewBuilder
    var body: some View {
        if allowsNativeDrop {
            sectionRowContent
                .onDrag {
                    NSItemProvider(object: NSString(string: "section:\(section.id.uuidString)"))
                }
                .onDrop(
                    of: [UTType.text.identifier, UTType.utf8PlainText.identifier, UTType.plainText.identifier],
                    isTargeted: $isDropTargeted
                ) { providers in
                    handleDrop(providers)
                }
        } else {
            sectionRowContent
        }
    }

    private var sectionRowContent: some View {
        HStack(spacing: 4) {
            Button(action: onToggleCollapsed) {
                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(ModernPalette.muted)
                    .frame(width: 20, height: 28)
                    .contentShape(Rectangle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .help(collapsed ? "展开分区" : "折叠分区")
            .accessibilityLabel(collapsed ? "展开分区" : "折叠分区")

            if isRenaming {
                TextField("分区名称", text: $draftName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: section.colorHex))
                    .focused($renameFocused)
                    .onSubmit(commitRename)
                    .onExitCommand(perform: cancelRename)
                    .task(id: isRenaming) {
                        guard isRenaming else { return }
                        await Task.yield()
                        renameFocused = true
                    }
            } else {
                Button(action: onSelect) {
                    HStack(spacing: 8) {
                        Text(section.name)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color(hex: section.colorHex))
                            .lineLimit(1)
                        Text("\(taskCount)")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(ModernPalette.muted)
                        Spacer(minLength: 8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .simultaneousGesture(
                    TapGesture(count: 2)
                        .onEnded(onToggleCollapsed)
                )
                .accessibilityLabel("\(section.name)，\(taskCount) 个任务")
                .accessibilityHint("单击选择，双击折叠或展开")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }

            Menu {
                Button("新建任务", systemImage: "plus", action: onAddTask)
                Button("重命名", systemImage: "pencil", action: beginRename)
                Divider()
                Button("删除", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ModernPalette.muted)
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .help("分区操作")
            .accessibilityLabel("分区操作：\(section.name)")
        }
        .padding(.horizontal, 16)
        .padding(.top, 13)
        .padding(.bottom, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (isDropTargeted || customDropHighlighted)
                ? Color(hex: section.colorHex).opacity(0.12)
                : (selected ? Color(hex: section.colorHex).opacity(0.065) : .clear),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay {
            if isDropTargeted || customDropHighlighted || selected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        Color(hex: section.colorHex).opacity(isDropTargeted || customDropHighlighted ? 0.34 : 0.24),
                        lineWidth: 1
                    )
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(hex: section.colorHex).opacity(0.46))
                .frame(height: 0.75)
                .padding(.horizontal, 16)
        }
        .background {
            if reportsFrame {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: TaskSectionFramesPreferenceKey.self,
                        value: [section.id.uuidString: proxy.frame(in: .named(taskListContentCoordinateSpace))]
                    )
                }
            }
        }
        .contentShape(Rectangle())
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let payload = object as? NSString else { return }
            let value = String(payload)
            Task { @MainActor in
                if let id = UUID(uuidString: String(value.dropFirst(5))), value.hasPrefix("task:") {
                    _ = onDropTask(id)
                } else if let id = UUID(uuidString: String(value.dropFirst(8))), value.hasPrefix("section:") {
                    _ = onDropSection(id)
                }
            }
        }
        return true
    }

    private func beginRename() {
        onSelect()
        draftName = section.name
        isRenaming = true
    }

    private func commitRename() {
        let cleanName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else {
            cancelRename()
            return
        }

        var updated = section
        updated.name = cleanName
        onRename(updated)
        renameFocused = false
        isRenaming = false
    }

    private func cancelRename() {
        draftName = section.name
        renameFocused = false
        isRenaming = false
    }
}

struct ModernUnassignedTaskSectionRow: View {
    let taskCount: Int
    let selected: Bool
    let collapsed: Bool
    let reportsFrame: Bool
    let customDropHighlighted: Bool
    let onSelect: () -> Void
    let onToggleCollapsed: () -> Void
    let onAddTask: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onToggleCollapsed) {
                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(ModernPalette.muted)
                    .frame(width: 20, height: 28)
                    .contentShape(Rectangle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .help(collapsed ? "展开未分区任务" : "折叠未分区任务")
            .accessibilityLabel(collapsed ? "展开未分区任务" : "折叠未分区任务")

            Button(action: onSelect) {
                HStack(spacing: 8) {
                    Text("未分区")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ModernPalette.muted)
                    Text("\(taskCount)")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(ModernPalette.muted)
                    Spacer(minLength: 8)
                }
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                TapGesture(count: 2)
                    .onEnded(onToggleCollapsed)
            )
            .accessibilityLabel("未分区，\(taskCount) 个任务")
            .accessibilityHint("单击选择，双击折叠或展开")
            .accessibilityAddTraits(selected ? .isSelected : [])

            Menu {
                Button("新建任务", systemImage: "plus", action: onAddTask)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ModernPalette.muted)
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .help("未分区操作")
            .accessibilityLabel("未分区操作")
        }
        .padding(.horizontal, 16)
        .padding(.top, 13)
        .padding(.bottom, 5)
        .background(
            customDropHighlighted
                ? ModernPalette.blue.opacity(0.10)
                : (selected ? ModernPalette.blue.opacity(0.055) : .clear),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay {
            if customDropHighlighted || selected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(ModernPalette.blue.opacity(customDropHighlighted ? 0.30 : 0.22), lineWidth: 1)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ModernPalette.line.opacity(0.72))
                .frame(height: 0.75)
                .padding(.horizontal, 16)
        }
        .background {
            if reportsFrame {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: TaskSectionFramesPreferenceKey.self,
                        value: [unassignedTaskSectionKey: proxy.frame(in: .named(taskListContentCoordinateSpace))]
                    )
                }
            }
        }
    }
}

private struct ModernEmptyTaskDropRow: View {
    let sectionID: UUID
    let reportsFrame: Bool
    let highlighted: Bool

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(
                highlighted ? ModernPalette.blue.opacity(0.08) : .clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                if highlighted {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(ModernPalette.blue.opacity(0.26), lineWidth: 1)
                }
            }
            .background {
                if reportsFrame {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: TaskSectionFramesPreferenceKey.self,
                            value: [sectionID.uuidString: proxy.frame(in: .named(taskListContentCoordinateSpace))]
                        )
                    }
                }
            }
    }
}

struct ModernTaskRow: View {
    let task: GTDTask
    let depth: Int
    let hasChildren: Bool
    let isExpanded: Bool
    let selected: Bool
    let isBeingDragged: Bool
    let isDropTargeted: Bool
    let isParentDropTargeted: Bool
    let reportsFrame: Bool
    var secondaryText: String? = nil
    var showsMetadata = true
    var allowsAddingChildren = true
    @Binding var editingTaskTitleID: UUID?
    @FocusState.Binding var taskTitleFocusedID: UUID?
    let onToggleExpanded: () -> Void
    let onAddChild: () -> Void
    let onSelect: () -> Void
    let onToggle: () -> Void
    let onDelete: () -> Void
    let onRename: (GTDTask) -> Void
    let onDragChanged: ((UUID, CGPoint, CGFloat) -> Void)?
    let onDragEnded: ((UUID, CGPoint, CGFloat) -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draftTitle = ""
    @State private var isHovered = false
    @State private var pendingExpansionToggle: Task<Void, Never>?
    @State private var suppressPrimaryClickUntil: TimeInterval = 0

    private var isRenaming: Bool { editingTaskTitleID == task.id }
    private var visualDepth: Int { min(depth, 6) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Button {
                handlePrimaryClick()
            } label: {
                HStack(alignment: .center, spacing: 8) {
                    HStack(spacing: 4) {
                        Color.clear
                            .frame(width: CGFloat(visualDepth) * 18)
                        Color.clear
                            .frame(width: 18)
                        // Reserve the checkbox column in the selection button.
                        // The real controls are layered above it below.
                        Color.clear
                            .frame(width: 28)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.title)
                            .font(.system(size: 13, weight: task.status.isFinished ? .regular : .medium))
                            .foregroundStyle(task.status.isFinished ? ModernPalette.muted : ModernPalette.ink)
                            .strikethrough(task.status.isFinished, color: ModernPalette.muted)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if let secondaryText {
                            Text(secondaryText)
                                .font(.system(size: 10.5))
                                .foregroundStyle(ModernPalette.muted)
                                .lineLimit(1)
                        } else if !task.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(task.note)
                                .font(.system(size: 10.5))
                                .foregroundStyle(ModernPalette.muted)
                                .lineLimit(1)
                        }
                    }
                    .opacity(isRenaming ? 0 : 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
                    .simultaneousGesture(
                        TapGesture(count: 2)
                            .onEnded(handleTitleDoubleClick)
                    )

                    if showsMetadata {
                        ModernTaskMetadataRow(task: task)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .highPriorityGesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .named(taskListContentCoordinateSpace))
                    .onChanged { value in
                        onDragChanged?(task.id, value.location, value.translation.width)
                    }
                    .onEnded { value in
                        onDragEnded?(task.id, value.location, value.translation.width)
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(task.title)
            .accessibilityHint("选择任务")

            if isRenaming {
                taskTitleEditor
                    .zIndex(2)
            }

            HStack(alignment: .top, spacing: 4) {
                Color.clear
                    .frame(width: CGFloat(visualDepth) * 18)

                if hasChildren {
                    Button(action: toggleExpandedImmediately) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .accessibilityHidden(true)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(ModernPalette.muted)
                            .frame(width: 18, height: 28)
                            .contentShape(Rectangle())
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)
                    .help(isExpanded ? "折叠下级任务" : "展开下级任务")
                    .accessibilityLabel(isExpanded ? "折叠下级任务" : "展开下级任务")
                } else if allowsAddingChildren {
                    // Keep the leaf-task control column spatially stable. The
                    // button remains in the tree and only its visual state
                    // changes on hover, avoiding insert/remove transitions.
                    Button(action: onAddChild) {
                        Image(systemName: "plus")
                            .accessibilityHidden(true)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(ModernPalette.blue)
                            .frame(width: 18, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("添加下级任务")
                    .accessibilityLabel("给“\(task.title)”添加下级任务")
                    .opacity(isHovered ? 1 : 0)
                    .allowsHitTesting(isHovered)
                } else {
                    Color.clear
                        .frame(width: 18, height: 28)
                }

                Button(action: onToggle) {
                    Image(systemName: completionSymbol)
                        .accessibilityHidden(true)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(completionColor)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(task.status == .done ? "重新打开任务" : "完成任务")
                .accessibilityValue(task.status.title)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
        .opacity(isBeingDragged ? 0.28 : 1)
        .background(
            (isDropTargeted || isParentDropTargeted)
                ? ModernPalette.blue.opacity(0.10)
                : (selected ? ModernPalette.blue.opacity(0.035) : .clear),
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .overlay {
            if isDropTargeted || isParentDropTargeted || selected {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(
                        isDropTargeted || isParentDropTargeted
                            ? ModernPalette.blue.opacity(0.34)
                            : ModernPalette.blue.opacity(0.68),
                        lineWidth: 1
                    )
            }
        }
        .shadow(color: selected ? ModernPalette.blue.opacity(0.055) : .clear, radius: 5, y: 1)
        .padding(.horizontal, 10)
        .overlay(alignment: .top) {
            if isDropTargeted {
                Capsule()
                    .fill(ModernPalette.blue)
                    .frame(height: 2)
                    .padding(.leading, 8 + CGFloat(visualDepth) * 18)
                    .padding(.trailing, 8)
                    .transition(.opacity)
            }
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.08) : .snappy(duration: 0.16),
            value: selected
        )
        .animation(
            reduceMotion ? nil : .snappy(duration: 0.18),
            value: task.status
        )
        .plannerTaskActions(taskID: task.id, onAddChild: allowsAddingChildren ? onAddChild : nil)
        .onChange(of: taskTitleFocusedID) { _, focusedID in
            guard isRenaming, focusedID != task.id else { return }
            commitRename()
        }
        .onChange(of: selected) { _, isSelected in
            if !isSelected { cancelPendingExpansionToggle() }
        }
        .onChange(of: isRenaming) { _, renaming in
            if renaming { cancelPendingExpansionToggle() }
        }
        .background {
            if reportsFrame {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: TaskRowFramesPreferenceKey.self,
                        value: [task.id: proxy.frame(in: .named(taskListContentCoordinateSpace))]
                    )
                }
            }
        }
        .onHover { isHovered = $0 }
        .onDisappear { cancelPendingExpansionToggle() }
    }

    private var completionSymbol: String {
        switch task.status {
        case .done:
            "checkmark.circle.fill"
        case .cancelled:
            "minus.circle.fill"
        default:
            "circle"
        }
    }

    private var completionColor: Color {
        switch task.status {
        case .done:
            ModernPalette.completion
        case .cancelled:
            ModernPalette.muted.opacity(0.82)
        default:
            ModernPalette.muted
        }
    }

    private var taskTitleEditor: some View {
        HStack(alignment: .top, spacing: 8) {
            HStack(spacing: 4) {
                Color.clear
                    .frame(width: CGFloat(visualDepth) * 18)
                Color.clear.frame(width: 18)
                Color.clear.frame(width: 28)
            }

            TextField("任务名称", text: $draftTitle, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: task.status.isFinished ? .regular : .medium))
                .foregroundStyle(task.status.isFinished ? ModernPalette.muted : ModernPalette.blue)
                .strikethrough(task.status.isFinished, color: ModernPalette.muted)
                .lineLimit(1...3)
                .fixedSize(horizontal: false, vertical: true)
                .focused($taskTitleFocusedID, equals: task.id)
                .onSubmit(commitRename)
                .onExitCommand(perform: cancelRename)
                .task(id: isRenaming) {
                    guard isRenaming else { return }
                    await Task.yield()
                    taskTitleFocusedID = task.id
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: TaskTitleFramePreferenceKey.self,
                            value: proxy.frame(in: .named("content-root"))
                        )
                    }
                }

        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: 38, alignment: .topLeading)
        .background(ModernPalette.panel, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func handlePrimaryClick() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now >= suppressPrimaryClickUntil else { return }

        switch TaskRowClickPolicy.resolve(
            intent: .primary,
            isSelected: selected,
            hasChildren: hasChildren,
            isRenaming: isRenaming
        ) {
        case .select:
            cancelPendingExpansionToggle()
            onSelect()
        case .scheduleExpansionToggle:
            scheduleExpansionToggle()
        case .beginRename, .toggleExpansionImmediately, .none:
            break
        }
    }

    private func handleTitleDoubleClick() {
        guard TaskRowClickPolicy.resolve(
            intent: .titleDoubleClick,
            isSelected: selected,
            hasChildren: hasChildren,
            isRenaming: isRenaming
        ) == .beginRename else { return }

        suppressPrimaryClickUntil = ProcessInfo.processInfo.systemUptime + NSEvent.doubleClickInterval
        cancelPendingExpansionToggle()
        beginRename()
    }

    private func scheduleExpansionToggle() {
        cancelPendingExpansionToggle()
        let delay = NSEvent.doubleClickInterval
        pendingExpansionToggle = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            pendingExpansionToggle = nil
            onToggleExpanded()
        }
    }

    private func toggleExpandedImmediately() {
        guard TaskRowClickPolicy.resolve(
            intent: .disclosure,
            isSelected: selected,
            hasChildren: hasChildren,
            isRenaming: isRenaming
        ) == .toggleExpansionImmediately else { return }
        cancelPendingExpansionToggle()
        onToggleExpanded()
    }

    private func cancelPendingExpansionToggle() {
        pendingExpansionToggle?.cancel()
        pendingExpansionToggle = nil
    }

    private func beginRename() {
        cancelPendingExpansionToggle()
        onSelect()
        draftTitle = task.title
        editingTaskTitleID = task.id
    }

    private func commitRename() {
        guard isRenaming else { return }
        let cleanTitle = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            cancelRename()
            return
        }

        if cleanTitle != task.title {
            var updated = task
            updated.title = cleanTitle
            onRename(updated)
        }
        taskTitleFocusedID = nil
        editingTaskTitleID = nil
    }

    private func cancelRename() {
        taskTitleFocusedID = nil
        editingTaskTitleID = nil
        draftTitle = task.title
    }
}

private struct ModernInlineSectionTaskEditor: View {
    @Binding var draft: String
    @FocusState.Binding var isFocused: Bool
    let onCommit: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(ModernPalette.blue)
                .frame(width: 28)

            TextField("在此分区新建任务…", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .focused($isFocused)
                .onSubmit(onCommit)
                .onExitCommand(perform: onCancel)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        .background(ModernPalette.blue.opacity(0.055))
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: InlineChildTaskFramePreferenceKey.self,
                    value: proxy.frame(in: .named(taskListContentCoordinateSpace))
                )
            }
        }
        .accessibilityLabel("分区内新任务名称")
    }
}

private struct ModernInlineChildTaskEditor: View {
    let depth: Int
    @Binding var draft: String
    @FocusState.Binding var isFocused: Bool
    let onCommit: () -> Void
    let onCancel: () -> Void

    private var visualDepth: Int { min(depth, 6) }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Color.clear
                    .frame(width: CGFloat(visualDepth) * 18)
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ModernPalette.muted)
                    .frame(width: 18)
                Image(systemName: "circle")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(ModernPalette.muted)
                    .frame(width: 28)
            }

            TextField("添加下级任务…", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .focused($isFocused)
                .onSubmit(onCommit)
                .onExitCommand(perform: onCancel)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .background(ModernPalette.blue.opacity(0.055))
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: InlineChildTaskFramePreferenceKey.self,
                    value: proxy.frame(in: .named(taskListContentCoordinateSpace))
                )
            }
        }
        .accessibilityLabel("下级任务名称")
    }
}

private struct ModernTaskMetadataRow: View {
    let task: GTDTask

    private var hasMetadata: Bool {
        task.plannedStart != nil || task.deadline != nil || !task.tags.isEmpty || task.priority != .none
    }

    var body: some View {
        if hasMetadata {
            HStack(spacing: 10) {
                if task.plannedStart != nil {
                    Label(modernPlannedRangeText(task), systemImage: "calendar")
                        .foregroundStyle(modernScheduleColor(task.plannedStart))
                }

                if let deadline = task.deadline {
                    Label(modernDeadlineText(task), systemImage: "calendar.badge.exclamationmark")
                        .foregroundStyle(deadlineColor(deadline))
                }

                if task.priority != .none {
                    ModernPriorityValue(priority: task.priority)
                }

                if !task.tags.isEmpty {
                    ModernTaskTagChips(tags: task.tags)
                }
            }
            .font(.system(size: 10.5))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func deadlineColor(_ deadline: Date) -> Color {
        let calendar = Calendar.current
        return deadline < .now || calendar.isDateInToday(deadline) ? ModernPalette.red : ModernPalette.ink
    }
}

struct ModernTaskTagChips: View {
    @Environment(AppModel.self) private var model: AppModel
    let tags: [String]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(tags.prefix(2)), id: \.self) { tag in
                Text(tag)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(tagColor(tag))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(tagColor(tag).opacity(0.13), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .lineLimit(1)
            }
            if tags.count > 2 {
                Text("+\(tags.count - 2)")
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(ModernPalette.muted)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(ModernPalette.subtle, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func tagColor(_ name: String) -> Color {
        model.currentTagDefinitions.first {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }.map { Color(hex: $0.colorHex) } ?? modernTagColor(name)
    }
}

struct ModernPriorityValue: View {
    let priority: Priority

    var body: some View {
        if priority == .none {
            Text("—")
                .font(.system(size: 11))
                .foregroundStyle(ModernPalette.muted)
        } else {
            HStack(spacing: 4) {
                Image(systemName: "flag.fill")
                    .font(.system(size: 11, weight: .medium))
                Text(priority.title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(Color(hex: priority.color))
        }
    }

}

struct ModernInspectorPane: View {
    @Environment(AppModel.self) private var model: AppModel
    @FocusState.Binding var inspectorNoteFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(ModernPalette.ink)
                    .accessibilityLabel("任务详情")
                Spacer()
                if model.selectedTask != nil {
                    Button { model.clearSelectedTask() } label: {
                        Image(systemName: "xmark")
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(ModernPalette.railInk)
                    .help("关闭任务详情")
                    .accessibilityLabel("关闭任务详情")
                }
            }
            .padding(.horizontal, 20)
            .frame(height: 50)
            Divider()

            if let task = model.selectedTask {
                ModernTaskInspector(task: task, noteFocused: $inspectorNoteFocused)
                    .id(task.id)
            } else if let project = model.selectedProject {
                ModernProjectInspector(project: project)
            } else {
                EmptyColumnHint(
                    icon: "cursorarrow.click.2",
                    title: "选择一个任务或项目",
                    message: "点击中间列表中的任务或项目，详情会在这里展开并可以直接修改",
                    iconColor: ModernPalette.accent
                )
                    .padding(.horizontal, 22)
            }
            Spacer(minLength: 0)
        }
        .background(ModernPalette.panel)
    }
}

struct ModernProjectInspector: View {
    @Environment(AppModel.self) private var model: AppModel
    let project: Project
    @State private var name: String
    @State private var category: String
    @State private var note: String
    @State private var symbolName: String
    @State private var iconColor: Color
    @FocusState private var focusedField: ProjectInspectorField?

    private let iconChoices = [
        "folder", "briefcase", "book.closed", "graduationcap", "house", "heart",
        "star", "flag", "calendar", "bolt", "person.2", "globe",
        "hammer", "paintbrush", "camera", "music.note", "cart", "archivebox",
        "lightbulb", "leaf", "figure.walk", "gamecontroller", "terminal", "doc.text"
    ]

    private enum ProjectInspectorField: Hashable {
        case name
        case category
        case note
    }

    init(project: Project) {
        self.project = project
        _name = State(initialValue: project.name)
        _category = State(initialValue: project.category)
        _note = State(initialValue: project.note)
        _symbolName = State(initialValue: project.symbolName)
        _iconColor = State(initialValue: Color(hex: project.colorHex))
    }

    private var taskCount: Int {
        model.taskCount(for: project.id)
    }

    private var activeTaskCount: Int {
        model.taskCount(for: project.id, includeFinished: false)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: symbolName)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(iconColor)
                        .frame(width: 24, height: 28)
                    TextField("项目名称", text: $name)
                        .textFieldStyle(.plain)
                        .font(.system(size: 19, weight: .semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                        .focused($focusedField, equals: .name)
                        .onSubmit { save() }
                        .padding(.vertical, 3)
                        .background(
                            focusedField == .name ? ModernPalette.subtle.opacity(0.85) : .clear,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                        .contentShape(Rectangle())
                }
                .padding(.bottom, 18)

                ModernInspectorValue(title: "工作区", icon: "square.grid.2x2") {
                    Text(model.currentWorkspace.name)
                        .foregroundStyle(ModernPalette.ink)
                }

                ModernInspectorValue(title: "分类", icon: "folder.badge.gearshape") {
                    TextField("未分组", text: $category)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(ModernPalette.ink)
                        .focused($focusedField, equals: .category)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "paintpalette")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(ModernPalette.muted)
                            .frame(width: 18)
                        Text("项目图标")
                            .font(.system(size: 11))
                            .foregroundStyle(ModernPalette.muted)
                        Spacer()
                        HStack(spacing: 6) {
                            Image(systemName: symbolName)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(iconColor)
                            Text("图标颜色")
                                .font(.system(size: 11))
                                .foregroundStyle(ModernPalette.muted)
                            ColorPicker("", selection: $iconColor, supportsOpacity: false)
                                .labelsHidden()
                        }
                    }

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                        ForEach(iconChoices, id: \.self) { symbol in
                            Button {
                                symbolName = symbol
                            } label: {
                                Image(systemName: symbol)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(symbolName == symbol ? iconColor : ModernPalette.muted)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 28)
                                    .background(
                                        symbolName == symbol ? iconColor.opacity(0.12) : ModernPalette.subtle,
                                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(symbol)
                        }
                    }
                }
                .padding(.vertical, 14)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(ModernPalette.line.opacity(0.55))
                        .frame(height: 0.5)
                }

                ModernInspectorValue(title: "任务", icon: "checklist") {
                    Text("\(activeTaskCount) 个进行中 · \(taskCount) 个总计")
                        .foregroundStyle(ModernPalette.ink)
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text("项目备注")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ModernPalette.ink)
                    TextEditor(text: $note)
                        .font(.system(size: 12))
                        .scrollContentBackground(.hidden)
                        .padding(9)
                        .frame(minHeight: 120)
                        .background(ModernPalette.subtle, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .focused($focusedField, equals: .note)
                }
                .padding(.vertical, 14)
            }
            .padding(20)
        }
        .onAppear { load() }
        .onChange(of: project) { _, _ in load() }
        .onChange(of: name) { _, _ in saveIfValid() }
        .onChange(of: category) { _, _ in saveIfValid() }
        .onChange(of: note) { _, _ in saveIfValid() }
        .onChange(of: symbolName) { _, _ in saveIfValid() }
        .onChange(of: iconColor) { _, _ in saveIfValid() }
    }

    private func load() {
        name = project.name
        category = project.category
        note = project.note
        symbolName = project.symbolName
        iconColor = Color(hex: project.colorHex)
    }

    private func save() {
        let original = model.projectIndex.projectByID[project.id] ?? project
        var updated = original
        updated.name = name
        updated.category = category
        updated.note = note
        updated.symbolName = symbolName
        updated.colorHex = hexString(from: iconColor)
        guard updated != original else { return }
        model.updateProject(updated)
    }

    private func saveIfValid() {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        save()
    }
}

struct LegacyModernTaskInspector: View {
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
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 10) {
                    Text(task.title)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(ModernPalette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button { editingTask = task; showTaskEditor = true } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .buttonStyle(ModernQuietButtonStyle())
                    .help("编辑完整任务")
                }
                .padding(.bottom, 18)

                ModernInspectorValue(title: "项目", icon: "folder") {
                    Text(model.project(for: task)?.name ?? "收集箱")
                        .foregroundStyle(ModernPalette.ink)
                }
                ModernInspectorValue(title: "标签", icon: "tag") {
                    if task.tags.isEmpty {
                        Text("未设置").foregroundStyle(ModernPalette.muted)
                    } else {
                        HStack(spacing: 4) {
                            ForEach(Array(task.tags.prefix(3)), id: \.self) { tag in
                                Text(tag)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(ModernPalette.blue)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(ModernPalette.blue.opacity(0.10), in: Capsule())
                            }
                        }
                    }
                }

                ModernInspectorValue(title: "计划时间", icon: "calendar") {
                    Text(task.plannedStart == nil ? "未设置" : modernPlannedRangeText(task))
                        .foregroundStyle(task.plannedStart == nil ? ModernPalette.muted : ModernPalette.ink)
                }

                ModernInspectorValue(title: "截止时间", icon: "calendar.badge.exclamationmark") {
                    if let deadline = task.deadline {
                        Text(deadline.formatted(date: .abbreviated, time: task.deadlinePrecision == .minute ? .shortened : .omitted))
                            .foregroundStyle(deadline < .now ? ModernPalette.red : ModernPalette.ink)
                    } else {
                        Text("未设置").foregroundStyle(ModernPalette.muted)
                    }
                }

                ModernInspectorValue(title: "优先级", icon: "flag") {
                    Picker("优先级", selection: Binding(get: { task.priority }, set: { var copy = task; copy.priority = $0; model.updateTask(copy) })) {
                        ForEach(Priority.allCases) { priority in
                            Text(priority.title).tag(priority)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                ModernInspectorValue(title: "状态", icon: "circle.dotted") {
                    Picker("状态", selection: Binding(
                        get: { task.status },
                        set: { model.setTaskStatus(task.id, to: $0) }
                    )) {
                        ForEach(TaskStatus.allCases) { status in
                            Text(status.title).tag(status)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text("备注")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ModernPalette.ink)
                    TextEditor(text: $note)
                        .font(.system(size: 12))
                        .scrollContentBackground(.hidden)
                        .padding(9)
                        .frame(minHeight: 90)
                        .background(ModernPalette.subtle, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .onChange(of: note) { _, value in
                            var copy = task
                            copy.note = value
                            model.updateTask(copy)
                        }
                }
                .padding(.vertical, 14)
                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("时间")
                        .font(.system(size: 12, weight: .semibold))
                    HStack {
                        Text("实际专注时间")
                        Spacer()
                        ModernActualDurationText(task: task)
                    }
                    HStack(spacing: 8) {
                        Button { model.startStopwatch(for: task) } label: {
                            Label("正计时", systemImage: "stopwatch")
                        }
                        .buttonStyle(ModernInspectorActionStyle(tint: ModernPalette.blue))
                        Button { model.startPomodoro(for: task) } label: {
                            Label("番茄钟", systemImage: "timer")
                        }
                        .buttonStyle(ModernInspectorActionStyle(tint: ModernPalette.red))
                    }
                }
                .padding(.vertical, 14)
                Divider()

                ModernMiniTimeline(task: task)
                    .padding(.top, 14)
            }
            .padding(20)
        }
    }
}

struct ModernTaskInspector: View {
    @Environment(AppModel.self) private var model: AppModel
    let task: GTDTask

    @State private var title: String
    @State private var projectID: UUID?
    @State private var sectionID: UUID?
    @State private var tags: [String]
    @State private var status: TaskStatus
    @State private var priority: Priority
    @State private var actionList: ActionList
    @State private var note: String
    @State private var recurrence: String
    @State private var hasPlan: Bool
    @State private var hasPlannedEnd: Bool
    @State private var plannedStart: Date
    @State private var plannedEnd: Date
    @State private var plannedPrecision: DeadlinePrecision
    @State private var planRangeIntent: TaskPlanRangeIntent
    @State private var hasDeadline: Bool
    @State private var deadline: Date
    @State private var deadlinePrecision: DeadlinePrecision
    @FocusState.Binding var noteFocused: Bool

    init(task: GTDTask, noteFocused: FocusState<Bool>.Binding) {
        self.task = task
        self._noteFocused = noteFocused
        _title = State(initialValue: task.title)
        _projectID = State(initialValue: task.projectID)
        _sectionID = State(initialValue: task.sectionID)
        _tags = State(initialValue: task.tags)
        _status = State(initialValue: task.status)
        _priority = State(initialValue: task.priority)
        _actionList = State(initialValue: task.actionList)
        _note = State(initialValue: task.note)
        _recurrence = State(initialValue: task.recurrence)
        _hasPlan = State(initialValue: task.plannedStart != nil)
        _hasPlannedEnd = State(initialValue: task.plannedEnd != nil)
        _plannedStart = State(initialValue: task.plannedStart ?? .now)
        _plannedEnd = State(initialValue: task.plannedEnd ?? task.plannedStart ?? .now)
        _plannedPrecision = State(initialValue: task.plannedPrecision == .none ? .date : task.plannedPrecision)
        _planRangeIntent = State(initialValue: task.planRangeIntent)
        _hasDeadline = State(initialValue: task.deadline != nil)
        _deadline = State(initialValue: task.deadline ?? .now)
        _deadlinePrecision = State(initialValue: task.deadlinePrecision == .none ? .date : task.deadlinePrecision)
    }

    private var availableSections: [ProjectSection] {
        guard let projectID else { return [] }
        return model.projectSections(for: projectID)
    }

    var body: some View {
        let displayedStatus = ModernInspectorTaskStatus(taskStatus: status)
        let descendants = model.descendants(of: task)

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ModernTaskInspectorHeader(title: $title)

                ModernInspectorPickerRow(
                    icon: "circle.dotted",
                    title: "状态",
                    value: displayedStatus.title,
                    valueColor: displayedStatus.valueColor
                ) {
                    ForEach(ModernInspectorTaskStatus.allCases) { item in
                        Button {
                            status = item.taskStatus
                            model.setTaskStatus(task.id, to: item.taskStatus)
                        } label: {
                            Label(item.title, systemImage: item.icon)
                        }
                    }
                }

                ModernInspectorPickerRow(
                    icon: priority == .none ? "flag" : "flag.fill",
                    title: "优先级",
                    value: priority.title,
                    valueColor: priority == .none ? ModernPalette.muted : Color(hex: priority.color)
                ) {
                    ForEach(Priority.allCases) { item in
                        Button {
                            priority = item
                            updateCanonical { $0.priority = item }
                        } label: {
                            Label(item.title, systemImage: item == .none ? "flag" : "flag.fill")
                        }
                    }
                }

                ModernInspectorPickerRow(
                    icon: actionList.icon,
                    title: "行动列表",
                    value: actionList.title
                ) {
                    ForEach(ActionList.allCases) { item in
                        Button {
                            actionList = item
                            updateCanonical { $0.actionList = item }
                        } label: {
                            Label(item.title, systemImage: item.icon)
                        }
                    }
                }

                ModernInspectorPickerRow(
                    icon: "folder",
                    title: "所属项目",
                    value: model.currentProjects.first(where: { $0.id == projectID })?.name ?? "收集箱 / 无项目"
                ) {
                    Button("收集箱 / 无项目") {
                        if model.moveTaskToProject(taskID: task.id, projectID: nil) {
                            projectID = nil
                            sectionID = nil
                        }
                    }
                    ForEach(model.currentProjects) { project in
                        Button(project.name) {
                            if model.moveTaskToProject(taskID: task.id, projectID: project.id) {
                                projectID = project.id
                                sectionID = nil
                            }
                        }
                    }
                }

                ModernInspectorPickerRow(
                    icon: "rectangle.3.group",
                    title: "所在分组",
                    value: availableSections.first(where: { $0.id == sectionID })?.name ?? "未分区"
                ) {
                    Button("未分区") {
                        sectionID = nil
                        updateCanonical { $0.sectionID = nil }
                    }
                    ForEach(availableSections) { section in
                        Button(section.name) {
                            sectionID = section.id
                            updateCanonical { $0.sectionID = section.id }
                        }
                    }
                }
                .disabled(projectID == nil)

                ModernTaskTagsRow(tags: $tags) {
                    updateCanonical { $0.tags = tags }
                }

                ModernInspectorNoteRow(note: $note, isFocused: $noteFocused)
                    .onChange(of: note) { _, value in
                        updateCanonical { $0.note = value }
                    }

                ModernTaskDateSection(
                    hasPlan: $hasPlan,
                    hasPlannedEnd: $hasPlannedEnd,
                    plannedStart: $plannedStart,
                    plannedEnd: $plannedEnd,
                    plannedPrecision: $plannedPrecision,
                    hasDeadline: $hasDeadline,
                    deadline: $deadline,
                    deadlinePrecision: $deadlinePrecision
                )
                .onChange(of: hasPlan) { _, _ in savePlanIfValid() }
                .onChange(of: hasPlannedEnd) { _, _ in savePlanIfValid() }
                .onChange(of: plannedStart) { _, _ in savePlanIfValid() }
                .onChange(of: plannedEnd) { _, _ in savePlanIfValid() }
                .onChange(of: plannedPrecision) { _, _ in savePlanIfValid() }
                .onChange(of: hasDeadline) { _, _ in saveDeadline() }
                .onChange(of: deadline) { _, _ in saveDeadline() }
                .onChange(of: deadlinePrecision) { _, _ in saveDeadline() }

                if showsPlanRangeIntent {
                    ModernInspectorPickerRow(
                        icon: "calendar.day.timeline.left",
                        title: "跨日方式",
                        value: planRangeIntent.title
                    ) {
                        ForEach(TaskPlanRangeIntent.allCases) { intent in
                            Button {
                                planRangeIntent = intent
                                updateCanonical { $0.planRangeIntent = intent }
                            } label: {
                                Label(intent.title, systemImage: intent.icon)
                            }
                            .help(intent.explanation)
                        }
                    }
                }

                ModernTaskTimeSection(task: task)

                ModernInspectorValue(title: "子任务", icon: "checklist") {
                    Text("\(descendants.filter { $0.status == .done }.count)/\(descendants.count)")
                        .foregroundStyle(ModernPalette.muted)
                }

                ModernInspectorValue(title: "重复", icon: "repeat") {
                    TextField("未设置", text: $recurrence)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .onSubmit { updateCanonical { $0.recurrence = recurrence } }
                        .onChange(of: recurrence) { _, value in
                            updateCanonical { $0.recurrence = value }
                        }
                }

                ModernInspectorValue(title: "创建时间", icon: "clock") {
                    Text(task.createdAt.formatted(date: .numeric, time: .shortened))
                        .foregroundStyle(ModernPalette.muted)
                }

                ModernInspectorValue(title: "更新时间", icon: "arrow.clockwise") {
                    Text(task.updatedAt.formatted(date: .numeric, time: .shortened))
                        .foregroundStyle(ModernPalette.muted)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .onAppear { load(from: task) }
        .onChange(of: task) { _, newTask in
            load(from: newTask)
        }
        .onChange(of: title) { _, value in
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { return }
            updateCanonical { $0.title = value }
        }
    }

    private func load(from task: GTDTask) {
        title = task.title
        projectID = task.projectID
        sectionID = task.sectionID
        tags = task.tags
        status = task.status
        priority = task.priority
        actionList = task.actionList
        note = task.note
        recurrence = task.recurrence
        hasPlan = task.plannedStart != nil
        hasPlannedEnd = task.plannedEnd != nil
        plannedStart = task.plannedStart ?? .now
        plannedEnd = task.plannedEnd ?? task.plannedStart ?? .now
        plannedPrecision = task.plannedPrecision == .none ? .date : task.plannedPrecision
        planRangeIntent = task.planRangeIntent
        hasDeadline = task.deadline != nil
        deadline = task.deadline ?? .now
        deadlinePrecision = task.deadlinePrecision == .none ? .date : task.deadlinePrecision
    }

    private func updateCanonical(_ mutate: (inout GTDTask) -> Void) {
        guard var updated = model.task(withID: task.id) else { return }
        let original = updated
        mutate(&updated)
        guard updated != original else { return }
        model.updateTask(updated)
    }

    private func savePlanIfValid() {
        let normalizedPlan: (start: Date, end: Date?)?
        if hasPlan {
            guard let plan = TaskDateNormalizer.normalizedPlan(
                start: plannedStart,
                end: hasPlannedEnd ? plannedEnd : nil,
                precision: plannedPrecision
            ) else { return }
            normalizedPlan = plan
        } else {
            normalizedPlan = nil
        }

        updateCanonical {
            $0.plannedStart = normalizedPlan?.start
            $0.plannedEnd = normalizedPlan?.end
            $0.plannedPrecision = hasPlan ? plannedPrecision : .none
            $0.planRangeIntent = planRangeIntent
        }
    }

    private var showsPlanRangeIntent: Bool {
        guard hasPlan, hasPlannedEnd else { return false }
        return !Calendar.current.isDate(plannedStart, inSameDayAs: plannedEnd)
    }

    private func saveDeadline() {
        let normalizedDeadline = hasDeadline
            ? TaskDateNormalizer.normalizedDeadline(deadline, precision: deadlinePrecision)
            : nil

        updateCanonical {
            $0.deadline = normalizedDeadline
            $0.deadlinePrecision = hasDeadline ? deadlinePrecision : .none
        }
    }
}

private enum ModernInspectorTaskStatus: String, CaseIterable, Identifiable {
    case active
    case completed
    case abandoned

    init(taskStatus: TaskStatus) {
        switch taskStatus {
        case .done:
            self = .completed
        case .cancelled:
            self = .abandoned
        default:
            self = .active
        }
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active: "活跃"
        case .completed: "已完成"
        case .abandoned: "已放弃"
        }
    }

    var icon: String {
        switch self {
        case .active: "circle.dotted"
        case .completed: "checkmark.circle"
        case .abandoned: "slash.circle"
        }
    }

    var taskStatus: TaskStatus {
        switch self {
        case .active: .open
        case .completed: .done
        case .abandoned: .cancelled
        }
    }

    var valueColor: Color {
        switch self {
        case .active: ModernPalette.ink
        case .completed: ModernPalette.completion
        case .abandoned: ModernPalette.muted
        }
    }
}

private struct ModernTaskInspectorHeader: View {
    @Binding var title: String

    var body: some View {
        TextField("任务标题", text: $title, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 17.5, weight: .semibold))
            .foregroundStyle(ModernPalette.ink)
            .multilineTextAlignment(.leading)
            .lineLimit(1...2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(ModernPalette.line.opacity(0.55))
                    .frame(height: 0.5)
            }
    }
}

struct ModernInspectorPickerRow<MenuContent: View>: View {
    let icon: String
    let title: String
    let value: String
    var valueColor: Color = ModernPalette.ink
    @ViewBuilder let menuContent: () -> MenuContent

    init(
        icon: String,
        title: String,
        value: String,
        valueColor: Color = ModernPalette.ink,
        @ViewBuilder menuContent: @escaping () -> MenuContent
    ) {
        self.icon = icon
        self.title = title
        self.value = value
        self.valueColor = valueColor
        self.menuContent = menuContent
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ModernPalette.muted)
                .frame(width: 18)
            Text(title)
                .font(.system(size: 11.5))
                .foregroundStyle(ModernPalette.muted)
            Spacer(minLength: 8)
            Menu {
                menuContent()
            } label: {
                Text(value)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
            }
            .menuStyle(.borderlessButton)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ModernPalette.line.opacity(0.55))
                .frame(height: 0.5)
        }
    }
}

private struct ModernTaskTagsRow: View {
    @Environment(AppModel.self) private var model: AppModel
    @Binding var tags: [String]
    let onChange: () -> Void
    @State private var showEditor = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "tag")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ModernPalette.muted)
                .frame(width: 18)
                .padding(.top, 4)
            Text("标签")
                .font(.system(size: 11.5))
                .foregroundStyle(ModernPalette.muted)
                .padding(.top, 4)
            Spacer(minLength: 8)

            TagFlowLayout(spacing: 5) {
                ForEach(tags, id: \.self) { tag in
                    HStack(spacing: 4) {
                        Text(tag)
                            .font(.system(size: 10.5, weight: .medium))
                            .lineLimit(1)

                        Button {
                            removeTag(tag)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 7.5, weight: .bold))
                                .frame(width: 12, height: 12)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("移除标签 \(tag)")
                    }
                    .foregroundStyle(tagColor(tag))
                    .padding(.leading, 7)
                    .padding(.trailing, 5)
                    .padding(.vertical, 4)
                    .background(tagColor(tag).opacity(0.12), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .contextMenu {
                        Button("移除标签", role: .destructive) {
                            removeTag(tag)
                        }
                    }
                }

                Button {
                    showEditor = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 24, height: 22)
                        .background(ModernPalette.subtle, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(ModernPalette.railInk)
                .popover(isPresented: $showEditor, arrowEdge: .trailing) {
                    ModernTaskTagEditor(tags: $tags, onChange: onChange)
                }
                .accessibilityLabel("添加标签")
            }
            .frame(maxWidth: 235, alignment: .trailing)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ModernPalette.line.opacity(0.55))
                .frame(height: 0.5)
        }
    }

    private func removeTag(_ tag: String) {
        tags.removeAll { $0 == tag }
        onChange()
    }

    private func tagColor(_ name: String) -> Color {
        model.currentTagDefinitions.first {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }.map { Color(hex: $0.colorHex) } ?? modernTagColor(name)
    }
}

private struct ModernTaskTagEditor: View {
    @Environment(AppModel.self) private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Binding var tags: [String]
    let onChange: () -> Void
    @State private var draft = ""
    @FocusState private var draftFocused: Bool

    private var suggestions: [TaskTagDefinition] {
        let needle = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return Array(model.currentTagDefinitions.filter { definition in
            !tags.contains(where: {
                $0.localizedCaseInsensitiveCompare(definition.name) == .orderedSame
            }) && (needle.isEmpty || definition.name.localizedCaseInsensitiveContains(needle))
        }.prefix(10))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !tags.isEmpty {
                TagFlowLayout(spacing: 5) {
                    ForEach(tags, id: \.self) { tag in
                        HStack(spacing: 4) {
                            Text(tag)
                                .font(.system(size: 10.5, weight: .medium))
                                .lineLimit(1)
                            Button {
                                removeTag(tag)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 7.5, weight: .bold))
                                    .frame(width: 12, height: 12)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("移除标签 \(tag)")
                        }
                        .foregroundStyle(tagColor(tag))
                        .padding(.leading, 7)
                        .padding(.trailing, 5)
                        .padding(.vertical, 4)
                        .background(
                            tagColor(tag).opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("已有标签")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(ModernPalette.muted)
                    TagFlowLayout(spacing: 5) {
                        ForEach(suggestions) { definition in
                            Button {
                                addExistingTag(definition)
                            } label: {
                                Text(definition.name)
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(Color(hex: definition.colorHex))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(
                                        Color(hex: definition.colorHex).opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("标签名称", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .focused($draftFocused)
                    .onSubmit(addTag)
                Button("添加", action: addTag)
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
        .frame(width: 290)
        .task {
            await Task.yield()
            draftFocused = true
        }
    }

    private func addTag() {
        let clean = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        if !tags.contains(where: { $0.localizedCaseInsensitiveCompare(clean) == .orderedSame }) {
            tags.append(clean)
            onChange()
        }
        draft = ""
        dismiss()
    }

    private func removeTag(_ tag: String) {
        tags.removeAll { $0 == tag }
        onChange()
    }

    private func addExistingTag(_ definition: TaskTagDefinition) {
        tags.append(definition.name)
        onChange()
        draft = ""
        dismiss()
    }

    private func tagColor(_ name: String) -> Color {
        model.currentTagDefinitions.first {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }.map { Color(hex: $0.colorHex) } ?? modernTagColor(name)
    }
}

private struct ModernInspectorNoteRow: View {
    @Binding var note: String
    @FocusState.Binding var isFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "text.alignleft")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ModernPalette.muted)
                .frame(width: 18)
                .padding(.top, 2)
            Text("备注")
                .font(.system(size: 11.5))
                .foregroundStyle(ModernPalette.muted)
                .padding(.top, 2)
            Spacer(minLength: 10)
            TextField("添加备注…", text: $note, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))
                .foregroundStyle(ModernPalette.ink)
                .multilineTextAlignment(.leading)
                .lineLimit(1...4)
                .frame(maxWidth: 230, alignment: .trailing)
                .focused($isFocused)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: InspectorNoteFramePreferenceKey.self,
                            value: proxy.frame(in: .named("content-root"))
                        )
                    }
                }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ModernPalette.line.opacity(0.55))
                .frame(height: 0.5)
        }
    }
}

private struct TagFlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + (x == 0 ? 0 : spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width.isFinite ? width : x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}


private struct ModernInspectorSectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(ModernPalette.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 18)
            .padding(.bottom, 4)
    }
}

private struct ModernTaskDateSection: View {
    @Binding var hasPlan: Bool
    @Binding var hasPlannedEnd: Bool
    @Binding var plannedStart: Date
    @Binding var plannedEnd: Date
    @Binding var plannedPrecision: DeadlinePrecision
    @Binding var hasDeadline: Bool
    @Binding var deadline: Date
    @Binding var deadlinePrecision: DeadlinePrecision

    var body: some View {
        VStack(spacing: 0) {
            ModernPlanDateRow(
                hasValue: $hasPlan,
                hasEnd: $hasPlannedEnd,
                start: $plannedStart,
                end: $plannedEnd,
                precision: $plannedPrecision
            )
            ModernDeadlineDateRow(
                hasValue: $hasDeadline,
                deadline: $deadline,
                precision: $deadlinePrecision
            )
        }
    }
}

private struct ModernPlanDateRow: View {
    @Binding var hasValue: Bool
    @Binding var hasEnd: Bool
    @Binding var start: Date
    @Binding var end: Date
    @Binding var precision: DeadlinePrecision
    @State private var showPicker = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ModernPalette.muted)
                .frame(width: 18)
            Text("计划时间")
                .font(.system(size: 11.5))
                .foregroundStyle(ModernPalette.muted)
            Spacer(minLength: 8)

            Button {
                showPicker = true
            } label: {
                HStack(spacing: 6) {
                    Text(hasValue ? valueText : "未设置")
                        .font(.system(size: 12, weight: hasValue ? .medium : .regular))
                        .foregroundStyle(hasValue ? ModernPalette.ink : ModernPalette.muted)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(ModernPalette.muted)
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showPicker, arrowEdge: .trailing) {
                ModernPlanDateEditor(
                    hasValue: $hasValue,
                    hasEnd: $hasEnd,
                    start: $start,
                    end: $end,
                    precision: $precision
                )
            }

            if hasValue {
                Button {
                    hasValue = false
                    hasEnd = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .foregroundStyle(ModernPalette.railInk)
                .accessibilityLabel("清除计划时间")
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ModernPalette.line.opacity(0.55)).frame(height: 0.5)
        }
    }

    private var valueText: String {
        let calendar = Calendar.current
        if precision == .date {
            let startText = start.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits))
            guard hasEnd else { return startText }
            let displayEnd = end
            if calendar.isDate(start, inSameDayAs: displayEnd) {
                return startText
            }
            return "\(startText) – \(displayEnd.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits)))"
        }
        let startText = start.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        guard hasEnd else { return startText }
        let endText = calendar.isDate(start, inSameDayAs: end)
            ? end.formatted(date: .omitted, time: .shortened)
            : end.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        return "\(startText) – \(endText)"
    }
}

private struct ModernPlanDateEditor: View {
    @Binding var hasValue: Bool
    @Binding var hasEnd: Bool
    @Binding var start: Date
    @Binding var end: Date
    @Binding var precision: DeadlinePrecision

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("计划时间")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ModernPalette.ink)

            ModernDatePrecisionPicker(precision: $precision)

            VStack(spacing: 6) {
                ModernDateSelectionRow(
                    label: "计划于",
                    selection: $start,
                    showsTime: precision == .minute,
                    hasValue: $hasValue
                )

                if hasEnd {
                    HStack {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(ModernPalette.muted)
                            .frame(width: 42)
                        Spacer()
                    }
                    .frame(height: 8)
                    .accessibilityHidden(true)

                    ModernDateSelectionRow(
                        label: "结束",
                        selection: $end,
                        showsTime: precision == .minute,
                        hasValue: $hasValue
                    )

                    Button {
                        hasEnd = false
                    } label: {
                        Label("移除结束时间", systemImage: "minus.circle")
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(ModernPalette.railInk)
                    .frame(minHeight: 28)
                    .accessibilityHint("保留计划日期或时间点")
                } else {
                    Button {
                        end = start
                        hasEnd = true
                    } label: {
                        Label("添加结束时间", systemImage: "plus.circle")
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(hasValue ? ModernPalette.blue : ModernPalette.muted)
                    .frame(minHeight: 28)
                    .disabled(!hasValue)
                    .accessibilityHint(hasValue ? "把计划时间点改为时间段" : "先选择计划日期或时间")
                }
            }

            statusMessage

            if hasValue {
                Divider()
                Button {
                    hasValue = false
                    hasEnd = false
                } label: {
                    Label("清除计划时间", systemImage: "xmark.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(ModernPalette.railInk)
                .frame(minHeight: 28)
            }
        }
        .padding(16)
        .frame(width: 328)
    }

    private var isValid: Bool {
        TaskDateNormalizer.normalizedPlan(
            start: start,
            end: hasEnd ? end : nil,
            precision: precision
        ) != nil
    }

    @ViewBuilder
    private var statusMessage: some View {
        if hasValue && hasEnd && !isValid {
            Text("结束时间需晚于计划时间")
                .font(.system(size: 11))
                .foregroundStyle(ModernPalette.red)
        } else if !hasValue {
            Text("选择日期或时间后启用计划时间")
                .font(.system(size: 10.5))
                .foregroundStyle(ModernPalette.muted)
        }
    }
}

private struct ModernDeadlineDateRow: View {
    @Binding var hasValue: Bool
    @Binding var deadline: Date
    @Binding var precision: DeadlinePrecision
    @State private var showPicker = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ModernPalette.muted)
                .frame(width: 18)
            Text("截止时间")
                .font(.system(size: 11.5))
                .foregroundStyle(ModernPalette.muted)
            Spacer(minLength: 8)

            Button {
                showPicker = true
            } label: {
                HStack(spacing: 6) {
                    Text(hasValue ? valueText : "未设置")
                        .font(.system(size: 12, weight: hasValue ? .medium : .regular))
                        .foregroundStyle(hasValue ? ModernPalette.ink : ModernPalette.muted)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(ModernPalette.muted)
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showPicker, arrowEdge: .trailing) {
                ModernDeadlineDateEditor(
                    hasValue: $hasValue,
                    deadline: $deadline,
                    precision: $precision
                )
            }

            if hasValue {
                Button { hasValue = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .foregroundStyle(ModernPalette.railInk)
                .accessibilityLabel("清除截止时间")
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ModernPalette.line.opacity(0.55)).frame(height: 0.5)
        }
    }

    private var valueText: String {
        if precision == .minute {
            return deadline.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        }
        return deadline.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits))
    }
}

private struct ModernDeadlineDateEditor: View {
    @Binding var hasValue: Bool
    @Binding var deadline: Date
    @Binding var precision: DeadlinePrecision

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ModernPalette.muted)
                    .accessibilityHidden(true)
                Text("截止时间")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ModernPalette.ink)
            }

            ModernDatePrecisionPicker(precision: $precision)

            HStack(spacing: 6) {
                ForEach(TaskDeadlineShortcut.allCases, id: \.self) { shortcut in
                    Button(shortcut.title) {
                        deadline = TaskDateNormalizer.shortcutDeadline(shortcut)
                        hasValue = true
                    }
                    .buttonStyle(ModernDateShortcutButtonStyle())
                    .frame(maxWidth: .infinity)
                    .accessibilityHint("设置截止时间，不更改计划时间")
                }
            }

            ModernDateSelectionRow(
                label: "截止",
                selection: $deadline,
                showsTime: precision == .minute,
                hasValue: $hasValue
            )

            if !hasValue {
                Text("选择日期、时间或快捷项后启用截止时间")
                    .font(.system(size: 10.5))
                    .foregroundStyle(ModernPalette.muted)
            }

            if hasValue {
                Divider()
                Button {
                    hasValue = false
                } label: {
                    Label("清除截止时间", systemImage: "xmark.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(ModernPalette.railInk)
                .frame(minHeight: 28)
            }
        }
        .padding(16)
        .frame(width: 304)
    }
}

private struct ModernDatePrecisionPicker: View {
    @Binding var precision: DeadlinePrecision

    var body: some View {
        Picker("时间精度", selection: $precision) {
            Text("仅日期").tag(DeadlinePrecision.date)
            Text("日期与时间").tag(DeadlinePrecision.minute)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(height: 28)
        .accessibilityLabel("时间精度")
    }
}

private struct ModernDateSelectionRow: View {
    let label: String
    @Binding var selection: Date
    let showsTime: Bool
    @Binding var hasValue: Bool
    @State private var showsDatePicker = false
    @State private var showsTimePicker = false

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(ModernPalette.muted)
                .frame(width: 42, alignment: .leading)

            Button {
                showsDatePicker = true
            } label: {
                Text(selection.formatted(.dateTime.year().month(.wide).day()))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            }
            .buttonStyle(ModernDateFieldButtonStyle())
            .help("选择\(label)日期")
            .accessibilityLabel("\(label)日期")
            .accessibilityValue(selection.formatted(date: .complete, time: .omitted))
            .popover(isPresented: $showsDatePicker, arrowEdge: .trailing) {
                DatePicker(
                    "\(label)日期",
                    selection: activatingSelection,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                .padding(12)
                .frame(width: 280)
            }

            if showsTime {
                Button {
                    showsTimePicker = true
                } label: {
                    Text(selection.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)))
                        .monospacedDigit()
                        .frame(width: 58, alignment: .center)
                        .frame(minHeight: 30)
                }
                .buttonStyle(ModernDateFieldButtonStyle())
                .help("选择\(label)时间")
                .accessibilityLabel("\(label)时间")
                .accessibilityValue(selection.formatted(date: .omitted, time: .shortened))
                .popover(isPresented: $showsTimePicker, arrowEdge: .trailing) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(label)时间")
                            .font(.system(size: 12, weight: .semibold))
                        DatePicker(
                            "\(label)时间",
                            selection: activatingSelection,
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                    }
                    .padding(12)
                    .frame(width: 180)
                }
            }
        }
        .frame(minHeight: 30)
        .accessibilityElement(children: .contain)
    }

    private var activatingSelection: Binding<Date> {
        Binding(
            get: { selection },
            set: { value in
                selection = value
                hasValue = true
            }
        )
    }
}

private struct ModernDateFieldButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(ModernPalette.ink)
            .padding(.horizontal, 9)
            .background(
                ModernPalette.subtle.opacity(configuration.isPressed ? 0.72 : 1),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(ModernPalette.line.opacity(0.65), lineWidth: 0.75)
            }
    }
}

private struct ModernDateShortcutButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(ModernPalette.railInk)
            .frame(maxWidth: .infinity, minHeight: 28)
            .background(
                configuration.isPressed ? ModernPalette.blue.opacity(0.08) : .clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(ModernPalette.line.opacity(0.65), lineWidth: 0.75)
            }
    }
}

private extension TaskDeadlineShortcut {
    var title: String {
        switch self {
        case .today: "今天"
        case .tomorrow: "明天"
        case .thisWeekend: "本周末"
        }
    }
}


private struct ModernTaskTimeSection: View {
    @Environment(AppModel.self) private var model: AppModel
    let task: GTDTask

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("实际专注时间", systemImage: "hourglass")
                    .font(.system(size: 12))
                    .foregroundStyle(ModernPalette.muted)
                Spacer()
                ModernActualDurationText(task: task)
            }
            HStack(spacing: 8) {
                Text("开始计时")
                    .font(.system(size: 11.5))
                    .foregroundStyle(ModernPalette.muted)
                Spacer()
                HStack(spacing: 0) {
                    Button { model.startStopwatch(for: task) } label: {
                        Label("正计时", systemImage: "stopwatch")
                    }
                    .buttonStyle(ModernInspectorActionStyle(tint: ModernPalette.blue))
                    Divider().frame(height: 18)
                    Button { model.startPomodoro(for: task) } label: {
                        Label("番茄钟", systemImage: "timer")
                    }
                    .buttonStyle(ModernInspectorActionStyle(tint: ModernPalette.red))
                }
                .padding(2)
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(ModernPalette.line.opacity(0.55), lineWidth: 0.75)
                }
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ModernPalette.line.opacity(0.55))
                .frame(height: 0.5)
        }
    }
}

struct ModernActualDurationText: View {
    @Environment(AppModel.self) private var model: AppModel
    let task: GTDTask

    var body: some View {
        if model.activeTimer?.taskID == task.id {
            SwiftUI.TimelineView(.periodic(from: Date(), by: 1)) { context in
                durationText(at: context.date)
            }
        } else {
            durationText(at: .now)
        }
    }

    private func durationText(at date: Date) -> some View {
        let recorded = model.entries(for: task).reduce(0) { $0 + $1.duration }
        let running = model.activeTimer?.taskID == task.id
            ? model.timerElapsed(at: date)
            : 0

        return Text(modernFormatDuration(recorded + running))
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundStyle(ModernPalette.ink)
    }
}

struct ModernInspectorValue<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ModernPalette.muted)
                .frame(width: 18)
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(ModernPalette.muted)
            Spacer(minLength: 8)
            content()
                .font(.system(size: 12))
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ModernPalette.line.opacity(0.55))
                .frame(height: 0.5)
        }
    }
}

struct ModernInspectorActionStyle: ButtonStyle {
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .opacity(configuration.isPressed ? 0.65 : 1)
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.96 : 1))
    }
}

struct ModernTimelineCanvas: View {
    @Environment(AppModel.self) private var model: AppModel
    let tasks: [GTDTask]

    private var plannedTasks: [GTDTask] {
        tasks.filter { $0.plannedStart != nil && !$0.status.isFinished }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("时间线")
                            .font(.system(size: 20, weight: .semibold))
                        Text("计划时间与实际专注记录")
                            .font(.system(size: 11))
                            .foregroundStyle(ModernPalette.muted)
                    }
                    Spacer()
                    Button("今天") { }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }

                ModernTimeScale()
                    .padding(.leading, 140)

                if plannedTasks.isEmpty {
                    EmptyColumnHint(icon: "calendar.badge.clock", title: "还没有计划时间", message: "在任务详情中设置计划日期或时间")
                        .padding(.top, 90)
                } else {
                    ForEach(plannedTasks) { task in
                        ModernTimelineTaskRow(task: task)
                    }
                }
            }
            .padding(22)
        }
        .background(ModernPalette.canvas)
    }
}

struct ModernTimeScale: View {
    var body: some View {
        HStack(spacing: 0) {
            ForEach(["06:00", "09:00", "12:00", "15:00", "18:00", "21:00", "24:00"], id: \.self) { label in
                Text(label)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(ModernPalette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct ModernTimelineTaskRow: View {
    @Environment(AppModel.self) private var model: AppModel
    let task: GTDTask

    var body: some View {
        Button {
            model.selectTask(task.id)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(task.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ModernPalette.ink)
                        .lineLimit(1)
                    Text(task.plannedPrecision == .date
                         ? "仅日期"
                         : task.plannedStart?.formatted(date: .omitted, time: .shortened) ?? "")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(ModernPalette.muted)
                }
                .frame(width: 128, alignment: .trailing)

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(ModernPalette.line.opacity(0.55))
                            .frame(height: 1)
                        if task.plannedEnd == nil {
                            Capsule()
                                .fill(ModernPalette.blue.opacity(0.82))
                                .frame(width: 7, height: 22)
                                .offset(x: max(0, barOffset(in: proxy.size.width) - 3.5))
                        } else {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(ModernPalette.blue.opacity(0.72))
                                .frame(width: max(38, barWidth(in: proxy.size.width)), height: 22)
                                .offset(x: barOffset(in: proxy.size.width))
                        }
                    }
                }
                .frame(height: 30)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityLabel(task.title)
        .accessibilityValue(modernPlannedRangeText(task))
    }

    private func normalized(_ date: Date) -> CGFloat {
        let start = Calendar.current.startOfDay(for: date)
        let value = date.timeIntervalSince(start) / (24 * 60 * 60)
        return CGFloat(min(1, max(0, value)))
    }

    private func barOffset(in width: CGFloat) -> CGFloat {
        guard let start = task.plannedStart else { return 0 }
        return normalized(start) * width
    }

    private func barWidth(in width: CGFloat) -> CGFloat {
        guard let start = task.plannedStart, let end = task.plannedEnd else { return 48 }
        let duration = CGFloat(max(0.06, min(1, end.timeIntervalSince(start) / (24 * 60 * 60))))
        return duration * width
    }
}

struct ModernMiniTimeline: View {
    let task: GTDTask

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("时间线")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("今天")
                    .font(.system(size: 10))
                    .foregroundStyle(ModernPalette.muted)
            }
            HStack(spacing: 0) {
                ForEach(["00:00", "06:00", "12:00", "18:00", "24:00"], id: \.self) { label in
                    Text(label)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(ModernPalette.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(ModernPalette.line.opacity(0.55)).frame(height: 1)
                    if let start = task.plannedStart {
                        let dayStart = Calendar.current.startOfDay(for: start)
                        let offset = CGFloat(max(0, min(1, start.timeIntervalSince(dayStart) / 86_400))) * proxy.size.width
                        if let end = task.plannedEnd {
                            let width = CGFloat(max(0.08, min(1, end.timeIntervalSince(start) / 86_400))) * proxy.size.width
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(ModernPalette.blue.opacity(0.72))
                                .frame(width: max(28, width), height: 18)
                                .offset(x: offset)
                        } else {
                            Capsule()
                                .fill(ModernPalette.blue.opacity(0.82))
                                .frame(width: 7, height: 18)
                                .offset(x: max(0, offset - 3.5))
                        }
                    } else {
                        Text("未设置计划时间")
                            .font(.system(size: 10))
                            .foregroundStyle(ModernPalette.muted)
                    }
                }
            }
            .frame(height: 22)
        }
    }
}

struct ModernQuietButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(ModernPalette.muted)
            .frame(width: 30, height: 30)
            .background(configuration.isPressed ? ModernPalette.subtle : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.94 : 1))
    }
}

enum ModernPalette {
    // Semantic surfaces follow the same appearance as dynamic label colors.
    // Fixed pale backgrounds would become unreadable with white dark-mode text.
    static let canvas = Color(nsColor: NSColor.windowBackgroundColor)
    static let panel = Color(nsColor: NSColor.controlBackgroundColor)
    static let projectPanel = Color(nsColor: NSColor.windowBackgroundColor)
    static let rail = Color(nsColor: NSColor.underPageBackgroundColor)
    static let railInk = Color(nsColor: NSColor.secondaryLabelColor)
    static let sidebar = Color(nsColor: NSColor.windowBackgroundColor)
    static let subtle = Color(nsColor: NSColor.controlBackgroundColor)
    static let line = Color(nsColor: NSColor.separatorColor)
    static let ink = Color(nsColor: NSColor.labelColor)
    static let muted = Color(nsColor: NSColor.secondaryLabelColor)
    /// Role-based aliases share the app's blue interaction theme.
    /// System blue remains dynamic; do not rely on a fixed resolved hex value.
    static let accent = PlannerTheme.accent
    static let blue = accent
    static let completion = PlannerTheme.completion
    static let red = Color(nsColor: NSColor.systemRed)
    static let green = Color(nsColor: NSColor.systemGreen)
    static let selection = PlannerTheme.selection
    static let sidebarSelection = selection.opacity(0.09)
}

private func modernScheduleText(_ date: Date?) -> String {
    guard let date else { return "—" }
    let calendar = Calendar.current
    let time = date.formatted(date: .omitted, time: .shortened)
    if calendar.isDateInToday(date) { return "今天 " + time }
    if calendar.isDateInTomorrow(date) { return "明天 " + time }

    let startOfToday = calendar.startOfDay(for: .now)
    let dayOffset = calendar.dateComponents([.day], from: startOfToday, to: calendar.startOfDay(for: date)).day ?? 99
    if (0..<7).contains(dayOffset) {
        let weekday = calendar.component(.weekday, from: date)
        let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        return names[max(1, min(7, weekday)) - 1] + " " + time
    }
    return date.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
}

private func modernPlannedRangeText(_ task: GTDTask) -> String {
    guard let start = task.plannedStart else { return "—" }
    let calendar = Calendar.current
    guard task.plannedPrecision == .date else {
        let startText = modernScheduleText(start)
        guard let end = task.plannedEnd else { return startText }
        let endText = calendar.isDate(start, inSameDayAs: end)
            ? end.formatted(date: .omitted, time: .shortened)
            : end.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        return "\(startText) – \(endText)"
    }

    let startText = start.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits))
    guard let storedEnd = task.plannedEnd else { return startText }
    let displayEnd = storedEnd
    if calendar.isDate(start, inSameDayAs: displayEnd) { return startText }
    return "\(startText) – \(displayEnd.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits)))"
}

private func modernDeadlineText(_ task: GTDTask) -> String {
    guard let deadline = task.deadline else { return "—" }
    if task.deadlinePrecision == .minute { return modernScheduleText(deadline) }
    if Calendar.current.isDateInToday(deadline) { return "今天" }
    if Calendar.current.isDateInTomorrow(deadline) { return "明天" }
    return deadline.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits))
}

private func modernScheduleColor(_ date: Date?) -> Color {
    guard let date else { return ModernPalette.muted }
    let calendar = Calendar.current
    return calendar.isDateInToday(date) || calendar.isDateInTomorrow(date) ? ModernPalette.blue : ModernPalette.ink
}

private func modernTagColor(_ tag: String) -> Color {
    switch tag {
    case "健康", "运动": return Color(nsColor: NSColor.systemPurple)
    case "重要", "创作": return ModernPalette.green
    case "等待": return Color(nsColor: NSColor.systemOrange)
    case "家庭", "学习", "工作": return ModernPalette.blue
    default: return ModernPalette.blue
    }
}

func hexString(from color: Color) -> String {
    let nsColor = NSColor(color).usingColorSpace(.deviceRGB) ?? NSColor.systemBlue
    let red = Int((nsColor.redComponent * 255).rounded())
    let green = Int((nsColor.greenComponent * 255).rounded())
    let blue = Int((nsColor.blueComponent * 255).rounded())
    return String(format: "#%02X%02X%02X", red, green, blue)
}

private func modernFormatDuration(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds.rounded()))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secs = total % 60
    return String(format: "%02d:%02d:%02d", hours, minutes, secs)
}
