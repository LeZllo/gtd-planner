import Foundation
import Testing
@testable import GTDPlanner

@MainActor
struct CalendarPlanningTests {
    @Test("The month grid respects firstWeekday and contains complete adjacent weeks")
    func completeWeeksAndWeekStart() throws {
        var calendar = makeCalendar()
        calendar.firstWeekday = 1
        let sunday = try #require(CalendarMonthGrid.make(containing: date(2026, 10, 15, calendar: calendar), calendar: calendar))
        #expect(sunday.days.first?.date == date(2026, 9, 27, calendar: calendar))
        #expect(sunday.days.last?.date == date(2026, 10, 31, calendar: calendar))
        #expect(sunday.days.filter(\.isInMonth).count == 31)
        #expect(sunday.days.count == 35)
        #expect(sunday.weekCount == 5)
        calendar.firstWeekday = 2
        let monday = try #require(CalendarMonthGrid.make(containing: sunday.month, calendar: calendar))
        #expect(monday.days.first?.date == date(2026, 9, 28, calendar: calendar))
        #expect(monday.days.last?.date == date(2026, 11, 1, calendar: calendar))
        #expect(monday.days.count % 7 == 0)
        #expect(monday.firstWeekday == 2)
        #expect(Set(monday.days.map(\.date)).count == monday.days.count)
    }

    @Test("Four-week and six-week months do not omit or duplicate dates")
    func shortAndLongMonthGrids() throws {
        var calendar = makeCalendar()
        calendar.firstWeekday = 2
        let short = try #require(CalendarMonthGrid.make(containing: date(2021, 2, 1, calendar: calendar), calendar: calendar))
        #expect(short.days.count == 28)
        let allDaysAreInMonth = short.days.allSatisfy { $0.isInMonth }
        #expect(allDaysAreInMonth)
        calendar.firstWeekday = 1
        let long = try #require(CalendarMonthGrid.make(containing: date(2026, 8, 1, calendar: calendar), calendar: calendar))
        #expect(long.days.count == 42)
        #expect(long.days.filter(\.isInMonth).count == 31)
        let leap = try #require(CalendarMonthGrid.make(containing: date(2028, 2, 1, calendar: calendar), calendar: calendar))
        #expect(leap.days.filter(\.isInMonth).count == 29)
    }

    @Test("A grid preserves local midnight through both daylight-saving transitions")
    func daylightSavingGrid() throws {
        let calendar = makeCalendar("America/New_York")
        for (month, transitionDay, hours) in [(3, 8, 23), (11, 1, 25)] {
            let grid = try #require(CalendarMonthGrid.make(containing: date(2026, month, 15, calendar: calendar), calendar: calendar))
            for (first, second) in zip(grid.days, grid.days.dropFirst()) {
                #expect(calendar.component(.hour, from: first.date) == 0)
                #expect(calendar.date(byAdding: .day, value: 1, to: first.date) == second.date)
            }
            let transition = date(2026, month, transitionDay, calendar: calendar)
            let nextDay = try #require(calendar.date(byAdding: .day, value: 1, to: transition))
            #expect(nextDay.timeIntervalSince(transition) == TimeInterval(hours * 3_600))
            #expect(grid.days.contains { $0.date == transition })
            #expect(grid.days.contains { $0.date == nextDay })
        }
    }

    @Test("Weekday headings use the same weekday order as the grid")
    func weekdayHeadingOrder() {
        var calendar = makeCalendar()
        calendar.firstWeekday = 1
        let sunday = CalendarMonthGrid.weekdaySymbols(calendar: calendar, locale: Locale(identifier: "en_US"))
        calendar.firstWeekday = 2
        let monday = CalendarMonthGrid.weekdaySymbols(calendar: calendar, locale: Locale(identifier: "en_US"))
        #expect(sunday.count == 7)
        #expect(monday == Array(sunday.dropFirst()) + [sunday[0]])
    }

