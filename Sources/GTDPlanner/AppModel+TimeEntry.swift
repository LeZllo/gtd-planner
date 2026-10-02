import Foundation

extension AppModel {
    /// Adds a manual actual-focus record. Actual activity is intentionally
    /// separate from task planning fields; this method never changes a task's
    /// planned start, planned end, or deadline.
    @discardableResult
    func addTimeEntry(
        workspaceID: UUID,
        taskID: UUID?,
        startedAt: Date,
        endedAt: Date,
        source: TimeEntrySource = .manual,
        note: String = "",
        now: Date = .now
    ) -> TimeEntry? {
        guard endedAt > startedAt, endedAt <= now,
              !hasTimeEntryConflict(
                  workspaceID: workspaceID,
                  startedAt: startedAt,
                  endedAt: endedAt
              ) else { return nil }

        let title = taskID.flatMap(task(withID:))?.title ?? "无任务专注"
        let entry = TimeEntry(
            workspaceID: workspaceID,
            taskID: taskID,
            title: title,
            startedAt: startedAt,
            endedAt: endedAt,
            source: source,
            pomodoroPhase: source == .pomodoro ? .focus : nil,
            note: note,
            activeSeconds: endedAt.timeIntervalSince(startedAt)
        )
        database.timeEntries.append(entry)
        appendLog(
            action: "补录实际专注",
            target: entry.title,
            detail: "\(entry.startedAt.formatted(date: .abbreviated, time: .shortened)) – \(entry.endedAt.formatted(date: .omitted, time: .shortened))"
        )
        scheduleSave()
        return entry
    }

    /// Updates only the actual-focus record. The caller may change its task,
    /// note, and time range, but never its workspace identity or source
    /// semantics through a task-planning mutation.
    @discardableResult
    func updateTimeEntry(_ value: TimeEntry, now: Date = .now) -> Bool {
        guard let index = database.timeEntries.firstIndex(where: { $0.id == value.id }),
              database.timeEntries[index].workspaceID == value.workspaceID,
              value.endedAt > value.startedAt,
              (value.endedAt <= now || (value.startedAt == database.timeEntries[index].startedAt && value.endedAt == database.timeEntries[index].endedAt)),
              !hasTimeEntryConflict(
                  workspaceID: value.workspaceID,
                  startedAt: value.startedAt,
                  endedAt: value.endedAt,
                  excluding: value.id
              ) else {
            return false
        }

        var updated = value
        // Once a record's boundaries are explicitly edited, its displayed
        // actual duration follows the edited range. This also prevents a
        // paused timer's old active-seconds value from surviving a resize.
        let original = database.timeEntries[index]
        if updated.startedAt != original.startedAt || updated.endedAt != original.endedAt {
            updated.activeSeconds = updated.endedAt.timeIntervalSince(updated.startedAt)
        } else {
            updated.activeSeconds = original.activeSeconds
        }
        database.timeEntries[index] = updated
        appendLog(
            action: "编辑实际专注",
            target: updated.title,
            detail: "时间 \(updated.startedAt.formatted(date: .abbreviated, time: .shortened)) – \(updated.endedAt.formatted(date: .omitted, time: .shortened))"
        )
        scheduleSave()
        return true
    }

    /// Removes a completed actual-focus record. Running timers are not
    /// represented by TimeEntry and therefore cannot be deleted here.
    @discardableResult
    func deleteTimeEntry(withID id: UUID) -> Bool {
        guard let index = database.timeEntries.firstIndex(where: { $0.id == id }) else {
            return false
        }
        let removed = database.timeEntries.remove(at: index)
        appendLog(action: "删除实际专注", target: removed.title, detail: "记录 ID \(id.uuidString)")
        scheduleSave()
        return true
    }

    func focusTaskCandidates(in workspaceID: UUID) -> [GTDTask] {
        _ = taskRevision
        return database.tasks
            .filter { $0.workspaceID == workspaceID }
            .sorted(by: TaskDisplayOrdering.flatList)
    }

    /// Actual records must not occupy the same wall-clock interval. An active
    /// timer is also included so a backfill cannot overlap a session that will
    /// become a `TimeEntry` when the user stops it.
    func hasTimeEntryConflict(
        workspaceID: UUID,
        startedAt: Date,
        endedAt: Date,
        excluding entryID: UUID? = nil,
        now: Date = .now
    ) -> Bool {
        guard endedAt > startedAt else { return true }

        let overlapsStoredEntry = database.timeEntries.contains { entry in
            entry.workspaceID == workspaceID
                && entry.id != entryID
                && entry.endedAt > startedAt
                && entry.startedAt < endedAt
        }
        if overlapsStoredEntry { return true }

        guard let timer = database.activeTimer,
              (timer.workspaceID ?? selection.selectedWorkspaceID) == workspaceID else {
            return false
        }
        let activeEnd = max(timer.sessionStartedAt, timer.pausedAt ?? now)
        return activeEnd > startedAt && timer.sessionStartedAt < endedAt
    }
}
