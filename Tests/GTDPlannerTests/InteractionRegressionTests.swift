import CoreGraphics
import Foundation
import Observation
import Testing
@testable import GTDPlanner

@MainActor
struct InteractionRegressionTests {
    @Test("Task toggles resolve canonical state and refresh every projection")
    func taskStatusUsesCanonicalIdentity() {
        let fixture = makeFixture()
        let model = AppModel(database: fixture.database, storage: LocalDatabase(inMemory: true))
        model.selectProject(fixture.projectID)
        model.selectTask(fixture.firstTaskID)

        let staleSnapshot = model.task(withID: fixture.firstTaskID)!
        _ = model.filteredTasks()

        model.toggleTask(fixture.firstTaskID)
        #expect(model.task(withID: fixture.firstTaskID)?.status == .done)
        #expect(model.selectedTask?.status == .done)
        #expect(model.filteredTasks().first(where: { $0.id == fixture.firstTaskID })?.status == .done)

        // A retained row snapshot must not apply "open -> done" twice.
        model.toggleTask(staleSnapshot)
        #expect(model.task(withID: fixture.firstTaskID)?.status == .open)
        #expect(model.selectedTask?.status == .open)
        #expect(model.filteredTasks().first(where: { $0.id == fixture.firstTaskID })?.status == .open)
    }

    @Test("Cached task projections retain their SwiftUI invalidation dependency")
    func cachedTaskProjectionRemainsObservable() async {
        let fixture = makeFixture()
        let model = AppModel(database: fixture.database, storage: LocalDatabase(inMemory: true))
        model.selectProject(fixture.projectID)

        // Warm the ignored value cache before starting observation. This is
        // the exact path that previously dropped the taskRevision dependency.
        _ = model.filteredTasks()

        await confirmation { invalidated in
            withObservationTracking {
                _ = model.filteredTasks()
            } onChange: {
                invalidated()
            }

            model.addTask(title: "Visible immediately", projectID: fixture.projectID, status: .open)
        }

        #expect(model.filteredTasks().contains(where: { $0.title == "Visible immediately" }))
    }

    @Test("Project switching preserves the Gantt planning context")
    func projectSwitchingPreservesGanttMode() throws {
        let fixture = makeFixture()
        let secondProject = Project(
            workspaceID: fixture.database.workspaces[0].id,
            category: "测试分类",
            name: "第二个项目",
            colorHex: "#4D9DE0"
        )
        var database = fixture.database
        database.projects.append(secondProject)

        let model = AppModel(database: database, storage: LocalDatabase(inMemory: true))
        model.selectProject(fixture.projectID)
        model.selection.plannerView = .timeline

        model.selectProject(secondProject.id)
        #expect(model.selection.selectedProjectID == secondProject.id)
        #expect(model.selection.plannerView == .timeline)

        model.selectProject(nil)
        #expect(model.selection.plannerView == .list)
    }

    @Test("A timer records into the workspace where it started")
    func timerKeepsStartingWorkspaceAfterNavigation() throws {
        let fixture = makeFixture()
        let secondWorkspace = Workspace(name: "Second", symbolName: "square", colorHex: "#0A84FF")
        var database = fixture.database
        database.workspaces.append(secondWorkspace)
        database.workspaceOrder.append(secondWorkspace.id)
        let model = AppModel(database: database, storage: LocalDatabase(inMemory: true))
        let startedAt = Date(timeIntervalSinceReferenceDate: 900_000)

        model.startStopwatch(for: nil, at: startedAt)
        model.selectWorkspace(secondWorkspace.id)
        let entry = try #require(model.stopTimer(at: startedAt.addingTimeInterval(125)))

        #expect(entry.workspaceID == fixture.database.workspaces[0].id)
        #expect(entry.taskID == nil)
        #expect(entry.title == "无任务专注")
        #expect(entry.duration == 125)
    }

    @Test("A Pomodoro stays active past its target until the user stops it")
    func pomodoroContinuesIntoOvertime() throws {
        let fixture = makeFixture()
        let model = AppModel(database: fixture.database, storage: LocalDatabase(inMemory: true))
        let task = try #require(model.task(withID: fixture.firstTaskID))
        let startedAt = Date(timeIntervalSinceReferenceDate: 1_000_000)

        model.startPomodoro(for: task, duration: 25 * 60, at: startedAt)
        #expect(!model.pomodoroTargetReached(at: startedAt.addingTimeInterval(1_499)))
        #expect(model.pomodoroTargetReached(at: startedAt.addingTimeInterval(1_500)))
        #expect(model.completePomodoroIfNeeded(at: startedAt.addingTimeInterval(1_502)) == nil)
        #expect(model.activeTimer != nil)

        let entry = try #require(model.stopTimer(at: startedAt.addingTimeInterval(1_620)))
        #expect(entry.taskID == task.id)
        #expect(entry.startedAt == startedAt)
        #expect(entry.endedAt == startedAt.addingTimeInterval(1_620))
        #expect(entry.duration == 1_620)
        #expect(entry.activeSeconds == 1_620)
        #expect(model.activeTimer == nil)
    }

    @Test("Pausing a timer excludes the pause and preserves the session start")
    func pausedTimerRecordsOnlyActiveSegments() throws {
        let fixture = makeFixture()
        let model = AppModel(database: fixture.database, storage: LocalDatabase(inMemory: true))
        let startedAt = Date(timeIntervalSinceReferenceDate: 1_010_000)
        let pauseAt = startedAt.addingTimeInterval(600)
        let resumeAt = startedAt.addingTimeInterval(900)
        let endedAt = startedAt.addingTimeInterval(2_400)

        model.startStopwatch(for: nil, at: startedAt)
        model.pauseTimer(at: pauseAt)
        #expect(model.timerElapsed(at: endedAt) == 600)
        #expect(model.activeTimer?.sessionStartedAt == startedAt)
        #expect(model.activeTimer?.startedAt == startedAt)

        model.resumeTimer(at: resumeAt)
        #expect(model.timerElapsed(at: endedAt) == 2_100)
        let entry = try #require(model.stopTimer(at: endedAt))

        #expect(entry.startedAt == startedAt)
        #expect(entry.endedAt == endedAt)
        #expect(entry.duration == 2_100)
        #expect(entry.activeSeconds == 2_100)
    }

    @Test("Pomodoro duration rounds to minutes and stays within the supported range")
    func pomodoroDurationIsMinuteBasedAndBounded() throws {
        let fixture = makeFixture()
        let model = AppModel(database: fixture.database, storage: LocalDatabase(inMemory: true))
        let task = try #require(model.task(withID: fixture.firstTaskID))
        let startedAt = Date(timeIntervalSinceReferenceDate: 1_020_000)

        model.startPomodoro(for: task, duration: 32.4 * 60, at: startedAt)
        #expect(try #require(model.activeTimer?.targetSeconds) == 32 * 60)
        _ = model.stopTimer(at: startedAt)

        model.startPomodoro(for: task, duration: 0, at: startedAt)
        #expect(try #require(model.activeTimer?.targetSeconds) == 60)
        _ = model.stopTimer(at: startedAt)

        model.startPomodoro(for: task, duration: 240 * 60, at: startedAt)
        #expect(try #require(model.activeTimer?.targetSeconds) == 180 * 60)
    }

    @Test("Focus timeline includes only minute-precise plans")
    func focusTimelineRequiresMinutePrecision() throws {
        let fixture = makeFixture()
        var database = fixture.database
        let day = Date(timeIntervalSinceReferenceDate: 1_100_000)
        let dayStart = Calendar.current.startOfDay(for: day)
        database.tasks[0].plannedStart = dayStart.addingTimeInterval(10 * 3_600)
        database.tasks[0].plannedEnd = dayStart.addingTimeInterval(11 * 3_600)
        database.tasks[0].plannedPrecision = .minute
        database.tasks[1].plannedStart = dayStart
        database.tasks[1].plannedEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)
        database.tasks[1].plannedPrecision = .date
        let model = AppModel(database: database, storage: LocalDatabase(inMemory: true))

        let planned = model.focusPlannedTasks(
            on: day,
            workspaceID: fixture.database.workspaces[0].id
        )

