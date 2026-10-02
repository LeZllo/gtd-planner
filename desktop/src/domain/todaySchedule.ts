import type { GTDDatabase, GTDTask, TimeEntry } from './types.js';
import { canScheduleTaskOnDay, dateDay, dayBounds, dayKey, deadlineInstant, isMultiDayPlan, isTaskCompletedOnDay, isISO, localDate, supportsDailyRecurrence, taskPlanIntersectsDay, wallClockTime } from './dates.js';
import { completeTask, tasksForDay, updateTask } from './operations.js';
import { actualFocusForDay, clipTimeEntryToDay } from './timeEntries.js';
import { idKey, sameID } from './validation.js';

export interface TodayPlanBlock {
  id: string; taskID: string; title: string; source: 'taskPlan' | 'executionSlot'; slotID?: string;
  start: string; end: string; plannedDuration: number; isPoint: boolean;
}
export interface TodayActualBlock { id: string; entry: TimeEntry; start: string; end: string; actualDuration: number; estimated: boolean }
export interface TodayScheduleSnapshot {
  day: string; dayStart: string; dayEnd: string; tasks: GTDTask[]; completedTasks: GTDTask[];
  drawerTasks: GTDTask[]; crossDayProgressTasks: GTDTask[]; completeWithinTasks: GTDTask[];
  overdueTasks: GTDTask[]; deadlineTasks: GTDTask[]; planBlocks: TodayPlanBlock[];
  actualEntries: TimeEntry[]; actualBlocks: TodayActualBlock[]; totalCount: number; completedCount: number;
  remainingCount: number; waitingCount: number; overdueCount: number; plannedDuration: number;
  actualDuration: number; actualEstimated: boolean;
}
const iso = (time: number) => new Date(time).toISOString();
function shiftedTemplate(task: GTDTask, day: string): GTDTask {
  if (task.plannedPrecision !== 'minute' || !supportsDailyRecurrence(task) || isMultiDayPlan(task) || !task.plannedStart) return task;
  const anchor = localDate(task.plannedStart), originalDay = dateDay(task.plannedStart);
  if (day < originalDay) return task;
  // Calendar-day arithmetic, not fixed 24-hour additions, preserves clock time.
  const ordinal = (key: string) => { const d = localDate(key); const utc = new Date(0); utc.setUTCFullYear(d.getFullYear(), d.getMonth(), d.getDate()); utc.setUTCHours(0, 0, 0, 0); return utc.getTime() / 86_400_000; };
  const offset = ordinal(day) - ordinal(originalDay);
  const shift = (value: string) => { const source = localDate(value), target = localDate(dateDay(value)); target.setDate(target.getDate() + offset); return wallClockTime(dayKey(target), source.getHours() * 60 + source.getMinutes() + source.getSeconds() / 60 + source.getMilliseconds() / 60_000).getTime(); };
  const start = shift(task.plannedStart); let end = task.plannedEnd ? shift(task.plannedEnd) : null;
  if (end !== null && end <= start && task.plannedEnd && localDate(task.plannedEnd).getTime() > anchor.getTime()) end = start + localDate(task.plannedEnd).getTime() - anchor.getTime();
  return { ...task, plannedStart: iso(start), plannedEnd: end === null ? null : iso(end) };
}
export function planBlocksForDay(task: GTDTask, day: string): TodayPlanBlock[] {
  const [dayStart, dayEnd] = dayBounds(day), blocks: TodayPlanBlock[] = [];
  for (const slot of task.executionSlots) {
    const start = Math.max(Date.parse(slot.start), dayStart), end = Math.min(Date.parse(slot.end), dayEnd);
    if (end > start) blocks.push({ id: `${task.id}:slot:${slot.id}`, source: 'executionSlot', slotID: slot.id, taskID: task.id, title: task.title, start: iso(start), end: iso(end), plannedDuration: (end - start) / 1000, isPoint: false });
  }
  const displayed = shiftedTemplate(task, day);
  if (displayed.plannedPrecision === 'minute' && !isMultiDayPlan(displayed) && displayed.plannedStart && taskPlanIntersectsDay(displayed, day)) {
    const start = Math.max(localDate(displayed.plannedStart).getTime(), dayStart);
    const explicitEnd = displayed.plannedEnd ? Math.min(localDate(displayed.plannedEnd).getTime(), dayEnd) : null;
    const isPoint = explicitEnd === null || explicitEnd === start;
    const end = isPoint ? Math.min(start + 1800_000, dayEnd) : explicitEnd!;
    blocks.push({ id: `${task.id}:plan`, source: 'taskPlan', taskID: task.id, title: task.title, start: iso(start), end: iso(end), plannedDuration: isPoint ? 0 : Math.max(0, (end - start) / 1000), isPoint });
  }
  return blocks;
}
/** A pure, framework-free snapshot. Call on data/day/deadline changes, not on
 * every timer tick or pointer sample. Actual totals share the report helper. */
