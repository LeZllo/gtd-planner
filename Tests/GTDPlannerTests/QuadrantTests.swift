import Foundation
import Testing
@testable import GTDPlanner

@MainActor
struct QuadrantTests {
    @Test("Every quadrant is present even in an empty workspace")
    func emptyWorkspace() {
        let fixture = Fixture()
        let snapshot = fixture.project([])
        #expect(snapshot.buckets.map(\.quadrant) == TaskQuadrant.allCases)
        #expect(snapshot.buckets.allSatisfy { $0.tasks.isEmpty })
        #expect(snapshot.totalCount == 0)
        #expect(snapshot.importantCount == 0)
        #expect(snapshot.urgentCount == 0)
    }

    @Test("High priority and local-today deadline independently define the two axes")
    func fourAxes() {
        let fixture = Fixture()
        let first = fixture.task("Important urgent", priority: .high, deadline: fixture.date(1))
        let second = fixture.task("Important later", priority: .high, deadline: fixture.date(3))
        let third = fixture.task("Medium urgent", priority: .medium, deadline: fixture.date(2, 23, 59))
        let fourth = fixture.task("Undated", priority: .none)
        let snapshot = fixture.project([fourth, third, second, first])
        #expect(snapshot.tasks(in: .importantUrgent).map(\.id) == [first.id])
        #expect(snapshot.tasks(in: .importantNotUrgent).map(\.id) == [second.id])
        #expect(snapshot.tasks(in: .notImportantUrgent).map(\.id) == [third.id])
        #expect(snapshot.tasks(in: .notImportantNotUrgent).map(\.id) == [fourth.id])
        #expect(snapshot.totalCount == 4)
        #expect(snapshot.importantCount == 2)
        #expect(snapshot.urgentCount == 2)
        #expect(Set(snapshot.tasks.map(\.id)).count == snapshot.totalCount)
    }

    @Test("Urgency includes all of today but excludes precisely tomorrow midnight")
    func midnightBoundary() {
        let fixture = Fixture()
        let deadlines = [fixture.date(1), fixture.date(2), fixture.date(3).addingTimeInterval(-0.001), fixture.date(3)]
        let expected: [TaskQuadrant] = [.notImportantUrgent, .notImportantUrgent, .notImportantUrgent, .notImportantNotUrgent]
        for (deadline, quadrant) in zip(deadlines, expected) {
            let task = fixture.task("Boundary", deadline: deadline)
            #expect(QuadrantProjection.quadrant(for: task, now: fixture.now, calendar: fixture.calendar) == quadrant)
        }
    }

    @Test("The same stored task automatically becomes urgent at local midnight")
    func midnightRollover() {
        let fixture = Fixture()
        let task = fixture.task("Tomorrow", priority: .high, deadline: fixture.date(3, 20))
        let model = fixture.model([task])
        let before = model.quadrantSnapshot(now: fixture.date(2, 23, 59), calendar: fixture.calendar)
        let after = model.quadrantSnapshot(now: fixture.date(3), calendar: fixture.calendar)
        #expect(before.tasks(in: .importantNotUrgent).map(\.id) == [task.id])
        #expect(after.tasks(in: .importantUrgent).map(\.id) == [task.id])
        #expect(model.task(withID: task.id) == task)
        #expect(before.day == fixture.date(2))
        #expect(after.day == fixture.date(3))
    }

