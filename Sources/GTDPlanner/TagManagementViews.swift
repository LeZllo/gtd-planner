import SwiftUI

// MARK: - UI-03 / C2

private enum TagSidebarGroupID: Hashable {
    case category(UUID)
    case uncategorized
}

private struct TagSidebarGroup: Identifiable {
    let id: TagSidebarGroupID
    let category: TagCategory?
    let title: String
    let color: Color
    let tags: [TaskTagDefinition]
}

struct ModernTagPane: View {
    @Environment(AppModel.self) private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""
    @State private var collapsedGroups: Set<TagSidebarGroupID> = []
    @State private var creationMode: CreationMode?
    @State private var creationDraft = ""
    @State private var showWorkspacePopover = false
    @FocusState private var creationFocused: Bool

    private enum CreationMode: Hashable {
        case category
        case tag

        var title: String {
            switch self {
            case .category: "新建标签分类"
            case .tag: "新建标签"
            }
        }

        var icon: String {
            switch self {
            case .category: "folder.badge.plus"
            case .tag: "tag.badge.plus"
            }
        }
    }

    private var groups: [TagSidebarGroup] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let allTags = model.currentTagDefinitions
        let categories = model.currentTagCategories
        var result: [TagSidebarGroup] = []

        for category in categories {
            let tags = allTags.filter { definition in
                guard definition.categoryID == category.id else { return false }
                return needle.isEmpty
                    || category.name.localizedCaseInsensitiveContains(needle)
                    || definition.name.localizedCaseInsensitiveContains(needle)
            }
            guard needle.isEmpty || !tags.isEmpty || category.name.localizedCaseInsensitiveContains(needle) else { continue }
            result.append(TagSidebarGroup(
                id: .category(category.id),
                category: category,
                title: category.name,
                color: Color(hex: category.colorHex),
                tags: tags
            ))
        }

        let uncategorized = allTags.filter { definition in
            guard definition.categoryID == nil else { return false }
            return needle.isEmpty || definition.name.localizedCaseInsensitiveContains(needle)
        }
        if !uncategorized.isEmpty {
            result.append(TagSidebarGroup(
                id: .uncategorized,
                category: nil,
                title: "未分类",
                color: ModernPalette.muted,
                tags: uncategorized
            ))
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            workspaceButton
            searchField

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if let creationMode {
                        creationRow(mode: creationMode)
                            .padding(.top, 2)
                    }

                    ForEach(groups) { group in
                        TagSidebarCategoryHeader(
                            group: group,
                            collapsed: collapsedGroups.contains(group.id),
                            onToggle: { toggle(group.id) },
                            onRename: { name in rename(group.category, to: name) },
                            onColorChange: { color in updateColor(group.category, to: color) },
                            onDelete: { delete(group.category) }
                        )

                        if !collapsedGroups.contains(group.id) {
                            ForEach(group.tags) { definition in
                                TagSidebarRow(
                                    definition: definition,
                                    count: model.taskCount(for: definition.id),
                                    selected: model.selection.selectedTag == .tag(definition.id),
                                    onSelect: { select(definition) },
                                    onDelete: { model.requestDeleteTag(definition) }
                                )
                            }
                        }
                    }

                    TagUntaggedSidebarRow(
                        count: model.tasks(for: .untagged).count,
                        selected: model.selection.selectedTag == .untagged,
                        onSelect: selectUntagged
                    )
                    .padding(.top, groups.isEmpty ? 4 : 8)

                    if groups.isEmpty, !query.isEmpty {
                        Text("没有匹配的标签")
                            .font(.system(size: 11.5))
                            .foregroundStyle(ModernPalette.muted)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 28)
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
                    Label("新建分类", systemImage: CreationMode.category.icon)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ModernProjectCreationButtonStyle())
                .help("新建标签分类")

