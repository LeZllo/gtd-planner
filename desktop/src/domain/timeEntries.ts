import { dayBounds, isISO } from './dates.js';
import { sameID, validateDatabase } from './validation.js';
import type { GTDDatabase, TimeEntry } from './types.js';

export interface ClippedTimeEntry { start: string; end: string; seconds: number; estimated: boolean }
/** Legacy paused sessions do not retain segments. Proration preserves the
 * saved active-seconds total; it is explicitly an estimate across days. */
export function clipTimeEntryToDay(entry: TimeEntry, day: string): ClippedTimeEntry | null {
  const [dayStart, dayEnd] = dayBounds(day), start = Date.parse(entry.startedAt), end = Date.parse(entry.endedAt);
  const clippedStart = Math.max(start, dayStart), clippedEnd = Math.min(end, dayEnd), overlap = clippedEnd - clippedStart;
  if (!(end > start) || !(overlap > 0)) return null;
  return { start: new Date(clippedStart).toISOString(), end: new Date(clippedEnd).toISOString(),
    seconds: entry.activeSeconds == null ? overlap / 1000 : Math.max(0, entry.activeSeconds) * overlap / (end - start),
    estimated: entry.activeSeconds != null && (start < dayStart || end > dayEnd) };
}
/** Finished actual focus only; plans and the currently running timer are excluded. */
export function actualFocusForDay(entries: readonly TimeEntry[], workspaceID: string, day: string): { seconds: number; estimated: boolean } {
  // Validate even when the workspace has no records.
  dayBounds(day); let seconds = 0, estimated = false;
  for (const entry of entries) {
    if (!sameID(entry.workspaceID, workspaceID)) continue;
    const clipped = clipTimeEntryToDay(entry, day);
    if (clipped) { seconds += clipped.seconds; estimated ||= clipped.estimated; }
  }
  return { seconds, estimated };
}
const checked = (db: GTDDatabase) => { validateDatabase(db); return db; };
function workspaceExists(db: GTDDatabase, workspaceID: string): string {
  const workspace = db.workspaces.find(w => sameID(w.id, workspaceID));
  if (!workspace) throw new Error('Workspace was not found');
  return workspace.id;
}
function resolveTask(db: GTDDatabase, workspaceID: string, taskID?: string | null) {
  if (taskID == null) return undefined;
  const task = db.tasks.find(t => sameID(t.id, taskID));
  if (!task) throw new Error('Task was not found');
  if (!sameID(task.workspaceID, workspaceID)) throw new Error('Task belongs to another workspace');
  // Historical actual work can legitimately refer to a now-finished task.
  return task;
}
function validRange(startedAt: string, endedAt: string): [number, number] {
  if (!isISO(startedAt) || !isISO(endedAt)) throw new Error('Actual times require ISO timestamps with a timezone');
  const start = Date.parse(startedAt), end = Date.parse(endedAt);
  if (end <= start) throw new Error('Actual end must be after start');
  return [start, end];
}
function validNow(now: Date): number {
  if (!Number.isFinite(now.getTime())) throw new Error('Invalid timestamp');
  return now.getTime();
}
/** Hard actual conflict, unlike advisory plan overlap. Paused timer gaps are
 * conservatively occupied because schema 11 stores no individual segments. */
