import Foundation

extension AppModel {
    func deleteTask(_ task: GTDTask) {
        requestDeleteTask(task)
    }

    func requestDeleteWorkspace(_ workspace: Workspace) {
        pendingDeletion = DeletionRequest(
            target: .workspace(workspace.id),
            title: "删除工作区？",
            message: "“\(workspace.name)”内的所有项目和任务会移入垃圾箱，之后仍可恢复。",
            confirmTitle: "移入垃圾箱"
        )
    }

    func requestDeleteProject(_ project: Project) {
        pendingDeletion = DeletionRequest(
            target: .project(project.id),
            title: "删除项目？",
            message: "“\(project.name)”内的所有任务会移入垃圾箱，之后仍可恢复。",
            confirmTitle: "移入垃圾箱"
        )
    }

    func requestDeleteProjectSection(_ section: ProjectSection) {
        let taskCount = database.tasks.filter { $0.sectionID == section.id }.count
        pendingDeletion = DeletionRequest(
            target: .projectSection(section.id),
            title: "删除分区？",
            message: "“\(section.name)”中的 \(taskCount) 个任务会移到未分区，任务本身不会被删除。",
            confirmTitle: "删除分区"
        )
    }

    func requestDeleteTask(_ task: GTDTask) {
        pendingDeletion = DeletionRequest(
            target: .task(task.id),
            title: "删除任务？",
            message: "“\(task.title)”及其子任务会移入垃圾箱，之后仍可恢复。",
            confirmTitle: "移入垃圾箱"
        )
    }

    func requestEmptyTrash() {
        pendingDeletion = DeletionRequest(
            target: .emptyTrash,
            title: "倾倒垃圾箱？",
            message: "垃圾箱中的工作区、项目和任务将被永久删除，无法恢复。",
            confirmTitle: "倾倒垃圾箱"
        )
    }

    func performDeletion(_ request: DeletionRequest) {
        pendingDeletion = nil
        switch request.target {
        case .workspace(let id): moveWorkspaceToTrash(id)
        case .project(let id): moveProjectToTrash(id)
        case .projectSection(let id): deleteProjectSection(id)
        case .task(let id): moveTaskToTrash(id)
        case .tagCategory(let id): deleteTagCategory(id)
        case .tag(let id): deleteTagDefinition(id)
        case .emptyTrash: emptyTrash()
        }
    }

    func restoreTrashItem(_ trashID: UUID) {
        guard let index = database.trashItems.firstIndex(where: { $0.id == trashID }) else { return }
        let item = database.trashItems[index]

        switch item.kind {
        case .workspace:
            guard let workspace = item.workspace else { return }
            guard !database.workspaces.contains(where: { $0.id == workspace.id }) else {
                notice = "该工作区已经存在，无法重复恢复"
                return
            }
            database.workspaces.append(workspace)
            database.workspaceOrder.append(workspace.id)
            database.workspaceLastOpenedAt[workspace.id.uuidString] = .now
            database.projectCategories.append(contentsOf: item.projectCategories.filter { category in
                !database.projectCategories.contains(where: { $0.id == category.id })
            })
            database.projectSections.append(contentsOf: (item.projectSections ?? []).filter { section in
                !database.projectSections.contains(where: { $0.id == section.id })
            })
            database.tagCategories.append(contentsOf: (item.tagCategories ?? []).filter { category in
                !database.tagCategories.contains(where: { $0.id == category.id })
            })
            database.tagDefinitions.append(contentsOf: (item.tagDefinitions ?? []).filter { definition in
                !database.tagDefinitions.contains(where: { $0.id == definition.id })
            })
            database.projects.append(contentsOf: item.projects.filter { project in
                !database.projects.contains(where: { $0.id == project.id })
            })
            database.tasks.append(contentsOf: item.tasks.filter { task in
                !database.tasks.contains(where: { $0.id == task.id })
            })
            database.timeEntries.append(contentsOf: item.timeEntries.filter { entry in
                !database.timeEntries.contains(where: { $0.id == entry.id })
            })
            appendLog(action: "恢复工作区", target: workspace.name, detail: item.summary)

        case .project:
            guard let project = item.project else { return }
            guard database.workspaces.contains(where: { $0.id == project.workspaceID }) else {
                notice = "所属工作区已不存在，无法恢复项目"
                return
            }
            guard !database.projects.contains(where: { $0.id == project.id }) else {
                notice = "该项目已经存在，无法重复恢复"
                return
            }
            ensureProjectCategory(named: project.category, workspaceID: project.workspaceID)
            database.projectSections.append(contentsOf: (item.projectSections ?? []).filter { section in
                !database.projectSections.contains(where: { $0.id == section.id })
            })
            database.projects.append(project)
            database.tasks.append(contentsOf: item.tasks.filter { task in
                !database.tasks.contains(where: { $0.id == task.id })
            })
            database.timeEntries.append(contentsOf: item.timeEntries.filter { entry in
                !database.timeEntries.contains(where: { $0.id == entry.id })
            })
            appendLog(action: "恢复项目", target: project.name, detail: item.summary)

        case .task:
            guard database.workspaces.contains(where: { $0.id == item.workspaceID }) else {
                notice = "所属工作区已不存在，无法恢复任务"
                return
            }
            database.tasks.append(contentsOf: item.tasks.filter { task in
                !database.tasks.contains(where: { $0.id == task.id })
            })
            database.timeEntries.append(contentsOf: item.timeEntries.filter { entry in
                !database.timeEntries.contains(where: { $0.id == entry.id })
            })
            appendLog(action: "恢复任务", target: item.name, detail: item.summary)
        }

        database.trashItems.remove(at: index)
        database.ensureTagDefinitions()
        selection.selectedArchive = .trash
        scheduleSave()
    }

