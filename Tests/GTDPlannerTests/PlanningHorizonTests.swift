import Foundation
import Testing
@testable import GTDPlanner

@MainActor
struct PlanningHorizonTests {
    @Test("Future horizons start tomorrow and include exactly seven natural days")
    func horizonBoundaries() {
        let calendar = calendar()
        let now = date(2026, 12, 29, 23, 59, calendar: calendar)
        let days = PlanningHorizon.nextSevenDays.days(relativeTo: now, calendar: calendar)
        #expect(days.count == 7)
        #expect(days.first == date(2026, 12, 30, calendar: calendar))
        #expect(days.last == date(2027, 1, 5, calendar: calendar))
        #expect(PlanningHorizon.tomorrow.days(relativeTo: now, calendar: calendar) == [days[0]])
        #expect(!days.contains(calendar.startOfDay(for: now)))
    }

    @Test("Future windows preserve local midnight across spring and fall daylight saving")
    func daylightSavingDays() throws {
        let calendar = calendar("America/Los_Angeles")
        for (month, day, expectedHours) in [(3, 8, 23), (11, 1, 25)] {
            let now = try #require(calendar.date(byAdding: .day, value: -1, to: date(2026, month, day, 12, calendar: calendar)))
            let days = PlanningHorizon.nextSevenDays.days(relativeTo: now, calendar: calendar)
            let interval = try #require(calendar.dateInterval(of: .day, for: days[0]))
            #expect(days.count == 7)
            #expect(interval.duration == Double(expectedHours * 3_600))
            #expect(days[1] == interval.end)
            #expect(days.allSatisfy { calendar.component(.hour, from: $0) == 0 })
            #expect(calendar.dateComponents([.day], from: days[0], to: days[6]).day == 6)
        }
    }

    @Test("Schedule dragging uses local clock time and natural midnight on both daylight-saving transitions")
    func daylightSavingDragSelection() throws {
        let calendar = calendar("America/New_York")
        for (month, day) in [(3, 8), (11, 1)] {
            let target = date(2026, month, day, calendar: calendar)
            let morning = TodayScheduleDragRules.selection(
                lane: .plan, day: target, startY: 3 * 64, currentY: 4 * 64,
                startHour: 6, endHour: 24, hourHeight: 64, fineSnap: false, calendar: calendar
            )
            #expect(morning.start == date(2026, month, day, 9, calendar: calendar))
            #expect(morning.end == date(2026, month, day, 10, calendar: calendar))
            let late = TodayScheduleDragRules.selection(
                lane: .plan, day: target, startY: 17.75 * 64, currentY: 18 * 64,
                startHour: 6, endHour: 24, hourHeight: 64, fineSnap: false, calendar: calendar
            )
            let interval = try #require(calendar.dateInterval(of: .day, for: target))
            #expect(late.start == date(2026, month, day, 23, 45, calendar: calendar))
            #expect(late.end == interval.end)
            #expect(late.duration == 15 * 60)
        }
    }

    @Test("Tomorrow includes ranges, slots, deadlines and daily tasks but not overdue-only backlog")
    func tomorrowMembership() {
        let fixture = Fixture()
        var range = fixture.task("Range")
        range.plannedStart = fixture.date(1)
        range.plannedEnd = fixture.date(5)
        range.plannedPrecision = .date
        var slot = fixture.task("Slot")
        slot.executionSlots = [.init(start: fixture.date(3, 10), end: fixture.date(3, 11))]
        var due = fixture.task("Due")
        due.deadline = fixture.date(3, 18)
        var daily = fixture.task("Daily")
        daily.recurrence = "FREQ=DAILY"
        var overdue = fixture.task("Overdue")
        overdue.deadline = fixture.date(1, 18)
        var today = fixture.task("Today")
        today.plannedStart = fixture.date(2, 10)
        var cancelled = due
        cancelled.id = UUID()
        cancelled.status = .cancelled
        var foreign = due
        foreign.id = UUID()
        foreign.workspaceID = UUID()
        let tasks = [range, slot, due, daily, overdue, today, cancelled, foreign]
        let snapshot = fixture.project(tasks, horizon: .tomorrow)
        #expect(Set(snapshot.tasks.map(\.id)) == Set([range.id, slot.id, due.id, daily.id]))
        #expect(snapshot.remainingCount == 4)
        #expect(snapshot.days[0].overdueCount == 0)
        #expect(TodayExecutionProjection.isRelevant(overdue, on: fixture.now, now: fixture.now, calendar: fixture.calendar))
        #expect(!TodayExecutionProjection.isRelevant(overdue, on: fixture.date(3), now: fixture.now, calendar: fixture.calendar))
    }

