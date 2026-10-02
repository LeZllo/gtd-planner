import Foundation
import Testing
@testable import GTDPlanner

@MainActor
struct TaskActionTests {
    @Test("Task actions resolve current status and reopen cancelled tasks")
    func canonicalCompletionAndCancellation() throws {
        let fixture = Fixture()
        let task = fixture.task("Current task")
        let model = fixture.model([task])
        #expect(model.performTaskCompletionAction(taskID: task.id))
        #expect(model.task(withID: task.id)?.status == .done)
        #expect(model.taskActionCompletion(taskID: task.id) == .reopenTask)
        #expect(model.performTaskCompletionAction(taskID: task.id))
        #expect(model.task(withID: task.id)?.status == .open)
        model.setTaskStatus(task.id, to: .cancelled)
        #expect(model.taskActionCompletion(taskID: task.id) == .reopenTask)
        #expect(model.performTaskCompletionAction(taskID: task.id))
        let reopened = try #require(model.task(withID: task.id))
        #expect(reopened.status == .open)
        #expect(reopened.completedAt == nil)
    }

    @Test("Daily whole-task completion requires confirmation without changing the day token")
    func recurringTaskConfirmation() throws {
        let fixture = Fixture()
        var daily = fixture.task("Daily")
        daily.recurrence = "FREQ=DAILY"
        let model = fixture.model([daily])
        let revision = model.taskRevision
        #expect(model.taskActionCompletion(taskID: daily.id) == .completeRecurringTask)
        #expect(model.taskActionCompletion(taskID: daily.id).requiresConfirmation)
        #expect(!model.performTaskCompletionAction(taskID: daily.id))
        #expect(model.taskRevision == revision)
        #expect(model.task(withID: daily.id)?.status == .open)
        #expect(model.performTaskCompletionAction(taskID: daily.id, confirmRecurringTask: true))
        let completed = try #require(model.task(withID: daily.id))
        #expect(completed.status == .done)
        #expect(completed.completedInstances.isEmpty)
        #expect(model.performTaskCompletionAction(taskID: daily.id))
        #expect(model.task(withID: daily.id)?.status == .open)
    }

    @Test("Today daily actions toggle only the dated occurrence and are reversible")
    func todayDailyInstance() throws {
        let fixture = Fixture()
        var daily = fixture.task("Daily")
        daily.recurrence = "FREQ=DAILY"
        var child = fixture.task("Child")
        child.parentID = daily.id
        let model = fixture.model([daily, child])
        let scope = TaskActionScope.day(fixture.date(2))
        #expect(model.taskActionCompletion(taskID: daily.id, scope: scope, now: fixture.now, calendar: fixture.calendar) == .completeDay)
        #expect(model.performTaskCompletionAction(taskID: daily.id, scope: scope, now: fixture.now, calendar: fixture.calendar))
        let changed = try #require(model.task(withID: daily.id))
        #expect(changed.status == .open)
        #expect(changed.completedAt == nil)
        #expect(changed.completedInstances == ["2026-10-02"])
        #expect(model.task(withID: child.id)?.status == .open)
        #expect(model.taskActionCompletion(taskID: daily.id, scope: scope, now: fixture.now, calendar: fixture.calendar) == .reopenDay)
        #expect(model.performTaskCompletionAction(taskID: daily.id, scope: scope, now: fixture.now, calendar: fixture.calendar))
        #expect(model.task(withID: daily.id)?.completedInstances.isEmpty == true)
    }

    @Test("Past daily occurrences are editable while ordinary historical tasks are read-only")
    func historicalCompletionRules() {
        let fixture = Fixture()
        var ordinary = fixture.task("Ordinary")
        ordinary.plannedStart = fixture.date(1)
        var daily = ordinary
        daily.id = UUID()
        daily.recurrence = "FREQ=DAILY"
        let model = fixture.model([ordinary, daily])
        let scope = TaskActionScope.day(fixture.date(1))
        #expect(model.taskActionCompletion(taskID: ordinary.id, scope: scope, now: fixture.now, calendar: fixture.calendar) == .historyOnly)
        #expect(!model.performTaskCompletionAction(taskID: ordinary.id, scope: scope, now: fixture.now, calendar: fixture.calendar))
        #expect(model.performTaskCompletionAction(taskID: daily.id, scope: scope, now: fixture.now, calendar: fixture.calendar))
        #expect(model.task(withID: daily.id)?.completedInstances == ["2026-10-01"])
        #expect(model.task(withID: ordinary.id)?.status == .open)
    }