    private func deleteProjectSection(_ sectionID: UUID) {
        guard let sectionIndex = database.projectSections.firstIndex(where: { $0.id == sectionID }) else { return }
        let section = database.projectSections[sectionIndex]
        let taskCount = database.tasks.filter { $0.sectionID == sectionID }.count
        for index in database.tasks.indices where database.tasks[index].sectionID == sectionID {
            database.tasks[index].sectionID = nil
        }
        database.projectSections.remove(at: sectionIndex)
        appendLog(action: "删除分区", target: section.name, detail: "已将 \(taskCount) 个任务移到未分区")
        scheduleSave()
    }

    private func moveWorkspaceToTrash(_ workspaceID: UUID) {
        guard database.workspaces.count > 1 else {
            notice = "至少需要保留一个工作区"
            return
        }
        guard let workspace = database.workspaces.first(where: { $0.id == workspaceID }) else { return }
        let wasSelected = selection.selectedWorkspaceID == workspaceID
        let wasDefault = defaultWorkspaceID == workspaceID
        let remainingManualOrder = database.workspaceOrder.filter { $0 != workspaceID }
        let projects = database.projects.filter { $0.workspaceID == workspaceID }
        let categories = database.projectCategories.filter { $0.workspaceID == workspaceID }
        let tagCategories = database.tagCategories.filter { $0.workspaceID == workspaceID }
        let tagDefinitions = database.tagDefinitions.filter { $0.workspaceID == workspaceID }
        let sections = database.projectSections.filter { section in
            projects.contains(where: { $0.id == section.projectID })
        }
        let tasks = database.tasks.filter { $0.workspaceID == workspaceID }
        let entries = database.timeEntries.filter { $0.workspaceID == workspaceID }

        database.trashItems.append(TrashItem(
            kind: .workspace,
            objectID: workspace.id,
            workspaceID: workspace.id,
            name: workspace.name,
            workspace: workspace,
            projectCategories: categories,
            projectSections: sections,
            tagCategories: tagCategories,
            tagDefinitions: tagDefinitions,
            projects: projects,
            tasks: tasks,
            timeEntries: entries
        ))
        database.workspaces.removeAll { $0.id == workspaceID }
        database.workspaceOrder.removeAll { $0 == workspaceID }
        if wasDefault, let promotedID = remainingManualOrder.first {
            database.pinnedWorkspaceIDs = [promotedID]
        }
        database.workspaceLastOpenedAt.removeValue(forKey: workspaceID.uuidString)
        database.projectCategories.removeAll { $0.workspaceID == workspaceID }
        database.tagCategories.removeAll { $0.workspaceID == workspaceID }
        database.tagDefinitions.removeAll { $0.workspaceID == workspaceID }
        database.projectSections.removeAll { section in projects.contains(where: { $0.id == section.projectID }) }
        database.projects.removeAll { $0.workspaceID == workspaceID }
        database.tasks.removeAll { $0.workspaceID == workspaceID }
        database.timeEntries.removeAll { $0.workspaceID == workspaceID }
        if let activeTaskID = database.activeTimer?.taskID,
           tasks.contains(where: { $0.id == activeTaskID }) {
            database.activeTimer = nil
        }
        if wasSelected {
            selection.selectedWorkspaceID = defaultWorkspaceID
            selection.selectedProjectID = nil
            selection.selectedTag = selection.selectedOrganization == .tags
                ? (currentTagDefinitions.first.map { .tag($0.id) } ?? .untagged)
                : nil
            clearSelectedTask()
        }
        appendLog(action: "删除工作区", target: workspace.name, detail: "已移入垃圾箱 · \(projects.count) 个项目 · \(tasks.count) 个任务")
        scheduleSave()
    }