    @Test("The seventh future day is included and today and the eighth day are excluded")
    func sevenDayMembership() {
        let fixture = Fixture()
        var today = fixture.task("Today")
        today.plannedStart = fixture.date(2, 16)
        var seventh = fixture.task("Seventh")
        seventh.deadline = fixture.date(9, 23, 59)
        var eighth = fixture.task("Eighth")
        eighth.deadline = fixture.date(10)
        let snapshot = fixture.project([today, seventh, eighth])
        #expect(snapshot.tasks.map(\.id) == [seventh.id])
        #expect(snapshot.days.count == 7)
        #expect(snapshot.days.last?.tasks.map(\.id) == [seventh.id])
    }

    @Test("Ranges, slots and deadlines use a half-open midnight boundary")
    func halfOpenMidnight() throws {
        let fixture = Fixture()
        var range = fixture.task("Range to midnight")
        range.plannedStart = fixture.date(2, 23)
        range.plannedEnd = fixture.date(3)
        range.plannedPrecision = .minute
        var slot = fixture.task("Slot to midnight")
        slot.executionSlots = [.init(start: fixture.date(2, 23), end: fixture.date(3))]
        var deadline = fixture.task("Midnight deadline")
        deadline.deadline = fixture.date(3)
        var point = fixture.task("Midnight point")
        point.plannedStart = fixture.date(3)
        point.plannedPrecision = .minute
        let tasks = [range, slot, deadline, point]
        let today = fixture.day(tasks, on: fixture.date(2))
        let tomorrow = fixture.day(tasks, on: fixture.date(3))
        #expect(Set(today.tasks.map(\.id)) == Set([range.id, slot.id]))
        #expect(Set(tomorrow.tasks.map(\.id)) == Set([deadline.id, point.id]))
        #expect(today.deadlineTasks.isEmpty)
        #expect(tomorrow.deadlineTasks.map(\.id) == [deadline.id])
        #expect(!TodayExecutionProjection.isMultiDayPlan(range, calendar: fixture.calendar))
        let block = try #require(today.planBlocks.first(where: { $0.taskID == range.id }))
        #expect(block.end == fixture.date(3))
        #expect(block.plannedDuration == 3_600)
    }

