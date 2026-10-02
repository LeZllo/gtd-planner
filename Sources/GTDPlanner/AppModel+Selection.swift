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

    /// Explicit date-view creation has a visible contextual default. Other
    /// contexts still create tasks without an implicit plan or deadline.
    func defaultTaskPlanningDay(now: Date = .now, calendar: Calendar = .current) -> Date? {
        guard selection.selectedOrganization == nil, selection.selectedArchive == nil,
              selection.focusMode == nil, selection.selectedProjectID == nil else { return nil }
        switch selection.selectedSmartList {
        case .today:
            return calendar.startOfDay(for: now)
        case .calendar:
            return calendar.startOfDay(for: selection.calendarDay ?? now)
        case .tomorrow, .recent:
            let horizon: PlanningHorizon = selection.selectedSmartList == .tomorrow ? .tomorrow : .nextSevenDays
            let days = horizon.days(relativeTo: now, calendar: calendar)
            if let selected = selection.planningDay,
               let day = days.first(where: { calendar.isDate($0, inSameDayAs: selected) }) {
                return day
            }
            return days.first
        default:
            return nil
        }
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
        selection.planningDay = nil
        selection.calendarDay = nil
        selection.selectedProjectID = nil
        selection.selectedTag = nil
        clearSelectedTask()
        selection.plannerView = list == .calendar ? .calendar : .list
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