                Button { beginCreation(.tag) } label: {
                    Label("新建标签", systemImage: CreationMode.tag.icon)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ModernProjectCreationButtonStyle())
                .help("新建标签")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(ModernPalette.projectPanel)
        .animation(
            reduceMotion ? .easeOut(duration: 0.10) : .snappy(duration: 0.20),
            value: creationMode
        )
    }

    private var workspaceButton: some View {
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
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(ModernPalette.muted)
            TextField("搜索标签", text: $query)
                .textFieldStyle(.plain)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(ModernPalette.muted)
                .accessibilityLabel("清空标签搜索")
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
    }

    private func creationRow(mode: CreationMode) -> some View {
        HStack(spacing: 9) {
            Image(systemName: mode.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(ModernPalette.blue)
                .frame(width: 18)
            TextField(mode.title, text: $creationDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($creationFocused)
                .onSubmit(commitCreation)
                .onExitCommand(perform: cancelCreation)
                .task {
                    await Task.yield()
                    creationFocused = true
                }
            Button(action: cancelCreation) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(ModernPalette.muted)
            .accessibilityLabel("取消")
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        .background(ModernPalette.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(ModernPalette.blue.opacity(0.22), lineWidth: 1)
        }
    }

    private func beginCreation(_ mode: CreationMode) {
        creationDraft = ""
        creationMode = mode
        creationFocused = true
    }

    private func commitCreation() {
        guard let creationMode else { return }
        let cleanName = creationDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        switch creationMode {
        case .category:
            model.addTagCategory(name: cleanName)
        case .tag:
            let selectedCategoryID = model.selectedTagDefinition?.categoryID
            model.addTag(name: cleanName, categoryID: selectedCategoryID)
        }
        cancelCreation()
    }

    private func cancelCreation() {
        creationFocused = false
        creationMode = nil
        creationDraft = ""
    }

    private func toggle(_ id: TagSidebarGroupID) {
        if collapsedGroups.contains(id) {
            collapsedGroups.remove(id)
        } else {
            collapsedGroups.insert(id)
        }
    }

    private func select(_ definition: TaskTagDefinition) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.18)) {
            model.selection.selectedTag = .tag(definition.id)
            model.clearSelectedTask()
        }
    }

    private func selectUntagged() {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.18)) {
            model.selection.selectedTag = .untagged
            model.clearSelectedTask()
        }
    }

    private func rename(_ category: TagCategory?, to name: String) {
        guard var category else { return }
        category.name = name
        model.updateTagCategory(category)
    }

    private func updateColor(_ category: TagCategory?, to color: Color) {
        guard var category else { return }
        category.colorHex = hexString(from: color)
        model.updateTagCategory(category)
    }

    private func delete(_ category: TagCategory?) {
        guard let category else { return }
        model.requestDeleteTagCategory(category)
    }
}

private struct TagSidebarCategoryHeader: View {
    let group: TagSidebarGroup
    let collapsed: Bool
    let onToggle: () -> Void
    let onRename: (String) -> Void
    let onColorChange: (Color) -> Void
    let onDelete: () -> Void
    @State private var renaming = false
    @State private var draftName = ""
    @FocusState private var renameFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onToggle) {
                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(ModernPalette.muted)
                    .frame(width: 16, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(collapsed ? "展开\(group.title)" : "折叠\(group.title)")

            Circle()
                .fill(group.color)
                .frame(width: 7, height: 7)

            if renaming, group.category != nil {
                TextField("分类名称", text: $draftName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5, weight: .semibold))
                    .focused($renameFocused)
                    .onSubmit(commitRename)
                    .onExitCommand(perform: cancelRename)
            } else {
                Text(group.title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(ModernPalette.ink)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)
            Text("\(group.tags.count)")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(ModernPalette.muted)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
        .contentShape(Rectangle())
        .contextMenu {
            if group.category != nil {
                Button("重命名分类", systemImage: "pencil", action: beginRename)
                Menu("分类颜色", systemImage: "paintpalette") {
                    ForEach(["#64748B", "#2F6FD0", "#0AA58F", "#C47A16", "#8256D0", "#C65374"], id: \.self) { hex in
                        Button {
                            onColorChange(Color(hex: hex))
                        } label: {
                            Label(hex, systemImage: "circle.fill")
                        }
                    }
                }
                Divider()
                Button("删除分类", role: .destructive, action: onDelete)
            }
        }
        .onChange(of: renaming) { _, value in
            guard value else { return }
            Task { @MainActor in
                await Task.yield()
                renameFocused = true
            }
        }
    }

    private func beginRename() {
        draftName = group.title
        renaming = true
    }

    private func commitRename() {
        let cleanName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanName.isEmpty { onRename(cleanName) }
        renaming = false
        renameFocused = false
    }

    private func cancelRename() {
        renaming = false
        renameFocused = false
        draftName = group.title
    }
}