    @Test("Month navigation crosses years and clamps month-end selection")
    func monthNavigation() throws {
        let calendar = makeCalendar()
        let december = date(2026, 12, 31, 18, calendar: calendar)
        let january = try #require(CalendarMonthGrid.navigation(from: december, selectedDay: december, offset: 1, calendar: calendar))
        #expect(january.month == date(2027, 1, 1, calendar: calendar))
        #expect(january.selectedDay == date(2027, 1, 31, calendar: calendar))
        let february = try #require(CalendarMonthGrid.navigation(from: january.month, selectedDay: january.selectedDay, offset: 1, calendar: calendar))
        #expect(february.month == date(2027, 2, 1, calendar: calendar))
        #expect(february.selectedDay == date(2027, 2, 28, calendar: calendar))
        let previous = try #require(CalendarMonthGrid.navigation(from: january.month, selectedDay: january.selectedDay, offset: -1, calendar: calendar))
        #expect(previous.month == date(2026, 12, 1, calendar: calendar))
        #expect(previous.selectedDay == date(2026, 12, 31, calendar: calendar))
    }

    @Test("Leap-month navigation and spring-forward selection remain calendar based")
    func leapAndDSTNavigation() throws {
        let calendar = makeCalendar("America/Los_Angeles")
        let january = date(2028, 1, 31, calendar: calendar)
        let leap = try #require(CalendarMonthGrid.navigation(from: january, selectedDay: january, offset: 1, calendar: calendar))
        #expect(leap.selectedDay == date(2028, 2, 29, calendar: calendar))
        let february = date(2026, 2, 8, calendar: calendar)
        let spring = try #require(CalendarMonthGrid.navigation(from: february, selectedDay: february, offset: 1, calendar: calendar))
        #expect(spring.selectedDay == date(2026, 3, 8, calendar: calendar))
        #expect(calendar.component(.hour, from: spring.selectedDay) == 0)
    }

    @Test("Calendar excludes overdue-only backlog even on Today, but includes explicit slots")
    func overdueBacklogIsNotScheduled() throws {
        let fixture = Fixture()
        var backlog = fixture.task("Past deadline")
        backlog.deadline = fixture.date(1, 9)
        let calendar = try fixture.project([backlog])
        #expect(calendar.day(on: fixture.date(1))?.tasks.map(\.id) == [backlog.id])
        #expect(calendar.day(on: fixture.date(2))?.tasks.isEmpty == true)
        #expect(calendar.day(on: fixture.date(3))?.tasks.isEmpty == true)
        #expect(calendar.taskCount == 1)
        backlog.executionSlots = [.init(start: fixture.date(3, 10), end: fixture.date(3, 11))]
        let scheduled = try fixture.project([backlog])
        #expect(scheduled.day(on: fixture.date(3))?.tasks.map(\.id) == [backlog.id])
        #expect(scheduled.day(on: fixture.date(3))?.planBlocks.count == 1)
        #expect(scheduled.taskCount == 1)
    }

    @Test("Date counts and selected-day counts agree and isolate workspace and cancelled tasks")
    func countsAndWorkspaceScope() throws {
        let fixture = Fixture()
        var plan = fixture.task("Dated plan")
        plan.plannedStart = fixture.date(3)
        plan.plannedPrecision = .date
        var deadline = fixture.task("Deadline only")
        deadline.deadline = fixture.date(3, 17)
        var foreign = plan
        foreign.id = UUID()
        foreign.workspaceID = UUID()
        var cancelled = plan
        cancelled.id = UUID()
        cancelled.status = .cancelled
        let projection = try fixture.project([plan, deadline, foreign, cancelled])
        let day = try #require(projection.day(on: fixture.date(3, 18)))
        #expect(day.totalCount == 2)
        #expect(day.deadlineTasks.map(\.id) == [deadline.id])
        #expect(day.planBlocks.isEmpty)
        #expect(projection.taskCount == 2)
        #expect(projection.deadlineCount == 1)
        #expect(projection.occurrenceCount == 2)
    }