    private func moveProjectToTrash(_ projectID: UUID) {
        guard let project = database.projects.first(where: { $0.id == projectID }) else { return }
        let sections = database.projectSections.filter { $0.projectID == projectID }
        let tasks = database.tasks.filter { $0.projectID == projectID }
        let taskIDs = Set(tasks.map(\.id))
        let entries = database.timeEntries.filter { entry in
            guard let taskID = entry.taskID else { return false }
            return taskIDs.contains(taskID)
        }
        database.trashItems.append(TrashItem(
            kind: .project,
            objectID: project.id,
            workspaceID: project.workspaceID,
            name: project.name,
            project: project,
            projectSections: sections,
            tasks: tasks,
            timeEntries: entries
        ))
        database.projects.removeAll { $0.id == projectID }
        database.projectSections.removeAll { $0.projectID == projectID }
        database.tasks.removeAll { taskIDs.contains($0.id) }
        database.timeEntries.removeAll { entry in
            guard let taskID = entry.taskID else { return false }
            return taskIDs.contains(taskID)
        }
        stopTimerIfNeeded(for: taskIDs)
        if selection.selectedProjectID == projectID { selection.selectedProjectID = nil }
        clearSelectedTask()
        appendLog(action: "删除项目", target: project.name, detail: "已移入垃圾箱 · \(tasks.count) 个任务")
        scheduleSave()
    }

    private func moveTaskToTrash(_ taskID: UUID) {
        guard let task = database.tasks.first(where: { $0.id == taskID }) else { return }
        let descendants = Set(database.tasks.filter { isDescendant($0, of: task.id) }.map(\.id))
        let taskIDs = descendants.union([task.id])
        let tasks = database.tasks.filter { taskIDs.contains($0.id) }
        let entries = database.timeEntries.filter { entry in
            guard let entryTaskID = entry.taskID else { return false }
            return taskIDs.contains(entryTaskID)
        }
        database.trashItems.append(TrashItem(
            kind: .task,
            objectID: task.id,
            workspaceID: task.workspaceID,
            name: task.title,
            tasks: tasks,
            timeEntries: entries
        ))
        database.tasks.removeAll { taskIDs.contains($0.id) }
        database.timeEntries.removeAll { entry in
            guard let entryTaskID = entry.taskID else { return false }
            return taskIDs.contains(entryTaskID)
        }
        stopTimerIfNeeded(for: taskIDs)
        if taskIDs.contains(selection.taskSelection?.taskID ?? UUID()) { clearSelectedTask() }
        appendLog(action: "删除任务", target: task.title, detail: "已移入垃圾箱 · \(tasks.count) 个任务")
        scheduleSave()
    }

    private func stopTimerIfNeeded(for taskIDs: Set<UUID>) {
        if let activeTaskID = database.activeTimer?.taskID, taskIDs.contains(activeTaskID) {
            database.activeTimer = nil
        }
    }

    private func emptyTrash() {
        let count = database.trashItems.count
        guard count > 0 else {
            notice = "垃圾箱已经是空的"
            return
        }
        database.trashItems.removeAll()
        appendLog(action: "倾倒垃圾箱", target: "垃圾箱", detail: "永久删除了 \(count) 个项目")
        selection.selectedArchive = .trash
        scheduleSave()
    }

    /// Shared by domain mutations so every destructive or editable action is
    /// recorded through the same AppModel coordination boundary.
    internal func appendLog(action: String, target: String, detail: String = "") {
        database.activityLog.insert(ActivityLogEntry(action: action, target: target, detail: detail), at: 0)
    }

    private func isDescendant(_ task: GTDTask, of ancestorID: UUID) -> Bool {
        var parent = task.parentID
        var seen = Set<UUID>()
        while let id = parent, !seen.contains(id) {
            if id == ancestorID { return true }
            seen.insert(id)
            parent = database.tasks.first(where: { $0.id == id })?.parentID
        }
        return false
    }
}
