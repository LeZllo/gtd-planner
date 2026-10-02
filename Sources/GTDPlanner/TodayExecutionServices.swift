import CoreGraphics
import Foundation

enum TodayTaskFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case progress
    case completeWithin
    case overdue

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部"
        case .progress: "跨日推进"
        case .completeWithin: "区间内完成"
        case .overdue: "逾期"
        }
    }
}

enum TodayScheduleLane: String, Hashable, Sendable {
    case plan
    case actual

    var title: String {
        switch self {
        case .plan: "计划"
        case .actual: "实际"
        }
    }
}

enum TodayActualDraftAction: String, CaseIterable, Identifiable, Hashable, Sendable {
    case manual
    case pomodoro

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual: "补录实际"
        case .pomodoro: "开始番茄钟"
        }
    }

    static func defaultAction(for interval: DateInterval, now: Date = .now) -> Self {
        interval.end <= now ? .manual : .pomodoro
    }
}

struct TodayScheduleDragSelection: Identifiable, Equatable, Sendable {
    let id: UUID
    let lane: TodayScheduleLane
    let start: Date
    let end: Date

    init(id: UUID = UUID(), lane: TodayScheduleLane, start: Date, end: Date) {
        self.id = id
        self.lane = lane
        self.start = start
        self.end = end
    }

    var interval: DateInterval { DateInterval(start: start, end: end) }
    var duration: TimeInterval { end.timeIntervalSince(start) }
}

private enum TodayWallClockTime {
    static func date(on day: Date, hour: Int, minute: Int, second: Int, calendar: Calendar) -> Date? {
        let dayStart = calendar.startOfDay(for: day)
        // bySettingHour downgrades the preserving policy to .nextTime. Use
        // nextDate directly so a missing 02:30 becomes 03:30, not 03:00.
        // Search before midnight because nextDate excludes its starting date.
        guard let result = calendar.nextDate(
            after: dayStart.addingTimeInterval(-1),
            matching: DateComponents(hour: hour, minute: minute, second: second),
            matchingPolicy: .nextTimePreservingSmallerComponents,
            repeatedTimePolicy: .first,
            direction: .forward
        ), calendar.isDate(result, inSameDayAs: dayStart) else { return nil }
        return result
    }
}

enum TodayScheduleDragRules {
    static let standardSnapMinutes = 15
    static let fineSnapMinutes = 5

    static func selection(
        lane: TodayScheduleLane,
        day: Date,
        startY: CGFloat,
        currentY: CGFloat,
        startHour: Int,
        endHour: Int,
        hourHeight: CGFloat,
        fineSnap: Bool,
        calendar: Calendar = .current,
        id: UUID = UUID()
    ) -> TodayScheduleDragSelection {
        let step = fineSnap ? fineSnapMinutes : standardSnapMinutes
        let visibleStart = startHour * 60
        let visibleEnd = endHour * 60

        func snappedMinute(for y: CGFloat) -> Int {
            let clampedY = min(CGFloat(endHour - startHour) * hourHeight, max(0, y))
            let rawMinute = Double(visibleStart) + Double(clampedY / hourHeight) * 60
            let snapped = Int((rawMinute / Double(step)).rounded()) * step
            return min(visibleEnd, max(visibleStart, snapped))
        }

        let anchor = snappedMinute(for: startY)
        let current = snappedMinute(for: currentY)
        var lower = min(anchor, current)
        var upper = max(anchor, current)

        if lower == upper {
            if upper + step <= visibleEnd {
                upper += step
            } else {
                lower = max(visibleStart, lower - step)
            }
        }

        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.dateInterval(of: .day, for: day)?.end
            ?? calendar.date(byAdding: .day, value: 1, to: dayStart)
            ?? dayStart.addingTimeInterval(24 * 3_600)
        func wallClockTime(for minute: Int) -> Date {
            if minute >= 24 * 60 { return dayEnd }
            return TodayWallClockTime.date(
                on: dayStart, hour: minute / 60, minute: minute % 60, second: 0, calendar: calendar
            ) ?? dayStart
        }
        var start = wallClockTime(for: lower)
        var end = wallClockTime(for: upper)
        if end <= start {
            // A missing spring-forward time may normalize past the selected
            // end. Preserve a positive selection without leaving this day.
            end = min(dayEnd, start.addingTimeInterval(TimeInterval(max(step, upper - lower) * 60)))
            if end <= start {
                end = dayEnd
                start = max(dayStart, dayEnd.addingTimeInterval(-TimeInterval(step * 60)))
            }
        }
        return TodayScheduleDragSelection(id: id, lane: lane, start: start, end: end)
    }