    @Test("Date ranges remain task occurrences, not all-day blocks, and end at midnight exclusively")
    func crossDayRangesAndMidnight() throws {
        let fixture = Fixture()
        var range = fixture.task("Two days")
        range.plannedStart = fixture.date(3)
        range.plannedEnd = fixture.date(5)
        range.plannedPrecision = .date
        var slot = fixture.task("Until midnight")
        slot.executionSlots = [.init(start: fixture.date(3, 23), end: fixture.date(4))]
        let projection = try fixture.project([range, slot])
        #expect(projection.day(on: fixture.date(3))?.totalCount == 2)
        #expect(projection.day(on: fixture.date(4))?.tasks.map(\.id) == [range.id])
        #expect(projection.day(on: fixture.date(5))?.tasks.isEmpty == true)
        #expect(projection.day(on: fixture.date(3))?.plannedDuration == 3_600)
        #expect(projection.day(on: fixture.date(4))?.planBlocks.isEmpty == true)
        #expect(projection.taskCount == 2)
        #expect(projection.occurrenceCount == 3)
    }

    @Test("A cross-midnight slot is clipped into exactly the intersected date cells")
    func clippedSlots() throws {
        let fixture = Fixture()
        var task = fixture.task("Night slot")
        let slot = TaskExecutionSlot(start: fixture.date(3, 23, 30), end: fixture.date(4, 1))
        task.executionSlots = [slot]
        let projection = try fixture.project([task])
        let first = try #require(projection.day(on: fixture.date(3))?.planBlocks.first)
        let second = try #require(projection.day(on: fixture.date(4))?.planBlocks.first)
        #expect(first.id.slotID == slot.id)
        #expect(second.id.slotID == slot.id)
        #expect(first.plannedDuration == 1_800)
        #expect(second.plannedDuration == 3_600)
        #expect(first.end == fixture.date(4))
        #expect(second.start == fixture.date(4))
        #expect(projection.day(on: fixture.date(5))?.planBlocks.isEmpty == true)
    }

    @Test("Adjacent-month dates remain selectable but do not inflate the month's totals")
    func adjacentMonthCounts() throws {
        let fixture = Fixture()
        var previous = fixture.task("September edge")
        previous.plannedStart = date(2026, 9, 30, calendar: fixture.calendar)
        var current = fixture.task("October")
        current.plannedStart = fixture.date(2)
        let projection = try fixture.project([previous, current])
        #expect(projection.day(on: previous.plannedStart!)?.tasks.map(\.id) == [previous.id])
        #expect(projection.taskCount == 1)
        #expect(projection.occurrenceCount == 1)
        #expect(projection.monthDays.count == 31)
    }

    @Test("Daily instances respect recurrence start, skipped days, and completion tokens")
    func dailyInstances() throws {
        let fixture = Fixture()
        var daily = fixture.task("Daily")
        daily.recurrence = "RRULE:FREQ=DAILY"
        daily.plannedStart = fixture.date(2, 9)
        daily.plannedEnd = fixture.date(2, 10)
        daily.plannedPrecision = .minute
        daily.completedInstances = [TodayExecutionProjection.completionToken(for: fixture.date(2), calendar: fixture.calendar)]
        daily.skippedInstances = [TodayExecutionProjection.completionToken(for: fixture.date(4), calendar: fixture.calendar)]
        let projection = try fixture.project([daily])
        #expect(projection.day(on: fixture.date(1))?.tasks.isEmpty == true)
        #expect(projection.day(on: fixture.date(2))?.completedCount == 1)
        #expect(projection.day(on: fixture.date(3))?.completedCount == 0)
        #expect(projection.day(on: fixture.date(3))?.planBlocks.first?.start == fixture.date(3, 9))
        #expect(projection.day(on: fixture.date(4))?.tasks.isEmpty == true)
        #expect(projection.taskCount == 1)
    }