private struct TagSidebarRow: View {
    let definition: TaskTagDefinition
    let count: Int
    let selected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 9) {
                Image(systemName: "tag.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(hex: definition.colorHex))
                    .frame(width: 18)
                Text(definition.name)
                    .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? ModernPalette.blue : ModernPalette.ink)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(ModernPalette.muted)
                }
            }
            .padding(.horizontal, 10)
            .padding(.leading, 16)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .background(
                selected ? ModernPalette.sidebarSelection : .clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("删除标签", role: .destructive, action: onDelete)
        }
        .accessibilityLabel(definition.name)
        .accessibilityValue("\(count) 个任务")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct TagUntaggedSidebarRow: View {
    let count: Int
    let selected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 9) {
                Image(systemName: "tag.slash")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ModernPalette.muted)
                    .frame(width: 18)
                Text("未标记")
                    .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? ModernPalette.blue : ModernPalette.ink)
                Spacer(minLength: 4)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(ModernPalette.muted)
                }
            }
            .padding(.horizontal, 10)
            .padding(.leading, 16)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .background(
                selected ? ModernPalette.sidebarSelection : .clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - UI-03 / C3

private enum TagTaskProjectGroupID: Hashable {
    case project(UUID)
    case unassigned
}

private struct TagTaskProjectGroup: Identifiable {
    let id: TagTaskProjectGroupID
    let title: String
    let color: Color
    let tasks: [GTDTask]
}

struct ModernTagTaskPane: View {
    @Environment(AppModel.self) private var model: AppModel
    @Binding var taskSearchExpanded: Bool
    @Binding var taskSearchQuery: String
    @Binding var quickTaskDraft: ModernQuickTaskDraft
    @FocusState.Binding var quickTaskFocused: Bool
    @Binding var editingTaskTitleID: UUID?
    @FocusState.Binding var taskTitleFocusedID: UUID?

    private var selectedTasks: [GTDTask] {
        guard let selection = model.selection.selectedTag else { return [] }
        return model.tasks(for: selection)
    }

    private var visibleTasks: [GTDTask] {
        ProjectTaskSearch.filter(selectedTasks, query: taskSearchQuery)
    }

    private var title: String {
        switch model.selection.selectedTag {
        case .tag:
            return model.selectedTagDefinition.map { "#\($0.name)" } ?? "标签"
        case .untagged:
            return "未标记"
        case nil:
            return "标签任务"
        }
    }

    private var titleColor: Color {
        model.selectedTagDefinition.map { Color(hex: $0.colorHex) } ?? ModernPalette.muted
    }

    var body: some View {
        VStack(spacing: 0) {
            ModernTagTaskHeader(
                title: title,
                titleColor: titleColor,
                taskCount: selectedTasks.count,
                taskSearchExpanded: $taskSearchExpanded,
                taskSearchQuery: $taskSearchQuery,
                enabled: model.selection.selectedTag != nil
            )

            if let selection = model.selection.selectedTag {
                ModernTagTaskList(
                    visibleTasks: visibleTasks,
                    projects: model.currentProjects,
                    editingTaskTitleID: $editingTaskTitleID,
                    taskTitleFocusedID: $taskTitleFocusedID
                )
                .id(TagTaskListIdentity(workspaceID: model.selection.selectedWorkspaceID, selection: selection))

                ModernQuickTaskComposer(
                    draft: $quickTaskDraft,
                    isFocused: $quickTaskFocused,
                    onSubmit: createQuickTask
                )
            } else {
                EmptyColumnHint(
                    icon: "tag",
                    title: "选择一个标签",
                    message: "从左侧标签列表中选择一项后，这里会按项目显示对应任务"
                )
            }
        }
        .background(ModernPalette.canvas)
    }

    private func createQuickTask() {
        let title = quickTaskDraft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let selection = model.selection.selectedTag else { return }

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
        var tags = quickTaskDraft.tags
        if case .tag = selection, let definition = model.selectedTagDefinition,
           !tags.contains(where: { $0.localizedCaseInsensitiveCompare(definition.name) == .orderedSame }) {
            tags.append(definition.name)
        }

        model.addTask(
            title: title,
            projectID: nil,
            status: .open,
            priority: quickTaskDraft.priority,
            actionList: quickTaskDraft.actionList,
            plannedStart: normalizedPlan?.start,
            plannedEnd: normalizedPlan?.end,
            plannedPrecision: quickTaskDraft.hasPlan ? quickTaskDraft.plannedPrecision : .none,
            deadline: normalizedDeadline,
            deadlinePrecision: quickTaskDraft.hasDeadline ? quickTaskDraft.deadlinePrecision : .none,
            tags: tags
        )
        quickTaskDraft.reset()
    }
}

private struct TagTaskListIdentity: Hashable {
    let workspaceID: UUID
    let selection: TagSelection
}

private struct ModernTagTaskHeader: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    let titleColor: Color
    let taskCount: Int
    @Binding var taskSearchExpanded: Bool
    @Binding var taskSearchQuery: String
    let enabled: Bool
    @FocusState private var searchFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: title == "未标记" ? "tag.slash" : "tag.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(titleColor)
            Text(title)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(ModernPalette.ink)
                .lineLimit(1)
            Text("\(taskCount)")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(ModernPalette.muted)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(ModernPalette.subtle, in: Capsule())
            Spacer()
            searchControl
        }
        .padding(.horizontal, 24)
        .frame(height: 50)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var searchControl: some View {
        HStack(spacing: taskSearchExpanded ? 6 : 0) {
            Button(action: toggleSearch) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(taskSearchExpanded ? ModernPalette.blue : ModernPalette.ink)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(taskSearchExpanded ? "关闭标签任务搜索" : "搜索标签任务")

            if taskSearchExpanded {
                TextField("搜索任务", text: $taskSearchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($searchFocused)
                    .onExitCommand(perform: handleExit)

                if !taskSearchQuery.isEmpty {
                    Button {
                        taskSearchQuery = ""
                        searchFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11.5))
                            .foregroundStyle(ModernPalette.muted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清空标签任务搜索")
                }
            }
        }
        .padding(.horizontal, taskSearchExpanded ? 6 : 3)
        .frame(width: taskSearchExpanded ? 188 : 30, height: 30, alignment: .leading)
        .background(taskSearchExpanded ? ModernPalette.panel : .clear, in: Capsule())
        .overlay {
            if taskSearchExpanded {
                Capsule()
                    .stroke(
                        searchFocused ? ModernPalette.blue.opacity(0.38) : ModernPalette.line.opacity(0.64),
                        lineWidth: 0.75
                    )
            }
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.38)
        .animation(
            reduceMotion ? .easeOut(duration: 0.10) : .snappy(duration: 0.20),
            value: taskSearchExpanded
        )
        .task(id: taskSearchExpanded) {
            guard taskSearchExpanded else {
                searchFocused = false
                return
            }
            await Task.yield()
            searchFocused = true
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

    private func toggleSearch() {
        guard enabled else { return }
        taskSearchExpanded.toggle()
        if !taskSearchExpanded {
            taskSearchQuery = ""
            searchFocused = false
        }
    }

    private func handleExit() {
        if taskSearchQuery.isEmpty {
            toggleSearch()
        } else {
            taskSearchQuery = ""
        }
    }
}

private struct ModernTagTaskList: View {
    @Environment(AppModel.self) private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let visibleTasks: [GTDTask]
    let projects: [Project]
    @Binding var editingTaskTitleID: UUID?
    @FocusState.Binding var taskTitleFocusedID: UUID?
    @State private var expandedTaskIDs: Set<UUID> = []
    @State private var collapsedGroups: Set<TagTaskProjectGroupID> = []
    @State private var addingChildToTaskID: UUID?
    @State private var childDraft = ""
    @State private var taskFrames: [UUID: CGRect] = [:]
    @State private var childFrame = CGRect.zero
    @FocusState private var childFocused: Bool

    private var groups: [TagTaskProjectGroup] {
        let projectByID = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
        let grouped = Dictionary(grouping: visibleTasks, by: \.projectID)
        var result = projects.compactMap { project -> TagTaskProjectGroup? in
            guard let tasks = grouped[project.id], !tasks.isEmpty else { return nil }
            return TagTaskProjectGroup(
                id: .project(project.id),
                title: project.name,
                color: Color(hex: project.colorHex),
                tasks: tasks
            )
        }
        let unassignedTasks = visibleTasks.filter { task in
            guard let projectID = task.projectID else { return true }
            return projectByID[projectID] == nil
        }
        if !unassignedTasks.isEmpty {
            result.append(TagTaskProjectGroup(
                id: .unassigned,
                title: "无项目",
                color: ModernPalette.muted,
                tasks: unassignedTasks
            ))
        }
        return result
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 5)

                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 0) {
                            TagTaskProjectHeader(
                                title: group.title,
                                color: group.color,
                                count: group.tasks.count,
                                collapsed: collapsedGroups.contains(group.id),
                                onToggle: { toggleGroup(group.id) }
                            )

                            if !collapsedGroups.contains(group.id) {
                                ForEach(TaskOutlineBuilder.rows(
                                    for: group.tasks,
                                    expandedTaskIDs: expandedTaskIDs
                                )) { outlineRow in
                                    let task = model.task(withID: outlineRow.task.id) ?? outlineRow.task
                                    VStack(alignment: .leading, spacing: 0) {
                                        ModernTaskRow(
                                            task: task,
                                            depth: outlineRow.depth,
                                            hasChildren: outlineRow.hasChildren,
                                            isExpanded: expandedTaskIDs.contains(task.id),
                                            selected: model.isTaskSelected(task.id),
                                            isBeingDragged: false,
                                            isDropTargeted: false,
                                            isParentDropTargeted: false,
                                            reportsFrame: true,
                                            editingTaskTitleID: $editingTaskTitleID,
                                            taskTitleFocusedID: $taskTitleFocusedID,
                                            onToggleExpanded: { toggleExpanded(task.id) },
                                            onAddChild: { beginAddingChild(to: task.id) },
                                            onSelect: {
                                                cancelAddingChild()
                                                model.selectTask(task.id)
                                            },
                                            onToggle: {
                                                withAnimation(reduceMotion ? nil : .snappy(duration: 0.18)) {
                                                    model.toggleTask(task.id)
                                                }
                                            },
                                            onDelete: { model.requestDeleteTask(task) },
                                            onRename: model.updateTask,
                                            onDragChanged: nil,
                                            onDragEnded: nil
                                        )

                                        if addingChildToTaskID == task.id {
                                            TagInlineChildEditor(
                                                depth: outlineRow.depth + 1,
                                                draft: $childDraft,
                                                focused: $childFocused,
                                                onCommit: commitAddingChild,
                                                onCancel: cancelAddingChild
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if visibleTasks.isEmpty {
                        EmptyColumnHint(
                            icon: "tag",
                            title: "这里还没有任务",
                            message: "可在下方快速创建，任务会自动附加当前标签"
                        )
                        .padding(.top, 110)
                    }
                }
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .top)
                .contentShape(Rectangle())
                .coordinateSpace(.named("task-list-content"))
                .simultaneousGesture(
                    SpatialTapGesture(coordinateSpace: .named("task-list-content"))
                        .onEnded(handleCanvasTap),
                    including: .gesture
                )
            }
        }
        .background(ModernPalette.subtle.opacity(0.18))
        .onPreferenceChange(TaskRowFramesPreferenceKey.self) { frames in
            if frames != taskFrames { taskFrames = frames }
        }
        .onPreferenceChange(InlineChildTaskFramePreferenceKey.self) { frame in
            if frame != childFrame { childFrame = frame }
        }
        .onChange(of: childFocused) { wasFocused, isFocused in
            guard wasFocused, !isFocused, addingChildToTaskID != nil else { return }
            cancelAddingChild()
        }
        .onAppear(perform: resetExpansion)
        .onChange(of: visibleTasks.map(\.id)) { _, _ in resetExpansion() }
    }

    private func handleCanvasTap(_ value: SpatialTapGesture.Value) {
        guard !taskFrames.values.contains(where: { $0.contains(value.location) }),
              (childFrame.isEmpty || !childFrame.contains(value.location)) else { return }
        cancelAddingChild()
        taskTitleFocusedID = nil
        editingTaskTitleID = nil
        model.clearSelectedTask()
    }

    private func resetExpansion() {
        let visibleIDs = Set(visibleTasks.map(\.id))
        expandedTaskIDs = Set(visibleTasks.compactMap { task in
            guard let parentID = task.parentID, visibleIDs.contains(parentID) else { return nil }
            return parentID
        })
    }

    private func toggleGroup(_ id: TagTaskProjectGroupID) {
        model.clearSelectedTask()
        if collapsedGroups.contains(id) {
            collapsedGroups.remove(id)
        } else {
            collapsedGroups.insert(id)
        }
    }

    private func toggleExpanded(_ taskID: UUID) {
        if expandedTaskIDs.contains(taskID) {
            expandedTaskIDs.remove(taskID)
        } else {
            expandedTaskIDs.insert(taskID)
        }
    }

    private func beginAddingChild(to taskID: UUID) {
        addingChildToTaskID = taskID
        expandedTaskIDs.insert(taskID)
        childDraft = ""
        Task { @MainActor in
            await Task.yield()
            childFocused = true
        }
    }

    private func commitAddingChild() {
        guard let parentID = addingChildToTaskID else { return }
        let title = childDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            cancelAddingChild()
            return
        }
        model.addSubtask(title: title, to: parentID)
        cancelAddingChild()
    }

    private func cancelAddingChild() {
        childFocused = false
        addingChildToTaskID = nil
        childDraft = ""
    }
}

private struct TagTaskProjectHeader: View {
    let title: String
    let color: Color
    let count: Int
    let collapsed: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 7) {
                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(ModernPalette.muted)
                    .frame(width: 16)
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(ModernPalette.ink)
                Text("\(count)")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(ModernPalette.muted)
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)，\(count) 个任务")
    }
}

