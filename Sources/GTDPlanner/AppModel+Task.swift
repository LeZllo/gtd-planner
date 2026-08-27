import Foundation

enum TaskInsertionPlacement {
    case beginning
    case end
}

struct InboxTaskClarification: Equatable, Sendable {
    var workspaceID: UUID
    var projectID: UUID?
    var sectionID: UUID?
    var actionList: ActionList
    var priority: Priority
    var tags: [String]
    var note: String
    var plannedStart: Date?
    var plannedEnd: Date?
    var plannedPrecision: DeadlinePrecision
    var deadline: Date?
    var deadlinePrecision: DeadlinePrecision
}

enum TaskDeadlineShortcut: CaseIterable, Hashable {
    case today
    case tomorrow
    case thisWeekend
}

enum TaskDateNormalizer {
    static func normalizedPlan(
        start: Date,
        end: Date?,
        precision: DeadlinePrecision,
        calendar: Calendar = .current
    ) -> (start: Date, end: Date?)? {
        switch precision {
        case .none:
            return nil
        case .minute:
            guard let end else { return (start, nil) }
            guard end > start else { return nil }
            return (start, end)
        case .date:
            let startDay = calendar.startOfDay(for: start)
            guard let end else { return (startDay, nil) }
            let selectedEndDay = calendar.startOfDay(for: end)
            guard selectedEndDay >= startDay else { return nil }
            let exclusiveEnd = calendar.date(byAdding: .day, value: 1, to: selectedEndDay) ?? selectedEndDay
            return (startDay, exclusiveEnd.addingTimeInterval(-1))
        }
    }

    static func normalizedDeadline(
        _ deadline: Date,
        precision: DeadlinePrecision,
        calendar: Calendar = .current
    ) -> Date? {
        switch precision {
        case .none:
            return nil
        case .minute:
            return deadline
        case .date:
            return endOfDay(containing: deadline, calendar: calendar)
        }
    }

    static func shortcutDeadline(
        _ shortcut: TaskDeadlineShortcut,
        relativeTo now: Date = .now,
        calendar: Calendar = .current
    ) -> Date {
        let targetDay: Date
        switch shortcut {
        case .today:
            targetDay = now
        case .tomorrow:
            targetDay = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        case .thisWeekend:
            targetDay = calendar.dateInterval(of: .weekOfYear, for: now)?.end.addingTimeInterval(-1) ?? now
        }
        return endOfDay(containing: targetDay, calendar: calendar)
    }

    private static func endOfDay(containing date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return nextDay.addingTimeInterval(-1)
    }
}

extension AppModel {
    func addTask(title: String, projectID: UUID? = nil, sectionID: UUID? = nil, parentID: UUID? = nil,
                 status: TaskStatus, priority: Priority = .none,
                 actionList: ActionList = .nextAction,
                 plannedStart: Date? = nil, plannedEnd: Date? = nil,
                 plannedPrecision: DeadlinePrecision = .none,
                 deadline: Date? = nil, deadlinePrecision: DeadlinePrecision = .none,
                 tags: [String] = [], contexts: [String] = [], note: String = "",
                 insertionPlacement: TaskInsertionPlacement = .beginning) {
        let resolvedParent: GTDTask? = parentID.flatMap { candidateID in
            self.task(withID: candidateID).flatMap { candidate in
                candidate.workspaceID == selection.selectedWorkspaceID && candidate.projectID == projectID
                    ? candidate
                    : nil
            }
        }
        let resolvedParentID = resolvedParent?.id
        let resolvedSectionID = resolvedParent?.sectionID ?? sectionID
        let peerTasks: [GTDTask] = (projectID.flatMap { taskIndex.tasksByProject[$0] }
            ?? taskIndex.tasksByWorkspace[selection.selectedWorkspaceID] ?? [])
            .filter {
                $0.projectID == projectID &&
                    $0.sectionID == resolvedSectionID &&
                    $0.parentID == resolvedParentID
            }
        let order: Int
        if peerTasks.isEmpty {
            order = 0
        } else {
            switch insertionPlacement {
            case .beginning:
                order = (peerTasks.map(\.order).min() ?? 0) - 1
            case .end:
                order = (peerTasks.map(\.order).max() ?? 0) + 1
            }
        }
        let canonicalTags = canonicalTagNames(tags, workspaceID: selection.selectedWorkspaceID)
        let task = GTDTask(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            workspaceID: selection.selectedWorkspaceID,
            projectID: projectID,
            sectionID: resolvedSectionID,
            parentID: resolvedParentID,
            status: status,
            priority: priority,
            actionList: actionList,
            tags: canonicalTags,
            contexts: contexts,
            plannedStart: plannedStart,
            plannedEnd: plannedEnd,
            plannedPrecision: plannedStart == nil ? .none : (plannedPrecision == .none ? .minute : plannedPrecision),
            deadline: deadline,
            deadlinePrecision: deadlinePrecision,
            note: note,
            completedAt: status == .done ? .now : nil,
            order: order
        )
        guard !task.title.isEmpty else { return }
        database.tasks.append(task)
        // Creating a task is a creation action, not a selection action. The
        // newly inserted row must not inherit the inspector selection tint;
        // an explicit click is the only operation that selects a task.
        scheduleSave(domain: .task)
    }