    @Test("Ordinary completion appears on its recorded day rather than silently backdating it")
    func ordinaryCompletionHistory() throws {
        let fixture = Fixture()
        var done = fixture.task("Completed yesterday")
        done.status = .done
        done.completedAt = fixture.date(1, 15)
        done.plannedStart = fixture.date(3)
        let projection = try fixture.project([done])
        #expect(projection.day(on: fixture.date(1))?.completedTasks.map(\.id) == [done.id])
        #expect(projection.day(on: fixture.date(2))?.tasks.isEmpty == true)
        #expect(projection.day(on: fixture.date(3))?.tasks.isEmpty == true)
    }

    @Test("Completion controls distinguish future plans, past history, and today's canonical task")
    func completionRules() {
        let fixture = Fixture()
        let ordinary = fixture.task("Ordinary")
        #expect(CalendarTaskCompletionRule.resolve(task: ordinary, day: fixture.date(1), now: fixture.now, calendar: fixture.calendar) == .historyOnly)
        #expect(CalendarTaskCompletionRule.resolve(task: ordinary, day: fixture.date(2, 23), now: fixture.now, calendar: fixture.calendar) == .todayTask)
        #expect(CalendarTaskCompletionRule.resolve(task: ordinary, day: fixture.date(3), now: fixture.now, calendar: fixture.calendar) == .futurePlan)
        var daily = fixture.task("Daily")
        daily.recurrence = "FREQ=DAILY"
        #expect(CalendarTaskCompletionRule.resolve(task: daily, day: fixture.date(1), now: fixture.now, calendar: fixture.calendar) == .dailyInstance)
        #expect(CalendarTaskCompletionRule.resolve(task: daily, day: fixture.date(3), now: fixture.now, calendar: fixture.calendar) == .futurePlan)
        daily.skippedInstances = [TodayExecutionProjection.completionToken(for: fixture.date(1), calendar: fixture.calendar)]
        #expect(CalendarTaskCompletionRule.resolve(task: daily, day: fixture.date(1), now: fixture.now, calendar: fixture.calendar) == .unavailable)
    }

    @Test("Future completed recurring tokens cannot be reopened through a calendar control")
    func futureCompletedTokenIsProtected() {
        let fixture = Fixture()
        var daily = fixture.task("Daily")
        daily.recurrence = "FREQ=DAILY"
        let token = TodayExecutionProjection.completionToken(for: fixture.date(3), calendar: fixture.calendar)
        daily.completedInstances = [token]
        let model = fixture.model([daily])
        #expect(!model.toggleCalendarCompletion(taskID: daily.id, day: fixture.date(3), now: fixture.now, calendar: fixture.calendar))
        #expect(model.task(withID: daily.id)?.completedInstances == [token])
    }

    @Test("Past daily instances can be recorded and reopened without changing global task state")
    func pastDailyMutation() {
        let fixture = Fixture()
        var daily = fixture.task("Daily")
        daily.recurrence = "FREQ=DAILY"
        let model = fixture.model([daily])
        #expect(model.toggleCalendarCompletion(taskID: daily.id, day: fixture.date(1), now: fixture.now, calendar: fixture.calendar))
        #expect(model.task(withID: daily.id)?.completedInstances == ["2026-10-01"])
        #expect(model.task(withID: daily.id)?.status == .open)
        #expect(model.task(withID: daily.id)?.completedAt == nil)
        #expect(model.toggleCalendarCompletion(taskID: daily.id, day: fixture.date(1), now: fixture.now, calendar: fixture.calendar))
        #expect(model.task(withID: daily.id)?.completedInstances.isEmpty == true)
    }