export function todayScheduleSnapshot(db: GTDDatabase, workspaceID: string, day: string, now = new Date()): TodayScheduleSnapshot {
  const [start, end] = dayBounds(day), overdue = (task: GTDTask) => { const deadline = deadlineInstant(task); return deadline !== null && deadline < now.getTime(); };
  const tasks = tasksForDay(db, workspaceID, day, now).sort((a, b) => Number(isTaskCompletedOnDay(a, day)) - Number(isTaskCompletedOnDay(b, day)) || Number(overdue(b)) - Number(overdue(a)));
  const completedTasks = tasks.filter(t => isTaskCompletedOnDay(t, day));
  const unfinished = tasks.filter(t => !isTaskCompletedOnDay(t, day) && t.status !== 'done' && t.status !== 'cancelled');
  const planBlocks = tasks.flatMap(task => planBlocksForDay(task, day)).sort((a, b) => Date.parse(a.start) - Date.parse(b.start) || a.title.localeCompare(b.title));
  const scheduled = new Set(planBlocks.map(b => idKey(b.taskID)));
  const drawerTasks = unfinished.filter(t => !scheduled.has(idKey(t.id)));
  const crossDayProgressTasks = unfinished.filter(t => isMultiDayPlan(t) && t.planRangeIntent === 'progress' && taskPlanIntersectsDay(t, day));
  const completeWithinTasks = unfinished.filter(t => isMultiDayPlan(t) && t.planRangeIntent === 'complete-within' && taskPlanIntersectsDay(t, day));
  const overdueTasks = unfinished.filter(overdue);
  const deadlineTasks = unfinished.filter(t => !!t.deadline && dateDay(t.deadline) === day);
  const actualBlocks: TodayActualBlock[] = [];
  for (const entry of db.timeEntries) {
    if (!sameID(entry.workspaceID, workspaceID)) continue;
    const clipped = clipTimeEntryToDay(entry, day);
    if (clipped) actualBlocks.push({ id: entry.id, entry, start: clipped.start, end: clipped.end, actualDuration: clipped.seconds, estimated: clipped.estimated });
  }
  actualBlocks.sort((a, b) => Date.parse(a.start) - Date.parse(b.start));
  const focus = actualFocusForDay(db.timeEntries, workspaceID, day);
  return { day, dayStart: iso(start), dayEnd: iso(end), tasks, completedTasks, drawerTasks, crossDayProgressTasks, completeWithinTasks, overdueTasks, deadlineTasks,
    planBlocks, actualEntries: actualBlocks.map(b => b.entry), actualBlocks, totalCount: tasks.length, completedCount: completedTasks.length,
    remainingCount: tasks.length - completedTasks.length, waitingCount: drawerTasks.length, overdueCount: overdueTasks.length,
    plannedDuration: planBlocks.reduce((total, b) => total + b.plannedDuration, 0), actualDuration: focus.seconds, actualEstimated: focus.estimated };
}
export interface ScheduleSelection { start: string; end: string; startMinute: number; endMinute: number }
export function makeScheduleSelection(day: string, startMinute: number, endMinute: number, fineSnap = false): ScheduleSelection {
  if (!Number.isFinite(startMinute) || !Number.isFinite(endMinute)) throw new Error('Selection requires finite clock minutes');
  const step = fineSnap ? 5 : 15, snap = (m: number) => Math.min(1440, Math.max(0, Math.round(m / step) * step));
  let lower = Math.min(snap(startMinute), snap(endMinute)), upper = Math.max(snap(startMinute), snap(endMinute));
  if (lower === upper) { if (upper + step <= 1440) upper += step; else lower = Math.max(0, lower - step); }
  const [dayStart, dayEnd] = dayBounds(day);
  let start = wallClockTime(day, lower).getTime(), end = wallClockTime(day, upper).getTime();
  if (end <= start) {
    end = Math.min(dayEnd, start + Math.max(step, upper - lower) * 60_000);
    if (end <= start) { end = dayEnd; start = Math.max(dayStart, dayEnd - step * 60_000); }
  }
  return { start: iso(start), end: iso(end), startMinute: lower, endMinute: upper };
}
export function planConflicts(selection: Pick<ScheduleSelection, 'start' | 'end'>, blocks: readonly TodayPlanBlock[]): boolean {
  const start = Date.parse(selection.start), end = Date.parse(selection.end);
  return blocks.some(block => block.isPoint ? Date.parse(block.start) >= start && Date.parse(block.start) < end : Date.parse(block.end) > start && Date.parse(block.start) < end);
}
function workspaceTask(db: GTDDatabase, workspaceID: string, taskID: string): GTDTask {
  if (!db.workspaces.some(w => sameID(w.id, workspaceID))) throw new Error('Workspace was not found');
  const task = db.tasks.find(t => sameID(t.id, taskID));
  if (!task) throw new Error('Task was not found');
  if (!sameID(task.workspaceID, workspaceID)) throw new Error('Task belongs to another workspace');
  return task;
}
export interface AddExecutionSlotInput { workspaceID: string; taskID: string; start: string; end: string }
export function addExecutionSlot(db: GTDDatabase, input: AddExecutionSlotInput, now = new Date()): GTDDatabase {
  const task = workspaceTask(db, input.workspaceID, input.taskID), start = Date.parse(input.start), end = Date.parse(input.end);
  if (!isISO(input.start) || !isISO(input.end)) throw new Error('Execution times require ISO timestamps with a timezone');
  if (end <= start) throw new Error('Execution end must be after start');
  if (task.status === 'done' || task.status === 'cancelled') throw new Error('Finished tasks cannot be scheduled');
  // Every occupied local day must be schedulable; an exclusive midnight end
  // does not accidentally validate (or reject) the next daily occurrence.
  if (supportsDailyRecurrence(task)) {
    let cursor = dayBounds(dayKey(new Date(start)))[0];
    while (cursor < end) {
      const key = dayKey(new Date(cursor));
      if (!canScheduleTaskOnDay(task, key)) throw new Error('This daily occurrence is completed, skipped, or before the recurrence starts');
      const next = dayBounds(key)[1]; if (next <= cursor) throw new Error('Unable to advance the local day'); cursor = next;
    }
  }
  if (task.executionSlots.some(s => Date.parse(s.start) === start && Date.parse(s.end) === end)) return db;
  const executionSlots = [...task.executionSlots, { id: crypto.randomUUID(), start: input.start, end: input.end }].sort((a, b) => Date.parse(a.start) - Date.parse(b.start));
  return updateTask(db, task.id, { executionSlots }, now);
}
export function removeExecutionSlot(db: GTDDatabase, workspaceID: string, taskID: string, slotID: string): GTDDatabase {
  const task = workspaceTask(db, workspaceID, taskID), executionSlots = task.executionSlots.filter(s => !sameID(s.id, slotID));
  return executionSlots.length === task.executionSlots.length ? db : updateTask(db, task.id, { executionSlots });
}
/** Explicit desired state is retry-safe, unlike a blind toggle. Historical
 * nonrecurring changes and all future completion remain disallowed. */