private struct TagInlineChildEditor: View {
    let depth: Int
    @Binding var draft: String
    @FocusState.Binding var focused: Bool
    let onCommit: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: CGFloat(min(depth, 6)) * 18)
            Image(systemName: "arrow.turn.down.right")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(ModernPalette.muted)
                .frame(width: 18)
            Image(systemName: "circle")
                .font(.system(size: 14))
                .foregroundStyle(ModernPalette.muted)
                .frame(width: 28)
            TextField("添加下级任务…", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .focused($focused)
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
                    value: proxy.frame(in: .named("task-list-content"))
                )
            }
        }
    }
}

// MARK: - UI-03 / C4

struct ModernTagInspectorPane: View {
    @Environment(AppModel.self) private var model: AppModel
    @FocusState.Binding var inspectorNoteFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: model.selectedTask == nil ? "tag" : "exclamationmark.circle")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(ModernPalette.ink)
                Text(model.selectedTask == nil ? "标签详情" : "任务详情")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(ModernPalette.muted)
                Spacer()
                if model.selectedTask != nil {
                    Button(action: model.clearSelectedTask) {
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
            } else if let definition = model.selectedTagDefinition {
                ModernTagInspector(definition: definition)
                    .id(definition.id)
            } else if model.selection.selectedTag == .untagged {
                ModernUntaggedInspector()
            } else {
                EmptyColumnHint(
                    icon: "tag",
                    title: "选择一个标签",
                    message: "标签的分类、颜色、说明和使用情况会显示在这里"
                )
                .padding(.horizontal, 22)
            }
            Spacer(minLength: 0)
        }
        .background(ModernPalette.panel)
    }
}