        #expect(planned.map(\.id) == [database.tasks[0].id])
    }

    @Test("Linear focus timeline keeps both lanes on the same minute geometry")
    func linearFocusTimelineGeometrySnapsToMinutes() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(from: DateComponents(year: 2026, month: 8, day: 26))!
        let geometry = FocusLinearTimelineGeometry(day: day, contentWidth: 600, calendar: calendar)

        #expect(geometry.visibleDuration == 10 * 3_600)
        #expect(geometry.x(for: geometry.visibleStart) == 0)
        #expect(geometry.x(for: geometry.visibleEnd) == 600)

        let fourteen = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: day)!
        #expect(abs(geometry.x(for: fourteen) - 300) < 0.001)
        #expect(geometry.date(atX: 330) == calendar.date(bySettingHour: 14, minute: 30, second: 0, of: day)!)
        #expect(geometry.minuteDelta(for: 60) == 60 * 60)
    }

    @Test("Completing a parent completes every descendant")
    func completingParentCompletesDescendants() throws {
        let fixture = makeTaskHierarchyFixture()
        let model = AppModel(database: fixture.database, storage: LocalDatabase(inMemory: true))

        model.setTaskStatus(fixture.parentID, to: .done)

        for taskID in [fixture.parentID, fixture.childID, fixture.grandchildID, fixture.siblingID] {
            let task = try #require(model.task(withID: taskID))
            #expect(task.status == .done)
            #expect(task.completedAt != nil)
        }
        #expect(model.task(withID: fixture.unrelatedID)?.status == .open)
    }

    @Test("Reopening a completed parent reopens every descendant")
    func reopeningParentReopensDescendants() throws {
        let fixture = makeTaskHierarchyFixture()
        let model = AppModel(database: fixture.database, storage: LocalDatabase(inMemory: true))
        model.setTaskStatus(fixture.parentID, to: .done)

        model.setTaskStatus(fixture.parentID, to: .open)

        for taskID in [fixture.parentID, fixture.childID, fixture.grandchildID, fixture.siblingID] {
            let task = try #require(model.task(withID: taskID))
            #expect(task.status == .open)
            #expect(task.completedAt == nil)
        }
        #expect(model.task(withID: fixture.unrelatedID)?.status == .open)
    }

    @Test("Reopening a descendant reopens completed ancestors without changing sibling branches")
    func reopeningDescendantReopensOnlyItsAncestorChain() throws {
        let fixture = makeTaskHierarchyFixture()
        let model = AppModel(database: fixture.database, storage: LocalDatabase(inMemory: true))
        model.setTaskStatus(fixture.parentID, to: .done)

        model.setTaskStatus(fixture.grandchildID, to: .open)

        for taskID in [fixture.parentID, fixture.childID, fixture.grandchildID] {
            let task = try #require(model.task(withID: taskID))
            #expect(task.status == .open)
            #expect(task.completedAt == nil)
        }
        #expect(model.task(withID: fixture.siblingID)?.status == .done)
        #expect(model.task(withID: fixture.unrelatedID)?.status == .open)
    }

    @Test("Descendant progress includes every nested level and only counts completed tasks")
    func descendantProgressUsesAllNestedLevels() throws {
        let fixture = makeTaskHierarchyFixture()
        var database = fixture.database
        database.tasks[try #require(database.tasks.firstIndex { $0.id == fixture.childID })].status = .done
        database.tasks[try #require(database.tasks.firstIndex { $0.id == fixture.grandchildID })].status = .done
        let model = AppModel(database: database, storage: LocalDatabase(inMemory: true))
        let parent = try #require(model.task(withID: fixture.parentID))

        let descendants = model.descendants(of: parent)

        #expect(Set(descendants.map(\.id)) == [fixture.childID, fixture.grandchildID, fixture.siblingID])
        #expect(descendants.filter { $0.status == .done }.count == 2)
        #expect(!descendants.contains { $0.id == fixture.parentID || $0.id == fixture.unrelatedID })
    }

    @Test("Workspace manual order supports before, after-derived, and final positions")
    func workspaceOrderingSupportsEndPosition() {
        let first = Workspace(name: "First", symbolName: "1.circle", colorHex: "#111111")
        let second = Workspace(name: "Second", symbolName: "2.circle", colorHex: "#222222")
        let third = Workspace(name: "Third", symbolName: "3.circle", colorHex: "#333333")
        var database = GTDDatabase(
            workspaces: [first, second, third],
            workspaceOrder: [first.id, second.id, third.id]
        )

        #expect(WorkspaceReorderService.move(in: &database, workspaceID: first.id, before: nil))
        #expect(database.workspaceOrder == [second.id, third.id, first.id])
        #expect(!WorkspaceReorderService.move(in: &database, workspaceID: first.id, before: nil))

        #expect(WorkspaceReorderService.move(in: &database, workspaceID: third.id, before: second.id))
        #expect(database.workspaceOrder == [third.id, second.id, first.id])
    }

    @Test("First drag from a sorted workspace view becomes the visible manual order")
    func workspaceSortModeChangesWithoutASecondDrag() {
        let bravo = Workspace(name: "Bravo", symbolName: "b.circle", colorHex: "#111111")
        let alpha = Workspace(name: "Alpha", symbolName: "a.circle", colorHex: "#222222")
        let charlie = Workspace(name: "Charlie", symbolName: "c.circle", colorHex: "#333333")
        let database = GTDDatabase(
            workspaces: [bravo, alpha, charlie],
            workspaceOrder: [charlie.id, bravo.id, alpha.id],
            workspaceSortMode: .name
        )
        let model = AppModel(database: database, storage: LocalDatabase(inMemory: true))

        #expect(model.orderedWorkspaces.map(\.id) == [alpha.id, bravo.id, charlie.id])
        model.moveWorkspace(alpha.id, before: charlie.id)

        #expect(model.database.workspaceSortMode == .manual)
        #expect(model.database.workspaceOrder == [bravo.id, alpha.id, charlie.id])
    }

    @Test("Project category drag reorders categories without moving projects")
    func projectCategoryOrderingIsIndependentFromProjectMembership() throws {
        let workspace = Workspace(name: "Categories", symbolName: "folder", colorHex: "#0A84FF")
        let first = ProjectCategory(workspaceID: workspace.id, name: "First", order: 0)
        let second = ProjectCategory(workspaceID: workspace.id, name: "Second", order: 1)
        let third = ProjectCategory(workspaceID: workspace.id, name: "Third", order: 2)
        let firstProject = Project(workspaceID: workspace.id, category: first.name, name: "A", colorHex: "#0AA58F")
        let secondProject = Project(workspaceID: workspace.id, category: second.name, name: "B", colorHex: "#0AA58F")
        var database = GTDDatabase(
            workspaces: [workspace],
            workspaceOrder: [workspace.id],
            projects: [firstProject, secondProject],
            projectCategories: [first, second, third]
        )

        #expect(ProjectCategoryReorderService.move(
            in: &database,
            categoryID: third.id,
            workspaceID: workspace.id,
            beforeCategoryID: first.id
        ))

        let ordered = database.projectCategories
            .filter { $0.workspaceID == workspace.id }
            .sorted { $0.order < $1.order }
        #expect(ordered.map(\.id) == [third.id, first.id, second.id])
        #expect(database.projects.first(where: { $0.id == firstProject.id })?.category == first.name)
        #expect(database.projects.first(where: { $0.id == secondProject.id })?.category == second.name)
    }

    @Test("Legacy workspace shortcuts migrate to exactly one default")
    func workspaceShortcutMigrationKeepsOneValidDefault() {
        let first = Workspace(name: "First", symbolName: "1.circle", colorHex: "#111111")
        let second = Workspace(name: "Second", symbolName: "2.circle", colorHex: "#222222")
        let invalidID = UUID()
        let database = GTDDatabase(
            workspaces: [first, second],
            workspaceOrder: [second.id, first.id],
            pinnedWorkspaceIDs: [invalidID, first.id, second.id],
            workspaceShortcutsConfigured: true
        )

        let model = AppModel(database: database, storage: LocalDatabase(inMemory: true))

        #expect(model.database.pinnedWorkspaceIDs == [first.id])
        #expect(model.defaultWorkspaceID == first.id)
        #expect(model.selection.selectedWorkspaceID == first.id)
    }

    @Test("Changing workspaces and creating one do not replace the default")
    func runtimeWorkspaceChangesPreserveDefault() throws {
        let first = Workspace(name: "First", symbolName: "1.circle", colorHex: "#111111")
        let second = Workspace(name: "Second", symbolName: "2.circle", colorHex: "#222222")
        let database = GTDDatabase(
            workspaces: [first, second],
            workspaceOrder: [first.id, second.id],
            pinnedWorkspaceIDs: [first.id],
            workspaceShortcutsConfigured: true
        )
        let model = AppModel(database: database, storage: LocalDatabase(inMemory: true))

        model.selectWorkspace(second.id)
        let created = try #require(model.addWorkspace(name: "Third", symbolName: "star", colorHex: "#0A84FF"))

        #expect(model.defaultWorkspaceID == first.id)
        #expect(model.selection.selectedWorkspaceID == second.id)
        #expect(model.database.workspaceOrder.last == created.id)
    }

    @Test("The chosen default opens after relaunch")
    func defaultWorkspacePersistsAcrossRelaunch() {
        let first = Workspace(name: "First", symbolName: "1.circle", colorHex: "#111111")
        let second = Workspace(name: "Second", symbolName: "2.circle", colorHex: "#222222")
        let storage = LocalDatabase(inMemory: true)
        let database = GTDDatabase(
            workspaces: [first, second],
            workspaceOrder: [first.id, second.id],
            pinnedWorkspaceIDs: [first.id],
            workspaceShortcutsConfigured: true
        )
        let model = AppModel(database: database, storage: storage)

        model.setDefaultWorkspace(second.id)
        model.saveTask?.cancel()
        model.saveNow()
        let relaunched = AppModel(storage: storage)

        #expect(relaunched.defaultWorkspaceID == second.id)
        #expect(relaunched.selection.selectedWorkspaceID == second.id)
    }

    @Test("Deleting the default promotes the first remaining manual workspace")
    func deletingDefaultPromotesManualOrderWithoutChangingAnotherSelection() throws {
        let first = Workspace(name: "First", symbolName: "1.circle", colorHex: "#111111")
        let second = Workspace(name: "Second", symbolName: "2.circle", colorHex: "#222222")
        let third = Workspace(name: "Third", symbolName: "3.circle", colorHex: "#333333")
        let database = GTDDatabase(
            workspaces: [first, second, third],
            workspaceOrder: [first.id, third.id, second.id],
            pinnedWorkspaceIDs: [first.id],
            workspaceShortcutsConfigured: true
        )
        let model = AppModel(database: database, storage: LocalDatabase(inMemory: true))
        model.selectWorkspace(second.id)

        model.requestDeleteWorkspace(first)
        model.performDeletion(try #require(model.pendingDeletion))

        #expect(model.defaultWorkspaceID == third.id)
        #expect(model.selection.selectedWorkspaceID == second.id)
        #expect(!model.database.workspaces.contains(where: { $0.id == first.id }))
    }

    @Test("The last workspace cannot be deleted")
    func lastWorkspaceDeletionIsRejected() throws {
        let only = Workspace(name: "Only", symbolName: "square.grid.2x2", colorHex: "#0A84FF")
        let model = AppModel(
            database: GTDDatabase(workspaces: [only], workspaceOrder: [only.id], pinnedWorkspaceIDs: [only.id]),
            storage: LocalDatabase(inMemory: true)
        )

        model.requestDeleteWorkspace(only)
        model.performDeletion(try #require(model.pendingDeletion))

        #expect(model.database.workspaces.map(\.id) == [only.id])
        #expect(model.defaultWorkspaceID == only.id)
        #expect(model.notice == "至少需要保留一个工作区")
    }

    @Test("Task drag hit testing crosses sections and reaches empty section")
    func taskDragResolvesSectionTargets() {
        let fixture = makeFixture()
        let firstSection = fixture.database.projectSections[0]
        let secondSection = fixture.database.projectSections[1]
        let firstTask = fixture.database.tasks[0]
        let secondTask = fixture.database.tasks[1]
        let displays = [
            TaskSectionDisplay(id: firstSection.id.uuidString, section: firstSection, tasks: [firstTask]),
            TaskSectionDisplay(id: secondSection.id.uuidString, section: secondSection, tasks: [secondTask])
        ]
        let taskFrames = [
            firstTask.id: CGRect(x: 0, y: 30, width: 400, height: 34),
            secondTask.id: CGRect(x: 0, y: 110, width: 400, height: 34)
        ]
        let sectionFrames = [
            firstSection.id.uuidString: CGRect(x: 0, y: 0, width: 400, height: 28),
            secondSection.id.uuidString: CGRect(x: 0, y: 80, width: 400, height: 28)
        ]

        let beforeSecond = TaskDragCoordinator.resolveTarget(
            location: CGPoint(x: 80, y: 112),
            movingTaskID: firstTask.id,
            sourceSectionID: firstSection.id,
            sectionDisplays: displays,
            taskFrames: taskFrames,
            sectionFrames: sectionFrames
        )
        #expect(beforeSecond == TaskDropTarget(sectionID: secondSection.id, beforeTaskID: secondTask.id))

        let endOfSecond = TaskDragCoordinator.resolveTarget(
            location: CGPoint(x: 80, y: 170),
            movingTaskID: firstTask.id,
            sourceSectionID: firstSection.id,
            sectionDisplays: displays,
            taskFrames: taskFrames,
            sectionFrames: sectionFrames
        )
        #expect(endOfSecond == TaskDropTarget(sectionID: secondSection.id, beforeTaskID: nil))
    }

    @Test("Task drag selects an empty section before rows in a later section")
    func taskDragPrioritizesNearestSectionBeforeRows() {
        let fixture = makeFixture()
        let firstSection = fixture.database.projectSections[0]
        let secondSection = fixture.database.projectSections[1]
        var firstCompletedTask = fixture.database.tasks[0]
        var secondCompletedTask = fixture.database.tasks[1]
        firstCompletedTask.sectionID = secondSection.id
        firstCompletedTask.status = .done
        secondCompletedTask.status = .done

        let displays = [
            TaskSectionDisplay(id: firstSection.id.uuidString, section: firstSection, tasks: []),
            TaskSectionDisplay(
                id: secondSection.id.uuidString,
                section: secondSection,
                tasks: [firstCompletedTask, secondCompletedTask]
            )
        ]
        let taskFrames = [
            firstCompletedTask.id: CGRect(x: 0, y: 110, width: 400, height: 34),
            secondCompletedTask.id: CGRect(x: 0, y: 144, width: 400, height: 34)
        ]
        let sectionFrames = [
            firstSection.id.uuidString: CGRect(x: 0, y: 30, width: 400, height: 34),
            secondSection.id.uuidString: CGRect(x: 0, y: 80, width: 400, height: 28)
        ]

        let target = TaskDragCoordinator.resolveTarget(
            location: CGPoint(x: 80, y: 46),
            movingTaskID: secondCompletedTask.id,
            sourceSectionID: secondSection.id,
            sectionDisplays: displays,
            taskFrames: taskFrames,
            sectionFrames: sectionFrames
        )

        #expect(target == TaskDropTarget(sectionID: firstSection.id, beforeTaskID: nil))
    }

    @Test("Subtasks reorder among siblings and can be promoted to a root task")
    func subtaskOrderingAndPromotion() {
        let fixture = makeFixture()
        let parent = fixture.database.tasks[0]
        var database = fixture.database
        let firstChild = GTDTask(
            title: "First child",
            workspaceID: parent.workspaceID,
            projectID: parent.projectID,
            sectionID: parent.sectionID,
            parentID: parent.id,
            status: .open,
            order: 0
        )
        let secondChild = GTDTask(
            title: "Second child",
            workspaceID: parent.workspaceID,
            projectID: parent.projectID,
            sectionID: parent.sectionID,
            parentID: parent.id,
            status: .open,
            order: 1
        )
        database.tasks.append(contentsOf: [firstChild, secondChild])

        #expect(TaskReorderService.moveTask(
            in: &database,
            taskID: secondChild.id,
            workspaceID: parent.workspaceID,
            toSectionID: parent.sectionID,
            toParentID: parent.id,
            beforeTaskID: firstChild.id
        ))
        let reorderedChildren = database.tasks
            .filter { $0.parentID == parent.id }
            .sorted { $0.order < $1.order }
        #expect(reorderedChildren.map(\.id) == [secondChild.id, firstChild.id])

        #expect(TaskReorderService.moveTask(
            in: &database,
            taskID: secondChild.id,
            workspaceID: parent.workspaceID,
            toSectionID: parent.sectionID,
            toParentID: nil,
            beforeTaskID: parent.id
        ))
        #expect(database.tasks.first(where: { $0.id == secondChild.id })?.parentID == nil)
    }

    @Test("New C3 subtasks stay open and inherit the parent's actionable metadata")
    func newC3SubtasksStayOpenAndInheritParentMetadata() throws {
        let fixture = makeFixture()
        let model = AppModel(database: fixture.database, storage: LocalDatabase(inMemory: true))
        model.selectProject(fixture.projectID)

        var parent = try #require(model.task(withID: fixture.firstTaskID))
        parent.tags = ["健身", "力量"]
        parent.contexts = ["健身房"]
        parent.plannedStart = Date(timeIntervalSinceReferenceDate: 10_000)
        parent.plannedEnd = Date(timeIntervalSinceReferenceDate: 13_600)
        parent.plannedPrecision = .minute
        parent.deadline = Date(timeIntervalSinceReferenceDate: 20_000)
        parent.deadlinePrecision = .minute
        parent.priority = .high
        parent.status = .inbox
        model.updateTask(parent)

        model.addSubtask(title: "B", to: parent.id)
        model.addSubtask(title: "C", to: parent.id)

        let children = model.database.tasks
            .filter { $0.parentID == parent.id }
            .sorted { $0.order < $1.order }
        #expect(children.map(\.title) == ["C", "B"])

        let latestParent = try #require(model.task(withID: parent.id))
        for child in children {
            #expect(child.tags == latestParent.tags)
            #expect(child.contexts == latestParent.contexts)
            #expect(child.plannedStart == latestParent.plannedStart)
            #expect(child.plannedEnd == latestParent.plannedEnd)
            #expect(child.plannedPrecision == latestParent.plannedPrecision)
            #expect(child.status == .open)
            #expect(child.deadline == latestParent.deadline)
            #expect(child.deadlinePrecision == latestParent.deadlinePrecision)
            #expect(child.priority == latestParent.priority)
            #expect(child.completedAt == nil)
        }
        let inboxTaskIDs = Set(model.filteredTasks(for: .inbox, includeSearch: false).map(\.id))
        #expect(inboxTaskIDs.contains(parent.id))
        #expect(children.allSatisfy { !inboxTaskIDs.contains($0.id) })
    }

    @Test("Completed subtasks sort by the time completion was clicked")
    func completedSubtasksSortByCompletionTime() {
        let fixture = makeFixture()
        let parent = fixture.database.tasks[0]
        let olderCompletion = GTDTask(
            title: "Older completion",
            workspaceID: parent.workspaceID,
            projectID: parent.projectID,
            sectionID: parent.sectionID,
            parentID: parent.id,
            status: .done,
            completedAt: Date(timeIntervalSinceReferenceDate: 10_000),
            order: 0
        )
        let openChild = GTDTask(
            title: "Open child",
            workspaceID: parent.workspaceID,
            projectID: parent.projectID,
            sectionID: parent.sectionID,
            parentID: parent.id,
            status: .open,
            order: 1
        )
        let newerCompletion = GTDTask(
            title: "Newer completion",
            workspaceID: parent.workspaceID,
            projectID: parent.projectID,
            sectionID: parent.sectionID,
            parentID: parent.id,
            status: .done,
            completedAt: Date(timeIntervalSinceReferenceDate: 20_000),
            order: 2
        )

        let rows = TaskOutlineBuilder.rows(
            for: [parent, olderCompletion, openChild, newerCompletion],
            expandedTaskIDs: [parent.id]
        )

        #expect(rows.map(\.task.id) == [parent.id, openChild.id, newerCompletion.id, olderCompletion.id])
    }

    @Test("Unassigned project tasks display before user-created sections")
    func unassignedTasksDisplayFirst() {
        let fixture = makeFixture()
        let template = fixture.database.tasks[0]
        let unassigned = GTDTask(
            title: "Unassigned",
            workspaceID: template.workspaceID,
            projectID: template.projectID,
            sectionID: nil,
            status: .open
        )

        let displays = TaskSectionDisplayBuilder.displays(
            projectID: fixture.projectID,
            sections: fixture.database.projectSections,
            tasks: [unassigned] + fixture.database.tasks
        )

        #expect(displays.first?.section == nil)
        #expect(displays.first?.tasks.map(\.id) == [unassigned.id])
        #expect(displays.dropFirst().compactMap(\.section?.id) == fixture.database.projectSections.map(\.id))
    }

    @Test("Task canvas blank-area hit testing excludes rows, section headers, and editors")
    func taskCanvasBlankAreaHitTesting() {
        let taskID = UUID()
        let taskFrames = [taskID: CGRect(x: 10, y: 50, width: 300, height: 38)]
        let sectionFrames = ["section": CGRect(x: 10, y: 10, width: 300, height: 32)]
        let editorFrame = CGRect(x: 10, y: 96, width: 300, height: 36)

        for point in [CGPoint(x: 20, y: 20), CGPoint(x: 20, y: 60), CGPoint(x: 20, y: 110)] {
            #expect(TaskCanvasHitTest.containsInteractiveContent(
                at: point,
                taskFrames: taskFrames,
                sectionFrames: sectionFrames,
                inlineEditorFrame: editorFrame
            ))
        }
        #expect(!TaskCanvasHitTest.containsInteractiveContent(
            at: CGPoint(x: 20, y: 160),
            taskFrames: taskFrames,
            sectionFrames: sectionFrames,
            inlineEditorFrame: editorFrame
        ))
    }

    @Test("Project task search matches title, note, tags, and contexts")
    func projectTaskSearchMatchesTaskFields() {
        let fixture = makeFixture()
        var titleTask = fixture.database.tasks[0]
        titleTask.title = "整理发布清单"
        titleTask.tags = ["设计"]
        titleTask.contexts = ["Mac"]
        var noteTask = fixture.database.tasks[1]
        noteTask.note = "核对移动端交互"

        #expect(ProjectTaskSearch.filter([titleTask, noteTask], query: "发布 设计").map(\.id) == [titleTask.id])
        #expect(ProjectTaskSearch.filter([titleTask, noteTask], query: "mac").map(\.id) == [titleTask.id])
        #expect(ProjectTaskSearch.filter([titleTask, noteTask], query: "移动端").map(\.id) == [noteTask.id])
        #expect(ProjectTaskSearch.filter([titleTask, noteTask], query: "   ").map(\.id) == [titleTask.id, noteTask.id])
    }

    @Test("Section quick creation targets the chosen section and inserts at its top")
    func sectionQuickCreationTargetsSectionTop() {
        let fixture = makeFixture()
        let model = AppModel(database: fixture.database, storage: LocalDatabase(inMemory: true))
        model.selectProject(fixture.projectID)
        let sectionID = fixture.database.projectSections[0].id

        model.addTask(title: "First quick task", projectID: fixture.projectID, sectionID: sectionID, status: .open)
        model.addTask(title: "Latest quick task", projectID: fixture.projectID, sectionID: sectionID, status: .open)

        let sectionTasks = model.database.tasks
            .filter { $0.projectID == fixture.projectID && $0.sectionID == sectionID && $0.parentID == nil }
            .sorted { $0.order < $1.order }
        #expect(sectionTasks.prefix(2).map(\.title) == ["Latest quick task", "First quick task"])
    }

    @Test("Quick task properties remain independent and persist on creation")
    func quickTaskCreationPersistsConfiguredProperties() throws {
        let fixture = makeFixture()
        let model = AppModel(database: fixture.database, storage: LocalDatabase(inMemory: true))
        model.selectProject(fixture.projectID)

        let plannedStart = Date(timeIntervalSinceReferenceDate: 40_000)
        let plannedEnd = Date(timeIntervalSinceReferenceDate: 43_600)
        let deadline = Date(timeIntervalSinceReferenceDate: 80_000)
        model.addTask(
            title: "Configured quick task",
            projectID: fixture.projectID,
            status: .open,
            priority: .high,
            actionList: .somedayMaybe,
            plannedStart: plannedStart,
            plannedEnd: plannedEnd,
            plannedPrecision: .minute,
            deadline: deadline,
            deadlinePrecision: .date,
            tags: ["重要", "本周"]
        )

        let task = try #require(model.database.tasks.first { $0.title == "Configured quick task" })
        #expect(task.projectID == fixture.projectID)
        #expect(task.priority == .high)
        #expect(task.actionList == .somedayMaybe)
        #expect(task.plannedStart == plannedStart)
        #expect(task.plannedEnd == plannedEnd)
        #expect(task.plannedPrecision == .minute)
        #expect(task.deadline == deadline)
        #expect(task.deadlinePrecision == .date)
        #expect(task.tags == ["重要", "本周"])
    }

    @Test("Plan normalization is shared by quick creation and the inspector")
    func taskPlanNormalizationHandlesDateAndMinutePrecision() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let start = Date(timeIntervalSince1970: 1_787_616_000)
        let selectedEnd = try #require(calendar.date(byAdding: .day, value: 2, to: start))

        let datePlan = try #require(TaskDateNormalizer.normalizedPlan(
            start: start.addingTimeInterval(12 * 60 * 60),
            end: selectedEnd.addingTimeInterval(8 * 60 * 60),
            precision: .date,
            calendar: calendar
        ))
        let expectedStart = calendar.startOfDay(for: start)
        let expectedExclusiveEnd = try #require(calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: selectedEnd)))
        #expect(datePlan.start == expectedStart)
        #expect(datePlan.end == expectedExclusiveEnd.addingTimeInterval(-1))

        let datePoint = try #require(TaskDateNormalizer.normalizedPlan(
            start: start.addingTimeInterval(12 * 60 * 60),
            end: nil,
            precision: .date,
            calendar: calendar
        ))
        #expect(datePoint.start == expectedStart)
        #expect(datePoint.end == nil)

        let minutePoint = try #require(TaskDateNormalizer.normalizedPlan(
            start: start,
            end: nil,
            precision: .minute,
            calendar: calendar
        ))
        #expect(minutePoint.start == start)
        #expect(minutePoint.end == nil)

        #expect(TaskDateNormalizer.normalizedPlan(
            start: selectedEnd,
            end: start,
            precision: .date,
            calendar: calendar
        ) == nil)
        #expect(TaskDateNormalizer.normalizedPlan(
            start: start,
            end: start,
            precision: .minute,
            calendar: calendar
        ) == nil)
        #expect(TaskDateNormalizer.normalizedPlan(
            start: start,
            end: start.addingTimeInterval(60),
            precision: .minute,
            calendar: calendar
        )?.end == start.addingTimeInterval(60))
    }

    @Test("Date-only deadlines normalize to the end of day and shortcuts stay explicit")
    func taskDeadlineNormalizationAndShortcuts() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        calendar.firstWeekday = 2

        let now = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 24,
            hour: 10,
            minute: 30
        )))
        let nextDay = try #require(calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)))
        let expectedToday = nextDay.addingTimeInterval(-1)

        #expect(TaskDateNormalizer.normalizedDeadline(now, precision: .date, calendar: calendar) == expectedToday)
        #expect(TaskDateNormalizer.normalizedDeadline(now, precision: .minute, calendar: calendar) == now)
        #expect(TaskDateNormalizer.normalizedDeadline(now, precision: .none, calendar: calendar) == nil)

        #expect(TaskDateNormalizer.shortcutDeadline(.today, relativeTo: now, calendar: calendar) == expectedToday)
        #expect(TaskDateNormalizer.shortcutDeadline(.tomorrow, relativeTo: now, calendar: calendar) == nextDay.addingTimeInterval(86_400 - 1))

        let endOfWeek = try #require(calendar.dateInterval(of: .weekOfYear, for: now)).end.addingTimeInterval(-1)
        #expect(TaskDateNormalizer.shortcutDeadline(.thisWeekend, relativeTo: now, calendar: calendar) == endOfWeek)
    }

    @Test("Resetting a quick-task draft clears every staged property")
    func quickTaskDraftResetClearsStagedProperties() {
        var draft = ModernQuickTaskDraft()
        #expect(!draft.hasStagedContent)

        draft.title = "Draft"
        draft.hasPlan = true
        draft.hasPlannedEnd = true
        draft.hasDeadline = true
        draft.priority = .medium
        draft.actionList = .waiting
        draft.tags = ["草稿"]
        #expect(draft.hasStagedContent)

        draft.reset()

        #expect(!draft.hasStagedContent)
        #expect(draft.title.isEmpty)
        #expect(!draft.hasPlan)
        #expect(!draft.hasPlannedEnd)
        #expect(!draft.hasDeadline)
        #expect(draft.priority == .none)
        #expect(draft.actionList == .nextAction)
        #expect(draft.tags.isEmpty)
        #expect(draft.plannedPrecision == .date)
        #expect(draft.deadlinePrecision == .date)
    }

    @Test("Every quick-task property independently marks the draft as staged")
    func quickTaskDraftDetectsEachStagedProperty() {
        var draft = ModernQuickTaskDraft()

        draft.title = " "
        #expect(draft.hasStagedContent)
        draft.reset()

        draft.hasPlan = true
        #expect(draft.hasStagedContent)
        draft.reset()

        draft.hasPlannedEnd = true
        #expect(draft.hasStagedContent)
        draft.reset()

        draft.plannedPrecision = .minute
        #expect(draft.hasStagedContent)
        draft.reset()

        draft.hasDeadline = true
        #expect(draft.hasStagedContent)
        draft.reset()

        draft.deadlinePrecision = .minute
        #expect(draft.hasStagedContent)
        draft.reset()

        draft.priority = .high
        #expect(draft.hasStagedContent)
        draft.reset()

        draft.tags = ["草稿"]
        #expect(draft.hasStagedContent)
    }

    @Test("Moving a parent across sections carries descendants and rejects hierarchy cycles")
    func parentMoveCarriesDescendantsAndRejectsCycles() {
        let fixture = makeFixture()
        var database = fixture.database
        let movingParent = database.tasks[0]
        let newParent = database.tasks[1]
        let child = GTDTask(
            title: "Child",
            workspaceID: movingParent.workspaceID,
            projectID: movingParent.projectID,
            sectionID: movingParent.sectionID,
            parentID: movingParent.id,
            status: .open,
            order: 0
        )
        let grandchild = GTDTask(
            title: "Grandchild",
            workspaceID: movingParent.workspaceID,
            projectID: movingParent.projectID,
            sectionID: movingParent.sectionID,
            parentID: child.id,
            status: .open,
            order: 0
        )
        database.tasks.append(contentsOf: [child, grandchild])

        #expect(TaskReorderService.moveTask(
            in: &database,
            taskID: movingParent.id,
            workspaceID: movingParent.workspaceID,
            toSectionID: newParent.sectionID,
            toParentID: newParent.id
        ))
        #expect(database.tasks.first(where: { $0.id == movingParent.id })?.parentID == newParent.id)
        #expect(database.tasks.first(where: { $0.id == child.id })?.sectionID == newParent.sectionID)
        #expect(database.tasks.first(where: { $0.id == grandchild.id })?.sectionID == newParent.sectionID)

        #expect(!TaskReorderService.moveTask(
            in: &database,
            taskID: newParent.id,
            workspaceID: newParent.workspaceID,
            toSectionID: newParent.sectionID,
            toParentID: grandchild.id
        ))
        #expect(database.tasks.first(where: { $0.id == newParent.id })?.parentID == nil)
    }

    @Test("Task outline only reveals descendants of expanded parents")
    func taskOutlineExpansion() {
        let fixture = makeFixture()
        let parent = fixture.database.tasks[0]
        let child = GTDTask(
            title: "Child",
            workspaceID: parent.workspaceID,
            projectID: parent.projectID,
            sectionID: parent.sectionID,
            parentID: parent.id,
            status: .open,
            order: 0
        )
        let grandchild = GTDTask(
            title: "Grandchild",
            workspaceID: parent.workspaceID,
            projectID: parent.projectID,
            sectionID: parent.sectionID,
            parentID: child.id,
            status: .open,
            order: 0
        )
        let tasks = [parent, child, grandchild]

        #expect(TaskOutlineBuilder.rows(for: tasks, expandedTaskIDs: []).map(\.id) == [parent.id])
        let parentExpanded = TaskOutlineBuilder.rows(for: tasks, expandedTaskIDs: [parent.id])
        #expect(parentExpanded.map(\.id) == [parent.id, child.id])
        #expect(parentExpanded.map(\.depth) == [0, 1])
        let fullyExpanded = TaskOutlineBuilder.rows(for: tasks, expandedTaskIDs: [parent.id, child.id])
        #expect(fullyExpanded.map(\.id) == [parent.id, child.id, grandchild.id])
        #expect(fullyExpanded.map(\.depth) == [0, 1, 2])
    }

    @Test("C3 and C34 use the same completion-first hierarchy ordering")
    func taskAndGanttOrderingStayInSync() throws {
        let fixture = makeFixture()
        let template = fixture.database.tasks[0]
        let parent = GTDTask(
            title: "Parent",
            workspaceID: template.workspaceID,
            projectID: template.projectID,
            sectionID: template.sectionID,
            status: .open,
            order: 0
        )
        let orderAfter = GTDTask(
            title: "Order after",
            workspaceID: template.workspaceID,
            projectID: template.projectID,
            sectionID: template.sectionID,
            status: .open,
            plannedStart: Date(timeIntervalSinceReferenceDate: 50),
            order: 1
        )
        let plannedEarlier = GTDTask(
            title: "Planned earlier",
            workspaceID: template.workspaceID,
            projectID: template.projectID,
            sectionID: template.sectionID,
            status: .open,
            plannedStart: Date(timeIntervalSinceReferenceDate: 10),
            order: 2
        )
        let titleBeta = GTDTask(
            title: "Beta",
            workspaceID: template.workspaceID,
            projectID: template.projectID,
            sectionID: template.sectionID,
            status: .open,
            plannedStart: Date(timeIntervalSinceReferenceDate: 20),
            order: 3
        )
        let titleAlpha = GTDTask(
            title: "Alpha",
            workspaceID: template.workspaceID,
            projectID: template.projectID,
            sectionID: template.sectionID,
            status: .open,
            plannedStart: Date(timeIntervalSinceReferenceDate: 20),
            order: 3
        )
        let completedRoot = GTDTask(
            title: "Completed root",
            workspaceID: template.workspaceID,
            projectID: template.projectID,
            sectionID: template.sectionID,
            status: .done,
            completedAt: Date(timeIntervalSinceReferenceDate: 30),
            order: -100
        )
        let openChild = GTDTask(
            title: "Open child",
            workspaceID: template.workspaceID,
            projectID: template.projectID,
            sectionID: template.sectionID,
            parentID: parent.id,
            status: .open,
            order: 99
        )
        let completedChild = GTDTask(
            title: "Completed child",
            workspaceID: template.workspaceID,
            projectID: template.projectID,
            sectionID: template.sectionID,
            parentID: parent.id,
            status: .done,
            completedAt: Date(timeIntervalSinceReferenceDate: 40),
            order: -99
        )

        var database = fixture.database
        database.tasks = [
            completedRoot, titleBeta, completedChild, parent,
            orderAfter, openChild, plannedEarlier, titleAlpha
        ]
        let model = AppModel(database: database, storage: LocalDatabase(inMemory: true))
        model.selectProject(fixture.projectID)
        let visibleTasks = model.filteredTasks(includeSearch: false)

        let c3Rows = TaskOutlineBuilder.rows(
            for: visibleTasks,
            expandedTaskIDs: [parent.id]
        )
        let ganttRows = ModernGanttOutlineBuilder.rows(
            for: visibleTasks,
            collapsedTaskIDs: []
        )

        #expect(c3Rows.map(\.id) == ganttRows.map(\.id))
        #expect(c3Rows.filter { $0.depth == 0 }.map(\.id) == [
            parent.id, orderAfter.id, plannedEarlier.id,
            titleAlpha.id, titleBeta.id, completedRoot.id
        ])
        #expect(c3Rows.filter { $0.depth == 1 }.map(\.id) == [openChild.id, completedChild.id])
        #expect(c3Rows.last?.id == completedRoot.id)
    }

    @Test("Task row clicks keep selection, expansion, and renaming independent")
    func taskRowClickPolicyKeepsActionsIndependent() {
        #expect(TaskRowClickPolicy.resolve(
            intent: .primary,
            isSelected: false,
            hasChildren: true,
            isRenaming: false
        ) == .select)
        #expect(TaskRowClickPolicy.resolve(
            intent: .primary,
            isSelected: true,
            hasChildren: true,
            isRenaming: false
        ) == .scheduleExpansionToggle)
        #expect(TaskRowClickPolicy.resolve(
            intent: .primary,
            isSelected: true,
            hasChildren: false,
            isRenaming: false
        ) == .none)
        #expect(TaskRowClickPolicy.resolve(
            intent: .titleDoubleClick,
            isSelected: true,
            hasChildren: true,
            isRenaming: false
        ) == .beginRename)
        #expect(TaskRowClickPolicy.resolve(
            intent: .disclosure,
            isSelected: true,
            hasChildren: true,
            isRenaming: false
        ) == .toggleExpansionImmediately)
        #expect(TaskRowClickPolicy.resolve(
            intent: .primary,
            isSelected: true,
            hasChildren: true,
            isRenaming: true
        ) == .none)
    }

    @Test("A deliberate rightward drag reparents onto the pointed task")
    func taskDragIndentsIntoTarget() {
        let fixture = makeFixture()
        let firstSection = fixture.database.projectSections[0]
        let secondSection = fixture.database.projectSections[1]
        let movingTask = fixture.database.tasks[0]
        let targetParent = fixture.database.tasks[1]
        let displays = [
            TaskSectionDisplay(id: firstSection.id.uuidString, section: firstSection, tasks: [movingTask]),
            TaskSectionDisplay(id: secondSection.id.uuidString, section: secondSection, tasks: [targetParent])
        ]
        let target = TaskDragCoordinator.resolveTarget(
            location: CGPoint(x: 120, y: 112),
            movingTaskID: movingTask.id,
            sourceSectionID: firstSection.id,
            sectionDisplays: displays,
            taskFrames: [
                movingTask.id: CGRect(x: 0, y: 30, width: 400, height: 34),
                targetParent.id: CGRect(x: 0, y: 100, width: 400, height: 34)
            ],
            sectionFrames: [
                firstSection.id.uuidString: CGRect(x: 0, y: 0, width: 400, height: 28),
                secondSection.id.uuidString: CGRect(x: 0, y: 70, width: 400, height: 28)
            ],
            horizontalTranslation: 30,
            invalidParentIDs: [movingTask.id]
        )

        #expect(target == TaskDropTarget(sectionID: secondSection.id, parentID: targetParent.id))
    }

    @Test("A leftward drag can promote a child without requiring vertical movement")
    func taskDragPromotesChildInPlace() {
        let fixture = makeFixture()
        let section = fixture.database.projectSections[0]
        let parent = fixture.database.tasks[0]
        let child = GTDTask(
            title: "Child",
            workspaceID: parent.workspaceID,
            projectID: parent.projectID,
            sectionID: section.id,
            parentID: parent.id,
            status: .open,
            order: 0
        )
        let display = TaskSectionDisplay(id: section.id.uuidString, section: section, tasks: [parent, child])
        let target = TaskDragCoordinator.resolveTarget(
            location: CGPoint(x: 40, y: 82),
            movingTaskID: child.id,
            sourceSectionID: section.id,
            sectionDisplays: [display],
            taskFrames: [
                parent.id: CGRect(x: 0, y: 30, width: 400, height: 34),
                child.id: CGRect(x: 0, y: 65, width: 400, height: 34)
            ],
            sectionFrames: [section.id.uuidString: CGRect(x: 0, y: 0, width: 400, height: 28)],
            sourceParentID: parent.id,
            horizontalTranslation: -30,
            invalidParentIDs: [child.id]
        )

        #expect(target == TaskDropTarget(sectionID: section.id, parentID: nil, beforeTaskID: nil))
    }

    @Test("SwiftData round-trips task precision, tags, hierarchy, and time fields")
    func swiftDataRoundTripPreservesApprovedInspectorFields() throws {
        let fixture = makeFixture()
        var database = fixture.database
        var task = try #require(database.tasks.first(where: { $0.id == fixture.firstTaskID }))
        task.tags = ["设计", "UI", "macOS"]
        task.actionList = .waiting
        task.plannedStart = Date(timeIntervalSinceReferenceDate: 100_000)
        task.plannedEnd = Date(timeIntervalSinceReferenceDate: 103_600)
        task.plannedPrecision = .minute
        task.deadline = Date(timeIntervalSinceReferenceDate: 200_000)
        task.deadlinePrecision = .date
        task.recurrence = "FREQ=WEEKLY"
        database.tasks[database.tasks.firstIndex(where: { $0.id == task.id })!] = task

        let storage = LocalDatabase(inMemory: true)
        try storage.save(database)
        let loaded = storage.load()
        let restored = try #require(loaded.tasks.first(where: { $0.id == task.id }))

        #expect(restored.tags == task.tags)
        #expect(restored.actionList == .waiting)
        #expect(restored.plannedStart == task.plannedStart)
        #expect(restored.plannedEnd == task.plannedEnd)
        #expect(restored.plannedPrecision == .minute)
        #expect(restored.deadline == task.deadline)
        #expect(restored.deadlinePrecision == .date)
        #expect(restored.recurrence == "FREQ=WEEKLY")
    }

    @Test("Actual focus records support backfill, editing, deletion, and persistence")
    func actualFocusRecordLifecycleIsIndependentFromPlanning() throws {
        let fixture = makeFixture()
        let model = AppModel(database: fixture.database, storage: LocalDatabase(inMemory: true))
        let start = Date(timeIntervalSinceReferenceDate: 1_200_000)
        let end = start.addingTimeInterval(3_600)

        let added = try #require(model.addTimeEntry(
            workspaceID: fixture.database.workspaces[0].id,
            taskID: fixture.firstTaskID,
            startedAt: start,
            endedAt: end,
            note: "补录说明"
        ))
        #expect(added.duration == 3_600)
        #expect(model.task(withID: fixture.firstTaskID)?.plannedStart == nil)

        var edited = added
        edited.startedAt = start.addingTimeInterval(600)
        edited.endedAt = end.addingTimeInterval(600)
        edited.note = "已编辑"
        #expect(model.updateTimeEntry(edited))
        #expect(model.timeEntry(withID: added.id)?.startedAt == start.addingTimeInterval(600))
        #expect(model.timeEntry(withID: added.id)?.duration == 3_600)

        model.saveTask?.cancel()
        model.saveNow()
        let restored = try #require(model.storage.load().timeEntries.first(where: { $0.id == added.id }))
        #expect(restored.activeSeconds == 3_600)
        #expect(restored.note == "已编辑")

        #expect(model.deleteTimeEntry(withID: added.id))
        #expect(model.timeEntry(withID: added.id) == nil)
        #expect(model.activityLog.contains { $0.action == "补录实际专注" })
        #expect(model.activityLog.contains { $0.action == "编辑实际专注" })
        #expect(model.activityLog.contains { $0.action == "删除实际专注" })
    }

    @Test("Legacy actual focus entries fall back to their wall-clock duration")
    func legacyTimeEntryWithoutActiveSecondsRemainsReadable() throws {
        let fixture = makeFixture()
        let start = Date(timeIntervalSinceReferenceDate: 1_210_000)
        let entry = TimeEntry(
            workspaceID: fixture.database.workspaces[0].id,
            taskID: fixture.firstTaskID,
            title: "历史专注",
            startedAt: start,
            endedAt: start.addingTimeInterval(125),
            source: .stopwatch,
            pomodoroPhase: nil
        )
        let encoded = try JSONEncoder().encode(entry)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "activeSeconds")
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(TimeEntry.self, from: legacyData)

        #expect(decoded.activeSeconds == nil)
        #expect(decoded.duration == 125)
    }

    @Test("Legacy task JSON maps waiting status to the independent action list")
    func legacyTaskJSONMigratesActionList() throws {
        let fixture = makeFixture()
        var legacyTask = try #require(fixture.database.tasks.first)
        legacyTask.status = .waiting
        let encoded = try JSONEncoder().encode(legacyTask)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "actionList")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let restored = try JSONDecoder().decode(GTDTask.self, from: legacyData)
        #expect(restored.status == .waiting)
        #expect(restored.actionList == .waiting)
    }

    @Test("A planned point keeps its precision and missing end through creation and persistence")
    func plannedPointRoundTripsWithoutInventedDuration() throws {
        let fixture = makeFixture()
        let plannedStart = Date(timeIntervalSinceReferenceDate: 300_000)
        let model = AppModel(database: fixture.database, storage: LocalDatabase(inMemory: true))

        model.addTask(
            title: "Planned point",
            projectID: fixture.projectID,
            status: .open,
            plannedStart: plannedStart,
            plannedEnd: nil,
            plannedPrecision: .minute
        )

        let created = try #require(model.database.tasks.first(where: { $0.title == "Planned point" }))
        #expect(created.plannedStart == plannedStart)
        #expect(created.plannedEnd == nil)
        #expect(created.plannedPrecision == .minute)

        let storage = LocalDatabase(inMemory: true)
        try storage.save(model.database)
        let restored = try #require(storage.load().tasks.first(where: { $0.id == created.id }))
        #expect(restored.plannedStart == plannedStart)
        #expect(restored.plannedEnd == nil)
        #expect(restored.plannedPrecision == .minute)
    }

    @Test("Ordinary creation stays actionable whether or not it has a project")
    func ordinaryTaskCreationNeverEntersInbox() throws {
        let fixture = makeFixture()
        let model = AppModel(database: fixture.database, storage: LocalDatabase(inMemory: true))

        model.addTask(title: "Unassigned action", status: .open)
        model.addTask(title: "Project action", projectID: fixture.projectID, status: .open)

        let unassigned = try #require(model.database.tasks.first { $0.title == "Unassigned action" })
        let project = try #require(model.database.tasks.first { $0.title == "Project action" })
        #expect(unassigned.status == .open)
        #expect(project.status == .open)
        let inboxTaskIDs = Set(model.filteredTasks(for: .inbox, includeSearch: false).map(\.id))
        #expect(!inboxTaskIDs.contains(unassigned.id))
        #expect(!inboxTaskIDs.contains(project.id))
    }

    @Test("Inbox grouping separates recent, same-day, and earlier captures")
    func inboxTaskGroupingUsesCaptureTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        let workspaceID = UUID()
        var recent = GTDTask(title: "Recent", workspaceID: workspaceID, parentID: nil, status: .inbox)
        recent.createdAt = now.addingTimeInterval(-10 * 60)
        var today = GTDTask(title: "Today", workspaceID: workspaceID, parentID: nil, status: .inbox)
        today.createdAt = calendar.startOfDay(for: now).addingTimeInterval(60 * 60)
        var earlier = GTDTask(title: "Earlier", workspaceID: workspaceID, parentID: nil, status: .inbox)
        earlier.createdAt = calendar.date(byAdding: .day, value: -1, to: now)!

        let sections = InboxTaskGrouping.sections(
            for: [earlier, recent, today],
            now: now,
            calendar: calendar
        )

        #expect(sections.map(\.id) == [.recentlyCollected, .today, .earlier])
        #expect(sections.flatMap(\.tasks).map(\.id) == [recent.id, today.id, earlier.id])
    }

    @Test("Inbox clarification validates cascading ownership and preserves focus history")
    func inboxClarificationCommitsAtomicallyAcrossWorkspaces() throws {
        let sourceWorkspace = Workspace(name: "Source", symbolName: "tray", colorHex: "#0A84FF")
        let targetWorkspace = Workspace(name: "Target", symbolName: "briefcase", colorHex: "#0AA58F")
        let sourceProject = Project(
            workspaceID: sourceWorkspace.id,
            category: "Source",
            name: "Wrong workspace project",
            colorHex: "#64748B"
        )
        let targetProject = Project(
            workspaceID: targetWorkspace.id,
            category: "Target",
            name: "Target project",
            colorHex: "#2F6FD0"
        )
        let targetSection = ProjectSection(projectID: targetProject.id, name: "Next")
        let parent = GTDTask(
            title: "Clarify me",
            workspaceID: sourceWorkspace.id,
            projectID: nil,
            parentID: nil,
            status: .inbox
        )
        let child = GTDTask(
            title: "Child",
            workspaceID: sourceWorkspace.id,
            projectID: nil,
            parentID: parent.id,
            status: .inbox
        )
        let focusStart = Date(timeIntervalSinceReferenceDate: 500_000)
        let focusEntry = TimeEntry(
            workspaceID: sourceWorkspace.id,
            taskID: parent.id,
            title: parent.title,
            startedAt: focusStart,
            endedAt: focusStart.addingTimeInterval(600),
            source: .stopwatch,
            pomodoroPhase: nil
        )
        let database = GTDDatabase(
            workspaces: [sourceWorkspace, targetWorkspace],
            workspaceOrder: [sourceWorkspace.id, targetWorkspace.id],
            pinnedWorkspaceIDs: [sourceWorkspace.id],
            projects: [sourceProject, targetProject],
            projectSections: [targetSection],
            tasks: [parent, child],
            timeEntries: [focusEntry]
        )
        let model = AppModel(database: database, storage: LocalDatabase(inMemory: true))
        let baseClarification = InboxTaskClarification(
            workspaceID: targetWorkspace.id,
            projectID: sourceProject.id,
            sectionID: nil,
            actionList: .waiting,
            priority: .high,
            tags: ["review"],
            note: "Clarified note",
            plannedStart: nil,
            plannedEnd: nil,
            plannedPrecision: .none,
            deadline: nil,
            deadlinePrecision: .none
        )

        #expect(!model.clarifyInboxTask(parent.id, with: baseClarification))
        #expect(model.task(withID: parent.id) == parent)

        var valid = baseClarification
        valid.projectID = targetProject.id
        valid.sectionID = targetSection.id
        #expect(model.clarifyInboxTask(parent.id, with: valid))

        let clarifiedParent = try #require(model.task(withID: parent.id))
        let clarifiedChild = try #require(model.task(withID: child.id))
        #expect(clarifiedParent.workspaceID == targetWorkspace.id)
        #expect(clarifiedParent.projectID == targetProject.id)
        #expect(clarifiedParent.sectionID == targetSection.id)
        #expect(clarifiedParent.status == .open)
        #expect(clarifiedParent.actionList == .waiting)
        #expect(clarifiedParent.priority == .high)
        #expect(clarifiedParent.tags == ["review"])
        #expect(clarifiedParent.note == "Clarified note")
        #expect(clarifiedChild.workspaceID == targetWorkspace.id)
        #expect(clarifiedChild.projectID == targetProject.id)
        #expect(clarifiedChild.sectionID == targetSection.id)
        #expect(clarifiedChild.status == .open)
        #expect(model.database.timeEntries == [focusEntry])
    }

    @Test("Legacy task label strings migrate into workspace label entities")
    func legacyTaskTagsBackfillDefinitions() throws {
        let fixture = makeFixture()
        var database = fixture.database
        database.schemaVersion = 9
        database.tasks[0].tags = ["Design", "design", "  Review  "]

        let model = AppModel(database: database, storage: LocalDatabase(inMemory: true))
        let task = try #require(model.task(withID: fixture.firstTaskID))

        #expect(model.database.schemaVersion == 10)
        #expect(model.currentTagDefinitions.map(\.name) == ["Design", "Review"])
        #expect(task.tags == ["Design", "Review"])
        #expect(model.currentTagDefinitions.allSatisfy { $0.categoryID == nil })
    }

    @Test("Renaming and deleting a label updates assignments without deleting tasks")
    func tagRenameAndDeletePreserveTasks() throws {
        let fixture = makeFixture()
        let model = AppModel(database: fixture.database, storage: LocalDatabase(inMemory: true))
        model.addTagCategory(name: "阶段")
        let category = try #require(model.currentTagCategories.first)
        let definition = try #require(model.addTag(name: "设计", categoryID: category.id))
        var task = try #require(model.task(withID: fixture.firstTaskID))
        task.tags = [definition.name]
        model.updateTask(task)

        var renamed = try #require(model.tagDefinition(withID: definition.id))
        renamed.name = "界面"
        model.updateTagDefinition(renamed)
        #expect(model.task(withID: fixture.firstTaskID)?.tags == ["界面"])
        #expect(model.tasks(for: .tag(definition.id)).map(\.id) == [fixture.firstTaskID])

        model.requestDeleteTagCategory(category)
        model.performDeletion(try #require(model.pendingDeletion))
        #expect(model.tagDefinition(withID: definition.id)?.categoryID == nil)
        #expect(model.task(withID: fixture.firstTaskID) != nil)

        let currentDefinition = try #require(model.tagDefinition(withID: definition.id))
        model.requestDeleteTag(currentDefinition)
        model.performDeletion(try #require(model.pendingDeletion))
        #expect(model.task(withID: fixture.firstTaskID)?.tags.isEmpty == true)
        #expect(model.task(withID: fixture.firstTaskID) != nil)
        #expect(model.tagDefinition(withID: definition.id) == nil)
    }

    @Test("Merging labels rewrites and deduplicates task assignments")
    func tagMergeUsesTargetLabel() throws {
        let fixture = makeFixture()
        let model = AppModel(database: fixture.database, storage: LocalDatabase(inMemory: true))
        let source = try #require(model.addTag(name: "待确认"))
        let target = try #require(model.addTag(name: "等待"))
        var task = try #require(model.task(withID: fixture.firstTaskID))
        task.tags = [source.name, target.name]
        model.updateTask(task)

        #expect(model.mergeTag(source.id, into: target.id))
        #expect(model.tagDefinition(withID: source.id) == nil)
        #expect(model.task(withID: fixture.firstTaskID)?.tags == [target.name])
        #expect(model.selection.selectedTag == .tag(target.id))
    }

    @Test("Tag view creation remains open and persists label metadata")
    func tagTaskCreationAndMetadataPersist() throws {
        let fixture = makeFixture()
        let storage = LocalDatabase(inMemory: true)
        let model = AppModel(database: fixture.database, storage: storage)
        model.selectOrganization(.tags)
        let definition = try #require(model.addTag(name: "UI-03"))

        model.addTask(title: "Tag view task", status: .open, tags: [definition.name])
        let created = try #require(model.database.tasks.first { $0.title == "Tag view task" })
        #expect(created.status == .open)
        #expect(model.tasks(for: .tag(definition.id)).contains(where: { $0.id == created.id }))
        #expect(!model.filteredTasks(for: .inbox, includeSearch: false).contains(where: { $0.id == created.id }))

        try storage.save(model.database)
        let restored = storage.load()
        #expect(restored.tagDefinitions.contains(where: { $0.id == definition.id && $0.name == "UI-03" }))
        #expect(restored.tasks.first(where: { $0.id == created.id })?.tags == ["UI-03"])
    }

    private func makeFixture() -> (database: GTDDatabase, projectID: UUID, firstTaskID: UUID) {
        let workspace = Workspace(name: "Test", symbolName: "square.grid.2x2", colorHex: "#0A84FF")
        let project = Project(
            workspaceID: workspace.id,
            category: "Test",
            name: "Project",
            colorHex: "#0AA58F"
        )
        let firstSection = ProjectSection(projectID: project.id, name: "First", order: 0)
        let secondSection = ProjectSection(projectID: project.id, name: "Second", order: 1)
        let firstTask = GTDTask(
            title: "First task",
            workspaceID: workspace.id,
            projectID: project.id,
            sectionID: firstSection.id,
            parentID: nil,
            status: .open,
            order: 0
        )
        let secondTask = GTDTask(
            title: "Second task",
            workspaceID: workspace.id,
            projectID: project.id,
            sectionID: secondSection.id,
            parentID: nil,
            status: .open,
            order: 0
        )
        let database = GTDDatabase(
            workspaces: [workspace],
            workspaceOrder: [workspace.id],
            projects: [project],
            projectSections: [firstSection, secondSection],
            tasks: [firstTask, secondTask]
        )
        return (database, project.id, firstTask.id)
    }

    private func makeTaskHierarchyFixture() -> (
        database: GTDDatabase,
        parentID: UUID,
        childID: UUID,
        grandchildID: UUID,
        siblingID: UUID,
        unrelatedID: UUID
    ) {
        let base = makeFixture()
        var database = base.database
        let parent = database.tasks[0]
        let unrelated = database.tasks[1]
        let child = GTDTask(
            title: "Child",
            workspaceID: parent.workspaceID,
            projectID: parent.projectID,
            sectionID: parent.sectionID,
            parentID: parent.id,
            status: .open,
            order: 0
        )
        let grandchild = GTDTask(
            title: "Grandchild",
            workspaceID: parent.workspaceID,
            projectID: parent.projectID,
            sectionID: parent.sectionID,
            parentID: child.id,
            status: .waiting,
            order: 0
        )
        let sibling = GTDTask(
            title: "Sibling",
            workspaceID: parent.workspaceID,
            projectID: parent.projectID,
            sectionID: parent.sectionID,
            parentID: parent.id,
            status: .cancelled,
            order: 1
        )
        database.tasks.append(contentsOf: [child, grandchild, sibling])
        return (database, parent.id, child.id, grandchild.id, sibling.id, unrelated.id)
    }
}