    /// Commits inbox routing and clarification fields only after the entire
    /// destination chain has been validated. Historical time entries are not
    /// rewritten when a task moves between workspaces.
    @discardableResult
    func clarifyInboxTask(_ taskID: UUID, with clarification: InboxTaskClarification) -> Bool {
        guard workspaceIndex.workspaceByID[clarification.workspaceID] != nil else {
            notice = "所选工作区已不存在"
            return false
        }
        guard let taskIndex = database.tasks.firstIndex(where: { $0.id == taskID }),
              database.tasks[taskIndex].status == .inbox else {
            notice = "该任务已不在收集箱"
            return false
        }

        if let projectID = clarification.projectID {
            guard let project = projectIndex.projectByID[projectID],
                  project.workspaceID == clarification.workspaceID else {
                notice = "所选项目不属于当前工作区"
                return false
            }
        }
        if let sectionID = clarification.sectionID {
            guard let projectID = clarification.projectID,
                  projectIndex.sectionsByProject[projectID]?.contains(where: { $0.id == sectionID }) == true else {
                notice = "所选分组不属于当前项目"
                return false
            }
        }

        let normalizedPlan: (start: Date, end: Date?)?
        if let plannedStart = clarification.plannedStart {
            guard let plan = TaskDateNormalizer.normalizedPlan(
                start: plannedStart,
                end: clarification.plannedEnd,
                precision: clarification.plannedPrecision
            ) else {
                notice = "计划结束必须晚于计划时间"
                return false
            }
            normalizedPlan = plan
        } else {
            normalizedPlan = nil
        }
        let normalizedDeadline = clarification.deadline.flatMap {
            TaskDateNormalizer.normalizedDeadline($0, precision: clarification.deadlinePrecision)
        }
        let canonicalTags = canonicalTagNames(clarification.tags, workspaceID: clarification.workspaceID)

        let affectedTaskIDs = TaskReorderService.descendantTaskIDs(in: database, of: taskID)
        let targetOrder = database.tasks
            .filter {
                !affectedTaskIDs.contains($0.id) &&
                    $0.workspaceID == clarification.workspaceID &&
                    $0.projectID == clarification.projectID &&
                    $0.sectionID == clarification.sectionID &&
                    $0.parentID == nil
            }
            .map(\.order)
            .min()
            .map { $0 - 1 } ?? 0
        let changedAt = Date.now

        for index in database.tasks.indices where affectedTaskIDs.contains(database.tasks[index].id) {
            database.tasks[index].workspaceID = clarification.workspaceID
            database.tasks[index].projectID = clarification.projectID
            database.tasks[index].sectionID = clarification.sectionID
            database.tasks[index].updatedAt = changedAt
            if database.tasks[index].status == .inbox {
                database.tasks[index].status = .open
                database.tasks[index].completedAt = nil
            }
        }

        database.tasks[taskIndex].parentID = nil
        database.tasks[taskIndex].order = targetOrder
        database.tasks[taskIndex].actionList = clarification.actionList
        database.tasks[taskIndex].priority = clarification.priority
        database.tasks[taskIndex].tags = canonicalTags
        database.tasks[taskIndex].note = clarification.note
        database.tasks[taskIndex].plannedStart = normalizedPlan?.start
        database.tasks[taskIndex].plannedEnd = normalizedPlan?.end
        database.tasks[taskIndex].plannedPrecision = normalizedPlan == nil ? .none : clarification.plannedPrecision
        database.tasks[taskIndex].deadline = normalizedDeadline
        database.tasks[taskIndex].deadlinePrecision = normalizedDeadline == nil ? .none : clarification.deadlinePrecision

        let destination = clarification.projectID.flatMap { projectIndex.projectByID[$0]?.name }
            ?? workspaceIndex.workspaceByID[clarification.workspaceID]?.name
            ?? "未指定项目"
        appendLog(action: "澄清收集箱", target: database.tasks[taskIndex].title, detail: "已归类到 \(destination)")
        scheduleSave(domain: .task)
        return true
    }