    /// Vertical position carries time, while horizontal position only chooses
    /// plan versus actual. Anchor to the lane center and the release time so a
    /// scroll container cannot push the popover to either outer edge.
    static func popoverAnchor(
        for lane: TodayScheduleLane,
        location: CGPoint,
        laneWidth: CGFloat,
        totalHeight: CGFloat
    ) -> CGPoint {
        let safeLaneWidth = max(1, laneWidth)
        let laneOriginX = lane == .plan ? CGFloat.zero : safeLaneWidth
        let x = laneOriginX + safeLaneWidth / 2
        let y = min(max(1, totalHeight), max(0, location.y))
        return CGPoint(x: x, y: y)
    }
}

enum TodayScheduleTaskCandidates {
    static func make(
        snapshot: TodayExecutionSnapshot,
        selectedTaskID: UUID?
    ) -> [GTDTask] {
        let completedIDs = Set(snapshot.completedTasks.map(\.id))
        return snapshot.tasks
            .filter { !completedIDs.contains($0.id) && !$0.status.isFinished }
            .sorted { lhs, rhs in
                if lhs.id == selectedTaskID { return true }
                if rhs.id == selectedTaskID { return false }
                return TaskDisplayOrdering.flatList(lhs, rhs)
            }
    }
}

enum TodayScheduleConflictRules {
    static func planConflicts(
        with selection: TodayScheduleDragSelection,
        blocks: [TodayPlanBlock]
    ) -> Bool {
        blocks.contains { block in
            if block.isPoint {
                return block.start >= selection.start && block.start < selection.end
            }
            return block.end > selection.start && block.start < selection.end
        }
    }
}

struct PomodoroClockState: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case remaining
        case overtime
    }

    let phase: Phase
    let seconds: TimeInterval

    static func make(targetSeconds: TimeInterval, elapsed: TimeInterval) -> Self {
        if elapsed < targetSeconds {
            return Self(phase: .remaining, seconds: max(0, targetSeconds - elapsed))
        }
        return Self(phase: .overtime, seconds: max(0, elapsed - targetSeconds))
    }

    var text: String {
        switch phase {
        case .remaining:
            "剩余 \(Self.formatted(seconds))"
        case .overtime:
            "超时 +\(Self.formatted(seconds))"
        }
    }

    private static func formatted(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let remainingSeconds = total % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
}

struct TodayPlanBlock: Identifiable, Hashable, Sendable {
    struct ID: Hashable, Sendable {
        enum Source: String, Hashable, Sendable {
            case taskPlan
            case executionSlot
        }

        let taskID: UUID
        let source: Source
        let slotID: UUID?
    }

    let id: ID
    let taskID: UUID
    let title: String
    let start: Date
    let end: Date
    let plannedDuration: TimeInterval
    let isPoint: Bool
}

struct TodayExecutionSnapshot: Equatable, Sendable {
    let day: Date
    let dayInterval: DateInterval?
    let tasks: [GTDTask]
    let completedTasks: [GTDTask]
    let drawerTasks: [GTDTask]
    let crossDayProgressTasks: [GTDTask]
    let completeWithinTasks: [GTDTask]
    let overdueTasks: [GTDTask]
    let deadlineTasks: [GTDTask]
    let planBlocks: [TodayPlanBlock]
    let actualEntries: [TimeEntry]

    var totalCount: Int { tasks.count }
    var completedCount: Int { completedTasks.count }
    var remainingCount: Int { max(0, totalCount - completedCount) }
    var overdueCount: Int { overdueTasks.count }
    var waitingCount: Int { drawerTasks.count }
    var plannedDuration: TimeInterval { planBlocks.reduce(0) { $0 + $1.plannedDuration } }
    var actualDuration: TimeInterval {
        guard let dayInterval else { return 0 }
        return actualEntries.reduce(0) { $0 + (TaskDayRules.clippedEntry($1, to: dayInterval)?.duration ?? 0) }
    }