    @Test("Urgency uses local natural days across both daylight-saving transitions")
    func daylightSavingBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        for (month, day, hours) in [(3, 8, 23), (11, 1, 25)] {
            let now = try #require(calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12)))
            let interval = try #require(calendar.dateInterval(of: .day, for: now))
            #expect(interval.duration == Double(hours * 3_600))
            var task = GTDTask(title: "DST boundary", workspaceID: UUID(), parentID: nil, status: .open)
            task.deadline = interval.end.addingTimeInterval(-1)
            #expect(QuadrantProjection.quadrant(for: task, now: now, calendar: calendar) == .notImportantUrgent)
            task.deadline = interval.end
            #expect(QuadrantProjection.quadrant(for: task, now: now, calendar: calendar) == .notImportantNotUrgent)
        }
    }

    @Test("Identical instants respect the selected calendar's time zone")
    func timeZoneBoundary() {
        let fixture = Fixture()
        let task = fixture.task("Late UTC", deadline: fixture.date(3, 4))
        var pacific = fixture.calendar
        pacific.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        #expect(QuadrantProjection.quadrant(for: task, now: fixture.now, calendar: fixture.calendar) == .notImportantNotUrgent)
        #expect(QuadrantProjection.quadrant(for: task, now: fixture.now, calendar: pacific) == .notImportantUrgent)
    }

    @Test("All unfinished lifecycle statuses are included, with finished and foreign tasks excluded")
    func workspaceAndStatus() {
        let fixture = Fixture()
        let activeStatuses: [TaskStatus] = [.inbox, .open, .inProgress, .waiting, .someday]
        let active = activeStatuses.map { status -> GTDTask in
            var task = fixture.task(status.title, priority: .low)
            task.status = status
            return task
        }
        var done = fixture.task("Done", priority: .high, deadline: fixture.date(1))
        done.status = .done
        var cancelled = fixture.task("Cancelled", priority: .high)
        cancelled.status = .cancelled
        var foreign = fixture.task("Foreign", priority: .high)
        foreign.workspaceID = UUID()
        let snapshot = fixture.project(active + [done, cancelled, foreign])
        #expect(Set(snapshot.tasks.map(\.id)) == Set(active.map(\.id)))
        #expect(snapshot.tasks(in: .notImportantNotUrgent).count == activeStatuses.count)
    }

    @Test("Plans, slots, action lists and missing deadline precision do not invent urgency")
    func schedulingIsIndependent() {
        let fixture = Fixture()
        var task = fixture.task("Planned now", priority: .medium)
        task.plannedStart = fixture.date(1)
        task.plannedEnd = fixture.date(4)
        task.plannedPrecision = .date
        task.executionSlots = [.init(start: fixture.date(2, 9), end: fixture.date(2, 10))]
        task.actionList = .nextAction
        #expect(QuadrantProjection.quadrant(for: task, now: fixture.now, calendar: fixture.calendar) == .notImportantNotUrgent)
        task.deadline = fixture.date(2)
        task.deadlinePrecision = .none // Legacy records still have a meaningful stored deadline.
        #expect(QuadrantProjection.quadrant(for: task, now: fixture.now, calendar: fixture.calendar) == .notImportantUrgent)
    }

    @Test("Completing today's daily instance does not remove an unfinished recurring task")
    func dailyInstanceRemains() {
        let fixture = Fixture()
        var daily = fixture.task("Daily", priority: .high)
        daily.recurrence = "FREQ=DAILY"
        daily.completedInstances = [TodayExecutionProjection.completionToken(for: fixture.now, calendar: fixture.calendar)]
        let snapshot = fixture.project([daily])
        #expect(snapshot.totalCount == 1)
        #expect(snapshot.tasks(in: .importantNotUrgent).map(\.id) == [daily.id])
    }

    @Test("Search includes notes, tags, contexts and the resolved project name")
    func searchCoverage() {
        let fixture = Fixture()
        var task = fixture.task("Review proposal")
        task.note = "Use the revised budget"
        task.tags = ["Deep Work"]
        task.contexts = ["Office"]
        for query in [" review ", "REVISED", "deep", "office", "launch", "\n  "] {
            #expect(QuadrantProjection.matchesSearch(task, query: query, projectName: "Launch"))
        }
        #expect(!QuadrantProjection.matchesSearch(task, query: "unrelated", projectName: "Launch"))
    }

    @Test("Each bucket puts earlier deadlines first and orders ties deterministically")
    func deadlineOrdering() {
        let fixture = Fixture()
        var noDeadline = fixture.task("No deadline", priority: .high)
        noDeadline.order = -100
        let later = fixture.task("Later", priority: .high, deadline: fixture.date(5))
        let earlier = fixture.task("Earlier", priority: .high, deadline: fixture.date(4))
        let tasks = [noDeadline, later, earlier]
        let forward = fixture.project(tasks)
        let reverse = fixture.project(Array(tasks.reversed()))
        #expect(forward == reverse)
        #expect(forward.tasks(in: .importantNotUrgent).map(\.id) == [earlier.id, later.id, noDeadline.id])
    }

    @Test("New-task defaults land in the chosen quadrant without creating plans or slots")
    func creationDefaults() throws {
        let fixture = Fixture()
        let model = fixture.model([])
        for quadrant in TaskQuadrant.allCases {
            let defaults = QuadrantTaskDefaults(quadrant: quadrant, now: fixture.now, calendar: fixture.calendar)
            model.addTask(title: quadrant.rawValue, status: .open, priority: defaults.priority,
                          deadline: defaults.deadline, deadlinePrecision: defaults.deadlinePrecision)
            let created = try #require(model.database.tasks.first { $0.title == quadrant.rawValue })
            #expect(QuadrantProjection.quadrant(for: created, now: fixture.now, calendar: fixture.calendar) == quadrant)
            #expect(created.plannedStart == nil)
            #expect(created.plannedEnd == nil)
            #expect(created.executionSlots.isEmpty)
            #expect(created.deadline == (quadrant.isUrgent ? fixture.date(3).addingTimeInterval(-1) : nil))
        }
    }

    @Test("An explicit priority change preserves every other task field")
    func priorityMutationIsNarrow() {
        let fixture = Fixture()
        let task = fixture.scheduledTask()
        var expected = task
        expected.priority = .high
        let updated = QuadrantTaskAction.setPriority(.high).applying(to: task, calendar: fixture.calendar)
        #expect(updated == expected)
        #expect(QuadrantTaskAction.setPriority(task.priority).applying(to: task, calendar: fixture.calendar) == task)
    }

    @Test("An explicit deadline edit or clear preserves priority, plans, slots and all other fields")
    func deadlineMutationIsNarrow() {
        let fixture = Fixture()
        let task = fixture.scheduledTask()
        var expected = task
        expected.deadline = fixture.date(3).addingTimeInterval(-1)
        expected.deadlinePrecision = .date
        #expect(QuadrantTaskAction.setDeadline(fixture.now, precision: .date).applying(to: task, calendar: fixture.calendar) == expected)
        expected.deadline = fixture.date(4, 17, 30)
        expected.deadlinePrecision = .minute
        #expect(QuadrantTaskAction.setDeadline(expected.deadline!, precision: .minute).applying(to: task, calendar: fixture.calendar) == expected)
        expected.deadline = nil
        expected.deadlinePrecision = .none
        #expect(QuadrantTaskAction.clearDeadline.applying(to: task, calendar: fixture.calendar) == expected)
    }

    @Test("Mutation guards reject stale, foreign and finished tasks without saving no-ops")
    func actionGuards() {
        let fixture = Fixture()
        let task = fixture.task("Current")
        var foreign = fixture.task("Foreign")
        foreign.workspaceID = UUID()
        var done = fixture.task("Done")
        done.status = .done
        let model = fixture.model([task, foreign, done])
        let revision = model.taskRevision
        #expect(!model.applyQuadrantAction(.setPriority(.none), taskID: task.id))
        #expect(!model.applyQuadrantAction(.clearDeadline, taskID: task.id))
        #expect(!model.applyQuadrantAction(.setPriority(.high), taskID: foreign.id))
        #expect(!model.applyQuadrantAction(.setPriority(.high), taskID: done.id))
        #expect(!model.applyQuadrantAction(.setPriority(.high), taskID: UUID()))
        #expect(model.taskRevision == revision)
        #expect(model.applyQuadrantAction(.setPriority(.high), taskID: task.id))
        #expect(model.task(withID: task.id)?.priority == .high)
        #expect(model.quadrantSnapshot(now: fixture.now, calendar: fixture.calendar).importantCount == 1)
    }

    @Test("Completion is idempotent, workspace-scoped and preserves task dates and slots")
    func completionGuardsAndPreservation() throws {
        let fixture = Fixture()
        let task = fixture.scheduledTask()
        var child = fixture.task("Child")
        child.parentID = task.id
        var foreign = fixture.task("Foreign")
        foreign.workspaceID = UUID()
        var cancelled = fixture.task("Cancelled")
        cancelled.status = .cancelled
        let model = fixture.model([task, child, foreign, cancelled])
        #expect(!model.completeQuadrantTask(taskID: foreign.id))
        #expect(!model.completeQuadrantTask(taskID: cancelled.id))
        #expect(!model.completeQuadrantTask(taskID: UUID()))
        #expect(model.completeQuadrantTask(taskID: task.id))
        let revision = model.taskRevision
        #expect(!model.completeQuadrantTask(taskID: task.id))
        #expect(model.taskRevision == revision)
        let updated = try #require(model.task(withID: task.id))
        #expect(updated.status == .done)
        #expect(model.task(withID: child.id)?.status == .done)
        #expect(updated.plannedStart == task.plannedStart)
        #expect(updated.plannedEnd == task.plannedEnd)
        #expect(updated.plannedPrecision == task.plannedPrecision)
        #expect(updated.deadline == task.deadline)
        #expect(updated.deadlinePrecision == task.deadlinePrecision)
        #expect(updated.executionSlots == task.executionSlots)
        #expect(model.quadrantSnapshot(now: fixture.now, calendar: fixture.calendar).totalCount == 0)
    }

    @Test("Explicit whole-task completion ends recurrence without fabricating occurrence completions")
    func recurringWholeTaskCompletion() throws {
        let fixture = Fixture()
        var task = fixture.task("Daily")
        task.recurrence = "FREQ=DAILY"
        task.completedInstances = ["2026-10-01"]
        let model = fixture.model([task])
        #expect(model.completeQuadrantTask(taskID: task.id))
        let updated = try #require(model.task(withID: task.id))
        #expect(updated.status == .done)
        #expect(updated.completedInstances == task.completedInstances)
        #expect(updated.skippedInstances == task.skippedInstances)
        #expect(updated.recurrence == task.recurrence)
        #expect(model.quadrantSnapshot(now: fixture.now, calendar: fixture.calendar).tasks.isEmpty)
    }

    @Test("Arranging a concrete day leaves the task in its existing quadrant and retains its plan and deadline")
    func schedulingDoesNotMoveQuadrants() throws {
        let fixture = Fixture()
        let task = fixture.scheduledTask()
        let model = fixture.model([task])
        let before = QuadrantProjection.quadrant(for: task, now: fixture.now, calendar: fixture.calendar)
        #expect(model.addExecutionSlot(taskID: task.id, start: fixture.date(5, 9), end: fixture.date(5, 10), calendar: fixture.calendar) != nil)
        let updated = try #require(model.task(withID: task.id))
        #expect(QuadrantProjection.quadrant(for: updated, now: fixture.now, calendar: fixture.calendar) == before)
        #expect(updated.priority == task.priority)
        #expect(updated.plannedStart == task.plannedStart)
        #expect(updated.plannedEnd == task.plannedEnd)
        #expect(updated.deadline == task.deadline)
        #expect(updated.executionSlots.count == task.executionSlots.count + 1)
    }

    private struct Fixture {
        let workspace = Workspace(name: "Quadrants", symbolName: "square.grid.2x2", colorHex: "#0A84FF")
        let calendar: Calendar = {
            var value = Calendar(identifier: .gregorian)
            value.timeZone = TimeZone(secondsFromGMT: 0)!
            return value
        }()
        var now: Date { date(2, 12) }

        func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
        }

        func task(_ title: String, priority: Priority = .none, deadline: Date? = nil) -> GTDTask {
            GTDTask(title: title, workspaceID: workspace.id, parentID: nil, status: .open,
                    priority: priority, deadline: deadline, deadlinePrecision: deadline == nil ? .none : .minute)
        }

        func scheduledTask() -> GTDTask {
            var task = task("Scheduled", priority: .medium, deadline: date(6, 18))
            task.plannedStart = date(2)
            task.plannedEnd = date(6)
            task.plannedPrecision = .date
            task.planRangeIntent = .completeWithin
            task.executionSlots = [.init(start: date(3, 9), end: date(3, 10))]
            task.tags = ["Work"]
            task.note = "Preserve this note"
            return task
        }

        func project(_ tasks: [GTDTask]) -> QuadrantSnapshot {
            QuadrantProjection.make(tasks: tasks, workspaceID: workspace.id, now: now, calendar: calendar)
        }

        @MainActor
        func model(_ tasks: [GTDTask]) -> AppModel {
            AppModel(database: GTDDatabase(workspaces: [workspace], workspaceOrder: [workspace.id],
                                          pinnedWorkspaceIDs: [workspace.id], tasks: tasks),
                     storage: LocalDatabase(inMemory: true))
        }
    }
}
