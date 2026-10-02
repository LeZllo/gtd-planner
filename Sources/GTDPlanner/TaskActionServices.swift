import Foundation

/// The scope belongs to the row, rather than the current sidebar selection.
/// A dated row must never silently fall back to completing the whole task.
enum TaskActionScope: Equatable, Sendable {
    case task
    case day(Date)
}

enum TaskActionCompletion: Equatable, Sendable {
    case completeTask
    case completeRecurringTask
    case reopenTask
    case completeDay
    case reopenDay
    case futurePlan
    case historyOnly
    case unavailable

    var title: String {
        switch self {
        case .completeTask: "完成任务"
        case .completeRecurringTask: "完成整个重复任务…"
        case .reopenTask: "重新打开任务"
        case .completeDay: "完成当天实例"
        case .reopenDay: "重新打开当天实例"
        case .futurePlan: "未来日期不能标记完成"
        case .historyOnly: "历史任务仅供查看"
        case .unavailable: "当前无法更改完成状态"
        }
    }

    var systemImage: String {
        switch self {
        case .reopenTask, .reopenDay: "arrow.uturn.backward.circle"
        case .futurePlan: "calendar"
        case .historyOnly, .unavailable: "clock"
        default: "checkmark.circle"
        }
    }

    var isEnabled: Bool {
        switch self {
        case .futurePlan, .historyOnly, .unavailable: false
        default: true
        }
    }

    var requiresConfirmation: Bool { self == .completeRecurringTask }
}