    @Test("Today's ordinary completion toggles the canonical task and records the real completion date")
    func todayOrdinaryMutation() throws {
        let fixture = Fixture()
        let now = Date.now
        let today = fixture.calendar.startOfDay(for: now)
        var ordinary = fixture.task("Complete now")
        ordinary.plannedStart = today
        let model = fixture.model([ordinary])
        #expect(model.toggleCalendarCompletion(taskID: ordinary.id, day: today, now: now, calendar: fixture.calendar))
        let completed = try #require(model.task(withID: ordinary.id))
        #expect(completed.status == .done)
        let completedAt = try #require(completed.completedAt)
        #expect(fixture.calendar.isDate(completedAt, inSameDayAs: now))
        #expect(model.toggleCalendarCompletion(taskID: ordinary.id, day: today, now: now, calendar: fixture.calendar))
        #expect(model.task(withID: ordinary.id)?.status == .open)
        #expect(model.task(withID: ordinary.id)?.completedAt == nil)
    }

    @Test("Scheduling backlog and removing its slot immediately updates calendar counts")
    func schedulingRoundTrip() throws {
        let fixture = Fixture()
        let backlog = fixture.task("Backlog")
        let model = fixture.model([backlog])
        #expect(model.dayPlanningCandidates(on: fixture.date(3), now: fixture.now, calendar: fixture.calendar).map(\.id) == [backlog.id])
        #expect(model.calendarPlanningSnapshot(month: fixture.now, now: fixture.now, calendar: fixture.calendar)?.taskCount == 0)
        let slot = try #require(model.addExecutionSlot(taskID: backlog.id, start: fixture.date(3, 9), end: fixture.date(3, 10), calendar: fixture.calendar))
        let scheduled = try #require(model.calendarPlanningSnapshot(month: fixture.now, now: fixture.now, calendar: fixture.calendar))
        #expect(scheduled.day(on: fixture.date(3))?.tasks.map(\.id) == [backlog.id])
        #expect(scheduled.taskCount == 1)
        #expect(model.dayPlanningCandidates(on: fixture.date(3), now: fixture.now, calendar: fixture.calendar).isEmpty)
        #expect(model.removeExecutionSlot(taskID: backlog.id, slotID: slot.id))
        #expect(model.calendarPlanningSnapshot(month: fixture.now, now: fixture.now, calendar: fixture.calendar)?.taskCount == 0)
        #expect(model.task(withID: backlog.id)?.plannedStart == nil)
        #expect(model.dayPlanningCandidates(on: fixture.date(3), now: fixture.now, calendar: fixture.calendar).map(\.id) == [backlog.id])
    }

    @Test("Stale, foreign, invisible, and past ordinary tasks cannot be completed through calendar rows")
    func mutationGuards() {
        let fixture = Fixture()
        let unplanned = fixture.task("Unplanned")
        var past = fixture.task("Yesterday")
        past.plannedStart = fixture.date(1)
        var foreign = fixture.task("Foreign")
        foreign.workspaceID = UUID()
        foreign.plannedStart = fixture.date(2)
        let model = fixture.model([unplanned, past, foreign])
        let revision = model.taskRevision
        #expect(!model.toggleCalendarCompletion(taskID: unplanned.id, day: fixture.date(2), now: fixture.now, calendar: fixture.calendar))
        #expect(!model.toggleCalendarCompletion(taskID: past.id, day: fixture.date(1), now: fixture.now, calendar: fixture.calendar))
        #expect(!model.toggleCalendarCompletion(taskID: foreign.id, day: fixture.date(2), now: fixture.now, calendar: fixture.calendar))
        #expect(!model.toggleCalendarCompletion(taskID: UUID(), day: fixture.date(2), now: fixture.now, calendar: fixture.calendar))
        #expect(model.taskRevision == revision)
    }

