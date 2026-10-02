import Foundation

/// A complete, locale-ordered week grid. Dates are advanced with Calendar so
/// local midnight survives short and long daylight-saving days.
struct CalendarMonthGrid: Equatable, Sendable {
    struct Day: Identifiable, Equatable, Sendable {
        let date: Date
        let isInMonth: Bool
        var id: Date { date }
    }

    let month: Date
    let interval: DateInterval
    let days: [Day]
    let firstWeekday: Int

    var weekCount: Int { days.count / 7 }

    static func make(containing date: Date, calendar: Calendar = .current) -> Self? {
        guard let interval = calendar.dateInterval(of: .month, for: date),
              let monthDays = calendar.range(of: .day, in: .month, for: date) else { return nil }
        let weekday = calendar.component(.weekday, from: interval.start)
        let leadingCount = (weekday - calendar.firstWeekday + 7) % 7
        let cellCount = ((leadingCount + monthDays.count + 6) / 7) * 7
        guard let gridStart = calendar.date(byAdding: .day, value: -leadingCount, to: interval.start) else { return nil }
        let days = (0..<cellCount).compactMap { offset -> Day? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: gridStart) else { return nil }
            return Day(date: day, isInMonth: TaskDayRules.contains(day, in: interval))
        }
        guard days.count == cellCount else { return nil }
        return Self(month: interval.start, interval: interval, days: days, firstWeekday: calendar.firstWeekday)
    }

    /// Month movement starts from day one rather than adding to January 31.
    /// The selected day is clamped to the destination month's valid day range.
    static func navigation(
        from month: Date,
        selectedDay: Date,
        offset: Int,
        calendar: Calendar = .current
    ) -> (month: Date, selectedDay: Date)? {
        guard let current = calendar.dateInterval(of: .month, for: month),
              let destination = calendar.date(byAdding: .month, value: offset, to: current.start),
              let destinationInterval = calendar.dateInterval(of: .month, for: destination),
              let dayRange = calendar.range(of: .day, in: .month, for: destination) else { return nil }
        let ordinal = min(dayRange.count, max(1, calendar.component(.day, from: selectedDay)))
        guard let day = calendar.date(byAdding: .day, value: ordinal - 1, to: destinationInterval.start) else { return nil }
        return (destinationInterval.start, day)
    }

    static func weekdaySymbols(calendar: Calendar = .current, locale: Locale = .current) -> [String] {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        let symbols = formatter.shortStandaloneWeekdaySymbols ?? []
        guard symbols.count == 7 else { return symbols }
        return (0..<7).map { symbols[(calendar.firstWeekday - 1 + $0) % 7] }
    }
}

struct CalendarPlanningSnapshot: Equatable, Sendable {
    let grid: CalendarMonthGrid
    /// Same order as grid.days, including the adjoining month's edge days.
    let days: [TodayExecutionSnapshot]
    private let calendar: Calendar

    var monthDays: [TodayExecutionSnapshot] {
        days.filter { TaskDayRules.contains($0.day, in: grid.interval) }
    }
    var taskCount: Int { Set(monthDays.flatMap { $0.tasks.map(\.id) }).count }
    var occurrenceCount: Int { monthDays.reduce(0) { $0 + $1.totalCount } }
    var deadlineCount: Int { monthDays.reduce(0) { $0 + $1.deadlineTasks.count } }

    func day(on date: Date) -> TodayExecutionSnapshot? {
        days.first { calendar.isDate($0.day, inSameDayAs: date) }
    }

    fileprivate init(grid: CalendarMonthGrid, days: [TodayExecutionSnapshot], calendar: Calendar) {
        self.grid = grid
        self.days = days
        self.calendar = calendar
    }
}

enum CalendarPlanningProjection {
    static func make(
        tasks: [GTDTask],
        timeEntries: [TimeEntry],
        month: Date,
        workspaceID: UUID,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> CalendarPlanningSnapshot? {
        guard let grid = CalendarMonthGrid.make(containing: month, calendar: calendar) else { return nil }
        let workspaceTasks = tasks.filter { $0.workspaceID == workspaceID }
        let workspaceEntries = timeEntries.filter { $0.workspaceID == workspaceID }
        let days = grid.days.map { day in
            TodayExecutionProjection.make(
                tasks: workspaceTasks, timeEntries: workspaceEntries,
                day: day.date, workspaceID: workspaceID, now: now, calendar: calendar,
                includeOverdueBacklog: false
            )
        }
        return CalendarPlanningSnapshot(grid: grid, days: days, calendar: calendar)
    }
}

/// Past ordinary tasks are read-only: completing one now would record today's
/// completion, not a historical completion. Daily recurrence has dated tokens,
/// so a past instance can be explicitly recorded or reopened. Future days never
/// expose an instance-completion control, including already-completed tokens.
enum CalendarTaskCompletionRule: Equatable, Sendable {
    case todayTask
    case dailyInstance
    case historyOnly
    case futurePlan
    case unavailable

    var allowsToggle: Bool { self == .todayTask || self == .dailyInstance }

    static func resolve(
        task: GTDTask,
        day: Date,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Self {
        guard task.status != .cancelled else { return .unavailable }
        let date = calendar.startOfDay(for: day)
        let today = calendar.startOfDay(for: now)
        guard date <= today else { return .futurePlan }
        if TodayExecutionProjection.isDailyRecurring(task) {
            guard !task.status.isFinished,
                  !TaskDayRules.isSkipped(task, on: day, calendar: calendar),
                  TodayExecutionProjection.isRelevant(task, on: day, now: now, calendar: calendar,
                                                      includeOverdueBacklog: false) else { return .unavailable }
            return .dailyInstance
        }
        return date == today ? .todayTask : .historyOnly
    }
}

extension AppModel {
    func calendarPlanningSnapshot(
        month: Date,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> CalendarPlanningSnapshot? {
        _ = taskRevision
        return CalendarPlanningProjection.make(
            tasks: database.tasks, timeEntries: database.timeEntries, month: month,
            workspaceID: selection.selectedWorkspaceID, now: now, calendar: calendar
        )
    }

    /// Resolves a fresh canonical task and checks the same rule as the button.
    /// This rejects stale rows after a workspace change or a date rollover.
    @discardableResult
    func toggleCalendarCompletion(
        taskID: UUID,
        day: Date,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        guard let task = task(withID: taskID),
              task.workspaceID == selection.selectedWorkspaceID,
              CalendarTaskCompletionRule.resolve(task: task, day: day, now: now, calendar: calendar).allowsToggle,
              TodayExecutionProjection.isRelevant(task, on: day, now: now, calendar: calendar,
                                                  includeOverdueBacklog: false) else { return false }
        toggleTodayCompletion(taskID: taskID, on: day, calendar: calendar)
        return true
    }
}