    @Test("Future days cannot complete or reopen occurrences even with whole-task confirmation")
    func futureCompletionNeverMutates() {
        let fixture = Fixture()
        for recurrence in ["", "FREQ=DAILY"] {
            for status in [TaskStatus.open, .done, .cancelled] {
                var task = fixture.task("Future")
                task.recurrence = recurrence
                task.status = status
                task.completedInstances = ["2026-10-03"]
                task.plannedStart = fixture.date(3)
                let model = fixture.model([task])
                let before = model.task(withID: task.id)
                let revision = model.taskRevision
                let scope = TaskActionScope.day(fixture.date(3))
                #expect(model.taskActionCompletion(taskID: task.id, scope: scope, now: fixture.now, calendar: fixture.calendar) == .futurePlan)
                #expect(!model.performTaskCompletionAction(taskID: task.id, scope: scope, confirmRecurringTask: true, now: fixture.now, calendar: fixture.calendar))
                #expect(model.task(withID: task.id) == before)
                #expect(model.taskRevision == revision)
            }
        }
    }

    @Test("Skipped and not-yet-started daily occurrences cannot be completed")
    func unavailableDailyOccurrences() {
        let fixture = Fixture()
        var skipped = fixture.task("Skipped")
        skipped.recurrence = "FREQ=DAILY"
        skipped.skippedInstances = ["2026-10-02"]
        var later = fixture.task("Starts later")
        later.recurrence = "FREQ=DAILY"
        later.plannedStart = fixture.date(3)
        let model = fixture.model([skipped, later])
        let scope = TaskActionScope.day(fixture.date(2))
        for task in [skipped, later] {
            #expect(model.taskActionCompletion(taskID: task.id, scope: scope, now: fixture.now, calendar: fixture.calendar) == .unavailable)
            #expect(!model.performTaskCompletionAction(taskID: task.id, scope: scope, now: fixture.now, calendar: fixture.calendar))
        }
    }

    @Test("Today backlog is actionable while unrelated tasks cannot be completed as an occurrence")
    func todayMembership() {
        let fixture = Fixture()
        var overdue = fixture.task("Overdue")
        overdue.deadline = fixture.date(1)
        let unrelated = fixture.task("No date")
        let model = fixture.model([overdue, unrelated])
        let scope = TaskActionScope.day(fixture.date(2))
        #expect(model.taskActionCompletion(taskID: overdue.id, scope: scope, now: fixture.now, calendar: fixture.calendar) == .completeTask)
        #expect(model.performTaskCompletionAction(taskID: overdue.id, scope: scope, now: fixture.now, calendar: fixture.calendar))
        #expect(!model.performTaskCompletionAction(taskID: unrelated.id, scope: scope, now: fixture.now, calendar: fixture.calendar))
    }

    @Test("Date scopes are revalidated after midnight")
    func dateRollover() {
        let fixture = Fixture()
        var task = fixture.task("Today plan")
        task.plannedStart = fixture.date(2, 10)
        let model = fixture.model([task])
        let scope = TaskActionScope.day(fixture.date(2))
        #expect(model.taskActionCompletion(taskID: task.id, scope: scope, now: fixture.date(2, 23), calendar: fixture.calendar) == .completeTask)
        #expect(!model.performTaskCompletionAction(taskID: task.id, scope: scope, now: fixture.date(3), calendar: fixture.calendar))
        #expect(model.task(withID: task.id)?.status == .open)
    }