    @Test("Calendar projection changes correctly across local midnight without carrying backlog")
    func midnightRollover() throws {
        let fixture = Fixture()
        var deadline = fixture.task("Midnight deadline")
        deadline.deadline = fixture.date(3)
        let before = try #require(CalendarPlanningProjection.make(tasks: [deadline], timeEntries: [], month: fixture.date(2), workspaceID: fixture.workspace.id,
                                                                now: fixture.date(2, 23, 59), calendar: fixture.calendar))
        let after = try #require(CalendarPlanningProjection.make(tasks: [deadline], timeEntries: [], month: fixture.date(3), workspaceID: fixture.workspace.id,
                                                               now: fixture.date(4), calendar: fixture.calendar))
        #expect(before.day(on: fixture.date(2))?.tasks.isEmpty == true)
        #expect(before.day(on: fixture.date(3))?.totalCount == 1)
        #expect(after.day(on: fixture.date(3))?.totalCount == 1)
        #expect(after.day(on: fixture.date(4))?.tasks.isEmpty == true)
    }

    @Test("Calendar creation uses the selected normalized day and navigation does not mutate tasks")
    func selectedDayCreationDefault() {
        let fixture = Fixture()
        let task = fixture.task("Original backlog")
        let model = fixture.model([task])
        model.selectSmartList(.calendar)
        #expect(model.defaultTaskPlanningDay(now: fixture.now, calendar: fixture.calendar) == fixture.date(2))
        model.selection.calendarDay = fixture.date(16, 18, 30)
        #expect(model.defaultTaskPlanningDay(now: fixture.now, calendar: fixture.calendar) == fixture.date(16))
        let planningDay = model.defaultTaskPlanningDay(now: fixture.now, calendar: fixture.calendar)
        model.addTask(title: "Created on selected day", status: .open, plannedStart: planningDay, plannedPrecision: .date)
        let created = model.database.tasks.first { $0.title == "Created on selected day" }
        #expect(created?.plannedStart == fixture.date(16))
        #expect(created?.plannedPrecision == .date)
        #expect(created?.workspaceID == fixture.workspace.id)
        #expect(model.task(withID: task.id)?.plannedStart == nil)
        model.selectSmartList(.all)
        #expect(model.defaultTaskPlanningDay(now: fixture.now, calendar: fixture.calendar) == nil)
    }

    @Test("Snapshot lookups use their own calendar rather than the process timezone")
    func lookupCalendarPreserved() throws {
        let calendar = makeCalendar("Asia/Tokyo")
        let workspace = Workspace(name: "Tokyo", symbolName: "calendar", colorHex: "#0A84FF")
        var task = GTDTask(title: "Local date", workspaceID: workspace.id, parentID: nil, status: .open)
        task.plannedStart = date(2026, 10, 3, calendar: calendar)
        let projection = try #require(CalendarPlanningProjection.make(tasks: [task], timeEntries: [], month: task.plannedStart!, workspaceID: workspace.id,
                                                                    now: date(2026, 10, 2, calendar: calendar), calendar: calendar))
        #expect(projection.day(on: date(2026, 10, 3, 23, calendar: calendar))?.tasks.map(\.id) == [task.id])
        #expect(projection.day(on: date(2026, 10, 4, calendar: calendar))?.tasks.isEmpty == true)
    }

    private func makeCalendar(_ timezone: String = "UTC") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timezone)!
        calendar.firstWeekday = 1
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private struct Fixture {
        let workspace = Workspace(name: "Calendar", symbolName: "calendar", colorHex: "#0A84FF")
        let calendar: Calendar = {
            var value = Calendar(identifier: .gregorian)
            value.timeZone = TimeZone(secondsFromGMT: 0)!
            value.firstWeekday = 1
            return value
        }()
        var now: Date { date(2, 12) }

        func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
        }

        func task(_ title: String) -> GTDTask {
            GTDTask(title: title, workspaceID: workspace.id, parentID: nil, status: .open)
        }

        func project(_ tasks: [GTDTask]) throws -> CalendarPlanningSnapshot {
            try #require(CalendarPlanningProjection.make(tasks: tasks, timeEntries: [], month: now,
                                                        workspaceID: workspace.id, now: now, calendar: calendar))
        }

        @MainActor
        func model(_ tasks: [GTDTask]) -> AppModel {
            AppModel(database: GTDDatabase(workspaces: [workspace], workspaceOrder: [workspace.id],
                                           pinnedWorkspaceIDs: [workspace.id], tasks: tasks),
                     storage: LocalDatabase(inMemory: true))
        }
    }
}
