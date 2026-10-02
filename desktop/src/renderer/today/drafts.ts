import { canScheduleTaskOnDay, dayBounds, dayKey, sameID, type ActiveTimer, type GTDDatabase, type TimeEntry, type TimeEntryPatch } from '../../domain';

export const inputDateTime = (value: string) => {
  const date = new Date(value);
  return `${dayKey(date)}T${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}`;
};
/** Resolve unchanged fields before comparing instants: minute-precision controls
 * must not destroy imported seconds, offsets, or a repeated DST hour. */
export function resolveActualDraftRange(startDraft: string, endDraft: string, originalStart: string, originalEnd: string) {
  const start = startDraft === inputDateTime(originalStart) ? new Date(originalStart) : new Date(startDraft);
  const end = endDraft === inputDateTime(originalEnd) ? new Date(originalEnd) : new Date(endDraft);
  if (!Number.isFinite(start.getTime()) || !Number.isFinite(end.getTime()) || end <= start) return null;
  return { startedAt: startDraft === inputDateTime(originalStart) ? originalStart : start.toISOString(), endedAt: endDraft === inputDateTime(originalEnd) ? originalEnd : end.toISOString() };
}
/** A paused session ending before this day has no current-day geometry. */
export function visibleTimerInterval(timer: ActiveTimer | null | undefined, tasks: GTDDatabase['tasks'], workspaceID: string, day: string, now: Date) {
  if (!timer) return null;
  const owner = timer.workspaceID || tasks.find(task => sameID(task.id, timer.taskID))?.workspaceID;
  if (!owner || !sameID(owner, workspaceID)) return null;
  const [dayStart, dayEnd] = dayBounds(day);
  const start = Math.max(dayStart, Date.parse(timer.sessionStartedAt));
  const end = Math.min(dayEnd, Date.parse(timer.pausedAt || now.toISOString()));
  return end > start ? { start: new Date(start).toISOString(), end: new Date(end).toISOString() } : null;
}

export interface ActualEntryDraft { start: string; end: string; taskID: string; title: string; note: string }
/** Send only intentional edits; opening and saving an imported record is a no-op. */
export function buildActualEntryPatch(entry: TimeEntry, draft: ActualEntryDraft, fallbackTitle = '无任务专注'): TimeEntryPatch | null {
  const interval = resolveActualDraftRange(draft.start, draft.end, entry.startedAt, entry.endedAt);
  if (!interval) return null;
  const patch: TimeEntryPatch = {};
  if (interval.startedAt !== entry.startedAt) patch.startedAt = interval.startedAt;
  if (interval.endedAt !== entry.endedAt) patch.endedAt = interval.endedAt;
  if (!sameID(draft.taskID || null, entry.taskID || null)) patch.taskID = draft.taskID || null;
  if (draft.title !== entry.title) patch.title = draft.title.trim() || fallbackTitle;
  if (draft.note !== entry.note) patch.note = draft.note;
  return patch;
}

export function preferredSchedulableTaskID(tasks: GTDDatabase['tasks'], workspaceID: string, day: string, preferred?: string | null): string {
  return tasks.find(task => sameID(task.id, preferred) && sameID(task.workspaceID, workspaceID) && canScheduleTaskOnDay(task, day))?.id || '';
}

/** Shift is a fine-snap alternative where the desktop captures Alt-drag. */
export function usesFineSnap(modifiers: { altKey: boolean; shiftKey: boolean }): boolean {
  return modifiers.altKey || modifiers.shiftKey;
}