    @Test("Date-only ranges include their selected last day without leaking into the next")
    func dateOnlyRangeBoundaries() throws {
        let fixture = Fixture()
        let plan = try #require(TaskDateNormalizer.normalizedPlan(
            start: fixture.date(2), end: fixture.date(4), precision: .date, calendar: fixture.calendar
        ))
        var task = fixture.task("Three days")
        task.plannedStart = plan.start
        task.plannedEnd = plan.end
        task.plannedPrecision = .date
        task.planRangeIntent = .completeWithin
        #expect(fixture.day([task], on: fixture.date(4)).completeWithinTasks.map(\.id) == [task.id])
        #expect(fixture.day([task], on: fixture.date(5)).tasks.isEmpty)
        #expect(fixture.day([task], on: fixture.date(3)).planBlocks.isEmpty)
    }

    @Test("Cross-midnight slots are clipped separately on each day without double counting")
    func crossMidnightSlots() {
        let fixture = Fixture()
        var task = fixture.task("Night slot")
        task.executionSlots = [.init(start: fixture.date(3, 23, 30), end: fixture.date(4, 1))]
        let snapshot = fixture.project([task])
        #expect(snapshot.totalCount == 1)
        #expect(snapshot.occurrenceCount == 2)
        #expect(snapshot.days[0].planBlocks[0].start == fixture.date(3, 23, 30))
        #expect(snapshot.days[0].planBlocks[0].end == fixture.date(4))
        #expect(snapshot.days[1].planBlocks[0].start == fixture.date(4))
        #expect(snapshot.days[1].planBlocks[0].end == fixture.date(4, 1))
        #expect(snapshot.plannedDuration == 90 * 60)
    }

    @Test("Daily completion applies to one instance and counts distinguish tasks from occurrences")
    func dailyCompletionsAndUniqueCounts() {
        let fixture = Fixture()
        var daily = fixture.task("Daily")
        daily.recurrence = " rrule:freq=daily ; "
        daily.completedInstances = [TodayExecutionProjection.completionToken(for: fixture.date(3), calendar: fixture.calendar)]
        var range = fixture.task("Range")
        range.plannedStart = fixture.date(2)
        range.plannedEnd = fixture.date(10)
        range.plannedPrecision = .date
        let snapshot = fixture.project([daily, range])
        #expect(snapshot.totalCount == 2)
        #expect(snapshot.remainingCount == 2)
        #expect(snapshot.completedCount == 0)
        #expect(snapshot.occurrenceCount == 14)
        #expect(snapshot.completedOccurrenceCount == 1)
        #expect(snapshot.days[0].completedTasks.map(\.id) == [daily.id])
        #expect(snapshot.days[1].completedTasks.isEmpty)
        #expect(!snapshot.planningCandidates(on: fixture.date(3), calendar: fixture.calendar).contains { $0.id == daily.id })
        #expect(snapshot.planningCandidates(on: fixture.date(4), calendar: fixture.calendar).contains { $0.id == daily.id })
        #expect(!PlanningHorizon.tomorrow.containsUnfinishedTask(daily, relativeTo: fixture.now, calendar: fixture.calendar))
        #expect(PlanningHorizon.nextSevenDays.containsUnfinishedTask(daily, relativeTo: fixture.now, calendar: fixture.calendar))
    }

    @Test("Daily start dates and skipped instances constrain projections and scheduling candidates")
    func dailyStartAndSkippedDates() {
        let fixture = Fixture()
        var daily = fixture.task("Starts later")
        daily.recurrence = "FREQ=DAILY"
        daily.plannedStart = fixture.date(4)
        daily.plannedPrecision = .date
        daily.skippedInstances = [TodayExecutionProjection.completionToken(for: fixture.date(5), calendar: fixture.calendar)]
        let snapshot = fixture.project([daily])
        #expect(snapshot.days[0].tasks.isEmpty)
        #expect(snapshot.days[1].tasks.map(\.id) == [daily.id])
        #expect(snapshot.days[2].tasks.isEmpty)
        #expect(snapshot.days[3].tasks.map(\.id) == [daily.id])
        #expect(snapshot.planningCandidates(on: fixture.date(3), calendar: fixture.calendar).isEmpty)
        #expect(snapshot.planningCandidates(on: fixture.date(5), calendar: fixture.calendar).isEmpty)
    }

    @Test("Daily minute templates retain local clock time across daylight saving")
    func dailyMinuteTemplate() throws {
        let calendar = calendar("America/Los_Angeles")
        let workspace = Workspace(name: "DST", symbolName: "calendar", colorHex: "#0A84FF")
        var task = GTDTask(title: "Daily hour", workspaceID: workspace.id, parentID: nil, status: .open)
        task.recurrence = "FREQ=DAILY"
        task.plannedStart = date(2026, 3, 7, 9, calendar: calendar)
        task.plannedEnd = date(2026, 3, 7, 10, calendar: calendar)
        task.plannedPrecision = .minute
        let snapshot = PlanningHorizonProjection.make(
            tasks: [task], timeEntries: [], horizon: .nextSevenDays, workspaceID: workspace.id,
            now: date(2026, 3, 7, 12, calendar: calendar), calendar: calendar
        )
        #expect(snapshot.days.count == 7)
        for day in snapshot.days {
            let block = try #require(day.planBlocks.first)
            #expect(calendar.component(.hour, from: block.start) == 9)
            #expect(calendar.component(.hour, from: block.end) == 10)
            #expect(calendar.isDate(block.start, inSameDayAs: day.day))
        }
        #expect(snapshot.plannedDuration == 7 * 3_600)
    }

    @Test("A daily template in a missing spring-forward hour shifts forward without losing its duration")
    func dailyTemplateInMissingHour() throws {
        let calendar = calendar("America/New_York")
        let workspace = Workspace(name: "DST", symbolName: "calendar", colorHex: "#0A84FF")
        var task = GTDTask(title: "Gap", workspaceID: workspace.id, parentID: nil, status: .open)
        task.recurrence = "FREQ=DAILY"
        task.plannedStart = date(2026, 3, 7, 2, 30, calendar: calendar)
        task.plannedEnd = date(2026, 3, 7, 3, calendar: calendar)
        task.plannedPrecision = .minute
        let snapshot = PlanningHorizonProjection.make(
            tasks: [task], timeEntries: [], horizon: .tomorrow, workspaceID: workspace.id,
            now: date(2026, 3, 7, 12, calendar: calendar), calendar: calendar
        )
        let block = try #require(snapshot.days[0].planBlocks.first)
        #expect(block.start == date(2026, 3, 8, 3, 30, calendar: calendar))
        #expect(block.end == date(2026, 3, 8, 4, calendar: calendar))
        #expect(block.plannedDuration == 30 * 60)
        #expect(snapshot.days[0].drawerTasks.isEmpty)
    }

    @Test("Candidate lookups default to the calendar used to construct the projection")
    func candidateCalendarIsPreserved() {
        let calendar = calendar("Asia/Tokyo")
        let workspace = Workspace(name: "Tokyo", symbolName: "calendar", colorHex: "#0A84FF")
        let task = GTDTask(title: "Backlog", workspaceID: workspace.id, parentID: nil, status: .open)
        let snapshot = PlanningHorizonProjection.make(
            tasks: [task], timeEntries: [], horizon: .tomorrow, workspaceID: workspace.id,
            now: date(2026, 10, 2, 12, calendar: calendar), calendar: calendar
        )
        #expect(snapshot.planningCandidates(on: date(2026, 10, 3, 12, calendar: calendar)).map(\.id) == [task.id])
    }

    @Test("Actual duration is clipped to each day while canonical entries remain intact")
    func clippedActualDurationPreservesRecords() {
        let fixture = Fixture()
        let entry = TimeEntry(
            workspaceID: fixture.workspace.id, taskID: nil, title: "Across midnight",
            startedAt: fixture.date(3, 23, 30), endedAt: fixture.date(4, 1), source: .manual
        )
        let snapshot = fixture.project([], entries: [entry])
        #expect(snapshot.days[0].actualDuration == 30 * 60)
        #expect(snapshot.days[1].actualDuration == 60 * 60)
        #expect(snapshot.actualDuration == entry.duration)
        #expect(snapshot.days[0].actualEntries == [entry])
        #expect(snapshot.days[1].actualEntries == [entry])
        #expect(snapshot.days[2].actualEntries.isEmpty)
    }

    @Test("Paused sessions are proportionally allocated instead of repeated in full on every day")
    func activeSecondsAllocation() {
        let fixture = Fixture()
        let entry = TimeEntry(
            workspaceID: fixture.workspace.id, taskID: nil, title: "Paused session",
            startedAt: fixture.date(3, 23), endedAt: fixture.date(4, 1), source: .pomodoro,
            activeSeconds: 3_600
        )
        let snapshot = fixture.project([], entries: [entry])
        #expect(snapshot.days[0].actualDuration == 1_800)
        #expect(snapshot.days[1].actualDuration == 1_800)
        #expect(snapshot.actualDuration == entry.duration)
        #expect(snapshot.days[0].actualEntries[0].activeSeconds == 3_600)
    }

    @Test("Actual records respect workspace and half-open boundaries and ignore invalid spans")
    func actualEntryBoundaries() {
        let fixture = Fixture()
        let valid = TimeEntry(
            workspaceID: fixture.workspace.id, taskID: nil, title: "Ends at midnight",
            startedAt: fixture.date(2, 23), endedAt: fixture.date(3), source: .manual
        )
        var foreign = valid
        foreign.id = UUID()
        foreign.workspaceID = UUID()
        foreign.startedAt = fixture.date(3, 8)
        foreign.endedAt = fixture.date(3, 9)
        var zero = valid
        zero.id = UUID()
        zero.startedAt = fixture.date(3, 8)
        zero.endedAt = zero.startedAt
        var reversed = zero
        reversed.id = UUID()
        reversed.endedAt = fixture.date(3, 7)
        let snapshot = fixture.project([], entries: [valid, foreign, zero, reversed])
        #expect(snapshot.actualDuration == 0)
        #expect(snapshot.days.allSatisfy { $0.actualEntries.isEmpty })
    }

    @Test("Planning candidates include backlog while respecting selected day and workspace")
    func planningCandidates() {
        let fixture = Fixture()
        var backlog = fixture.task("Overdue backlog")
        backlog.deadline = fixture.date(1)
        var scheduled = fixture.task("Scheduled tomorrow")
        scheduled.executionSlots = [.init(start: fixture.date(3, 9), end: fixture.date(3, 10))]
        var done = fixture.task("Done")
        done.status = .done
        var foreign = fixture.task("Other workspace")
        foreign.workspaceID = UUID()
        let snapshot = fixture.project([backlog, scheduled, done, foreign])
        #expect(snapshot.tasks.map(\.id) == [scheduled.id])
        #expect(snapshot.planningCandidates.map(\.id) == [backlog.id])
        #expect(snapshot.planningCandidates(on: fixture.date(3), calendar: fixture.calendar).map(\.id) == [backlog.id])
        #expect(Set(snapshot.planningCandidates(on: fixture.date(4), calendar: fixture.calendar).map(\.id)) == Set([backlog.id, scheduled.id]))
        #expect(snapshot.planningCandidates(on: fixture.date(10), calendar: fixture.calendar).isEmpty)
    }

    @Test("Smart list counts and cached filtering share future projection rules")
    func smartListConsistency() {
        let fixture = Fixture()
        var range = fixture.task("Range")
        range.plannedStart = fixture.date(1)
        range.plannedEnd = fixture.date(10)
        var slot = fixture.task("Only slot")
        slot.executionSlots = [.init(start: fixture.date(4, 10), end: fixture.date(4, 11))]
        var daily = fixture.task("Daily")
        daily.recurrence = "FREQ=DAILY"
        daily.completedInstances = [TodayExecutionProjection.completionToken(for: fixture.date(3), calendar: fixture.calendar)]
        var overdue = fixture.task("Overdue")
        overdue.deadline = fixture.date(1)
        let model = fixture.model([range, slot, daily, overdue])
        for (list, horizon) in [(SmartList.tomorrow, PlanningHorizon.tomorrow), (.recent, .nextSevenDays)] {
            let filtered = model.filteredTasks(for: list, includeSearch: false, now: fixture.now, calendar: fixture.calendar)
            let projection = model.planningHorizonSnapshot(for: horizon, now: fixture.now, calendar: fixture.calendar)
            #expect(filtered.count == model.count(for: list, now: fixture.now, calendar: fixture.calendar))
            #expect(filtered.count == projection.remainingCount)
            #expect(filtered == model.filteredTasks(for: list, includeSearch: false, now: fixture.now, calendar: fixture.calendar))
        }
        model.toggleTodayCompletion(taskID: daily.id, on: fixture.date(3), calendar: fixture.calendar)
        #expect(model.count(for: .tomorrow, now: fixture.now, calendar: fixture.calendar) == 2)
        #expect(model.filteredTasks(for: .tomorrow, now: fixture.now, calendar: fixture.calendar).count == 2)
    }

    @Test("Cached future lists roll over at local midnight and isolate calendar changes")
    func cacheRolloverAndCalendar() {
        let fixture = Fixture()
        var task = fixture.task("Midnight-sensitive")
        task.plannedStart = fixture.date(3, 4)
        let model = fixture.model([task])
        #expect(model.filteredTasks(for: .tomorrow, now: fixture.now, calendar: fixture.calendar).count == 1)
        #expect(model.filteredTasks(for: .tomorrow, now: fixture.date(3, 0, 1), calendar: fixture.calendar).isEmpty)
        let pacific = calendar("America/Los_Angeles")
        #expect(model.filteredTasks(for: .tomorrow, now: fixture.now, calendar: pacific).isEmpty)
        #expect(model.filteredTasks(for: .tomorrow, now: fixture.now, calendar: fixture.calendar).count == 1)
    }

    @Test("Execution slots are idempotent and reject finished or foreign-workspace tasks")
    func executionSlotValidation() throws {
        let fixture = Fixture()
        let task = fixture.task("Open")
        var done = fixture.task("Done")
        done.status = .done
        var foreign = fixture.task("Foreign")
        foreign.workspaceID = UUID()
        let model = fixture.model([task, done, foreign])
        let first = try #require(model.addExecutionSlot(taskID: task.id, start: fixture.date(3, 9), end: fixture.date(3, 10), calendar: fixture.calendar))
        let revision = model.taskRevision
        let repeated = model.addExecutionSlot(taskID: task.id, start: first.start, end: first.end, calendar: fixture.calendar)
        #expect(repeated == first)
        #expect(model.taskRevision == revision)
        #expect(model.task(withID: task.id)?.executionSlots.count == 1)
        #expect(model.addExecutionSlot(taskID: done.id, start: first.start, end: first.end) == nil)
        #expect(model.addExecutionSlot(taskID: foreign.id, start: first.start, end: first.end) == nil)
        #expect(model.addExecutionSlot(taskID: task.id, start: first.end, end: first.start) == nil)
        #expect(model.addExecutionSlot(taskID: task.id, start: first.start, end: first.start) == nil)
        // Distinct overlapping slots remain a user decision, not a model error.
        #expect(model.addExecutionSlot(taskID: task.id, start: fixture.date(3, 9, 30), end: fixture.date(3, 10, 30), calendar: fixture.calendar) != nil)
    }

    @Test("Execution slots cannot overlap completed or skipped daily instances")
    func executionSlotsRespectDailyInstances() {
        let fixture = Fixture()
        var daily = fixture.task("Daily")
        daily.recurrence = "FREQ=DAILY"
        daily.completedInstances = [TodayExecutionProjection.completionToken(for: fixture.date(4), calendar: fixture.calendar)]
        daily.skippedInstances = [TodayExecutionProjection.completionToken(for: fixture.date(5), calendar: fixture.calendar)]
        let model = fixture.model([daily])
        #expect(model.addExecutionSlot(taskID: daily.id, start: fixture.date(4, 9), end: fixture.date(4, 10), calendar: fixture.calendar) == nil)
        #expect(model.addExecutionSlot(taskID: daily.id, start: fixture.date(3, 23), end: fixture.date(4, 1), calendar: fixture.calendar) == nil)
        #expect(model.addExecutionSlot(taskID: daily.id, start: fixture.date(5, 9), end: fixture.date(5, 10), calendar: fixture.calendar) == nil)
        #expect(model.addExecutionSlot(taskID: daily.id, start: fixture.date(3, 23), end: fixture.date(4), calendar: fixture.calendar) != nil)
    }

    @Test("Removing a slot is scoped, idempotent and preserves other plans and deadlines")
    func executionSlotRemoval() throws {
        let fixture = Fixture()
        var task = fixture.task("Two slots")
        let first = TaskExecutionSlot(start: fixture.date(3, 9), end: fixture.date(3, 10))
        let second = TaskExecutionSlot(start: fixture.date(4, 9), end: fixture.date(4, 10))
        task.executionSlots = [first, second]
        task.plannedStart = fixture.date(2)
        task.plannedEnd = fixture.date(8)
        task.plannedPrecision = .date
        task.deadline = fixture.date(9, 18)
        var foreign = task
        foreign.id = UUID()
        foreign.workspaceID = UUID()
        let model = fixture.model([task, foreign])
        #expect(!model.removeExecutionSlot(taskID: foreign.id, slotID: first.id))
        #expect(!model.removeExecutionSlot(taskID: task.id, slotID: UUID()))
        #expect(model.removeExecutionSlot(taskID: task.id, slotID: first.id))
        let revision = model.taskRevision
        #expect(!model.removeExecutionSlot(taskID: task.id, slotID: first.id))
        #expect(model.taskRevision == revision)
        let updated = try #require(model.task(withID: task.id))
        #expect(updated.executionSlots == [second])
        #expect(updated.plannedStart == task.plannedStart)
        #expect(updated.plannedEnd == task.plannedEnd)
        #expect(updated.deadline == task.deadline)
        #expect(model.task(withID: foreign.id)?.executionSlots == [first, second])
    }

    @Test("A fully completed recurring horizon has one completed task and seven completed instances")
    func fullyCompletedRecurrence() {
        let fixture = Fixture()
        var daily = fixture.task("Complete every day")
        daily.recurrence = "FREQ=DAILY"
        daily.completedInstances = (3...9).map {
            TodayExecutionProjection.completionToken(for: fixture.date($0), calendar: fixture.calendar)
        }
        let snapshot = fixture.project([daily])
        #expect(snapshot.totalCount == 1)
        #expect(snapshot.remainingCount == 0)
        #expect(snapshot.completedCount == 1)
        #expect(snapshot.completedOccurrenceCount == 7)
        #expect(snapshot.planningCandidates.isEmpty)
        #expect(!PlanningHorizon.nextSevenDays.containsUnfinishedTask(daily, relativeTo: fixture.now, calendar: fixture.calendar))
    }

    @Test("Invalid task ranges and execution slots do not leak into a future day")
    func invalidPlans() {
        let fixture = Fixture()
        var invalidRange = fixture.task("Reversed plan")
        invalidRange.plannedStart = fixture.date(3, 10)
        invalidRange.plannedEnd = fixture.date(3, 9)
        invalidRange.plannedPrecision = .minute
        var zeroSlot = fixture.task("Zero slot")
        zeroSlot.executionSlots = [.init(start: fixture.date(3, 9), end: fixture.date(3, 9))]
        var cancelled = fixture.task("Cancelled daily")
        cancelled.status = .cancelled
        cancelled.recurrence = "FREQ=DAILY"
        cancelled.completedInstances = [TodayExecutionProjection.completionToken(for: fixture.date(3), calendar: fixture.calendar)]
        let snapshot = fixture.project([invalidRange, zeroSlot, cancelled], horizon: .tomorrow)
        #expect(snapshot.tasks.isEmpty)
        #expect(snapshot.days[0].planBlocks.isEmpty)
    }

    @Test("Future creation defaults use the selected valid day and recover from stale dates")
    func defaultPlanningDay() {
        let fixture = Fixture()
        let model = fixture.model([])
        model.selectSmartList(.today)
        #expect(model.defaultTaskPlanningDay(now: fixture.now, calendar: fixture.calendar) == fixture.date(2))
        model.selectSmartList(.tomorrow)
        #expect(model.defaultTaskPlanningDay(now: fixture.now, calendar: fixture.calendar) == fixture.date(3))
        model.selectSmartList(.recent)
        model.selection.planningDay = fixture.date(7, 15)
        #expect(model.defaultTaskPlanningDay(now: fixture.now, calendar: fixture.calendar) == fixture.date(7))
        model.selection.planningDay = fixture.date(10)
        #expect(model.defaultTaskPlanningDay(now: fixture.now, calendar: fixture.calendar) == fixture.date(3))
        model.selection.planningDay = fixture.date(3)
        #expect(model.defaultTaskPlanningDay(now: fixture.date(4, 12), calendar: fixture.calendar) == fixture.date(5))
    }

    @Test("Leaving calendar resets its display mode and future selection without changing tasks")
    func calendarNavigationAndDefaultIsolation() {
        let fixture = Fixture()
        let task = fixture.task("Unscheduled")
        let model = fixture.model([task])
        model.selectSmartList(.calendar)
        #expect(model.selection.plannerView == .calendar)
        #expect(model.defaultTaskPlanningDay(now: fixture.now, calendar: fixture.calendar) == fixture.date(2))
        model.selection.planningDay = fixture.date(8)
        model.selectSmartList(.tomorrow)
        #expect(model.selection.plannerView == .list)
        #expect(model.selection.planningDay == nil)
        #expect(model.task(withID: task.id)?.plannedStart == nil)

        model.selection.selectedOrganization = .filters
        #expect(model.defaultTaskPlanningDay(now: fixture.now, calendar: fixture.calendar) == nil)
        model.selection.selectedOrganization = nil
        model.selection.focusMode = .pomodoro
        #expect(model.defaultTaskPlanningDay(now: fixture.now, calendar: fixture.calendar) == nil)
        model.selection.focusMode = nil
        model.selection.selectedArchive = .logs
        #expect(model.defaultTaskPlanningDay(now: fixture.now, calendar: fixture.calendar) == nil)
        model.selection.selectedArchive = nil
        model.selection.selectedProjectID = UUID()
        #expect(model.defaultTaskPlanningDay(now: fixture.now, calendar: fixture.calendar) == nil)
        model.selectSmartList(.all)
        #expect(model.defaultTaskPlanningDay(now: fixture.now, calendar: fixture.calendar) == nil)
    }

    private func calendar(_ zone: String = "UTC") -> Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: zone)!
        return result
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private struct Fixture {
        let workspace = Workspace(name: "Planning", symbolName: "calendar", colorHex: "#0A84FF")
        let calendar: Calendar = {
            var value = Calendar(identifier: .gregorian)
            value.timeZone = TimeZone(secondsFromGMT: 0)!
            return value
        }()
        var now: Date { date(2, 12) }

        func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
        }

        func task(_ title: String) -> GTDTask {
            GTDTask(title: title, workspaceID: workspace.id, parentID: nil, status: .open)
        }

        func project(_ tasks: [GTDTask], entries: [TimeEntry] = [], horizon: PlanningHorizon = .nextSevenDays) -> PlanningHorizonSnapshot {
            PlanningHorizonProjection.make(
                tasks: tasks, timeEntries: entries, horizon: horizon,
                workspaceID: workspace.id, now: now, calendar: calendar
            )
        }

        func day(_ tasks: [GTDTask], on day: Date) -> TodayExecutionSnapshot {
            TodayExecutionProjection.make(tasks: tasks, timeEntries: [], day: day, workspaceID: workspace.id, now: now, calendar: calendar)
        }

        @MainActor
        func model(_ tasks: [GTDTask]) -> AppModel {
            AppModel(database: GTDDatabase(
                workspaces: [workspace], workspaceOrder: [workspace.id],
                pinnedWorkspaceIDs: [workspace.id], tasks: tasks
            ), storage: LocalDatabase(inMemory: true))
        }
    }
}
