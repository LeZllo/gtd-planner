import Foundation

extension AppModel {
    var currentTaskSelectionContext: TaskSelectionContext {
        TaskSelectionContext(
            workspaceID: selection.selectedWorkspaceID,
            projectID: selection.selectedProjectID,
            smartList: selection.selectedSmartList,
            plannerView: selection.plannerView,
            organization: selection.selectedOrganization,
            tagSelection: selection.selectedTag
        )
    }

    func selectTask(_ id: UUID) {
        guard taskIndex.taskByID[id] != nil else { return }
        selection.selectTask(TaskSelection(taskID: id, context: currentTaskSelectionContext))
    }

    func clearSelectedTask() {
        selection.clearSelectedTask()
    }

    func isTaskSelected(_ id: UUID) -> Bool {
        selection.taskSelection?.taskID == id && selection.taskSelection?.context == currentTaskSelectionContext
    }

    func selectSmartList(_ list: SmartList) {
        selection.focusMode = nil
        selection.selectedArchive = nil
        selection.selectedOrganization = nil
        selection.selectedSmartList = list
        selection.selectedProjectID = nil
        selection.selectedTag = nil
        clearSelectedTask()
        if list == .calendar { selection.plannerView = .calendar }
    }

    func selectProject(_ id: UUID?) {
        selection.focusMode = nil
        let wasGanttMode = selection.plannerView == .timeline
        selection.selectedArchive = nil
        selection.selectedOrganization = .projects
        selection.selectedProjectID = id
        selection.selectedTag = nil
        clearSelectedTask()
        selection.selectedSmartList = .all
        // Switching projects from the project-level Gantt view keeps the
        // planning context open while replacing its data. All other project
        // entry points continue to open the normal task list.
        selection.plannerView = wasGanttMode && id != nil ? .timeline : .list
    }

    func selectOrganization(_ item: OrganizationItem) {
        selection.focusMode = nil
        selection.selectedArchive = nil
        selection.selectedOrganization = item
        selection.selectedProjectID = nil
        if item != .tags { selection.selectedTag = nil }
        clearSelectedTask()
        switch item {
        case .inbox:
            selection.selectedSmartList = .inbox
            selection.plannerView = .list
        case .projects:
            selection.selectedSmartList = .all
            selection.plannerView = .list
        case .tags:
            selection.selectedSmartList = .all
            selection.plannerView = .list
            if selection.selectedTag == nil {
                selection.selectedTag = currentTagDefinitions.first.map { .tag($0.id) } ?? .untagged
            }
        case .filters:
            notice = "过滤器入口已保留，下一步可保存组合条件"
        }
    }

    func selectArchive(_ item: ArchiveItem) {
        selection.focusMode = nil
        selection.selectedArchive = item
        selection.selectedOrganization = nil
        selection.selectedProjectID = nil
        selection.selectedTag = nil
        clearSelectedTask()
        selection.selectedSmartList = .all
        selection.plannerView = .list
    }
}