    func filteringTasks(to ids: Set<UUID>) -> TodayExecutionSnapshot {
        TodayExecutionSnapshot(
            day: day, dayInterval: dayInterval,
            tasks: tasks.filter { ids.contains($0.id) },
            completedTasks: completedTasks.filter { ids.contains($0.id) },
            drawerTasks: drawerTasks.filter { ids.contains($0.id) },
            crossDayProgressTasks: crossDayProgressTasks.filter { ids.contains($0.id) },
            completeWithinTasks: completeWithinTasks.filter { ids.contains($0.id) },
            overdueTasks: overdueTasks.filter { ids.contains($0.id) },
            deadlineTasks: deadlineTasks.filter { ids.contains($0.id) },
            planBlocks: planBlocks.filter { ids.contains($0.taskID) },
            actualEntries: actualEntries.filter { $0.taskID.map(ids.contains) ?? false }
        )
    }

    func drawerTasks(for filter: TodayTaskFilter) -> [GTDTask] {
        switch filter {
        case .all:
            drawerTasks
        case .progress:
            drawerTasks.filter { task in
                crossDayProgressTasks.contains { $0.id == task.id }
            }
        case .completeWithin:
            drawerTasks.filter { task in
                completeWithinTasks.contains { $0.id == task.id }
            }
        case .overdue:
            drawerTasks.filter { task in
                overdueTasks.contains { $0.id == task.id }
            }
        }
    }

    func count(for filter: TodayTaskFilter) -> Int {
        drawerTasks(for: filter).count
    }
}

