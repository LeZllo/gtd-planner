import CoreGraphics
import Foundation
import Testing
@testable import GTDPlanner

@MainActor
struct DayPlanningTests {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }

    private func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func model(tasks: [GTDTask], workspace: Workspace, entries: [TimeEntry] = []) -> AppModel {
        AppModel(database: GTDDatabase(workspaces: [workspace], workspaceOrder: [workspace.id],
                                     pinnedWorkspaceIDs: [workspace.id], tasks: tasks, timeEntries: entries),
                 storage: LocalDatabase(inMemory: true))
    }

    private func workspace() -> Workspace {
        Workspace(name: "Day QA", symbolName: "calendar", colorHex: "#0A84FF")
    }

    @Test("Calendar can exclude overdue backlog while Today preserves it")
    func overdueIsExplicit() {
        let workspace = workspace()
        var overdue = GTDTask(title: "Backlog", workspaceID: workspace.id, parentID: nil, status: .open)
        overdue.deadline = date(1)
        let app = model(tasks: [overdue], workspace: workspace)
        #expect(app.todayExecutionSnapshot(on: date(2), now: date(2, 12), calendar: calendar).tasks.count == 1)
        #expect(app.todayExecutionSnapshot(on: date(2), now: date(2, 12), calendar: calendar, includeOverdueBacklog: false).tasks.isEmpty)
        #expect(app.dayPlanningCandidates(on: date(3), now: date(2, 12), calendar: calendar).map(\.id) == [overdue.id])
    }

    @Test("Shared day candidates include unscheduled tasks but exclude scheduled, finished and foreign tasks")
    func sharedCandidates() {
        let workspace = workspace()
        let open = GTDTask(title: "Open", workspaceID: workspace.id, parentID: nil, status: .open)
        var scheduled = open; scheduled.id = UUID()
        scheduled.executionSlots = [.init(start: date(3, 9), end: date(3, 10))]
        var done = open; done.id = UUID(); done.status = .done
        var foreign = open; foreign.id = UUID(); foreign.workspaceID = UUID()
        let app = model(tasks: [open, scheduled, done, foreign], workspace: workspace)
        #expect(app.dayPlanningCandidates(on: date(3), now: date(2, 12), calendar: calendar).map(\.id) == [open.id])
    }

    @Test("Display filtering preserves canonical actual records and hides unrelated task blocks")
    func filteredSnapshot() {
        let workspace = workspace()
        var first = GTDTask(title: "A", workspaceID: workspace.id, parentID: nil, status: .open)
        first.executionSlots = [.init(start: date(2, 9), end: date(2, 10))]
        var second = first; second.id = UUID(); second.title = "B"
        let entry = TimeEntry(workspaceID: workspace.id, taskID: first.id, title: "A", startedAt: date(1, 23), endedAt: date(2, 1), source: .manual)
        let app = model(tasks: [first, second], workspace: workspace, entries: [entry])
        let full = app.todayExecutionSnapshot(on: date(2), now: date(2, 12), calendar: calendar)
        let filtered = full.filteringTasks(to: [first.id])
        #expect(filtered.tasks.map(\.id) == [first.id])
        #expect(filtered.planBlocks.count == 1)
        #expect(filtered.actualEntries == [entry])
        #expect(filtered.actualDuration == 3_600)
        #expect(full.planBlocks.count == 2)
    }

    @Test("A plan point does not reserve its synthetic display duration")
    func pointConflictSemantics() {
        let taskID = UUID()
        let point = TodayPlanBlock(id: .init(taskID: taskID, source: .taskPlan, slotID: nil), taskID: taskID,
                                   title: "Point", start: date(2, 9), end: date(2, 9, 30), plannedDuration: 0, isPoint: true)
        let later = TodayScheduleDragSelection(lane: .plan, start: date(2, 9, 10), end: date(2, 9, 20))
        let includes = TodayScheduleDragSelection(lane: .plan, start: date(2, 9), end: date(2, 9, 15))
        #expect(!TodayScheduleConflictRules.planConflicts(with: later, blocks: [point]))
        #expect(TodayScheduleConflictRules.planConflicts(with: includes, blocks: [point]))
    }

    @Test("Whole-day timeline clips cross-midnight geometry and maps end to 24:00")
    func timelineClipping() throws {
        let interval = try #require(DayTimelineLayout.visibleInterval(day: date(2), startHour: 0, endHour: 24, calendar: calendar))
        let clipped = try #require(DayTimelineLayout.clipped(start: date(1, 23, 50), end: date(2, 0, 10), to: interval))
        #expect(clipped.start == date(2))
        #expect(clipped.end == date(2, 0, 10))
        #expect(DayTimelineLayout.yOffset(for: date(2), in: interval, startHour: 0, endHour: 24, hourHeight: 60, calendar: calendar) == 0)
        #expect(DayTimelineLayout.yOffset(for: date(3), in: interval, startHour: 0, endHour: 24, hourHeight: 60, calendar: calendar) == 1_440)
        #expect(DayTimelineLayout.clipped(start: date(1, 23), end: date(2), to: interval) == nil)
    }

    @Test("Timeline wall-clock placement stays at 09:00 on short and long DST days")
    func timelineDSTPlacement() throws {
        var pacific = calendar
        pacific.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        for (month, day, duration) in [(3, 8, 23), (11, 1, 25)] {
            let start = try #require(pacific.date(from: DateComponents(year: 2026, month: month, day: day)))
            let nine = try #require(pacific.date(bySettingHour: 9, minute: 0, second: 0, of: start))
            let interval = try #require(DayTimelineLayout.visibleInterval(day: start, startHour: 0, endHour: 24, calendar: pacific))
            #expect(interval.duration == Double(duration * 3_600))
            #expect(DayTimelineLayout.yOffset(for: nine, in: interval, startHour: 0, endHour: 24, hourHeight: 60, calendar: pacific) == 540)
        }
    }

    @Test("Paused cross-midnight timers use wall-clock geometry and remaining active time for the target")
    func pausedTimerGeometry() throws {
        var timer = ActiveTimer(mode: .pomodoro, workspaceID: nil, taskID: nil, title: "Timer",
                                sessionStartedAt: date(1, 23), startedAt: date(2, 9), pausedAt: nil,
                                accumulatedSeconds: 600, targetSeconds: 1_500, phase: .focus)
        let now = date(2, 9, 10)
        let interval = try #require(ActiveTimerDisplayRules.wallClockInterval(for: timer, now: now))
        #expect(interval.start == date(1, 23))
        #expect(interval.end == now)
        #expect(ActiveTimerDisplayRules.targetDate(for: timer, elapsed: 1_200, now: now) == date(2, 9, 15))
        timer.pausedAt = now
        #expect(ActiveTimerDisplayRules.targetDate(for: timer, elapsed: 1_200, now: now) == nil)
        #expect(ActiveTimerDisplayRules.wallClockInterval(for: timer, now: date(2, 12))?.end == now)
    }

    @Test("Editing only actual-record metadata preserves paused effective duration")
    func actualMetadataPreservesDuration() throws {
        let workspace = workspace()
        var entry = TimeEntry(workspaceID: workspace.id, taskID: nil, title: "Paused", startedAt: date(1, 23), endedAt: date(2, 1), source: .stopwatch, activeSeconds: 600)
        let app = model(tasks: [], workspace: workspace, entries: [entry])
        entry.note = "Only note"; entry.activeSeconds = 7_200
        #expect(app.updateTimeEntry(entry, now: date(2, 12)))
        #expect(app.timeEntry(withID: entry.id)?.activeSeconds == 600)
        #expect(app.timeEntry(withID: entry.id)?.startedAt == date(1, 23))
        #expect(app.timeEntry(withID: entry.id)?.endedAt == date(2, 1))
    }

    @Test("Changing an actual time range recomputes duration and cannot change workspace identity")
    func actualRangeAndWorkspace() {
        let workspace = workspace()
        var entry = TimeEntry(workspaceID: workspace.id, taskID: nil, title: "Paused", startedAt: date(1, 23), endedAt: date(2, 1), source: .stopwatch, activeSeconds: 600)
        let app = model(tasks: [], workspace: workspace, entries: [entry])
        entry.endedAt = date(2, 2)
        #expect(app.updateTimeEntry(entry, now: date(2, 12)))
        #expect(app.timeEntry(withID: entry.id)?.activeSeconds == 10_800)
        entry.workspaceID = UUID()
        #expect(!app.updateTimeEntry(entry, now: date(2, 12)))
        #expect(app.timeEntry(withID: entry.id)?.workspaceID == workspace.id)
    }

    @Test("Future actual creation and range changes are rejected, legacy metadata remains editable")
    func futureActualValidation() {
        let workspace = workspace()
        var legacy = TimeEntry(workspaceID: workspace.id, taskID: nil, title: "Imported", startedAt: date(3, 9), endedAt: date(3, 10), source: .manual)
        let app = model(tasks: [], workspace: workspace, entries: [legacy])
        #expect(app.addTimeEntry(workspaceID: workspace.id, taskID: nil, startedAt: date(4, 9), endedAt: date(4, 10), now: date(2, 12)) == nil)
        legacy.note = "Preserve imported dates"
        #expect(app.updateTimeEntry(legacy, now: date(2, 12)))
        legacy.endedAt = date(3, 11)
        #expect(!app.updateTimeEntry(legacy, now: date(2, 12)))
    }

    @Test("A note-only stale editor preserves a concurrent newer time range")
    func mergeConcurrentMetadata() throws {
        let workspace = workspace()
        let original = TimeEntry(workspaceID: workspace.id, taskID: nil, title: "Original", startedAt: date(1, 23), endedAt: date(2, 1), source: .stopwatch, activeSeconds: 600)
        var current = original; current.endedAt = date(2, 2); current.activeSeconds = 10_800
        var draft = original; draft.note = "My new note"
        let merged = try #require(TimeEntryEditRules.merge(original: original, draft: draft, current: current))
        #expect(merged.endedAt == current.endedAt)
        #expect(merged.activeSeconds == current.activeSeconds)
        #expect(merged.note == draft.note)
    }

    @Test("Conflicting edits to the same actual field are rejected instead of overwritten")
    func conflictingEdits() {
        let workspace = workspace()
        let original = TimeEntry(workspaceID: workspace.id, taskID: nil, title: "Original", startedAt: date(1, 23), endedAt: date(2, 1), source: .manual)
        var current = original; current.note = "Other window"
        var draft = original; draft.note = "This window"
        #expect(TimeEntryEditRules.merge(original: original, draft: draft, current: current) == nil)
        current = original; current.endedAt = date(2, 2)
        draft = original; draft.endedAt = date(2, 3)
        #expect(TimeEntryEditRules.merge(original: original, draft: draft, current: current) == nil)
    }

    @Test("Sidebar destinations count the workspace rather than a previously selected project")
    func workspaceSidebarCounts() {
        let workspace = workspace()
        var task = GTDTask(title: "No project", workspaceID: workspace.id, parentID: nil, status: .open)
        task.plannedStart = date(3); task.plannedPrecision = .date
        let app = model(tasks: [task], workspace: workspace)
        app.selection.selectedProjectID = UUID()
        #expect(app.count(for: .tomorrow, now: date(2, 12), calendar: calendar) == 1)
        #expect(app.count(for: .fourSquares, now: date(2, 12), calendar: calendar) == 1)
        app.selectSmartList(.calendar)
        #expect(app.count(for: .calendar, now: date(2, 12), calendar: calendar) == 1)
        app.selection.calendarDay = calendar.date(byAdding: .month, value: 1, to: date(2))
        #expect(app.count(for: .calendar, now: date(2, 12), calendar: calendar) == 0)
    }
}