private struct ModernTagInspector: View {
    @Environment(AppModel.self) private var model: AppModel
    let definition: TaskTagDefinition
    @State private var name: String
    @State private var categoryID: UUID?
    @State private var color: Color
    @State private var note: String
    @State private var mergeTargetID: UUID?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name
        case note
    }

    init(definition: TaskTagDefinition) {
        self.definition = definition
        _name = State(initialValue: definition.name)
        _categoryID = State(initialValue: definition.categoryID)
        _color = State(initialValue: Color(hex: definition.colorHex))
        _note = State(initialValue: definition.note)
    }

    private var mergeTarget: TaskTagDefinition? {
        guard let mergeTargetID else { return nil }
        return model.tagDefinition(withID: mergeTargetID)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "tag.fill")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(color)
                        .frame(width: 24, height: 30)
                    TextField("标签名称", text: $name)
                        .textFieldStyle(.plain)
                        .font(.system(size: 19, weight: .semibold))
                        .focused($focusedField, equals: .name)
                        .onSubmit(save)
                        .padding(.vertical, 3)
                        .background(
                            focusedField == .name ? ModernPalette.subtle.opacity(0.85) : .clear,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                }
                .padding(.bottom, 18)

                ModernInspectorValue(title: "工作区", icon: "square.grid.2x2") {
                    Text(model.currentWorkspace.name)
                        .foregroundStyle(ModernPalette.ink)
                }

                ModernInspectorPickerRow(
                    icon: "folder.badge.gearshape",
                    title: "标签分类",
                    value: model.currentTagCategories.first(where: { $0.id == categoryID })?.name ?? "未分类"
                ) {
                    Button("未分类") {
                        categoryID = nil
                        save()
                    }
                    ForEach(model.currentTagCategories) { category in
                        Button(category.name) {
                            categoryID = category.id
                            save()
                        }
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: "paintpalette")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ModernPalette.muted)
                        .frame(width: 18)
                    Text("标签颜色")
                        .font(.system(size: 11.5))
                        .foregroundStyle(ModernPalette.muted)
                    Spacer()
                    Circle()
                        .fill(color)
                        .frame(width: 10, height: 10)
                    ColorPicker("标签颜色", selection: $color, supportsOpacity: false)
                        .labelsHidden()
                }
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(ModernPalette.line.opacity(0.55)).frame(height: 0.5)
                }

                ModernInspectorValue(title: "任务使用", icon: "checklist") {
                    Text("\(model.taskCount(for: definition.id)) 个任务")
                        .foregroundStyle(ModernPalette.ink)
                }
                ModernInspectorValue(title: "涉及项目", icon: "folder") {
                    Text("\(model.projectUsageCount(for: definition.id)) 个项目")
                        .foregroundStyle(ModernPalette.ink)
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text("标签说明")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ModernPalette.ink)
                    TextEditor(text: $note)
                        .font(.system(size: 12))
                        .scrollContentBackground(.hidden)
                        .padding(9)
                        .frame(minHeight: 110)
                        .background(ModernPalette.subtle, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .focused($focusedField, equals: .note)
                }
                .padding(.vertical, 14)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(ModernPalette.line.opacity(0.55)).frame(height: 0.5)
                }

                ModernInspectorValue(title: "创建时间", icon: "clock") {
                    Text(definition.createdAt.formatted(date: .numeric, time: .shortened))
                        .foregroundStyle(ModernPalette.muted)
                }
                ModernInspectorValue(title: "更新时间", icon: "arrow.clockwise") {
                    Text(definition.updatedAt.formatted(date: .numeric, time: .shortened))
                        .foregroundStyle(ModernPalette.muted)
                }

                VStack(spacing: 8) {
                    Menu {
                        ForEach(model.currentTagDefinitions.filter { $0.id != definition.id }) { target in
                            Button(target.name) { mergeTargetID = target.id }
                        }
                    } label: {
                        Label("合并到其他标签", systemImage: "arrow.triangle.merge")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ModernInspectorActionStyle(tint: ModernPalette.blue))
                    .disabled(model.currentTagDefinitions.count < 2)

                    Button {
                        model.requestDeleteTag(definition)
                    } label: {
                        Label("删除标签", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ModernInspectorActionStyle(tint: ModernPalette.red))
                }
                .padding(.top, 16)
            }
            .padding(20)
        }
        .onChange(of: name) { _, _ in saveIfValid() }
        .onChange(of: color) { _, _ in saveIfValid() }
        .onChange(of: note) { _, _ in saveIfValid() }
        .confirmationDialog(
            "合并标签？",
            isPresented: Binding(
                get: { mergeTargetID != nil },
                set: { if !$0 { mergeTargetID = nil } }
            )
        ) {
            if let target = mergeTarget {
                Button("合并到“\(target.name)”", role: .destructive) {
                    model.mergeTag(definition.id, into: target.id)
                    mergeTargetID = nil
                }
            }
            Button("取消", role: .cancel) { mergeTargetID = nil }
        } message: {
            Text("任务会改用目标标签，当前标签随后被删除。")
        }
    }

    private func saveIfValid() {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        save()
    }

    private func save() {
        guard var updated = model.tagDefinition(withID: definition.id) else { return }
        updated.name = name
        updated.categoryID = categoryID
        updated.colorHex = hexString(from: color)
        updated.note = note
        model.updateTagDefinition(updated)
    }
}

private struct ModernUntaggedInspector: View {
    @Environment(AppModel.self) private var model: AppModel

    private var tasks: [GTDTask] { model.tasks(for: .untagged) }
    private var projectCount: Int { Set(tasks.compactMap(\.projectID)).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "tag.slash")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(ModernPalette.muted)
                    .frame(width: 24)
                Text("未标记")
                    .font(.system(size: 19, weight: .semibold))
            }
            .padding(.bottom, 18)

            ModernInspectorValue(title: "工作区", icon: "square.grid.2x2") {
                Text(model.currentWorkspace.name)
                    .foregroundStyle(ModernPalette.ink)
            }
            ModernInspectorValue(title: "任务", icon: "checklist") {
                Text("\(tasks.count) 个任务")
                    .foregroundStyle(ModernPalette.ink)
            }
            ModernInspectorValue(title: "涉及项目", icon: "folder") {
                Text("\(projectCount) 个项目")
                    .foregroundStyle(ModernPalette.ink)
            }

            Text("“未标记”是动态集合，不是可编辑标签。给任务添加任意标签后，它会自动移出这里。")
                .font(.system(size: 11.5))
                .foregroundStyle(ModernPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