export function hasTimeEntryConflict(db: GTDDatabase, workspaceID: string, startedAt: string, endedAt: string, excludingEntryID?: string, now = new Date()): boolean {
  const [start, end] = validRange(startedAt, endedAt), at = validNow(now);
  if (db.timeEntries.some(e => sameID(e.workspaceID, workspaceID) && !sameID(e.id, excludingEntryID) && Date.parse(e.endedAt) > start && Date.parse(e.startedAt) < end)) return true;
  const timer = db.activeTimer;
  if (!timer) return false;
  const timerWorkspace = timer.workspaceID ?? (timer.taskID ? db.tasks.find(t => sameID(t.id, timer.taskID))?.workspaceID : undefined) ?? workspaceID;
  if (!sameID(timerWorkspace, workspaceID)) return false;
  const timerStart = Date.parse(timer.sessionStartedAt), timerEnd = Math.max(timerStart, timer.pausedAt ? Date.parse(timer.pausedAt) : at);
  return timerEnd > start && timerStart < end;
}
export interface AddTimeEntryInput { workspaceID: string; taskID?: string | null; startedAt: string; endedAt: string; title?: string; note?: string }
export function addTimeEntry(db: GTDDatabase, input: AddTimeEntryInput, now = new Date()): GTDDatabase {
  const workspaceID = workspaceExists(db, input.workspaceID), task = resolveTask(db, workspaceID, input.taskID);
  const [start, end] = validRange(input.startedAt, input.endedAt);
  if (end > validNow(now)) throw new Error('Actual records cannot extend into the future');
  if (hasTimeEntryConflict(db, workspaceID, input.startedAt, input.endedAt, undefined, now)) throw new Error('Actual time overlaps another record or the active timer');
  const entry: TimeEntry = { id: crypto.randomUUID(), workspaceID, taskID: task?.id ?? null, title: input.title?.trim() || task?.title || '无任务专注',
    startedAt: input.startedAt, endedAt: input.endedAt, source: 'manual', pomodoroPhase: null, note: input.note ?? '', activeSeconds: (end - start) / 1000 };
  return checked({ ...db, timeEntries: [...db.timeEntries, entry] });
}
export type TimeEntryPatch = Partial<Pick<TimeEntry, 'taskID' | 'startedAt' | 'endedAt' | 'title' | 'note'>>;
export function updateTimeEntry(db: GTDDatabase, workspaceID: string, entryID: string, patch: TimeEntryPatch, now = new Date()): GTDDatabase {
  workspaceExists(db, workspaceID);
  const previous = db.timeEntries.find(e => sameID(e.id, entryID));
  if (!previous) throw new Error('Actual record was not found');
  if (!sameID(previous.workspaceID, workspaceID)) throw new Error('Actual record belongs to another workspace');
  for (const key of Object.keys(patch)) if (!['taskID', 'startedAt', 'endedAt', 'title', 'note'].includes(key)) throw new Error('Only the actual record task, title, note, and time range can be edited');
  const next: TimeEntry = { ...previous, ...patch };
  const task = resolveTask(db, workspaceID, next.taskID);
  if ('taskID' in patch) {
    next.taskID = task?.id ?? null;
    if (!('title' in patch)) next.title = task?.title ?? '无任务专注';
  }
  const [start, end] = validRange(next.startedAt, next.endedAt);
  const rangeChanged = start !== Date.parse(previous.startedAt) || end !== Date.parse(previous.endedAt);
  // Equivalent instants are not a range edit. Retain offset/fractional source
  // strings so a form reformat cannot silently rewrite imported timestamps.
  if (start === Date.parse(previous.startedAt)) next.startedAt = previous.startedAt;
  if (end === Date.parse(previous.endedAt)) next.endedAt = previous.endedAt;
  if (rangeChanged && end > validNow(now)) throw new Error('Actual records cannot extend into the future');
  if (hasTimeEntryConflict(db, workspaceID, next.startedAt, next.endedAt, previous.id, now)) throw new Error('Actual time overlaps another record or the active timer');
  next.activeSeconds = rangeChanged ? (end - start) / 1000 : previous.activeSeconds;
  if (Object.keys(next).every(key => next[key] === previous[key])) return db;
  return checked({ ...db, timeEntries: db.timeEntries.map(e => sameID(e.id, previous.id) ? next : e) });
}
export function deleteTimeEntry(db: GTDDatabase, workspaceID: string, entryID: string): GTDDatabase {
  workspaceExists(db, workspaceID);
  const previous = db.timeEntries.find(e => sameID(e.id, entryID));
  if (!previous) return db;
  if (!sameID(previous.workspaceID, workspaceID)) throw new Error('Actual record belongs to another workspace');
  return checked({ ...db, timeEntries: db.timeEntries.filter(e => !sameID(e.id, previous.id)) });
}