    @Test("Every command rejects a missing task and a task from another workspace")
    func workspaceAndMissingGuards() {
        let fixture = Fixture()
        let task = fixture.task("Original workspace")
        let other = Workspace(name: "Other", symbolName: "square", colorHex: "#0A84FF")
        var database = fixture.database([task])
        database.workspaces.append(other)
        database.workspaceOrder.append(other.id)
        let model = AppModel(database: database, storage: LocalDatabase(inMemory: true))
        model.selectWorkspace(other.id)
        let original = model.task(withID: task.id)
        let revision = model.taskRevision
        for id in [task.id, UUID()] {
            #expect(model.taskActionTask(taskID: id) == nil)
            #expect(model.taskActionCompletion(taskID: id) == .unavailable)
            #expect(!model.performTaskCompletionAction(taskID: id, confirmRecurringTask: true))
            #expect(!model.setTaskPriority(taskID: id, priority: .high))
            #expect(!model.setTaskDeadline(taskID: id, shortcut: .today))
            #expect(!model.requestTaskActionDeletion(taskID: id))
            #expect(model.duplicateTask(taskID: id) == nil)
        }
        #expect(model.task(withID: task.id) == original)
        #expect(model.taskRevision == revision)
        #expect(model.pendingDeletion == nil)
        #expect(model.database.tasks.count == 1)
    }

    @Test("Priority and deadline shortcuts preserve current planning fields and status")
    func narrowFieldUpdates() throws {
        let fixture = Fixture()
        var task = fixture.task("Keep current fields")
        task.recurrence = "FREQ=DAILY"
        task.note = "Keep note"
        task.plannedStart = fixture.date(2, 9)
        task.plannedEnd = fixture.date(4, 18)
        task.plannedPrecision = .minute
        task.planRangeIntent = .completeWithin
        task.executionSlots = [.init(start: fixture.date(3, 10), end: fixture.date(3, 11))]
        task.completedInstances = ["2026-10-01"]
        let model = fixture.model([task])
        var latest = try #require(model.task(withID: task.id))
        latest.note = "Changed in another presentation"
        latest.status = .inProgress
        model.updateTask(latest)
        let before = try #require(model.task(withID: task.id))
        #expect(model.setTaskPriority(taskID: task.id, priority: .high))
        #expect(model.setTaskDeadline(taskID: task.id, shortcut: .tomorrow, now: fixture.now, calendar: fixture.calendar))
        var after = try #require(model.task(withID: task.id))
        #expect(after.priority == .high)
        #expect(after.deadline == fixture.date(4).addingTimeInterval(-1))
        #expect(after.deadlinePrecision == .date)
        after.priority = before.priority
        after.deadline = before.deadline
        after.deadlinePrecision = before.deadlinePrecision
        after.updatedAt = before.updatedAt
        #expect(after == before)
        #expect(model.setTaskDeadline(taskID: task.id, shortcut: nil, now: fixture.now, calendar: fixture.calendar))
        let cleared = try #require(model.task(withID: task.id))
        #expect(cleared.deadline == nil)
        #expect(cleared.deadlinePrecision == .none)
        #expect(cleared.executionSlots == before.executionSlots)
        #expect(cleared.plannedStart == before.plannedStart)
    }

    @Test("No-op shortcuts do not create an unnecessary persistence revision")
    func noOpShortcuts() {
        let fixture = Fixture()
        let task = fixture.task("No-op")
        let model = fixture.model([task])
        let revision = model.taskRevision
        #expect(model.setTaskPriority(taskID: task.id, priority: .none))
        #expect(model.setTaskDeadline(taskID: task.id, shortcut: nil))
        #expect(model.taskRevision == revision)
    }

