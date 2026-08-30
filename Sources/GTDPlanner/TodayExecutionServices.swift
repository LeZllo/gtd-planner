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
        let start = calendar.date(byAdding: .minute, value: lower, to: dayStart) ?? dayStart
        let end = calendar.date(byAdding: .minute, value: upper, to: dayStart)
            ?? start.addingTimeInterval(TimeInterval(step * 60))
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
            block.end > selection.start && block.start < selection.end
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
    var actualDuration: TimeInterval { actualEntries.reduce(0) { $0 + $1.duration } }

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
        calendar: Calendar = .current
    ) -> TodayExecutionSnapshot {
        guard let dayInterval = calendar.dateInterval(of: .day, for: day) else {
            return TodayExecutionSnapshot(
                day: day,
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
            return isRelevant(task, on: day, now: now, calendar: calendar)
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
                && planContains($0, interval: dayInterval)
        }
        let completeWithinTasks = unfinishedTasks.filter {
            isMultiDayPlan($0, calendar: calendar)
                && $0.planRangeIntent == .completeWithin
                && planContains($0, interval: dayInterval)
        }
        let overdueTasks = unfinishedTasks.filter { task in
            task.deadline.map { $0 < now } ?? false
        }
        let deadlineTasks = unfinishedTasks.filter { task in
            task.deadline.map(dayInterval.contains) ?? false
        }
        let drawerTasks = unfinishedTasks.filter { !scheduledTaskIDs.contains($0.id) }

        let actualEntries = timeEntries
            .filter {
                $0.workspaceID == workspaceID
                    && $0.endedAt > dayInterval.start
                    && $0.startedAt < dayInterval.end
            }
            .sorted { $0.startedAt < $1.startedAt }

        return TodayExecutionSnapshot(
            day: dayInterval.start,
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
        calendar: Calendar = .current
    ) -> Bool {
        guard let interval = calendar.dateInterval(of: .day, for: day) else { return false }
        if isCompleted(task, on: day, calendar: calendar) { return true }
        guard !task.status.isFinished else { return false }
        if planContains(task, interval: interval) { return true }
        if task.executionSlots.contains(where: { $0.end > interval.start && $0.start < interval.end }) { return true }
        if let deadline = task.deadline, interval.contains(deadline) || deadline < now { return true }
        if isDailyRecurring(task) {
            guard let plannedStart = task.plannedStart else { return true }
            return plannedStart < interval.end
        }
        return false
    }

    static func isMultiDayPlan(_ task: GTDTask, calendar: Calendar = .current) -> Bool {
        guard let start = task.plannedStart, let end = task.plannedEnd else { return false }
        return !calendar.isDate(start, inSameDayAs: end)
    }

    static func isDailyRecurring(_ task: GTDTask) -> Bool {
        task.recurrence
            .uppercased()
            .split(separator: ";")
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

    private static func planContains(_ task: GTDTask, interval: DateInterval) -> Bool {
        guard let start = task.plannedStart else { return false }
        let end = task.plannedEnd ?? start
        return end >= interval.start && start < interval.end
    }

    private static func planBlocks(
        for task: GTDTask,
        in interval: DateInterval,
        calendar: Calendar
    ) -> [TodayPlanBlock] {
        var blocks = task.executionSlots.compactMap { slot -> TodayPlanBlock? in
            guard slot.end > slot.start, slot.end > interval.start, slot.start < interval.end else { return nil }
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

        if task.plannedPrecision == .minute,
           !isMultiDayPlan(task, calendar: calendar),
           let plannedStart = task.plannedStart,
           plannedStart < interval.end,
           (task.plannedEnd ?? plannedStart) >= interval.start {
            let clippedStart = max(plannedStart, interval.start)
            let explicitEnd = task.plannedEnd.map { min($0, interval.end) }
            let displayEnd = explicitEnd ?? min(clippedStart.addingTimeInterval(30 * 60), interval.end)
            blocks.append(
                TodayPlanBlock(
                    id: .init(taskID: task.id, source: .taskPlan, slotID: nil),
                    taskID: task.id,
                    title: task.title,
                    start: clippedStart,
                    end: max(displayEnd, clippedStart.addingTimeInterval(60)),
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
        calendar: Calendar = .current
    ) -> TodayExecutionSnapshot {
        _ = taskRevision
        return TodayExecutionProjection.make(
            tasks: database.tasks,
            timeEntries: database.timeEntries,
            day: day,
            workspaceID: selection.selectedWorkspaceID,
            now: now,
            calendar: calendar
        )
    }

    @discardableResult
    func addExecutionSlot(taskID: UUID, start: Date, end: Date) -> TaskExecutionSlot? {
        guard end > start, var task = task(withID: taskID) else { return nil }
        let slot = TaskExecutionSlot(start: start, end: end)
        task.executionSlots.append(slot)
        task.executionSlots.sort { $0.start < $1.start }
        updateTask(task)
        return slot
    }

    @discardableResult
    func removeExecutionSlot(taskID: UUID, slotID: UUID) -> Bool {
        guard var task = task(withID: taskID) else { return false }
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