enum TaskActionRules {
    static func completion(
        task: GTDTask,
        scope: TaskActionScope,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> TaskActionCompletion {
        switch scope {
        case .task:
            if task.status.isFinished { return .reopenTask }
            return TodayExecutionProjection.isDailyRecurring(task) ? .completeRecurringTask : .completeTask
        case .day(let day):
            let date = calendar.startOfDay(for: day)
            let today = calendar.startOfDay(for: now)
            guard date <= today else { return .futurePlan }
            let isDaily = TodayExecutionProjection.isDailyRecurring(task)
            // Ordinary historical rows cannot record a misleading completion
            // with today's timestamp, including reopening an old completion.
            guard date == today || isDaily else { return .historyOnly }
            if task.status.isFinished {
                // This is explicitly a whole-task reopen, never a daily token.
                return date == today ? .reopenTask : .unavailable
            }
            guard TodayExecutionProjection.isRelevant(
                task, on: day, now: now, calendar: calendar,
                includeOverdueBacklog: date == today
            ) else { return .unavailable }
            if isDaily {
                guard !TaskDayRules.isSkipped(task, on: day, calendar: calendar) else { return .unavailable }
                return TodayExecutionProjection.isCompleted(task, on: day, calendar: calendar)
                    ? .reopenDay : .completeDay
            }
            return .completeTask
        }
    }

    static func schedulingDay(
        scope: TaskActionScope,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Date {
        let today = calendar.startOfDay(for: now)
        guard case .day(let day) = scope else { return today }
        return max(today, calendar.startOfDay(for: day))
    }
}

extension AppModel {
    /// Every menu and command resolves identity at action time. A retained row
    /// from a different workspace is never a writable task snapshot.
    func taskActionTask(taskID: UUID) -> GTDTask? {
        guard let task = task(withID: taskID),
              task.workspaceID == selection.selectedWorkspaceID,
              workspace(withID: task.workspaceID) != nil else { return nil }
        return task
    }

    func taskActionCompletion(
        taskID: UUID,
        scope: TaskActionScope = .task,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> TaskActionCompletion {
        guard let task = taskActionTask(taskID: taskID) else { return .unavailable }
        return TaskActionRules.completion(task: task, scope: scope, now: now, calendar: calendar)
    }

    @discardableResult
    func performTaskCompletionAction(
        taskID: UUID,
        scope: TaskActionScope = .task,
        confirmRecurringTask: Bool = false,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        let action = taskActionCompletion(taskID: taskID, scope: scope, now: now, calendar: calendar)
        guard action.isEnabled, !action.requiresConfirmation || confirmRecurringTask else { return false }
        switch action {
        case .completeTask, .completeRecurringTask:
            setTaskStatus(taskID, to: .done)
        case .reopenTask:
            setTaskStatus(taskID, to: .open)
        case .completeDay, .reopenDay:
            guard case .day(let day) = scope else { return false }
            toggleTodayCompletion(taskID: taskID, on: day, calendar: calendar)
        case .futurePlan, .historyOnly, .unavailable:
            return false
        }
        return true
    }

    /// These shortcuts only touch their named field and the mutation timestamp.
    /// They do not round-trip a stale editor's plan, status, tags, or slots.
    @discardableResult
    func setTaskPriority(taskID: UUID, priority: Priority) -> Bool {
        guard let task = taskActionTask(taskID: taskID),
              let index = database.tasks.firstIndex(where: { $0.id == task.id }) else { return false }
        guard task.priority != priority else { return true }
        database.tasks[index].priority = priority
        database.tasks[index].updatedAt = .now
        scheduleSave(domain: .task)
        return true
    }

    @discardableResult
    func setTaskDeadline(
        taskID: UUID,
        shortcut: TaskDeadlineShortcut?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        guard let task = taskActionTask(taskID: taskID),
              let index = database.tasks.firstIndex(where: { $0.id == task.id }) else { return false }
        let deadline = shortcut.map { TaskDateNormalizer.shortcutDeadline($0, relativeTo: now, calendar: calendar) }
        let precision: DeadlinePrecision = shortcut == nil ? .none : .date
        guard task.deadline != deadline || task.deadlinePrecision != precision else { return true }
        database.tasks[index].deadline = deadline
        database.tasks[index].deadlinePrecision = precision
        database.tasks[index].updatedAt = now
        scheduleSave(domain: .task)
        return true
    }

    @discardableResult
    func requestTaskActionDeletion(taskID: UUID) -> Bool {
        guard let task = taskActionTask(taskID: taskID) else { return false }
        requestDeleteTask(task)
        return true
    }

    /// Changing a task's project moves its subtree as one unit. The root leaves
    /// its former parent/section; descendants retain their own parent links.
    /// Historical actual time remains attached to the same task identities.
    @discardableResult
    func moveTaskToProject(taskID: UUID, projectID: UUID?) -> Bool {
        guard let source = taskActionTask(taskID: taskID) else { return false }
        if let projectID {
            guard database.projects.contains(where: {
                $0.id == projectID && $0.workspaceID == source.workspaceID
            }) else { return false }
        }
        guard source.projectID != projectID else { return true }
        let movedIDs = TaskReorderService.descendantTaskIDs(in: database, of: taskID)
        let movedTasks = database.tasks.filter { movedIDs.contains($0.id) }
        guard movedIDs.contains(taskID),
              movedTasks.allSatisfy({ $0.workspaceID == source.workspaceID }) else { return false }
        let peers = database.tasks.filter {
            !movedIDs.contains($0.id) && $0.workspaceID == source.workspaceID
                && $0.projectID == projectID && $0.sectionID == nil && $0.parentID == nil
        }
        let rootOrder = (peers.map(\.order).max() ?? -1) + 1
        let changedAt = Date.now
        for index in database.tasks.indices where movedIDs.contains(database.tasks[index].id) {
            database.tasks[index].projectID = projectID
            database.tasks[index].sectionID = nil
            database.tasks[index].updatedAt = changedAt
            if database.tasks[index].id == taskID {
                database.tasks[index].parentID = nil
                database.tasks[index].order = rootOrder
            }
        }
        scheduleSave(domain: .task)
        return true
    }

    /// Copies this item only. Actual focus records, children, activity history,
    /// occurrence history, and reserved time-boxes stay with the original.
    @discardableResult
    func duplicateTask(taskID: UUID, now: Date = .now) -> GTDTask? {
        guard let source = taskActionTask(taskID: taskID) else { return nil }
        let projectID = source.projectID.flatMap { id in
            database.projects.first { $0.id == id && $0.workspaceID == source.workspaceID }?.id
        }
        let parent = source.parentID.flatMap { id in
            database.tasks.first {
                $0.id == id && $0.id != source.id && $0.workspaceID == source.workspaceID
                    && $0.projectID == projectID
            }
        }
        // A child's section follows its parent, including the unsectioned case.
        let sectionCandidate: UUID? = if let parent { parent.sectionID } else { source.sectionID }
        let sectionID = sectionCandidate.flatMap { id in
            database.projectSections.first { $0.id == id && $0.projectID == projectID }?.id
        }
        var copy = source
        copy.id = UUID()
        copy.title = source.title + "（副本）"
        copy.projectID = projectID
        copy.parentID = parent?.id
        copy.sectionID = sectionID
        if copy.status.isFinished { copy.status = .open }
        copy.completedAt = nil
        copy.completedInstances = []
        copy.skippedInstances = []
        copy.executionSlots = []
        copy.createdAt = now
        copy.updatedAt = now
        let peers = database.tasks.filter {
            $0.workspaceID == source.workspaceID && $0.projectID == copy.projectID
                && $0.sectionID == copy.sectionID && $0.parentID == copy.parentID
        }
        copy.order = (peers.map(\.order).max() ?? -1) + 1
        database.tasks.append(copy)
        scheduleSave(domain: .task)
        return copy
    }
}