enum TodayExecutionProjection {
    static func make(
        tasks sourceTasks: [GTDTask],
        timeEntries: [TimeEntry],
        day: Date,
        workspaceID: UUID,
        now: Date = .now,
        calendar: Calendar = .current,
        includeOverdueBacklog: Bool = true
    ) -> TodayExecutionSnapshot {
        guard let dayInterval = calendar.dateInterval(of: .day, for: day) else {
            return TodayExecutionSnapshot(
                day: day,
                dayInterval: nil,
                tasks: [],
                completedTasks: [],
                drawerTasks: [],
                crossDayProgressTasks: [],
                completeWithinTasks: [],
                overdueTasks: [],
                deadlineTasks: [],
                planBlocks: [],
                actualEntries: []
            )
        }

        let workspaceTasks = sourceTasks.filter { $0.workspaceID == workspaceID }
        let relevantTasks = workspaceTasks.filter { task in
            guard task.status != .cancelled else { return false }
            return isRelevant(task, on: day, now: now, calendar: calendar, includeOverdueBacklog: includeOverdueBacklog)
        }
        .sorted { taskSort($0, $1, day: day, now: now, calendar: calendar) }

        let completedTasks = relevantTasks.filter {
            isCompleted($0, on: day, calendar: calendar)
        }
        let unfinishedTasks = relevantTasks.filter { task in
            !isCompleted(task, on: day, calendar: calendar) && !task.status.isFinished
        }

        let dailyPlanBlocks: [TodayPlanBlock] = relevantTasks
            .flatMap { Self.planBlocks(for: $0, in: dayInterval, calendar: calendar) }
            .sorted { lhs, rhs in
                if lhs.start != rhs.start { return lhs.start < rhs.start }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
        let scheduledTaskIDs = Set(dailyPlanBlocks.map(\.taskID))

        let crossDayProgressTasks = unfinishedTasks.filter {
            isMultiDayPlan($0, calendar: calendar)
                && $0.planRangeIntent == .progress
                && TaskDayRules.planIntersects($0, interval: dayInterval)
        }
        let completeWithinTasks = unfinishedTasks.filter {
            isMultiDayPlan($0, calendar: calendar)
                && $0.planRangeIntent == .completeWithin
                && TaskDayRules.planIntersects($0, interval: dayInterval)
        }
        let overdueTasks = unfinishedTasks.filter { task in
            task.deadline.map { $0 < now } ?? false
        }
        let deadlineTasks = unfinishedTasks.filter { task in
            task.deadline.map { TaskDayRules.contains($0, in: dayInterval) } ?? false
        }
        let drawerTasks = unfinishedTasks.filter { !scheduledTaskIDs.contains($0.id) }

        let actualEntries = timeEntries
            .filter {
                $0.workspaceID == workspaceID
                    && TaskDayRules.overlaps(start: $0.startedAt, end: $0.endedAt, interval: dayInterval)
            }
            .sorted { $0.startedAt < $1.startedAt }

        return TodayExecutionSnapshot(
            day: dayInterval.start,
            dayInterval: dayInterval,
            tasks: relevantTasks,
            completedTasks: completedTasks,
            drawerTasks: drawerTasks,
            crossDayProgressTasks: crossDayProgressTasks,
            completeWithinTasks: completeWithinTasks,
            overdueTasks: overdueTasks,
            deadlineTasks: deadlineTasks,
            planBlocks: dailyPlanBlocks,
            actualEntries: actualEntries
        )
    }

    static func isRelevant(
        _ task: GTDTask,
        on day: Date,
        now: Date = .now,
        calendar: Calendar = .current,
        includeOverdueBacklog: Bool = true
    ) -> Bool {
        guard task.status != .cancelled,
              let interval = calendar.dateInterval(of: .day, for: day) else { return false }
        if isCompleted(task, on: day, calendar: calendar) { return true }
        guard !task.status.isFinished else { return false }
        if isDailyRecurring(task) {
            guard !TaskDayRules.isSkipped(task, on: day, calendar: calendar) else { return false }
            guard let plannedStart = task.plannedStart else { return true }
            return plannedStart < interval.end
        }
        if TaskDayRules.planIntersects(task, interval: interval) { return true }
        if task.executionSlots.contains(where: { TaskDayRules.overlaps(start: $0.start, end: $0.end, interval: interval) }) { return true }
        if let deadline = task.deadline {
            if TaskDayRules.contains(deadline, in: interval) { return true }
            // Backlog belongs in Today. Browsing another day must not silently
            // schedule all already-overdue tasks on that day as well.
            if includeOverdueBacklog, calendar.isDate(day, inSameDayAs: now), deadline < now { return true }
        }
        return false
    }

    static func isMultiDayPlan(_ task: GTDTask, calendar: Calendar = .current) -> Bool {
        guard let start = task.plannedStart, let end = task.plannedEnd, end > start,
              let firstDay = calendar.dateInterval(of: .day, for: start) else { return false }
        return end > firstDay.end
    }

    static func isDailyRecurring(_ task: GTDTask) -> Bool {
        task.recurrence
            .uppercased()
            .replacingOccurrences(of: "RRULE:", with: "")
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .contains("FREQ=DAILY")
    }

    static func completionToken(for day: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: day)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    static func isCompleted(_ task: GTDTask, on day: Date, calendar: Calendar = .current) -> Bool {
        if isDailyRecurring(task) {
            let token = completionToken(for: day, calendar: calendar)
            return task.completedInstances.contains(token)
        }
        guard task.status == .done, let completedAt = task.completedAt else { return false }
        return calendar.isDate(completedAt, inSameDayAs: day)
    }

    private static func planBlocks(
        for task: GTDTask,
        in interval: DateInterval,
        calendar: Calendar
    ) -> [TodayPlanBlock] {
        var blocks = task.executionSlots.compactMap { slot -> TodayPlanBlock? in
            guard TaskDayRules.overlaps(start: slot.start, end: slot.end, interval: interval) else { return nil }
            let clippedStart = max(slot.start, interval.start)
            let clippedEnd = min(slot.end, interval.end)
            return TodayPlanBlock(
                id: .init(taskID: task.id, source: .executionSlot, slotID: slot.id),
                taskID: task.id,
                title: task.title,
                start: clippedStart,
                end: clippedEnd,
                plannedDuration: max(0, clippedEnd.timeIntervalSince(clippedStart)),
                isPoint: false
            )
        }

        var displayedTask = task
        if task.plannedPrecision == .minute, isDailyRecurring(task),
           !isMultiDayPlan(task, calendar: calendar), let anchor = task.plannedStart {
            let offset = calendar.dateComponents([.day], from: calendar.startOfDay(for: anchor), to: interval.start).day ?? 0
            if offset >= 0 {
                func shiftedTime(_ date: Date) -> Date? {
                    guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date)) else { return nil }
                    let components = calendar.dateComponents([.hour, .minute, .second], from: date)
                    return TodayWallClockTime.date(
                        on: day, hour: components.hour ?? 0, minute: components.minute ?? 0,
                        second: components.second ?? 0, calendar: calendar
                    )
                }
                displayedTask.plannedStart = shiftedTime(anchor)
                displayedTask.plannedEnd = task.plannedEnd.flatMap(shiftedTime)
                // A spring-forward gap can move 02:30 past an otherwise valid
                // 03:00 end. Keep the template's elapsed duration in that case
                // instead of silently dropping its planned block.
                if let start = displayedTask.plannedStart, let end = displayedTask.plannedEnd,
                   end <= start, let originalEnd = task.plannedEnd, originalEnd > anchor {
                    displayedTask.plannedEnd = start.addingTimeInterval(originalEnd.timeIntervalSince(anchor))
                }
            }
        }
        if displayedTask.plannedPrecision == .minute,
           !isMultiDayPlan(displayedTask, calendar: calendar),
           let plannedStart = displayedTask.plannedStart,
           TaskDayRules.planIntersects(displayedTask, interval: interval) {
            let clippedStart = max(plannedStart, interval.start)
            let explicitEnd = displayedTask.plannedEnd.map { min($0, interval.end) }
            let displayEnd = explicitEnd ?? min(clippedStart.addingTimeInterval(30 * 60), interval.end)
            blocks.append(
                TodayPlanBlock(
                    id: .init(taskID: task.id, source: .taskPlan, slotID: nil),
                    taskID: task.id,
                    title: task.title,
                    start: clippedStart,
                    end: displayEnd,
                    plannedDuration: explicitEnd.map { max(0, $0.timeIntervalSince(clippedStart)) } ?? 0,
                    isPoint: explicitEnd == nil
                )
            )
        }

