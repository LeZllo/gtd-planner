import type { GTDDatabase, GTDTask, TimeEntry } from './types.js';
import { canScheduleTaskOnDay, dateDay, dayBounds, dayKey, deadlineInstant, isMultiDayPlan, isTaskCompletedOnDay, isISO, localDate, supportsDailyRecurrence, taskPlanIntersectsDay, wallClockTime } from './dates.js';
import { completeTask, tasksForDay, updateTask } from './operations.js';
import { actualFocusForDay, clipTimeEntryToDay } from './timeEntries.js';
import { effectiveTaskPlan, isConcretePlan, needsReschedule, resolveTaskArrangements } from './scheduling.js';
import { removeTaskArrangement, saveTaskArrangement } from './scheduleCommands.js';
import { idKey, sameID } from './validation.js';

export interface TodayPlanBlock {
  id: string; taskID: string; title: string; source: 'taskPlan' | 'executionSlot'; slotID?: string;
  start: string; end: string; plannedDuration: number; isPoint: boolean;
}
export interface TodayActualBlock { id: string; entry: TimeEntry; start: string; end: string; actualDuration: number; estimated: boolean }
export interface TodayScheduleSnapshot {
  day: string; dayStart: string; dayEnd: string; tasks: GTDTask[]; completedTasks: GTDTask[];
  drawerTasks: GTDTask[]; rescheduleTasks: GTDTask[]; crossDayProgressTasks: GTDTask[]; completeWithinTasks: GTDTask[];
  overdueTasks: GTDTask[]; deadlineTasks: GTDTask[]; planBlocks: TodayPlanBlock[];
  actualEntries: TimeEntry[]; actualBlocks: TodayActualBlock[]; totalCount: number; completedCount: number;
  remainingCount: number; waitingCount: number; overdueCount: number; plannedDuration: number;
  actualDuration: number; actualEstimated: boolean;
}
const iso = (time: number) => new Date(time).toISOString();
export function planBlocksForDay(task: GTDTask, day: string): TodayPlanBlock[] {
  const [dayStart, dayEnd] = dayBounds(day), blocks: TodayPlanBlock[] = [];
  for (const item of resolveTaskArrangements(task, day)) {
    const plan = item.plan;
    if (item.source === 'taskPlan' && !isConcretePlan(plan)) continue;
    if (!taskPlanIntersectsDay(plan, day)) continue;
    const start = Math.max(localDate(plan.plannedStart!).getTime(), dayStart);
    const explicitEnd = plan.plannedEnd ? Math.min(localDate(plan.plannedEnd).getTime(), dayEnd) : null;
    const isPoint = explicitEnd === null || explicitEnd === start;
    const end = isPoint ? Math.min(start + 1800_000, dayEnd) : explicitEnd!;
    blocks.push({ id: item.id, source: item.source, slotID: item.slotID, taskID: task.id, title: task.title, start: iso(start), end: iso(end), plannedDuration: isPoint ? 0 : Math.max(0, (end - start) / 1000), isPoint });
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
  const rescheduleTasks = unfinished.filter(t => needsReschedule(t, day, now));
  const rescheduleIDs = new Set(rescheduleTasks.map(t => idKey(t.id)));
  const drawerTasks = unfinished.filter(t => !scheduled.has(idKey(t.id)) || rescheduleIDs.has(idKey(t.id)));
  const crossDayProgressTasks = unfinished.filter(t => isMultiDayPlan(effectiveTaskPlan(t, day)) && effectiveTaskPlan(t, day).planRangeIntent === 'progress' && taskPlanIntersectsDay(effectiveTaskPlan(t, day), day));
  const completeWithinTasks = unfinished.filter(t => isMultiDayPlan(effectiveTaskPlan(t, day)) && effectiveTaskPlan(t, day).planRangeIntent === 'complete-within' && taskPlanIntersectsDay(effectiveTaskPlan(t, day), day));
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
  return { day, dayStart: iso(start), dayEnd: iso(end), tasks, completedTasks, drawerTasks, rescheduleTasks, crossDayProgressTasks, completeWithinTasks, overdueTasks, deadlineTasks,
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
  if (!isISO(input.start) || !isISO(input.end)) throw new Error('Execution times require ISO timestamps with a timezone');
  if (Date.parse(input.end) <= Date.parse(input.start)) throw new Error('Execution end must be after start');
  return saveTaskArrangement(db, { ...input, day: dateDay(input.start), ref: 'additional', plan: { plannedStart: input.start, plannedEnd: input.end, plannedPrecision: 'minute', planRangeIntent: 'progress' } }, now);
}
export function removeExecutionSlot(db: GTDDatabase, workspaceID: string, taskID: string, slotID: string): GTDDatabase {
  const task = workspaceTask(db, workspaceID, taskID), slot = task.executionSlots.find(s => sameID(s.id, slotID));
  if (!slot) return db;
  const day = dateDay(slot.start), alias = resolveTaskArrangements(task, day).find(item => item.linkedSlotIDs.some(id => sameID(id, slotID)));
  return removeTaskArrangement(db, { workspaceID, taskID, day, ref: alias ? { source: 'taskPlan' } : { source: 'executionSlot', slotID }, scope: supportsDailyRecurrence(task) ? 'occurrence' : undefined });
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