    /// Creates an actionable child at the beginning of its sibling list and carries
    /// forward the parent's scheduling metadata. A child created from C3 is always
    /// open; inbox capture is reserved for UI-01's quick collector.
    func addSubtask(title: String, to parentID: UUID) {
        guard let parent = task(withID: parentID),
              parent.workspaceID == selection.selectedWorkspaceID else { return }

        addTask(
            title: title,
            projectID: parent.projectID,
            sectionID: parent.sectionID,
            parentID: parent.id,
            status: .open,
            priority: parent.priority,
            actionList: parent.actionList,
            plannedStart: parent.plannedStart,
            plannedEnd: parent.plannedEnd,
            plannedPrecision: parent.plannedPrecision,
            deadline: parent.deadline,
            deadlinePrecision: parent.deadlinePrecision,
            tags: parent.tags,
            contexts: parent.contexts,
            insertionPlacement: .beginning
        )
    }

    @discardableResult
    func moveTask(
        _ taskID: UUID,
        toSectionID sectionID: UUID?,
        toParentID parentID: UUID? = nil,
        beforeTaskID: UUID? = nil
    ) -> Bool {
        guard TaskReorderService.moveTask(
            in: &database,
            taskID: taskID,
            workspaceID: selection.selectedWorkspaceID,
            toSectionID: sectionID,
            toParentID: parentID,
            beforeTaskID: beforeTaskID
        ) else { return false }
        scheduleSave(domain: .task)
        return true
    }

    func invalidParentTaskIDs(for taskID: UUID) -> Set<UUID> {
        TaskReorderService.descendantTaskIDs(in: database, of: taskID)
    }

    func updateTask(_ task: GTDTask) {
        guard let index = database.tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let previousStatus = database.tasks[index].status
        var updated = task
        updated.tags = canonicalTagNames(updated.tags, workspaceID: updated.workspaceID)
        updated.updatedAt = .now
        if updated.status == .done, previousStatus != .done { updated.completedAt = .now }
        if updated.status != .done { updated.completedAt = nil }
        database.tasks[index] = updated

        guard previousStatus != updated.status else {
            scheduleSave(domain: .task)
            return
        }

        cascadeTaskStatusChange(
            from: previousStatus,
            to: updated.status,
            taskID: updated.id,
            changedAt: updated.updatedAt
        )
        scheduleSave(domain: .task)
    }

    func setTaskStatus(_ taskID: UUID, to status: TaskStatus) {
        guard var task = task(withID: taskID), task.status != status else { return }
        task.status = status
        updateTask(task)
    }

    func toggleTask(_ taskID: UUID) {
        guard let task = task(withID: taskID) else { return }
        setTaskStatus(taskID, to: task.status == .done ? .open : .done)
    }

    /// Compatibility entry point for older views. Resolve by stable identity
    /// so a retained value snapshot can never apply the same toggle twice or
    /// overwrite a newer status.
    func toggleTask(_ task: GTDTask) {
        toggleTask(task.id)
    }

    /// Keeps hierarchy state coherent while preserving branch-level control:
    /// completing a task completes its whole subtree; reopening a completed
    /// task reopens its subtree and every completed ancestor, but leaves
    /// sibling branches untouched.
    private func cascadeTaskStatusChange(
        from previousStatus: TaskStatus,
        to status: TaskStatus,
        taskID: UUID,
        changedAt: Date
    ) {
        if status == .done {
            let descendantIDs = TaskReorderService.descendantTaskIDs(in: database, of: taskID)
            for index in database.tasks.indices
            where descendantIDs.contains(database.tasks[index].id) && database.tasks[index].id != taskID {
                database.tasks[index].status = .done
                database.tasks[index].completedAt = changedAt
                database.tasks[index].updatedAt = changedAt
            }
            return
        }

        guard !status.isFinished else { return }

        if previousStatus == .done {
            let descendantIDs = TaskReorderService.descendantTaskIDs(in: database, of: taskID)
            for index in database.tasks.indices
            where descendantIDs.contains(database.tasks[index].id) && database.tasks[index].id != taskID {
                database.tasks[index].status = .open
                database.tasks[index].completedAt = nil
                database.tasks[index].updatedAt = changedAt
            }
        }

        let taskByID = Dictionary(uniqueKeysWithValues: database.tasks.map { ($0.id, $0) })
        var parentID = taskByID[taskID]?.parentID
        var visited: Set<UUID> = []
        while let currentParentID = parentID, visited.insert(currentParentID).inserted {
            guard let ancestor = taskByID[currentParentID] else { break }
            if ancestor.status == .done,
               let index = database.tasks.firstIndex(where: { $0.id == currentParentID }) {
                database.tasks[index].status = .open
                database.tasks[index].completedAt = nil
                database.tasks[index].updatedAt = changedAt
            }
            parentID = ancestor.parentID
        }
    }
}