    @Test("Deadline shortcuts use natural local days across daylight saving")
    func deadlineAcrossDaylightSaving() throws {
        let fixture = Fixture()
        let task = fixture.task("DST")
        let model = fixture.model([task])
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        for (month, day) in [(3, 7), (10, 31)] {
            let now = try #require(calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12)))
            let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: now))
            let interval = try #require(calendar.dateInterval(of: .day, for: tomorrow))
            #expect(model.setTaskDeadline(taskID: task.id, shortcut: .tomorrow, now: now, calendar: calendar))
            #expect(model.task(withID: task.id)?.deadline == interval.end.addingTimeInterval(-1))
        }
    }

    @Test("Duplicate copies only one current item and resets execution and completion history")
    func duplicateItemOnly() throws {
        let fixture = Fixture()
        var source = fixture.task("Original")
        source.status = .done
        source.priority = .high
        source.actionList = .waiting
        source.tags = ["Research"]
        source.contexts = ["Desk"]
        source.recurrence = "FREQ=DAILY"
        source.note = "Reusable notes"
        source.plannedStart = fixture.date(2)
        source.plannedEnd = fixture.date(4)
        source.plannedPrecision = .date
        source.planRangeIntent = .completeWithin
        source.deadline = fixture.date(5)
        source.deadlinePrecision = .minute
        source.executionSlots = [.init(start: fixture.date(2, 10), end: fixture.date(2, 11))]
        source.completedAt = fixture.date(1)
        source.completedInstances = ["2026-10-01"]
        source.skippedInstances = ["2026-09-30"]
        source.createdAt = fixture.date(1)
        source.updatedAt = fixture.date(1)
        var child = fixture.task("Child")
        child.parentID = source.id
        let entry = TimeEntry(workspaceID: fixture.workspace.id, taskID: source.id, title: source.title,
                              startedAt: fixture.date(1, 10), endedAt: fixture.date(1, 11), source: .manual)
        let log = ActivityLogEntry(action: "Original history", target: source.title)
        var database = fixture.database([source, child])
        database.timeEntries = [entry]
        database.activityLog = [log]
        let model = AppModel(database: database, storage: LocalDatabase(inMemory: true))
        let canonical = try #require(model.task(withID: source.id))
        let copy = try #require(model.duplicateTask(taskID: source.id, now: fixture.now))
        #expect(copy.id != source.id)
        #expect(copy.title == "Original（副本）")
        #expect(copy.status == .open)
        #expect(copy.completedAt == nil)
        #expect(copy.completedInstances.isEmpty)
        #expect(copy.skippedInstances.isEmpty)
        #expect(copy.executionSlots.isEmpty)
        #expect(copy.createdAt == fixture.now)
        #expect(copy.updatedAt == fixture.now)
        #expect(copy.priority == canonical.priority)
        #expect(copy.actionList == canonical.actionList)
        #expect(copy.tags == canonical.tags)
        #expect(copy.contexts == canonical.contexts)
        #expect(copy.note == canonical.note)
        #expect(copy.recurrence == canonical.recurrence)
        #expect(copy.plannedStart == canonical.plannedStart)
        #expect(copy.plannedEnd == canonical.plannedEnd)
        #expect(copy.plannedPrecision == canonical.plannedPrecision)
        #expect(copy.planRangeIntent == canonical.planRangeIntent)
        #expect(copy.deadline == canonical.deadline)
        #expect(copy.deadlinePrecision == canonical.deadlinePrecision)
        #expect(model.database.tasks.count == 3)
        #expect(model.database.tasks.filter { $0.parentID == copy.id }.isEmpty)
        #expect(model.database.timeEntries == [entry])
        #expect(model.database.activityLog == [log])
        #expect(model.task(withID: source.id) == canonical)
        #expect(model.selectedTask == nil)
    }

    @Test("Duplicate retains valid project-section-parent identity and receives a sibling order")
    func duplicateHierarchy() throws {
        let fixture = Fixture()
        let project = Project(workspaceID: fixture.workspace.id, category: "Work", name: "Project", colorHex: "#0A84FF")
        let section = ProjectSection(projectID: project.id, name: "Section")
        var parent = fixture.task("Parent")
        parent.projectID = project.id
        parent.sectionID = section.id
        var child = fixture.task("Child")
        child.projectID = project.id
        child.sectionID = section.id
        child.parentID = parent.id
        child.order = 5
        var database = fixture.database([parent, child])
        database.projects = [project]
        database.projectSections = [section]
        let model = AppModel(database: database, storage: LocalDatabase(inMemory: true))
        let copy = try #require(model.duplicateTask(taskID: child.id, now: fixture.now))
        #expect(copy.projectID == project.id)
        #expect(copy.sectionID == section.id)
        #expect(copy.parentID == parent.id)
        #expect(copy.order > model.task(withID: child.id)!.order)
    }

    @Test("Duplicate repairs invalid cross-workspace project and parent links")
    func duplicateRejectsInvalidRelationships() throws {
        let fixture = Fixture()
        let source = fixture.task("Invalid relationships")
        let model = fixture.model([source])
        // Introduce stale relationships after import normalization to exercise
        // the action-time validation rather than the database migration.
        let foreignWorkspace = UUID()
        let foreignProject = Project(workspaceID: foreignWorkspace, category: "Other", name: "Foreign", colorHex: "#0A84FF")
        var foreignParent = fixture.task("Foreign parent")
        foreignParent.workspaceID = foreignWorkspace
        foreignParent.projectID = foreignProject.id
        let foreignSection = ProjectSection(projectID: foreignProject.id, name: "Foreign section")
        model.database.projects.append(foreignProject)
        model.database.projectSections.append(foreignSection)
        model.database.tasks.append(foreignParent)
        model.database.tasks[0].projectID = foreignProject.id
        model.database.tasks[0].sectionID = foreignSection.id
        model.database.tasks[0].parentID = foreignParent.id
        model.invalidateQueryIndex()
        let copy = try #require(model.duplicateTask(taskID: source.id, now: fixture.now))
        #expect(copy.workspaceID == fixture.workspace.id)
        #expect(copy.projectID == nil)
        #expect(copy.sectionID == nil)
        #expect(copy.parentID == nil)
    }

    @Test("Moving projects detaches the root and preserves subtree plans, identities, and actual records")
    func moveProjectSubtree() throws {
        let fixture = Fixture()
        let oldProject = Project(workspaceID: fixture.workspace.id, category: "Work", name: "Old", colorHex: "#0A84FF")
        let newProject = Project(workspaceID: fixture.workspace.id, category: "Work", name: "New", colorHex: "#0A84FF")
        let section = ProjectSection(projectID: oldProject.id, name: "Old section")
        var ancestor = fixture.task("Ancestor")
        ancestor.projectID = oldProject.id
        ancestor.sectionID = section.id
        var root = fixture.task("Move this branch")
        root.projectID = oldProject.id
        root.sectionID = section.id
        root.parentID = ancestor.id
        root.plannedStart = fixture.date(3, 9)
        root.plannedEnd = fixture.date(3, 17)
        root.plannedPrecision = .minute
        root.deadline = fixture.date(4)
        root.executionSlots = [.init(start: fixture.date(3, 10), end: fixture.date(3, 11))]
        var child = root
        child.id = UUID()
        child.title = "Child"
        child.parentID = root.id
        var grandchild = child
        grandchild.id = UUID()
        grandchild.title = "Grandchild"
        grandchild.parentID = child.id
        let entry = TimeEntry(workspaceID: fixture.workspace.id, taskID: root.id, title: root.title,
                              startedAt: fixture.date(1, 10), endedAt: fixture.date(1, 11), source: .manual)
        var database = fixture.database([ancestor, root, child, grandchild])
        database.projects = [oldProject, newProject]
        database.projectSections = [section]
        database.timeEntries = [entry]
        let model = AppModel(database: database, storage: LocalDatabase(inMemory: true))
        let ancestorBefore = model.task(withID: ancestor.id)
        #expect(model.moveTaskToProject(taskID: root.id, projectID: newProject.id))
        let movedRoot = try #require(model.task(withID: root.id))
        #expect(movedRoot.parentID == nil)
        #expect(model.task(withID: child.id)?.parentID == root.id)
        #expect(model.task(withID: grandchild.id)?.parentID == child.id)
        for original in [root, child, grandchild] {
            let moved = try #require(model.task(withID: original.id))
            #expect(moved.projectID == newProject.id)
            #expect(moved.sectionID == nil)
            #expect(moved.plannedStart == original.plannedStart)
            #expect(moved.plannedEnd == original.plannedEnd)
            #expect(moved.deadline == original.deadline)
            #expect(moved.executionSlots == original.executionSlots)
            #expect(moved.status == original.status)
        }
        #expect(model.task(withID: ancestor.id) == ancestorBefore)
        #expect(model.database.timeEntries == [entry])
        #expect(model.moveTaskToProject(taskID: root.id, projectID: nil))
        #expect(model.task(withID: root.id)?.projectID == nil)
        #expect(model.task(withID: child.id)?.projectID == nil)
        #expect(model.task(withID: child.id)?.parentID == root.id)
    }

    @Test("Moving projects rejects invalid destinations and cross-workspace descendants atomically")
    func moveProjectGuards() {
        let fixture = Fixture()
        let source = fixture.task("Source")
        let foreignWorkspace = Workspace(name: "Foreign", symbolName: "square", colorHex: "#0A84FF")
        let foreignProject = Project(workspaceID: foreignWorkspace.id, category: "Foreign", name: "Foreign", colorHex: "#0A84FF")
        let target = Project(workspaceID: fixture.workspace.id, category: "Work", name: "Target", colorHex: "#0A84FF")
        var database = fixture.database([source])
        database.workspaces.append(foreignWorkspace)
        database.projects = [foreignProject, target]
        let model = AppModel(database: database, storage: LocalDatabase(inMemory: true))
        let before = model.task(withID: source.id)
        let revision = model.taskRevision
        #expect(!model.moveTaskToProject(taskID: source.id, projectID: foreignProject.id))
        #expect(!model.moveTaskToProject(taskID: source.id, projectID: UUID()))
        #expect(!model.moveTaskToProject(taskID: UUID(), projectID: target.id))
        #expect(model.moveTaskToProject(taskID: source.id, projectID: nil))
        #expect(model.task(withID: source.id) == before)
        #expect(model.taskRevision == revision)
        var corruptChild = fixture.task("Foreign child")
        corruptChild.workspaceID = foreignWorkspace.id
        corruptChild.parentID = source.id
        model.database.tasks.append(corruptChild)
        model.invalidateQueryIndex(.task)
        #expect(!model.moveTaskToProject(taskID: source.id, projectID: target.id))
        #expect(model.task(withID: source.id) == before)
        #expect(model.task(withID: corruptChild.id) == corruptChild)
    }

    @Test("Requesting deletion preserves confirmation and cancellation leaves data intact")
    func deletionConfirmation() throws {
        let fixture = Fixture()
        let task = fixture.task("Keep until confirmed")
        let model = fixture.model([task])
        #expect(model.requestTaskActionDeletion(taskID: task.id))
        let request = try #require(model.pendingDeletion)
        #expect(request.target == .task(task.id))
        #expect(model.task(withID: task.id) != nil)
        #expect(model.database.trashItems.isEmpty)
        model.pendingDeletion = nil
        #expect(model.task(withID: task.id) != nil)
        #expect(model.database.trashItems.isEmpty)
        #expect(model.requestTaskActionDeletion(taskID: task.id))
        model.performDeletion(try #require(model.pendingDeletion))
        #expect(model.task(withID: task.id) == nil)
        #expect(model.database.trashItems.count == 1)
    }

    @Test("Scheduling uses the row's future day and does not carry a historical date forward")
    func schedulingDefaults() {
        let fixture = Fixture()
        #expect(TaskActionRules.schedulingDay(scope: .task, now: fixture.now, calendar: fixture.calendar) == fixture.date(2))
        #expect(TaskActionRules.schedulingDay(scope: .day(fixture.date(5, 18)), now: fixture.now, calendar: fixture.calendar) == fixture.date(5))
        #expect(TaskActionRules.schedulingDay(scope: .day(fixture.date(1)), now: fixture.now, calendar: fixture.calendar) == fixture.date(2))
    }

    private struct Fixture {
        let workspace = Workspace(name: "Task actions", symbolName: "checklist", colorHex: "#0A84FF")
        let calendar: Calendar = {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            return calendar
        }()
        var now: Date { date(2, 12) }

        func date(_ day: Int, _ hour: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
        }

        func task(_ title: String) -> GTDTask {
            GTDTask(title: title, workspaceID: workspace.id, parentID: nil, status: .open)
        }

        func database(_ tasks: [GTDTask]) -> GTDDatabase {
            GTDDatabase(workspaces: [workspace], workspaceOrder: [workspace.id],
                        pinnedWorkspaceIDs: [workspace.id], tasks: tasks)
        }

        @MainActor
        func model(_ tasks: [GTDTask]) -> AppModel {
            AppModel(database: database(tasks), storage: LocalDatabase(inMemory: true))
        }
    }
}