export function setTaskCompletionForDay(db: GTDDatabase, workspaceID: string, taskID: string, day: string, completed: boolean, now = new Date()): GTDDatabase {
  dayBounds(day); const task = workspaceTask(db, workspaceID, taskID), today = dayKey(now);
  if (day > today) throw new Error('Only today or a past daily occurrence can be completed');
  if (task.status === 'cancelled') throw new Error('Reopen this cancelled task before changing completion');
  const daily = supportsDailyRecurrence(task);
  if (!daily && task.recurrence.trim()) throw new Error('Completing this recurrence is not supported. Its rule has been preserved.');
  if (!daily && day !== today) throw new Error('Historical nonrecurring tasks cannot be backdated');
  if (daily && task.skippedInstances.includes(day)) throw new Error('This occurrence was skipped');
  if (daily && !task.completedInstances.includes(day) && task.plannedStart && day < dateDay(task.plannedStart)) throw new Error('This occurrence is before the recurrence starts');
  // Re-resolve day membership at commit time. A retained row may have lost
  // its plan/slot, moved to another day, or crossed local midnight. A done
  // ordinary task belongs only to its completion date, even if its old plan
  // still points at today. Never fall back to a general task action here.
  if (!tasksForDay(db, workspaceID, day, now).some(t => sameID(t.id, taskID))) throw new Error('This task no longer belongs to the selected day');
  if (!daily) {
    if (completed) return completeTask(db, taskID, day, now);
    return task.status === 'done' ? updateTask(db, taskID, { status: 'open' }, now) : db;
  }
  if (completed) return completeTask(db, taskID, day, now);
  if (!task.completedInstances.includes(day)) return db;
  return updateTask(db, taskID, { completedInstances: task.completedInstances.filter(d => d !== day) }, now);
}