        return blocks
    }

    private static func taskSort(
        _ lhs: GTDTask,
        _ rhs: GTDTask,
        day: Date,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        let lhsCompleted = isCompleted(lhs, on: day, calendar: calendar)
        let rhsCompleted = isCompleted(rhs, on: day, calendar: calendar)
        if lhsCompleted != rhsCompleted { return !lhsCompleted }
        let lhsOverdue = lhs.deadline.map { $0 < now } ?? false
        let rhsOverdue = rhs.deadline.map { $0 < now } ?? false
        if lhsOverdue != rhsOverdue { return lhsOverdue }
        return TaskDisplayOrdering.flatList(lhs, rhs)
    }
}

extension AppModel {
    func todayExecutionSnapshot(
        on day: Date = .now,
        now: Date = .now,
        calendar: Calendar = .current,
        includeOverdueBacklog: Bool = true
    ) -> TodayExecutionSnapshot {
        _ = taskRevision
        return TodayExecutionProjection.make(
            tasks: database.tasks,
            timeEntries: database.timeEntries,
            day: day,
            workspaceID: selection.selectedWorkspaceID,
            now: now,
            calendar: calendar,
            includeOverdueBacklog: includeOverdueBacklog
        )
    }

    @discardableResult
    func addExecutionSlot(taskID: UUID, start: Date, end: Date, calendar: Calendar = .current) -> TaskExecutionSlot? {
        guard end > start, var task = task(withID: taskID),
              !task.status.isFinished, task.workspaceID == selection.selectedWorkspaceID else { return nil }
        if TodayExecutionProjection.isDailyRecurring(task) {
            var day = calendar.startOfDay(for: start)
            while day < end {
                guard TaskDayRules.canSchedule(task, on: day, calendar: calendar),
                      let nextDay = calendar.date(byAdding: .day, value: 1, to: day), nextDay > day else { return nil }
                day = nextDay
            }
        }
        if let existing = task.executionSlots.first(where: { $0.start == start && $0.end == end }) {
            return existing
        }
        let slot = TaskExecutionSlot(start: start, end: end)
        task.executionSlots.append(slot)
        task.executionSlots.sort { $0.start < $1.start }
        updateTask(task)
        return slot
    }

    @discardableResult
    func removeExecutionSlot(taskID: UUID, slotID: UUID) -> Bool {
        guard var task = task(withID: taskID), task.workspaceID == selection.selectedWorkspaceID else { return false }
        let originalCount = task.executionSlots.count
        task.executionSlots.removeAll { $0.id == slotID }
        guard task.executionSlots.count != originalCount else { return false }
        updateTask(task)
        return true
    }

    func toggleTodayCompletion(taskID: UUID, on day: Date = .now, calendar: Calendar = .current) {
        guard var task = task(withID: taskID) else { return }
        guard TodayExecutionProjection.isDailyRecurring(task) else {
            toggleTask(taskID)
            return
        }

        let token = TodayExecutionProjection.completionToken(for: day, calendar: calendar)
        if task.completedInstances.contains(token) {
            task.completedInstances.removeAll { $0 == token }
        } else {
            task.completedInstances.append(token)
        }
        updateTask(task)
    }
}
