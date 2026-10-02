import CoreGraphics
import Foundation

extension AppModel {
    /// Backlog appears here only after an explicit scheduling action, not in
    /// every calendar cell. Candidates are resolved against canonical state.
    func dayPlanningCandidates(on day: Date, now: Date = .now, calendar: Calendar = .current) -> [GTDTask] {
        _ = taskRevision
        let snapshot = todayExecutionSnapshot(on: day, now: now, calendar: calendar, includeOverdueBacklog: false)
        let scheduledIDs = Set(snapshot.planBlocks.map(\.taskID))
        return currentTasks.filter {
            TaskDayRules.canSchedule($0, on: day, calendar: calendar)
                && !scheduledIDs.contains($0.id)
        }.sorted(by: TaskDisplayOrdering.flatList)
    }
}

/// A civil-clock timeline has one row per displayed clock hour. Clip only
/// geometry; callers retain original records for editing and persistence.
enum DayTimelineLayout {
    static func visibleInterval(day: Date, startHour: Int, endHour: Int, calendar: Calendar = .current) -> DateInterval? {
        guard let dayInterval = calendar.dateInterval(of: .day, for: day),
              let start = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: dayInterval.start),
              let end = endHour == 24 ? dayInterval.end
                : calendar.date(bySettingHour: endHour, minute: 0, second: 0, of: dayInterval.start),
              end > start else { return nil }
        return DateInterval(start: start, end: end)
    }

    static func clipped(start: Date, end: Date, to interval: DateInterval) -> DateInterval? {
        guard TaskDayRules.overlaps(start: start, end: end, interval: interval) else { return nil }
        return DateInterval(start: max(start, interval.start), end: min(end, interval.end))
    }

    static func yOffset(for date: Date, in interval: DateInterval, startHour: Int, endHour: Int, hourHeight: CGFloat, calendar: Calendar = .current) -> CGFloat {
        if date <= interval.start { return 0 }
        let fullHeight = CGFloat(endHour - startHour) * hourHeight
        if date >= interval.end { return fullHeight }
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        let minutes = Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0)) + Double(parts.second ?? 0) / 60
        return min(fullHeight, max(0, CGFloat(minutes / 60 - Double(startHour)) * hourHeight))
    }
}

/// Pauses affect effective duration, not the wall-clock position of a session.
enum ActiveTimerDisplayRules {
    static func wallClockInterval(for timer: ActiveTimer, now: Date) -> DateInterval? {
        let end = timer.pausedAt ?? now
        guard end >= timer.sessionStartedAt else { return nil }
        return DateInterval(start: timer.sessionStartedAt, end: max(end, timer.sessionStartedAt.addingTimeInterval(1)))
    }

    static func targetDate(for timer: ActiveTimer, elapsed: TimeInterval, now: Date) -> Date? {
        guard timer.mode == .pomodoro, timer.pausedAt == nil,
              let target = timer.targetSeconds, elapsed < target else { return nil }
        return now.addingTimeInterval(max(0, target - elapsed))
    }
}

/// Merge only fields edited in this presentation. A second window must not
/// undo a newer time range merely because the first window edits a note.
enum TimeEntryEditRules {
    static func merge(original: TimeEntry, draft: TimeEntry, current: TimeEntry) -> TimeEntry? {
        guard original.id == draft.id, draft.id == current.id,
              original.workspaceID == draft.workspaceID, draft.workspaceID == current.workspaceID else { return nil }
        func conflicts<T: Equatable>(_ original: T, _ draft: T, _ current: T) -> Bool {
            draft != original && current != original && draft != current
        }
        let changedTimes = draft.startedAt != original.startedAt || draft.endedAt != original.endedAt
        let concurrentTimes = current.startedAt != original.startedAt || current.endedAt != original.endedAt
        if changedTimes && concurrentTimes && (draft.startedAt != current.startedAt || draft.endedAt != current.endedAt) { return nil }
        guard !conflicts(original.taskID, draft.taskID, current.taskID),
              !conflicts(original.source, draft.source, current.source),
              !conflicts(original.note, draft.note, current.note) else { return nil }
        var merged = current
        if changedTimes { merged.startedAt = draft.startedAt; merged.endedAt = draft.endedAt }
        if draft.taskID != original.taskID { merged.taskID = draft.taskID; merged.title = draft.title }
        if draft.source != original.source { merged.source = draft.source; merged.pomodoroPhase = draft.pomodoroPhase }
        if draft.note != original.note { merged.note = draft.note }
        return merged
    }
}
