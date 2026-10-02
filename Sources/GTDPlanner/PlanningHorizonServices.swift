import Foundation

/// All planning windows are local calendar days, never fixed 24-hour offsets.
enum PlanningHorizon: String, CaseIterable, Identifiable, Sendable {
    case tomorrow
    case nextSevenDays

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tomorrow: "明天"
        case .nextSevenDays: "未来七天"
        }
    }

    func days(relativeTo now: Date = .now, calendar: Calendar = .current) -> [Date] {
        let today = calendar.startOfDay(for: now)
        let count = self == .tomorrow ? 1 : 7
        return (1...count).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }

    func containsUnfinishedTask(
        _ task: GTDTask,
        relativeTo now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        guard !task.status.isFinished else { return false }
        return days(relativeTo: now, calendar: calendar).contains { day in
            !TodayExecutionProjection.isCompleted(task, on: day, calendar: calendar)
                && TodayExecutionProjection.isRelevant(task, on: day, now: now, calendar: calendar)
        }
    }
}

struct PlanningHorizonSnapshot: Equatable, Sendable {
    let horizon: PlanningHorizon
    let days: [TodayExecutionSnapshot]
    /// A task may appear on several days; this collection counts it only once.
    let tasks: [GTDTask]
    /// Unfinished tasks with no concrete time block anywhere in this horizon.
    let planningCandidates: [GTDTask]
    private let workspaceCandidates: [GTDTask]
    private let projectionCalendar: Calendar

    var totalCount: Int { tasks.count }
    var uniqueTaskCount: Int { totalCount }
    var remainingCount: Int {
        Set(days.flatMap { day in
            day.tasks.filter { task in
                !task.status.isFinished && !day.completedTasks.contains { $0.id == task.id }
            }.map(\.id)
        }).count
    }
    /// A recurring task is complete here only when every visible instance is complete.
    var completedCount: Int { totalCount - remainingCount }
    var occurrenceCount: Int { days.reduce(0) { $0 + $1.totalCount } }
    var completedOccurrenceCount: Int { days.reduce(0) { $0 + $1.completedCount } }
    var plannedDuration: TimeInterval { days.reduce(0) { $0 + $1.plannedDuration } }
    var actualDuration: TimeInterval { days.reduce(0) { $0 + $1.actualDuration } }

    /// Explicit scheduling can bring backlog into a future day. Merely being
    /// overdue does not make that backlog a member of the day's task list.
    func planningCandidates(on day: Date, calendar: Calendar? = nil) -> [GTDTask] {
        let calendar = calendar ?? projectionCalendar
        guard let snapshot = days.first(where: { calendar.isDate($0.day, inSameDayAs: day) }) else { return [] }
        let scheduledIDs = Set(snapshot.planBlocks.map(\.taskID))
        return workspaceCandidates.filter { task in
            !scheduledIDs.contains(task.id)
                && TaskDayRules.canSchedule(task, on: day, calendar: calendar)
        }
    }

    fileprivate init(horizon: PlanningHorizon, days: [TodayExecutionSnapshot], tasks: [GTDTask], workspaceCandidates: [GTDTask], calendar: Calendar) {
        self.horizon = horizon
        self.days = days
        self.tasks = tasks
        self.workspaceCandidates = workspaceCandidates
        self.projectionCalendar = calendar
        let scheduledIDs = Set(days.flatMap { $0.planBlocks.map(\.taskID) })
        self.planningCandidates = workspaceCandidates.filter { task in
            !scheduledIDs.contains(task.id) && days.contains { day in
                TaskDayRules.canSchedule(task, on: day.day, calendar: calendar)
            }
        }
    }
}

enum PlanningHorizonProjection {
    static func make(
        tasks: [GTDTask],
        timeEntries: [TimeEntry],
        horizon: PlanningHorizon,
        workspaceID: UUID,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> PlanningHorizonSnapshot {
        let days = horizon.days(relativeTo: now, calendar: calendar).map { day in
            TodayExecutionProjection.make(
                tasks: tasks, timeEntries: timeEntries, day: day,
                workspaceID: workspaceID, now: now, calendar: calendar
            )
        }
        var seenIDs: Set<UUID> = []
        let uniqueTasks = days.flatMap(\.tasks).filter { seenIDs.insert($0.id).inserted }
            .sorted(by: TaskDisplayOrdering.flatList)
        let candidates = tasks.filter { $0.workspaceID == workspaceID && !$0.status.isFinished }
            .sorted(by: TaskDisplayOrdering.flatList)
        return PlanningHorizonSnapshot(horizon: horizon, days: days, tasks: uniqueTasks, workspaceCandidates: candidates, calendar: calendar)
    }
}

/// DateInterval.contains includes its end; planning deliberately uses [start, end).
enum TaskDayRules {
    static func contains(_ date: Date, in interval: DateInterval) -> Bool {
        date >= interval.start && date < interval.end
    }

    static func overlaps(start: Date, end: Date, interval: DateInterval) -> Bool {
        end > start && end > interval.start && start < interval.end
    }

    static func planIntersects(_ task: GTDTask, interval: DateInterval) -> Bool {
        guard let start = task.plannedStart else { return false }
        guard let end = task.plannedEnd else { return contains(start, in: interval) }
        return overlaps(start: start, end: end, interval: interval)
    }

    static func isSkipped(_ task: GTDTask, on day: Date, calendar: Calendar) -> Bool {
        TodayExecutionProjection.isDailyRecurring(task)
            && task.skippedInstances.contains(TodayExecutionProjection.completionToken(for: day, calendar: calendar))
    }

    static func canSchedule(_ task: GTDTask, on day: Date, calendar: Calendar) -> Bool {
        guard !task.status.isFinished,
              !TodayExecutionProjection.isCompleted(task, on: day, calendar: calendar),
              !isSkipped(task, on: day, calendar: calendar) else { return false }
        if TodayExecutionProjection.isDailyRecurring(task), let start = task.plannedStart {
            guard let interval = calendar.dateInterval(of: .day, for: day) else { return false }
            return start < interval.end
        }
        return true
    }

    static func clippedEntry(_ entry: TimeEntry, to interval: DateInterval) -> TimeEntry? {
        guard overlaps(start: entry.startedAt, end: entry.endedAt, interval: interval) else { return nil }
        var clipped = entry
        clipped.startedAt = max(entry.startedAt, interval.start)
        clipped.endedAt = min(entry.endedAt, interval.end)
        if let activeSeconds = entry.activeSeconds {
            // Persisted timers retain total active seconds, not pause segments.
            // Prorate across the wall-clock span rather than counting the whole
            // session on every day. This preserves the stored session total.
            let fraction = clipped.endedAt.timeIntervalSince(clipped.startedAt)
                / entry.endedAt.timeIntervalSince(entry.startedAt)
            clipped.activeSeconds = max(0, activeSeconds) * fraction
        }
        return clipped
    }
}

extension AppModel {
    func planningHorizonSnapshot(
        for horizon: PlanningHorizon,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> PlanningHorizonSnapshot {
        _ = taskRevision
        return PlanningHorizonProjection.make(
            tasks: database.tasks, timeEntries: database.timeEntries, horizon: horizon,
            workspaceID: selection.selectedWorkspaceID, now: now, calendar: calendar
        )
    }
}
