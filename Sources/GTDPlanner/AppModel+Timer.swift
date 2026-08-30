import Foundation

extension AppModel {
    static let minimumPomodoroSeconds: TimeInterval = 60
    static let maximumPomodoroSeconds: TimeInterval = 180 * 60

    func normalizedPomodoroDuration(_ duration: TimeInterval) -> TimeInterval {
        let minuteCount = (duration / 60).rounded()
        return min(
            Self.maximumPomodoroSeconds,
            max(Self.minimumPomodoroSeconds, minuteCount * 60)
        )
    }

    func startStopwatch(for task: GTDTask?, at now: Date = .now) {
        guard database.activeTimer == nil else { return }
        database.activeTimer = ActiveTimer(
            mode: .stopwatch,
            workspaceID: task?.workspaceID ?? selection.selectedWorkspaceID,
            taskID: task?.id,
            title: task?.title ?? "无任务专注",
            sessionStartedAt: now,
            startedAt: now,
            pausedAt: nil,
            accumulatedSeconds: 0,
            targetSeconds: nil,
            phase: nil
        )
        scheduleSave(domain: .timer)
    }

    func startPomodoro(
        for task: GTDTask?,
        duration: TimeInterval = 25 * 60,
        at now: Date = .now
    ) {
        guard database.activeTimer == nil else { return }
        let normalizedDuration = normalizedPomodoroDuration(duration)
        database.activeTimer = ActiveTimer(
            mode: .pomodoro,
            workspaceID: task?.workspaceID ?? selection.selectedWorkspaceID,
            taskID: task?.id,
            title: task?.title ?? "无任务专注",
            sessionStartedAt: now,
            startedAt: now,
            pausedAt: nil,
            accumulatedSeconds: 0,
            targetSeconds: normalizedDuration,
            phase: .focus
        )
        scheduleSave(domain: .timer)
    }

    func timerElapsed(at now: Date = .now) -> TimeInterval {
        guard let timer = database.activeTimer else { return 0 }
        return elapsed(for: timer, at: now)
    }

    func pauseTimer(at now: Date = .now) {
        guard var timer = database.activeTimer, timer.pausedAt == nil else { return }
        timer.accumulatedSeconds = elapsed(for: timer, at: now)
        timer.pausedAt = now
        database.activeTimer = timer
        scheduleSave(domain: .timer)
    }

    func resumeTimer(at now: Date = .now) {
        guard var timer = database.activeTimer, timer.pausedAt != nil else { return }
        timer.startedAt = now
        timer.pausedAt = nil
        database.activeTimer = timer
        scheduleSave(domain: .timer)
    }

    @discardableResult
    func stopTimer(at endedAt: Date = .now) -> TimeEntry? {
        guard let timer = database.activeTimer else { return nil }
        return finishTimer(timer, endedAt: endedAt, elapsed: elapsed(for: timer, at: endedAt))
    }

    /// Returns whether a Pomodoro has reached its target. Reaching zero does
    /// not mutate the timer: the user can continue in overtime until they
    /// explicitly choose to stop and record the session.
    func pomodoroTargetReached(at now: Date = .now) -> Bool {
        guard let timer = database.activeTimer,
              timer.mode == .pomodoro,
              timer.phase == .focus,
              let target = timer.targetSeconds else { return false }
        return elapsed(for: timer, at: now) >= target
    }

    /// Kept as a source-compatible no-op for older callers. Pomodoros no
    /// longer auto-complete at their target; `stopTimer(at:)` is the only
    /// operation that creates the actual focus entry.
    @discardableResult
    func completePomodoroIfNeeded(at now: Date = .now) -> TimeEntry? {
        nil
    }

    private func elapsed(for timer: ActiveTimer, at now: Date) -> TimeInterval {
        if timer.pausedAt != nil {
            return max(0, timer.accumulatedSeconds)
        }
        let segmentEnd = timer.pausedAt ?? now
        return max(0, timer.accumulatedSeconds + segmentEnd.timeIntervalSince(timer.startedAt))
    }

    private func finishTimer(_ timer: ActiveTimer, endedAt: Date, elapsed: TimeInterval) -> TimeEntry {
        let clampedElapsed = max(0, elapsed)
        let sessionStart = timer.sessionStartedAt
        let sessionEnd = max(sessionStart, timer.pausedAt ?? endedAt)
        let entry = TimeEntry(
            workspaceID: timer.workspaceID ?? selection.selectedWorkspaceID,
            taskID: timer.taskID,
            title: timer.title,
            startedAt: sessionStart,
            endedAt: sessionEnd,
            source: TimeEntrySource(timerMode: timer.mode),
            pomodoroPhase: timer.phase,
            activeSeconds: clampedElapsed
        )
        database.timeEntries.append(entry)
        database.activeTimer = nil
        scheduleSave()
        return entry
    }
}
